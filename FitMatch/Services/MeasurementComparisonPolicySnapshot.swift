import Foundation

enum MeasurementComparisonPolicySource: String, Equatable {
    case embeddedFallback = "embedded_fallback"
}

struct MeasurementComparisonPolicySnapshot {
    static let embeddedProductionV1 = MeasurementComparisonPolicySnapshot(
        version: "fitmatch-production-measurement-policy-2026-09-28-v2",
        source: .embeddedFallback
    )

    let version: String
    let source: MeasurementComparisonPolicySource

    private init(version: String, source: MeasurementComparisonPolicySource) {
        self.version = version
        self.source = source
    }

    func policy(
        for category: ClothingCategory,
        detailCategory: ClosetDetailCategory
    ) -> MeasurementComparisonPolicy {
        switch category.serviceGroup {
        case .top, .shirt, .knit:
            return MeasurementComparisonPolicy(
                kinds: [.shoulder, .chest, .totalLength, .sleeveLength],
                weights: [.shoulder: 1.5, .chest: 2.0, .totalLength: 1.0, .sleeveLength: 1.0],
                minimumComparableCount: 1,
                requiredAnyKinds: [],
                minimumRequiredKindCount: 0,
                requiredAllKinds: []
            )
        case .outer:
            return MeasurementComparisonPolicy(
                kinds: [.shoulder, .chest, .totalLength, .sleeveLength, .hem],
                weights: [.shoulder: 1.1, .chest: 1.5, .totalLength: 0.8, .sleeveLength: 1.0, .hem: 0.6],
                minimumComparableCount: 1,
                requiredAnyKinds: [],
                minimumRequiredKindCount: 0,
                requiredAllKinds: []
            )
        case .bottom, .pants:
            return MeasurementComparisonPolicy(
                kinds: [.waist, .hip, .thigh, .rise, .hem, .totalLength],
                weights: [.waist: 1.4, .hip: 1.2, .thigh: 0.9, .rise: 0.7, .hem: 0.6, .totalLength: 1.0],
                minimumComparableCount: 1,
                requiredAnyKinds: [.waist, .hip, .thigh],
                minimumRequiredKindCount: 0,
                requiredAllKinds: []
            )
        case .dress:
            return MeasurementComparisonPolicy(
                kinds: [.shoulder, .chest, .totalLength, .waist, .hip],
                weights: [.shoulder: 1.0, .chest: 1.2, .totalLength: 1.0, .waist: 1.0, .hip: 0.9],
                minimumComparableCount: 1,
                requiredAnyKinds: [.chest, .waist, .hip],
                minimumRequiredKindCount: 1,
                requiredAllKinds: []
            )
        case .shoes:
            return MeasurementComparisonPolicy(
                kinds: [],
                weights: [:],
                minimumComparableCount: 1,
                requiredAnyKinds: [],
                minimumRequiredKindCount: 0,
                requiredAllKinds: []
            )
        case .underwear:
            let kinds = category.measurementKinds(detailCategory: detailCategory, gender: .unisex)
            return MeasurementComparisonPolicy(
                kinds: kinds,
                weights: Dictionary(uniqueKeysWithValues: kinds.map { ($0, 1.0) }),
                minimumComparableCount: 1,
                requiredAnyKinds: [],
                minimumRequiredKindCount: 0,
                requiredAllKinds: []
            )
        case .accessory, .other:
            return MeasurementComparisonPolicy(
                kinds: [],
                weights: [:],
                minimumComparableCount: 1,
                requiredAnyKinds: [],
                minimumRequiredKindCount: 0,
                requiredAllKinds: []
            )
        }
    }
}

struct MeasurementComparisonPolicy {
    let kinds: [MeasurementKind]
    let weights: [MeasurementKind: Double]
    let minimumComparableCount: Int
    let requiredAnyKinds: [MeasurementKind]
    let minimumRequiredKindCount: Int
    let requiredAllKinds: [MeasurementKind]

    func weight(for kind: MeasurementKind) -> Double {
        weights[kind] ?? 1
    }

    var expectedWeightSum: Double {
        kinds.map(weight(for:)).reduce(0, +)
    }
}
