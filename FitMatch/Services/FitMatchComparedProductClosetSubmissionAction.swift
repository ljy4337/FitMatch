import Foundation

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
}
