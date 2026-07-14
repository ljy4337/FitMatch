import Foundation

struct FitMatchCandidate: Identifiable {
    var id: UUID { userFit.id }
    let userFit: UserFit
    let matchRate: Int
}

struct RecommendationService {
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

    func recommend(
        product: Product,
        selectedReferenceItem: UserFit,
        productDetailCategory: ClosetDetailCategory
    ) -> RecommendationHistory? {
        let fallbackReason = "\(productDetailCategory.rawValue) 기준 옷이 없어 선택한 옷으로 임시 비교했습니다."
        return bestRecommendation(
            product: product,
            userFits: [selectedReferenceItem],
            productDetailCategory: productDetailCategory,
            basis: RecommendationBasis(
                userFits: [selectedReferenceItem],
                methodText: "사용자 선택 임시 비교",
                scorePenalty: 12,
                fallbackReason: fallbackReason
            )
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
        let sameGroupFits = userFits.filter { isSameServiceGroup($0, product: product) }
        let sameDetail = sameGroupFits.filter { $0.detailCategory == productDetailCategory }
        if !sameDetail.isEmpty {
            return sameDetail.sorted { lhs, rhs in
                rankedCandidateScore(lhs, product: product, productDetailCategory: productDetailCategory) >
                    rankedCandidateScore(rhs, product: product, productDetailCategory: productDetailCategory)
            }
        }

        return rankedFitMatches(
            product: product,
            productDetailCategory: productDetailCategory,
            userFits: sameGroupFits
        )
        .prefix(3)
        .map(\.userFit)
    }

    func rankedFitMatches(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [FitMatchCandidate] {
        userFits
            .filter { isSameServiceGroup($0, product: product) }
            .map { item in
                FitMatchCandidate(
                    userFit: item,
                    matchRate: bestFitConfidence(
                        product: product,
                        userFit: item,
                        productDetailCategory: productDetailCategory
                    )?.score ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.matchRate != rhs.matchRate {
                    return lhs.matchRate > rhs.matchRate
                }
                if lhs.userFit.detailCategory == productDetailCategory && rhs.userFit.detailCategory != productDetailCategory {
                    return true
                }
                if lhs.userFit.isRepresentative != rhs.userFit.isRepresentative {
                    return lhs.userFit.isRepresentative
                }
                return lhs.userFit.updatedAt > rhs.userFit.updatedAt
            }
    }

    private func sortCandidates(_ userFits: [UserFit]) -> [UserFit] {
        userFits.sorted { lhs, rhs in
            if lhs.isRepresentative != rhs.isRepresentative {
                return lhs.isRepresentative
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func bestRecommendation(
        product: Product,
        userFits: [UserFit],
        productDetailCategory: ClosetDetailCategory,
        basis: RecommendationBasis
    ) -> RecommendationHistory? {
        var bestHistory: RecommendationHistory?
        var bestFitConfidence = -1
        var bestAverageDifference = Double.greatestFiniteMagnitude

        for size in product.sizes.sorted(by: { $0.displayOrder < $1.displayOrder }) where !size.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for userFit in userFits {
                let signedDifferences = GarmentMeasurements(
                    shoulder: size.measurements.shoulder - userFit.measurements.shoulder,
                    chest: size.measurements.chest - userFit.measurements.chest,
                    totalLength: size.measurements.totalLength - userFit.measurements.totalLength,
                    sleeveLength: size.measurements.sleeveLength - userFit.measurements.sleeveLength,
                    waist: size.measurements.waist - userFit.measurements.waist,
                    hip: size.measurements.hip - userFit.measurements.hip,
                    thigh: size.measurements.thigh - userFit.measurements.thigh,
                    rise: size.measurements.rise - userFit.measurements.rise,
                    hem: size.measurements.hem - userFit.measurements.hem,
                    footLength: size.measurements.footLength - userFit.measurements.footLength,
                    underBust: size.measurements.underBust - userFit.measurements.underBust
                )
                let fitConfidence = fitConfidence(
                    productMeasurements: size.measurements,
                    referenceMeasurements: userFit.measurements,
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory
                )

                let history = RecommendationHistory(
                    product: product,
                    recommendedSize: size,
                    userFit: userFit,
                    totalDifference: fitConfidence.averageDifference,
                    measurementDifferences: signedDifferences,
                    recommendationScore: fitConfidence.score,
                    trueToSizeRecommendation: "\(userFit.fitPreference.rawValue)으로 입으려면 \(size.name) 추천",
                    oversizedRecommendation: oversizedSuggestion(for: size, in: product.sizes),
                    comparisonMethod: basis.methodText,
                    fallbackReason: basis.fallbackReason,
                    productDetailCategory: productDetailCategory
                )

                printFitConfidenceDebug(
                    referenceItem: userFit,
                    sizeName: size.name,
                    signedDifferences: signedDifferences,
                    result: fitConfidence
                )

                if fitConfidence.score > bestFitConfidence ||
                    (fitConfidence.score == bestFitConfidence && fitConfidence.averageDifference < bestAverageDifference) {
                    bestHistory = history
                    bestFitConfidence = fitConfidence.score
                    bestAverageDifference = fitConfidence.averageDifference
                }
            }
        }

        if let bestHistory {
            print("[RecommendationService] selectedReferenceItem: \(bestHistory.userFit.displayName)")
            print("[RecommendationService] comparisonMode: \(bestHistory.comparisonMethod)")
            print("[RecommendationService] finalRecommendedSize: \(bestHistory.recommendedSize.name)")
            print("[RecommendationService] final Fit Confidence: \(bestHistory.recommendationScore)")
        }

        return bestHistory
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
        let sameDetailFits = userFits.filter {
            matchesInternalCategory($0, product: product, productDetailCategory: productDetailCategory)
                && hasComparableMeasurements($0, product: product, productDetailCategory: productDetailCategory)
        }
        let representativeFits = sameDetailFits.filter(\.isRepresentative)

        if !representativeFits.isEmpty {
            return RecommendationBasis(
                userFits: representativeFits,
                methodText: "같은 세부 카테고리 기준 옷 비교",
                scorePenalty: 0
            )
        }

        if !sameDetailFits.isEmpty {
            return RecommendationBasis(
                userFits: sameDetailFits,
                methodText: "같은 세부 카테고리 옷 비교",
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
        userFits.contains {
            matchesInternalCategory($0, product: product, productDetailCategory: productDetailCategory)
                && hasComparableMeasurements($0, product: product, productDetailCategory: productDetailCategory)
        }
    }

    private func rankedCandidateScore(
        _ item: UserFit,
        product: Product,
        productDetailCategory: ClosetDetailCategory
    ) -> Int {
        product.sizes
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { size in
                fitConfidence(
                    productMeasurements: size.measurements,
                    referenceMeasurements: item.measurements,
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory
                ).score
            }
            .max() ?? 0
    }

    private func bestFitConfidence(
        product: Product,
        userFit: UserFit,
        productDetailCategory: ClosetDetailCategory
    ) -> FitConfidenceResult? {
        product.sizes
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map {
                fitConfidence(
                    productMeasurements: $0.measurements,
                    referenceMeasurements: userFit.measurements,
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory
                )
            }
            .max { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }
                return lhs.averageDifference > rhs.averageDifference
            }
    }

    private func fitConfidence(
        productMeasurements: GarmentMeasurements,
        referenceMeasurements: GarmentMeasurements,
        productCategory: ClothingCategory,
        productDetailCategory: ClosetDetailCategory
    ) -> FitConfidenceResult {
        var comparedItems: [FitConfidenceItem] = []
        var ignoredKinds: [MeasurementKind] = []

        for kind in v1MeasurementKinds(productCategory: productCategory, productDetailCategory: productDetailCategory) {
            let productValue = productMeasurements.value(for: kind)
            let referenceValue = referenceMeasurements.value(for: kind)
            guard productValue > 0, referenceValue > 0 else {
                ignoredKinds.append(kind)
                continue
            }

            let difference = abs(productValue - referenceValue)
            let itemScore = max(0, min(100, Int((100 - difference * 5).rounded())))
            comparedItems.append(FitConfidenceItem(kind: kind, difference: difference, score: itemScore))
        }

        let score = comparedItems.isEmpty
            ? 0
            : Int((Double(comparedItems.map(\.score).reduce(0, +)) / Double(comparedItems.count)).rounded())
        let averageDifference = comparedItems.isEmpty
            ? .greatestFiniteMagnitude
            : comparedItems.map(\.difference).reduce(0, +) / Double(comparedItems.count)

        return FitConfidenceResult(
            score: score,
            comparedItems: comparedItems,
            ignoredKinds: ignoredKinds,
            averageDifference: averageDifference
        )
    }

    private func v1MeasurementKinds(
        productCategory: ClothingCategory,
        productDetailCategory: ClosetDetailCategory
    ) -> [MeasurementKind] {
        switch productCategory.serviceGroup {
        case .top, .outer, .shirt, .knit:
            return [.shoulder, .chest, .totalLength, .sleeveLength]
        case .bottom, .pants:
            return [.waist, .hip, .thigh, .totalLength]
        default:
            return productCategory.measurementKinds(detailCategory: productDetailCategory, gender: .unisex)
        }
    }

    private func printFitConfidenceDebug(
        referenceItem: UserFit,
        sizeName: String,
        signedDifferences: GarmentMeasurements,
        result: FitConfidenceResult
    ) {
        let comparedNames = result.comparedItems.map { $0.kind.title }.joined(separator: ", ")
        let ignoredNames = result.ignoredKinds.map(\.title).joined(separator: ", ")
        let shoulderScore = result.score(for: .shoulder)?.description ?? "ignored"
        let chestScore = result.score(for: .chest)?.description ?? "ignored"
        let totalLengthScore = result.score(for: .totalLength)?.description ?? "ignored"
        let sleeveScore = result.score(for: .sleeveLength)?.description ?? "ignored"

        print("[RecommendationService] reference item: \(referenceItem.displayName)")
        print("[RecommendationService] product size name: \(sizeName)")
        print("[RecommendationService] compared measurement names: \(comparedNames)")
        print("[RecommendationService] ignored measurement names: \(ignoredNames)")
        print("[RecommendationService] shoulder difference / score: \(signedDifferences.shoulder) / \(shoulderScore)")
        print("[RecommendationService] chest difference / score: \(signedDifferences.chest) / \(chestScore)")
        print("[RecommendationService] totalLength difference / score: \(signedDifferences.totalLength) / \(totalLengthScore)")
        print("[RecommendationService] sleeve difference / score: \(signedDifferences.sleeveLength) / \(sleeveScore)")
        print("[RecommendationService] final Fit Confidence: \(result.score)")
        print("[RecommendationService] comparison reliability level: \(result.reliabilityTitle)")
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

    private func isSameServiceGroup(_ item: UserFit, product: Product) -> Bool {
        item.category.serviceGroup == product.category.serviceGroup
            && product.category.serviceGroup != .other
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
        case .top, .outer, .other, .pants, .shirt, .knit:
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
}

private struct FitConfidenceItem {
    let kind: MeasurementKind
    let difference: Double
    let score: Int
}

private struct FitConfidenceResult {
    let score: Int
    let comparedItems: [FitConfidenceItem]
    let ignoredKinds: [MeasurementKind]
    let averageDifference: Double

    var reliabilityTitle: String {
        switch comparedItems.count {
        case 4...:
            return "높은 신뢰도"
        case 3:
            return "충분한 비교"
        case 2:
            return "참고 가능"
        case 1:
            return "참고용"
        default:
            return "계산 불가"
        }
    }

    func score(for kind: MeasurementKind) -> Int? {
        comparedItems.first { $0.kind == kind }?.score
    }
}
