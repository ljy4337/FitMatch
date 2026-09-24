import Combine
import Foundation
import SwiftData
import SwiftUI

protocol FitMatchComparisonRemoteServicing: Sendable {
    func fetchVNextComparisonHistory() async throws -> [VNextComparisonHistoryDTO]
    func fetchVNextComparisonHistorySync() async throws -> VNextComparisonHistorySyncDTO
    func hideVNextComparisonHistories(clientComparisonIDs: [UUID]) async throws
        -> VNextComparisonHistoryVisibilityDTO
    func completeVNextComparison(
        comparisonID: UUID,
        payload: VNextComparisonCompletionPayload
    ) async throws -> VNextCompleteComparisonDTO
}

extension FitMatchComparisonRemoteServicing {
    /// Compatibility for existing remote test doubles and deployed servers
    /// before the additive tombstone RPC is applied.  This path deliberately
    /// returns no tombstones; absence from an active-list response never
    /// authorizes a local deletion.
    func fetchVNextComparisonHistorySync() async throws -> VNextComparisonHistorySyncDTO {
        VNextComparisonHistorySyncDTO(
            histories: try await fetchVNextComparisonHistory(),
            tombstones: []
        )
    }
}

extension FitMatchSupabaseDomainClient: FitMatchComparisonRemoteServicing {}

enum FitMatchComparisonSyncState: Equatable {
    case idle
    case syncing
    case synced
    case pendingRetry
    case parityWarning
}

/// Synchronizes the local/offline history cache from vNext authority.
///
/// It deliberately has no resolve/authorize/begin path for a local history.
/// A comparison can enter this coordinator only after the server has already
/// created its immutable begin snapshot. PENDING rows are replayed from that
/// snapshot and COMPLETED rows hydrate the presentation cache.
@MainActor
final class FitMatchComparisonSyncCoordinator: ObservableObject {
    @Published private(set) var state: FitMatchComparisonSyncState = .idle
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var parityWarningCount = 0
    @Published private(set) var missingLocalCompletedCount = 0

    private let remote: any FitMatchComparisonRemoteServicing
    private let defaults: UserDefaults
    private let adapter = VNextComparisonEngineAdapter()
    private let hydrator = VNextHistoryCacheHydrator()
    private var isSynchronizing = false
    private var needsAnotherPass = false
    private var activeUserID: UUID?
    private var pendingRequest: SynchronizationRequest?

    private static let processedPrefix = "FitMatch.comparisonProcessed.v2."
    private static let tombstonePrefix = "FitMatch.comparisonTombstones.v1."

    private struct SynchronizationRequest {
        let userID: UUID
        let histories: [RecommendationHistory]
        let products: [Product]
        let closetItems: [UserFit]
        let modelContext: ModelContext?
    }

    init(
        remote: (any FitMatchComparisonRemoteServicing)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.remote = remote ?? FitMatchSupabaseDomainClient.shared
        self.defaults = defaults
    }

    /// Claims the comparison cache for the authenticated session before the
    /// root presents user-owned data. This also invalidates an outgoing
    /// account's in-flight response, so a late A response cannot hydrate B's
    /// newly prepared cache.
    func prepareForAuthenticatedUser(_ userID: UUID?) {
        guard activeUserID != userID else { return }
        activeUserID = userID
        pendingRequest = nil
        needsAnotherPass = false
        if userID == nil {
            state = .idle
            lastErrorMessage = nil
            parityWarningCount = 0
            missingLocalCompletedCount = 0
        }
    }

    func synchronize(
        userID: UUID,
        histories: [RecommendationHistory],
        products: [Product] = [],
        closetItems: [UserFit] = [],
        modelContext: ModelContext? = nil
    ) async {
        guard !Task.isCancelled else { return }
        let request = SynchronizationRequest(
            userID: userID,
            histories: histories,
            products: products,
            closetItems: closetItems,
            modelContext: modelContext
        )
        prepareForAuthenticatedUser(userID)
        if isSynchronizing {
            needsAnotherPass = true
            pendingRequest = request
            return
        }

        isSynchronizing = true
        defer { isSynchronizing = false }

        var pass = request
        while true {
            needsAnotherPass = false
            pendingRequest = nil
            await synchronizeOnce(
                userID: pass.userID,
                histories: pass.histories,
                products: pass.products,
                closetItems: pass.closetItems,
                modelContext: pass.modelContext
            )

            // A session change must use that session's current local snapshot
            // on its next pass. Reusing A's history/product arrays after B is
            // active can rehydrate outgoing immutable comparisons into B's
            // cache.
            if let pendingRequest {
                pass = pendingRequest
                continue
            }
            guard activeUserID == pass.userID else { return }
            if needsAnotherPass {
                continue
            }
            break
        }
    }

    /// Persists a user-owned, immutable-comparison visibility choice before a
    /// vNext history leaves the local presentation cache. The server resolves
    /// each client ID to an owned completed comparison; a local UUID alone
    /// never grants authority to hide arbitrary evidence.
    func hideVNextComparisonHistories(
        clientComparisonIDs: [UUID]
    ) async throws {
        let requestedIDs = Array(Set(clientComparisonIDs)).sorted {
            $0.uuidString < $1.uuidString
        }
        guard !requestedIDs.isEmpty else { return }

        // Legacy callers can perform a durable hide before their first cache
        // sync. When a cache owner is known, retain the generation check so a
        // late receipt cannot affect a newly authenticated account.
        let userID = activeUserID
        let receipt = try await remote.hideVNextComparisonHistories(
            clientComparisonIDs: requestedIDs
        )
        if let userID {
            guard isCurrentSyncUser(userID) else {
                throw FitMatchHistoryVisibilityRPCError.authenticationRequired
            }
        }
        guard receipt.hidden,
              Set(receipt.clientComparisonIDs) == Set(requestedIDs),
              receipt.clientComparisonIDs.count == requestedIDs.count else {
            throw FitMatchSupabaseProductResolverError.invalidVNextResponse
        }
    }

    /// Called only after the caller has successfully persisted the local
    /// presentation removal.  Keeping this separate from the server hide
    /// prevents an uncertain local save from consuming a tombstone cursor.
    func recordPersistedHistoryTombstones(_ clientComparisonIDs: [UUID]) {
        guard let userID = activeUserID else { return }
        let ids = Set(clientComparisonIDs)
        guard !ids.isEmpty else { return }
        var known = tombstoneHistoryIDs(for: userID)
        known.formUnion(ids)
        storeTombstoneHistoryIDs(known, for: userID)
        var processed = processedHistoryIDs(for: userID)
        processed.subtract(ids)
        storeProcessedHistoryIDs(processed, for: userID)
        needsAnotherPass = true
    }

    /// Clears only the local idempotency cache for an account which has just
    /// been deleted. Immutable remote comparisons are never touched here.
    func purgeProcessedHistoryIDs(for userID: UUID) {
        defaults.removeObject(forKey: Self.processedPrefix + userID.uuidString)
        defaults.removeObject(forKey: Self.tombstonePrefix + userID.uuidString)
        if activeUserID == userID {
            activeUserID = nil
            pendingRequest = nil
        }
        needsAnotherPass = false
        state = .idle
        lastErrorMessage = nil
        parityWarningCount = 0
        missingLocalCompletedCount = 0
    }

    private func synchronizeOnce(
        userID: UUID,
        histories: [RecommendationHistory],
        products: [Product],
        closetItems: [UserFit],
        modelContext: ModelContext?
    ) async {
        guard isCurrentSyncUser(userID) else { return }
        state = .syncing
        lastErrorMessage = nil
        parityWarningCount = 0
        missingLocalCompletedCount = 0

        do {
            var response = try await remote.fetchVNextComparisonHistorySync()
            guard isCurrentSyncUser(userID) else { return }
            var rows = response.histories
            var tombstoneIDs = tombstoneHistoryIDs(for: userID)
            tombstoneIDs.formUnion(response.tombstones.map(\.clientComparisonID))
            try persistServerTombstones(
                response.tombstones,
                knownIDs: tombstoneIDs,
                userID: userID,
                modelContext: modelContext
            )
            guard isCurrentSyncUser(userID) else { return }
            var hasRetryableFailure = false
            var recoveredPending = false

            var hasSupportedPending = false
            for row in rows where row.resultStatus == "PENDING" {
                guard isCurrentSyncUser(userID) else { return }
                do {
                    try FitMatchVNextContractValidator.validatePendingReplay(row)
                } catch {
                    parityWarningCount += 1
                    lastErrorMessage = lastErrorMessage
                        ?? "지원하지 않는 서버 비교 기록은 자동으로 완료하지 않았습니다."
                    continue
                }
                guard let begin = row.pendingBegin else {
                    parityWarningCount += 1
                    lastErrorMessage = lastErrorMessage
                        ?? "서버 비교 기록의 시작 스냅샷이 불완전합니다."
                    continue
                }
                hasSupportedPending = true
                do {
                    guard isCurrentSyncUser(userID) else { return }
                    let analysis = try adapter.analyze(begin)
                    guard isCurrentSyncUser(userID) else { return }
                    let completed = try await remote.completeVNextComparison(
                        comparisonID: row.id,
                        payload: analysis.completionPayload
                    )
                    guard isCurrentSyncUser(userID) else { return }
                    guard completed.completed,
                          completed.comparisonID == row.id,
                          completed.recommendedProductSizeID
                            == analysis.recommended.productSizeID else {
                        throw FitMatchSupabaseProductResolverError.invalidVNextResponse
                    }
                    recoveredPending = true
                } catch is FitMatchVNextContractError {
                    parityWarningCount += 1
                    lastErrorMessage = lastErrorMessage
                        ?? "지원하지 않는 서버 비교 기록은 자동으로 완료하지 않았습니다."
                } catch {
                    guard isCurrentSyncUser(userID) else { return }
                    hasRetryableFailure = true
                    lastErrorMessage = lastErrorMessage
                        ?? synchronizationErrorMessage(for: error)
                    #if DEBUG
                    print(
                        "[FitMatchComparisonSync] pending=\(row.id) recovery failed: "
                            + error.localizedDescription
                    )
                    #endif
                }
            }

            // Re-read after recovery. A PENDING row is never treated as a
            // completed history merely because the completion call returned.
            if recoveredPending {
                response = try await remote.fetchVNextComparisonHistorySync()
                guard isCurrentSyncUser(userID) else { return }
                rows = response.histories
                tombstoneIDs.formUnion(response.tombstones.map(\.clientComparisonID))
                try persistServerTombstones(
                    response.tombstones,
                    knownIDs: tombstoneIDs,
                    userID: userID,
                    modelContext: modelContext
                )
                guard isCurrentSyncUser(userID) else { return }
            }

            var completedRows: [VNextComparisonHistoryDTO] = []
            for row in rows where row.resultStatus == "COMPLETED"
                && !tombstoneIDs.contains(row.clientComparisonID) {
                do {
                    try FitMatchVNextContractValidator.validateCompletedReplay(row)
                    guard row.snapshotBegin != nil else {
                        throw FitMatchVNextContractError.missingRequiredField(
                            "comparison_history.begin_snapshot"
                        )
                    }
                    completedRows.append(row)
                } catch {
                    parityWarningCount += 1
                    lastErrorMessage = lastErrorMessage
                        ?? "지원하지 않는 서버 비교 기록은 이 기기에 복원하지 않았습니다."
                }
            }
            let unsupportedStatusCount = rows.filter {
                $0.resultStatus != "PENDING" && $0.resultStatus != "COMPLETED"
            }.count
            if unsupportedStatusCount > 0 {
                parityWarningCount += unsupportedStatusCount
                lastErrorMessage = lastErrorMessage
                    ?? "지원하지 않는 서버 비교 상태를 건너뛰었습니다."
            }
            let completedClientIDs = Set(completedRows.map(\.clientComparisonID))
            var processed = processedHistoryIDs(for: userID)
            // Tombstones are applied even if the same identifier was marked
            // processed in a prior session.  Their presence is never inferred
            // from a missing active-history row.
            processed.subtract(tombstoneIDs)
            let visibleHistories = histories.filter { !tombstoneIDs.contains($0.id) }
            let localIDs = Set(visibleHistories.map(\.id))

            if let modelContext {
                do {
                    guard isCurrentSyncUser(userID) else { return }
                    let hydrated = try hydrator.hydrateCompleted(
                        completedRows,
                        existingHistories: visibleHistories,
                        existingProducts: products,
                        existingClosetItems: closetItems,
                        modelContext: modelContext
                    )
                    guard isCurrentSyncUser(userID) else { return }
                    processed.formUnion(hydrated)
                } catch is FitMatchVNextContractError,
                        is VNextHistoryCacheHydrationError {
                    // A malformed or unsupported immutable record will not
                    // become valid after a network retry. Keep existing local
                    // history intact and surface the parity issue instead.
                    parityWarningCount += 1
                    lastErrorMessage = lastErrorMessage
                        ?? "지원하지 않는 서버 비교 기록은 이 기기에 복원하지 않았습니다."
                } catch {
                    guard isCurrentSyncUser(userID) else { return }
                    hasRetryableFailure = true
                    lastErrorMessage = lastErrorMessage
                        ?? synchronizationErrorMessage(for: error)
                }
            } else {
                missingLocalCompletedCount = completedClientIDs.subtracting(localIDs).count
                parityWarningCount += missingLocalCompletedCount
            }

            for history in visibleHistories where !processed.contains(history.id) {
                guard isCurrentSyncUser(userID) else { return }
                if completedClientIDs.contains(history.id) {
                    processed.insert(history.id)
                } else if history.comparisonMethod.hasPrefix("서버 승인") {
                    // A locally cached vNext result without its immutable
                    // server completion is not silently uploaded or trusted.
                    parityWarningCount += 1
                } else {
                    // Legacy histories remain readable offline but are never
                    // promoted into the vNext business authority pipeline.
                    processed.insert(history.id)
                }
            }

            hasSupportedPending = rows.contains { row in
                guard row.resultStatus == "PENDING" else { return false }
                return (try? FitMatchVNextContractValidator.validatePendingReplay(row)) != nil
            }
            if hasSupportedPending {
                hasRetryableFailure = true
                if lastErrorMessage == nil {
                    lastErrorMessage = "완료되지 않은 서버 비교를 다음 동기화에서 다시 복구합니다."
                }
            }
            guard isCurrentSyncUser(userID) else { return }
            storeProcessedHistoryIDs(processed, for: userID)

            if hasRetryableFailure {
                state = .pendingRetry
            } else if parityWarningCount > 0 {
                state = .parityWarning
                if lastErrorMessage == nil {
                    lastErrorMessage = "서버 immutable history와 로컬 캐시가 일치하지 않습니다."
                }
            } else {
                state = .synced
            }
        } catch {
            guard isCurrentSyncUser(userID) else { return }
            state = .pendingRetry
            lastErrorMessage = synchronizationErrorMessage(for: error)
            #if DEBUG
            print("[FitMatchComparisonSync] sync failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func synchronizationErrorMessage(for error: Error) -> String {
        if error is URLError {
            return FitMatchFailureCopy.transientNetwork
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return FitMatchFailureCopy.transientNetwork
        }
        return FitMatchFailureCopy.serviceInspection
    }

    private func isCurrentSyncUser(_ userID: UUID) -> Bool {
        activeUserID == userID && !Task.isCancelled
    }

    private func processedHistoryIDs(for userID: UUID) -> Set<UUID> {
        Set(
            (defaults.stringArray(forKey: Self.processedPrefix + userID.uuidString) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }

    private func tombstoneHistoryIDs(for userID: UUID) -> Set<UUID> {
        Set(
            (defaults.stringArray(forKey: Self.tombstonePrefix + userID.uuidString) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }

    private func storeTombstoneHistoryIDs(_ ids: Set<UUID>, for userID: UUID) {
        defaults.set(
            ids.map(\.uuidString).sorted(),
            forKey: Self.tombstonePrefix + userID.uuidString
        )
    }

    /// Deletes only exact server-backed History cache rows. The caller owns
    /// the active account; Product, Closet, and legacy History projections
    /// are intentionally untouched. Server tombstones become durable locally
    /// only after this SwiftData save succeeds.
    private func persistServerTombstones(
        _ tombstones: [VNextComparisonHistoryTombstoneDTO],
        knownIDs: Set<UUID>,
        userID: UUID,
        modelContext: ModelContext?
    ) throws {
        guard !tombstones.isEmpty else { return }
        guard let modelContext else { return }
        let serverIDs = Set(tombstones.map(\.clientComparisonID))
        guard serverIDs.isSubset(of: knownIDs) else {
            throw FitMatchSupabaseProductResolverError.invalidVNextResponse
        }
        let matching = try modelContext.fetch(FetchDescriptor<RecommendationHistory>())
            .filter { serverIDs.contains($0.id) && $0.isServerBackedVNextHistory }
        matching.forEach(modelContext.delete)
        try modelContext.save()
        var stored = tombstoneHistoryIDs(for: userID)
        stored.formUnion(serverIDs)
        storeTombstoneHistoryIDs(stored, for: userID)
    }

    private func storeProcessedHistoryIDs(_ ids: Set<UUID>, for userID: UUID) {
        defaults.set(
            ids.map(\.uuidString).sorted(),
            forKey: Self.processedPrefix + userID.uuidString
        )
    }
}

private struct FitMatchComparisonSyncCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: FitMatchComparisonSyncCoordinator? = nil
}

extension EnvironmentValues {
    var fitMatchComparisonSyncCoordinator: FitMatchComparisonSyncCoordinator? {
        get { self[FitMatchComparisonSyncCoordinatorEnvironmentKey.self] }
        set { self[FitMatchComparisonSyncCoordinatorEnvironmentKey.self] = newValue }
    }
}
