import Foundation

/// Non-visual account-deletion orchestration shared by My Page and headless
/// callers. The closures are the existing local cache side effects; this
/// action only preserves their order and user-visible terminal state.
@MainActor
enum FitMatchAccountDeletionAction {
    enum Outcome: Equatable {
        case deleted
        case serverDeletionFailed(String)
        case localPurgeFailed(String)

        var userVisibleMessage: String? {
            switch self {
            case .deleted:
                nil
            case .serverDeletionFailed(let message), .localPurgeFailed(let message):
                message
            }
        }
    }

    static func delete(
        authSession: FitMatchAuthSessionStore,
        deletedUserID: UUID?,
        purgeLocalData: () throws -> Void,
        purgeProcessedHistoryIDs: (UUID) -> Void
    ) async -> Outcome {
        guard await authSession.deleteAccount() else {
            return .serverDeletionFailed(
                authSession.errorMessage ?? "잠시 후 다시 시도해 주세요."
            )
        }

        do {
            try purgeLocalData()
            if let deletedUserID {
                purgeProcessedHistoryIDs(deletedUserID)
            }
            return .deleted
        } catch {
            return .localPurgeFailed(
                "이 기기의 데이터를 안전하게 정리하지 못했어요. 앱을 다시 열어 확인해 주세요."
            )
        }
    }
}
