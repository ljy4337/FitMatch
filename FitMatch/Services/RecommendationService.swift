import Foundation

struct FitMatchCandidate: Identifiable {
    var id: UUID { userFit.id }
    let userFit: UserFit
    let matchRate: Int
    let compatibleMeasurementCount: Int
    let selectionReason: String
}

struct ReferenceSelectionPlan {
    let recommendedCandidates: [FitMatchCandidate]
    let automaticallySelectedCandidate: FitMatchCandidate?

    var requiresUserSelection: Bool {
        !recommendedCandidates.isEmpty && automaticallySelectedCandidate == nil
    }
}

struct InsufficientComparisonEvidence {
    let productSize: ProductSize
    let referenceItem: UserFit
    let comparisonResult: MeasurementComparisonResult

    var comparedKinds: [MeasurementKind] {
        comparisonResult.comparedKinds
    }

    var missingKinds: [MeasurementKind] {
        comparisonResult.exclusions.map(\.kind)
    }
}

struct RecommendationService {
    private let comparisonMatcher = ComparisonProfileMatcher()
    private let measurementComparisonEngine = MeasurementComparisonEngine()

    func recommend(
        product: Product,
        userFits: [UserFit],
        productDetailCategory: ClosetDetailCategory = .other,
        allowsGlobalFallback: Bool = true
    ) -> RecommendationHistory? {
        let basis = selectBasis(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits,
            allowsGlobalFallback: allowsGlobalFallback
        )
        guard !basis.userFits.isEmpty else {
            return nil
        }

        let sortedFits = sortCandidates(basis.userFits)
        return bestRecommendation(
            product: product,
            userFits: sortedFits,
            productDetailCategory: productDetailCategory,
            basis: basis
        )
    }

    func insufficientEvidence(
        product: Product,
        userFits: [UserFit],
        productDetailCategory: ClosetDetailCategory = .other,
        allowsGlobalFallback: Bool = true
    ) -> InsufficientComparisonEvidence? {
        let profileResult = comparisonMatcher.match(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        )
        let candidates = profileResult.compatibleCandidates.isEmpty && allowsGlobalFallback
            ? comparisonMatcher.manualCandidates(
                product: product,
                productDetailCategory: productDetailCategory,
                userFits: userFits
            )
            : profileResult.compatibleCandidates
        return bestInsufficientEvidence(
            product: product,
            userFits: candidates,
            productDetailCategory: productDetailCategory,
            excludedKinds: []
        )
    }

    func insufficientEvidence(
        product: Product,
        selectedReferenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory
    ) -> InsufficientComparisonEvidence? {
        let mismatch = comparisonMatcher.manualMismatch(
            product: product,
            productDetailCategory: productDetailCategory,
            selectedItem: selectedReferenceItem
        )
        return bestInsufficientEvidence(
            product: product,
            userFits: [selectedReferenceItem],
            productDetailCategory: productDetailCategory,
            excludedKinds: mismatch.excludedKinds
        )
    }

    func recommend(
        product: Product,
        selectedReferenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory
    ) -> RecommendationHistory? {
        let mismatch = comparisonMatcher.manualMismatch(
            product: product,
            productDetailCategory: productDetailCategory,
            selectedItem: selectedReferenceItem
        )
        let fallbackReason = mismatch.note
            ?? "\(productDetailCategory.rawValue) 기준 옷이 없어 선택한 옷으로 임시 비교했습니다."
        return bestRecommendation(
            product: product,
            userFits: [selectedReferenceItem],
            productDetailCategory: productDetailCategory,
            basis: RecommendationBasis(
                userFits: [selectedReferenceItem],
                methodText: "사용자 선택 임시 비교",
                scorePenalty: mismatch.note == nil ? 12 : 20,
                fallbackReason: fallbackReason,
                excludedMeasurementKinds: mismatch.excludedKinds
            )
        )
    }

    func automaticMatchResult(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> AutomaticComparisonMatchResult {
        let profileResult = comparisonMatcher.match(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        )
        guard !profileResult.compatibleCandidates.isEmpty else { return profileResult }
        let ranked = Array(rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: profileResult.compatibleCandidates
        ).prefix(3))
        let candidates = ranked.isEmpty
            ? profileResult.compatibleCandidates
            : ranked.map(\.userFit)
        return AutomaticComparisonMatchResult(
            state: .compatible,
            incomingProfile: profileResult.incomingProfile,
            compatibleCandidates: candidates
        )
    }

    func manualCandidateNote(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        item: UserFit
    ) -> String? {
        comparisonMatcher.candidateNote(
            product: product,
            productDetailCategory: productDetailCategory,
            item: item
        )
    }

    func hasDetailCategoryClosetItem(
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> Bool {
        userFits.contains { $0.detailCategory == productDetailCategory }
    }

    func hasDetailCategoryBasis(
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> Bool {
        userFits.contains { $0.detailCategory == productDetailCategory && $0.isRepresentative }
    }

    func temporaryComparisonCandidates(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [UserFit] {
        let manual = comparisonMatcher.manualCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        )
        let recommended = rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: manual
        ).prefix(3).map(\.userFit)
        let recommendedIDs = Set(recommended.map(\.id))
        return recommended + manual.filter { !recommendedIDs.contains($0.id) }
    }

    func rankedFitMatches(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [FitMatchCandidate] {
        Array(rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).prefix(3))
    }

    func referenceSelectionPlan(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> ReferenceSelectionPlan {
        if product.sizeType == StandardBodySizeChart.metadataMarker {
            let candidates = standardSizeCandidates(product: product, userFits: userFits)
            return ReferenceSelectionPlan(
                recommendedCandidates: candidates,
                automaticallySelectedCandidate: candidates.first
            )
        }
        let compatible = comparisonMatcher.match(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).compatibleCandidates
        let preferredRepresentativeIDs = Set(preferredRepresentatives(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).map(\.id))
        let candidates = Array(rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: compatible
        ).prefix(3))
        let automaticallySelected: FitMatchCandidate?
        if preferredRepresentativeIDs.isEmpty {
            automaticallySelected = clearlyBestCandidate(in: candidates)
        } else {
            automaticallySelected = candidates.first {
                preferredRepresentativeIDs.contains($0.id)
            }
        }

        return ReferenceSelectionPlan(
            recommendedCandidates: candidates,
            automaticallySelectedCandidate: automaticallySelected
        )
    }

    private func sortCandidates(_ userFits: [UserFit]) -> [UserFit] {
        userFits.sorted { lhs, rhs in
            if lhs.isRepresentative != rhs.isRepresentative {
                return lhs.isRepresentative
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func clearlyBestCandidate(in candidates: [FitMatchCandidate]) -> FitMatchCandidate? {
        guard let first = candidates.first else { return nil }
        guard candidates.count > 1 else { return first }

        let second = candidates[1]
        if first.compatibleMeasurementCount > second.compatibleMeasurementCount {
            return first
        }
        if first.compatibleMeasurementCount == second.compatibleMeasurementCount,
           first.matchRate >= second.matchRate + 10 {
            return first
        }
        return nil
    }

    private func bestRecommendation(
        product: Product,
        userFits: [UserFit],
        productDetailCategory: ClosetDetailCategory,
        basis: RecommendationBasis
    ) -> RecommendationHistory? {
        if usesStandardSizeFallback(product: product, userFits: userFits) {
            return standardSizeRecommendation(
                product: product,
                userFits: userFits,
                productDetailCategory: productDetailCategory,
                basis: basis
            )
        }

        var bestHistory: RecommendationHistory?
        var bestFitConfidence = -1
        var bestAverageDifference = Double.greatestFiniteMagnitude

        for size in product.sizes.sorted(by: { $0.displayOrder < $1.displayOrder }) where !size.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for userFit in userFits {
                let fitConfidence = measurementComparisonEngine.compare(
                    productSize: size,
                    referenceItem: userFit,
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory,
                    excludedKinds: basis.excludedMeasurementKinds
                )
                guard fitConfidence.status == .confirmed else { continue }
                let signedDifferences = fitConfidence.signedDifferences

                let adjustedScore = max(0, fitConfidence.score - basis.scorePenalty)

                let history = RecommendationHistory(
                    product: product,
                    recommendedSize: size,
                    userFit: userFit,
                    totalDifference: fitConfidence.averageDifference,
                    measurementDifferences: signedDifferences,
                    recommendationScore: adjustedScore,
                    trueToSizeRecommendation: "\(userFit.fitPreference.rawValue)으로 입으려면 \(size.name) 추천",
                    oversizedRecommendation: oversizedSuggestion(for: size, in: product.sizes),
                    comparisonMethod: basis.methodText,
                    fallbackReason: basis.fallbackReason,
                    productDetailCategory: productDetailCategory,
                    comparisonResult: fitConfidence
                )

                printFitConfidenceDebug(
                    referenceItem: userFit,
                    sizeName: size.name,
                    signedDifferences: signedDifferences,
                    result: fitConfidence
                )

                if adjustedScore > bestFitConfidence ||
                    (adjustedScore == bestFitConfidence && fitConfidence.averageDifference < bestAverageDifference) {
                    bestHistory = history
                    bestFitConfidence = adjustedScore
                    bestAverageDifference = fitConfidence.averageDifference
                }
            }
        }

        if let bestHistory {
            #if DEBUG
            FitMatchDebugLogger.detail(
                screen: "추천 계산",
                action: "최종 후보 선택",
                details: "기준옷=\(bestHistory.userFit.displayName), 방식=\(bestHistory.comparisonMethod), 추천사이즈=\(bestHistory.recommendedSize.name), 신뢰도=\(bestHistory.recommendationScore)"
            )
            #endif
        }

        return bestHistory
    }

    private func usesStandardSizeFallback(product: Product, userFits: [UserFit]) -> Bool {
        product.sizeType == StandardBodySizeChart.metadataMarker
            || userFits.contains { $0.sourceProduct?.sizeType == StandardBodySizeChart.metadataMarker }
    }

    private func standardSizeRecommendation(
        product: Product,
        userFits: [UserFit],
        productDetailCategory: ClosetDetailCategory,
        basis: RecommendationBasis
    ) -> RecommendationHistory? {
        let sizes = product.sizes.sorted { $0.displayOrder < $1.displayOrder }
        var bestHistory: RecommendationHistory?
        var bestDifference = Double.greatestFiniteMagnitude

        for size in sizes {
            guard let productChest = StandardBodySizeChart.chestCircumferenceCm(for: size.name) else { continue }
            for userFit in userFits {
                guard let referenceChest = StandardBodySizeChart.chestCircumferenceCm(for: userFit.sizeName) else { continue }
                let signedDifference = productChest - referenceChest
                let absoluteDifference = abs(signedDifference)
                let score = max(0, min(100, Int((100 - absoluteDifference * 5).rounded())))
                let item = MeasurementComparisonItem(
                    kind: .chest,
                    measurementCode: .standardBodyChestCircumference,
                    productValue: productChest,
                    referenceValue: referenceChest,
                    signedDifference: signedDifference,
                    absoluteDifference: absoluteDifference,
                    score: score,
                    weight: 1
                )
                let comparison = MeasurementComparisonResult(
                    status: .confirmed,
                    score: score,
                    comparedItems: [item],
                    exclusions: standardSizeExclusions,
                    averageDifference: absoluteDifference,
                    minimumComparableCount: 1,
                    requiredKinds: [.chest],
                    minimumRequiredKindCount: 1,
                    requiredAllKinds: []
                )
                let history = RecommendationHistory(
                    product: product,
                    recommendedSize: size,
                    userFit: userFit,
                    totalDifference: absoluteDifference,
                    measurementDifferences: comparison.signedDifferences,
                    recommendationScore: max(0, score - basis.scorePenalty),
                    trueToSizeRecommendation: standardSizeReason(productSize: size.name, referenceSize: userFit.sizeName, difference: signedDifference),
                    oversizedRecommendation: "기준표에는 총장과 소매 정보가 없어 가슴둘레만 비교했습니다.",
                    comparisonMethod: "기준표 가슴둘레 비교",
                    fallbackReason: "실측값이 아닌 한국 의류 기준표 기반 결과입니다.",
                    productDetailCategory: productDetailCategory,
                    comparisonResult: comparison
                )
                if absoluteDifference < bestDifference {
                    bestDifference = absoluteDifference
                    bestHistory = history
                }
            }
        }

        return bestHistory
    }

    private var standardSizeExclusions: [MeasurementComparisonExclusion] {
        [.shoulder, .totalLength, .sleeveLength].map {
            MeasurementComparisonExclusion(
                kind: $0,
                reason: .missingProductValue,
                productCode: nil,
                referenceCode: nil
            )
        }
    }

    private func standardSizeReason(productSize: String, referenceSize: String, difference: Double) -> String {
        let absolute = abs(difference).formatted(.number.precision(.fractionLength(0...1)))
        if difference == 0 { return "두 사이즈의 기준표 가슴둘레가 같습니다." }
        let larger = difference > 0 ? productSize : referenceSize
        return "\(larger) 사이즈가 기준표 가슴둘레 기준 \(absolute)cm 큽니다."
    }

    private func bestInsufficientEvidence(
        product: Product,
        userFits: [UserFit],
        productDetailCategory: ClosetDetailCategory,
        excludedKinds: [MeasurementKind]
    ) -> InsufficientComparisonEvidence? {
        var bestEvidence: InsufficientComparisonEvidence?

        for size in product.sizes.sorted(by: { $0.displayOrder < $1.displayOrder })
        where !size.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for userFit in userFits {
                let result = measurementComparisonEngine.compare(
                    productSize: size,
                    referenceItem: userFit,
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory,
                    excludedKinds: excludedKinds
                )
                guard result.status == .insufficientEvidence else { continue }

                let candidate = InsufficientComparisonEvidence(
                    productSize: size,
                    referenceItem: userFit,
                    comparisonResult: result
                )
                guard let current = bestEvidence else {
                    bestEvidence = candidate
                    continue
                }
                if result.comparedItems.count > current.comparisonResult.comparedItems.count
                    || (result.comparedItems.count == current.comparisonResult.comparedItems.count
                        && result.score > current.comparisonResult.score) {
                    bestEvidence = candidate
                }
            }
        }

        return bestEvidence
    }

    func hasRelevantClosetItem(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> Bool {
        automaticBasisExists(product: product, productDetailCategory: productDetailCategory, userFits: userFits)
    }

    private func selectBasis(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit],
        allowsGlobalFallback: Bool
    ) -> RecommendationBasis {
        if product.sizeType == StandardBodySizeChart.metadataMarker {
            let candidates = standardSizeCandidates(product: product, userFits: userFits)
            return RecommendationBasis(
                userFits: candidates.first.map { [$0.userFit] } ?? Array(userFits.prefix(1)),
                methodText: "기준표 가슴둘레 비교",
                scorePenalty: 18,
                fallbackReason: "실측값이 아닌 한국 의류 기준표 기반 결과입니다."
            )
        }
        let result = comparisonMatcher.match(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        )
        let preferredRepresentativeIDs = Set(preferredRepresentatives(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).map(\.id))
        let ranked = rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: result.compatibleCandidates
        )
        let selected: UserFit?
        if preferredRepresentativeIDs.isEmpty {
            selected = ranked.first?.userFit
        } else {
            selected = ranked.first {
                preferredRepresentativeIDs.contains($0.userFit.id)
            }?.userFit
        }
        if let selected {
            return RecommendationBasis(
                userFits: [selected],
                methodText: "비교 프로필 호환 옷 비교",
                scorePenalty: 0
            )
        }

        return RecommendationBasis(userFits: [], methodText: "사용자 선택 임시 비교", scorePenalty: 12)
    }

    private func automaticBasisExists(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> Bool {
        if product.sizeType == StandardBodySizeChart.metadataMarker {
            return !standardSizeCandidates(product: product, userFits: userFits).isEmpty
        }
        let profileCandidates = comparisonMatcher.match(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).compatibleCandidates
        let ranked = rankedReferenceCandidates(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: profileCandidates
        )
        let preferredRepresentativeIDs = Set(preferredRepresentatives(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).map(\.id))
        if preferredRepresentativeIDs.isEmpty {
            return !ranked.isEmpty
        }
        return ranked.contains {
            preferredRepresentativeIDs.contains($0.userFit.id)
        }
    }

    private func standardSizeCandidates(product: Product, userFits: [UserFit]) -> [FitMatchCandidate] {
        let sameCategory = userFits.filter { $0.category.serviceGroup == product.category.serviceGroup }
        let sorted = sameCategory.sorted { lhs, rhs in
            let lhsConvertible = StandardBodySizeChart.chestCircumferenceCm(for: lhs.sizeName) != nil
            let rhsConvertible = StandardBodySizeChart.chestCircumferenceCm(for: rhs.sizeName) != nil
            if lhsConvertible != rhsConvertible { return lhsConvertible }
            if lhs.isRepresentative != rhs.isRepresentative { return lhs.isRepresentative }
            return lhs.updatedAt > rhs.updatedAt
        }
        return sorted.map { item in
            let convertible = StandardBodySizeChart.chestCircumferenceCm(for: item.sizeName) != nil
            return FitMatchCandidate(
                userFit: item,
                matchRate: convertible ? 70 : 0,
                compatibleMeasurementCount: convertible ? 1 : 0,
                selectionReason: convertible ? "기준표 가슴둘레 비교 가능" : "기준표 변환 확인 필요"
            )
        }
    }

    private func rankedReferenceCandidates(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [FitMatchCandidate] {
        let incomingProfile = comparisonMatcher.profile(for: product, detailCategory: productDetailCategory)
        let preferredRepresentativeIDs = Set(preferredRepresentatives(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: userFits
        ).map(\.id))
        return userFits
            .compactMap { item -> RankedReferenceCandidate? in
                let candidateProfile = comparisonMatcher.profile(for: item)
                guard candidateProfile.garmentFamily == incomingProfile.garmentFamily,
                      candidateProfile.lengthType == incomingProfile.lengthType,
                      let comparison = bestFitConfidence(
                        product: product,
                        userFit: item,
                        productDetailCategory: productDetailCategory
                      ) else {
                    return nil
                }
                let constructionRank: Int
                if incomingProfile.constructionType != .unknown,
                   candidateProfile.constructionType == incomingProfile.constructionType {
                    constructionRank = 2
                } else if incomingProfile.constructionType == .unknown || candidateProfile.constructionType == .unknown {
                    constructionRank = 1
                } else {
                    constructionRank = 0
                }
                guard constructionRank > 0 else { return nil }
                let sameBrand = matchesBrand(item, product: product)
                let reasonParts = [
                    "같은 \(incomingProfile.garmentFamily.displayName)",
                    incomingProfile.lengthType.displayName.isEmpty ? nil : "같은 \(incomingProfile.lengthType.displayName)",
                    constructionRank == 2 ? "같은 봉제 구조" : nil,
                    "실측 \(comparison.comparedItems.count)개 호환",
                    sameBrand ? "같은 브랜드" : nil
                ].compactMap { $0 }
                return RankedReferenceCandidate(
                    candidate: FitMatchCandidate(
                        userFit: item,
                        matchRate: comparison.score,
                        compatibleMeasurementCount: comparison.comparedItems.count,
                        selectionReason: reasonParts.joined(separator: " · ")
                    ),
                    constructionRank: constructionRank,
                    isSameBrand: sameBrand
                )
            }
            .sorted { lhs, rhs in
                let lhsPreferred = preferredRepresentativeIDs.contains(lhs.candidate.userFit.id)
                let rhsPreferred = preferredRepresentativeIDs.contains(rhs.candidate.userFit.id)
                if lhsPreferred != rhsPreferred { return lhsPreferred }
                if lhs.constructionRank != rhs.constructionRank { return lhs.constructionRank > rhs.constructionRank }
                if lhs.candidate.compatibleMeasurementCount != rhs.candidate.compatibleMeasurementCount {
                    return lhs.candidate.compatibleMeasurementCount > rhs.candidate.compatibleMeasurementCount
                }
                if lhs.candidate.matchRate != rhs.candidate.matchRate { return lhs.candidate.matchRate > rhs.candidate.matchRate }
                if lhs.isSameBrand != rhs.isSameBrand { return lhs.isSameBrand }
                if lhs.candidate.userFit.updatedAt != rhs.candidate.userFit.updatedAt {
                    return lhs.candidate.userFit.updatedAt > rhs.candidate.userFit.updatedAt
                }
                return lhs.candidate.id.uuidString < rhs.candidate.id.uuidString
            }
            .map(\.candidate)
    }

    private func preferredRepresentatives(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [UserFit] {
        let incomingGender = product.productTargetGender.taxonomyCode
        return userFits.filter {
            $0.isRepresentative
                && gendersAreCompatible(incomingGender, $0.resolvedGenderCode)
                && $0.category.serviceGroup == product.category.serviceGroup
                && $0.detailCategory == productDetailCategory
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

    private func rankedCandidateScore(
        _ item: UserFit,
        product: Product,
        productDetailCategory: ClosetDetailCategory
    ) -> Int {
        product.sizes
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { size in
                measurementComparisonEngine.compare(
                    productSize: size,
                    referenceItem: item,
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory
                )
            }
            .filter { $0.status == .confirmed }
            .map(\.score)
            .max() ?? 0
    }

    private func bestFitConfidence(
        product: Product,
        userFit: UserFit,
        productDetailCategory: ClosetDetailCategory
    ) -> MeasurementComparisonResult? {
        product.sizes
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map {
                measurementComparisonEngine.compare(
                    productSize: $0,
                    referenceItem: userFit,
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory
                )
            }
            .filter { $0.status == .confirmed }
            .max { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }
                return lhs.averageDifference > rhs.averageDifference
            }
    }

    private func v1MeasurementKinds(
        productCategory: ClothingCategory,
        productDetailCategory: ClosetDetailCategory
    ) -> [MeasurementKind] {
        switch productCategory.serviceGroup {
        case .top, .shirt, .knit:
            return [.shoulder, .chest, .totalLength, .sleeveLength]
        case .outer:
            return [.shoulder, .chest, .totalLength, .sleeveLength, .hem]
        case .bottom, .pants:
            return [.waist, .hip, .thigh, .rise, .hem, .totalLength]
        default:
            return productCategory.measurementKinds(detailCategory: productDetailCategory, gender: .unisex)
        }
    }

    private func printFitConfidenceDebug(
        referenceItem: UserFit,
        sizeName: String,
        signedDifferences: GarmentMeasurements,
        result: MeasurementComparisonResult
    ) {
        #if DEBUG
        let comparedNames = result.comparedItems.map { $0.kind.title }.joined(separator: ", ")
        let ignoredNames = result.exclusions.map { $0.kind.title }.joined(separator: ", ")
        let shoulderScore = result.score(for: .shoulder)?.description ?? "ignored"
        let chestScore = result.score(for: .chest)?.description ?? "ignored"
        let totalLengthScore = result.score(for: .totalLength)?.description ?? "ignored"
        let sleeveScore = result.score(for: .sleeveLength)?.description ?? "ignored"

        FitMatchDebugLogger.detail(
            screen: "추천 계산",
            action: "사이즈 후보 평가",
            details: "기준옷=\(referenceItem.displayName), 사이즈=\(sizeName), 비교=\(comparedNames), 제외=\(ignoredNames), 어깨=\(signedDifferences.shoulder)/\(shoulderScore), 가슴=\(signedDifferences.chest)/\(chestScore), 총장=\(signedDifferences.totalLength)/\(totalLengthScore), 소매=\(signedDifferences.sleeveLength)/\(sleeveScore), 신뢰도=\(result.score), 근거=\(result.reliabilityTitle)"
        )
        #endif
    }

    private func matchesSource(_ item: UserFit, product: Product) -> Bool {
        normalized(item.sourceName) == normalized(product.sourceName)
    }

    private func matchesBrand(_ item: UserFit, product: Product) -> Bool {
        guard let productBrand = product.brand?.name, !productBrand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return normalized(item.brandName) == normalized(productBrand)
    }

    private func matchesShoppingCategory(_ item: UserFit, product: Product) -> Bool {
        normalized(item.sourceCategoryNameForMatching) == normalized(product.sourceCategoryNameForMatching)
    }

    private func matchesInternalCategory(
        _ item: UserFit,
        product: Product,
        productDetailCategory: ClosetDetailCategory
    ) -> Bool {
        item.category == product.category && item.detailCategory == productDetailCategory
    }

    private func hasComparableMeasurements(
        _ item: UserFit,
        product: Product,
        productDetailCategory: ClosetDetailCategory
    ) -> Bool {
        let kinds = v1MeasurementKinds(productCategory: product.category, productDetailCategory: productDetailCategory)
        guard !kinds.isEmpty else { return true }
        return product.sizes.contains { size in
            kinds.contains {
                size.measurements.value(for: $0) > 0 && item.measurements.value(for: $0) > 0
            }
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func measurementWeights(
        productCategory: ClothingCategory,
        productDetailCategory: ClosetDetailCategory,
        referenceDetailCategory: ClosetDetailCategory,
        comparisonMethod: String
    ) -> GarmentMeasurements {
        var weights: GarmentMeasurements

        switch productCategory.serviceGroup {
        case .bottom:
            weights = GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 1.0,
                sleeveLength: 0,
                waist: 1.4,
                hip: 1.2,
                thigh: 0.9,
                rise: 0.7,
                hem: 0.6
            )
        case .shoes:
            weights = GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0, footLength: 1.6)
        case .dress:
            weights = GarmentMeasurements(
                shoulder: 1.0,
                chest: 1.2,
                totalLength: 1.0,
                sleeveLength: 0.5,
                waist: 1.0,
                hip: 0.9
            )
        case .underwear:
            switch productDetailCategory {
            case .menBriefs, .menTrunks, .womenPanty:
                weights = GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0, waist: 1.3, hip: 1.2)
            case .menUndershirt:
                weights = GarmentMeasurements(shoulder: 0, chest: 1.2, totalLength: 0.8, sleeveLength: 0)
            case .womenBra:
                weights = GarmentMeasurements(shoulder: 0, chest: 1.2, totalLength: 0, sleeveLength: 0, underBust: 1.4)
            case .womenCamisole:
                weights = GarmentMeasurements(shoulder: 0, chest: 1.1, totalLength: 0.7, sleeveLength: 0, underBust: 1.2)
            case .womenSlip:
                weights = GarmentMeasurements(shoulder: 0, chest: 1.0, totalLength: 0.7, sleeveLength: 0, waist: 1.0, hip: 1.0, underBust: 1.1)
            case .socks:
                weights = GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0, footLength: 1.0)
            default:
                weights = GarmentMeasurements(shoulder: 0, chest: 1.0, totalLength: 0.6, sleeveLength: 0, waist: 1.0, hip: 1.0)
            }
        case .accessory:
            weights = GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0)
        case .outer:
            weights = GarmentMeasurements(
                shoulder: 1.1,
                chest: 1.5,
                totalLength: 0.8,
                sleeveLength: 1.0,
                hem: 0.6
            )
        case .top, .other, .pants, .shirt, .knit:
            weights = GarmentMeasurements(
                shoulder: 1.2,
                chest: 1.4,
                totalLength: 1.0,
                sleeveLength: 0.8
            )
        }

        switch productDetailCategory {
        case .sleeveless:
            weights.sleeveLength = 0
        case .shortSleeve:
            weights.sleeveLength = min(weights.sleeveLength, 0.2)
        case .longSleeve, .shirt, .sweatshirt, .hoodie, .jumper, .jacket, .coat:
            weights.sleeveLength = max(weights.sleeveLength, 0.9)
        default:
            break
        }

        if comparisonMethod == "사용자 선택 임시 비교",
           productDetailCategory != referenceDetailCategory,
           (productDetailCategory == .shortSleeve || productDetailCategory == .sleeveless) {
            weights.sleeveLength = min(weights.sleeveLength, 0.2)
        }

        return weights
    }

    private func weightedDifference(differences: GarmentMeasurements, weights: GarmentMeasurements) -> Double {
        let weightedSum = differences.shoulder * weights.shoulder
            + differences.chest * weights.chest
            + differences.totalLength * weights.totalLength
            + differences.sleeveLength * weights.sleeveLength
            + differences.waist * weights.waist
            + differences.hip * weights.hip
            + differences.thigh * weights.thigh
            + differences.rise * weights.rise
            + differences.hem * weights.hem
            + differences.footLength * weights.footLength
            + differences.underBust * weights.underBust
        let weightSum = weights.shoulder + weights.chest + weights.totalLength + weights.sleeveLength
            + weights.waist + weights.hip + weights.thigh + weights.rise + weights.hem + weights.footLength + weights.underBust
        guard weightSum > 0 else {
            return .greatestFiniteMagnitude
        }
        return weightedSum / weightSum
    }

    private func validMeasurementCount(size: GarmentMeasurements, userFit: GarmentMeasurements, weights: GarmentMeasurements) -> Int {
        [
            (size.shoulder, userFit.shoulder, weights.shoulder),
            (size.chest, userFit.chest, weights.chest),
            (size.totalLength, userFit.totalLength, weights.totalLength),
            (size.sleeveLength, userFit.sleeveLength, weights.sleeveLength),
            (size.waist, userFit.waist, weights.waist),
            (size.hip, userFit.hip, weights.hip),
            (size.thigh, userFit.thigh, weights.thigh),
            (size.rise, userFit.rise, weights.rise),
            (size.hem, userFit.hem, weights.hem),
            (size.footLength, userFit.footLength, weights.footLength),
            (size.underBust, userFit.underBust, weights.underBust)
        ].filter { productValue, referenceValue, weight in
            productValue > 0 && referenceValue > 0 && weight > 0
        }.count
    }

    private func oversizedSuggestion(for size: ProductSize, in sizes: [ProductSize]) -> String {
        let sortedSizes = sizes.sorted { $0.displayOrder < $1.displayOrder }
        guard let index = sortedSizes.firstIndex(where: { $0.id == size.id }) else {
            return "오버핏으로 입으려면 \(size.name) 추천"
        }

        let nextIndex = min(index + 1, sortedSizes.count - 1)
        return "오버핏으로 입으려면 \(sortedSizes[nextIndex].name) 추천"
    }
}

private struct RecommendationBasis {
    let userFits: [UserFit]
    let methodText: String
    let scorePenalty: Int
    var fallbackReason: String = ""
    var excludedMeasurementKinds: [MeasurementKind] = []
}

private struct RankedReferenceCandidate {
    let candidate: FitMatchCandidate
    let constructionRank: Int
    let isSameBrand: Bool
}
