import Foundation

/// Canonical parser output used at Closet/Compare boundaries. Stable taxonomy
/// codes remain independent from source garment structure and length attributes.
struct ParsedClosetClassification: Equatable {
    let categoryCode: String
    let detailCode: String
    let category: ClothingCategory
    let detailCategory: ClosetDetailCategory
    let normalizedProductTypeCode: String?
    let garmentFamily: ComparisonGarmentFamily
    let lengthType: ComparisonLengthType
    let constructionType: ComparisonConstructionType

    var isValid: Bool {
        let provider = FitMatchTaxonomyProvider.shared
        return provider.isActiveCategory(categoryCode)
            && provider.isValidDetail(detailCode, for: categoryCode)
            && Self.isConsistent(category: category, detailCategory: detailCategory,
                                 categoryCode: categoryCode, detailCode: detailCode)
    }

    static func resolve(
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        sourceDepths: [String?],
        sourcePath: String?,
        productName: String,
        normalizedProductTypeCode: String? = nil,
        garmentFamily: ComparisonGarmentFamily = .unknown,
        lengthType: ComparisonLengthType = .unknown,
        constructionType: ComparisonConstructionType = .unknown
    ) -> ParsedClosetClassification? {
        let depths = sourceDepths.compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let source = (depths.isEmpty ? (sourcePath ?? "") : depths.joined(separator: " > ")).lowercased()
        let specificSource = mostSpecificCategorySource(in: depths, fallback: source)
        let name = productName.lowercased()
        let combined = "\(source) \(name) \(detailCategory.rawValue.lowercased())"

        let resolvedCategoryCode: String
        let resolvedDetailCode: String
        let resolvedCategory: ClothingCategory
        let resolvedDetail: ClosetDetailCategory

        // Exact source families are evaluated before generic words such as 하의/원피스.
        if specificSource.contains("스커트") || specificSource.contains("skirt") {
            resolvedCategoryCode = "skirts"; resolvedDetailCode = "skirt"
            resolvedCategory = .bottom; resolvedDetail = .skirt
        } else if specificSource.contains("원피스") || specificSource.contains("dress") {
            resolvedCategoryCode = "dresses"; resolvedDetailCode = "one_piece"
            resolvedCategory = .dress; resolvedDetail = .onePiece
        } else if specificSource.contains("여성 속옷 하의") || specificSource.contains("팬티") || specificSource.contains("panty") {
            resolvedCategoryCode = "underwear"; resolvedDetailCode = "women_panty"
            resolvedCategory = .underwear; resolvedDetail = .womenPanty
        } else if specificSource.contains("홈웨어") || specificSource.contains("homewear") || specificSource.contains("loungewear") {
            resolvedCategoryCode = "homewear"; resolvedDetailCode = "loungewear"
            resolvedCategory = .other; resolvedDetail = .loungewear
        } else {
            resolvedCategoryCode = category.serviceGroup.taxonomyCode
            resolvedCategory = category.serviceGroup
            let inferredDetail = canonicalDetailCode(categoryCode: resolvedCategoryCode,
                                                     detail: detailCategory,
                                                     text: combined,
                                                     sourceText: source)
            guard let inferredDetail else { return nil }
            resolvedDetailCode = inferredDetail
            resolvedDetail = ClosetDetailCategory.fromTaxonomyCode(inferredDetail)
        }

        let provider = FitMatchTaxonomyProvider.shared
        guard provider.isValidDetail(resolvedDetailCode, for: resolvedCategoryCode) else { return nil }
        let normalized = normalizedProductTypeCode ?? provider.normalizedProductTypeCode(
            sourceCategoryPath: sourcePath ?? source,
            categoryCode: resolvedCategoryCode
        )
        let family = garmentFamily == .unknown ? inferredFamily(from: source, categoryCode: resolvedCategoryCode) : garmentFamily
        let length = lengthType == .unknown ? inferredLength(from: combined, detailCode: resolvedDetailCode) : lengthType
        return .init(categoryCode: resolvedCategoryCode, detailCode: resolvedDetailCode,
                     category: resolvedCategory, detailCategory: resolvedDetail,
                     normalizedProductTypeCode: normalized, garmentFamily: family,
                     lengthType: length, constructionType: constructionType)
    }

    static func resolve(product: Product, detailCategory: ClosetDetailCategory) -> ParsedClosetClassification? {
        resolve(category: product.category, detailCategory: detailCategory,
                sourceDepths: [product.sourceCategoryDepth1, product.sourceCategoryDepth2,
                               product.sourceCategoryDepth3, product.sourceCategoryDepth4],
                sourcePath: product.sourceCategoryPath, productName: product.name,
                normalizedProductTypeCode: product.resolvedNormalizedProductTypeCode,
                garmentFamily: product.garmentType, lengthType: product.sleeveType,
                constructionType: product.constructionType)
    }

    static func isConsistent(category: ClothingCategory, detailCategory: ClosetDetailCategory,
                             categoryCode: String, detailCode: String) -> Bool {
        ClothingCategory.fromTaxonomyCode(categoryCode).serviceGroup == category.serviceGroup
            && ClosetDetailCategory.fromTaxonomyCode(detailCode) == detailCategory
    }

    private static func canonicalDetailCode(categoryCode: String, detail: ClosetDetailCategory,
                                            text: String, sourceText: String) -> String? {
        switch categoryCode {
        case "tops":
            if containsAny(text, ["민소매", "나시", "슬리브리스", "sleeveless", "tank"]) { return "sleeveless" }
            if containsAny(text, ["반팔", "반소매", "숏슬리브", "short sleeve"]) { return "short_sleeve" }
            if containsAny(text, ["긴팔", "긴소매", "롱슬리브", "long sleeve"]) { return "long_sleeve" }
        case "bottoms":
            if containsAny(sourceText, ["숏 팬츠", "쇼트 팬츠", "반바지", "쇼츠", "버뮤다", "shorts", "short pants"]) { return "shorts" }
            if containsAny(text, ["긴바지", "롱 팬츠", "long pants"]) { return "long_pants" }
        case "outerwear":
            let mappings: [(String, [String])] = [
                ("padded_vest", ["패딩조끼"]), ("cardigan", ["가디건", "cardigan"]),
                ("blazer", ["블레이저", "blazer"]), ("blouson", ["블루종", "blouson"]),
                ("padding", ["패딩", "파카", "padding", "parka"]), ("vest", ["베스트", "조끼", "vest"]),
                ("jacket", ["재킷", "자켓", "jacket"]), ("coat", ["코트", "coat"]),
                ("jumper", ["점퍼", "jumper"])
            ]
            if let match = mappings.first(where: { containsAny(sourceText, $0.1) }) { return match.0 }
        default: break
        }
        let fallback = FitMatchTaxonomyProvider.shared.detailCode(for: detail.rawValue, categoryCode: categoryCode)
        return FitMatchTaxonomyProvider.shared.isValidDetail(fallback, for: categoryCode) ? fallback : nil
    }

    private static func inferredFamily(from source: String, categoryCode: String) -> ComparisonGarmentFamily {
        if containsAny(source, ["니트", "스웨터", "가디건", "knit", "sweater", "cardigan"]) { return .knitCardigan }
        if containsAny(source, ["티셔츠", "t-shirt", "tshirt"]) { return .tshirt }
        if containsAny(source, ["셔츠", "블라우스", "shirt", "blouse"]) { return .shirt }
        if containsAny(source, ["데님", "청바지", "denim", "jeans"]) { return .denim }
        switch categoryCode {
        case "bottoms", "leggings": return .pants
        case "skirts": return .skirt
        case "outerwear": return .outerwear
        case "underwear", "homewear": return .underwear
        case "dresses": return .dress
        default: return .unknown
        }
    }

    private static func inferredLength(from text: String, detailCode: String) -> ComparisonLengthType {
        if containsAny(text, ["민소매", "나시", "슬리브리스", "sleeveless"]) { return .sleeveless }
        if containsAny(text, ["반팔", "반소매", "숏슬리브", "short sleeve", "쇼츠", "숏 팬츠", "반바지"]) { return .short }
        if containsAny(text, ["긴팔", "긴소매", "롱슬리브", "long sleeve", "긴바지", "롱 팬츠"]) { return .long }
        if ["sleeveless"].contains(detailCode) { return .sleeveless }
        if ["short_sleeve", "short_pants", "shorts", "short_leggings"].contains(detailCode) { return .short }
        if ["long_sleeve", "long_pants", "long_leggings"].contains(detailCode) { return .long }
        return .unknown
    }

    private static func containsAny(_ text: String, _ values: [String]) -> Bool {
        values.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func mostSpecificCategorySource(in depths: [String], fallback: String) -> String {
        let umbrellaValues = ["원피스/스커트", "원피스 & 스커트", "속옷/홈웨어", "속옷 & 홈웨어"]
        let categoryWords = ["스커트", "skirt", "원피스", "dress", "여성 속옷 하의", "팬티", "panty",
                             "홈웨어", "homewear", "loungewear"]
        if let value = depths.reversed().first(where: { depth in
            containsAny(depth, categoryWords) && !umbrellaValues.contains {
                depth.localizedCaseInsensitiveContains($0)
                    && depth.trimmingCharacters(in: .whitespacesAndNewlines).count <= $0.count + 2
            }
        }) {
            return value.lowercased()
        }
        return umbrellaValues.contains(where: fallback.localizedCaseInsensitiveContains) ? "" : fallback
    }
}
