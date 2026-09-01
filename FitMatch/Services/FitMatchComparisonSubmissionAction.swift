import Foundation

/// Serializes one visible Compare submission. The View continues to own its
/// presentation state and persistence, while both automatic and manual paths
/// share this production gate so a second tap cannot start a second server
/// begin/completion while the first action is still in flight.
@MainActor
final class FitMatchComparisonSubmissionAction {
    enum Outcome {
        case alreadyInFlight
        case finished(RecommendationHistory?)
    }

    private var isInFlight = false

    func submit(
        _ work: @escaping @MainActor () async -> RecommendationHistory?
    ) async -> Outcome {
        guard !isInFlight else { return .alreadyInFlight }
        isInFlight = true
        defer { isInFlight = false }
        return .finished(await work())
    }
}
