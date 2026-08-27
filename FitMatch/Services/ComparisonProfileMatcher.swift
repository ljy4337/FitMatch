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
        guard major == .top || major == .outer || major == .bottom || major == .dress else {
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
    let bodyLengthType: ComparisonLengthType
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
                state: product.canonicalResolutionMethod
                    == ParsedClosetClassificationSafetyAudit.conflictResolutionMethod
                    ? .requiresConfirmation
                    : .noCompatibleGarment,
                incomingProfile: incoming,
                compatibleCandidates: []
            )
        }
        let candidates = userFits.filter { $0.canonicalEligibility != false }
        let profiled = candidates.map { ($0, profile(for: $0)) }

        guard incoming.garmentFamily != .unknown,
              !requiresLengthClassification(incoming.garmentFamily)
                || incoming.lengthType != .unknown,
              incoming.majorCategory.serviceGroup != .outer
                || incoming.bodyLengthType != .unknown else {
            return AutomaticComparisonMatchResult(
                state: .requiresConfirmation,
                incomingProfile: incoming,
                compatibleCandidates: []
            )
        }

        let familyCompatible = profiled.filter {
            $0.1.majorCategory == incoming.majorCategory
                && garmentFamiliesAreCompatible($0.1.garmentFamily, incoming.garmentFamily)
                && gendersAreCompatible(
                    product.productTargetGender.taxonomyCode,
                    $0.0.resolvedGenderCode,
                    family: incoming.garmentFamily
                )
        }
        let directlyCompatible = familyCompatible.filter {
            categoryCompatibilityLevel(
                incoming: incoming,
                incomingDetail: productDetailCategory,
                candidate: $0.1,
                candidateDetail: $0.0.detailCategory
            ) == .direct
        }
        let profileCompatible = directlyCompatible
            .filter {
                lengthsAreCompatible($0.1, incoming)
                    && constructionsAreCompatible(incoming.constructionType, $0.1.constructionType)
                    && commonCoreMeasurementCount(incoming, $0.1)
                        >= minimumCommonMeasurementCount(for: incoming.garmentFamily)
            }
        // Profile matching is a pre-evaluator UI hint only. Running the
        // measurement scorer here would score target/reference pairs before
        // evaluator v4 has created a comparison permit.
        let compatible = profileCompatible
            .sorted { lhs, rhs in
                let lhsSameDetail = lhs.0.detailCategory == productDetailCategory
                let rhsSameDetail = rhs.0.detailCategory == productDetailCategory
                if lhsSameDetail != rhsSameDetail { return lhsSameDetail }
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

        let hasLengthConflict = familyCompatible.contains {
            (requiresLengthClassification(incoming.garmentFamily)
                && $0.1.lengthType != .unknown
                && $0.1.lengthType != incoming.lengthType)
                || (incoming.majorCategory.serviceGroup == .outer
                    && $0.1.bodyLengthType != .unknown
                    && $0.1.bodyLengthType != incoming.bodyLengthType)
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
            .compactMap { item -> (UserFit, GarmentComparisonCompatibility)? in
                let compatibility = manualComparisonCompatibility(
                    product: product,
                    productDetailCategory: productDetailCategory,
                    item: item
                )
                return compatibility.level.isAllowed ? (item, compatibility) : nil
            }
            .sorted { lhsPair, rhsPair in
                let lhs = lhsPair.0
                let rhs = rhsPair.0
                let lhsLevel = lhsPair.1.level
                let rhsLevel = rhsPair.1.level
                if lhsLevel != rhsLevel { return lhsLevel.rawValue > rhsLevel.rawValue }
                let lhsProfile = profile(for: lhs)
                let rhsProfile = profile(for: rhs)
                let lhsSameDetail = lhs.detailCategory == productDetailCategory
                let rhsSameDetail = rhs.detailCategory == productDetailCategory
                if lhsSameDetail != rhsSameDetail { return lhsSameDetail }
                let lhsSameMajor = lhsProfile.majorCategory == incoming.majorCategory
                let rhsSameMajor = rhsProfile.majorCategory == incoming.majorCategory
                if lhsSameMajor != rhsSameMajor { return lhsSameMajor }
                let lhsCompatibleDetail = detailCategoriesAreCompatible(
                    lhs.detailCategory,
                    productDetailCategory,
                    family: incoming.garmentFamily,
                    major: incoming.majorCategory
                )
                let rhsCompatibleDetail = detailCategoriesAreCompatible(
                    rhs.detailCategory,
                    productDetailCategory,
                    family: incoming.garmentFamily,
                    major: incoming.majorCategory
                )
                if lhsCompatibleDetail != rhsCompatibleDetail { return lhsCompatibleDetail }
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
            .map(\.0)
    }

    func manualComparisonCompatibility(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        item: UserFit
    ) -> GarmentComparisonCompatibility {
        let strict = comparisonCompatibility(
            product: product,
            productDetailCategory: productDetailCategory,
            item: item
        )
        guard !strict.level.isAllowed else { return strict }
        guard product.canonicalEligibility != false,
              item.canonicalEligibility != false else { return strict }

        let incoming = profile(for: product, detailCategory: productDetailCategory)
        let candidate = profile(for: item)
        guard incoming.majorCategory == candidate.majorCategory else {
            return .blocked("착용 부위가 달라 비교할 수 없어요.")
        }
        guard [.top, .bottom, .outer].contains(incoming.majorCategory.serviceGroup),
              incoming.garmentFamily != .unknown,
              candidate.garmentFamily != .unknown else {
            return strict
        }
        let isShortTopExpansion = shortTopFamiliesCanExpand(incoming, candidate)
        let isTopSleeveLengthExpansion = topSleeveLengthsCanExpand(incoming, candidate)
        let isBottomLengthExpansion = bottomLengthsCanExpand(incoming, candidate)
        if incoming.majorCategory.serviceGroup == .top, !isShortTopExpansion {
            let shortLengths: Set<ComparisonLengthType> = [.sleeveless, .short]
            let crossesShortAndLongBoundary = shortLengths.contains(incoming.lengthType)
                != shortLengths.contains(candidate.lengthType)
            if (crossesShortAndLongBoundary && !isTopSleeveLengthExpansion)
                || (incoming.garmentFamily != candidate.garmentFamily
                    && !isTopSleeveLengthExpansion) {
                return strict
            }
        }
        guard garmentFamiliesAreCompatible(candidate.garmentFamily, incoming.garmentFamily)
                || isShortTopExpansion
                || isTopSleeveLengthExpansion
                || isBottomLengthExpansion else { return strict }
        guard gendersAreCompatible(
            product.productTargetGender.taxonomyCode,
            item.resolvedGenderCode,
            family: incoming.garmentFamily
        ) else {
            return .blocked("착용 대상이 달라 비교할 수 없어요.")
        }
        let commonCount: Int
        if isTopSleeveLengthExpansion {
            commonCount = commonTopBodyMeasurementCount(incoming, candidate)
        } else if isBottomLengthExpansion {
            commonCount = commonBottomBodyMeasurementCount(incoming, candidate)
        } else {
            commonCount = commonCoreMeasurementCount(incoming, candidate)
        }
        guard commonCount >= (isShortTopExpansion || isTopSleeveLengthExpansion || isBottomLengthExpansion ? 2 : 1) else {
            return .blocked("공통 실측이 없어 비교할 수 없어요.")
        }
        if isTopSleeveLengthExpansion {
            return GarmentComparisonCompatibility(
                level: .extended,
                reason: "부분 비교 · 소매길이 제외 · 공통 실측 \(commonCount)개 비교 가능"
            )
        }
        if isShortTopExpansion {
            return GarmentComparisonCompatibility(
                level: .extended,
                reason: "사용자 선택 확장 비교 · 다른 반팔 상의 구조 · 공통 실측 \(commonCount)개"
            )
        }
        if isBottomLengthExpansion {
            return GarmentComparisonCompatibility(
                level: .extended,
                reason: "참고용 부분 비교 · 바지 길이 구조 차이 · 허리·엉덩이·허벅지 등 공통 실측 \(commonCount)개"
            )
        }
        return GarmentComparisonCompatibility(
            level: .extended,
            reason: "사용자 선택 확장 비교 · 길이·세부 종류 차이 · 공통 실측 \(commonCount)개"
        )
    }

    private func shortTopFamiliesCanExpand(
        _ lhs: ComparisonProfile,
        _ rhs: ComparisonProfile
    ) -> Bool {
        guard lhs.majorCategory.serviceGroup == .top,
              rhs.majorCategory.serviceGroup == .top else { return false }
        let shortLengths: Set<ComparisonLengthType> = [.sleeveless, .short]
        return shortLengths.contains(lhs.lengthType)
            && shortLengths.contains(rhs.lengthType)
    }

    private func topSleeveLengthsCanExpand(
        _ lhs: ComparisonProfile,
        _ rhs: ComparisonProfile
    ) -> Bool {
        guard lhs.majorCategory.serviceGroup == .top,
              rhs.majorCategory.serviceGroup == .top else { return false }
        return Set([lhs.lengthType, rhs.lengthType]) == Set([.short, .long])
    }

    private func bottomLengthsCanExpand(
        _ lhs: ComparisonProfile,
        _ rhs: ComparisonProfile
    ) -> Bool {
        guard lhs.majorCategory.serviceGroup == .bottom,
              rhs.majorCategory.serviceGroup == .bottom,
              [.pants, .denim].contains(lhs.garmentFamily),
              [.pants, .denim].contains(rhs.garmentFamily),
              lhs.lengthType != .unknown,
              rhs.lengthType != .unknown else { return false }
        return lhs.lengthType != rhs.lengthType
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
            let compatibility = comparisonCompatibility(
                product: product,
                productDetailCategory: productDetailCategory,
                item: item
            )
            var reasons: [String] = []
            if product.canonicalEligibility == false { reasons.append("incoming_ineligible") }
            if item.canonicalEligibility == false { reasons.append("candidate_ineligible") }
            if candidate.majorCategory != incoming.majorCategory { reasons.append("major_category_incompatible") }
            if !gendersAreCompatible(
                incomingGender,
                item.resolvedGenderCode,
                family: incoming.garmentFamily
            ) { reasons.append("gender_incompatible") }
            if incoming.garmentFamily == .unknown { reasons.append("incoming_family_unknown") }
            if !garmentFamiliesAreCompatible(candidate.garmentFamily, incoming.garmentFamily) { reasons.append("family_incompatible") }
            if !detailCategoriesAreCompatible(
                item.detailCategory,
                productDetailCategory,
                family: incoming.garmentFamily,
                major: incoming.majorCategory
            ) { reasons.append("detail_category_incompatible") }
            if !lengthsAreCompatible(candidate, incoming) { reasons.append("length_incompatible") }
            if !constructionsAreCompatible(incoming.constructionType, candidate.constructionType) { reasons.append("construction_incompatible") }
            let commonCount = commonCoreMeasurementCount(incoming, candidate)
            if commonCount < minimum { reasons.append("common_measurements_insufficient") }
            if compatibility.level == .blocked { reasons.append("comparison_blocked") }
            if compatibility.level == .extended { reasons.append("extended_comparison_only") }

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
        let compatibility = manualComparisonCompatibility(
            product: product,
            productDetailCategory: productDetailCategory,
            item: selectedItem
        )
        if compatibility.level == .extended {
            let incoming = profile(for: product, detailCategory: productDetailCategory)
            let candidate = profile(for: selectedItem)
            if topSleeveLengthsCanExpand(incoming, candidate) {
                return (
                    [.sleeveLength],
                    "반팔과 긴팔은 소매 구조가 달라 소매길이를 제외하고 가슴·어깨·총장 등 공통 실측만 비교했어요."
                )
            }
            if bottomLengthsCanExpand(incoming, candidate) {
                return (
                    [.totalLength, .hem],
                    "긴바지와 반바지는 길이 구조가 달라 자동 비교에서 제외했어요. 허리·엉덩이·허벅지 등 공통 실측은 참고용으로 비교했어요."
                )
            }
            return ([], "유사한 다른 종류의 옷이라 공통 실측 중심으로 확장 비교했어요.")
        }
        if compatibility.level == .blocked {
            return ([], compatibility.reason)
        }
        return ([], nil)
    }

    func hasSamePlatformOfficialFormat(
        product: Product,
        selectedItem: UserFit,
        minimumCommonMeasurementCount: Int = 2
    ) -> Bool {
        directSourceComparisonCount(product: product, selectedItem: selectedItem) >= minimumCommonMeasurementCount
    }

    func directSourceComparisonCount(product: Product, selectedItem: UserFit) -> Int {
        MeasurementKind.allCases.filter {
            hasDirectSourceComparison(
                kind: $0,
                product: product,
                selectedItem: selectedItem
            )
        }.count
    }

    func candidateNote(product: Product, productDetailCategory: ClosetDetailCategory, item: UserFit) -> String? {
        comparisonCompatibility(
            product: product,
            productDetailCategory: productDetailCategory,
            item: item
        ).reason
    }

    func comparisonCompatibility(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        item: UserFit
    ) -> GarmentComparisonCompatibility {
        let incoming = profile(for: product, detailCategory: productDetailCategory)
        let candidate = profile(for: item)
        guard product.canonicalEligibility != false,
              item.canonicalEligibility != false else {
            return .blocked("분류 검증이 완료되지 않아 비교할 수 없어요.")
        }
        guard incoming.majorCategory == candidate.majorCategory else {
            return .blocked("착용 부위가 달라 비교할 수 없어요.")
        }
        guard incoming.garmentFamily != .unknown,
              candidate.garmentFamily != .unknown else {
            return .blocked("옷 종류를 확인할 수 없어 비교할 수 없어요.")
        }
        guard gendersAreCompatible(
            product.productTargetGender.taxonomyCode,
            item.resolvedGenderCode,
            family: incoming.garmentFamily
        ) else {
            return .blocked("착용 대상이 달라 비교할 수 없어요.")
        }

        var level = categoryCompatibilityLevel(
            incoming: incoming,
            incomingDetail: productDetailCategory,
            candidate: candidate,
            candidateDetail: item.detailCategory
        )
        guard level.isAllowed else {
            return .blocked("옷의 용도와 구조가 달라 비교할 수 없어요.")
        }
        guard lengthsAreCompatible(candidate, incoming) else {
            return .blocked("길이 형태가 달라 직접 비교할 수 없어요.")
        }

        let commonCount = commonCoreMeasurementCount(incoming, candidate)
        guard commonCount >= minimumCommonMeasurementCount(for: incoming.garmentFamily) else {
            return .blocked("공통 핵심 실측이 부족해 비교할 수 없어요.")
        }

        if !constructionsAreCompatible(incoming.constructionType, candidate.constructionType) {
            level = .extended
        }
        switch level {
        case .direct:
            return GarmentComparisonCompatibility(
                level: .direct,
                reason: "유사 의류 직접 비교 · 실측 \(commonCount)개 호환"
            )
        case .extended:
            return GarmentComparisonCompatibility(
                level: .extended,
                reason: "확장 비교 · 다른 구조 · 실측 \(commonCount)개 호환"
            )
        case .blocked:
            return .blocked("비교할 수 없는 조합이에요.")
        }
    }

    func garmentFamiliesAreCompatible(
        _ lhs: ComparisonGarmentFamily,
        _ rhs: ComparisonGarmentFamily
    ) -> Bool {
        if lhs == rhs { return true }
        let pair = Set([lhs, rhs])
        return pair == Set([.denim, .pants])
            || pair == Set([.sweatshirt, .hoodie])
            || pair == Set([.outerwear, .hoodie])
    }

    private func categoryCompatibilityLevel(
        incoming: ComparisonProfile,
        incomingDetail: ClosetDetailCategory,
        candidate: ComparisonProfile,
        candidateDetail: ClosetDetailCategory
    ) -> GarmentComparisonCompatibilityLevel {
        guard incoming.majorCategory == candidate.majorCategory else { return .blocked }

        let familyPair = Set([incoming.garmentFamily, candidate.garmentFamily])
        if familyPair == Set([.denim, .pants]) { return .direct }
        if familyPair == Set([.sweatshirt, .hoodie]) { return .direct }
        if familyPair == Set([.tshirt, .shirt]) { return .blocked }
        if incoming.majorCategory.serviceGroup == .outer,
           familyPair == Set([.outerwear, .hoodie]) {
            return outerDetailsCanExpand(incomingDetail, candidateDetail) ? .extended : .blocked
        }
        guard incoming.garmentFamily == candidate.garmentFamily else { return .blocked }
        if incomingDetail == candidateDetail { return .direct }
        if detailCategoriesAreCompatible(
            incomingDetail,
            candidateDetail,
            family: incoming.garmentFamily,
            major: incoming.majorCategory
        ) {
            return .direct
        }
        if incoming.majorCategory.serviceGroup == .outer,
           outerDetailsCanExpand(incomingDetail, candidateDetail) {
            return .extended
        }
        return .blocked
    }

    private func outerDetailsCanExpand(
        _ lhs: ClosetDetailCategory,
        _ rhs: ClosetDetailCategory
    ) -> Bool {
        let casualLight: Set<ClosetDetailCategory> = [
            .jumper, .jacket, .windbreaker, .anorak, .blouson, .fleece, .hoodie
        ]
        let tailoredLight: Set<ClosetDetailCategory> = [.jacket, .blazer, .blouson]
        let padded: Set<ClosetDetailCategory> = [
            .padding, .lightPadding, .shortPadding, .longPadding, .paddedVest
        ]
        let coat: Set<ClosetDetailCategory> = [.coat, .trenchCoat, .mouton]
        return [casualLight, tailoredLight, padded, coat].contains {
            $0.contains(lhs) && $0.contains(rhs)
        }
    }

    private func isPoloText(_ text: String) -> Bool {
        let value = normalized(text)
        if ["카라티", "카라 티", "폴로셔츠", "폴로 셔츠", "polo shirt", "polo_shirt"]
            .contains(where: value.contains) {
            return true
        }
        return value.contains("카라")
            && ["티셔츠", "반팔티", "긴팔티", "tee"].contains(where: value.contains)
    }

    func detailCategoriesAreCompatible(
        _ lhs: ClosetDetailCategory,
        _ rhs: ClosetDetailCategory,
        family: ComparisonGarmentFamily,
        major: ClothingCategory
    ) -> Bool {
        if lhs == rhs { return true }
        if lhs == .other || rhs == .other { return false }

        switch major.serviceGroup {
        case .top:
            let sleeveDetails: Set<ClosetDetailCategory> = [
                .sleeveless, .shortSleeve, .threeQuarterSleeve, .longSleeve
            ]
            // 셔츠·블라우스처럼 의류형 세부분류와 소매길이 세부분류가
            // 서로 다른 축일 때는 이미 같은 family/length로 검증한다.
            return !(sleeveDetails.contains(lhs) && sleeveDetails.contains(rhs))
        case .bottom:
            if Set([lhs, rhs]) == Set([.shortPants, .shorts]) { return true }
            let longPantsDetails: Set<ClosetDetailCategory> = [
                .longPants, .slacks, .denim, .trainingPants
            ]
            return (family == .pants || family == .denim)
                && longPantsDetails.contains(lhs)
                && longPantsDetails.contains(rhs)
        case .outer, .underwear, .dress, .shoes, .accessory, .other:
            return false
        case .pants, .shirt, .knit:
            return false
        }
    }

    func lengthsAreCompatible(
        _ lhs: ComparisonProfile,
        _ rhs: ComparisonProfile
    ) -> Bool {
        if lhs.majorCategory.serviceGroup == .outer || rhs.majorCategory.serviceGroup == .outer {
            guard lhs.bodyLengthType != .unknown,
                  lhs.bodyLengthType == rhs.bodyLengthType else {
                return false
            }
        }
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
        case .underwear, .shoes, .accessory, .unknown:
            return false
        case .skirt, .dress:
            return true
        }
    }

    func profile(for product: Product, detailCategory: ClosetDetailCategory) -> ComparisonProfile {
        let preservesAuthoritativeTuple = product.classificationAuthorityProvenance?
            .isComparisonAuthority == true
        if product.canonicalProfileSnapshotJSON == nil && !preservesAuthoritativeTuple {
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
            major: major,
            prefersProviderCategory: product.sourceName.localizedCaseInsensitiveContains("무신사")
        )
        let productNameFamily = explicitProductFamilyKeywordMatch(product.name, major: major)
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
        let bodyLength = outerBodyLengthType(
            productName: product.name,
            source: source,
            major: major,
            gender: product.productTargetGender,
            measurements: product.sizes.map(\.measurements)
        )
        let family = preservesAuthoritativeTuple
            ? product.garmentType
            : storedGarmentType(
                product.garmentTypeRawValue,
                fallback: inferredFamily,
                productNameFamily: productNameFamily,
                major: major,
                allowsProductNameOverride: !product.sourceName.localizedCaseInsensitiveContains("무신사")
                    || sourceCategoryIsGeneric(source)
            )
        let length: ComparisonLengthType
        if preservesAuthoritativeTuple {
            length = product.sleeveType
        } else {
            length = detailLength(detailCategory, major: major) == .sleeveless
                ? .sleeveless
                : storedSleeveType(product.sleeveTypeRawValue, fallback: inferredLength)
        }
        let construction = preservesAuthoritativeTuple
            ? product.constructionType
            : storedConstructionType(
                product.constructionTypeRawValue,
                fallback: inferredConstruction
            )
        if !preservesAuthoritativeTuple {
            storeResolvedAttributes(
                garmentType: family,
                sleeveType: length,
                constructionType: construction,
                on: product
            )
            recoverProductLevelFallbackEligibility(
                product,
                major: major,
                family: family,
                length: length,
                availableMeasurements: availableMeasurements(product.sizes.map(\.measurements))
            )
        }
        return ComparisonProfile(
            majorCategory: major,
            garmentFamily: family,
            lengthType: length,
            bodyLengthType: bodyLength,
            constructionType: construction,
            availableMeasurements: availableMeasurements(product.sizes.map(\.measurements))
        )
    }

    func profile(for item: UserFit) -> ComparisonProfile {
        let preservesAuthoritativeTuple = item.classificationAuthorityProvenance?
            .isComparisonAuthority == true
        if item.canonicalProfileSnapshotJSON == nil && !preservesAuthoritativeTuple {
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
            major: major,
            prefersProviderCategory: item.sourceName.localizedCaseInsensitiveContains("무신사")
        )
        let productNameFamily = explicitProductFamilyKeywordMatch(item.productName, major: major)
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
        let bodyLength = outerBodyLengthType(
            productName: item.productName,
            source: source,
            major: major,
            gender: item.gender,
            measurements: [item.measurements]
        )
        let family = preservesAuthoritativeTuple
            ? item.garmentType
            : storedGarmentType(
                item.garmentTypeRawValue,
                fallback: inferredFamily,
                productNameFamily: productNameFamily,
                major: major,
                allowsProductNameOverride: !item.sourceName.localizedCaseInsensitiveContains("무신사")
                    || sourceCategoryIsGeneric(source)
            )
        let length: ComparisonLengthType
        if preservesAuthoritativeTuple {
            length = item.sleeveType
        } else {
            length = detailLength(item.detailCategory, major: major) == .sleeveless
                ? .sleeveless
                : storedSleeveType(item.sleeveTypeRawValue, fallback: inferredLength)
        }
        let construction = preservesAuthoritativeTuple
            ? item.constructionType
            : storedConstructionType(
                item.constructionTypeRawValue,
                fallback: inferredConstruction
            )
        if !preservesAuthoritativeTuple {
            storeResolvedAttributes(
                garmentType: family,
                sleeveType: length,
                constructionType: construction,
                on: item
            )
            recoverProductLevelFallbackEligibility(
                item,
                major: major,
                family: family,
                length: length,
                availableMeasurements: availableMeasurements([item.measurements])
            )
        }
        return ComparisonProfile(
            majorCategory: major,
            garmentFamily: family,
            lengthType: length,
            bodyLengthType: bodyLength,
            constructionType: construction,
            availableMeasurements: availableMeasurements([item.measurements])
        )
    }

    private func recoverProductLevelFallbackEligibility(
        _ product: Product,
        major: ClothingCategory,
        family: ComparisonGarmentFamily,
        length: ComparisonLengthType,
        availableMeasurements: [MeasurementKind]
    ) {
        guard product.canonicalEligibility == false,
              product.canonicalResolutionMethod == "product_level_fallback",
              major.serviceGroup == .bottom,
              [.pants, .denim].contains(family),
              let productNameFamily = explicitProductFamilyKeywordMatch(product.name, major: major),
              [.pants, .denim].contains(productNameFamily),
              !normalized(product.name).contains("세트"),
              length == .long,
              availableMeasurements.filter({ [.waist, .hip, .thigh, .rise, .hem, .totalLength].contains($0) }).count >= 3
        else { return }
        product.canonicalEligibility = true
        product.canonicalResolutionMethod = "product_level_fallback_resolved"
    }

    private func recoverProductLevelFallbackEligibility(
        _ item: UserFit,
        major: ClothingCategory,
        family: ComparisonGarmentFamily,
        length: ComparisonLengthType,
        availableMeasurements: [MeasurementKind]
    ) {
        guard item.canonicalEligibility == false,
              item.canonicalResolutionMethod == "product_level_fallback",
              major.serviceGroup == .bottom,
              [.pants, .denim].contains(family),
              let productNameFamily = explicitProductFamilyKeywordMatch(item.productName, major: major),
              [.pants, .denim].contains(productNameFamily),
              !normalized(item.productName).contains("세트"),
              length == .long,
              availableMeasurements.filter({ [.waist, .hip, .thigh, .rise, .hem, .totalLength].contains($0) }).count >= 3
        else { return }
        item.canonicalEligibility = true
        item.canonicalResolutionMethod = "product_level_fallback_resolved"
    }

    private func storedGarmentType(
        _ rawValue: String?,
        fallback: ComparisonGarmentFamily,
        productNameFamily: ComparisonGarmentFamily?,
        major: ClothingCategory,
        allowsProductNameOverride: Bool
    ) -> ComparisonGarmentFamily {
        guard let rawValue,
              let stored = ComparisonGarmentFamily(rawValue: rawValue),
              stored != .unknown else {
            return fallback
        }
        if stored == .pants, fallback == .denim {
            return fallback
        }
        if major.serviceGroup == .top, stored == .shirt, fallback == .tshirt {
            return fallback
        }
        if major.serviceGroup == .top, stored == .tshirt, fallback == .shirt {
            // A resolved shirt/blouse detail is a typed structural fact. A
            // broader cached `tops.tshirt` source mapping must not downgrade it.
            return fallback
        }
        if major.serviceGroup == .underwear, stored != .underwear {
            return .underwear
        }
        let lowerBodyFamilies: Set<ComparisonGarmentFamily> = [.pants, .denim, .leggings, .skirt]
        if major.serviceGroup == .bottom,
           lowerBodyFamilies.contains(fallback),
           !lowerBodyFamilies.contains(stored) {
            return fallback
        }
        if major.serviceGroup == .bottom,
           stored == .pants,
           productNameFamily == .skirt {
            return .skirt
        }
        let outerFamilies: [ComparisonGarmentFamily] = [.outerwear, .leatherJacket, .knitCardigan]
        if major.serviceGroup == .outer,
           outerFamilies.contains(fallback),
           !outerFamilies.contains(stored) {
            return fallback
        }
        if allowsProductNameOverride,
           major.serviceGroup == .top,
           let productNameFamily,
           [.knitCardigan, .hoodie, .sweatshirt].contains(productNameFamily) {
            return productNameFamily
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
        major: ClothingCategory,
        prefersProviderCategory: Bool
    ) -> ComparisonGarmentFamily {
        if major.serviceGroup == .top, isPoloText(productName) {
            return .tshirt
        }
        if major.serviceGroup == .top,
           detailCategory == .shirt || detailCategory == .blouse {
            return .shirt
        }
        if major.serviceGroup == .top, isPoloText(source) {
            return .tshirt
        }
        let sourceFamily = normalizedProductTypeCode.flatMap(family(forNormalizedProductTypeCode:))
            ?? familyKeywordMatch(source)
        if !prefersProviderCategory || sourceCategoryIsGeneric(source) {
            return explicitProductFamilyKeywordMatch(productName, major: major)
                ?? sourceFamily
                ?? familyKeywordMatch(productName)
                ?? family(for: detailCategory, major: major)
        }
        return sourceFamily
            ?? explicitProductFamilyKeywordMatch(productName, major: major)
            ?? familyKeywordMatch(productName)
            ?? family(for: detailCategory, major: major)
    }

    private func sourceCategoryIsGeneric(_ source: String) -> Bool {
        let terminal = source
            .components(separatedBy: ">").last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? source
        let value = normalized(terminal)
        return [
            "기타상의", "기타 상의", "기타 아우터", "기타 하의",
            "other tops", "other top", "other outerwear", "other bottoms"
        ].contains { value.contains($0) }
    }

    private func explicitProductFamilyKeywordMatch(
        _ productName: String,
        major: ClothingCategory
    ) -> ComparisonGarmentFamily? {
        let value = normalized(productName)
        switch major.serviceGroup {
        case .top:
            if [
                "후디", "후드 티", "후드티", "hoodie",
                "풀집파카", "풀집 파카", "스웨트파카", "스웨트 파카",
                "full-zip parka", "full zip parka"
            ].contains(where: value.contains) { return .hoodie }
            if ["스웨트셔츠", "스웨트 셔츠", "스웨트", "맨투맨", "sweatshirt"].contains(where: value.contains) { return .sweatshirt }
            if ["니트", "스웨터", "knit", "sweater"].contains(where: value.contains) { return .knitCardigan }
            return nil
        case .outer:
            if ["가디건", "카디건", "cardigan"].contains(where: value.contains) { return .knitCardigan }
            if ["레더 재킷", "레더 자켓", "가죽 재킷", "가죽 자켓", "라이더스", "leather jacket", "riders jacket"].contains(where: value.contains) {
                return .leatherJacket
            }
            return .outerwear
        case .bottom:
            if ["스코츠", "skorts", "skort"].contains(where: value.contains) { return .skirt }
            if ["레깅스", "타이즈", "타이츠", "leggings"].contains(where: value.contains) { return .leggings }
            if ["데님", "청바지", "denim", "jeans"].contains(where: value.contains) { return .denim }
            if ["팬츠", "바지", "슬랙스", "pants", "trousers", "slacks"].contains(where: value.contains) { return .pants }
            return nil
        default:
            return nil
        }
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
        let kids = Set(["boys", "girls", "kids_unisex"])
        if kids.contains(incoming) || kids.contains(candidate) {
            return kids.contains(incoming) && kids.contains(candidate)
        }
        if incoming == "unisex" || candidate == "unisex" { return true }
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
        case .sleeveless, .shortSleeve, .threeQuarterSleeve, .longSleeve, .poloShirt: return .tshirt
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
        if detailCategory == .skirt {
            if let value = skirtLength(productName) { return value }
            if let value = skirtLength(source) { return value }
        }
        // Sleeveless is a garment construction, not merely a tunable length.
        // Keep an already resolved sleeveless detail from being reinterpreted
        // as long sleeve by umbrella-path text such as `긴소매 티셔츠`.
        if detailLength(detailCategory, major: major) == .sleeveless {
            return .sleeveless
        }
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

    private func skirtLength(_ text: String) -> ComparisonLengthType? {
        let value = normalized(text)
        if ["미니 스커트", "미니스커트", "미니 스코츠", "미니스코츠", "스코츠", "skorts", "mini skirt"].contains(where: value.contains) { return .short }
        if ["미디 스커트", "미디스커트", "midi skirt"].contains(where: value.contains) { return .threeQuarter }
        if ["롱 스커트", "롱스커트", "맥시 스커트", "맥시스커트", "long skirt", "maxi skirt"].contains(where: value.contains) { return .long }
        return nil
    }

    private func outerBodyLengthType(
        productName: String,
        source: String,
        major: ClothingCategory,
        gender: UserGender,
        measurements: [GarmentMeasurements]
    ) -> ComparisonLengthType {
        guard major.serviceGroup == .outer else { return .unknown }
        if let value = outerBodyLength(productName) { return value }
        if let value = outerBodyLength(source) { return value }
        let values = measurements
            .map(\.totalLength)
            .filter { $0.isFinite && $0 > 0 }
            .sorted()
        guard !values.isEmpty else { return .unknown }
        let middle = values.count / 2
        let value = values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
        let boundaries: (cropped: Double, short: Double, threeQuarter: Double)
        switch gender {
        case .men:
            boundaries = (58, 78, 100)
        case .women:
            boundaries = (52, 72, 95)
        case .kids, .baby:
            boundaries = (38, 52, 70)
        case .unisex, .unknown:
            boundaries = (55, 75, 98)
        }
        if value <= boundaries.cropped { return .cropped }
        if value <= boundaries.short { return .short }
        if value <= boundaries.threeQuarter { return .threeQuarter }
        return .long
    }

    private func outerBodyLength(_ text: String) -> ComparisonLengthType? {
        let value = normalized(text)
        let padded = " \(value) "
        if ["크롭", "crop jacket", "cropped jacket", "crop coat", "cropped coat",
            "crop cardigan", "cropped cardigan"].contains(where: value.contains) {
            return .cropped
        }
        if ["숏 재킷", "숏재킷", "숏 자켓", "숏자켓", "쇼트 재킷", "쇼트재킷",
            "쇼트 자켓", "쇼트자켓", "숏 코트", "숏코트", "쇼트 코트", "쇼트코트",
            "숏 패딩", "숏패딩", "쇼트 패딩", "쇼트패딩", "short jacket", "short coat",
            "short parka", "short padding"].contains(where: value.contains) {
            return .short
        }
        let hasShortSleeve = ["숏 슬리브", "숏슬리브", "쇼트 슬리브", "쇼트슬리브",
                              "short sleeve"].contains(where: value.contains)
        if !hasShortSleeve
            && (value.contains("숏") || value.contains("쇼트") || padded.contains(" short ")) {
            return .short
        }
        if ["하프 재킷", "하프재킷", "하프 자켓", "하프자켓", "하프 코트", "하프코트",
            "미디 코트", "미디코트", "half jacket", "half coat", "midi coat"].contains(where: value.contains) {
            return .threeQuarter
        }
        let hasNonLengthHalf = ["하프넥", "하프 넥", "하프집업", "하프 집업", "하프 슬리브", "하프슬리브",
                                "half-neck", "half neck", "half-zip", "half zip", "half sleeve"].contains(where: value.contains)
        if !hasNonLengthHalf && (value.contains("하프") || padded.contains(" half ")) {
            return .threeQuarter
        }
        let hasLongSleeve = ["롱 슬리브", "롱슬리브", "long sleeve"].contains(where: value.contains)
        if ["롱 코트", "롱코트", "롱 재킷", "롱재킷", "롱 자켓", "롱자켓",
            "롱 패딩", "롱패딩", "long coat", "long jacket", "long parka", "맥시", "maxi"].contains(where: value.contains)
            || (!hasLongSleeve && (value.contains("롱") || padded.contains(" long "))) {
            return .long
        }
        return nil
    }

    private func keywordLength(_ text: String, major: ClothingCategory) -> ComparisonLengthType? {
        let value = normalized(text)
        if major == .bottom {
            if ["반바지", "쇼츠", "숏 팬츠", "쇼트 팬츠", "버뮤다", "큐롯", "culotte",
                "하프 타이즈", "하프타이즈", "하프 타이츠", "하프타이츠", "shorts"].contains(where: value.contains) { return .short }
            if ["7부", "three quarter", "3/4"].contains(where: value.contains) { return .threeQuarter }
            if ["크롭", "cropped"].contains(where: value.contains) { return .cropped }
            if ["9부", "nine tenths", "ankle"].contains(where: value.contains) { return .nineTenths }
            if ["긴바지", "롱 팬츠", "long pants"].contains(where: value.contains) { return .long }
            return nil
        }
        if ["민소매", "나시", "슬리브리스", "sleeveless"].contains(where: value.contains) { return .sleeveless }
        let hasShort = [
            "반팔", "반소매", "숏슬리브", "short sleeve", "half sleeve", "cap sleeve",
            "s/s tee", "s/s t-shirt", "s/s tshirt"
        ].contains(where: value.contains)
        let hasLong = [
            "긴팔", "긴소매", "롱슬리브", "long sleeve",
            "l/s tee", "l/s t-shirt", "l/s tshirt"
        ].contains(where: value.contains)
        if hasShort != hasLong { return hasShort ? .short : .long }
        if ["7부", "three quarter", "3/4"].contains(where: value.contains) { return .threeQuarter }
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

    private func commonTopBodyMeasurementCount(_ lhs: ComparisonProfile, _ rhs: ComparisonProfile) -> Int {
        [.shoulder, .chest, .totalLength]
            .filter { lhs.availableMeasurements.contains($0) && rhs.availableMeasurements.contains($0) }
            .count
    }

    private func commonBottomBodyMeasurementCount(_ lhs: ComparisonProfile, _ rhs: ComparisonProfile) -> Int {
        [.waist, .hip, .thigh, .rise]
            .filter { lhs.availableMeasurements.contains($0) && rhs.availableMeasurements.contains($0) }
            .count
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
            guard let productSource = productRecord.sourceIdentity else {
                return false
            }
            return referenceRecords.contains { referenceRecord in
                guard referenceRecord.sourceIdentity?.code == productSource.code else {
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
