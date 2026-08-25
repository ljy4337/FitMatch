import Foundation
import Testing
@testable import FitMatch

private enum ExperimentalMeasurementDirection: String, Codable, Equatable {
    case undersize
    case equal
    case oversize
}

private struct ExperimentalMeasurementParameter: Codable, Equatable {
    let toleranceCm: Double
    let undersizePenalty: Double
    let oversizePenalty: Double
}

private struct VerifiedStretchAdjustment: Codable, Equatable {
    let penaltyMultiplier: Double
    let evidence: String
}

private struct ExperimentalMeasurementScoreConfiguration: Equatable {
    static let productionParity = ExperimentalMeasurementScoreConfiguration(
        version: "EXPERIMENTAL-production-parity-v1",
        defaultParameter: ExperimentalMeasurementParameter(
            toleranceCm: 0,
            undersizePenalty: 1,
            oversizePenalty: 1
        ),
        parameters: [:]
    )

    // These values are hypotheses for deterministic shadow fixtures only.
    // They are not product policy and must never be read by production compare().
    static let fixtureHypothesisV1 = ExperimentalMeasurementScoreConfiguration(
        version: "EXPERIMENTAL-fixture-hypothesis-2026-08-24-v1",
        defaultParameter: ExperimentalMeasurementParameter(
            toleranceCm: 0.5,
            undersizePenalty: 1,
            oversizePenalty: 1
        ),
        parameters: [
            .chest: .init(toleranceCm: 0.5, undersizePenalty: 1.2, oversizePenalty: 0.8),
            .waist: .init(toleranceCm: 0.5, undersizePenalty: 1.2, oversizePenalty: 0.8),
            .hip: .init(toleranceCm: 0.5, undersizePenalty: 1.15, oversizePenalty: 0.85),
            .thigh: .init(toleranceCm: 0.5, undersizePenalty: 1.1, oversizePenalty: 0.9),
            .totalLength: .init(toleranceCm: 0.5, undersizePenalty: 1, oversizePenalty: 1),
            .sleeveLength: .init(toleranceCm: 0.5, undersizePenalty: 1, oversizePenalty: 1)
        ]
    )

    let version: String
    let defaultParameter: ExperimentalMeasurementParameter
    let parameters: [MeasurementKind: ExperimentalMeasurementParameter]

    func parameter(for kind: MeasurementKind) -> ExperimentalMeasurementParameter {
        parameters[kind] ?? defaultParameter
    }
}

private struct ExperimentalMeasurementScoreDetail: Equatable {
    let kind: MeasurementKind
    let measurementCode: MeasurementCode
    let referenceValue: Double
    let candidateValue: Double
    let signedDelta: Double
    let absoluteDelta: Double
    let toleranceCm: Double
    let effectiveDelta: Double
    let direction: ExperimentalMeasurementDirection
    let penaltyMultiplier: Double
    let stretchMultiplier: Double
    let stretchEvidence: String?
    let productionItemScore: Int
    let experimentalItemScore: Int
    let weight: Double
}

private struct ExperimentalMeasurementScoreResult: Equatable {
    let productionScore: Int
    let experimentalScore: Int
    let scoreDelta: Int
    let coverage: Double
    let eligibility: Bool
    let recommendable: Bool
    let details: [ExperimentalMeasurementScoreDetail]
    let parameterVersion: String
    let reason: String
}

private struct ExperimentalCandidateInput {
    let candidateID: String
    let production: MeasurementComparisonResult
    let experimental: ExperimentalMeasurementScoreResult
}

private struct ExperimentalCandidateRank: Equatable {
    let candidateID: String
    let productionScore: Int
    let experimentalScore: Int
    let productionRank: Int?
    let experimentalRank: Int?
    let coverage: Double
    let eligibility: Bool
    let details: [ExperimentalMeasurementScoreDetail]

    var rankChanged: Bool { productionRank != experimentalRank }
}

private struct ExperimentalRankingReport: Equatable {
    let candidates: [ExperimentalCandidateRank]
    let comparisonCount: Int
    let sameRankCount: Int
    let rankChangedCount: Int
    let topRecommendationChanged: Bool
    let averageScoreDelta: Double
}

private enum ExperimentalMeasurementScoreV2 {
    static func evaluate(
        _ production: MeasurementComparisonResult,
        configuration: ExperimentalMeasurementScoreConfiguration,
        verifiedStretch: [MeasurementKind: VerifiedStretchAdjustment] = [:]
    ) -> ExperimentalMeasurementScoreResult {
        let details = production.comparedItems.map { item in
            let parameter = configuration.parameter(for: item.kind)
            let direction: ExperimentalMeasurementDirection
            if item.signedDifference < 0 {
                direction = .undersize
            } else if item.signedDifference > 0 {
                direction = .oversize
            } else {
                direction = .equal
            }
            let directionalMultiplier: Double
            switch direction {
            case .undersize:
                directionalMultiplier = parameter.undersizePenalty
            case .oversize:
                directionalMultiplier = parameter.oversizePenalty
            case .equal:
                directionalMultiplier = 1
            }
            let stretch = verifiedStretch[item.kind]
            let stretchMultiplier = stretch?.penaltyMultiplier ?? 1
            let effectiveDelta = max(0, item.absoluteDifference - parameter.toleranceCm)
            let score = max(
                0,
                min(
                    100,
                    Int((
                        100
                            - effectiveDelta
                            * 5
                            * directionalMultiplier
                            * stretchMultiplier
                    ).rounded())
                )
            )
            return ExperimentalMeasurementScoreDetail(
                kind: item.kind,
                measurementCode: item.measurementCode,
                referenceValue: item.referenceValue,
                candidateValue: item.productValue,
                signedDelta: item.signedDifference,
                absoluteDelta: item.absoluteDifference,
                toleranceCm: parameter.toleranceCm,
                effectiveDelta: effectiveDelta,
                direction: direction,
                penaltyMultiplier: directionalMultiplier,
                stretchMultiplier: stretchMultiplier,
                stretchEvidence: stretch?.evidence,
                productionItemScore: item.score,
                experimentalItemScore: score,
                weight: item.weight
            )
        }
        let weightSum = details.map(\.weight).reduce(0, +)
        let score = weightSum > 0
            ? Int((details.map {
                Double($0.experimentalItemScore) * $0.weight
            }.reduce(0, +) / weightSum).rounded())
            : 0
        let eligibility = production.status == .confirmed
        return ExperimentalMeasurementScoreResult(
            productionScore: production.score,
            experimentalScore: score,
            scoreDelta: score - production.score,
            coverage: production.comparisonCoverage,
            eligibility: eligibility,
            recommendable: eligibility,
            details: details,
            parameterVersion: configuration.version,
            reason: eligibility
                ? "shadow_similarity_only"
                : "production_eligibility_failed"
        )
    }

    static func compareRankings(
        _ inputs: [ExperimentalCandidateInput]
    ) -> ExperimentalRankingReport {
        let productionOrder = inputs
            .filter { $0.production.status == .confirmed }
            .sorted {
                if $0.production.score != $1.production.score {
                    return $0.production.score > $1.production.score
                }
                if $0.production.averageDifference != $1.production.averageDifference {
                    return $0.production.averageDifference < $1.production.averageDifference
                }
                return $0.candidateID < $1.candidateID
            }
        let experimentalOrder = inputs
            .filter(\.experimental.recommendable)
            .sorted {
                if $0.experimental.experimentalScore != $1.experimental.experimentalScore {
                    return $0.experimental.experimentalScore > $1.experimental.experimentalScore
                }
                if $0.production.averageDifference != $1.production.averageDifference {
                    return $0.production.averageDifference < $1.production.averageDifference
                }
                return $0.candidateID < $1.candidateID
            }
        let productionRanks = Dictionary(uniqueKeysWithValues:
            productionOrder.enumerated().map { ($0.element.candidateID, $0.offset + 1) }
        )
        let experimentalRanks = Dictionary(uniqueKeysWithValues:
            experimentalOrder.enumerated().map { ($0.element.candidateID, $0.offset + 1) }
        )
        let candidates = inputs.map {
            ExperimentalCandidateRank(
                candidateID: $0.candidateID,
                productionScore: $0.production.score,
                experimentalScore: $0.experimental.experimentalScore,
                productionRank: productionRanks[$0.candidateID],
                experimentalRank: experimentalRanks[$0.candidateID],
                coverage: $0.experimental.coverage,
                eligibility: $0.experimental.eligibility,
                details: $0.experimental.details
            )
        }.sorted { $0.candidateID < $1.candidateID }
        let sameRankCount = candidates.filter { !$0.rankChanged }.count
        let delta = candidates.isEmpty ? 0 : candidates.map {
            Double($0.experimentalScore - $0.productionScore)
        }.reduce(0, +) / Double(candidates.count)
        return ExperimentalRankingReport(
            candidates: candidates,
            comparisonCount: candidates.count,
            sameRankCount: sameRankCount,
            rankChangedCount: candidates.count - sameRankCount,
            topRecommendationChanged: productionOrder.first?.candidateID
                != experimentalOrder.first?.candidateID,
            averageScoreDelta: delta
        )
    }
}

private final class P3ExperimentalFixtureBundleToken {}

@MainActor
@Suite struct ExperimentalMeasurementScoreV2Tests {
    @Test func productionParityConfigurationMatchesEverySupportedExperimentalAxis() {
        let kinds: [MeasurementKind] = [
            .chest, .shoulder, .waist, .hip, .thigh,
            .totalLength, .sleeveLength, .rise, .hem
        ]
        let deltas: [Double] = [-3, -1, 0, 1, 3]

        for kind in kinds {
            for delta in deltas {
                let production = comparison(kind: kind, delta: delta)
                let shadow = ExperimentalMeasurementScoreV2.evaluate(
                    production,
                    configuration: .productionParity
                )
                #expect(shadow.experimentalScore == production.score)
                #expect(shadow.scoreDelta == 0)
                #expect(shadow.details.first?.signedDelta == delta)
            }
        }
    }

    @Test func toleranceBoundaryAndDirectionalPenaltyStayExplicit() throws {
        let parameter = ExperimentalMeasurementParameter(
            toleranceCm: 1,
            undersizePenalty: 1.5,
            oversizePenalty: 0.5
        )
        let configuration = ExperimentalMeasurementScoreConfiguration(
            version: "EXPERIMENTAL-direction-test",
            defaultParameter: parameter,
            parameters: [:]
        )
        let boundary = ExperimentalMeasurementScoreV2.evaluate(
            comparison(kind: .chest, delta: 1),
            configuration: configuration
        )
        let undersize = ExperimentalMeasurementScoreV2.evaluate(
            comparison(kind: .chest, delta: -3),
            configuration: configuration
        )
        let oversize = ExperimentalMeasurementScoreV2.evaluate(
            comparison(kind: .chest, delta: 3),
            configuration: configuration
        )

        #expect(boundary.experimentalScore == 100)
        #expect(undersize.experimentalScore == 85)
        #expect(oversize.experimentalScore == 95)
        #expect(try #require(undersize.details.first).direction == .undersize)
        #expect(try #require(oversize.details.first).direction == .oversize)
    }

    @Test func highSimilarityWithLowCoverageAndFailedEligibilityIsNotRecommendable() {
        let production = comparison(
            kind: .chest,
            delta: 0,
            status: .insufficientEvidence,
            expectedWeightSum: 4,
            usedWeightSum: 1
        )
        let shadow = ExperimentalMeasurementScoreV2.evaluate(
            production,
            configuration: .fixtureHypothesisV1
        )

        #expect(shadow.experimentalScore == 100)
        #expect(shadow.coverage == 0.25)
        #expect(!shadow.eligibility)
        #expect(!shadow.recommendable)
        #expect(shadow.reason == "production_eligibility_failed")
    }

    @Test func stretchChangesPenaltyOnlyWithVerifiedEvidence() throws {
        let production = comparison(kind: .waist, delta: -3)
        let withoutEvidence = ExperimentalMeasurementScoreV2.evaluate(
            production,
            configuration: .productionParity
        )
        let withEvidence = ExperimentalMeasurementScoreV2.evaluate(
            production,
            configuration: .productionParity,
            verifiedStretch: [
                .waist: VerifiedStretchAdjustment(
                    penaltyMultiplier: 0.5,
                    evidence: "verified_source_attribute_fixture"
                )
            ]
        )

        #expect(withoutEvidence.experimentalScore == 85)
        #expect(withEvidence.experimentalScore == 93)
        #expect(try #require(withEvidence.details.first).stretchEvidence
            == "verified_source_attribute_fixture")
    }

    @Test func supportedCategoryFixturesReuseProductionEligibilityAndWeights() {
        let fixtures: [(String, ClothingCategory, ClosetDetailCategory)] = [
            ("top", .top, .shortSleeve),
            ("shirt", .top, .shirt),
            ("knit", .top, .knitTop),
            ("outer", .outer, .jacket),
            ("pants", .bottom, .longPants),
            ("denim", .bottom, .denim),
            ("leggings", .bottom, .leggings),
            ("skirt", .bottom, .skirt),
            ("dress", .dress, .onePiece)
        ]
        let engine = MeasurementComparisonEngine()

        for (identifier, category, detail) in fixtures {
            let referenceSize = categorySize(
                name: "reference",
                category: category,
                detail: detail,
                offset: 0
            )
            let candidateSize = categorySize(
                name: "candidate",
                category: category,
                detail: detail,
                offset: 1
            )
            let reference = referenceItem(
                sourceCode: "p3category",
                size: referenceSize,
                category: category,
                detail: detail
            )
            let production = engine.compare(
                productSize: candidateSize,
                referenceItem: reference,
                productCategory: category,
                productDetailCategory: detail
            )
            let shadow = ExperimentalMeasurementScoreV2.evaluate(
                production,
                configuration: .fixtureHypothesisV1
            )

            #expect(production.status == .confirmed, "\(identifier) must remain eligible")
            #expect(production.comparedItems.count >= 2)
            #expect(shadow.recommendable)
            #expect(shadow.coverage > 0)
        }
    }

    @Test func capturedMusinsaFixtureProducesAuditableOldNewRanking() throws {
        let fixtures = try loadMusinsaFixtures()
        let referenceSizes = ParsedProductSizeNormalizer.makeProductSizes(
            from: try #require(fixtures["6566713"])
        )
        let targetSizes = ParsedProductSizeNormalizer.makeProductSizes(
            from: try #require(fixtures["5020093"])
        )
        let referenceSize = try #require(referenceSizes.first {
            SizeTokenNormalizer.displayName(for: $0.name) == "M"
        })
        let reference = referenceItem(
            sourceCode: "musinsa",
            size: referenceSize,
            category: .bottom,
            detail: .longPants
        )
        let report = rankingReport(
            sourceCode: "musinsa",
            sizes: targetSizes,
            reference: reference,
            category: .bottom,
            detail: .longPants
        )

        #expect(report.comparisonCount == targetSizes.count)
        #expect(report.candidates.allSatisfy { $0.productionRank != nil })
        print("P3_REAL_MUSINSA \(rankingDescription(report))")
    }

    @Test func capturedUniqloFixtureProducesAuditableOldNewRanking() throws {
        let fixture = try loadUniqloFixture(productID: "E475941")
        let sizes = ParsedProductSizeNormalizer.makeProductSizes(from: fixture)
        let referenceSize = try #require(sizes.first { $0.name == "M" })
        let reference = referenceItem(
            sourceCode: "uniqlo",
            size: referenceSize,
            category: .top,
            detail: .shirt
        )
        let report = rankingReport(
            sourceCode: "uniqlo",
            sizes: sizes,
            reference: reference,
            category: .top,
            detail: .shirt
        )

        #expect(report.comparisonCount == sizes.count)
        #expect(report.candidates.allSatisfy { $0.productionRank != nil })
        print("P3_REAL_UNIQLO \(rankingDescription(report))")
    }

    @Test func validatedZARAPantsValuesRemainEligibleInShadowRanking() {
        // Captured from ZARA production sample 08372248 / variant 582770476.
        // Only the verified waist/hip/front-rise subset is represented.
        let values: [(String, Double, Double, Double)] = [
            ("XS (KR 24)", 34.5, 46, 32),
            ("S (KR 26)", 37, 48, 32.5),
            ("M (KR 28)", 39.5, 50, 33),
            ("L (KR 30)", 42, 52, 33.5),
            ("XL (KR 32)", 44.5, 54, 34)
        ]
        let sizes = values.map { label, waist, hip, rise in
            bottomSize(
                name: label,
                sourceCode: "zara",
                waist: waist,
                hip: hip,
                rise: rise
            )
        }
        let reference = referenceItem(
            sourceCode: "zara",
            size: sizes[2],
            category: .bottom,
            detail: .longPants
        )
        let report = rankingReport(
            sourceCode: "zara",
            sizes: sizes,
            reference: reference,
            category: .bottom,
            detail: .longPants
        )

        #expect(report.comparisonCount == 5)
        #expect(report.candidates.allSatisfy { $0.productionRank != nil })
        #expect(report.candidates.first { $0.candidateID == "M (KR 28)" }?.productionScore == 100)
        print("P3_VALIDATED_ZARA \(rankingDescription(report))")
    }

    @Test func observationPayloadPreservesConflictAndUnknownRawEvidence() throws {
        let unknownMeasurement = ParsedMeasurement(
            value: 51,
            measurementCode: .unknown,
            displayKind: .chest,
            methodSource: "futuremerchant_api",
            inputSource: .importedSizeChart,
            mappingVersion: "futuremerchant-unverified-v1",
            rawCode: "torso-span",
            rawLabel: "Torso Span",
            rawInfo: "provider-specific basis",
            rawValueText: "51 cm",
            evidenceLevel: .officialText,
            semanticStatus: .unknownDefinition
        )
        var metadata = ProductMetadata(
            sourceCategoryPath: "상의 > 긴소매 티셔츠",
            categoryDepth1Code: "TOP",
            categoryDepth2Code: "LONG_TEE"
        )
        metadata.sourceCategoryDepth1 = "상의"
        metadata.sourceCategoryDepth2 = "긴소매 티셔츠"
        let parsed = ParsedProductInfo(
            sourceURL: try #require(URL(string: "https://www.musinsa.com/products/conflict-1")),
            sourceType: .officialStore,
            sourceName: "무신사",
            brandName: "Fixture",
            productName: "반팔 티셔츠",
            category: .top,
            detailCategory: .longSleeve,
            sizes: [
                ParsedProductSize(
                    name: "M",
                    measurements: GarmentMeasurements(
                        shoulder: 0,
                        chest: 51,
                        totalLength: 0,
                        sleeveLength: 0
                    ),
                    measurementRecords: [unknownMeasurement]
                )
            ],
            productID: "conflict-1",
            sourceCategoryPath: "상의 > 긴소매 티셔츠",
            sourceCategoryDepth1: "상의",
            sourceCategoryDepth2: "긴소매 티셔츠",
            productMetadata: metadata
        )

        let request = try #require(parsed.fitMatchProductObservationRequest())
        #expect(request.payload.sourceCategoryPath == "상의 > 긴소매 티셔츠")
        #expect(request.payload.sourceCategoryCodes == ["TOP", "LONG_TEE"])
        #expect(request.payload.rawPayload["local_classification_conflict"] == "true")
        #expect(request.payload.rawPayload["local_classification_conflict_dimensions"]?
            .contains("length") == true)
        #expect(request.payload.rawPayload["local_classification_conflict_evidence"]?
            .contains("long_sleeve->short_sleeve") == true)
        let raw = try #require(request.payload.variants.first?.sizes.first?.measurements.first)
        #expect(raw.rawCode == "torso-span")
        #expect(raw.rawLabel == "Torso Span")
        #expect(raw.rawValue == 51)
        #expect(raw.rawRepresentation == "provider-specific basis")
        #expect(raw.evidence["semantic_status"] == "unknown_definition")
    }

    private func comparison(
        kind: MeasurementKind,
        delta: Double,
        status: MeasurementComparisonStatus = .confirmed,
        expectedWeightSum: Double = 1,
        usedWeightSum: Double = 1
    ) -> MeasurementComparisonResult {
        let reference = 50.0
        let candidate = reference + delta
        let absolute = abs(delta)
        let itemScore = max(0, min(100, Int((100 - absolute * 5).rounded())))
        return MeasurementComparisonResult(
            status: status,
            score: itemScore,
            comparedItems: [
                MeasurementComparisonItem(
                    kind: kind,
                    measurementCode: code(for: kind),
                    productValue: candidate,
                    referenceValue: reference,
                    signedDifference: delta,
                    absoluteDifference: absolute,
                    score: itemScore,
                    weight: usedWeightSum
                )
            ],
            exclusions: [],
            averageDifference: absolute,
            minimumComparableCount: status == .confirmed ? 1 : 2,
            requiredKinds: [],
            minimumRequiredKindCount: 0,
            requiredAllKinds: [],
            expectedWeightSum: expectedWeightSum,
            usedWeightSum: usedWeightSum
        )
    }

    private func code(for kind: MeasurementKind) -> MeasurementCode {
        switch kind {
        case .shoulder: return .shoulderWidthSeamToSeam
        case .chest: return .chestWidthPitToPit
        case .totalLength: return .pantsInseamCrotchToHem
        case .sleeveLength: return .sleeveShoulderSeamToCuff
        case .upperAbdomen: return .upperAbdomenWidthEdgeToEdge
        case .upperWaist: return .upperWaistWidthEdgeToEdge
        case .waist: return .waistWidthEdgeToEdge
        case .hip: return .hipWidthAtWidest
        case .thigh: return .thighWidthCrotchToOuter
        case .rise: return .riseCrotchToWaistFront
        case .hem: return .hemWidthEdgeToEdge
        case .footLength: return .footLengthHeelToToe
        case .underBust: return .underBustWidthEdgeToEdge
        }
    }

    private func loadMusinsaFixtures() throws -> [String: [ParsedProductSize]] {
        let bundle = Bundle(for: P3ExperimentalFixtureBundleToken.self)
        let url = try #require(bundle.url(
            forResource: "ThreeProductActualSizeFixtures",
            withExtension: "json"
        ))
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]]
        )
        return try Dictionary(uniqueKeysWithValues: root.map { entry in
            let id = try #require(entry["productID"] as? String)
            let data = try JSONSerialization.data(withJSONObject: [
                "data": try #require(entry["data"])
            ])
            let parsed = try MusinsaActualSizeAPIParser().parseActualSize(from: data)
            return (id, parsed.sizes)
        })
    }

    private func loadUniqloFixture(productID: String) throws -> [ParsedProductSize] {
        let bundle = Bundle(for: P3ExperimentalFixtureBundleToken.self)
        let url = try #require(bundle.url(
            forResource: "Uniqlo243FitPairInputs",
            withExtension: "json"
        ))
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]]
        )
        let entry = try #require(root.first { $0["product_id"] as? String == productID })
        let response = try #require(entry["response"])
        return try UniqloSizeAPIParser().parseSizes(
            from: JSONSerialization.data(withJSONObject: response)
        )
    }

    private func rankingReport(
        sourceCode: String,
        sizes: [ProductSize],
        reference: UserFit,
        category: ClothingCategory,
        detail: ClosetDetailCategory
    ) -> ExperimentalRankingReport {
        let engine = MeasurementComparisonEngine()
        let inputs = sizes.map { size in
            let production = engine.compare(
                productSize: size,
                referenceItem: reference,
                productCategory: category,
                productDetailCategory: detail
            )
            return ExperimentalCandidateInput(
                candidateID: size.name,
                production: production,
                experimental: ExperimentalMeasurementScoreV2.evaluate(
                    production,
                    configuration: .fixtureHypothesisV1
                )
            )
        }
        return ExperimentalMeasurementScoreV2.compareRankings(inputs)
    }

    private func referenceItem(
        sourceCode: String,
        size: ProductSize,
        category: ClothingCategory,
        detail: ClosetDetailCategory
    ) -> UserFit {
        let item = UserFit(
            sourceName: sourceCode,
            brandName: "P3 fixture",
            gender: .unisex,
            productName: "P3 reference",
            category: category,
            detailCategory: detail,
            sizeName: size.name,
            measurements: size.measurements,
            fitMemo: "shadow fixture",
            satisfaction: 3
        )
        item.sourcePlatformCode = sourceCode
        item.canonicalEligibility = true
        item.replaceMeasurementRecords(with: size.measurementRecords)
        return item
    }

    private func bottomSize(
        name: String,
        sourceCode: String,
        waist: Double,
        hip: Double,
        rise: Double
    ) -> ProductSize {
        let measurements = GarmentMeasurements(
            shoulder: 0,
            chest: 0,
            totalLength: 0,
            sleeveLength: 0,
            waist: waist,
            hip: hip,
            rise: rise
        )
        let size = ProductSize(name: name, measurements: measurements)
        size.measurementRecords = [
            measurementRecord(
                sourceCode: sourceCode,
                value: waist,
                kind: .waist,
                code: .waistWidthEdgeToEdge,
                rawCode: "zone-name-waist"
            ),
            measurementRecord(
                sourceCode: sourceCode,
                value: hip,
                kind: .hip,
                code: .hipWidthAtWidest,
                rawCode: "zone-name-hips"
            ),
            measurementRecord(
                sourceCode: sourceCode,
                value: rise,
                kind: .rise,
                code: .riseCrotchToWaistFront,
                rawCode: "zone-name-front-rise"
            )
        ]
        return size
    }

    private func categorySize(
        name: String,
        category: ClothingCategory,
        detail: ClosetDetailCategory,
        offset: Double
    ) -> ProductSize {
        let base: [(MeasurementKind, Double, MeasurementCode)]
        switch category.serviceGroup {
        case .top:
            base = [
                (.shoulder, 45, .shoulderWidthSeamToSeam),
                (.chest, 55, .chestWidthPitToPit),
                (.totalLength, 70, .bodyLengthHPSToHemFront),
                (.sleeveLength, 60, .sleeveShoulderSeamToCuff)
            ]
        case .outer:
            base = [
                (.shoulder, 47, .shoulderWidthSeamToSeam),
                (.chest, 58, .chestWidthPitToPit),
                (.totalLength, 72, .bodyLengthHPSToHemFront),
                (.sleeveLength, 62, .sleeveShoulderSeamToCuff),
                (.hem, 55, .hemWidthEdgeToEdge)
            ]
        case .bottom:
            let lengthCode: MeasurementCode = detail == .skirt
                ? .skirtLengthWaistToHem
                : .pantsOutseamWaistToHem
            base = [
                (.waist, 40, .waistWidthEdgeToEdge),
                (.hip, 50, .hipWidthAtWidest),
                (.thigh, 30, .thighWidthCrotchToOuter),
                (.rise, 28, .riseCrotchToWaistFront),
                (.hem, 22, .hemWidthEdgeToEdge),
                (.totalLength, 100, lengthCode)
            ]
        case .dress:
            base = [
                (.shoulder, 40, .shoulderWidthSeamToSeam),
                (.chest, 46, .chestWidthPitToPit),
                (.totalLength, 118, .bodyLengthHPSToHemFront),
                (.waist, 39, .waistWidthEdgeToEdge),
                (.hip, 49, .hipWidthAtWidest)
            ]
        default:
            base = []
        }
        var values = GarmentMeasurements(
            shoulder: 0,
            chest: 0,
            totalLength: 0,
            sleeveLength: 0
        )
        for (kind, value, _) in base {
            switch kind {
            case .shoulder: values.shoulder = value + offset
            case .chest: values.chest = value + offset
            case .totalLength: values.totalLength = value + offset
            case .sleeveLength: values.sleeveLength = value + offset
            case .upperAbdomen: values.upperAbdomen = value + offset
            case .upperWaist: values.upperWaist = value + offset
            case .waist: values.waist = value + offset
            case .hip: values.hip = value + offset
            case .thigh: values.thigh = value + offset
            case .rise: values.rise = value + offset
            case .hem: values.hem = value + offset
            case .footLength: values.footLength = value + offset
            case .underBust: values.underBust = value + offset
            }
        }
        let size = ProductSize(name: name, measurements: values)
        size.measurementRecords = base.map { kind, value, code in
            measurementRecord(
                sourceCode: "p3category",
                value: value + offset,
                kind: kind,
                code: code,
                rawCode: "p3-\(kind.rawValue)"
            )
        }
        return size
    }

    private func measurementRecord(
        sourceCode: String,
        value: Double,
        kind: MeasurementKind,
        code: MeasurementCode,
        rawCode: String
    ) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(
            value: value,
            measurementCode: code,
            displayKind: kind.displayKind,
            methodSource: "\(sourceCode)_verified_fixture",
            inputSource: .importedSizeChart,
            mappingVersion: "p3-validated-fixture-v1",
            rawCode: rawCode,
            rawLabel: rawCode,
            rawValueText: String(value),
            evidenceLevel: .officialText,
            semanticStatus: .mapped
        )
    }

    private func rankingDescription(_ report: ExperimentalRankingReport) -> String {
        let values = report.candidates.map {
            "\($0.candidateID):\($0.productionScore)->\($0.experimentalScore)"
                + "/r\($0.productionRank.map(String.init) ?? "-")"
                + "->\($0.experimentalRank.map(String.init) ?? "-")"
                + "/coverage=\(String(format: "%.2f", $0.coverage))"
                + "/eligible=\($0.eligibility)"
                + "/items=["
                + $0.details.map { detail in
                    "\(detail.kind.rawValue):ref=\(detail.referenceValue)"
                        + ",candidate=\(detail.candidateValue)"
                        + ",delta=\(detail.signedDelta)"
                        + ",absolute=\(detail.absoluteDelta)"
                        + ",tolerance=\(detail.toleranceCm)"
                        + ",effective=\(detail.effectiveDelta)"
                        + ",direction=\(detail.direction.rawValue)"
                        + ",penalty=\(detail.penaltyMultiplier)"
                        + ",old=\(detail.productionItemScore)"
                        + ",new=\(detail.experimentalItemScore)"
                        + ",weight=\(detail.weight)"
                }.joined(separator: ";")
                + "]"
        }.joined(separator: ",")
        return "count=\(report.comparisonCount) same=\(report.sameRankCount) "
            + "changed=\(report.rankChangedCount) topChanged=\(report.topRecommendationChanged) "
            + "avgDelta=\(String(format: "%.2f", report.averageScoreDelta)) \(values)"
    }
}
