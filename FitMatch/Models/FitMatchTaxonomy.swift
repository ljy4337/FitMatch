import Foundation

struct FitMatchTaxonomy: Codable, Equatable {
    let schemaVersion: Int
    let taxonomyVersion: String
    let genders: [TaxonomyOption]
    let categories: [TaxonomyCategory]
    let normalizedProductTypes: [TaxonomyNormalizedProductType]
    let legacyAliases: [TaxonomyLegacyAlias]
}

struct TaxonomyOption: Codable, Equatable, Hashable, Identifiable {
    let code: String
    let displayName: String
    let sortOrder: Int
    let isActive: Bool

    var id: String { code }
}

struct TaxonomyCategory: Codable, Equatable, Hashable, Identifiable {
    let code: String
    let displayName: String
    let sortOrder: Int
    let isActive: Bool
    let details: [TaxonomyOption]

    var id: String { code }
}

struct TaxonomyNormalizedProductType: Codable, Equatable, Hashable, Identifiable {
    let code: String
    let categoryCode: String
    let displayName: String
    let sortOrder: Int
    let isActive: Bool

    var id: String { code }
}

struct TaxonomyLegacyAlias: Codable, Equatable, Hashable {
    enum AliasType: String, Codable { case gender, category, detailCategory }

    let type: AliasType
    let value: String
    let categoryCode: String?
    let targetCode: String
}

protocol FitMatchTaxonomyProviding {
    func loadTaxonomy() throws -> FitMatchTaxonomy
}

enum FitMatchTaxonomyRepositoryError: Error {
    case bundledTaxonomyMissing
}

struct BundledFitMatchTaxonomyRepository: FitMatchTaxonomyProviding {
    let bundle: Bundle
    let decoder: JSONDecoder

    init(bundle: Bundle = .main, decoder: JSONDecoder = JSONDecoder()) {
        self.bundle = bundle
        self.decoder = decoder
    }

    func loadTaxonomy() throws -> FitMatchTaxonomy {
        guard let url = bundle.url(forResource: "FitMatchTaxonomy", withExtension: "json") else {
            throw FitMatchTaxonomyRepositoryError.bundledTaxonomyMissing
        }
        return try decoder.decode(FitMatchTaxonomy.self, from: Data(contentsOf: url))
    }
}

struct DataFitMatchTaxonomyRepository: FitMatchTaxonomyProviding {
    let data: Data

    func loadTaxonomy() throws -> FitMatchTaxonomy {
        try JSONDecoder().decode(FitMatchTaxonomy.self, from: data)
    }
}

final class FitMatchTaxonomyProvider {
    static let shared = FitMatchTaxonomyProvider()

    let taxonomy: FitMatchTaxonomy
    let loadingError: Error?

    init(repository: FitMatchTaxonomyProviding = BundledFitMatchTaxonomyRepository()) {
        do {
            taxonomy = try repository.loadTaxonomy()
            loadingError = nil
        } catch {
            taxonomy = Self.safeFallback
            loadingError = error
        }
    }

    var selectableGenders: [TaxonomyOption] {
        taxonomy.genders.filter { $0.isActive && $0.code != "unknown" }.sorted {
            ($0.sortOrder, $0.code) < ($1.sortOrder, $1.code)
        }
    }

    var activeCategories: [TaxonomyCategory] {
        taxonomy.categories.filter(\.isActive).sorted {
            ($0.sortOrder, $0.code) < ($1.sortOrder, $1.code)
        }
    }

    func activeDetails(categoryCode: String) -> [TaxonomyOption] {
        taxonomy.categories.first { $0.code == categoryCode }?.details
            .filter(\.isActive)
            .sorted { ($0.sortOrder, $0.code) < ($1.sortOrder, $1.code) } ?? []
    }

    func genderCode(for legacyValue: String) -> String? {
        resolveAlias(.gender, value: legacyValue, categoryCode: nil)
            ?? taxonomy.genders.first { $0.displayName == legacyValue || $0.code == legacyValue }?.code
    }

    func categoryCode(for legacyValue: String) -> String? {
        resolveAlias(.category, value: legacyValue, categoryCode: nil)
            ?? taxonomy.categories.first { $0.displayName == legacyValue || $0.code == legacyValue }?.code
    }

    func detailCode(for legacyValue: String, categoryCode: String) -> String? {
        resolveAlias(.detailCategory, value: legacyValue, categoryCode: categoryCode)
            ?? activeDetails(categoryCode: categoryCode).first { $0.displayName == legacyValue || $0.code == legacyValue }?.code
    }

    func displayName(forGender code: String) -> String? {
        taxonomy.genders.first { $0.code == code }?.displayName
    }

    func displayName(forCategory code: String) -> String? {
        taxonomy.categories.first { $0.code == code }?.displayName
    }

    func displayName(forDetail code: String, categoryCode: String) -> String? {
        taxonomy.categories.first { $0.code == categoryCode }?.details.first { $0.code == code }?.displayName
    }

    func normalizedProductTypeCode(sourceCategoryPath: String?, categoryCode: String?) -> String? {
        let source = sourceCategoryPath?.lowercased() ?? ""
        guard categoryCode == "tops" else { return nil }
        if ["니트", "스웨터", "knit", "sweater"].contains(where: source.contains) {
            return "tops.knit_sweater"
        }
        if ["티셔츠", "t-shirt", "tshirt"].contains(where: source.contains) {
            return "tops.tshirt"
        }
        return nil
    }

    func sourcePlatformCode(sourceName: String, sourceURLString: String? = nil) -> String? {
        let value = "\(sourceName) \(sourceURLString ?? "")".lowercased()
        if value.contains("musinsa") || value.contains("무신사") { return "musinsa" }
        if value.contains("uniqlo") || value.contains("유니클로") { return "uniqlo" }
        return nil
    }

    func isValidDetail(_ detailCode: String?, for categoryCode: String?) -> Bool {
        guard let detailCode, let categoryCode else { return false }
        return activeDetails(categoryCode: categoryCode).contains { $0.code == detailCode }
    }

    func isActiveCategory(_ categoryCode: String?) -> Bool {
        guard let categoryCode else { return false }
        return activeCategories.contains { $0.code == categoryCode }
    }

    private func resolveAlias(_ type: TaxonomyLegacyAlias.AliasType, value: String, categoryCode: String?) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return taxonomy.legacyAliases.first {
            $0.type == type
                && $0.value.lowercased() == normalized
                && ($0.categoryCode == nil || $0.categoryCode == categoryCode)
        }?.targetCode
    }

    static let safeFallback = FitMatchTaxonomy(
        schemaVersion: 1,
        taxonomyVersion: "fallback",
        genders: [
            .init(code: "male", displayName: "남성", sortOrder: 0, isActive: true),
            .init(code: "female", displayName: "여성", sortOrder: 1, isActive: true),
            .init(code: "unisex", displayName: "공용", sortOrder: 2, isActive: true),
            .init(code: "unknown", displayName: "미분류", sortOrder: 99, isActive: true)
        ],
        categories: [
            .init(code: "tops", displayName: "상의", sortOrder: 0, isActive: true, details: [
                .init(code: "sleeveless", displayName: "민소매", sortOrder: 0, isActive: true),
                .init(code: "short_sleeve", displayName: "반팔", sortOrder: 1, isActive: true),
                .init(code: "long_sleeve", displayName: "긴팔", sortOrder: 3, isActive: true)
            ]),
            .init(code: "bottoms", displayName: "하의", sortOrder: 1, isActive: true, details: [
                .init(code: "shorts", displayName: "반바지", sortOrder: 1, isActive: true),
                .init(code: "long_pants", displayName: "긴바지", sortOrder: 5, isActive: true)
            ])
        ],
        normalizedProductTypes: [],
        legacyAliases: []
    )
}
