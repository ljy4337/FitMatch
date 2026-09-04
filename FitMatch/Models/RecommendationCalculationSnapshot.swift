import Foundation

struct UsedMeasurementCalculationSnapshot: Codable, Equatable {
    let kind: MeasurementKind
    let measurementCode: MeasurementCode
    let displayTitle: String?
    let productValue: Double
    let referenceValue: Double
    let signedDifference: Double
    let absoluteDifference: Double
    let itemScore: Int
    let effectiveWeight: Double

    init(
        kind: MeasurementKind,
        measurementCode: MeasurementCode,
        displayTitle: String? = nil,
        productValue: Double,
        referenceValue: Double,
        signedDifference: Double,
        absoluteDifference: Double,
        itemScore: Int,
        effectiveWeight: Double
    ) {
        self.kind = kind
        self.measurementCode = measurementCode
        self.displayTitle = displayTitle
        self.productValue = productValue
        self.referenceValue = referenceValue
        self.signedDifference = signedDifference
        self.absoluteDifference = absoluteDifference
        self.itemScore = itemScore
        self.effectiveWeight = effectiveWeight
    }
}

struct RecommendationCalculationSnapshot: Codable, Equatable {
    static let currentVersion = 2

    let version: Int
    let usedMeasurements: [UsedMeasurementCalculationSnapshot]
    let excludedMeasurements: [MeasurementComparisonExclusion]
    let comparisonCoverage: Double
    /// Present only for a completed vNext comparison after the server has
    /// accepted the engine payload. Legacy snapshots intentionally omit it.
    let serverApprovedReliability: Int?

    var usages: [MeasurementComparisonUsage] {
        usedMeasurements.map {
            MeasurementComparisonUsage(
                kind: $0.kind,
                measurementCode: $0.measurementCode,
                displayTitle: $0.displayTitle
            )
        }
    }

    static func make(
        comparison: MeasurementComparisonResult,
        serverApprovedReliability: Int? = nil
    ) -> RecommendationCalculationSnapshot {
        RecommendationCalculationSnapshot(
            version: currentVersion,
            usedMeasurements: comparison.comparedItems.map {
                UsedMeasurementCalculationSnapshot(
                    kind: $0.kind,
                    measurementCode: $0.measurementCode,
                    displayTitle: $0.displayTitle,
                    productValue: $0.productValue,
                    referenceValue: $0.referenceValue,
                    signedDifference: $0.signedDifference,
                    absoluteDifference: $0.absoluteDifference,
                    itemScore: $0.score,
                    effectiveWeight: $0.weight
                )
            },
            excludedMeasurements: comparison.exclusions,
            comparisonCoverage: comparison.comparisonCoverage,
            serverApprovedReliability: serverApprovedReliability
        )
    }
}

nonisolated struct RecommendationComparisonEnvelope: Codable {
    let snapshot: RecommendationCalculationSnapshot
}
