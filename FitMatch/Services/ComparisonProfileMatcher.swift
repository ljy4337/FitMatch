import Foundation

enum GarmentLengthInferencePolicy {
    struct Sample {
        let value: Double
        let code: MeasurementCode
        let methodSource: String
    }

    static func infer(
        category: ClothingCategory,
        gender: UserGender,
        samples: [Sample],
        fallbackMeasurements: [GarmentMeasurements] = []
    ) -> ComparisonLengthType {
        let major = category.serviceGroup
        guard major == .top || major == .outer || major == .bottom else {
            return .unknown
        }

        if major == .bottom {
            if let inferred = inferBottom(gender: gender, samples: samples) {
                return inferred
            }
            let values = fallbackMeasurements
                .map(\.totalLength)
                .filter { $0.isFinite && $0 > 0 }
            guard let value = median(values) else { return .unknown }
            return value <= fallbackBottomBoundary(for: gender) ? .short : .long
        }

        if let inferred = inferSleeve(gender: gender, samples: samples) {
            return inferred
        }
        let values = fallbackMeasurements
            .map(\.sleeveLength)
            .filter { $0.isFinite && $0 > 0 }
        guard let value = median(values) else { return .unknown }
        return value <= fallbackSleeveBoundary(for: gender) ? .short : .long
    }

    static func samples(from records: [GarmentMeasurementRecord]) -> [Sample] {
        records.compactMap {
            guard $0.isComparable, $0.value.isFinite, $0.value > 0 else { return nil }
            return Sample(value: $0.value, code: $0.measurementCode, methodSource: $0.methodSource)
        }
    }

    static func samples(from sizes: [ParsedProductSize]) -> [Sample] {
        sizes.flatMap(\.measurementRecords).compactMap {
            guard $0.semanticStatus == .mapped,
                  $0.measurementCode != .unknown,
                  $0.measurementCode != .legacyUnknown,
                  $0.value.isFinite,
                  $0.value > 0 else {
                return nil
            }
            return Sample(value: $0.value, code: $0.measurementCode, methodSource: $0.methodSource)
        }
    }

    private static func inferSleeve(
        gender: UserGender,
        samples: [Sample]
    ) -> ComparisonLengthType? {
        let sleeveSamples = samples.filter {
            $0.code == .sleeveShoulderSeamToCuff
                || $0.code == .sleeveCenterBackToCuff
                || $0.code == .sleeveRaglanNeckToCuff
        }
        for code in [
            MeasurementCode.sleeveShoulderSeamToCuff,
            .sleeveCenterBackToCuff,
            .sleeveRaglanNeckToCuff
        ] {
            let matching = sleeveSamples.filter { $0.code == code }
            guard let value = median(matching.map(\.value)) else { continue }
            let platform = dominantPlatform(in: matching)
            let boundary = sleeveBoundary(code: code, platform: platform, gender: gender)
            return value <= boundary ? .short : .long
        }
        return nil
    }

    private static func inferBottom(
        gender: UserGender,
        samples: [Sample]
    ) -> ComparisonLengthType? {
        for code in [
            MeasurementCode.pantsInseamCrotchToHem,
            .pantsOutseamWaistToHem
        ] {
            let matching = samples.filter { $0.code == code }
            guard let value = median(matching.map(\.value)) else { continue }
            let platform = dominantPlatform(in: matching)
            let boundary: Double
            if code == .pantsInseamCrotchToHem {
                boundary = platform == "uniqlo" ? 46.5 : 48
            } else if platform == "musinsa" {
                switch gender {
                case .men: boundary = 84.0
                case .women: boundary = 65.0
                default: boundary = 74.0
                }
            } else {
                boundary = fallbackBottomBoundary(for: gender)
            }
            return value <= boundary ? .short : .long
        }
        return nil
    }

    private static func sleeveBoundary(
        code: MeasurementCode,
        platform: String?,
        gender: UserGender
    ) -> Double {
        if platform == "uniqlo", code == .sleeveCenterBackToCuff {
            switch gender {
            case .men: return 67.0
            case .women: return 60.0
            case .kids, .baby: return 34.5
            default: return 63.5
            }
        }
        if platform == "musinsa", code == .sleeveShoulderSeamToCuff {
            switch gender {
            case .men: return 52.0
            case .women: return 43.0
            default: return 47.5
            }
        }
        switch code {
        case .sleeveShoulderSeamToCuff: return fallbackSleeveBoundary(for: gender)
        case .sleeveCenterBackToCuff: return gender == .men ? 67 : (gender == .women ? 60 : 63.5)
        case .sleeveRaglanNeckToCuff: return 52.5
        default: return fallbackSleeveBoundary(for: gender)
        }
    }

    private static func fallbackSleeveBoundary(for gender: UserGender) -> Double {
        switch gender {
        case .men: return 50
        case .women: return 42
        default: return 46
        }
    }

    private static func fallbackBottomBoundary(for gender: UserGender) -> Double {
        switch gender {
        case .men: return 84
        case .women: return 65
        default: return 74
        }
    }

    private static func dominantPlatform(in samples: [Sample]) -> String? {
        let values = samples.compactMap { platform(for: $0.methodSource) }
        return Dictionary(grouping: values, by: { $0 })
            .max { $0.value.count < $1.value.count }?
            .key
    }

    private static func platform(for methodSource: String) -> String? {
        let normalized = methodSource.lowercased()
        if normalized.contains("uniqlo") { return "uniqlo" }
        if normalized.contains("musinsa") { return "musinsa" }
        return nil
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

struct ComparisonProfile: Equatable {
    let majorCategory: ClothingCategory
    let garmentFamily: ComparisonGarmentFamily
    let lengthType: ComparisonLengthType
    let constructionType: ComparisonConstructionType
    let availableMeasurements: [MeasurementKind]

    var garmentType: ComparisonGarmentFamily { garmentFamily }
    var sleeveType: ComparisonLengthType { lengthType }
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
    struct CandidateDiagnostic {
        let itemName: String
        let incomingGender: String
        let candidateGender: String
        let incomingFamily: ComparisonGarmentFamily
        let candidateFamily: ComparisonGarmentFamily
        let incomingLength: ComparisonLengthType
        let candidateLength: ComparisonLengthType
        let candidateEligibility: Bool?
        let commonCoreMeasurementCount: Int
        let minimumCommonMeasurementCount: Int
        let exclusionReasons: [String]

        var logDescription: String {
            let result = exclusionReasons.isEmpty ? "compatible" : exclusionReasons.joined(separator: ",")
            let eligibility = candidateEligibility.map(String.init) ?? "nil"
            return "item=\(itemName), incomingGender=\(incomingGender), candidateGender=\(candidateGender), incomingFamily=\(incomingFamily.rawValue), candidateFamily=\(candidateFamily.rawValue), incomingLength=\(incomingLength.rawValue), candidateLength=\(candidateLength.rawValue), eligibility=\(eligibility), commonCore=\(commonCoreMeasurementCount)/\(minimumCommonMeasurementCount), result=\(result)"
        }
    }

    func match(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> AutomaticComparisonMatchResult {
        let incoming = profile(for: product, detailCategory: productDetailCategory)
        guard product.canonicalEligibility != false else {
            return AutomaticComparisonMatchResult(
                state: .noCompatibleGarment,
                incomingProfile: incoming,
                compatibleCandidates: []
            )
        }
        let candidates = userFits.filter { $0.canonicalEligibility != false }
        let profiled = candidates.map { ($0, profile(for: $0)) }

        guard incoming.garmentFamily != .unknown,
              !requiresLengthClassification(incoming.garmentFamily)
                || incoming.lengthType != .unknown else {
            return AutomaticComparisonMatchResult(
                state: .requiresConfirmation,
                incomingProfile: incoming,
                compatibleCandidates: []
            )
        }

        let sameFamily = profiled.filter {
            garmentFamiliesAreCompatible($0.1.garmentFamily, incoming.garmentFamily)
                && gendersAreCompatible(
                    product.productTargetGender.taxonomyCode,
                    $0.0.resolvedGenderCode,
                    family: incoming.garmentFamily
                )
        }
        let compatible = sameFamily
            .filter {
                lengthsAreCompatible($0.1, incoming)
                    && constructionsAreCompatible(incoming.constructionType, $0.1.constructionType)
                    && commonCoreMeasurementCount(incoming, $0.1)
                        >= minimumCommonMeasurementCount(for: incoming.garmentFamily)
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

        let hasLengthConflict = requiresLengthClassification(incoming.garmentFamily) && sameFamily.contains {
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
        guard product.canonicalEligibility != false else { return [] }
        return userFits
            .filter { $0.canonicalEligibility != false }
            .sorted { lhs, rhs in
                let lhsProfile = profile(for: lhs)
                let rhsProfile = profile(for: rhs)
                let lhsFamily = garmentFamiliesAreCompatible(
                    lhsProfile.garmentFamily, incoming.garmentFamily
                )
                let rhsFamily = garmentFamiliesAreCompatible(
                    rhsProfile.garmentFamily, incoming.garmentFamily
                )
                if lhsFamily != rhsFamily { return lhsFamily }
                if lhs.isRepresentative != rhs.isRepresentative { return lhs.isRepresentative }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func candidateDiagnostics(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [CandidateDiagnostic] {
        let incoming = profile(for: product, detailCategory: productDetailCategory)
        let incomingGender = product.productTargetGender.taxonomyCode
        let minimum = minimumCommonMeasurementCount(for: incoming.garmentFamily)

        return userFits.map { item in
            let candidate = profile(for: item)
            var reasons: [String] = []
            if product.canonicalEligibility == false { reasons.append("incoming_ineligible") }
            if item.canonicalEligibility == false { reasons.append("candidate_ineligible") }
            if !gendersAreCompatible(
                incomingGender,
                item.resolvedGenderCode,
                family: incoming.garmentFamily
            ) { reasons.append("gender_incompatible") }
            if incoming.garmentFamily == .unknown { reasons.append("incoming_family_unknown") }
            if !garmentFamiliesAreCompatible(candidate.garmentFamily, incoming.garmentFamily) { reasons.append("family_incompatible") }
            if !lengthsAreCompatible(candidate, incoming) { reasons.append("length_incompatible") }
            if !constructionsAreCompatible(incoming.constructionType, candidate.constructionType) { reasons.append("construction_incompatible") }
            let commonCount = commonCoreMeasurementCount(incoming, candidate)
            if commonCount < minimum { reasons.append("common_measurements_insufficient") }

            return CandidateDiagnostic(
                itemName: item.productName,
                incomingGender: incomingGender,
                candidateGender: item.resolvedGenderCode,
                incomingFamily: incoming.garmentFamily,
                candidateFamily: candidate.garmentFamily,
                incomingLength: incoming.lengthType,
                candidateLength: candidate.lengthType,
                candidateEligibility: item.canonicalEligibility,
                commonCoreMeasurementCount: commonCount,
                minimumCommonMeasurementCount: minimum,
                exclusionReasons: reasons
            )
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
            if hasDirectSourceComparison(
                kind: .sleeveLength,
                product: product,
                selectedItem: selectedItem
            ) {
                return ([], nil)
            }
            return ([.sleeveLength], "소매 형태가 달라 소매 길이는 비교에서 제외했어요.")
        }
        return ([], nil)
    }

    func hasSamePlatformOfficialFormat(
        product: Product,
        selectedItem: UserFit,
        minimumCommonMeasurementCount: Int = 2
    ) -> Bool {
        MeasurementKind.allCases.filter {
            hasDirectSourceComparison(
                kind: $0,
                product: product,
                selectedItem: selectedItem
            )
        }.count >= minimumCommonMeasurementCount
    }

    func candidateNote(product: Product, productDetailCategory: ClosetDetailCategory, item: UserFit) -> String? {
        let incoming = profile(for: product, detailCategory: productDetailCategory)
        let candidate = profile(for: item)
        guard garmentFamiliesAreCompatible(incoming.garmentFamily, candidate.garmentFamily),
              incoming.garmentFamily != .unknown else {
            return "다른 종류 · 공통 실측만 참고"
        }
        if incoming.lengthType != .unknown, candidate.lengthType != .unknown, incoming.lengthType != candidate.lengthType {
            return "길이 형태 다름 · 일부 항목 제외"
        }
        if incoming.constructionType != .unknown,
           candidate.constructionType != .unknown,
           incoming.constructionType != candidate.constructionType {
            return "봉제 구조 다름 · 호환 항목만 참고"
        }
        return "같은 \(incoming.garmentFamily.displayName)"
    }

    func garmentFamiliesAreCompatible(
        _ lhs: ComparisonGarmentFamily,
        _ rhs: ComparisonGarmentFamily
    ) -> Bool {
        if lhs == rhs { return true }
        // 데님과 치노·슬랙스·면바지는 원본 소재 분류는 다르지만,
        // 모두 같은 길이의 하의 실측 항목으로 비교할 수 있다.
        return Set([lhs, rhs]) == Set([.denim, .pants])
    }

    func lengthsAreCompatible(
        _ lhs: ComparisonProfile,
        _ rhs: ComparisonProfile
    ) -> Bool {
        guard requiresLengthClassification(lhs.garmentFamily)
                || requiresLengthClassification(rhs.garmentFamily) else {
            return true
        }
        return lhs.lengthType != .unknown && lhs.lengthType == rhs.lengthType
    }

    func minimumCommonMeasurementCount(for family: ComparisonGarmentFamily) -> Int {
        family == .shoes ? 1 : 2
    }

    private func requiresLengthClassification(_ family: ComparisonGarmentFamily) -> Bool {
        switch family {
        case .knitCardigan, .tshirt, .shirt, .sweatshirt, .hoodie,
             .pants, .denim, .leggings, .outerwear, .leatherJacket:
            return true
        case .skirt, .underwear, .dress, .shoes, .accessory, .unknown:
            return false
        }
    }

    func profile(for product: Product, detailCategory: ClosetDetailCategory) -> ComparisonProfile {
        if product.canonicalProfileSnapshotJSON == nil {
            let resolver = CanonicalComparisonProfileResolver()
            let profile = resolver.resolve(
                source: product.sourceName,
                externalCategoryID: [product.categoryDepth4Code, product.categoryDepth3Code,
                                     product.categoryDepth2Code, product.categoryDepth1Code]
                    .compactMap { $0 }.first { !$0.isEmpty },
                target: canonicalTarget(for: product.productTargetGender),
                sourceCategoryPath: product.sourceCategoryPath ?? product.baseCategoryFullPath
            )
            resolver.apply(profile, to: product)
        }
        let major = product.category.serviceGroup
        let source = sourceText(
            path: product.sourceCategoryPath,
            depths: [product.sourceCategoryDepth1, product.sourceCategoryDepth2, product.sourceCategoryDepth3, product.sourceCategoryDepth4]
        )
        let inferredFamily = garmentFamily(
            normalizedProductTypeCode: product.resolvedNormalizedProductTypeCode,
            source: source,
            productName: product.name,
            detailCategory: detailCategory,
            major: major
        )
        let inferredLength = lengthType(
            productName: product.name,
            source: source,
            detailCategory: detailCategory,
            major: major,
            gender: product.productTargetGender,
            measurements: product.sizes.map(\.measurements),
            measurementRecords: product.sizes.flatMap(\.measurementRecords)
        )
        let inferredConstruction = constructionType(product.sizes.flatMap(\.measurementRecords))
        let family = storedGarmentType(product.garmentTypeRawValue, fallback: inferredFamily)
        let length = storedSleeveType(product.sleeveTypeRawValue, fallback: inferredLength)
        let construction = storedConstructionType(product.constructionTypeRawValue, fallback: inferredConstruction)
        storeResolvedAttributes(
            garmentType: family,
            sleeveType: length,
            constructionType: construction,
            on: product
        )
        return ComparisonProfile(
            majorCategory: major,
            garmentFamily: family,
            lengthType: length,
            constructionType: construction,
            availableMeasurements: availableMeasurements(product.sizes.map(\.measurements))
        )
    }

    func profile(for item: UserFit) -> ComparisonProfile {
        if item.canonicalProfileSnapshotJSON == nil {
            if let sourceProfile = item.sourceProduct?.canonicalProfileSnapshot {
                CanonicalComparisonProfileResolver().apply(sourceProfile, to: item)
            } else {
                let resolver = CanonicalComparisonProfileResolver()
                let profile = resolver.resolve(
                    source: item.sourceName,
                    externalCategoryID: nil,
                    target: canonicalTarget(for: item.gender),
                    sourceCategoryPath: item.sourceCategoryPath ?? item.sourceProduct?.sourceCategoryPath
                )
                resolver.apply(profile, to: item)
            }
        }
        let major = item.category.serviceGroup
        let source = sourceText(
            path: item.sourceCategoryPath ?? item.sourceProduct?.sourceCategoryPath,
            depths: [item.sourceCategoryDepth1, item.sourceCategoryDepth2, item.sourceCategoryDepth3, item.sourceCategoryDepth4]
        )
        let inferredFamily = garmentFamily(
            normalizedProductTypeCode: item.resolvedNormalizedProductTypeCode,
            source: source,
            productName: item.productName,
            detailCategory: item.detailCategory,
            major: major
        )
        let inferredLength = lengthType(
            productName: item.productName,
            source: source,
            detailCategory: item.detailCategory,
            major: major,
            gender: item.gender,
            measurements: [item.measurements],
            measurementRecords: item.measurementRecords
        )
        let inferredConstruction = constructionType(item.measurementRecords)
        let family = storedGarmentType(item.garmentTypeRawValue, fallback: inferredFamily)
        let length = storedSleeveType(item.sleeveTypeRawValue, fallback: inferredLength)
        let construction = storedConstructionType(item.constructionTypeRawValue, fallback: inferredConstruction)
        storeResolvedAttributes(
            garmentType: family,
            sleeveType: length,
            constructionType: construction,
            on: item
        )
        return ComparisonProfile(
            majorCategory: major,
            garmentFamily: family,
            lengthType: length,
            constructionType: construction,
            availableMeasurements: availableMeasurements([item.measurements])
        )
    }

    private func storedGarmentType(
        _ rawValue: String?,
        fallback: ComparisonGarmentFamily
    ) -> ComparisonGarmentFamily {
        guard let rawValue,
              let stored = ComparisonGarmentFamily(rawValue: rawValue),
              stored != .unknown else {
            return fallback
        }
        return stored
    }

    private func canonicalTarget(for gender: UserGender) -> String {
        switch gender {
        case .men: return "MEN"
        case .women: return "WOMEN"
        case .kids: return "KIDS"
        case .baby: return "BABY"
        case .unisex, .unknown: return "UNKNOWN"
        }
    }

    private func storedSleeveType(
        _ rawValue: String?,
        fallback: ComparisonLengthType
    ) -> ComparisonLengthType {
        guard let rawValue,
              let stored = ComparisonLengthType(rawValue: rawValue),
              stored != .unknown else {
            return fallback
        }
        return stored
    }

    private func storedConstructionType(
        _ rawValue: String?,
        fallback: ComparisonConstructionType
    ) -> ComparisonConstructionType {
        guard let rawValue,
              let stored = ComparisonConstructionType(rawValue: rawValue),
              stored != .unknown else {
            return fallback
        }
        return stored
    }

    private func storeResolvedAttributes(
        garmentType: ComparisonGarmentFamily,
        sleeveType: ComparisonLengthType,
        constructionType: ComparisonConstructionType,
        on product: Product
    ) {
        if garmentType != .unknown, product.garmentType != garmentType { product.garmentType = garmentType }
        if sleeveType != .unknown, product.sleeveType != sleeveType { product.sleeveType = sleeveType }
        if constructionType != .unknown, product.constructionType != constructionType { product.constructionType = constructionType }
    }

    private func storeResolvedAttributes(
        garmentType: ComparisonGarmentFamily,
        sleeveType: ComparisonLengthType,
        constructionType: ComparisonConstructionType,
        on item: UserFit
    ) {
        if garmentType != .unknown, item.garmentType != garmentType { item.garmentType = garmentType }
        if sleeveType != .unknown, item.sleeveType != sleeveType { item.sleeveType = sleeveType }
        if constructionType != .unknown, item.constructionType != constructionType { item.constructionType = constructionType }
    }

    private func constructionType(_ records: [GarmentMeasurementRecord]) -> ComparisonConstructionType {
        let codes = Set(records.filter(\.isComparable).map(\.measurementCode))
        if codes.contains(.sleeveRaglanNeckToCuff) { return .raglan }
        if codes.contains(.sleeveShoulderSeamToCuff) { return .setIn }
        return .unknown
    }

    private func constructionsAreCompatible(
        _ lhs: ComparisonConstructionType,
        _ rhs: ComparisonConstructionType
    ) -> Bool {
        lhs == .unknown || rhs == .unknown || lhs == rhs
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

    private func gendersAreCompatible(
        _ incoming: String,
        _ candidate: String,
        family: ComparisonGarmentFamily
    ) -> Bool {
        if incoming == "unknown" || candidate == "unknown" { return true }
        if incoming == "unisex" || candidate == "unisex" { return true }
        let kids = Set(["boys", "girls", "kids_unisex"])
        if kids.contains(incoming) || kids.contains(candidate) {
            return kids.contains(incoming) && kids.contains(candidate)
        }
        let adults = Set(["male", "female"])
        let adultCrossGenderFamilies: Set<ComparisonGarmentFamily> = [
            .knitCardigan, .tshirt, .shirt, .sweatshirt, .hoodie,
            .pants, .denim, .leggings, .skirt, .outerwear,
            .leatherJacket, .shoes
        ]
        if adults.contains(incoming), adults.contains(candidate) {
            return incoming == candidate || adultCrossGenderFamilies.contains(family)
        }
        return incoming == candidate
    }

    private func familyKeywordMatch(_ value: String) -> ComparisonGarmentFamily? {
        let value = normalized(value)
        let rules: [(ComparisonGarmentFamily, [String])] = [
            (.leatherJacket, ["레더 재킷", "레더 자켓", "라이더스", "leather jacket", "riders jacket"]),
            (.knitCardigan, ["니트", "가디건", "스웨터", "knit", "cardigan", "sweater"]),
            (.hoodie, ["후드", "hoodie"]),
            (.sweatshirt, ["스웨트", "맨투맨", "sweatshirt"]),
            (.tshirt, ["티셔츠", "t-shirt", "tee"]),
            (.shirt, ["셔츠", "블라우스", "shirt", "blouse"]),
            (.denim, ["데님", "청바지", "denim", "jeans"]),
            (.skirt, ["스커트", "치마", "skirt"]),
            (.leggings, ["레깅스", "leggings"]),
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
        case .sleeveless, .shortSleeve, .threeQuarterSleeve, .longSleeve: return .tshirt
        case .shirt, .blouse: return .shirt
        case .sweatshirt: return .sweatshirt
        case .hoodie: return .hoodie
        case .denim: return .denim
        case .skirt: return .skirt
        case .shortPants, .croppedPants, .threeQuarterPants, .nineTenthsPants,
             .longPants, .slacks, .shorts, .trainingPants: return .pants
        case .shortLeggings, .threeQuarterLeggings, .nineTenthsLeggings,
             .longLeggings, .leggings: return .leggings
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
        measurements: [GarmentMeasurements],
        measurementRecords: [GarmentMeasurementRecord]
    ) -> ComparisonLengthType {
        if let value = keywordLength(productName, major: major) { return value }
        if let value = keywordLength(source, major: major) { return value }
        if let value = detailLength(detailCategory, major: major) { return value }
        return GarmentLengthInferencePolicy.infer(
            category: major,
            gender: gender,
            samples: GarmentLengthInferencePolicy.samples(from: measurementRecords),
            fallbackMeasurements: measurements
        )
    }

    private func keywordLength(_ text: String, major: ClothingCategory) -> ComparisonLengthType? {
        let value = normalized(text)
        if major == .bottom {
            if ["반바지", "쇼츠", "숏 팬츠", "쇼트 팬츠", "버뮤다", "shorts"].contains(where: value.contains) { return .short }
            if ["7부", "three quarter", "3/4"].contains(where: value.contains) { return .threeQuarter }
            if ["크롭", "cropped"].contains(where: value.contains) { return .cropped }
            if ["9부", "nine tenths", "ankle"].contains(where: value.contains) { return .nineTenths }
            if ["긴바지", "롱 팬츠", "long pants"].contains(where: value.contains) { return .long }
            return nil
        }
        if ["민소매", "나시", "슬리브리스", "sleeveless"].contains(where: value.contains) { return .sleeveless }
        if ["반팔", "반소매", "숏슬리브", "short sleeve", "half sleeve"].contains(where: value.contains) { return .short }
        if ["7부", "three quarter", "3/4"].contains(where: value.contains) { return .threeQuarter }
        if ["긴팔", "긴소매", "롱슬리브", "long sleeve"].contains(where: value.contains) { return .long }
        return nil
    }

    private func detailLength(_ detail: ClosetDetailCategory, major: ClothingCategory) -> ComparisonLengthType? {
        switch detail {
        case .sleeveless, .vest, .paddedVest, .womenCamisole: return .sleeveless
        case .shortSleeve, .shortPants, .shorts, .shortLeggings: return .short
        case .threeQuarterSleeve, .threeQuarterPants, .threeQuarterLeggings: return .threeQuarter
        case .croppedPants: return .cropped
        case .nineTenthsPants, .nineTenthsLeggings: return .nineTenths
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
        case .top: core = [.shoulder, .chest, .totalLength, .sleeveLength]
        case .outer: core = [.shoulder, .chest, .totalLength, .sleeveLength, .hem]
        case .bottom: core = [.waist, .hip, .thigh, .totalLength]
        default: core = lhs.availableMeasurements
        }
        return core.filter { lhs.availableMeasurements.contains($0) && rhs.availableMeasurements.contains($0) }.count
    }

    private func hasDirectSourceComparison(
        kind: MeasurementKind,
        product: Product,
        selectedItem: UserFit
    ) -> Bool {
        let productRecords = product.sizes
            .flatMap(\.measurementRecords)
            .filter { $0.displayKind == kind.displayKind && $0.isComparable }
        let referenceRecords = selectedItem.measurementRecords
            .filter { $0.displayKind == kind.displayKind && $0.isComparable }

        return productRecords.contains { productRecord in
            guard let productPlatform = platform(for: productRecord.methodSource) else {
                return false
            }
            return referenceRecords.contains { referenceRecord in
                guard platform(for: referenceRecord.methodSource) == productPlatform else {
                    return false
                }
                if let productCode = normalizedSourceKey(productRecord.rawCode),
                   let referenceCode = normalizedSourceKey(referenceRecord.rawCode) {
                    return productCode == referenceCode
                }
                return normalizedSourceKey(productRecord.rawLabel)
                    == normalizedSourceKey(referenceRecord.rawLabel)
            }
        }
    }

    private func platform(for methodSource: String) -> String? {
        let normalized = methodSource.lowercased()
        if normalized.contains("uniqlo") { return "uniqlo" }
        if normalized.contains("musinsa") { return "musinsa" }
        if normalized.contains("fitmatch") || normalized.contains("manual") { return "fitmatch" }
        return nil
    }

    private func normalizedSourceKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        return normalized.isEmpty ? nil : normalized
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
