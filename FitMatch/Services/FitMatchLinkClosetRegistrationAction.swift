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
        existingBrand: @escaping (String) -> Brand?
    ) async -> Outcome {
        if FitMatchRequestTrace.context == nil {
            let trace = FitMatchRequestTrace.Context(
                id: UUID(),
                origin: .closetRegistration
            )
            return await FitMatchRequestTrace.$context.withValue(trace) {
                await load(
                    urlString: urlString,
                    makeViewModel: makeViewModel,
                    existingBrand: existingBrand
                )
            }
        }
        let startedAt = Date()
        var completionState = "취소"
        defer {
#if DEBUG
            FitMatchDebugLogger.duration(
                stage: "상품 불러오기→다음 준비",
                startedAt: startedAt,
                state: completionState
            )
#endif
        }
        let validation = FitMatchProductLinkInput.validate(urlString)
        guard case .supported(let url) = validation else {
            // Keep the official provider boundary in front of parser/network
            // construction.  In particular, an unsupported COS URL must not
            // instantiate a shopping resolver just because a caller bypassed
            // the SwiftUI button's disabled state.
            completionState = "입력차단"
            return .blocked(validation)
        }

        let viewModel = makeViewModel(url.absoluteString)
        _ = await viewModel.loadProductInfoFromURL()
        guard !Task.isCancelled else {
            completionState = "취소"
            return .cancelled
        }

        // A fresh retailer observation can replace an earlier DB review
        // decision. Read runtime once more only when the first result still
        // says REVIEW_REQUIRED so the registration sheet receives the latest
        // confirmed tuple for every supported retailer.
        _ = await viewModel.refreshLinkRegistrationAuthorityIfNeeded()
        guard !Task.isCancelled else {
            completionState = "취소"
            return .cancelled
        }

        let brand = existingBrand(viewModel.brand) ?? Brand(name: viewModel.brand)
        completionState = "최종준비완료"
        return .loaded(
            LinkClosetRegistrationPreparation.make(
                from: viewModel,
                brand: brand
            )
        )
    }
}
