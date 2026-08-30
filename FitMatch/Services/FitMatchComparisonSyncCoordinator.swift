import Combine
import Foundation
import SwiftData

protocol FitMatchComparisonRemoteServicing: Sendable {
    func fetchVNextComparisonHistory() async throws -> [VNextComparisonHistoryDTO]
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

    private static let processedPrefix = "FitMatch.comparisonProcessed.v2."

    init(
        remote: (any FitMatchComparisonRemoteServicing)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.remote = remote ?? FitMatchSupabaseDomainClient.shared
        self.defaults = defaults
    }

    func synchronize(
        userID: UUID,
        histories: [RecommendationHistory],
        products: [Product] = [],
        closetItems: [UserFit] = [],
        modelContext: ModelContext? = nil
    ) async {
        if isSynchronizing {
            needsAnotherPass = true
            return
        }

        isSynchronizing = true
        defer { isSynchronizing = false }

        repeat {
            needsAnotherPass = false
            await synchronizeOnce(
                userID: userID,
                histories: histories,
                products: products,
                closetItems: closetItems,
                modelContext: modelContext
            )
        } while needsAnotherPass
    }

    private func synchronizeOnce(
        userID: UUID,
        histories: [RecommendationHistory],
        products: [Product],
        closetItems: [UserFit],
        modelContext: ModelContext?
    ) async {
        state = .syncing
        lastErrorMessage = nil
        parityWarningCount = 0
        missingLocalCompletedCount = 0

        do {
            var rows = try await remote.fetchVNextComparisonHistory()
            var hasRetryableFailure = false
            var recoveredPending = false

            for row in rows where row.resultStatus == "PENDING" {
                guard let begin = row.pendingBegin else {
                    parityWarningCount += 1
                    continue
                }
                do {
                    let analysis = try adapter.analyze(begin)
                    let completed = try await remote.completeVNextComparison(
                        comparisonID: row.id,
                        payload: analysis.completionPayload
                    )
                    guard completed.completed,
                          completed.comparisonID == row.id,
                          completed.recommendedProductSizeID
                            == analysis.recommended.productSizeID else {
                        throw FitMatchSupabaseProductResolverError.invalidVNextResponse
                    }
                    recoveredPending = true
                } catch {
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
            }

            let completedRows = rows.filter { $0.resultStatus == "COMPLETED" }
            let completedClientIDs = Set(completedRows.map(\.clientComparisonID))
            var processed = processedHistoryIDs(for: userID)
            let localIDs = Set(histories.map(\.id))

            if let modelContext {
                do {
                    let hydrated = try hydrator.hydrateCompleted(
                        completedRows,
                        existingHistories: histories,
                        existingProducts: products,
                        existingClosetItems: closetItems,
                        modelContext: modelContext
                    )
                    processed.formUnion(hydrated)
                } catch {
                    hasRetryableFailure = true
                    lastErrorMessage = error.localizedDescription
                }
            } else {
                missingLocalCompletedCount = completedClientIDs.subtracting(localIDs).count
                parityWarningCount += missingLocalCompletedCount
            }

            for history in histories where !processed.contains(history.id) {
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
            state = .pendingRetry
            lastErrorMessage = error.localizedDescription
            #if DEBUG
            print("[FitMatchComparisonSync] sync failed: \(error.localizedDescription)")
            #endif
        }
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
