import Foundation

/// Synchronous form action retained for local persistence consumers and tests.
/// New registration screens use the coordinator server-first boundary.
@MainActor
enum FitMatchClosetManualRegistrationAction {
    static func save(
        from viewModel: AddClosetItemViewModel,
        activeClosetItems _: [UserFit],
        persist: (UserFit) -> Bool
    ) -> FitMatchClosetFormAction.Outcome {
        FitMatchClosetFormAction.save(from: viewModel, persist: persist)
    }
}
