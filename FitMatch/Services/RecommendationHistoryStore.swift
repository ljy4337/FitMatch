import Foundation
import SwiftData

enum RecommendationHistoryStore {
    /// Persists a server-completed vNext comparison without invoking any of
    /// the legacy presentation-identity fallbacks. The remote snapshot keeps
    /// the server identities; the local cache gets a per-comparison immutable
    /// Product/reference projection so later comparisons cannot mutate the
    /// presentation or authority of an older completed row.
    static func saveCompletedVNext(
        _ history: RecommendationHistory,
        existing histories: [RecommendationHistory],
        modelContext: ModelContext
    ) throws {
        guard history.comparisonSchemaVersion >= 2,
              history.calculationSnapshot != nil,
              history.comparisonMethod.hasPrefix("서버 승인") else {
            throw RecommendationHistoryStoreError.invalidCompletedVNextHistory
        }

        let historyID = history.id
        if histories.contains(where: { $0.id == historyID }) {
            return
        }
        let historyDescriptor = FetchDescriptor<RecommendationHistory>(
            predicate: #Predicate { $0.id == historyID }
        )
        if try modelContext.fetch(historyDescriptor).first != nil {
            return
        }

        let incomingProduct = history.product
        let incomingReference = history.userFit
        let recommendedSizeID = history.recommendedSize.id
        guard incomingProduct.sizes.contains(where: { $0.id == recommendedSizeID }) else {
            throw RecommendationHistoryStoreError.vnextIdentityConflict
        }

        let localProductID = VNextHistoryProjectionIdentity.productID(
            comparisonID: historyID
        )
        let existingProductDescriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.id == localProductID }
        )
        guard try modelContext.fetch(existingProductDescriptor).isEmpty else {
            // A projection without the immutable History row is not safe to
            // guess at or reuse. The next server hydration can recover it.
            throw RecommendationHistoryStoreError.vnextIdentityConflict
        }

        let frozenProduct = makeHistoricalProductProjection(
            from: incomingProduct,
            comparisonID: historyID
        )
        let frozenSizes = incomingProduct.sizes.map {
            makeHistoricalSizeProjection(
                from: $0,
                comparisonID: historyID,
                product: frozenProduct
            )
        }
        frozenProduct.sizes = frozenSizes
        guard let frozenRecommendedSize = frozenSizes.first(where: {
            $0.id == VNextHistoryProjectionIdentity.productSizeID(
                comparisonID: historyID,
                productSizeID: recommendedSizeID
            )
        }) else {
            throw RecommendationHistoryStoreError.vnextIdentityConflict
        }

        let frozenReference = makeHistoricalReferenceProjection(
            from: incomingReference,
            comparisonID: historyID
        )

        history.product = frozenProduct
        history.recommendedSize = frozenRecommendedSize
        history.userFit = frozenReference

        modelContext.insert(frozenProduct)
        modelContext.insert(frozenReference)
        modelContext.insert(history)
        try modelContext.save()
    }

    private static func makeHistoricalProductProjection(
        from source: Product,
        comparisonID: UUID
    ) -> Product {
        let projection = Product(
            id: VNextHistoryProjectionIdentity.productID(comparisonID: comparisonID),
            name: source.name,
            brand: source.brand,
            category: source.category,
            productCode: source.productCode,
            sourceURLString: source.sourceURLString,
            imageURLString: source.imageURLString,
            sourceType: source.sourceType,
            sourceName: source.sourceName,
            source: source.source,
            notes: source.notes,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt
        )
        copyProductSnapshot(from: source, to: projection, comparisonID: comparisonID)
        return projection
    }

    private static func copyProductSnapshot(
        from source: Product,
        to destination: Product,
        comparisonID: UUID
    ) {
        destination.categoryRawValue = source.categoryRawValue
        destination.categoryCode = source.categoryCode
        destination.normalizedProductTypeCode = source.normalizedProductTypeCode
        destination.garmentTypeRawValue = source.garmentTypeRawValue
        destination.sleeveTypeRawValue = source.sleeveTypeRawValue
        destination.constructionTypeRawValue = source.constructionTypeRawValue
        destination.canonicalProfileSnapshotJSON = source.canonicalProfileSnapshotJSON
        destination.canonicalPolicyVersion = source.canonicalPolicyVersion
        destination.canonicalResolutionMethod = source.canonicalResolutionMethod
        destination.canonicalSourceIdentity = [
            source.canonicalSourceIdentity ?? "unknown",
            "target=\(source.id.uuidString.lowercased())",
            "comparison=\(comparisonID.uuidString.lowercased())"
        ].joined(separator: ";")
        destination.canonicalEligibility = source.canonicalEligibility
        destination.styleNo = source.styleNo
        destination.englishName = source.englishName
        destination.brandCode = source.brandCode
        destination.brandEnglishName = source.brandEnglishName
        destination.brandLogoImageURLString = source.brandLogoImageURLString
        destination.brandNationName = source.brandNationName
        destination.sourceCategoryPath = source.sourceCategoryPath
        destination.sourceCategoryDepth1 = source.sourceCategoryDepth1
        destination.sourceCategoryDepth2 = source.sourceCategoryDepth2
        destination.sourceCategoryDepth3 = source.sourceCategoryDepth3
        destination.sourceCategoryDepth4 = source.sourceCategoryDepth4
        destination.baseCategoryFullPath = source.baseCategoryFullPath
        destination.categoryDepth1Code = source.categoryDepth1Code
        destination.categoryDepth1Name = source.categoryDepth1Name
        destination.categoryDepth2Code = source.categoryDepth2Code
        destination.categoryDepth2Name = source.categoryDepth2Name
        destination.categoryDepth3Code = source.categoryDepth3Code
        destination.categoryDepth3Name = source.categoryDepth3Name
        destination.categoryDepth4Code = source.categoryDepth4Code
        destination.categoryDepth4Name = source.categoryDepth4Name
        destination.sizeType = source.sizeType
        destination.genderCodes = source.genderCodes
        destination.labelNames = source.labelNames
        destination.imageURLStrings = source.imageURLStrings
        destination.normalPrice = source.normalPrice
        destination.salePrice = source.salePrice
        destination.finalPrice = source.finalPrice
        destination.currencyCode = source.currencyCode
        destination.discountRate = source.discountRate
        destination.isSale = source.isSale
        destination.isOutOfStock = source.isOutOfStock
        destination.stockStatusRawValue = source.stockStatusRawValue
        destination.isRestock = source.isRestock
        destination.isSoonOutOfStock = source.isSoonOutOfStock
        destination.isLimitedQuantity = source.isLimitedQuantity
        destination.reviewCount = source.reviewCount
        destination.reviewSatisfactionScore = source.reviewSatisfactionScore
        destination.seasonYear = source.seasonYear
        destination.season = source.season
        destination.checkedColorName = source.checkedColorName
        destination.checkedSizeName = source.checkedSizeName
        destination.sourceTypeRawValue = source.sourceTypeRawValue
        destination.sourceName = source.sourceName
        destination.sourcePlatformCode = source.sourcePlatformCode
        destination.sourceRawValue = source.sourceRawValue
        destination.notes = source.notes
        destination.brand = source.brand
    }

    private static func makeHistoricalSizeProjection(
        from source: ProductSize,
        comparisonID: UUID,
        product: Product
    ) -> ProductSize {
        let projection = ProductSize(
            id: VNextHistoryProjectionIdentity.productSizeID(
                comparisonID: comparisonID,
                productSizeID: source.id
            ),
            name: source.name,
            measurements: source.measurements,
            displayOrder: source.displayOrder,
            product: product,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt
        )
        projection.measurementSchemaVersion = source.measurementSchemaVersion
        projection.measurementMigrationVersion = source.measurementMigrationVersion
        projection.measurementMigrationStatusRawValue = source.measurementMigrationStatusRawValue
        projection.measurementMigrationErrorCode = source.measurementMigrationErrorCode
        projection.measurementRecords = source.measurementRecords.map {
            copyMeasurementRecord($0, productSize: projection)
        }
        return projection
    }

    private static func makeHistoricalReferenceProjection(
        from source: UserFit,
        comparisonID: UUID
    ) -> UserFit {
        let projection = UserFit(
            id: VNextHistoryProjectionIdentity.referenceID(
                comparisonID: comparisonID,
                clientItemID: source.id
            ),
            sourceType: source.sourceType,
            sourceName: source.sourceName,
            sourceCategoryPath: source.sourceCategoryPath,
            sourceCategoryDepth1: source.sourceCategoryDepth1,
            sourceCategoryDepth2: source.sourceCategoryDepth2,
            sourceCategoryDepth3: source.sourceCategoryDepth3,
            sourceCategoryDepth4: source.sourceCategoryDepth4,
            brandName: source.brandName,
            gender: source.gender,
            productName: source.productName,
            category: source.category,
            detailCategory: source.detailCategory,
            sizeName: source.sizeName,
            measurements: source.measurements,
            fitMemo: source.fitMemo,
            fitPreference: source.fitPreference,
            satisfaction: source.satisfaction,
            isRepresentative: false,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt
        )
        projection.sourcePlatformCode = source.sourcePlatformCode
        projection.genderCode = source.genderCode
        projection.categoryCode = source.categoryCode
        projection.detailCategoryCode = source.detailCategoryCode
        projection.normalizedProductTypeCode = source.normalizedProductTypeCode
        projection.garmentTypeRawValue = source.garmentTypeRawValue
        projection.sleeveTypeRawValue = source.sleeveTypeRawValue
        projection.constructionTypeRawValue = source.constructionTypeRawValue
        projection.canonicalProfileSnapshotJSON = source.canonicalProfileSnapshotJSON
        projection.canonicalPolicyVersion = source.canonicalPolicyVersion
        projection.canonicalResolutionMethod = source.canonicalResolutionMethod
        projection.canonicalEligibility = false
        projection.fitPreferenceRawValue = source.fitPreferenceRawValue
        projection.measurementSchemaVersion = source.measurementSchemaVersion
        projection.measurementInputSourceRawValue = source.measurementInputSourceRawValue
        projection.measurementMigrationVersion = source.measurementMigrationVersion
        projection.measurementMigrationStatusRawValue = source.measurementMigrationStatusRawValue
        projection.measurementMigrationErrorCode = source.measurementMigrationErrorCode
        projection.measurementRecords = source.measurementRecords.map {
            copyMeasurementRecord($0, userFit: projection)
        }
        projection.markAsHistoryOnlyReferenceSnapshot(
            sourceIdentity: [
                "client_item_id=\(source.id.uuidString.lowercased())",
                "authority=\(source.canonicalSourceIdentity ?? "unknown")"
            ].joined(separator: ";")
        )
        return projection
    }

    private static func copyMeasurementRecord(
        _ source: GarmentMeasurementRecord,
        productSize: ProductSize? = nil,
        userFit: UserFit? = nil
    ) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(
            value: source.value,
            unit: MeasurementUnit(rawValue: source.unitRawValue) ?? .centimeter,
            measurementCode: source.measurementCode,
            displayKind: source.displayKind ?? .unknown,
            methodSource: source.methodSource,
            methodProfile: source.methodProfile,
            inputSource: MeasurementInputSource(rawValue: source.inputSourceRawValue)
                ?? .importedSizeChart,
            standardVersion: source.standardVersion,
            mappingVersion: source.mappingVersion,
            rawCode: source.rawCode,
            rawLabel: source.rawLabel,
            rawInfo: source.rawInfo,
            rawValueText: source.rawValueText,
            evidenceLevel: MeasurementEvidenceLevel(rawValue: source.evidenceLevelRawValue)
                ?? .unknown,
            semanticStatus: source.semanticStatus,
            productSize: productSize,
            userFit: userFit,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt
        )
    }

    static func saveUnique(
        _ history: RecommendationHistory,
        existing histories: [RecommendationHistory],
        modelContext: ModelContext
    ) throws {
        if history.comparisonSchemaVersion >= 2, history.calculationSnapshot == nil {
            throw RecommendationHistoryStoreError.missingCalculationSnapshot
        }
        let matchingHistories = histories.filter { isSameProduct($0.product, history.product) }
        let storedProducts = try modelContext.fetch(FetchDescriptor<Product>())
        let matchingProducts = storedProducts.filter { isSameProduct($0, history.product) }
        let storedUserFits = try modelContext.fetch(FetchDescriptor<UserFit>())
        let closetProductIDs = Set(storedUserFits.compactMap { $0.sourceProduct?.id })
        let recommendedSizeID = history.recommendedSize.id
        let storedSizeDescriptor = FetchDescriptor<ProductSize>(
            predicate: #Predicate { $0.id == recommendedSizeID }
        )
        let storedSizeByID = try modelContext.fetch(storedSizeDescriptor).first
        let storedProduct = storedSizeByID?.product
            ?? matchingProducts.first(where: { closetProductIDs.contains($0.id) })
            ?? matchingHistories.first?.product
            ?? matchingProducts.first
        var replacedTransientSize: ProductSize?
        var replacedTransientProduct: Product?

        if let storedProduct {
            let incomingProduct = history.product
            let incomingSize = history.recommendedSize
            storedProduct.refreshExternalPresentation(from: incomingProduct)
            let recommendedSizeKey = ParsedProductSizeNormalizer.normalizedSizeKey(for: history.recommendedSize.name)
            let storedSize = storedSizeByID ?? storedProduct.sizes.first {
                ParsedProductSizeNormalizer.normalizedSizeKey(for: $0.name) == recommendedSizeKey
            }

            history.product = storedProduct
            if let storedSize {
                history.recommendedSize = storedSize
                if incomingSize !== storedSize {
                    incomingSize.product = nil
                    replacedTransientSize = incomingSize
                }
            } else {
                let newSize = history.recommendedSize
                newSize.product = storedProduct
                storedProduct.sizes.append(newSize)
            }
            if incomingProduct !== storedProduct {
                incomingProduct.sizes.removeAll()
                replacedTransientProduct = incomingProduct
            }
        }

        matchingHistories.forEach(modelContext.delete)

        if let retainedProductID = history.product.modelContext == nil ? nil : Optional(history.product.id) {
            matchingProducts
                .filter { $0.id != retainedProductID && !closetProductIDs.contains($0.id) }
                .forEach(modelContext.delete)
        }

        if history.product.modelContext == nil {
            modelContext.insert(history.product)
        }
        modelContext.insert(history)
        if let replacedTransientSize, replacedTransientSize.modelContext != nil {
            modelContext.delete(replacedTransientSize)
        }
        if let replacedTransientProduct, replacedTransientProduct.modelContext != nil {
            modelContext.delete(replacedTransientProduct)
        }
        try modelContext.save()
    }

    private static func isSameProduct(_ lhs: Product, _ rhs: Product) -> Bool {
        if let lhsURL = normalizedURL(lhs.sourceURLString),
           let rhsURL = normalizedURL(rhs.sourceURLString) {
            return lhsURL == rhsURL
        }

        if let lhsCode = normalizedText(lhs.productCode), !lhsCode.isEmpty,
           let rhsCode = normalizedText(rhs.productCode), !rhsCode.isEmpty {
            return lhsCode == rhsCode
        }

        let lhsBrand = lhs.brand?.normalizedName ?? lhs.displayName.normalizedBrandName
        let rhsBrand = rhs.brand?.normalizedName ?? rhs.displayName.normalizedBrandName
        return lhsBrand == rhsBrand && lhs.name.normalizedBrandName == rhs.name.normalizedBrandName
    }

    private static func normalizedURL(_ value: String?) -> String? {
        guard var value = normalizedText(value)?.lowercased(), !value.isEmpty else { return nil }
        if value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private static func normalizedText(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RecommendationHistoryStoreError: Error {
    case missingCalculationSnapshot
    case invalidCompletedVNextHistory
    case vnextIdentityConflict
}

/// A hydrated History record remains immutable even when its source page is
/// no longer available. This is the production routing boundary used by the
/// History and Home surfaces, so a recompare tap either reaches an official
/// provider URL or gives the user a truthful next action.
enum FitMatchHistoryRecompareAction {
    enum StartRequest {
        case supportedURL(String)
        case storedOfficialProduct(Product)
    }

    enum Outcome {
        case openCompare(StartRequest)
        case unavailable(String)
    }

    static func outcome(for history: RecommendationHistory) -> Outcome {
        if let raw = history.product.sourceURLString?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
           let url = URL(string: raw),
           FitMatchProductURLRouting.provider(for: url) != nil {
            return .openCompare(.supportedURL(url.absoluteString))
        }

        // Some older immutable server History rows did not project a canonical
        // browser URL.  A stored official product identity can still enter the
        // existing server resolver without manufacturing a retailer URL.
        guard hasSupportedOfficialIdentity(history.product),
              history.product.fitMatchDatabaseResolutionRequest() != nil else {
            return .unavailable(
                "이 비교 기록의 상품 정보를 다시 불러올 수 없어요. 상품 링크를 다시 열어 주세요."
            )
        }
        return .openCompare(.storedOfficialProduct(history.product))
    }

    private static func hasSupportedOfficialIdentity(_ product: Product) -> Bool {
        let sourceCode = product.sourcePlatformCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if ["uniqlo", "musinsa", "zara"].contains(sourceCode) {
            return true
        }

        let sourceName = product.sourceName.lowercased()
        return sourceName.contains("uniqlo")
            || sourceName.contains("유니클로")
            || sourceName.contains("musinsa")
            || sourceName.contains("무신사")
            || sourceName.contains("zara")
    }
}
