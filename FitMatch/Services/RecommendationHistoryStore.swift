import Foundation
import SwiftData

enum RecommendationHistoryStore {
    static func saveUnique(
        _ history: RecommendationHistory,
        existing histories: [RecommendationHistory],
        modelContext: ModelContext
    ) throws {
        histories
            .filter { isSameProduct($0.product, history.product) }
            .forEach(modelContext.delete)

        modelContext.insert(history.product)
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
