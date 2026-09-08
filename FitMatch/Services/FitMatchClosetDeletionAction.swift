import Foundation
import SwiftData

/// The production-used transaction boundary for deleting a Closet item.
/// It retains the existing durable History semantics:
/// server-completed History is hidden first, immutable remote evidence stays,
/// then the local History presentation cache and Closet row are removed.
@MainActor
enum FitMatchClosetDeletionAction {
    enum Outcome: Equatable {
        case deleted
        case comparisonSyncUnavailable
        case authenticationRequired
        case serverHistoryUnavailable
        case serverHistoryHideFailed
        case localPersistenceFailed(historyWasHiddenOnServer: Bool)

        var userVisibleMessage: String? {
            switch self {
            case .deleted:
                nil
            case .comparisonSyncUnavailable:
                "서버 비교 기록을 삭제할 준비가 되지 않았어요. 다시 시도해 주세요."
            case .authenticationRequired:
                "로그인 상태를 확인한 뒤 다시 시도해 주세요."
            case .serverHistoryUnavailable:
                "이 비교 기록은 현재 처리할 수 없습니다. 목록을 새로 확인한 뒤 다시 시도해 주세요."
            case .serverHistoryHideFailed:
                "비교 기록을 삭제하지 못했어요. 다시 시도해 주세요."
            case .localPersistenceFailed(let historyWasHiddenOnServer):
                historyWasHiddenOnServer
                    ? "비교 기록은 서버에서 삭제됐지만 옷을 삭제하지 못했어요. 다시 시도해 주세요."
                    : "옷을 삭제하지 못했어요. 다시 시도해 주세요."
            }
        }
    }

    static func delete(
        item: UserFit,
        histories: [RecommendationHistory],
        in modelContext: ModelContext,
        comparisonSync: FitMatchComparisonSyncCoordinator?,
        closetSync: FitMatchClosetSyncCoordinator?
    ) async -> Outcome {
        // Capture immutable identity before mutation.  No deleted SwiftData
        // object is traversed after `modelContext.delete(item)`.
        let itemID = item.id
        let relatedHistories = histories.filter {
            $0.referencesClosetItem(clientItemID: itemID)
        }
        let serverHistories = relatedHistories.filter(\.isServerBackedVNextHistory)

        let hideOutcome = await FitMatchHistoryVisibilityAction
            .hideCompletedServerHistories(
                serverHistories,
                comparisonSync: comparisonSync
            )
        switch hideOutcome {
        case .deleted:
            break
        case .comparisonSyncUnavailable:
            return .comparisonSyncUnavailable
        case .authenticationRequired:
            return .authenticationRequired
        case .serverHistoryUnavailable:
            return .serverHistoryUnavailable
        case .serverHideUnavailable,
             .invalidServerHideRequest,
             .serverHideUncertain,
             .serverHideFailed:
            return .serverHistoryHideFailed
        case .localPersistenceFailedAfterServerHide, .localPersistenceFailed:
            // `hideCompletedServerHistories` never performs local persistence.
            return .serverHistoryHideFailed
        }

        relatedHistories.forEach(modelContext.delete)
        modelContext.delete(item)
        do {
            try modelContext.save()
            closetSync?.enqueueDeletion(clientItemID: itemID)
            return .deleted
        } catch {
            modelContext.rollback()
            return .localPersistenceFailed(historyWasHiddenOnServer: !serverHistories.isEmpty)
        }
    }
}
