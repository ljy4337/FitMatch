import Foundation
import SwiftData

enum RecommendationHistoryStore {
    static func saveUnique(
        _ history: RecommendationHistory,
        existing histories: [RecommendationHistory],
        modelContext: ModelContext
    ) throws {
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

        if let storedProduct {
            let recommendedSizeKey = ParsedProductSizeNormalizer.normalizedSizeKey(for: history.recommendedSize.name)
            let storedSize = storedSizeByID ?? storedProduct.sizes.first {
                ParsedProductSizeNormalizer.normalizedSizeKey(for: $0.name) == recommendedSizeKey
            }

            history.product = storedProduct
            if let storedSize {
                history.recommendedSize = storedSize
            } else {
                let newSize = history.recommendedSize
                newSize.product = storedProduct
                storedProduct.sizes.append(newSize)
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
