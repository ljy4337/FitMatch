import Foundation

struct SourceCategoryHistoryMatch: Identifiable, Hashable {
    let category: ClothingCategory
    let detailCategory: ClosetDetailCategory
    let count: Int

    var id: String {
        "\(category.rawValue)|\(detailCategory.rawValue)"
    }

    var title: String {
        "\(detailCategory.rawValue) \(count)개"
    }

    var subtitle: String {
        category.rawValue
    }
}

enum SourceCategoryHistoryMatcher {
    static func matches(for product: Product, userFits: [UserFit]) -> [SourceCategoryHistoryMatch] {
        if let storedMatch = storedMatch(for: product) {
            return [storedMatch]
        }

        let eligibleItems = userFits.filter {
            $0.category != .other && $0.detailCategory != .other
        }

        let depthMatches = matchesByDepth(for: product, userFits: eligibleItems)
        if !depthMatches.isEmpty {
            return groupedMatches(from: depthMatches)
        }

        return groupedMatches(from: matchesByPathFallback(for: product, userFits: eligibleItems))
    }

    static func saveMapping(
        for product: Product,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory
    ) {
        guard category != .other, detailCategory != .other else { return }
        guard let key = depthKey(for: product) ?? pathKey(for: product) else { return }

        var mappings = storedMappings()
        mappings[key] = StoredSourceCategoryMapping(
            categoryRawValue: category.rawValue,
            detailCategoryRawValue: detailCategory.rawValue
        )
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        UserDefaults.standard.set(data, forKey: mappingStoreKey)
    }

    private static func matchesByDepth(for product: Product, userFits: [UserFit]) -> [UserFit] {
        guard let productKey = sourceDepthKey(
            sourceTypeRawValue: product.sourceTypeRawValue,
            sourceName: product.sourceName,
            depths: [
                product.sourceCategoryDepth1,
                product.sourceCategoryDepth2,
                product.sourceCategoryDepth3,
                product.sourceCategoryDepth4
            ]
        ) else {
            return []
        }

        return userFits.filter { item in
            sourceDepthKey(
                sourceTypeRawValue: item.sourceTypeRawValue,
                sourceName: item.sourceName,
                depths: [
                    item.sourceCategoryDepth1,
                    item.sourceCategoryDepth2,
                    item.sourceCategoryDepth3,
                    item.sourceCategoryDepth4
                ]
            ) == productKey
        }
    }

    private static func matchesByPathFallback(for product: Product, userFits: [UserFit]) -> [UserFit] {
        guard let productKey = sourcePathKey(
            sourceTypeRawValue: product.sourceTypeRawValue,
            sourceName: product.sourceName,
            sourceCategoryPath: product.sourceCategoryPath
        ) else {
            return []
        }

        return userFits.filter { item in
            sourcePathKey(
                sourceTypeRawValue: item.sourceTypeRawValue,
                sourceName: item.sourceName,
                sourceCategoryPath: item.sourceCategoryPath
            ) == productKey
        }
    }

    private static func groupedMatches(from items: [UserFit]) -> [SourceCategoryHistoryMatch] {
        let grouped = Dictionary(grouping: items) { item in
            CategoryPair(category: item.category, detailCategory: item.detailCategory)
        }

        return grouped
            .map { pair, items in
                SourceCategoryHistoryMatch(
                    category: pair.category,
                    detailCategory: pair.detailCategory,
                    count: items.count
                )
            }
            .sorted {
                if $0.count != $1.count {
                    return $0.count > $1.count
                }
                if $0.category.rawValue != $1.category.rawValue {
                    return $0.category.rawValue.localizedCompare($1.category.rawValue) == .orderedAscending
                }
                return $0.detailCategory.rawValue.localizedCompare($1.detailCategory.rawValue) == .orderedAscending
            }
    }

    private static let mappingStoreKey = "FitMatch.sourceCategoryMappings"

    private static func storedMatch(for product: Product) -> SourceCategoryHistoryMatch? {
        let mappings = storedMappings()
        guard let key = depthKey(for: product) ?? pathKey(for: product),
              let mapping = mappings[key],
              let category = ClothingCategory(rawValue: mapping.categoryRawValue),
              let detailCategory = ClosetDetailCategory(rawValue: mapping.detailCategoryRawValue) else {
            return nil
        }

        return SourceCategoryHistoryMatch(category: category, detailCategory: detailCategory, count: 1)
    }

    private static func storedMappings() -> [String: StoredSourceCategoryMapping] {
        guard let data = UserDefaults.standard.data(forKey: mappingStoreKey),
              let mappings = try? JSONDecoder().decode([String: StoredSourceCategoryMapping].self, from: data) else {
            return [:]
        }
        return mappings
    }

    private static func depthKey(for product: Product) -> String? {
        sourceDepthKey(
            sourceTypeRawValue: product.sourceTypeRawValue,
            sourceName: product.sourceName,
            depths: [
                product.sourceCategoryDepth1,
                product.sourceCategoryDepth2,
                product.sourceCategoryDepth3,
                product.sourceCategoryDepth4
            ]
        )
    }

    private static func pathKey(for product: Product) -> String? {
        sourcePathKey(
            sourceTypeRawValue: product.sourceTypeRawValue,
            sourceName: product.sourceName,
            sourceCategoryPath: product.sourceCategoryPath
        )
    }

    nonisolated private static func sourceDepthKey(
        sourceTypeRawValue: String,
        sourceName: String,
        depths: [String?]
    ) -> String? {
        let normalizedDepths = depths
            .compactMap(normalizedCategoryComponent)
            .filter { !isTargetGenderToken($0) }

        guard !normalizedDepths.isEmpty else {
            return nil
        }

        return [
            normalizedSourceComponent(sourceTypeRawValue),
            normalizedSourceComponent(sourceName),
            normalizedDepths.joined(separator: ">")
        ].joined(separator: "|")
    }

    nonisolated private static func sourcePathKey(
        sourceTypeRawValue: String,
        sourceName: String,
        sourceCategoryPath: String?
    ) -> String? {
        guard let normalizedPath = normalizedCategoryPath(sourceCategoryPath),
              !normalizedPath.isEmpty else {
            return nil
        }

        return [
            normalizedSourceComponent(sourceTypeRawValue),
            normalizedSourceComponent(sourceName),
            normalizedPath
        ].joined(separator: "|")
    }

    nonisolated private static func normalizedCategoryPath(_ value: String?) -> String? {
        guard let value else { return nil }

        let parts = value
            .components(separatedBy: CharacterSet(charactersIn: ">/"))
            .compactMap(normalizedCategoryComponent)
            .filter { !isTargetGenderToken($0) }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: ">")
    }

    nonisolated private static func normalizedCategoryComponent(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = decodeHTMLEntities(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return normalized.isEmpty ? nil : normalized
    }

    nonisolated private static func normalizedSourceComponent(_ value: String) -> String {
        normalizedCategoryComponent(value) ?? ""
    }

    nonisolated private static func isTargetGenderToken(_ value: String) -> Bool {
        [
            "men", "man", "male", "m", "남성",
            "women", "woman", "female", "f", "여성",
            "kids", "kid", "키즈",
            "baby", "베이비",
            "unisex", "common", "공용"
        ].contains(value)
    }

    nonisolated private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

private struct StoredSourceCategoryMapping: Codable {
    let categoryRawValue: String
    let detailCategoryRawValue: String
}

private struct CategoryPair: Hashable {
    let category: ClothingCategory
    let detailCategory: ClosetDetailCategory
}
