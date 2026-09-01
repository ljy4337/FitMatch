import Foundation
import SwiftData

/// Non-visual production actions behind History deletion.  A server-completed
/// comparison is never deleted: the server visibility receipt must succeed
/// before its local presentation cache is removed.  Legacy local History
/// retains its existing local-only delete behavior.
@MainActor
enum FitMatchHistoryVisibilityAction {
    enum Outcome: Equatable {
        case deleted
        case comparisonSyncUnavailable
        case serverHideFailed
        case localPersistenceFailedAfterServerHide
        case localPersistenceFailed

        var userVisibleMessage: String? {
            switch self {
            case .deleted:
                nil
            case .comparisonSyncUnavailable:
                "서버 비교 기록을 삭제할 준비가 되지 않았어요. 다시 시도해 주세요."
            case .serverHideFailed:
                "비교 기록을 삭제하지 못했어요. 다시 시도해 주세요."
            case .localPersistenceFailedAfterServerHide:
                "비교 기록은 서버에서 삭제됐지만 이 기기에 반영하지 못했어요. 화면을 다시 열어 확인해 주세요."
            case .localPersistenceFailed:
                "비교 기록을 삭제하지 못했어요. 다시 시도해 주세요."
            }
        }
    }

    /// Handles one visible History delete request.  The caller continues to
    /// own button progress and alert presentation; it cannot report success
    /// until this action returns `.deleted`.
    static func delete(
        _ history: RecommendationHistory,
        in modelContext: ModelContext,
        comparisonSync: FitMatchComparisonSyncCoordinator?
    ) async -> Outcome {
        if history.isServerBackedVNextHistory {
            guard let comparisonSync else {
                return .comparisonSyncUnavailable
            }
            do {
                try await comparisonSync.hideVNextComparisonHistories(
                    clientComparisonIDs: [history.id]
                )
            } catch {
                return .serverHideFailed
            }
            return deleteLocally(
                history,
                in: modelContext,
                afterServerHide: true
            )
        }

        return deleteLocally(
            history,
            in: modelContext,
            afterServerHide: false
        )
    }

    /// Hides a batch before the owning Closet item can be deleted.  The
    /// immutable comparison evidence remains untouched on the server.
    static func hideCompletedServerHistories(
        _ histories: [RecommendationHistory],
        comparisonSync: FitMatchComparisonSyncCoordinator?
    ) async -> Outcome {
        let ids = Array(Set(histories.lazy
            .filter(\.isServerBackedVNextHistory)
            .map(\.id)))
            .sorted { $0.uuidString < $1.uuidString }
        guard !ids.isEmpty else { return .deleted }
        guard let comparisonSync else {
            return .comparisonSyncUnavailable
        }
        do {
            try await comparisonSync.hideVNextComparisonHistories(
                clientComparisonIDs: ids
            )
            return .deleted
        } catch {
            return .serverHideFailed
        }
    }

    /// Removes only presentation-cache rows after a successful user-owned
    /// server hide (or for a legacy local-only row).
    static func deleteLocally(
        _ history: RecommendationHistory,
        in modelContext: ModelContext,
        afterServerHide: Bool
    ) -> Outcome {
        modelContext.delete(history)
        do {
            try modelContext.save()
            return .deleted
        } catch {
            modelContext.rollback()
            return afterServerHide
                ? .localPersistenceFailedAfterServerHide
                : .localPersistenceFailed
        }
    }
}
