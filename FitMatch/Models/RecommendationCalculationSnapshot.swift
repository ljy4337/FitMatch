import Foundation

enum BodyShapePreferenceCode: String, Codable, CaseIterable {
    case broadShoulders = "broad_shoulders"
    case developedChest = "developed_chest"
    case prominentAbdomen = "prominent_abdomen"
    case prominentLowerWaist = "prominent_lower_waist"
    case developedHips = "developed_hips"
    case developedThighs = "developed_thighs"
}

enum BodyShapeApplicationStatus: String, Codable {
    case applied
    case notApplicableCategory = "not_applicable_category"
    case missingProductMeasurement = "missing_product_measurement"
    case missingReferenceMeasurement = "missing_reference_measurement"
    case missingBothMeasurements = "missing_both_measurements"
    case unverifiedDefinition = "unverified_definition"
    case incompatibleMeasurementCode = "incompatible_measurement_code"
    case unavailable = "unavailable"
}

struct BodyShapeApplicationSnapshot: Codable, Equatable {
    let preference: BodyShapePreferenceCode
    let status: BodyShapeApplicationStatus
    let measurementCodes: [MeasurementCode]
}

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
    static let currentVersion = 1

    let version: Int
    let bodyShapeSettings: BodyShapePreferences
    let bodyShapeApplications: [BodyShapeApplicationSnapshot]
    let usedMeasurements: [UsedMeasurementCalculationSnapshot]
    let excludedMeasurements: [MeasurementComparisonExclusion]
    let comparisonCoverage: Double

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
        bodyShapeSettings: BodyShapePreferences
    ) -> RecommendationCalculationSnapshot {
        RecommendationCalculationSnapshot(
            version: currentVersion,
            bodyShapeSettings: bodyShapeSettings,
            bodyShapeApplications: applicationSnapshots(
                preferences: bodyShapeSettings,
                comparison: comparison
            ),
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
            comparisonCoverage: comparison.comparisonCoverage
        )
    }

    private static func applicationSnapshots(
        preferences: BodyShapePreferences,
        comparison: MeasurementComparisonResult
    ) -> [BodyShapeApplicationSnapshot] {
        selectedPreferences(preferences).map { preference, kinds in
            let appliedItems = comparison.comparedItems.filter { kinds.contains($0.kind) }
            if !appliedItems.isEmpty {
                return BodyShapeApplicationSnapshot(
                    preference: preference,
                    status: .applied,
                    measurementCodes: appliedItems.map(\.measurementCode)
                )
            }

            let relevantExclusions = comparison.exclusions.filter { kinds.contains($0.kind) }
            return BodyShapeApplicationSnapshot(
                preference: preference,
                status: applicationStatus(from: relevantExclusions),
                measurementCodes: []
            )
        }
    }

    private static func selectedPreferences(
        _ preferences: BodyShapePreferences
    ) -> [(BodyShapePreferenceCode, [MeasurementKind])] {
        var selected: [(BodyShapePreferenceCode, [MeasurementKind])] = []
        if preferences.hasBroadShoulders { selected.append((.broadShoulders, [.shoulder])) }
        if preferences.hasDevelopedChest { selected.append((.developedChest, [.chest])) }
        if preferences.hasProminentAbdomen {
            selected.append((.prominentAbdomen, [.upperAbdomen, .upperWaist]))
        }
        if preferences.hasProminentLowerWaist {
            selected.append((.prominentLowerWaist, [.waist]))
        }
        if preferences.hasDevelopedHips { selected.append((.developedHips, [.hip])) }
        if preferences.hasDevelopedThighs { selected.append((.developedThighs, [.thigh])) }
        return selected
    }

    private static func applicationStatus(
        from exclusions: [MeasurementComparisonExclusion]
    ) -> BodyShapeApplicationStatus {
        if exclusions.isEmpty { return .notApplicableCategory }
        if exclusions.contains(where: { $0.reason == .incompatibleMeasurementCode }) {
            return .incompatibleMeasurementCode
        }
        if exclusions.contains(where: {
            $0.reason == .unverifiedProductDefinition || $0.reason == .unverifiedReferenceDefinition
        }) {
            return .unverifiedDefinition
        }
        if exclusions.contains(where: { $0.reason == .missingBothValues }) {
            return .missingBothMeasurements
        }
        if exclusions.contains(where: { $0.reason == .missingProductValue }) {
            return .missingProductMeasurement
        }
        if exclusions.contains(where: { $0.reason == .missingReferenceValue }) {
            return .missingReferenceMeasurement
        }
        if exclusions.allSatisfy({ $0.reason == .categoryPolicy }) {
            return .notApplicableCategory
        }
        return .unavailable
    }
}

nonisolated struct RecommendationComparisonEnvelope: Codable {
    let snapshot: RecommendationCalculationSnapshot
}
