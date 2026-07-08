import Foundation

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

    func temporaryComparisonCandidates(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> [UserFit] {
        userFits.sorted { lhs, rhs in
            let lhsScore = temporaryCandidateScore(lhs, product: product, productDetailCategory: productDetailCategory)
            let rhsScore = temporaryCandidateScore(rhs, product: product, productDetailCategory: productDetailCategory)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            if lhs.isRepresentative != rhs.isRepresentative {
                return lhs.isRepresentative
            }
            return lhs.updatedAt > rhs.updatedAt
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
        var bestWeightedDifference = Double.greatestFiniteMagnitude

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
                let differences = GarmentMeasurements(
                    shoulder: abs(signedDifferences.shoulder),
                    chest: abs(signedDifferences.chest),
                    totalLength: abs(signedDifferences.totalLength),
                    sleeveLength: abs(signedDifferences.sleeveLength),
                    waist: abs(signedDifferences.waist),
                    hip: abs(signedDifferences.hip),
                    thigh: abs(signedDifferences.thigh),
                    rise: abs(signedDifferences.rise),
                    hem: abs(signedDifferences.hem),
                    footLength: abs(signedDifferences.footLength),
                    underBust: abs(signedDifferences.underBust)
                )
                let weights = measurementWeights(
                    productCategory: product.category,
                    productDetailCategory: productDetailCategory,
                    referenceDetailCategory: userFit.detailCategory,
                    comparisonMethod: basis.methodText
                )
                let weightedDifference = weightedDifference(differences: differences, weights: weights)
                let validItemCount = validMeasurementCount(size: size.measurements, userFit: userFit.measurements, weights: weights)
                var recommendationScore = max(0, min(100, Int((100 - weightedDifference * 4).rounded())))
                recommendationScore = max(0, recommendationScore - basis.scorePenalty)
                if validItemCount >= 2, recommendationScore > 0 {
                    recommendationScore = max(30, recommendationScore)
                }

                let history = RecommendationHistory(
                    product: product,
                    recommendedSize: size,
                    userFit: userFit,
                    totalDifference: weightedDifference,
                    measurementDifferences: signedDifferences,
                    recommendationScore: recommendationScore,
                    trueToSizeRecommendation: "\(userFit.fitPreference.rawValue)으로 입으려면 \(size.name) 추천",
                    oversizedRecommendation: oversizedSuggestion(for: size, in: product.sizes),
                    comparisonMethod: basis.methodText,
                    fallbackReason: basis.fallbackReason,
                    productDetailCategory: productDetailCategory
                )

                if weightedDifference < bestWeightedDifference {
                    bestHistory = history
                    bestWeightedDifference = weightedDifference
                }
            }
        }

        if let bestHistory {
            print("[RecommendationService] selectedReferenceItem: \(bestHistory.userFit.displayName)")
            print("[RecommendationService] comparisonMode: \(bestHistory.comparisonMethod)")
            print("[RecommendationService] finalRecommendedSize: \(bestHistory.recommendedSize.name)")
            print("[RecommendationService] finalScore: \(bestHistory.recommendationScore)")
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
        let priorityGroups: [(method: String, penalty: Int, filter: (UserFit) -> Bool)] = [
            ("같은 플랫폼/브랜드/세부카테고리 기준 비교", 0, { item in
                matchesSource(item, product: product)
                    && matchesBrand(item, product: product)
                    && item.detailCategory == productDetailCategory
                    && item.isRepresentative
            }),
            ("같은 플랫폼/브랜드/세부카테고리 기준 비교", 0, { item in
                matchesSource(item, product: product)
                    && matchesBrand(item, product: product)
                    && item.detailCategory == productDetailCategory
            }),
            ("같은 브랜드 기준 비교", 0, { item in
                matchesBrand(item, product: product)
                    && item.detailCategory == productDetailCategory
                    && item.isRepresentative
            }),
            ("같은 브랜드 기준 비교", 0, { item in
                matchesBrand(item, product: product)
                    && item.detailCategory == productDetailCategory
            }),
            ("같은 플랫폼 기준 비교", 0, { item in
                matchesSource(item, product: product)
                    && item.detailCategory == productDetailCategory
                    && item.isRepresentative
            }),
            ("같은 플랫폼 기준 비교", 0, { item in
                matchesSource(item, product: product)
                    && item.detailCategory == productDetailCategory
            }),
            ("같은 세부카테고리 기준 비교", 0, { item in
                item.detailCategory == productDetailCategory && item.isRepresentative
            }),
            ("같은 세부카테고리 기준 비교", 0, { item in
                item.detailCategory == productDetailCategory
            }),
            ("같은 대분류 기준 비교", 8, { item in
                item.category.serviceGroup == product.category.serviceGroup && item.isRepresentative
            }),
            ("같은 대분류 기준 비교", 8, { item in
                item.category.serviceGroup == product.category.serviceGroup
            })
        ]

        for group in priorityGroups {
            let matches = userFits.filter(group.filter)
            if !matches.isEmpty {
                return RecommendationBasis(
                    userFits: matches,
                    methodText: group.method,
                    scorePenalty: group.penalty
                )
            }
        }

        return RecommendationBasis(userFits: [], methodText: "사용자 선택 임시 비교", scorePenalty: 12)
    }

    private func automaticBasisExists(
        product: Product,
        productDetailCategory: ClosetDetailCategory,
        userFits: [UserFit]
    ) -> Bool {
        userFits.contains {
            ($0.detailCategory == productDetailCategory)
                || ($0.category.serviceGroup == product.category.serviceGroup)
        }
    }

    private func temporaryCandidateScore(
        _ item: UserFit,
        product: Product,
        productDetailCategory: ClosetDetailCategory
    ) -> Int {
        var score = 0
        if item.category.serviceGroup == product.category.serviceGroup {
            score += 100
        }
        if item.isRepresentative {
            score += 40
        }
        if matchesSource(item, product: product) {
            score += 30
        }
        if matchesBrand(item, product: product) {
            score += 30
        }
        if item.detailCategory == productDetailCategory {
            score += 25
        }
        return score
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
