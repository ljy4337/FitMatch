import Foundation
import SwiftData

/// Builds the owned Closet row for a product that originated in the shopping
/// flow.  The sheet owns presentation, duplicate checks, and persistence; this
/// production action owns the classification-authority boundary shared by the
/// Result, History, Compare, and link-registration entry points.
///
/// In particular, a shopping USER_EXPLICIT classification is product-scoped.
/// It is not a Closet override unless the user separately changed the Closet
/// classification in that registration surface.
enum FitMatchComparedProductClosetRegistration {
    /// The production persistence action behind the compared-product Closet
    /// sheet.  The View owns the progress indicator, alert presentation, and
    /// dismissal; this action owns the existing identity, authority-boundary,
    /// reference, and save ordering so those semantics are available to every
    /// real entry point (and to headless tests) without a second implementation.
    struct SaveRequest {
        let product: Product
        let selectedSize: ProductSize
        let activeClosetItems: [UserFit]
        let brandName: String
        let gender: UserGender
        let genderCode: String
        let productName: String
        let category: ClothingCategory
        let categoryCode: String
        let detailCategory: ClosetDetailCategory
        let detailCategoryCode: String
        let isRepresentative: Bool
        let didExplicitlyChangeClassification: Bool

        init(
            product: Product,
            selectedSize: ProductSize,
            activeClosetItems: [UserFit],
            brandName: String,
            gender: UserGender,
            genderCode: String,
            productName: String,
            category: ClothingCategory,
            categoryCode: String,
            detailCategory: ClosetDetailCategory,
            detailCategoryCode: String,
            isRepresentative: Bool,
            didExplicitlyChangeClassification: Bool
        ) {
            self.product = product
            self.selectedSize = selectedSize
            self.activeClosetItems = activeClosetItems
            self.brandName = brandName
            self.gender = gender
            self.genderCode = genderCode
            self.productName = productName
            self.category = category
            self.categoryCode = categoryCode
            self.detailCategory = detailCategory
            self.detailCategoryCode = detailCategoryCode
            self.isRepresentative = isRepresentative
            self.didExplicitlyChangeClassification = didExplicitlyChangeClassification
        }
    }

    enum SaveOutcome {
        case saved(UserFit)
        case duplicate
        case storageLookupFailed
        case persistenceFailed

        var userVisibleMessage: String? {
            switch self {
            case .saved:
                nil
            case .duplicate:
                "이미 내 옷장에 등록된 사이즈입니다."
            case .storageLookupFailed:
                "저장된 상품 정보를 확인하지 못했습니다. 다시 시도해 주세요."
            case .persistenceFailed:
                "내 옷장에 저장하지 못했습니다. 다시 시도해 주세요."
            }
        }
    }

    /// Performs the exact storage sequence previously owned by
    /// `AddComparedProductToClosetSheet.saveSelectedSize()`.  It deliberately
    /// does not infer a Closet classification: `makeUserFit` remains the
    /// single boundary that keeps shopping USER_EXPLICIT separate from an
    /// explicit Closet classification intent.
    @MainActor
    static func save(
        _ request: SaveRequest,
        in modelContext: ModelContext,
        persist: (ModelContext) throws -> Void = { try $0.save() }
    ) -> SaveOutcome {
        if isDuplicate(
            size: request.selectedSize,
            product: request.product,
            among: request.activeClosetItems
        ) {
            return .duplicate
        }

        let storedProducts: [Product]
        do {
            storedProducts = try modelContext.fetch(FetchDescriptor<Product>())
        } catch {
            return .storageLookupFailed
        }

        // ProductSize.id is a size-chart identifier, not a retailer-product
        // identity. Resolve an existing row by the retailer product first so
        // saving "M" never attaches this Closet item to another product's M.
        let storedProduct = storedProducts.first {
            isSameRetailerProduct($0, request.product)
        }
        let sourceProduct = storedProduct ?? request.product
        storedProduct?.refreshExternalPresentation(from: request.product)

        let selectedSizeKey = ParsedProductSizeNormalizer.normalizedSizeKey(
            for: request.selectedSize.name
        )
        let sourceSize = storedProduct?.sizes.first {
            ParsedProductSizeNormalizer.normalizedSizeKey(for: $0.name) == selectedSizeKey
        } ?? request.selectedSize

        if sourceProduct.modelContext == nil {
            modelContext.insert(sourceProduct)
        }
        if sourceSize.product !== sourceProduct {
            sourceSize.product = sourceProduct
        }

        let item = makeUserFit(
            sourceProduct: sourceProduct,
            sourceSize: sourceSize,
            authorityProduct: request.product,
            brandName: request.brandName,
            gender: request.gender,
            genderCode: request.genderCode,
            productName: request.productName,
            category: request.category,
            categoryCode: request.categoryCode,
            detailCategory: request.detailCategory,
            detailCategoryCode: request.detailCategoryCode,
            isRepresentative: request.isRepresentative,
            didExplicitlyChangeClassification: request.didExplicitlyChangeClassification
        )

        if request.isRepresentative,
           item.classificationAuthorityProvenance?.isComparisonAuthority == true {
            FitMatchClosetReferenceMutation.setRepresentative(
                item,
                among: request.activeClosetItems
            )
        }

        modelContext.insert(item)
        do {
            try persist(modelContext)
        } catch {
            modelContext.rollback()
            return .persistenceFailed
        }

        if item.classificationAuthorityProvenance == .userExplicit {
            SourceCategoryHistoryMatcher.saveMapping(
                for: sourceProduct,
                category: request.category,
                detailCategory: request.detailCategory
            )
        }
        FitMatchMetricsRecorder.shared.record(
            .closetCreated(
                origin: .comparedProduct,
                category: FitMatchMetricMajorCategory(category: item.category)
            )
        )
        return .saved(item)
    }

    static func makeUserFit(
        sourceProduct: Product,
        sourceSize: ProductSize,
        authorityProduct: Product,
        brandName: String,
        gender: UserGender,
        genderCode: String,
        productName: String,
        category: ClothingCategory,
        categoryCode: String,
        detailCategory: ClosetDetailCategory,
        detailCategoryCode: String,
        isRepresentative: Bool,
        didExplicitlyChangeClassification: Bool
    ) -> UserFit {
        let item = UserFit(
            sourceType: sourceProduct.sourceType,
            sourceName: sourceProduct.sourceDisplayName,
            sourceCategoryPath: sourceProduct.sourceCategoryPath,
            sourceCategoryDepth1: sourceProduct.sourceCategoryDepth1,
            sourceCategoryDepth2: sourceProduct.sourceCategoryDepth2,
            sourceCategoryDepth3: sourceProduct.sourceCategoryDepth3,
            sourceCategoryDepth4: sourceProduct.sourceCategoryDepth4,
            brandName: brandName,
            gender: gender,
            productName: productName,
            category: category,
            detailCategory: detailCategory,
            sizeName: displaySizeName(for: sourceSize.name),
            measurements: sourceSize.measurements,
            fitMemo: "비교 상품에서 추가",
            fitPreference: .regular,
            satisfaction: 0,
            isRepresentative: isRepresentative,
            sourceProduct: sourceProduct,
            sourceProductSize: sourceSize
        )
        item.genderCode = genderCode
        item.categoryCode = categoryCode
        item.detailCategoryCode = detailCategoryCode

        let savedAuthority = FitMatchClosetClassificationEditPolicy.resultingAuthority(
            current: authorityProduct.classificationAuthorityProvenance,
            isSourced: FitMatchClosetClassificationEditPolicy.isSourced(authorityProduct),
            isExplicitSet: FitMatchClosetClassificationEditPolicy.isExplicitSet(authorityProduct),
            didExplicitlyChangeClassification: didExplicitlyChangeClassification,
            scope: .newSourcedRegistration
        )
        applyAuthority(
            savedAuthority,
            to: item,
            authorityProduct: authorityProduct,
            category: category,
            detailCategory: detailCategory,
            productName: productName
        )
        item.replaceMeasurementRecords(with: sourceSize.measurementRecords)
        if item.classificationAuthorityProvenance
            == FitMatchClassificationAuthorityProvenance.userExplicit {
            _ = ComparisonProfileMatcher().profile(for: item)
        }
        return item
    }

    private static func applyAuthority(
        _ savedAuthority: FitMatchClassificationAuthorityProvenance,
        to item: UserFit,
        authorityProduct: Product,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        productName: String
    ) {
        if savedAuthority == .userExplicit {
            // Only the current registration surface's explicit Closet picker
            // may create this owned personal authority.  Product-derived
            // shopping Recovery facts are deliberately not reused here.
            let savedClassification = ParsedClosetClassification.resolve(
                category: category,
                detailCategory: detailCategory,
                sourceDepths: [],
                sourcePath: nil,
                productName: productName
            )
            item.normalizedProductTypeCode = savedClassification?.normalizedProductTypeCode
            if let savedClassification {
                item.garmentType = savedClassification.garmentFamily
                item.sleeveType = savedClassification.lengthType
                item.constructionType = savedClassification.constructionType
            }
            item.markClassificationAuthority(.userExplicit)
            return
        }

        if savedAuthority == .serverConfirmed {
            item.normalizedProductTypeCode = authorityProduct.normalizedProductTypeCode
            item.garmentTypeRawValue = authorityProduct.garmentTypeRawValue
            item.sleeveTypeRawValue = authorityProduct.sleeveTypeRawValue
            item.constructionTypeRawValue = authorityProduct.constructionTypeRawValue
            item.canonicalPolicyVersion = authorityProduct.canonicalPolicyVersion
            item.markClassificationAuthority(
                .serverConfirmed,
                sourceIdentity: authorityProduct.canonicalSourceIdentity
            )
            return
        }

        switch savedAuthority {
        case .serverReviewRequired:
            item.markClassificationAuthority(
                .serverReviewRequired,
                sourceIdentity: authorityProduct.canonicalSourceIdentity
            )
        case .serverNotComparable:
            item.markClassificationAuthority(
                .serverNotComparable,
                sourceIdentity: authorityProduct.canonicalSourceIdentity
            )
        case .serverUnavailable:
            item.markClassificationAuthority(
                .serverUnavailable,
                sourceIdentity: authorityProduct.canonicalSourceIdentity
            )
        default:
            item.markClassificationAuthority(.localHint)
        }
    }

    private static func displaySizeName(for rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalComponent = value
            .split(separator: "/")
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? value
        return SizeTokenNormalizer.displayName(for: finalComponent)
    }

    private static func isDuplicate(
        size: ProductSize,
        product: Product,
        among userFits: [UserFit]
    ) -> Bool {
        userFits.contains { item in
            let selectedDisplaySize = displaySizeName(for: size.name)
            if item.sourceProductSize?.id == size.id {
                return true
            }

            if let sourceURL = product.sourceURLString,
               let itemURL = item.sourceProduct?.sourceURLString,
               sourceURL == itemURL,
               item.sizeName == selectedDisplaySize {
                return true
            }

            if let productCode = product.productCode,
               let itemProductCode = item.sourceProduct?.productCode,
               productCode == itemProductCode,
               item.sizeName == selectedDisplaySize {
                return true
            }

            if product.sourceURLString != nil,
               item.sourceProduct == nil,
               item.productName == product.name,
               item.sizeName == selectedDisplaySize,
               item.sourceName == product.sourceDisplayName,
               item.brandName == product.brand?.name {
                return true
            }

            return false
        }
    }

    static func isSameRetailerProduct(_ lhs: Product, _ rhs: Product) -> Bool {
        if let lhsURL = normalizedSourceURL(lhs.sourceURLString),
           let rhsURL = normalizedSourceURL(rhs.sourceURLString) {
            return lhsURL == rhsURL
        }

        guard let lhsCode = normalizedText(lhs.productCode), !lhsCode.isEmpty,
              let rhsCode = normalizedText(rhs.productCode), !rhsCode.isEmpty,
              lhsCode == rhsCode else {
            return false
        }

        let lhsPlatform = normalizedText(lhs.sourcePlatformCode)
        let rhsPlatform = normalizedText(rhs.sourcePlatformCode)
        return lhsPlatform == nil || rhsPlatform == nil || lhsPlatform == rhsPlatform
    }

    private static func normalizedSourceURL(_ value: String?) -> String? {
        guard var value = normalizedText(value)?.lowercased(), !value.isEmpty else {
            return nil
        }
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private static func normalizedText(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
