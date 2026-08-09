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
        } else if specificSource.contains("레깅스") || specificSource.contains("leggings") {
            resolvedCategoryCode = "leggings"
            if containsAny(combined, [
                "6부", "7부", "8부", "카프리", "capri", "three quarter", "3/4"
            ]) {
                resolvedDetailCode = "three_quarter_leggings"
            } else if containsAny(combined, ["9부", "ankle"]) {
                resolvedDetailCode = "nine_tenths_leggings"
            } else if containsAny(combined, [
                "숏", "쇼트", "short", "쇼츠", "바이커",
                "3부", "3.5부", "4부", "4.5부", "5부",
                "하프 타이즈", "하프타이즈", "하프 타이츠", "하프타이츠"
            ]) {
                resolvedDetailCode = "short_leggings"
            } else {
                resolvedDetailCode = "long_leggings"
            }
            resolvedCategory = .bottom
            resolvedDetail = ClosetDetailCategory.fromTaxonomyCode(resolvedDetailCode)
        } else if specificSource.contains("원피스") || specificSource.contains("dress") {
            resolvedCategoryCode = "dresses"; resolvedDetailCode = "one_piece"
            resolvedCategory = .dress; resolvedDetail = .onePiece
        } else if specificSource.contains("여성 속옷 하의") || specificSource.contains("팬티") || specificSource.contains("panty") {
            resolvedCategoryCode = "underwear"; resolvedDetailCode = "women_panty"
            resolvedCategory = .underwear; resolvedDetail = .womenPanty
        } else if containsAny(specificSource, ["브라", "bra"]) {
            resolvedCategoryCode = "underwear"; resolvedDetailCode = "women_bra"
            resolvedCategory = .underwear; resolvedDetail = .womenBra
        } else if containsAny(specificSource, ["여성 속옷", "남성 속옷", "underwear"]) {
            resolvedCategoryCode = "underwear"
            let providerDetail = FitMatchTaxonomyProvider.shared.detailCode(
                for: detailCategory.rawValue,
                categoryCode: resolvedCategoryCode
            )
            if let providerDetail,
               FitMatchTaxonomyProvider.shared.isValidDetail(providerDetail, for: resolvedCategoryCode) {
                resolvedDetailCode = providerDetail
            } else {
                resolvedDetailCode = "underwear"
            }
            resolvedCategory = .underwear
            resolvedDetail = ClosetDetailCategory.fromTaxonomyCode(resolvedDetailCode)
        } else if containsAny(combined, [
            "홈웨어", "라운지", "파자마", "잠옷", "homewear", "loungewear", "pajama", "pyjama"
        ]) {
            resolvedCategoryCode = "homewear"; resolvedDetailCode = "loungewear"
            resolvedCategory = .other; resolvedDetail = .loungewear
        } else if let explicitOuterwearDetail = crossCategoryOuterwearDetail(in: name),
                  category.serviceGroup != .outer {
            // 공급사 경로와 상품 종류가 충돌할 때도 코치재킷·윈드브레이커처럼
            // 의미가 명확한 상품명은 티셔츠 등 다른 대분류로 저장하지 않는다.
            resolvedCategoryCode = "outerwear"
            resolvedDetailCode = explicitOuterwearDetail
            resolvedCategory = .outer
            resolvedDetail = ClosetDetailCategory.fromTaxonomyCode(explicitOuterwearDetail)
        } else {
            resolvedCategoryCode = category.serviceGroup.taxonomyCode
            resolvedCategory = category.serviceGroup
            let sourceOuterwearDetail = resolvedCategoryCode == "outerwear"
                ? deepestOuterwearDetail(in: depths)
                : nil
            let explicitNameOuterwearDetail = resolvedCategoryCode == "outerwear"
                ? explicitOuterwearDetail(in: name)
                : nil
            let preferredNameOuterwearDetail = preferredOuterwearNameDetail(
                explicitNameOuterwearDetail,
                over: sourceOuterwearDetail
            )
            let inferredDetail = resolvedCategoryCode == "outerwear"
                ? preferredNameOuterwearDetail
                    ?? (sourceOuterwearDetail == "other_outerwear" ? nil : sourceOuterwearDetail)
                    ?? canonicalDetailCode(categoryCode: resolvedCategoryCode,
                                           detail: detailCategory,
                                           text: combined,
                                           sourceText: source,
                                           productNameText: name)
                : canonicalDetailCode(categoryCode: resolvedCategoryCode,
                                      detail: detailCategory,
                                      text: combined,
                                      sourceText: source,
                                      productNameText: name)
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
        let family = garmentFamily == .unknown
            ? inferredFamily(from: source, productName: name, categoryCode: resolvedCategoryCode)
            : garmentFamily
        let length = lengthType == .unknown
            ? inferredLength(
                from: combined,
                detailCode: resolvedDetailCode,
                categoryCode: resolvedCategoryCode
            )
            : lengthType
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
                                            text: String, sourceText: String,
                                            productNameText: String) -> String? {
        switch categoryCode {
        case "tops":
            if let productDetail = explicitTopLengthDetail(in: productNameText) { return productDetail }
            if containsAny(productNameText, [
                "스웨트셔츠", "스웨트 셔츠", "스웨트후디", "스웨트 후디",
                "맨투맨", "후디", "hoodie", "sweatshirt"
            ]) { return "other_tops" }
            let sourceHasShort = containsAny(sourceText, ["반팔", "반소매", "숏슬리브", "short sleeve"])
            let sourceHasLong = containsAny(sourceText, ["긴팔", "긴소매", "롱슬리브", "long sleeve"])
            if sourceHasShort != sourceHasLong { return sourceHasShort ? "short_sleeve" : "long_sleeve" }
            if containsAny(sourceText, ["민소매", "나시", "슬리브리스", "sleeveless", "tank"]) { return "sleeveless" }
            if containsAny(sourceText, ["7부", "three quarter", "3/4 sleeve"]) { return "three_quarter_sleeve" }
            if containsAny(sourceText, ["cut & sewn", "cut and sewn"]) { return "short_sleeve" }
            let providerDetail = FitMatchTaxonomyProvider.shared.detailCode(
                for: detail.rawValue,
                categoryCode: categoryCode
            )
            if providerDetail != "other_tops",
               FitMatchTaxonomyProvider.shared.isValidDetail(providerDetail, for: categoryCode) {
                return providerDetail
            }
            return "other_tops"
        case "bottoms":
            if containsAny(text, [
                "숏 팬츠", "숏팬츠", "쇼트 팬츠", "쇼트팬츠",
                "반바지", "쇼츠", "버뮤다", "큐롯", "culotte", "culottes",
                "shorts", "short pants",
                "3부", "3.5부", "4부", "4.5부", "5부"
            ]) { return "shorts" }
            if containsAny(text, ["크롭", "cropped", "카프리", "capri"]) { return "cropped_pants" }
            if containsAny(text, ["6부", "7부", "8부", "three quarter", "3/4 pants"]) { return "three_quarter_pants" }
            if containsAny(text, ["9부", "ankle", "nine tenths"]) { return "nine_tenths_pants" }
            if containsAny(text, ["점프 슈트", "점프수트", "오버올", "jumpsuit", "overall"]) {
                return "other_bottoms"
            }
            if containsAny(text, ["조거팬츠", "조거 팬츠", "팬츠", "바지", "pants", "trousers"]) {
                return "long_pants"
            }
            if containsAny(sourceText, ["기타 하의"]) {
                return containsAny(text, ["팬츠", "바지", "pants", "trousers"])
                    ? "long_pants"
                    : "other_bottoms"
            }
            if containsAny(sourceText, [
                "데님 팬츠", "코튼 팬츠", "트레이닝", "조거 팬츠",
                "슈트 팬츠", "슬랙스", "진(청바지)", "청바지",
                "팬츠", "바지", "denim", "jeans", "pants", "trousers"
            ]) { return "long_pants" }
            if containsAny(text, ["긴바지", "롱 팬츠", "long pants"]) { return "long_pants" }
            return "other_bottoms"
        case "outerwear":
            if let detail = outerwearDetail(in: text) { return detail }
            return "other_outerwear"
        case "underwear":
            let mapped = FitMatchTaxonomyProvider.shared.detailCode(
                for: detail.rawValue,
                categoryCode: categoryCode
            )
            return FitMatchTaxonomyProvider.shared.isValidDetail(mapped, for: categoryCode)
                ? mapped
                : "underwear"
        default: break
        }
        let fallback = FitMatchTaxonomyProvider.shared.detailCode(for: detail.rawValue, categoryCode: categoryCode)
        return FitMatchTaxonomyProvider.shared.isValidDetail(fallback, for: categoryCode) ? fallback : nil
    }

    private static func deepestOuterwearDetail(in depths: [String]) -> String? {
        for depth in depths.reversed() {
            if let detail = outerwearDetail(in: depth.lowercased()) {
                return detail
            }
        }
        return nil
    }

    private static func outerwearDetail(in source: String) -> String? {
        let mappings: [(String, [String])] = [
            ("padded_vest", ["패딩조끼", "패딩 베스트"]),
            ("light_padding", ["경량 패딩"]),
            ("short_padding", ["숏패딩"]),
            ("long_padding", ["롱패딩"]),
            ("cardigan", ["가디건", "카디건", "cardigan"]),
            ("blazer", ["블레이저", "테일러드 재킷", "테일러드재킷", "tailored jacket", "blazer"]),
            ("blouson", ["블루종", "ma-1", "ma1", "blouson"]),
            ("fleece", ["플리스", "뽀글이", "fleece"]),
            ("anorak", ["아노락", "anorak"]),
            ("windbreaker", [
                "바람막이", "윈드브레이커", "나일론/코치",
                "코치 재킷", "코치재킷", "코치 자켓", "코치자켓",
                "windbreaker", "coach jacket"
            ]),
            ("mouton", ["무스탕", "퍼 재킷", "퍼 자켓", "퍼 코트", "mouton", "mustang"]),
            ("trench_coat", ["트렌치", "trench"]),
            ("padding", ["패딩", "패디드", "파카", "헤비 아우터", "padding", "padded", "parka"]),
            ("vest", ["베스트", "조끼", "vest"]),
            ("coat", ["코트", "coat"]),
            ("jumper", [
                "점퍼", "후드 집업", "후드집업", "풀집 후디", "풀집후디",
                "메쉬 후디", "메쉬후디", "jumper", "full zip hoodie",
                "full-zip hoodie", "mesh hoodie"
            ]),
            ("jacket", ["재킷", "자켓", "라이더스", "스타디움", "사파리", "헌팅", "트러커", "트랙탑", "track top", "tracktop", "jacket"]),
            ("other_outerwear", ["기타 아우터"])
        ]
        return mappings.first(where: { containsAny(source, $0.1) })?.0
    }

    private static func explicitOuterwearDetail(in productName: String) -> String? {
        var matches = Set<String>()
        let rules: [(String, [String])] = [
            ("padded_vest", ["패딩조끼", "패딩 조끼", "패딩베스트", "패딩 베스트", "padded vest"]),
            ("light_padding", ["경량 패딩", "라이트 패딩", "light padding"]),
            ("short_padding", ["숏패딩", "숏 패딩", "쇼트패딩", "쇼트 패딩", "short padding"]),
            ("long_padding", ["롱패딩", "롱 패딩", "long padding"]),
            ("cardigan", ["가디건", "카디건", "cardigan"]),
            ("blazer", ["블레이저", "테일러드 재킷", "테일러드재킷", "테일러드 자켓", "테일러드자켓", "tailored jacket", "blazer"]),
            ("blouson", ["블루종", "blouson", "ma-1", "ma1"]),
            ("fleece", ["플리스", "후리스", "뽀글이", "fleece"]),
            ("anorak", ["아노락", "anorak"]),
            ("windbreaker", ["바람막이", "윈드브레이커", "코치 재킷", "코치재킷", "코치 자켓", "코치자켓", "windbreaker", "coach jacket"]),
            ("mouton", ["무스탕", "퍼 재킷", "퍼 자켓", "퍼 코트", "mouton", "mustang"]),
            ("trench_coat", ["트렌치", "trench"]),
            ("padding", [
                "패딩", "패디드", "padding", "padded",
                "다운 파카", "다운파카", "down parka", "다운 재킷", "다운재킷", "down jacket",
                "퍼프테크", "pufftech"
            ]),
            ("coat", ["코트", "coat"]),
            ("jumper", ["점퍼", "후드 집업", "후드집업", "풀집 후디", "풀집후디", "메쉬 후디", "메쉬후디", "jumper", "full zip hoodie", "full-zip hoodie", "mesh hoodie"]),
            ("jacket", ["재킷", "자켓", "라이더스", "스타디움", "바시티", "사파리", "헌팅", "트러커", "트랙탑", "track top", "tracktop", "jacket"])
        ]
        for (detail, tokens) in rules where containsAny(productName, tokens) {
            matches.insert(detail)
        }

        if matches.contains("padded_vest") {
            matches.remove("padding")
            matches.remove("jacket")
        }
        if !matches.isDisjoint(with: ["light_padding", "short_padding", "long_padding"]) {
            matches.remove("padding")
            matches.remove("jacket")
        }
        if !matches.isDisjoint(with: ["blazer", "blouson", "fleece", "anorak", "windbreaker", "padding"]) {
            matches.remove("jacket")
        }
        if !matches.isDisjoint(with: ["trench_coat", "mouton"]) {
            matches.remove("coat")
            matches.remove("jacket")
        }
        return matches.count == 1 ? matches.first : nil
    }

    private static func crossCategoryOuterwearDetail(in productName: String) -> String? {
        guard containsAny(productName, [
            "블레이저", "테일러드 재킷", "테일러드재킷", "테일러드 자켓", "테일러드자켓",
            "가디건", "카디건", "cardigan",
            "바람막이", "윈드브레이커", "코치 재킷", "코치재킷", "코치 자켓", "코치자켓",
            "블루종", "ma-1", "ma1", "아노락", "트렌치", "무스탕", "mustang",
            "패딩", "패디드", "padding", "padded", "padded vest",
            "라이더스", "스타디움", "바시티", "사파리", "헌팅", "트러커",
            "tailored jacket", "blazer", "windbreaker", "coach jacket", "blouson",
            "anorak", "trench", "mouton"
        ]) else { return nil }
        return explicitOuterwearDetail(in: productName)
    }

    private static func preferredOuterwearNameDetail(
        _ nameDetail: String?,
        over sourceDetail: String?
    ) -> String? {
        guard let nameDetail else { return nil }
        guard let sourceDetail, sourceDetail != "other_outerwear" else { return nameDetail }
        let genericDetails = Set(["jacket", "coat", "jumper"])
        if genericDetails.contains(nameDetail), !genericDetails.contains(sourceDetail) {
            return nil
        }
        return nameDetail
    }

    private static func explicitTopLengthDetail(in productName: String) -> String? {
        if containsAny(productName, ["민소매", "나시", "슬리브리스", "sleeveless", "tank"]) { return "sleeveless" }
        if containsAny(productName, [
            "반팔", "반소매", "숏슬리브", "하프 슬리브", "short sleeve", "half sleeve",
            "cap sleeve", "s/s tee", "s/s t-shirt", "s/s tshirt"
        ]) { return "short_sleeve" }
        if containsAny(productName, [
            "긴팔", "긴소매", "롱슬리브", "long sleeve",
            "l/s tee", "l/s t-shirt", "l/s tshirt"
        ]) { return "long_sleeve" }
        if containsAny(productName, ["7부", "three quarter", "3/4 sleeve", "3/4"]) { return "three_quarter_sleeve" }
        return nil
    }

    private static func inferredFamily(from source: String, productName: String,
                                       categoryCode: String) -> ComparisonGarmentFamily {
        if categoryCode == "outerwear" {
            if containsAny(productName, ["가디건", "카디건", "cardigan"]) { return .knitCardigan }
            return containsAny(productName, ["레더", "가죽", "라이더스", "leather jacket", "riders jacket"])
                ? .leatherJacket
                : .outerwear
        }
        if categoryCode == "tops" {
            if containsAny(productName, ["후디", "후드 티", "후드티", "hoodie"]) { return .hoodie }
            if containsAny(productName, ["스웨트셔츠", "스웨트 셔츠", "스웨트", "맨투맨", "sweatshirt"]) { return .sweatshirt }
        }
        if containsAny(source, ["레더", "라이더스", "leather jacket", "riders jacket"]) { return .leatherJacket }
        if containsAny(source, ["니트", "스웨터", "가디건", "knit", "sweater", "cardigan"]) { return .knitCardigan }
        if containsAny(source, ["티셔츠", "t-shirt", "tshirt"]) { return .tshirt }
        if containsAny(source, ["셔츠", "블라우스", "shirt", "blouse"]) { return .shirt }
        if containsAny(source, ["데님", "청바지", "denim", "jeans"]) { return .denim }
        switch categoryCode {
        case "bottoms": return .pants
        case "leggings": return .leggings
        case "skirts": return .skirt
        case "outerwear": return .outerwear
        case "underwear", "homewear": return .underwear
        case "dresses": return .dress
        default: return .unknown
        }
    }

    private static func inferredLength(
        from text: String,
        detailCode: String,
        categoryCode: String
    ) -> ComparisonLengthType {
        let sleeveAxisCategories = Set(["tops", "outerwear", "dresses"])
        if sleeveAxisCategories.contains(categoryCode) {
            if detailCode == "sleeveless" { return .sleeveless }
            if detailCode == "short_sleeve" { return .short }
            if detailCode == "three_quarter_sleeve" { return .threeQuarter }
            if detailCode == "long_sleeve" { return .long }
            if containsAny(text, ["민소매", "나시", "슬리브리스", "sleeveless"]) {
                return .sleeveless
            }
            let hasShort = containsAny(text, [
                "반팔", "반소매", "숏슬리브", "하프 슬리브", "short sleeve", "half sleeve",
                "cap sleeve", "s/s tee", "s/s t-shirt", "s/s tshirt"
            ])
            let hasLong = containsAny(text, [
                "긴팔", "긴소매", "롱슬리브", "long sleeve",
                "l/s tee", "l/s t-shirt", "l/s tshirt"
            ])
            if hasShort != hasLong { return hasShort ? .short : .long }
            if containsAny(text, ["7부", "three quarter", "3/4"]) { return .threeQuarter }
            // 크롭은 몸판 길이이며 상의/아우터의 소매 길이 축에 저장하지 않는다.
            return .unknown
        }

        if detailCode == "skirt" {
            if containsAny(text, ["미니 스커트", "미니스커트", "미니 스코츠", "미니스코츠", "스코츠", "skorts", "mini skirt"]) { return .short }
            if containsAny(text, ["미디 스커트", "미디스커트", "midi skirt"]) { return .threeQuarter }
            if containsAny(text, ["롱 스커트", "롱스커트", "맥시 스커트", "맥시스커트", "long skirt", "maxi skirt"]) { return .long }
        }
        if containsAny(text, [
            "쇼츠", "숏 팬츠", "반바지",
            "3부", "3.5부", "4부", "4.5부", "5부", "바이커",
            "하프 타이즈", "하프타이즈", "하프 타이츠", "하프타이츠"
        ]) { return .short }
        if containsAny(text, ["6부", "7부", "8부", "three quarter", "3/4"])
            || (detailCode == "three_quarter_leggings"
                && containsAny(text, ["카프리", "capri"])) {
            return .threeQuarter
        }
        if containsAny(text, ["크롭", "cropped", "카프리", "capri"]) { return .cropped }
        if containsAny(text, ["9부", "nine tenths", "ankle"]) { return .nineTenths }
        if containsAny(text, ["긴바지", "롱 팬츠", "long pants"]) { return .long }
        if ["short_pants", "shorts", "short_leggings"].contains(detailCode) { return .short }
        if ["three_quarter_pants", "three_quarter_leggings"].contains(detailCode) { return .threeQuarter }
        if detailCode == "cropped_pants" { return .cropped }
        if ["nine_tenths_pants", "nine_tenths_leggings"].contains(detailCode) { return .nineTenths }
        if ["long_pants", "long_leggings"].contains(detailCode) { return .long }
        return .unknown
    }

    private static func containsAny(_ text: String, _ values: [String]) -> Bool {
        values.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func mostSpecificCategorySource(in depths: [String], fallback: String) -> String {
        let umbrellaValues = ["원피스/스커트", "원피스 & 스커트", "속옷/홈웨어", "속옷 & 홈웨어"]
        let categoryWords = ["스커트", "skirt", "원피스", "dress", "여성 속옷 하의", "팬티", "panty", "브라", "bra",
                             "홈웨어", "라운지", "homewear", "loungewear"]
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
