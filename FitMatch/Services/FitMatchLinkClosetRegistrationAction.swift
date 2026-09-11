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
        existingBrand: @escaping (String) -> Brand?,
        onRetailerProductLoaded: ((LinkClosetRegistrationPreparation) -> Void)? = nil
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
        _ = await viewModel.loadProductInfoFromURL { loadedViewModel in
            let brand = existingBrand(loadedViewModel.brand)
                ?? Brand(name: loadedViewModel.brand)
            onRetailerProductLoaded?(
                LinkClosetRegistrationPreparation.make(
                    from: loadedViewModel,
                    brand: brand
                )
            )
        }
        guard !Task.isCancelled else {
            return .cancelled
        }

        // A fresh retailer observation can replace an earlier DB review
        // decision. Read runtime once more only when the first result still
        // says REVIEW_REQUIRED so the registration sheet receives the latest
        // confirmed tuple for every supported retailer.
        _ = await viewModel.refreshLinkRegistrationAuthorityIfNeeded()
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
