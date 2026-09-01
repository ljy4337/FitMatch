import Combine
import Foundation
import SwiftData
import SwiftUI

protocol FitMatchComparisonRemoteServicing: Sendable {
    func fetchVNextComparisonHistory() async throws -> [VNextComparisonHistoryDTO]
    func hideVNextComparisonHistories(clientComparisonIDs: [UUID]) async throws
        -> VNextComparisonHistoryVisibilityDTO
    func completeVNextComparison(
        comparisonID: UUID,
        payload: VNextComparisonCompletionPayload
    ) async throws -> VNextCompleteComparisonDTO
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

        let receipt = try await remote.hideVNextComparisonHistories(
            clientComparisonIDs: requestedIDs
        )
        guard receipt.hidden,
              Set(receipt.clientComparisonIDs) == Set(requestedIDs),
              receipt.clientComparisonIDs.count == requestedIDs.count else {
            throw FitMatchSupabaseProductResolverError.invalidVNextResponse
        }
    }

    /// Clears only the local idempotency cache for an account which has just
    /// been deleted. Immutable remote comparisons are never touched here.
    func purgeProcessedHistoryIDs(for userID: UUID) {
        defaults.removeObject(forKey: Self.processedPrefix + userID.uuidString)
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
            var rows = try await remote.fetchVNextComparisonHistory()
            guard isCurrentSyncUser(userID) else { return }
            var hasRetryableFailure = false
            var recoveredPending = false

            for row in rows where row.resultStatus == "PENDING" {
                guard isCurrentSyncUser(userID) else { return }
                guard let begin = row.pendingBegin else {
                    parityWarningCount += 1
                    continue
                }
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
                } catch {
                    guard isCurrentSyncUser(userID) else { return }
                    hasRetryableFailure = true
                    lastErrorMessage = error.localizedDescription
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
                rows = try await remote.fetchVNextComparisonHistory()
                guard isCurrentSyncUser(userID) else { return }
            }

            let completedRows = rows.filter { $0.resultStatus == "COMPLETED" }
            let completedClientIDs = Set(completedRows.map(\.clientComparisonID))
            var processed = processedHistoryIDs(for: userID)
            let localIDs = Set(histories.map(\.id))

            if let modelContext {
                do {
                    guard isCurrentSyncUser(userID) else { return }
                    let hydrated = try hydrator.hydrateCompleted(
                        completedRows,
                        existingHistories: histories,
                        existingProducts: products,
                        existingClosetItems: closetItems,
                        modelContext: modelContext
                    )
                    guard isCurrentSyncUser(userID) else { return }
                    processed.formUnion(hydrated)
                } catch {
                    guard isCurrentSyncUser(userID) else { return }
                    hasRetryableFailure = true
                    lastErrorMessage = error.localizedDescription
                }
            } else {
                missingLocalCompletedCount = completedClientIDs.subtracting(localIDs).count
                parityWarningCount += missingLocalCompletedCount
            }

            for history in histories where !processed.contains(history.id) {
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

            let stillPending = rows.contains { $0.resultStatus == "PENDING" }
            if stillPending {
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
            lastErrorMessage = error.localizedDescription
            #if DEBUG
            print("[FitMatchComparisonSync] sync failed: \(error.localizedDescription)")
            #endif
        }
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
