import Foundation

/// Serializes one visible Compare submission. The View continues to own its
/// presentation state and persistence, while both automatic and manual paths
/// share this production gate so a second tap cannot start a second server
/// begin/completion while the first action is still in flight.
@MainActor
final class FitMatchComparisonSubmissionAction {
    enum Outcome {
        case alreadyInFlight
        case cancelled
        case finished(RecommendationHistory?)
    }

    private var currentSubmissionID: UUID?

    /// Invalidates the currently visible submission without making any claim
    /// about a begin/complete RPC that may already have reached the server.
    /// A later request owns a new ID, so an old deferred cleanup cannot unlock
    /// or replace the current action.
    func invalidate() {
        currentSubmissionID = nil
    }

    func submit(
        _ work: @escaping @MainActor () async -> RecommendationHistory?
    ) async -> Outcome {
        guard currentSubmissionID == nil else { return .alreadyInFlight }
        let submissionID = UUID()
        currentSubmissionID = submissionID
        defer {
            if currentSubmissionID == submissionID {
                currentSubmissionID = nil
            }
        }
        guard !Task.isCancelled else { return .cancelled }
        let result = await work()
        guard !Task.isCancelled, currentSubmissionID == submissionID else {
            return .cancelled
        }
        return .finished(result)
    }
}
