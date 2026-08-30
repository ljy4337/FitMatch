import Foundation

enum MeasurementComparisonStatus: String, Codable, Equatable {
    case legacy
    case confirmed
    case insufficientEvidence = "insufficient_evidence"
}

enum MeasurementExclusionReason: String, Codable, Equatable {
    case categoryPolicy = "category_policy"
    case sleeveLengthMismatch = "sleeve_length_mismatch"
    case garmentLengthMismatch = "garment_length_mismatch"
    case missingProductValue = "missing_product_value"
    case missingReferenceValue = "missing_reference_value"
    case missingBothValues = "missing_both_values"
    case unverifiedProductDefinition = "unverified_product_definition"
    case unverifiedReferenceDefinition = "unverified_reference_definition"
    case incompatibleMeasurementCode = "incompatible_measurement_code"

    var userMessage: String {
        switch self {
        case .categoryPolicy:
            return "의류 구조가 달라 비교에서 제외했어요."
        case .sleeveLengthMismatch:
            return "반팔과 긴팔은 소매 구조가 달라 비교에서 제외했어요."
        case .garmentLengthMismatch:
            return "긴바지와 반바지는 길이 구조가 달라 비교에서 제외했어요."
        case .missingProductValue:
            return "비교 상품의 실측값이 없어요."
        case .missingReferenceValue:
            return "기준 옷의 실측값이 없어요."
        case .missingBothValues:
            return "상품과 기준 옷 모두 실측값이 없어요."
        case .unverifiedProductDefinition:
            return "비교 상품의 측정 방식을 확인할 수 없어요."
        case .unverifiedReferenceDefinition:
            return "기준 옷의 측정 방식을 확인할 수 없어요."
        case .incompatibleMeasurementCode:
            return "측정 방식이 서로 달라 비교에서 제외했어요."
        }
    }

    var badgeTitle: String {
        switch self {
        case .incompatibleMeasurementCode, .unverifiedProductDefinition, .unverifiedReferenceDefinition:
            return "측정 기준 다름"
        default:
            return "비교 제외"
        }
    }
}

struct MeasurementComparisonExclusion: Codable, Equatable {
    let kind: MeasurementKind
    let reason: MeasurementExclusionReason
    let productCode: MeasurementCode?
    let referenceCode: MeasurementCode?

    var productDefinition: String? { productCode?.comparisonDefinition }
    var referenceDefinition: String? { referenceCode?.comparisonDefinition }

    var definitionDetail: String? {
        guard reason == .incompatibleMeasurementCode else { return nil }
        let product = productDefinition ?? "측정 기준 미확인"
        let reference = referenceDefinition ?? "측정 기준 미확인"
        return "상품: \(product) · 내 옷: \(reference)"
    }
}

struct MeasurementComparisonItem: Equatable {
    let kind: MeasurementKind
    let measurementCode: MeasurementCode
    let displayTitle: String?
    let productValue: Double
    let referenceValue: Double
    let signedDifference: Double
    let absoluteDifference: Double
    let score: Int
    let weight: Double

    init(
        kind: MeasurementKind,
        measurementCode: MeasurementCode,
        displayTitle: String? = nil,
        productValue: Double,
        referenceValue: Double,
        signedDifference: Double,
        absoluteDifference: Double,
        score: Int,
        weight: Double
    ) {
        self.kind = kind
        self.measurementCode = measurementCode
        self.displayTitle = displayTitle
        self.productValue = productValue
        self.referenceValue = referenceValue
        self.signedDifference = signedDifference
        self.absoluteDifference = absoluteDifference
        self.score = score
        self.weight = weight
    }
}

struct MeasurementComparisonUsage: Codable, Equatable {
    let kind: MeasurementKind
    let measurementCode: MeasurementCode
    let displayTitle: String?

    init(
        kind: MeasurementKind,
        measurementCode: MeasurementCode,
        displayTitle: String? = nil
    ) {
        self.kind = kind
        self.measurementCode = measurementCode
        self.displayTitle = displayTitle
    }
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
        comparedItems.map {
            MeasurementComparisonUsage(
                kind: $0.kind,
                measurementCode: $0.measurementCode,
                displayTitle: $0.displayTitle
            )
        }
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
    let policySnapshot: MeasurementComparisonPolicySnapshot

    init(
        policySnapshot: MeasurementComparisonPolicySnapshot = .embeddedProductionV1
    ) {
        self.policySnapshot = policySnapshot
    }

    var activePolicyVersion: String { policySnapshot.version }
    var activePolicySource: MeasurementComparisonPolicySource { policySnapshot.source }

    /// Scores only the canonical metric evidence frozen by vNext at
    /// `begin_comparison`. This entry point deliberately bypasses the embedded
    /// category policy and local record matching: candidate membership,
    /// exclusions, values, and weights are all server-authorized inputs.
    func compareAuthorizedEvidence(
        _ evidence: [VNextAuthorizedMeasurementDTO],
        minimumComparableCount: Int
    ) -> MeasurementComparisonResult? {
        guard !evidence.isEmpty,
              minimumComparableCount > 0,
              evidence.count >= minimumComparableCount else {
            return nil
        }

        let sortedEvidence = evidence.sorted(by: {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.measurementCode < $1.measurementCode
        })
        var seenCodes = Set<String>()
        var comparedItems: [MeasurementComparisonItem] = []
        for metric in sortedEvidence {
            guard seenCodes.insert(metric.measurementCode).inserted,
                  let code = MeasurementCode(rawValue: metric.measurementCode),
                  let kind = Self.measurementKind(for: code),
                  metric.referenceValue.isFinite,
                  metric.targetValue.isFinite,
                  metric.difference.isFinite,
                  metric.absoluteDifference.isFinite,
                  metric.weight.isFinite,
                  metric.weight > 0,
                  abs((metric.targetValue - metric.referenceValue) - metric.difference)
                    < 0.000_001,
                  abs(abs(metric.difference) - metric.absoluteDifference) < 0.000_001 else {
                return nil
            }

            let itemScore = max(
                0,
                min(100, Int((100 - metric.absoluteDifference * 5).rounded()))
            )
            comparedItems.append(MeasurementComparisonItem(
                kind: kind,
                measurementCode: code,
                displayTitle: nil,
                productValue: metric.targetValue,
                referenceValue: metric.referenceValue,
                signedDifference: metric.difference,
                absoluteDifference: metric.absoluteDifference,
                score: itemScore,
                weight: metric.weight
            ))
        }

        let weightSum = comparedItems.map(\.weight).reduce(0, +)
        guard weightSum > 0 else { return nil }
        let score = Int((comparedItems.map {
            Double($0.score) * $0.weight
        }.reduce(0, +) / weightSum).rounded())
        let averageDifference = comparedItems.map {
            $0.absoluteDifference * $0.weight
        }.reduce(0, +) / weightSum
        let requiredAnyKinds = sortedEvidence.enumerated().compactMap { index, metric in
            metric.requirementMode == "REQUIRED_ANY" ? comparedItems[index].kind : nil
        }
        let requiredAllKinds = sortedEvidence.enumerated().compactMap { index, metric in
            metric.requirementMode == "REQUIRED_ALL" ? comparedItems[index].kind : nil
        }

        return MeasurementComparisonResult(
            status: .confirmed,
            score: score,
            comparedItems: comparedItems,
            exclusions: [],
            averageDifference: averageDifference,
            minimumComparableCount: minimumComparableCount,
            requiredKinds: requiredAnyKinds,
            minimumRequiredKindCount: requiredAnyKinds.isEmpty ? 0 : 1,
            requiredAllKinds: requiredAllKinds,
            expectedWeightSum: weightSum,
            usedWeightSum: weightSum
        )
    }

    func compare(
        productSize: ProductSize,
        referenceItem: UserFit,
        productCategory: ClothingCategory,
        productDetailCategory: ClosetDetailCategory,
        excludedKinds: [MeasurementKind] = [],
        excludedKindReasons: [MeasurementKind: MeasurementExclusionReason] = [:]
    ) -> MeasurementComparisonResult {
        let policy = policySnapshot.policy(
            for: productCategory,
            detailCategory: productDetailCategory
        )
        var comparedItems: [MeasurementComparisonItem] = []
        var exclusions: [MeasurementComparisonExclusion] = []

        for kind in policy.kinds {
            if excludedKinds.contains(kind) {
                exclusions.append(exclusion(
                    kind: kind,
                    reason: excludedKindReasons[kind] ?? .categoryPolicy,
                    productRecords: productSize.measurementRecords,
                    referenceRecords: referenceItem.measurementRecords
                ))
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
                    displayTitle: pair.displayTitle,
                    productValue: pair.productValue,
                    referenceValue: pair.referenceValue,
                    signedDifference: signedDifference,
                    absoluteDifference: absoluteDifference,
                    score: itemScore,
                    weight: policy.weight(for: kind)
                )
            )
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
            let resolvedKind = resolvedKind(for: $0)
            let canonicalMatch = resolvedKind == kind
            // 동일 플랫폼의 공식 원본 필드는 raw code/명칭으로 직접 비교한다.
            // 단, 과거 버전에서 canonical 의미와 표시 필드가 엇갈린
            // 명시적 legacy 레코드(예: 유니클로 밑위→총장)는 직접 비교에서 제외한다.
            let directPlatformFieldMatch = !isLegacyDisplayConflict($0, resolvedKind: resolvedKind)
                && $0.sourceIdentity != nil
                && $0.displayKind == kind.displayKind
                && (normalizedSourceKey($0.rawCode) != nil
                    || normalizedSourceKey($0.rawLabel) != nil)
            return (canonicalMatch || directPlatformFieldMatch)
                && $0.value.isFinite
                && $0.value > 0
        }
    }

    static func measurementKind(for code: MeasurementCode) -> MeasurementKind? {
        switch code {
        case .standardBodyChestCircumference,
             .chestWidthPitToPit,
             .chestCircumferenceGarment,
             .chestWidthUniqloBodyWidth:
            return .chest
        case .shoulderWidthSeamToSeam:
            return .shoulder
        case .bodyLengthHPSToHemFront,
             .bodyLengthBackNeckToHem,
             .bodyLengthMusinsaType5,
             .bodyLengthMusinsaType20,
             .bodyLengthMusinsaType21,
             .bodyLengthUniqloBack,
             .bodyLengthUniqloShirt,
             .bodyLengthUniqloKnitFront,
             .pantsOutseamWaistToHem,
             .pantsInseamCrotchToHem,
             .skirtLengthWaistToHem:
            return .totalLength
        case .sleeveShoulderSeamToCuff,
             .sleeveCenterBackToCuff,
             .sleeveRaglanNeckToCuff:
            return .sleeveLength
        case .upperAbdomenWidthEdgeToEdge: return .upperAbdomen
        case .upperWaistWidthEdgeToEdge: return .upperWaist
        case .waistWidthEdgeToEdge, .waistCircumferenceGarment: return .waist
        case .hipWidthAtWidest: return .hip
        case .thighWidthCrotchToOuter: return .thigh
        case .riseCrotchToWaistFront, .riseCrotchToWaistBack: return .rise
        case .hemWidthEdgeToEdge: return .hem
        case .footLengthHeelToToe: return .footLength
        case .underBustWidthEdgeToEdge: return .underBust
        case .unknown, .legacyUnknown: return nil
        }
    }

    private func isLegacyDisplayConflict(
        _ record: GarmentMeasurementRecord,
        resolvedKind: MeasurementKind?
    ) -> Bool {
        guard let resolvedKind,
              record.displayKind != resolvedKind.displayKind else {
            return false
        }
        return record.mappingVersion.lowercased().contains("legacy")
            || record.methodProfile?.lowercased().contains("legacy") == true
    }

    private func resolvedKind(
        for record: GarmentMeasurementRecord
    ) -> MeasurementKind? {
        switch record.measurementCode {
        case .standardBodyChestCircumference,
             .chestWidthPitToPit,
             .chestCircumferenceGarment,
             .chestWidthUniqloBodyWidth:
            return .chest
        case .shoulderWidthSeamToSeam:
            return .shoulder
        case .bodyLengthHPSToHemFront,
             .bodyLengthBackNeckToHem,
             .bodyLengthMusinsaType5,
             .bodyLengthMusinsaType20,
             .bodyLengthMusinsaType21,
             .bodyLengthUniqloBack,
             .bodyLengthUniqloShirt,
             .bodyLengthUniqloKnitFront,
             .pantsOutseamWaistToHem,
             .pantsInseamCrotchToHem,
             .skirtLengthWaistToHem:
            return .totalLength
        case .sleeveShoulderSeamToCuff,
             .sleeveCenterBackToCuff,
             .sleeveRaglanNeckToCuff:
            return .sleeveLength
        case .upperAbdomenWidthEdgeToEdge:
            return .upperAbdomen
        case .upperWaistWidthEdgeToEdge:
            return .upperWaist
        case .waistWidthEdgeToEdge, .waistCircumferenceGarment:
            return .waist
        case .hipWidthAtWidest:
            return .hip
        case .thighWidthCrotchToOuter:
            return .thigh
        case .riseCrotchToWaistFront, .riseCrotchToWaistBack:
            return .rise
        case .hemWidthEdgeToEdge:
            return .hem
        case .footLengthHeelToToe:
            return .footLength
        case .underBustWidthEdgeToEdge:
            return .underBust
        case .unknown, .legacyUnknown:
            return record.displayKind.flatMap { displayKind in
                MeasurementKind.allCases.first { $0.displayKind == displayKind }
            }
        }
    }

    private struct ComparableMeasurementPair {
        let comparisonCode: MeasurementCode
        let displayTitle: String?
        let productValue: Double
        let referenceValue: Double
    }

    private func matchingPair(
        kind: MeasurementKind,
        productRecords: [GarmentMeasurementRecord],
        referenceRecords: [GarmentMeasurementRecord]
    ) -> ComparableMeasurementPair? {
        if recordsUseSamePlatformFormat(productRecords, referenceRecords),
           let pair = matchingSourcePair(
                productRecords: productRecords,
                referenceRecords: referenceRecords
           ) {
            return pair
        }

        if kind == .chest,
           let productRecord = preferredGarmentChestRecord(in: productRecords),
           let referenceRecord = preferredGarmentChestRecord(in: referenceRecords) {
            return normalizedPair(
                kind: kind,
                productRecord: productRecord,
                referenceRecord: referenceRecord
            )
        }

        for productRecord in productRecords {
            if let referenceRecord = referenceRecords.first(where: { $0.measurementCode == productRecord.measurementCode }) {
                return normalizedPair(
                    kind: kind,
                    productRecord: productRecord,
                    referenceRecord: referenceRecord
                )
            }
        }
        return nil
    }

    private func recordsUseSamePlatformFormat(
        _ productRecords: [GarmentMeasurementRecord],
        _ referenceRecords: [GarmentMeasurementRecord]
    ) -> Bool {
        guard let product = productRecords.first,
              let reference = referenceRecords.first,
              let productSource = product.sourceIdentity,
              let referenceSource = reference.sourceIdentity,
              productSource.code == referenceSource.code else {
            return false
        }
        return product.methodSource == reference.methodSource
            && product.methodProfile == reference.methodProfile
    }

    private func matchingSourcePair(
        productRecords: [GarmentMeasurementRecord],
        referenceRecords: [GarmentMeasurementRecord]
    ) -> ComparableMeasurementPair? {
        for productRecord in productRecords {
            let productRawCode = normalizedSourceKey(productRecord.rawCode)
            let referenceRecord: GarmentMeasurementRecord?
            if let productRawCode {
                referenceRecord = referenceRecords.first {
                    normalizedSourceKey($0.rawCode) == productRawCode
                }
            } else {
                guard let productLabel = normalizedSourceKey(productRecord.rawLabel) else {
                    continue
                }
                referenceRecord = referenceRecords.first {
                    normalizedSourceKey($0.rawLabel) == productLabel
                }
            }
            if let referenceRecord {
                let title = sourceDisplayTitle(
                    kind: productRecord.displayKind.flatMap { displayKind in
                        MeasurementKind.allCases.first { $0.displayKind == displayKind }
                    },
                    productRecord: productRecord,
                    referenceRecord: referenceRecord
                )
                return ComparableMeasurementPair(
                    comparisonCode: productRecord.measurementCode,
                    displayTitle: title,
                    productValue: officialCentimeterValue(productRecord),
                    referenceValue: officialCentimeterValue(referenceRecord)
                )
            }
        }
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

    private func preferredGarmentChestRecord(
        in records: [GarmentMeasurementRecord]
    ) -> GarmentMeasurementRecord? {
        records.first { $0.measurementCode == .chestWidthPitToPit }
            ?? records.first { $0.measurementCode == .chestCircumferenceGarment }
    }

    private enum HorizontalRepresentation {
        case circumference
        case width
        case notApplicable
    }

    private func normalizedPair(
        kind: MeasurementKind,
        productRecord: GarmentMeasurementRecord,
        referenceRecord: GarmentMeasurementRecord
    ) -> ComparableMeasurementPair {
        let productRepresentation = horizontalRepresentation(of: productRecord)
        let referenceRepresentation = horizontalRepresentation(of: referenceRecord)
        let bothCircumference = productRepresentation == .circumference
            && referenceRepresentation == .circumference

        if bothCircumference {
            return ComparableMeasurementPair(
                comparisonCode: productRecord.measurementCode,
                displayTitle: circumferenceTitle(for: kind),
                productValue: officialCentimeterValue(productRecord),
                referenceValue: officialCentimeterValue(referenceRecord)
            )
        }

        let hasHorizontalRepresentation = productRepresentation != .notApplicable
            || referenceRepresentation != .notApplicable
        return ComparableMeasurementPair(
            comparisonCode: canonicalWidthCode(
                for: kind,
                fallback: productRecord.measurementCode
            ),
            displayTitle: hasHorizontalRepresentation ? widthTitle(for: kind) : nil,
            productValue: normalizedWidthValue(productRecord),
            referenceValue: normalizedWidthValue(referenceRecord)
        )
    }

    private func canonicalWidthCode(
        for kind: MeasurementKind,
        fallback: MeasurementCode
    ) -> MeasurementCode {
        switch kind {
        case .chest: return .chestWidthPitToPit
        case .upperAbdomen: return .upperAbdomenWidthEdgeToEdge
        case .upperWaist: return .upperWaistWidthEdgeToEdge
        case .waist: return .waistWidthEdgeToEdge
        case .hip: return .hipWidthAtWidest
        case .thigh: return .thighWidthCrotchToOuter
        case .hem: return .hemWidthEdgeToEdge
        case .underBust: return .underBustWidthEdgeToEdge
        default: return fallback
        }
    }

    private func horizontalRepresentation(
        of record: GarmentMeasurementRecord
    ) -> HorizontalRepresentation {
        let normalizedLabel = record.rawLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedLabel.contains("둘레") || normalizedLabel.contains("circumference") {
            return .circumference
        }
        switch record.measurementCode {
        case .standardBodyChestCircumference,
             .chestCircumferenceGarment,
             .waistCircumferenceGarment:
            return .circumference
        case .chestWidthPitToPit,
             .chestWidthUniqloBodyWidth,
             .upperAbdomenWidthEdgeToEdge,
             .upperWaistWidthEdgeToEdge,
             .waistWidthEdgeToEdge,
             .hipWidthAtWidest,
             .thighWidthCrotchToOuter,
             .hemWidthEdgeToEdge,
             .underBustWidthEdgeToEdge:
            return .width
        default:
            return .notApplicable
        }
    }

    private func normalizedWidthValue(_ record: GarmentMeasurementRecord) -> Double {
        horizontalRepresentation(of: record) == .circumference
            ? officialCentimeterValue(record) / 2
            : record.value
    }

    private func officialCentimeterValue(_ record: GarmentMeasurementRecord) -> Double {
        guard let raw = record.rawValueText,
              let match = raw.range(of: #"-?\d+(?:[.,]\d+)?"#, options: .regularExpression),
              let number = Double(raw[match].replacingOccurrences(of: ",", with: ".")) else {
            return record.value
        }
        return raw.lowercased().contains("mm") ? number / 10 : number
    }

    private func sourceDisplayTitle(
        kind: MeasurementKind?,
        productRecord: GarmentMeasurementRecord,
        referenceRecord: GarmentMeasurementRecord
    ) -> String? {
        let productLabel = productRecord.rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceLabel = referenceRecord.rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSourceKey(productLabel) == normalizedSourceKey(referenceLabel),
           !productLabel.isEmpty {
            return productLabel
        }
        guard let kind else { return nil }
        let bothCircumference = horizontalRepresentation(of: productRecord) == .circumference
            && horizontalRepresentation(of: referenceRecord) == .circumference
        return bothCircumference ? circumferenceTitle(for: kind) : widthTitle(for: kind)
    }

    private func circumferenceTitle(for kind: MeasurementKind) -> String? {
        switch kind {
        case .chest: return "가슴둘레"
        case .upperAbdomen: return "복부둘레"
        case .upperWaist, .waist: return "허리둘레"
        case .hip: return "엉덩이둘레"
        case .thigh: return "허벅지둘레"
        case .hem: return "밑단둘레"
        case .underBust: return "밑가슴둘레"
        default: return nil
        }
    }

    private func widthTitle(for kind: MeasurementKind) -> String? {
        switch kind {
        case .chest: return "가슴단면"
        case .upperAbdomen: return "복부단면"
        case .upperWaist: return "상의 허리단면"
        case .waist: return "허리단면"
        case .hip: return "엉덩이단면"
        case .thigh: return "허벅지단면"
        case .hem: return "밑단단면"
        case .underBust: return "밑가슴단면"
        default: return nil
        }
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
