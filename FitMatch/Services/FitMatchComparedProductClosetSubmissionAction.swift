import Foundation
import SwiftData
import Supabase

/// Minimal remote contract for the server-first link-registration action.
/// Keeping this narrower than account sync makes the View's production action
/// easy to exercise without pulling comparison or reconciliation authority
/// into the registration sheet.
nonisolated protocol FitMatchClosetRegistrationRemoteServicing: Sendable {
    func upsertClosetItem(_ request: FitMatchUpsertClosetItemRequest) async throws
        -> FitMatchUpsertClosetItemResponse
    func setClosetReference(closetItemID: UUID, isReference: Bool) async throws
        -> FitMatchSetClosetReferenceResponse
    func listClosetItems() async throws -> FitMatchClosetItemsResponse
}

extension FitMatchClosetRegistrationRemoteServicing {
    /// Existing test seams that only exercise the write boundary retain a
    /// compile-compatible default. The production client implements the real
    /// read-back method and the app supplies an authoritative projector.
    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        throw FitMatchSupabaseProductResolverError.invalidVNextResponse
    }
}

extension FitMatchSupabaseDomainClient: FitMatchClosetRegistrationRemoteServicing {}

nonisolated enum FitMatchClosetSubmissionRecovery: Equatable, Sendable {
    case editable
    case retrySameRequest
    case serverAccepted(closetItemID: UUID)

    var mayEditInput: Bool {
        if case .editable = self { return true }
        return false
    }
}

nonisolated enum FitMatchClosetRegistrationRPCError: LocalizedError, Sendable {
    case rejected(sqlState: String, message: String)

    var errorDescription: String? {
        switch self {
        case .rejected(_, let message): return message
        }
    }
}

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
    private(set) var recovery: FitMatchClosetSubmissionRecovery = .editable

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

    func resetAfterCompletedSubmission() {
        recovery = .editable
    }

    /// The link path must be server-first: it allocates one stable
    /// client_item_id, performs the atomic Closet upsert, optionally asks the
    /// server to make that row a reference, and only then persists SwiftData.
    /// A remote success followed by a local failure deliberately keeps the
    /// same pending id for retry; it never deletes the accepted server row.
    func submitServerFirst(
        _ submission: FitMatchComparedProductClosetRegistration.ServerFirstSubmission,
        in modelContext: ModelContext,
        submissionUserID: UUID? = nil,
        currentUserID: @MainActor () -> UUID? = { nil },
        projectAuthoritativeReceipt: ((
            FitMatchClosetItemRecord,
            FitMatchUpsertClosetItemRequest,
            UUID,
            ModelContext
        ) throws -> UserFit)? = nil,
        persist: (ModelContext) throws -> Void = { try $0.save() }
    ) async -> Outcome {
        guard !isSubmitting else {
            return .alreadyInFlight
        }

        isSubmitting = true
        defer { isSubmitting = false }

        if recovery.mayEditInput,
           FitMatchComparedProductClosetRegistration.isDuplicate(submission.localRequest) {
            return .completed(.duplicate)
        }

        guard isCurrentSubmissionUser(submissionUserID, currentUserID) else {
            return .completed(.serverRejected("로그인 상태가 변경되어 등록 결과를 안전하게 확인할 수 없습니다."))
        }

        let acceptedClosetItemID: UUID
        switch recovery {
        case .serverAccepted(let closetItemID):
            // Never write the same accepted client_item_id again. Continue at
            // the authoritative read-back receipt only.
            acceptedClosetItemID = closetItemID
        case .editable, .retrySameRequest:
            do {
                let response = try await remote.upsertClosetItem(submission.remoteRequest)
                guard response.clientItemID == submission.remoteRequest.clientItemID else {
                    // A decode/identity anomaly can follow a committed RPC.
                    // Keep exactly this immutable request for reconciliation.
                    recovery = .retrySameRequest
                    return .completed(.serverRejected(
                        "서버 등록 결과를 확인하지 못했습니다. 등록 결과를 다시 확인해 주세요."
                    ))
                }
                guard isCurrentSubmissionUser(submissionUserID, currentUserID) else {
                    recovery = .serverAccepted(closetItemID: response.closetItemID)
                    return .completed(.serverAcceptedLocalPersistenceFailed(
                        clientItemID: submission.remoteRequest.clientItemID
                    ))
                }
                acceptedClosetItemID = response.closetItemID
                recovery = .serverAccepted(closetItemID: acceptedClosetItemID)
            } catch {
                if deterministicRejection(from: error) != nil, recovery.mayEditInput {
                    // A first SQL-state rejection proves this transaction did
                    // not commit, so a user may change XL to M and form a new
                    // immutable request/client ID.
                    recovery = .editable
                    return .completed(.serverRejected(serverMessage(for: error)))
                }
                // A transport failure, PGRST envelope, decode issue, or a
                // replay rejection after an earlier timeout cannot disprove a
                // previous commit. Lock input and retain the exact request.
                recovery = .retrySameRequest
                return .completed(.serverRejected(serverMessage(for: error)))
            }
        }

        var receiptReferenceState = false
        if submission.localRequest.isRepresentative {
            do {
                let response = try await remote.setClosetReference(
                    closetItemID: acceptedClosetItemID,
                    isReference: true
                )
                receiptReferenceState = response.isReference
            } catch {
                // An absent reply is not evidence that the server left this
                // row non-reference. The following list receipt is final.
            }
        }

        guard isCurrentSubmissionUser(submissionUserID, currentUserID) else {
            return .completed(.serverAcceptedLocalPersistenceFailed(
                clientItemID: submission.remoteRequest.clientItemID
            ))
        }

        guard let projectAuthoritativeReceipt else {
            // This branch is retained solely for older isolated unit-test
            // seams that intentionally model only the write boundary. The
            // application sheet always supplies the authoritative projector
            // below, so production cannot construct a UserFit from the
            // pre-submit ProductSize.
            let fallback = FitMatchComparedProductClosetRegistration.save(
                submission.localRequest.replacingRepresentative(receiptReferenceState),
                in: modelContext,
                persist: persist
            )
            switch fallback {
            case .saved(let item):
                if submission.localRequest.isRepresentative,
                   !receiptReferenceState {
                    return .completed(.savedWithoutReference(
                        item,
                        "옷은 등록했지만 기준 옷으로 지정할 수 없습니다."
                    ))
                }
                return .completed(.saved(item))
            case .persistenceFailed:
                return .completed(.serverAcceptedLocalPersistenceFailed(
                    clientItemID: submission.remoteRequest.clientItemID
                ))
            default:
                return .completed(.serverAcceptedLocalPersistenceFailed(
                    clientItemID: submission.remoteRequest.clientItemID
                ))
            }
        }

        let receipt: FitMatchClosetItemRecord
        do {
            let rows = try await remote.listClosetItems()
            guard rows.state == "ready" else {
                throw FitMatchSupabaseProductResolverError.authenticationRequired
            }
            let matches = rows.items.filter {
                $0.clientItemID == submission.remoteRequest.clientItemID
            }
            guard matches.count == 1 else {
                throw FitMatchSupabaseProductResolverError.invalidVNextResponse
            }
            receipt = matches[0]
        } catch {
            return .completed(.serverAcceptedLocalPersistenceFailed(
                clientItemID: submission.remoteRequest.clientItemID
            ))
        }

        guard isCurrentSubmissionUser(submissionUserID, currentUserID) else {
            return .completed(.serverAcceptedLocalPersistenceFailed(
                clientItemID: submission.remoteRequest.clientItemID
            ))
        }

        let item: UserFit
        do {
            item = try projectAuthoritativeReceipt(
                receipt,
                submission.remoteRequest,
                acceptedClosetItemID,
                modelContext
            )
        } catch {
            return .completed(.serverAcceptedLocalPersistenceFailed(
                clientItemID: submission.remoteRequest.clientItemID
            ))
        }

        if submission.localRequest.isRepresentative && !receipt.isReference {
            return .completed(.savedWithoutReference(
                item,
                "옷은 등록했지만 기준 옷으로 지정할 수 없습니다."
            ))
        }
        return .completed(.saved(item))
    }

    private func isCurrentSubmissionUser(
        _ original: UUID?,
        _ currentUserID: @MainActor () -> UUID?
    ) -> Bool {
        guard let original else { return true }
        return currentUserID() == original
    }

    private func deterministicRejection(from error: Error) -> (code: String, message: String)? {
        if let registrationError = error as? FitMatchClosetRegistrationRPCError {
            switch registrationError {
            case .rejected(let sqlState, let message):
                return (sqlState, message)
            }
        }
        guard let postgrest = error as? PostgrestError,
              let code = postgrest.code?.uppercased(),
              isDeterministicSQLState(code) else {
            return nil
        }
        return (code, postgrest.message)
    }

    private func isDeterministicSQLState(_ code: String) -> Bool {
        code == "P0001"
            || code.hasPrefix("22")
            || code.hasPrefix("23")
            || code.hasPrefix("40")
            || code == "42501"
            || code.hasPrefix("28")
    }

    private func serverMessage(for error: Error) -> String {
        let localized = (error as? LocalizedError)?.errorDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let localizedMessage = localized?.isEmpty == false ? localized : nil
        let diagnosticMessage = localizedMessage
            ?? error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = diagnosticMessage.lowercased()
        // The public RPC is the final canonical-measurement authority. Keep
        // its SQL-facing rejection out of the View and translate it here at
        // the registration domain boundary.
        if normalized.contains("closet registration requires at least one usable canonical measurement")
            || (normalized.contains("usable canonical measurement")
                && normalized.contains("closet")) {
            return "선택한 사이즈는 실측 정보가 없어 내 옷장에 등록할 수 없습니다."
        }
        if let localizedMessage { return localizedMessage }
        return "서버에 옷장을 저장하지 못했습니다. 다시 시도해 주세요."
    }
}
