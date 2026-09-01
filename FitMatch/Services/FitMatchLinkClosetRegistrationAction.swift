import Foundation

/// The non-visual production action behind link-based Closet registration.
/// It deliberately owns only the parser/authority/preparation sequence; the
/// View continues to own loading presentation, sheets, and dismissal.
@MainActor
enum FitMatchLinkClosetRegistrationAction {
    enum Outcome {
        case loaded(LinkClosetRegistrationPreparation)
        case blocked(FitMatchProductLinkInput.Validation)
        case cancelled
    }

    static func load(
        urlString: String,
        makeViewModel: (String) -> ShoppingProductViewModel,
        existingBrand: (String) -> Brand?
    ) async -> Outcome {
        let validation = FitMatchProductLinkInput.validate(urlString)
        guard case .supported(let url) = validation else {
            // Keep the official provider boundary in front of parser/network
            // construction.  In particular, an unsupported COS URL must not
            // instantiate a shopping resolver just because a caller bypassed
            // the SwiftUI button's disabled state.
            return .blocked(validation)
        }

        let viewModel = makeViewModel(url.absoluteString)
        _ = await viewModel.loadProductInfoFromURL()
        guard !Task.isCancelled else {
            return .cancelled
        }

        let brand = existingBrand(viewModel.brand) ?? Brand(name: viewModel.brand)
        return .loaded(
            LinkClosetRegistrationPreparation.make(
                from: viewModel,
                brand: brand
            )
        )
    }
}
