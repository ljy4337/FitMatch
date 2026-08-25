import Foundation

enum ParsedClosetClassificationConflictDimension: String, Equatable {
    case category
    case garmentFamily = "garment_family"
    case length
}

struct ParsedClosetClassificationConflict: Equatable {
    let dimension: ParsedClosetClassificationConflictDimension
    let trustedValue: String
    let explicitValue: String
}

struct ParsedClosetClassificationSafetyAudit: Equatable {
    static let conflictResolutionMethod = "classification_conflict"
    static let policyVersion = "local-classification-safety-2026-08-24-v1"
    static let safe = ParsedClosetClassificationSafetyAudit(conflicts: [])

    let conflicts: [ParsedClosetClassificationConflict]

    var requiresReview: Bool { !conflicts.isEmpty }
}

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
        return categoryCode != "other"
            && detailCode != "other"
            && provider.isActiveCategory(categoryCode)
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
        let deepestSource = depths.last?.lowercased() ?? source
        let lowerBodyDepths = depths.isEmpty
            ? (sourcePath ?? "").components(separatedBy: ">").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            : depths
        let decisiveLowerBodySource = lowerBodyDepths.reversed().first { depth in
            let value = depth.lowercased()
            let hasLeggings = containsAny(value, ["레깅스", "leggings"])
            let hasPants = containsAny(value, [
                "팬츠", "바지", "쇼츠", "반바지", "pants", "trousers", "shorts"
            ])
            return hasLeggings != hasPants
        }?.lowercased()
        let lowerBodyDeclaresLeggings = decisiveLowerBodySource.map {
            containsAny($0, ["레깅스", "leggings"])
        } ?? false
        let lowerBodyDeclaresPants = decisiveLowerBodySource.map {
            containsAny($0, [
                "팬츠", "바지", "쇼츠", "반바지", "pants", "trousers", "shorts"
            ])
        } ?? false
        let specificHasLeggings = containsAny(specificSource, ["레깅스", "leggings"])
        let specificHasPants = containsAny(specificSource, [
            "팬츠", "바지", "쇼츠", "반바지", "pants", "trousers", "shorts"
        ])
        let refinedTopSource = depths.count > 1
            ? depths.dropFirst().joined(separator: " > ").lowercased()
            : deepestSource
        let name = productName.lowercased()
        let productNameDeclaresLeggings = containsAny(name, ["레깅스", "leggings"])
        guard !isExplicitCompositeGarmentSet(name),
              !hasAmbiguousGarmentOption(name) else { return nil }
        let combined = "\(source) \(name) \(detailCategory.rawValue.lowercased())"

        let resolvedCategoryCode: String
        let resolvedDetailCode: String
        let resolvedCategory: ClothingCategory
        let resolvedDetail: ClosetDetailCategory

        // Explicit underwear garment names win over merchandising buckets and
        // generic lower-body words such as "쇼츠". AIRism itself is never a
        // category signal.
        if isSleevelessTopMerchandisingPath(source),
           containsExplicitBra(in: name),
           !containsAny(name, ["스포츠브라", "sports bra"]) {
            // A bra cup can be construction inside a sleeveless top. Musinsa's
            // explicit sleeveless T-shirt leaf is stronger than the generic
            // bra token; sports bras and generic buckets remain underwear.
            resolvedCategoryCode = "tops"
            resolvedDetailCode = "sleeveless"
            resolvedCategory = .top
            resolvedDetail = .sleeveless
        } else if category.serviceGroup == .underwear,
                  detailCategory == .womenBra,
                  containsExplicitBra(in: source) {
            // A verified retailer bra leaf remains authoritative when the
            // product name describes an attached camisole construction.
            resolvedCategoryCode = "underwear"
            resolvedDetailCode = "women_bra"
            resolvedCategory = .underwear
            resolvedDetail = .womenBra
        } else if let explicitUnderwearDetail = explicitUnderwearDetail(
            in: name,
            source: source
        ) {
            resolvedCategoryCode = "underwear"
            resolvedDetailCode = explicitUnderwearDetail
            resolvedCategory = .underwear
            resolvedDetail = ClosetDetailCategory.fromTaxonomyCode(explicitUnderwearDetail)
        } else if containsAny(name, ["가디건", "카디건", "cardigan"]),
                  !containsAny(name, ["세트", "셋업", "set-up", "set up", "setup"]) {
            resolvedCategoryCode = "outerwear"
            resolvedDetailCode = "cardigan"
            resolvedCategory = .outer
            resolvedDetail = .cardigan
        // 스코츠는 바지형 안감이 있어도 사용자가 스커트로 찾고 비교하는
        // 단일 구조다. 쇼트 팬츠 상위 경로보다 명시적 상품/말단명을 우선한다.
        } else if containsAny(name, ["스코츠", "skorts", "skort"])
                    || containsAny(deepestSource, ["스코츠", "skorts", "skort"]) {
            resolvedCategoryCode = "skirts"; resolvedDetailCode = "skirt"
            resolvedCategory = .bottom; resolvedDetail = .skirt
        // Exact source families are evaluated before generic words such as 하의/원피스.
        } else if specificSource.contains("스커트") || specificSource.contains("skirt") {
            resolvedCategoryCode = "skirts"; resolvedDetailCode = "skirt"
            resolvedCategory = .bottom; resolvedDetail = .skirt
        } else if productNameDeclaresLeggings
                    || lowerBodyDeclaresLeggings
                    || (!lowerBodyDeclaresPants && specificHasLeggings && !specificHasPants) {
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
        } else if containsExplicitBra(in: specificSource)
                    || (category.serviceGroup == .other && containsExplicitBra(in: name)) {
            resolvedCategoryCode = "underwear"; resolvedDetailCode = "women_bra"
            resolvedCategory = .underwear; resolvedDetail = .womenBra
        } else if containsAny(specificSource, [
            "홈웨어", "라운지", "파자마", "잠옷", "homewear", "loungewear", "pajama", "pyjama"
        ]) || (category.serviceGroup == .other && containsAny(name, [
            "홈웨어", "라운지", "파자마", "잠옷", "homewear", "loungewear", "pajama", "pyjama"
        ])) {
            resolvedCategoryCode = "homewear"; resolvedDetailCode = "loungewear"
            resolvedCategory = .other; resolvedDetail = .loungewear
        } else if isInnerwearStructuralTShirt(source: source, productName: name) {
            // UNIQLO's Innerwear class is a merchandising bucket: it can contain
            // both underwear and ordinary T-shirts. Explicit underwear garments
            // are resolved above. A product explicitly named as a T-shirt is
            // classified by garment structure; AIRism alone is never evidence.
            resolvedCategoryCode = "tops"
            resolvedDetailCode = explicitTopLengthDetail(in: name) ?? "short_sleeve"
            resolvedCategory = .top
            resolvedDetail = ClosetDetailCategory.fromTaxonomyCode(resolvedDetailCode)
        } else if containsAny(specificSource, ["여성 속옷", "남성 속옷", "언더웨어", "underwear"]) {
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
        } else if category.serviceGroup == .top,
                  containsExplicitTShirt(in: name) {
            // Words such as "스타디움" may describe a T-shirt design rather
            // than a jacket. An explicit T-shirt structure keeps the top major.
            resolvedCategoryCode = "tops"
            resolvedDetailCode = explicitProviderTopDetail(
                in: specificSource,
                productName: name
            )
                ?? explicitTopGarmentDetail(in: name)
                ?? explicitTopLengthDetail(in: name)
                ?? explicitTopLengthDetail(in: source)
                ?? "short_sleeve"
            resolvedCategory = .top
            resolvedDetail = ClosetDetailCategory.fromTaxonomyCode(resolvedDetailCode)
        } else if let explicitOuterwearDetail = crossCategoryOuterwearDetail(in: name),
                  [.top, .other].contains(category.serviceGroup),
                  !(category.serviceGroup == .top && containsAny(source, [
                      "반팔", "반소매", "긴팔", "긴소매", "숏슬리브", "롱슬리브",
                      "short sleeve", "long sleeve"
                  ])) {
            // 코치재킷·바람막이처럼 구조가 명시된 상품명은 공식 경로가
            // 그래픽 티 등으로 잘못 내려오더라도 아우터 구조를 우선한다.
            resolvedCategoryCode = "outerwear"
            resolvedDetailCode = explicitOuterwearDetail
            resolvedCategory = .outer
            resolvedDetail = ClosetDetailCategory.fromTaxonomyCode(explicitOuterwearDetail)
        } else if category.serviceGroup == .other,
                  detailCategory == .sweatshirt,
                  containsAny(name, ["스웨트", "스웻", "맨투맨", "sweat"]) {
            // When the provider path has no garment major category, a matching
            // provider detail plus an explicit product-name signal can safely
            // recover a sweatshirt. A detail or name alone is not enough.
            resolvedCategoryCode = "tops"
            resolvedDetailCode = "sweatshirt"
            resolvedCategory = .top
            resolvedDetail = .sweatshirt
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
                                           specificSourceText: refinedTopSource,
                                           productNameText: name)
                : canonicalDetailCode(categoryCode: resolvedCategoryCode,
                                      detail: detailCategory,
                                      text: combined,
                                      sourceText: source,
                                      specificSourceText: refinedTopSource,
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
            ? inferredFamily(from: source, productName: name,
                             categoryCode: resolvedCategoryCode, detailCode: resolvedDetailCode)
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

    /// Audits explicit product-name evidence after the normal classifier has
    /// made its decision. Product-name evidence may corroborate a trusted
    /// source fact, but it cannot silently replace an incompatible critical
    /// category, garment family, or length.
    static func auditExplicitContradictions(
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        sourceDepths: [String?],
        sourcePath: String?,
        productName: String
    ) -> ParsedClosetClassificationSafetyAudit {
        let depths = sourceDepths.compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let source = (depths.isEmpty ? (sourcePath ?? "") : depths.joined(separator: " > "))
            .lowercased()
        let name = productName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !source.isEmpty, !name.isEmpty, category.serviceGroup != .other else {
            return .safe
        }

        var conflicts: [ParsedClosetClassificationConflict] = []
        let trustedMajor = category.serviceGroup
        let explicitMajors = explicitNameMajorCategories(in: name)
        let isVerifiedInnerwearTShirtException = trustedMajor == .underwear
            && isInnerwearStructuralTShirt(source: source, productName: name)
        let isVerifiedSleevelessBraConstruction = trustedMajor == .top
            && isSleevelessTopMerchandisingPath(source)
            && containsExplicitBra(in: name)
            && !containsAny(name, ["스포츠브라", "sports bra"])
        let isVerifiedMerchandisingException = isVerifiedInnerwearTShirtException
            || isVerifiedSleevelessBraConstruction
        if !isVerifiedMerchandisingException,
           !explicitMajors.isEmpty,
           !explicitMajors.contains(trustedMajor) {
            conflicts.append(ParsedClosetClassificationConflict(
                dimension: .category,
                trustedValue: trustedMajor.taxonomyCode,
                explicitValue: explicitMajors.map(\.taxonomyCode).sorted().joined(separator: ",")
            ))
        }

        let categoryCode = trustedMajor.taxonomyCode
        let detailCode = FitMatchTaxonomyProvider.shared.detailCode(
            for: detailCategory.rawValue,
            categoryCode: categoryCode
        ) ?? "other"
        let trustedLength = explicitLength(for: detailCategory)
            ?? inferredLength(from: source, detailCode: detailCode, categoryCode: categoryCode)
        let explicitNameLength = inferredLength(
            from: name,
            detailCode: "other",
            categoryCode: categoryCode
        )
        if trustedLength != .unknown,
           explicitNameLength != .unknown,
           trustedLength != explicitNameLength {
            conflicts.append(ParsedClosetClassificationConflict(
                dimension: .length,
                trustedValue: trustedLength.rawValue,
                explicitValue: explicitNameLength.rawValue
            ))
        }

        if !isVerifiedMerchandisingException,
           let trustedFamily = explicitFamily(for: detailCategory) {
            let explicitFamilies = explicitNameFamilies(in: name)
            if !explicitFamilies.isEmpty, !explicitFamilies.contains(trustedFamily) {
                conflicts.append(ParsedClosetClassificationConflict(
                    dimension: .garmentFamily,
                    trustedValue: trustedFamily.rawValue,
                    explicitValue: explicitFamilies.map(\.rawValue).sorted().joined(separator: ",")
                ))
            }
        }

        return ParsedClosetClassificationSafetyAudit(conflicts: conflicts)
    }

    static func isConsistent(category: ClothingCategory, detailCategory: ClosetDetailCategory,
                             categoryCode: String, detailCode: String) -> Bool {
        ClothingCategory.fromTaxonomyCode(categoryCode).serviceGroup == category.serviceGroup
            && ClosetDetailCategory.fromTaxonomyCode(detailCode) == detailCategory
    }

    private static func canonicalDetailCode(categoryCode: String, detail: ClosetDetailCategory,
                                            text: String, sourceText: String,
                                            specificSourceText: String,
                                            productNameText: String) -> String? {
        switch categoryCode {
        case "tops":
            let providerDetailCode = FitMatchTaxonomyProvider.shared.detailCode(
                for: detail.rawValue,
                categoryCode: categoryCode
            )
            let providerUsesLengthAxis = [
                "sleeveless", "short_sleeve", "three_quarter_sleeve", "long_sleeve"
            ].contains(providerDetailCode)
            if providerUsesLengthAxis,
               let productLength = explicitTopLengthDetail(in: productNameText) {
                return productLength
            }
            if let providerDetail = explicitProviderTopDetail(
                in: specificSourceText,
                productName: productNameText
            ) {
                return providerDetail
            }
            if containsAny(productNameText, [
                "피케/카라 티셔츠", "피케/카라티셔츠", "카라티", "카라 티",
                "폴로셔츠", "폴로 셔츠", "polo shirt", "polo_shirt"
            ]) { return "polo_shirt" }
            if let namedDetail = explicitTopGarmentDetail(in: productNameText) {
                return namedDetail
            }
            if let productDetail = explicitTopLengthDetail(in: productNameText) { return productDetail }
            let sourceHasShort = containsAny(sourceText, ["반팔", "반소매", "숏슬리브", "short sleeve"])
            let sourceHasLong = containsAny(sourceText, ["긴팔", "긴소매", "롱슬리브", "long sleeve"])
            if sourceHasShort != sourceHasLong { return sourceHasShort ? "short_sleeve" : "long_sleeve" }
            if containsAny(sourceText, ["민소매", "나시", "슬리브리스", "sleeveless", "tank"]) { return "sleeveless" }
            if containsAny(sourceText, ["7부", "three quarter", "3/4 sleeve"]) { return "three_quarter_sleeve" }
            if containsAny(sourceText, ["cut & sewn", "cut and sewn"]) { return "short_sleeve" }
            if providerDetailCode != "other_tops",
               FitMatchTaxonomyProvider.shared.isValidDetail(providerDetailCode, for: categoryCode) {
                return providerDetailCode
            }
            return nil
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
        if containsAny(source, [
            "스웨트파카", "스웨트 파카", "스웨트풀집", "스웨트 풀집",
            "sweat parka", "sweat full zip", "sweat full-zip"
        ]) {
            return "jumper"
        }
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
            ("mouton", ["무스탕", "mouton", "mustang"]),
            ("trench_coat", ["트렌치", "trench"]),
            ("padding", ["패딩", "패디드", "파카", "헤비 아우터", "padding", "padded", "parka"]),
            ("vest", ["베스트", "조끼", "vest"]),
            ("coat", ["코트", "coat"]),
            ("jumper", [
                "점퍼", "후드 집업", "후드집업", "풀집 후디", "풀집후디", "풀집 파카", "풀집파카", "집업 후디", "집업후디",
                "메쉬 후디", "메쉬후디", "jumper", "full zip hoodie",
                "full-zip hoodie", "zip hoodie", "zip-up hoodie", "mesh hoodie"
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
            ("mouton", ["무스탕", "mouton", "mustang"]),
            ("trench_coat", ["트렌치", "trench"]),
            ("padding", [
                "패딩", "패디드", "padding", "padded",
                "다운 파카", "다운파카", "down parka", "다운 재킷", "다운재킷", "down jacket",
                "퍼프테크", "pufftech"
            ]),
            ("coat", ["코트", "coat"]),
            ("jumper", ["점퍼", "후드 집업", "후드집업", "풀집 후디", "풀집후디", "풀집 파카", "풀집파카", "집업 후디", "집업후디", "메쉬 후디", "메쉬후디", "jumper", "zip hoodie", "zip-up hoodie", "full zip hoodie", "full-zip hoodie", "mesh hoodie"]),
            ("jacket", ["재킷", "자켓", "라이더스", "스타디움", "바시티", "사파리", "헌팅", "트러커", "트랙탑", "track top", "tracktop", "jacket"])
        ]
        for (detail, tokens) in rules where containsAny(productName, tokens) {
            matches.insert(detail)
        }
        if containsStandaloneFurOuterwear(in: productName) {
            matches.insert("mouton")
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
            "후드 집업", "후드집업", "풀집 후디", "풀집후디", "풀집 파카", "풀집파카", "집업 후디", "집업후디",
            "블루종", "ma-1", "ma1", "아노락", "트렌치", "무스탕", "mustang",
            "패딩", "패디드", "padding", "padded", "padded vest",
            "라이더스", "스타디움", "바시티", "사파리", "헌팅", "트러커",
            "tailored jacket", "blazer", "windbreaker", "coach jacket", "blouson",
            "anorak", "trench", "mouton", "zip hoodie", "zip-up hoodie", "full zip hoodie", "full-zip hoodie"
        ]) else { return nil }
        let detail = explicitOuterwearDetail(in: productName)
        if detail == "windbreaker",
           containsAny(productName, ["코치 재킷", "코치재킷", "코치 자켓", "코치자켓", "coach jacket"]) {
            // Outside an official outerwear path, "coach jacket" establishes
            // jacket structure but not the retailer-specific windbreaker leaf.
            return "jacket"
        }
        return detail
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
        if containsAny(productName, [
            "민소매", "나시", "슬리브리스", "캐미솔", "camisole", "sleeveless", "tank"
        ]) { return "sleeveless" }
        if containsAny(productName, [
            "반팔", "반소매", "숏슬리브", "하프 슬리브", "short sleeve", "short-sleeve", "half sleeve",
            "cap sleeve", "s/s tee", "s/s t-shirt", "s/s tshirt"
        ]) { return "short_sleeve" }
        if containsAny(productName, [
            "긴팔", "긴소매", "롱슬리브", "롱 슬리브", "long sleeve", "long-sleeve",
            "l/s tee", "l/s t-shirt", "l/s tshirt"
        ]) { return "long_sleeve" }
        if containsAny(productName, ["9부", "nine tenths", "nine-tenths"]) { return "long_sleeve" }
        if containsAny(productName, ["7부", "three quarter", "3/4 sleeve", "3/4"]) { return "three_quarter_sleeve" }
        return nil
    }

    private static func containsExplicitTShirt(in productName: String) -> Bool {
        containsAny(productName, [
            "티셔츠", "크루넥t", "크루넥 t", "v넥t", "v넥 t", "u넥t", "u넥 t",
            "t-shirt", "tshirt", "tee ", " tee", "[tee]", "(tee)",
            "crew neck t", "crew-neck t"
        ])
    }

    private static func isSleevelessTopMerchandisingPath(_ source: String) -> Bool {
        containsAny(source, [
            "나시/민소매 티셔츠", "나시 & 민소매 티셔츠",
            "sleeveless t-shirt", "sleeveless tshirt"
        ])
    }

    private static func isInnerwearStructuralTShirt(source: String, productName: String) -> Bool {
        let isInnerwearPath = containsAny(source, [
            "이너웨어", "언더웨어", "innerwear", "underwear"
        ])
        let isCottonLine = containsAny(productName, ["코튼", "cotton"])
        let isExplicitTShirt = containsAny(productName, [
            "티셔츠", "크루넥t", "크루넥 t", "v넥t", "v넥 t", "u넥t", "u넥 t",
            "t-shirt", "tshirt", "crew neck t", "crew-neck t",
            "v neck t", "v-neck t", "u neck t", "u-neck t"
        ]) || productName.range(
            of: #"[가-힣0-9]t(?:$|[\s(])"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        // Plain AIRism/mesh crew-neck and V-neck T products in Innerwear are
        // undershirts. The known merchandising exception is the cotton T line.
        return isInnerwearPath && isCottonLine && isExplicitTShirt
    }

    private static func explicitUnderwearDetail(in productName: String, source: String) -> String? {
        if containsAny(productName, ["브라캐미솔", "bra camisole"]) { return "women_camisole" }
        if containsAny(productName, ["브라탱크", "퍼스트브라", "와이어리스브라"])
            || containsExplicitBra(in: productName) {
            return "women_bra"
        }
        if containsAny(productName, ["캐미솔", "camisole"]) && containsAny(source, ["이너웨어", "언더웨어", "innerwear", "underwear"]) {
            return "women_camisole"
        }
        let isInnerwearPath = containsAny(source, [
            "이너웨어", "언더웨어", "innerwear", "underwear"
        ])
        let isCottonOuterTException = containsAny(productName, ["코튼", "cotton"])
            && containsAny(productName, [
                "크루넥t", "크루넥 t", "v넥t", "v넥 t", "u넥t", "u넥 t",
                "t-shirt", "tshirt", "crew neck t", "v neck t", "u neck t"
            ])
        let isStructuralUndershirt = containsAny(productName, [
            "크루넥t", "크루넥 t", "v넥t", "v넥 t", "u넥t", "u넥 t",
            "탱크탑", "탱크 탑", "tank top", "t-shirt", "tshirt",
            "crew neck t", "v neck t", "u neck t"
        ])
        if isInnerwearPath, isStructuralUndershirt, !isCottonOuterTException {
            return "underwear"
        }
        if containsAny(productName, ["트렁크스", "트렁크", "trunks"]) { return "men_trunks" }
        if containsAny(productName, ["복서브리프", "boxer brief", "boxer-brief"]) {
            return containsAny(productName, ["girls", "여아"]) ? "women_panty" : "men_briefs"
        }
        if containsAny(source, ["이너웨어", "언더웨어", "속옷", "innerwear", "underwear"]),
           containsAny(productName, ["브리프", "brief"]) {
            return "men_briefs"
        }
        if containsAny(source, ["이너웨어", "언더웨어", "innerwear", "underwear"]),
           containsAny(productName, ["심리스쇼츠", "쉐이퍼쇼츠", "속바지", "seamless shorts", "shaper shorts"]) {
            return "women_panty"
        }
        return nil
    }

    private static func explicitProviderTopDetail(
        in source: String,
        productName: String
    ) -> String? {
        guard !isGenericSourceCategory(source) else { return nil }
        let leaf = source
            .components(separatedBy: ">").last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? source
        let isMixedShirtBucket = containsAny(leaf, ["셔츠", "shirt"])
            && containsAny(leaf, ["블라우스", "blouse"])
        let isMixedTShirtBucket = containsAny(leaf, ["티셔츠", "t-shirt", "tshirt"])
            && containsAny(leaf, ["스웨트", "sweat"])
        guard !isMixedShirtBucket, !isMixedTShirtBucket else { return nil }
        if containsAny(leaf, ["피케/카라 티셔츠", "피케/카라티셔츠", "폴로셔츠", "폴로 셔츠", "polo shirt"]) {
            return "polo_shirt"
        }
        if containsAny(leaf, ["후드 티", "후드티", "후디", "hoodie"]) { return "hoodie" }
        if containsAny(leaf, ["스웨트셔츠", "스웨트 셔츠", "맨투맨", "sweatshirt"]) { return "sweatshirt" }
        if containsAny(leaf, ["블라우스", "blouse"]) { return "blouse" }
        if containsAny(leaf, ["니트", "스웨터", "knit", "sweater"]) { return "knit_top" }
        if containsAny(leaf, ["셔츠", "shirt"])
            && !containsAny(leaf, ["티셔츠", "t-shirt", "tshirt"]) {
            return "shirt"
        }
        return nil
    }

    private static func explicitTopGarmentDetail(in productName: String) -> String? {
        if containsAny(productName, ["후디", "후드 티", "후드티", "hoodie"]) { return "hoodie" }
        if containsAny(productName, [
            "스웨트셔츠", "스웨트 셔츠", "스웻셔츠", "스웻 셔츠",
            "스웨트후디", "스웨트 후디", "맨투맨", "sweatshirt", "sweat shirt"
        ]) { return "sweatshirt" }
        if containsAny(productName, ["니트", "스웨터", "knit", "sweater"]) { return "knit_top" }
        if containsAny(productName, ["블라우스", "blouse"]) { return "blouse" }
        let hasStandaloneShirt = productName.contains("셔츠")
            || containsEnglishWord("shirt", in: productName)
        if hasStandaloneShirt
            && !containsAny(productName, [
                "티셔츠", "t-shirt", "tshirt", "스웨트셔츠", "스웨트 셔츠",
                "스웻셔츠", "스웻 셔츠", "sweatshirt"
            ]) {
            return "shirt"
        }
        return nil
    }

    private static func isGenericSourceCategory(_ source: String) -> Bool {
        let terminal = source
            .components(separatedBy: ">").last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? source
        return containsAny(terminal, [
            "기타상의", "기타 상의", "기타 아우터", "기타 하의",
            "other tops", "other top", "other outerwear", "other bottoms"
        ])
    }

    private static func isExplicitCompositeGarmentSet(_ productName: String) -> Bool {
        // "셋업 가능" and a single "셋업 자켓" describe one garment or a
        // coordination option. Only explicit bundles or names that enumerate
        // multiple garment structures are held for user confirmation.
        if containsAny(productName, [
            "파자마 세트", "pajama set", "pyjama set",
            "세트상품", "정장 세트", "수트 세트", "suit set",
            "셋업 수트", "셋업수트", "set-up suit", "set up suit", "setup suit",
            "투피스", "two-piece", "two piece", "2-piece", "2 piece",
            "2pc", "2 pcs", "3p 셋업", "3-piece", "3 piece", "3pcs", "3 pcs"
        ]) {
            return true
        }

        let hasSetSignal = containsAny(productName, [
            "세트", "셋업", " set", "set ", "[set]", "(set)", "set-up", "set up", "setup"
        ])
        guard hasSetSignal else { return false }
        if containsAny(productName, ["레이어드", "layered"]) { return true }

        let garmentFamilies: [[String]] = [
            ["티셔츠", "t-shirt", "tshirt", "탑 ", " 탑", "top "],
            ["셔츠", "shirt"],
            ["블라우스", "blouse"],
            ["탑", " top"],
            ["나시", "민소매", "슬리브리스", "camisole", "cami", "bustier"],
            ["니트", "knit", "sweater"],
            ["가디건", "카디건", "cardigan"],
            ["베스트", "조끼", " vest"],
            ["재킷", "자켓", "jacket", "블레이저", "blazer"],
            ["코트", " coat", "트렌치"],
            ["팬츠", "바지", "pants", "trousers", "슬랙스"],
            ["스커트", "skirt"],
            ["레깅스", "leggings"],
            ["원피스", "dress"],
            ["점프수트", "점프 슈트", "오버롤", "jumpsuit", "overall"],
            ["가방", "백 세트", " bag"],
        ]
        let matchedFamilyCount = garmentFamilies.reduce(into: 0) { count, terms in
            if containsAny(productName, terms) { count += 1 }
        }
        return matchedFamilyCount >= 2
    }

    private static func hasAmbiguousGarmentOption(_ productName: String) -> Bool {
        let hasOptionSignal = containsAny(productName, ["선택", "옵션", "choose", "option"])
        let hasMultipleSleeveLengths = containsAny(productName, [
            "민소매/반팔", "나시/반팔", "sleeveless/short", "short/long sleeve"
        ])
        let hasLayeredLengthConflict = containsAny(productName, ["나시 레이어드 반팔", "민소매 레이어드 반팔"])
        return hasMultipleSleeveLengths || hasLayeredLengthConflict
            || (hasOptionSignal
                && containsAny(productName, ["나시", "민소매", "sleeveless"])
                && containsAny(productName, ["반팔", "반소매", "short sleeve", "short-sleeve"]))
    }

    private static func inferredFamily(from source: String, productName: String,
                                       categoryCode: String, detailCode: String) -> ComparisonGarmentFamily {
        // The resolved canonical major wins over retailer merchandising path
        // tokens. For example, UNIQLO bra tops can live under a T-shirt path,
        // but an underwear/women_bra decision must use the underwear family.
        if categoryCode == "underwear" || categoryCode == "homewear" {
            return .underwear
        }
        if categoryCode == "outerwear" {
            if containsAny(productName, ["가디건", "카디건", "cardigan"]) { return .knitCardigan }
            return containsAny(productName, ["레더", "가죽", "라이더스", "leather jacket", "riders jacket"])
                ? .leatherJacket
                : .outerwear
        }
        if categoryCode == "tops" {
            if detailCode == "hoodie" { return .hoodie }
            if detailCode == "sweatshirt" { return .sweatshirt }
            if detailCode == "knit_top" { return .knitCardigan }
            if detailCode == "shirt" || detailCode == "blouse" { return .shirt }
            if detailCode == "polo_shirt" { return .tshirt }
            if containsAny(productName, [
                "피케/카라 티셔츠", "피케/카라티셔츠", "카라티", "카라 티",
                "폴로셔츠", "폴로 셔츠", "polo shirt", "polo_shirt"
            ]) { return .tshirt }
            if containsAny("\(source) \(productName)", ["오버셔츠", "overshirt"]) { return .shirt }
            if ["sleeveless", "short_sleeve", "three_quarter_sleeve", "long_sleeve"].contains(detailCode) {
                return .tshirt
            }
            if containsAny(productName, ["후디", "후드 티", "후드티", "hoodie"]) { return .hoodie }
            if containsAny(productName, ["스웨트셔츠", "스웨트 셔츠", "스웨트", "맨투맨", "sweatshirt", "sweat shirt"]) { return .sweatshirt }
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
        case "dresses": return .dress
        default: return .unknown
        }
    }

    private static func explicitNameMajorCategories(
        in productName: String
    ) -> Set<ClothingCategory> {
        var categories = Set<ClothingCategory>()

        if containsExplicitTShirt(in: productName)
            || explicitTopGarmentDetail(in: productName) != nil
            || containsAny(productName, [
                "폴로셔츠", "폴로 셔츠", "카라티", "polo shirt",
                "민소매 탑", "슬리브리스 탑", "sleeveless top"
            ]) {
            categories.insert(.top)
        }
        if explicitOuterwearDetail(in: productName) != nil {
            categories.insert(.outer)
        }
        if containsAny(productName, ["스커트", "스코츠", "skirt", "skort"]) {
            categories.insert(.bottom)
        }
        if containsAny(productName, [
            "레깅스", "leggings", "팬츠", "바지", "쇼츠", "반바지",
            "pants", "trousers", "shorts", "슬랙스", "slacks"
        ]) {
            categories.insert(.bottom)
        }
        if containsAny(productName, ["원피스", "점프수트", "점프 슈트", "jumpsuit"])
            || containsEnglishWord("dress", in: productName) {
            categories.insert(.dress)
        }
        if containsExplicitBra(in: productName)
            || containsAny(productName, [
                "브리프", "트렁크", "복서", "팬티", "속바지",
                "briefs", "trunks", "boxer", "panty"
            ]) {
            categories.insert(.underwear)
        }

        return Set(categories.map(\.serviceGroup))
    }

    private static func explicitNameFamilies(
        in productName: String
    ) -> [ComparisonGarmentFamily] {
        var families: [ComparisonGarmentFamily] = []
        func append(_ family: ComparisonGarmentFamily) {
            if !families.contains(family) { families.append(family) }
        }
        if containsExplicitTShirt(in: productName) { append(.tshirt) }
        if let detail = explicitTopGarmentDetail(in: productName) {
            switch detail {
            case "shirt", "blouse": append(.shirt)
            case "sweatshirt": append(.sweatshirt)
            case "hoodie": append(.hoodie)
            default: break
            }
        }
        if let detail = explicitOuterwearDetail(in: productName) {
            append(detail == "cardigan" ? .knitCardigan : .outerwear)
        }
        if containsAny(productName, ["레깅스", "leggings"]) { append(.leggings) }
        if containsAny(productName, ["스커트", "스코츠", "skirt", "skort"]) { append(.skirt) }
        if containsAny(productName, ["데님", "청바지", "denim", "jeans"]) { append(.denim) }
        if containsAny(productName, [
            "팬츠", "바지", "쇼츠", "반바지", "pants", "trousers", "shorts", "슬랙스", "slacks"
        ]) {
            append(.pants)
        }
        if containsAny(productName, ["원피스", "점프수트", "점프 슈트", "jumpsuit"])
            || containsEnglishWord("dress", in: productName) {
            append(.dress)
        }
        if containsExplicitBra(in: productName)
            || containsAny(productName, [
                "브리프", "트렁크", "복서", "팬티", "속바지",
                "briefs", "trunks", "boxer", "panty"
            ]) {
            append(.underwear)
        }
        return families
    }

    private static func explicitFamily(
        for detail: ClosetDetailCategory
    ) -> ComparisonGarmentFamily? {
        switch detail {
        case .sleeveless, .shortSleeve, .threeQuarterSleeve, .longSleeve, .poloShirt:
            return .tshirt
        case .shirt, .blouse:
            return .shirt
        case .knitTop, .cardigan:
            return .knitCardigan
        case .sweatshirt:
            return .sweatshirt
        case .hoodie:
            return .hoodie
        case .shortPants, .croppedPants, .threeQuarterPants, .nineTenthsPants,
             .longPants, .shorts, .slacks, .trainingPants:
            return .pants
        case .denim:
            return .denim
        case .shortLeggings, .threeQuarterLeggings, .nineTenthsLeggings,
             .longLeggings, .leggings:
            return .leggings
        case .skirt:
            return .skirt
        case .jumper, .jacket, .coat, .padding, .windbreaker, .anorak,
             .blazer, .blouson, .fleece, .lightPadding, .shortPadding,
             .longPadding, .trenchCoat, .mouton, .paddedVest, .vest:
            return .outerwear
        case .underwear, .menBriefs, .menTrunks, .menUndershirt,
             .womenBra, .womenPanty, .womenCamisole, .womenSlip:
            return .underwear
        case .onePiece:
            return .dress
        default:
            return nil
        }
    }

    private static func explicitLength(
        for detail: ClosetDetailCategory
    ) -> ComparisonLengthType? {
        switch detail {
        case .sleeveless: return .sleeveless
        case .shortSleeve, .shortPants, .shorts, .shortLeggings: return .short
        case .threeQuarterSleeve, .threeQuarterPants, .threeQuarterLeggings: return .threeQuarter
        case .croppedPants: return .cropped
        case .nineTenthsPants, .nineTenthsLeggings: return .nineTenths
        case .longSleeve, .longPants, .longLeggings: return .long
        default: return nil
        }
    }

    private static func inferredLength(
        from text: String,
        detailCode: String,
        categoryCode: String
    ) -> ComparisonLengthType {
        if ["underwear", "homewear"].contains(categoryCode) { return .unknown }
        let sleeveAxisCategories = Set(["tops", "outerwear", "dresses"])
        if sleeveAxisCategories.contains(categoryCode) {
            if containsAny(text, ["9부", "nine tenths", "nine-tenths"]) { return .nineTenths }
            if detailCode == "sleeveless" { return .sleeveless }
            if detailCode == "short_sleeve" { return .short }
            if detailCode == "three_quarter_sleeve" { return .threeQuarter }
            if detailCode == "long_sleeve" { return .long }
            if containsAny(text, ["민소매", "나시", "슬리브리스", "sleeveless"]) {
                return .sleeveless
            }
            let hasShort = containsAny(text, [
                "반팔", "반소매", "숏슬리브", "하프 슬리브", "short sleeve", "short-sleeve", "half sleeve",
                "cap sleeve", "s/s tee", "s/s t-shirt", "s/s tshirt"
            ])
            let hasLong = containsAny(text, [
                "긴팔", "긴소매", "롱슬리브", "long sleeve", "long-sleeve",
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

    private static func containsEnglishWord(_ word: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return text.range(
            of: "(?i)(?:^|[^a-z])\(escaped)(?![a-z])",
            options: .regularExpression
        ) != nil
    }

    private static func containsStandaloneFurOuterwear(in text: String) -> Bool {
        text.range(
            of: #"(?:^|[^가-힣A-Za-z0-9])퍼\s*(?:재킷|자켓|코트)(?:$|[^가-힣A-Za-z0-9])"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func containsExplicitBra(in text: String) -> Bool {
        if containsEnglishWord("bra", in: text) { return true }
        if containsAny(text, ["브라탑", "브라렛", "스포츠브라"]) { return true }
        return text.range(
            of: #"브라(?=$|[\s(/_\-])"#,
            options: .regularExpression
        ) != nil
    }

    private static func mostSpecificCategorySource(in depths: [String], fallback: String) -> String {
        let umbrellaValues = ["원피스/스커트", "원피스 & 스커트", "속옷/홈웨어", "속옷 & 홈웨어"]
        let categoryWords = ["스커트", "skirt", "원피스", "dress", "여성 속옷 하의", "팬티", "panty", "브라", "bra",
                             "언더웨어", "underwear", "홈웨어", "라운지", "homewear", "loungewear"]
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
