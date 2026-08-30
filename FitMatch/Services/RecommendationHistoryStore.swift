import Foundation
import SwiftData

enum RecommendationHistoryStore {
    /// Persists a server-completed vNext comparison without invoking any of
    /// the legacy presentation-identity fallbacks. Server UUIDs are the sole
    /// product, size, and immutable history identities on this path.
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
        let productID = incomingProduct.id
        let recommendedSizeID = history.recommendedSize.id
        let productDescriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.id == productID }
        )
        let storedProduct = try modelContext.fetch(productDescriptor).first
        let storedSizes = try modelContext.fetch(FetchDescriptor<ProductSize>())
        let storedSizesByID = Dictionary(
            uniqueKeysWithValues: storedSizes.map { ($0.id, $0) }
        )

        if let storedProduct {
            let incomingSizes = Array(incomingProduct.sizes)
            storedProduct.refreshExternalPresentation(from: incomingProduct)

            for incomingSize in incomingSizes {
                if let exactStoredSize = storedSizesByID[incomingSize.id] {
                    guard exactStoredSize.product?.id == productID else {
                        throw RecommendationHistoryStoreError.vnextIdentityConflict
                    }
                    continue
                }
                incomingSize.product = storedProduct
                if !storedProduct.sizes.contains(where: { $0.id == incomingSize.id }) {
                    storedProduct.sizes.append(incomingSize)
                }
            }

            guard let exactRecommendedSize = storedProduct.sizes.first(where: {
                $0.id == recommendedSizeID
            }) else {
                throw RecommendationHistoryStoreError.vnextIdentityConflict
            }
            history.product = storedProduct
            history.recommendedSize = exactRecommendedSize
        } else {
            if storedSizesByID[recommendedSizeID] != nil {
                throw RecommendationHistoryStoreError.vnextIdentityConflict
            }
            guard incomingProduct.sizes.contains(where: { $0.id == recommendedSizeID }) else {
                throw RecommendationHistoryStoreError.vnextIdentityConflict
            }
            if incomingProduct.modelContext == nil {
                modelContext.insert(incomingProduct)
            }
        }

        modelContext.insert(history)
        try modelContext.save()
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
