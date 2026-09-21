import Foundation
import SwiftData

/// The production-used transaction boundary for deleting a Closet item.
/// It retains the existing durable History semantics:
/// server-completed History is hidden first, immutable remote evidence stays,
/// then the local History presentation cache and Closet row are removed.
@MainActor
enum FitMatchClosetDeletionAction {
    enum Outcome: Error, Equatable {
        case deleted
        case serverClosetUnavailable
        case serverDeletionUnconfirmed
        case serverDeletedLocalPending
        case synchronizationInProgress
        case sessionChanged
        case comparisonSyncUnavailable
        case authenticationRequired
        case serverHistoryUnavailable
        case serverHistoryHideFailed
        case localPersistenceFailed(historyWasHiddenOnServer: Bool)

        var userVisibleMessage: String? {
            switch self {
            case .deleted:
                nil
            case .serverClosetUnavailable:
                "옷장 삭제를 준비하지 못했어요. 화면을 다시 열고 시도해 주세요."
            case .serverDeletionUnconfirmed:
                "삭제 완료를 확인하지 못했어요. 옷은 아직 목록에 표시됩니다. 연결을 확인하고 다시 시도해 주세요."
            case .serverDeletedLocalPending:
                "서버에서는 삭제됐지만 이 기기 목록을 정리하지 못했어요. 다시 시도해 주세요."
            case .synchronizationInProgress:
                "옷장 동기화가 오래 걸려 삭제를 시작하지 못했어요. 연결 상태를 확인한 뒤 다시 삭제해 주세요."
            case .sessionChanged:
                "로그인 상태가 바뀌어 삭제를 중단했어요. 현재 계정의 옷장을 다시 확인해 주세요."
            case .comparisonSyncUnavailable:
                "비교 기록 삭제 서비스를 준비하지 못했어요. 문제가 계속되면 문의해 주세요."
            case .authenticationRequired:
                FitMatchFailureCopy.loginRequired
            case .serverHistoryUnavailable:
                "이 비교 기록은 현재 처리할 수 없습니다. 목록을 새로 확인한 뒤 다시 시도해 주세요."
            case .serverHistoryHideFailed:
                "비교 기록 삭제 서비스에 문제가 있어요. 문제가 계속되면 문의해 주세요."
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
        closetSync: (any FitMatchClosetDeleting)?
    ) async -> Outcome {
        // Capture immutable identity before mutation.  No deleted SwiftData
        // object is traversed after `modelContext.delete(item)`.
        let itemID = item.id
        let relatedHistories = histories.filter {
            $0.referencesClosetItem(clientItemID: itemID)
        }
        let serverHistories = relatedHistories.filter(\.isServerBackedVNextHistory)

        guard let closetSync else { return .serverClosetUnavailable }
        do {
            try await closetSync.deleteServerFirst(
                clientItemID: itemID,
                prepare: {
                    let hideOutcome = await FitMatchHistoryVisibilityAction
                        .hideCompletedServerHistories(serverHistories, comparisonSync: comparisonSync)
                    switch hideOutcome {
                    case .deleted: break
                    case .comparisonSyncUnavailable: throw Outcome.comparisonSyncUnavailable
                    case .authenticationRequired: throw Outcome.authenticationRequired
                    case .serverHistoryUnavailable: throw Outcome.serverHistoryUnavailable
                    default: throw Outcome.serverHistoryHideFailed
                    }
                },
                commit: {
                    relatedHistories.forEach(modelContext.delete)
                    modelContext.delete(item)
                    do {
                        try modelContext.save()
                    } catch {
                        modelContext.rollback()
                        throw Outcome.serverDeletedLocalPending
                    }
                }
            )
            return .deleted
        } catch let outcome as Outcome {
            return outcome
        } catch let error as FitMatchClosetDeletionTransaction.Failure {
            switch error {
            case .sessionChanged: return .sessionChanged
            case .synchronizationInProgress: return .synchronizationInProgress
            case .invalidReceipt: return .serverClosetUnavailable
            }
        } catch let error as FitMatchSupabaseProductResolverError {
            if case .authenticationRequired = error { return .authenticationRequired }
            return .serverDeletionUnconfirmed
        } catch {
            return .serverDeletionUnconfirmed
        }
    }
}
