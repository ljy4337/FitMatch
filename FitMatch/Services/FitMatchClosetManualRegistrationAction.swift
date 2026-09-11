import Foundation

/// The production action behind a new manual Closet registration.
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
