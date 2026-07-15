import Foundation

enum ComparisonLengthType: String, Equatable {
    case sleeveless
    case short
    case long
    case unknown

    var displayName: String {
        switch self {
        case .sleeveless: return "민소매"
        case .short: return "반팔"
        case .long: return "긴팔"
        case .unknown: return ""
        }
    }
}

enum ComparisonGarmentFamily: String, Equatable {
    case knitCardigan
    case tshirt
    case shirt
    case sweatshirt
    case hoodie
    case pants
    case denim
    case skirt
    case outerwear
    case underwear
    case dress
    case shoes
    case accessory
    case unknown

    var displayName: String {
        switch self {
        case .knitCardigan: return "니트/가디건"
        case .tshirt: return "티셔츠"
        case .shirt: return "셔츠/블라우스"
        case .sweatshirt: return "스웨트"
        case .hoodie: return "후드"
        case .pants: return "팬츠"
        case .denim: return "데님"
        case .skirt: return "스커트"
        case .outerwear: return "아우터"
        case .underwear: return "속옷"
        case .dress: return "원피스"
        case .shoes: return "신발"
        case .accessory: return "액세서리"
        case .unknown: return "옷"
        }
    }
}

struct ComparisonProfile: Equatable {
    let majorCategory: ClothingCategory
    let garmentFamily: ComparisonGarmentFamily
    let lengthType: ComparisonLengthType
    let availableMeasurements: [MeasurementKind]
}

enum AutomaticComparisonMatchState: Equatable {
    case compatible
    case sameFamilyLengthConflict
    case requiresConfirmation
    case noCompatibleGarment
}

struct AutomaticComparisonMatchResult {
    let state: AutomaticComparisonMatchState
    let incomingProfile: ComparisonProfile
    let compatibleCandidates: [UserFit]
}

struct ComparisonProfileMatcher {
    func match(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> AutomaticComparisonMatchResult {
        let incoming = profile(for: product, detailCategory: productDetailCategory)
        let sameMajor = userFits.filter {
            $0.category.serviceGroup == incoming.majorCategory
                && gendersAreCompatible(product.productTargetGender.taxonomyCode, $0.resolvedGenderCode)
        }
        let profiled = sameMajor.map { ($0, profile(for: $0)) }

        guard incoming.garmentFamily != .unknown, incoming.lengthType != .unknown else {
            return AutomaticComparisonMatchResult(
                state: .requiresConfirmation,
                incomingProfile: incoming,
                compatibleCandidates: []
            )
        }

        let sameFamily = profiled.filter { $0.1.garmentFamily == incoming.garmentFamily }
        let compatible = sameFamily
            .filter {
                $0.1.lengthType == incoming.lengthType
                    && commonCoreMeasurementCount(incoming, $0.1) >= 2
            }
            .sorted { lhs, rhs in
                if lhs.0.isRepresentative != rhs.0.isRepresentative {
                    return lhs.0.isRepresentative
                }
                let lhsCount = commonCoreMeasurementCount(incoming, lhs.1)
                let rhsCount = commonCoreMeasurementCount(incoming, rhs.1)
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                if lhs.0.updatedAt != rhs.0.updatedAt { return lhs.0.updatedAt > rhs.0.updatedAt }
                return lhs.0.id.uuidString < rhs.0.id.uuidString
            }
            .map(\.0)

        if !compatible.isEmpty {
            return AutomaticComparisonMatchResult(state: .compatible, incomingProfile: incoming, compatibleCandidates: compatible)
        }

        let hasLengthConflict = sameFamily.contains {
            $0.1.lengthType != .unknown && $0.1.lengthType != incoming.lengthType
        }
        return AutomaticComparisonMatchResult(
            state: hasLengthConflict ? .sameFamilyLengthConflict : .noCompatibleGarment,
            incomingProfile: incoming,
            compatibleCandidates: []
        )
    }

    func manualCandidates(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [UserFit] {
        let incoming = profile(for: product, detailCategory: productDetailCategory)
        return userFits
            .filter { $0.category.serviceGroup == incoming.majorCategory }
            .sorted { lhs, rhs in
                let lhsProfile = profile(for: lhs)
                let rhsProfile = profile(for: rhs)
                let lhsFamily = lhsProfile.garmentFamily == incoming.garmentFamily
                let rhsFamily = rhsProfile.garmentFamily == incoming.garmentFamily
                if lhsFamily != rhsFamily { return lhsFamily }
                if lhs.isRepresentative != rhs.isRepresentative { return lhs.isRepresentative }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func manualMismatch(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        selectedItem: UserFit
    ) -> (excludedKinds: [MeasurementKind], note: String?) {
        let incoming = profile(for: product, detailCategory: productDetailCategory)
        let selected = profile(for: selectedItem)
        guard incoming.lengthType != .unknown,
              selected.lengthType != .unknown,
              incoming.lengthType != selected.lengthType else {
            return ([], nil)
        }

        if incoming.majorCategory == .bottom {
            return ([.totalLength], "바지 길이 형태가 달라 총장은 비교에서 제외했어요.")
        }
        if incoming.majorCategory == .top || incoming.majorCategory == .outer {
            return ([.sleeveLength], "소매 형태가 달라 소매 길이는 비교에서 제외했어요.")
        }
        return ([], nil)
    }

    func candidateNote(product: Product, productDetailCategory: ClosetDetailCategory, item: UserFit) -> String? {
        let incoming = profile(for: product, detailCategory: productDetailCategory)
        let candidate = profile(for: item)
        guard incoming.garmentFamily == candidate.garmentFamily, incoming.garmentFamily != .unknown else { return nil }
        if incoming.lengthType != .unknown, candidate.lengthType != .unknown, incoming.lengthType != candidate.lengthType {
            return "같은 \(incoming.garmentFamily.displayName) · 길이 형태 다름"
        }
        return "같은 \(incoming.garmentFamily.displayName)"
    }

    func profile(for product: Product, detailCategory: ClosetDetailCategory) -> ComparisonProfile {
        let major = product.category.serviceGroup
        let source = sourceText(
            path: product.sourceCategoryPath,
            depths: [product.sourceCategoryDepth1, product.sourceCategoryDepth2, product.sourceCategoryDepth3, product.sourceCategoryDepth4]
        )
        let family = garmentFamily(
            normalizedProductTypeCode: product.resolvedNormalizedProductTypeCode,
            source: source,
            productName: product.name,
            detailCategory: detailCategory,
            major: major
        )
        let length = lengthType(
            productName: product.name,
            source: source,
            detailCategory: detailCategory,
            major: major,
            gender: product.productTargetGender,
            measurements: product.sizes.map(\.measurements)
        )
        return ComparisonProfile(
            majorCategory: major,
            garmentFamily: family,
            lengthType: length,
            availableMeasurements: availableMeasurements(product.sizes.map(\.measurements))
        )
    }

    func profile(for item: UserFit) -> ComparisonProfile {
        let major = item.category.serviceGroup
        let source = sourceText(
            path: item.sourceCategoryPath ?? item.sourceProduct?.sourceCategoryPath,
            depths: [item.sourceCategoryDepth1, item.sourceCategoryDepth2, item.sourceCategoryDepth3, item.sourceCategoryDepth4]
        )
        let family = garmentFamily(
            normalizedProductTypeCode: item.resolvedNormalizedProductTypeCode,
            source: source,
            productName: item.productName,
            detailCategory: item.detailCategory,
            major: major
        )
        let length = lengthType(
            productName: item.productName,
            source: source,
            detailCategory: item.detailCategory,
            major: major,
            gender: item.gender,
            measurements: [item.measurements]
        )
        return ComparisonProfile(
            majorCategory: major,
            garmentFamily: family,
            lengthType: length,
            availableMeasurements: availableMeasurements([item.measurements])
        )
    }

    private func garmentFamily(
        normalizedProductTypeCode: String?,
        source: String,
        productName: String,
        detailCategory: ClosetDetailCategory,
        major: ClothingCategory
    ) -> ComparisonGarmentFamily {
        normalizedProductTypeCode.flatMap(family(forNormalizedProductTypeCode:))
            ?? familyKeywordMatch(source)
            ?? familyKeywordMatch(productName)
            ?? family(for: detailCategory, major: major)
    }

    private func family(forNormalizedProductTypeCode code: String) -> ComparisonGarmentFamily? {
        switch code {
        case "tops.knit_sweater": return .knitCardigan
        case "tops.tshirt": return .tshirt
        default: return nil
        }
    }

    private func gendersAreCompatible(_ incoming: String, _ candidate: String) -> Bool {
        if incoming == "unknown" || candidate == "unknown" { return true }
        if incoming == "unisex" || candidate == "unisex" { return true }
        let kids = Set(["boys", "girls", "kids_unisex"])
        if kids.contains(incoming) || kids.contains(candidate) {
            return kids.contains(incoming) && kids.contains(candidate)
        }
        return incoming == candidate
    }

    private func familyKeywordMatch(_ value: String) -> ComparisonGarmentFamily? {
        let value = normalized(value)
        let rules: [(ComparisonGarmentFamily, [String])] = [
            (.knitCardigan, ["니트", "가디건", "스웨터", "knit", "cardigan", "sweater"]),
            (.hoodie, ["후드", "hoodie"]),
            (.sweatshirt, ["스웨트", "맨투맨", "sweatshirt"]),
            (.tshirt, ["티셔츠", "t-shirt", "tee"]),
            (.shirt, ["셔츠", "블라우스", "shirt", "blouse"]),
            (.denim, ["데님", "청바지", "denim", "jeans"]),
            (.skirt, ["스커트", "치마", "skirt"]),
            (.pants, ["팬츠", "바지", "쇼츠", "shorts", "trousers", "pants"]),
            (.outerwear, ["재킷", "자켓", "코트", "점퍼", "패딩", "jacket", "coat"]),
            (.underwear, ["언더웨어", "속옷", "브라", "팬티", "underwear"]),
            (.dress, ["원피스", "dress"]),
            (.shoes, ["신발", "스니커즈", "슈즈", "shoes", "sneakers"])
        ]
        return rules.first { rule in rule.1.contains { value.contains($0) } }?.0
    }

    private func family(for detail: ClosetDetailCategory, major: ClothingCategory) -> ComparisonGarmentFamily {
        switch detail {
        case .knitTop, .cardigan, .vest: return .knitCardigan
        case .sleeveless, .shortSleeve, .longSleeve: return .tshirt
        case .shirt, .blouse: return .shirt
        case .sweatshirt: return .sweatshirt
        case .hoodie: return .hoodie
        case .denim: return .denim
        case .skirt: return .skirt
        case .slacks, .shorts, .trainingPants, .leggings: return .pants
        case .jumper, .jacket, .coat, .padding: return .outerwear
        case .underwear, .menBriefs, .menTrunks, .menUndershirt, .womenBra, .womenPanty, .womenCamisole, .womenSlip: return .underwear
        case .onePiece: return .dress
        case .sneakers, .runningShoes, .loafers, .boots, .sandals, .heels: return .shoes
        case .watch, .ring, .bracelet, .necklace, .bag, .hat, .belt, .scarf: return .accessory
        default:
            switch major {
            case .outer: return .outerwear
            case .underwear: return .underwear
            case .dress: return .dress
            case .shoes: return .shoes
            case .accessory: return .accessory
            default: return .unknown
            }
        }
    }

    private func lengthType(
        productName: String,
        source: String,
        detailCategory: ClosetDetailCategory,
        major: ClothingCategory,
        gender: UserGender,
        measurements: [GarmentMeasurements]
    ) -> ComparisonLengthType {
        if let value = keywordLength(productName, major: major) { return value }
        if let value = keywordLength(source, major: major) { return value }
        if let value = detailLength(detailCategory, major: major) { return value }
        guard gender != .kids, gender != .baby else { return .unknown }

        let values: [Double]
        if major == .bottom {
            values = measurements.map(\.totalLength).filter { $0 > 0 && $0.isFinite }
        } else if major == .top || major == .outer {
            values = measurements.map(\.sleeveLength).filter { $0 > 0 && $0.isFinite }
        } else {
            return .unknown
        }
        guard let median = median(values) else { return .unknown }
        if major == .bottom {
            if median <= 70 { return .short }
            if median >= 85 { return .long }
        } else {
            if median <= 35 { return .short }
            if median >= 45 { return .long }
        }
        return .unknown
    }

    private func keywordLength(_ text: String, major: ClothingCategory) -> ComparisonLengthType? {
        let value = normalized(text)
        if major == .bottom {
            if ["반바지", "쇼츠", "숏 팬츠", "쇼트 팬츠", "버뮤다", "shorts"].contains(where: value.contains) { return .short }
            if ["긴바지", "롱 팬츠", "long pants"].contains(where: value.contains) { return .long }
            return nil
        }
        if ["민소매", "나시", "슬리브리스", "sleeveless"].contains(where: value.contains) { return .sleeveless }
        if ["반팔", "반소매", "숏슬리브", "short sleeve", "half sleeve"].contains(where: value.contains) { return .short }
        if ["긴팔", "긴소매", "롱슬리브", "long sleeve"].contains(where: value.contains) { return .long }
        return nil
    }

    private func detailLength(_ detail: ClosetDetailCategory, major: ClothingCategory) -> ComparisonLengthType? {
        switch detail {
        case .sleeveless, .vest, .womenCamisole: return .sleeveless
        case .shortSleeve, .shortPants, .shorts, .shortLeggings: return .short
        case .longSleeve, .longPants, .longLeggings: return .long
        default: return nil
        }
    }

    private func availableMeasurements(_ values: [GarmentMeasurements]) -> [MeasurementKind] {
        MeasurementKind.allCases.filter { kind in values.contains { $0.value(for: kind) > 0 && $0.value(for: kind).isFinite } }
    }

    private func commonCoreMeasurementCount(_ lhs: ComparisonProfile, _ rhs: ComparisonProfile) -> Int {
        let core: [MeasurementKind]
        switch lhs.majorCategory {
        case .top, .outer: core = [.shoulder, .chest, .totalLength, .sleeveLength]
        case .bottom: core = [.waist, .hip, .thigh, .totalLength]
        default: core = lhs.availableMeasurements
        }
        return core.filter { lhs.availableMeasurements.contains($0) && rhs.availableMeasurements.contains($0) }.count
    }

    private func sourceText(path: String?, depths: [String?]) -> String {
        let depthText = depths.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !depthText.isEmpty { return depthText.joined(separator: " > ") }
        return path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
