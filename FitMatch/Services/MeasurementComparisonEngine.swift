import Foundation

enum MeasurementComparisonStatus: String, Codable, Equatable {
    case legacy
    case confirmed
    case insufficientEvidence = "insufficient_evidence"
}

enum MeasurementExclusionReason: String, Codable, Equatable {
    case categoryPolicy = "category_policy"
    case missingProductValue = "missing_product_value"
    case missingReferenceValue = "missing_reference_value"
    case missingBothValues = "missing_both_values"
    case unverifiedProductDefinition = "unverified_product_definition"
    case unverifiedReferenceDefinition = "unverified_reference_definition"
    case incompatibleMeasurementCode = "incompatible_measurement_code"

    var userMessage: String {
        switch self {
        case .categoryPolicy:
            return "의류 구조가 달라 제외했습니다."
        case .missingProductValue:
            return "비교 상품의 실측값이 없습니다."
        case .missingReferenceValue:
            return "기준 옷의 실측값이 없습니다."
        case .missingBothValues:
            return "상품과 기준 옷 모두 실측값이 없습니다."
        case .unverifiedProductDefinition:
            return "비교 상품의 측정 방식을 확인할 수 없습니다."
        case .unverifiedReferenceDefinition:
            return "기준 옷의 측정 방식을 확인할 수 없습니다."
        case .incompatibleMeasurementCode:
            return "측정 방식이 서로 달라 제외했습니다."
        }
    }
}

struct MeasurementComparisonExclusion: Codable, Equatable {
    let kind: MeasurementKind
    let reason: MeasurementExclusionReason
    let productCode: MeasurementCode?
    let referenceCode: MeasurementCode?
}

struct MeasurementComparisonItem: Equatable {
    let kind: MeasurementKind
    let measurementCode: MeasurementCode
    let productValue: Double
    let referenceValue: Double
    let signedDifference: Double
    let absoluteDifference: Double
    let score: Int
    let weight: Double
}

struct MeasurementComparisonUsage: Codable, Equatable {
    let kind: MeasurementKind
    let measurementCode: MeasurementCode
}

struct MeasurementComparisonResult: Equatable {
    let status: MeasurementComparisonStatus
    let score: Int
    let comparedItems: [MeasurementComparisonItem]
    let exclusions: [MeasurementComparisonExclusion]
    let averageDifference: Double
    let minimumComparableCount: Int
    let requiredKinds: [MeasurementKind]
    let minimumRequiredKindCount: Int
    let requiredAllKinds: [MeasurementKind]
    let expectedWeightSum: Double
    let usedWeightSum: Double

    var comparedKinds: [MeasurementKind] {
        comparedItems.map(\.kind)
    }

    var usages: [MeasurementComparisonUsage] {
        comparedItems.map { MeasurementComparisonUsage(kind: $0.kind, measurementCode: $0.measurementCode) }
    }

    var comparisonCoverage: Double {
        guard expectedWeightSum > 0 else { return 0 }
        return min(1, max(0, usedWeightSum / expectedWeightSum))
    }

    var signedDifferences: GarmentMeasurements {
        var result = GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0)
        for item in comparedItems {
            result.setValue(item.signedDifference, for: item.kind)
        }
        return result
    }

    var reliabilityTitle: String {
        guard status == .confirmed else { return "근거 부족" }
        switch comparedItems.count {
        case 4...: return "높은 신뢰도"
        case 3: return "충분한 비교"
        default: return "최소 기준 충족"
        }
    }

    func score(for kind: MeasurementKind) -> Int? {
        comparedItems.first { $0.kind == kind }?.score
    }
}

struct MeasurementComparisonEngine {
    func compare(
        productSize: ProductSize,
        referenceItem: UserFit,
        productCategory: ClothingCategory,
        productDetailCategory: ClosetDetailCategory,
        excludedKinds: [MeasurementKind] = [],
        bodyShapePreferences: BodyShapePreferences = .none
    ) -> MeasurementComparisonResult {
        let policy = policy(
            for: productCategory,
            detailCategory: productDetailCategory,
            bodyShapePreferences: bodyShapePreferences
        )
        var comparedItems: [MeasurementComparisonItem] = []
        var exclusions: [MeasurementComparisonExclusion] = []

        for kind in policy.kinds {
            if excludedKinds.contains(kind) {
                exclusions.append(exclusion(kind: kind, reason: .categoryPolicy, productRecords: productSize.measurementRecords, referenceRecords: referenceItem.measurementRecords))
                continue
            }

            let productRecords = records(for: kind, in: productSize.measurementRecords)
            let referenceRecords = records(for: kind, in: referenceItem.measurementRecords)
            guard !productRecords.isEmpty || !referenceRecords.isEmpty else {
                exclusions.append(exclusion(kind: kind, reason: .missingBothValues, productRecords: productSize.measurementRecords, referenceRecords: referenceItem.measurementRecords))
                continue
            }
            guard !productRecords.isEmpty else {
                exclusions.append(exclusion(kind: kind, reason: .missingProductValue, productRecords: productSize.measurementRecords, referenceRecords: referenceItem.measurementRecords))
                continue
            }
            guard !referenceRecords.isEmpty else {
                exclusions.append(exclusion(kind: kind, reason: .missingReferenceValue, productRecords: productSize.measurementRecords, referenceRecords: referenceItem.measurementRecords))
                continue
            }

            let comparableProductRecords = productRecords.filter(\.isComparable)
            let comparableReferenceRecords = referenceRecords.filter(\.isComparable)

            guard !comparableProductRecords.isEmpty else {
                exclusions.append(exclusion(kind: kind, reason: .unverifiedProductDefinition, productRecords: productRecords, referenceRecords: referenceRecords))
                continue
            }
            guard !comparableReferenceRecords.isEmpty else {
                exclusions.append(exclusion(kind: kind, reason: .unverifiedReferenceDefinition, productRecords: productRecords, referenceRecords: referenceRecords))
                continue
            }
            guard let pair = matchingPair(
                kind: kind,
                productRecords: comparableProductRecords,
                referenceRecords: comparableReferenceRecords
            ) else {
                exclusions.append(exclusion(kind: kind, reason: .incompatibleMeasurementCode, productRecords: comparableProductRecords, referenceRecords: comparableReferenceRecords))
                continue
            }

            let signedDifference = pair.productValue - pair.referenceValue
            let absoluteDifference = abs(signedDifference)
            let itemScore = max(0, min(100, Int((100 - absoluteDifference * 5).rounded())))
            comparedItems.append(
                MeasurementComparisonItem(
                    kind: kind,
                    measurementCode: pair.comparisonCode,
                    productValue: pair.productValue,
                    referenceValue: pair.referenceValue,
                    signedDifference: signedDifference,
                    absoluteDifference: absoluteDifference,
                    score: itemScore,
                    weight: policy.weight(for: kind)
                )
            )
        }

        let availableAbdomenKinds = comparedItems.filter {
            $0.kind == .upperAbdomen || $0.kind == .upperWaist
        }.map(\.kind)
        if !availableAbdomenKinds.isEmpty {
            let dividedWeight = 1.4 * 1.25 / Double(availableAbdomenKinds.count)
            comparedItems = comparedItems.map { item in
                guard availableAbdomenKinds.contains(item.kind) else { return item }
                return MeasurementComparisonItem(
                    kind: item.kind,
                    measurementCode: item.measurementCode,
                    productValue: item.productValue,
                    referenceValue: item.referenceValue,
                    signedDifference: item.signedDifference,
                    absoluteDifference: item.absoluteDifference,
                    score: item.score,
                    weight: dividedWeight
                )
            }
        }

        let weightSum = comparedItems.map(\.weight).reduce(0, +)
        let expectedWeightSum = policy.expectedWeightSum
        let score = weightSum > 0
            ? Int((comparedItems.map { Double($0.score) * $0.weight }.reduce(0, +) / weightSum).rounded())
            : 0
        let averageDifference = weightSum > 0
            ? comparedItems.map { $0.absoluteDifference * $0.weight }.reduce(0, +) / weightSum
            : .greatestFiniteMagnitude
        let requiredKindCount = comparedItems.filter { policy.requiredAnyKinds.contains($0.kind) }.count
        let hasRequiredKinds = policy.requiredAnyKinds.isEmpty
            || requiredKindCount >= policy.minimumRequiredKindCount
        let hasAllRequiredKinds = policy.requiredAllKinds.allSatisfy { requiredKind in
            comparedItems.contains { $0.kind == requiredKind }
        }
        let status: MeasurementComparisonStatus = comparedItems.count >= policy.minimumComparableCount
            && hasRequiredKinds
            && hasAllRequiredKinds
            ? .confirmed
            : .insufficientEvidence

        return MeasurementComparisonResult(
            status: status,
            score: score,
            comparedItems: comparedItems,
            exclusions: exclusions,
            averageDifference: averageDifference,
            minimumComparableCount: policy.minimumComparableCount,
            requiredKinds: policy.requiredAnyKinds,
            minimumRequiredKindCount: policy.minimumRequiredKindCount,
            requiredAllKinds: policy.requiredAllKinds,
            expectedWeightSum: expectedWeightSum,
            usedWeightSum: weightSum
        )
    }

    private func records(
        for kind: MeasurementKind,
        in records: [GarmentMeasurementRecord]
    ) -> [GarmentMeasurementRecord] {
        records.filter {
            $0.displayKindRawValue == kind.displayKind.rawValue && $0.value.isFinite && $0.value > 0
        }
    }

    private struct ComparableMeasurementPair {
        let comparisonCode: MeasurementCode
        let productValue: Double
        let referenceValue: Double
    }

    private func matchingPair(
        kind: MeasurementKind,
        productRecords: [GarmentMeasurementRecord],
        referenceRecords: [GarmentMeasurementRecord]
    ) -> ComparableMeasurementPair? {
        if kind == .chest,
           let productRecord = preferredGarmentChestRecord(in: productRecords),
           let referenceRecord = preferredGarmentChestRecord(in: referenceRecords) {
            return ComparableMeasurementPair(
                comparisonCode: .chestWidthPitToPit,
                productValue: garmentChestWidthValue(productRecord),
                referenceValue: garmentChestWidthValue(referenceRecord)
            )
        }

        for productRecord in productRecords {
            if let referenceRecord = referenceRecords.first(where: { $0.measurementCode == productRecord.measurementCode }) {
                return ComparableMeasurementPair(
                    comparisonCode: productRecord.measurementCode,
                    productValue: productRecord.value,
                    referenceValue: referenceRecord.value
                )
            }
        }
        return nil
    }

    private func preferredGarmentChestRecord(
        in records: [GarmentMeasurementRecord]
    ) -> GarmentMeasurementRecord? {
        records.first { $0.measurementCode == .chestWidthPitToPit }
            ?? records.first { $0.measurementCode == .chestCircumferenceGarment }
    }

    private func garmentChestWidthValue(_ record: GarmentMeasurementRecord) -> Double {
        record.measurementCode == .chestCircumferenceGarment
            ? record.value / 2
            : record.value
    }

    private func exclusion(
        kind: MeasurementKind,
        reason: MeasurementExclusionReason,
        productRecords: [GarmentMeasurementRecord],
        referenceRecords: [GarmentMeasurementRecord]
    ) -> MeasurementComparisonExclusion {
        MeasurementComparisonExclusion(
            kind: kind,
            reason: reason,
            productCode: records(for: kind, in: productRecords).first?.measurementCode,
            referenceCode: records(for: kind, in: referenceRecords).first?.measurementCode
        )
    }

    private func policy(
        for category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        bodyShapePreferences: BodyShapePreferences
    ) -> MeasurementComparisonPolicy {
        let preferredKinds = bodyShapePreferences.preferredMeasurementKinds
        func weighted(_ weights: [MeasurementKind: Double]) -> [MeasurementKind: Double] {
            weights.mapValues { $0 }.reduce(into: [:]) { result, pair in
                result[pair.key] = pair.value * (preferredKinds.contains(pair.key) ? 1.25 : 1)
            }
        }
        let abdomenKinds: [MeasurementKind] = bodyShapePreferences.hasProminentAbdomen
            ? [.upperAbdomen, .upperWaist]
            : []
        switch category.serviceGroup {
        case .top, .shirt, .knit:
            var weights: [MeasurementKind: Double] = [
                .shoulder: 1.2, .chest: 1.4, .totalLength: 1.0, .sleeveLength: 0.8
            ]
            if detailCategory == .sleeveless { weights[.sleeveLength] = 0 }
            if detailCategory == .shortSleeve { weights[.sleeveLength] = 0.2 }
            return MeasurementComparisonPolicy(
                kinds: ([.shoulder, .chest, .totalLength, .sleeveLength].filter { (weights[$0] ?? 0) > 0 }) + abdomenKinds,
                weights: weighted(weights),
                minimumComparableCount: 2,
                requiredAnyKinds: [.shoulder, .chest],
                minimumRequiredKindCount: 1,
                requiredAllKinds: []
            )
        case .outer:
            return MeasurementComparisonPolicy(
                kinds: [.shoulder, .chest, .totalLength, .sleeveLength, .hem] + abdomenKinds,
                weights: weighted([.shoulder: 1.1, .chest: 1.5, .totalLength: 0.8, .sleeveLength: 1.0, .hem: 0.6]),
                minimumComparableCount: 2,
                requiredAnyKinds: [],
                minimumRequiredKindCount: 0,
                requiredAllKinds: [.chest]
            )
        case .bottom, .pants:
            return MeasurementComparisonPolicy(
                kinds: [.waist, .hip, .thigh, .rise, .hem, .totalLength],
                weights: weighted([.waist: 1.4, .hip: 1.2, .thigh: 0.9, .rise: 0.7, .hem: 0.6, .totalLength: 1.0]),
                minimumComparableCount: 2,
                requiredAnyKinds: [.waist, .hip, .thigh],
                minimumRequiredKindCount: 2,
                requiredAllKinds: []
            )
        case .dress:
            return MeasurementComparisonPolicy(
                kinds: [.shoulder, .chest, .totalLength, .waist, .hip],
                weights: [.shoulder: 1.0, .chest: 1.2, .totalLength: 1.0, .waist: 1.0, .hip: 0.9],
                minimumComparableCount: 2,
                requiredAnyKinds: [.chest, .waist, .hip],
                minimumRequiredKindCount: 1,
                requiredAllKinds: []
            )
        case .shoes:
            return MeasurementComparisonPolicy(
                kinds: [.footLength],
                weights: [.footLength: 1.0],
                minimumComparableCount: 1,
                requiredAnyKinds: [.footLength],
                minimumRequiredKindCount: 1,
                requiredAllKinds: []
            )
        case .underwear:
            let kinds = category.measurementKinds(detailCategory: detailCategory, gender: .unisex)
            return MeasurementComparisonPolicy(
                kinds: kinds,
                weights: Dictionary(uniqueKeysWithValues: kinds.map { ($0, 1.0) }),
                minimumComparableCount: min(2, kinds.count),
                requiredAnyKinds: Array(kinds.prefix(2)),
                minimumRequiredKindCount: 1,
                requiredAllKinds: []
            )
        case .accessory, .other:
            let kinds = category.measurementKinds(detailCategory: detailCategory, gender: .unisex)
            return MeasurementComparisonPolicy(
                kinds: kinds,
                weights: Dictionary(uniqueKeysWithValues: kinds.map { ($0, 1.0) }),
                minimumComparableCount: kinds.isEmpty ? 1 : min(2, kinds.count),
                requiredAnyKinds: [],
                minimumRequiredKindCount: 0,
                requiredAllKinds: []
            )
        }
    }
}

private struct MeasurementComparisonPolicy {
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
        let regularKinds = kinds.filter { $0 != .upperAbdomen && $0 != .upperWaist }
        let regularWeight = regularKinds.map(weight(for:)).reduce(0, +)
        let includesAbdomenGroup = kinds.contains(.upperAbdomen) || kinds.contains(.upperWaist)
        return regularWeight + (includesAbdomenGroup ? 1.4 * 1.25 : 0)
    }
}

private extension GarmentMeasurements {
    mutating func setValue(_ value: Double, for kind: MeasurementKind) {
        switch kind {
        case .shoulder: shoulder = value
        case .chest: chest = value
        case .totalLength: totalLength = value
        case .sleeveLength: sleeveLength = value
        case .upperAbdomen: upperAbdomen = value
        case .upperWaist: upperWaist = value
        case .waist: waist = value
        case .hip: hip = value
        case .thigh: thigh = value
        case .rise: rise = value
        case .hem: hem = value
        case .footLength: footLength = value
        case .underBust: underBust = value
        }
    }
}
