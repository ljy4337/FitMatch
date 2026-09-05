import Foundation

/// A transient, freshly-resolved registration input for a comparison Result.
///
/// A completed Result is historical presentation data.  In contrast, this
/// preparation always rebuilds retailer products through the current server
/// authority/runtime before the Closet sheet can be opened.  The optional
/// context intentionally remains nil only for the pre-existing manual product
/// path; a retailer-sourced Result never falls back to that local-only path.
@MainActor
struct FitMatchResultClosetRegistrationPreparation: Identifiable {
    let id = UUID()
    let product: Product
    let productDetailCategory: ClosetDetailCategory
    let serverRegistrationContext: FitMatchClosetRegistrationServerContext?
    /// A display size selected only after matching the exact server
    /// `product_size_id` from the completed comparison batch to the fresh
    /// runtime context.  It is never recovered from the rendered size label.
    let preferredSize: ProductSize?
    /// When the Result was displaying a known exact size that has become
    /// unregistrable in the fresh runtime, retain no selection rather than
    /// silently returning to the historical recommendation.
    let requiresExplicitSizeSelection: Bool
}

/// Non-visual preparation behind Result → "보유한 옷으로 등록".
///
/// This deliberately reuses `ShoppingProductViewModel`'s historical-product
/// replay path.  That path sends retained retailer facts to the existing
/// server coordinator, obtains current authority/runtime, restores every
/// runtime size, and builds the exact registration identity map used by the
/// Phase 1E server-first sheet.
@MainActor
enum FitMatchResultClosetRegistrationPreparationAction {
    enum Outcome {
        case prepared(FitMatchResultClosetRegistrationPreparation)
        case blocked(String)
        case cancelled
    }

    static func prepare(
        historicalProduct: Product,
        productDetailCategory: ClosetDetailCategory,
        preferredProductSizeID: UUID?,
        legacyPreferredSize: ProductSize?,
        makeViewModel: () -> ShoppingProductViewModel
    ) async -> Outcome {
        // Manual products have no retailer identity to resolve.  Preserve the
        // established local form behavior for that intentionally separate
        // flow, while never using it as a fallback for a sourced product.
        guard historicalProduct.sourceType != .manual else {
            return .prepared(
                FitMatchResultClosetRegistrationPreparation(
                    product: historicalProduct,
                    productDetailCategory: productDetailCategory,
                    serverRegistrationContext: nil,
                    preferredSize: legacyPreferredSize,
                    requiresExplicitSizeSelection: false
                )
            )
        }

        let viewModel = makeViewModel()
        _ = await viewModel.loadProductInfoFromHistoricalProduct(historicalProduct)
        guard !Task.isCancelled else {
            return .cancelled
        }

        let context = viewModel.closetRegistrationServerContext
        if let message = context.registrationBlockMessage {
            return .blocked(viewModel.errorMessage ?? message)
        }

        guard viewModel.productMeasurementPresence != .none else {
            return .blocked("이 상품은 실측 정보가 없어 내 옷장에 등록할 수 없습니다.")
        }

        // A server-approved classification without fresh exact size identity
        // cannot safely become a retailer Closet mutation.
        guard !context.identitiesByDisplaySizeID.isEmpty else {
            return .blocked("서버 사이즈 정보를 다시 확인해 주세요.")
        }

        let brand = historicalProduct.brand ?? Brand(name: viewModel.brand)
        guard let product = viewModel.makeProductForClosetRegistration(brand: brand) else {
            return .blocked(
                viewModel.errorMessage
                    ?? "서버 상품 정보를 다시 확인한 뒤 등록해 주세요."
            )
        }

        // `availableSizes` in the sheet will apply this same set for
        // presentation.  Check it here as well so a Result never opens a
        // server-first registration form that cannot make a valid request.
        guard !context.registerableDisplaySizeIDs.isEmpty else {
            return .blocked("서버 사이즈 정보를 다시 확인해 주세요.")
        }

        let preferredSize = preferredDisplaySize(
            for: preferredProductSizeID,
            product: product,
            context: context
        )
        return .prepared(
            FitMatchResultClosetRegistrationPreparation(
                product: product,
                productDetailCategory: viewModel.detailCategory,
                serverRegistrationContext: context,
                preferredSize: preferredSize,
                requiresExplicitSizeSelection: preferredProductSizeID != nil
                    && preferredSize == nil
            )
        )
    }

    /// Converts an exact runtime `product_size_id` to its fresh display row.
    /// The context is the proof boundary: a ProductSize's local ID alone is
    /// never treated as a production database ID.
    static func preferredDisplaySize(
        for productSizeID: UUID?,
        product: Product,
        context: FitMatchClosetRegistrationServerContext
    ) -> ProductSize? {
        guard let productSizeID else {
            return nil
        }
        return product.sizes.first { displaySize in
            guard context.isRegisterable(displaySizeID: displaySize.id) else {
                return false
            }
            return context.identity(for: displaySize.id)?.productSizeID == productSizeID
        }
    }
}
