import Foundation
import SwiftData

/// Minimal remote contract for the server-first link-registration action.
/// Keeping this narrower than account sync makes the View's production action
/// easy to exercise without pulling comparison or reconciliation authority
/// into the registration sheet.
nonisolated protocol FitMatchClosetRegistrationRemoteServicing: Sendable {
    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws
        -> FitMatchUpsertClosetItemResponse
    func setClosetReference(closetItemID: UUID, isReference: Bool) async throws
        -> FitMatchSetClosetReferenceResponse
}

extension FitMatchSupabaseDomainClient: FitMatchClosetRegistrationRemoteServicing {}

/// Serializes one compared-product Closet save interaction.  The sheet owns
/// its visual loading state and presentation, while this action owns the
/// interaction-level invariant that a second tap cannot begin a second save
/// before the first storage operation has reached a terminal result.
///
/// The operation itself remains the existing
/// `FitMatchComparedProductClosetRegistration.save` production boundary.  The
/// async closure only represents its real persistence side-effect boundary so
/// callers and headless tests exercise the same task-ownership rule.
@MainActor
final class FitMatchComparedProductClosetSubmissionAction {
    enum Outcome {
        case completed(FitMatchComparedProductClosetRegistration.SaveOutcome)
        case alreadyInFlight
    }

    private var isSubmitting = false
    private let remote: any FitMatchClosetRegistrationRemoteServicing

    init(
        remote: any FitMatchClosetRegistrationRemoteServicing = FitMatchSupabaseDomainClient.shared
    ) {
        self.remote = remote
    }

    func submit(
        operation: @MainActor () async -> FitMatchComparedProductClosetRegistration.SaveOutcome
    ) async -> Outcome {
        guard !isSubmitting else {
            return .alreadyInFlight
        }

        isSubmitting = true
        defer { isSubmitting = false }
        return .completed(await operation())
    }

    /// The link path must be server-first: it allocates one stable
    /// client_item_id, performs the atomic Closet upsert, optionally asks the
    /// server to make that row a reference, and only then persists SwiftData.
    /// A remote success followed by a local failure deliberately keeps the
    /// same pending id for retry; it never deletes the accepted server row.
    func submitServerFirst(
        _ submission: FitMatchComparedProductClosetRegistration.ServerFirstSubmission,
        in modelContext: ModelContext,
        persist: (ModelContext) throws -> Void = { try $0.save() }
    ) async -> Outcome {
        guard !isSubmitting else {
            return .alreadyInFlight
        }

        isSubmitting = true
        defer { isSubmitting = false }

        if FitMatchComparedProductClosetRegistration.isDuplicate(
            submission.localRequest
        ) {
            return .completed(.duplicate)
        }

        let response: FitMatchUpsertClosetItemResponse
        do {
            response = try await remote.upsertClosetItem(submission.remoteRequest)
            guard response.clientItemID == submission.remoteRequest.clientItemID else {
                return .completed(.serverRejected(
                    "서버가 등록 요청의 식별자를 확인하지 못했습니다. 다시 시도해 주세요."
                ))
            }
        } catch {
            return .completed(.serverRejected(serverMessage(for: error)))
        }

        var localRequest = submission.localRequest
        var referenceFailureMessage: String?
        if submission.localRequest.isRepresentative {
            do {
                let reference = try await remote.setClosetReference(
                    closetItemID: response.closetItemID,
                    isReference: true
                )
                guard reference.closetItemID == response.closetItemID,
                      reference.isReference else {
                    throw FitMatchSupabaseProductResolverError.invalidVNextResponse
                }
            } catch {
                // The item upsert already succeeded. Persist the local row as a
                // non-reference and explain this partial outcome rather than
                // attempting an unsafe compensating delete.
                localRequest = localRequest.replacingRepresentative(false)
                referenceFailureMessage = "옷은 등록했지만 기준 옷으로 지정할 수 없습니다."
            }
        }

        let localOutcome = FitMatchComparedProductClosetRegistration.save(
            localRequest,
            in: modelContext,
            persist: persist
        )
        switch localOutcome {
        case .saved(let item):
            if let referenceFailureMessage {
                return .completed(.savedWithoutReference(item, referenceFailureMessage))
            }
            return .completed(.saved(item))
        case .savedWithoutReference:
            // `save` itself cannot produce this case; retain the exhaustive
            // handling in case a future local persistence adapter can.
            return .completed(localOutcome)
        case .duplicate, .storageLookupFailed, .persistenceFailed,
             .serverRejected, .serverAcceptedLocalPersistenceFailed:
            return .completed(.serverAcceptedLocalPersistenceFailed(
                clientItemID: submission.remoteRequest.clientItemID
            ))
        }
    }

    private func serverMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let message = localized.errorDescription,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return "서버에 옷장을 저장하지 못했습니다. 다시 시도해 주세요."
    }
}
