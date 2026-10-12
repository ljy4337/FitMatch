import Foundation

/// A distance index describes known dimensions; it is never a fit probability.
/// This presentation policy can withhold a score, but cannot authorize evidence.
struct SizeComparisonDecision: Equatable {
    let overallScore: Int?
    let comparedCount: Int
    let missingCoreDimensions: [String]
    let differenceSummary: String
    var hasAdditionalMeasurements = false

    var sizeTitle: String { overallScore == nil ? "참고 사이즈" : "가까운 사이즈" }
    var scoreText: String { overallScore.map { "\($0)점" } ?? "부분 비교" }
    var badge: String {
        guard let score = overallScore else { return "확인된 치수만 비교" }
        return Self.distanceDescription(score)
    }
    var explanation: String {
        if comparedCount == 0 { return "저장된 비교 근거가 없어 전체 치수를 판단할 수 없어요." }
        let known = differenceSummary.isEmpty ? "실측 \(comparedCount)개를 비교했어요." : differenceSummary
        if overallScore != nil {
            return known + " 비교한 치수가 내 옷과 가까울수록 점수가 높아요."
        }
        if hasAdditionalMeasurements {
            return known + " 모든 사이즈의 핵심 치수를 함께 확인할 수 없어 전체 점수는 표시하지 않아요."
        }
        let missing = missingCoreDimensions.joined(separator: "·")
        return known + " " + (missing.isEmpty
            ? "전체 치수를 판단할 근거가 부족해요."
            : "\(missing)까지 비교할 수 없어 전체 점수는 표시하지 않아요.")
    }

    static func distanceDescription(_ score: Int) -> String {
        switch score {
        case 90...: return "치수가 가까워요"
        case 75...: return "일부 치수 차이가 있어요"
        default: return "치수 차이가 커요"
        }
    }

    static func make(group: FitMatchComparisonGroup?, result: MeasurementComparisonResult?) -> Self {
        make(group: group, score: result?.score ?? 0,
             status: result?.status ?? .legacy,
             measurements: result.map { RecommendationCalculationSnapshot.make(comparison: $0).usedMeasurements } ?? [],
             additionalMeasurements: result.flatMap { RecommendationCalculationSnapshot.make(comparison: $0).additionalMeasurements } ?? [])
    }

    static func make(
        group: FitMatchComparisonGroup?, score: Int, status: MeasurementComparisonStatus,
        measurements: [UsedMeasurementCalculationSnapshot],
        additionalMeasurements: [UsedMeasurementCalculationSnapshot] = []
    ) -> Self {
        let used = status == .confirmed ? measurements.filter {
            $0.productValue.isFinite && $0.referenceValue.isFinite
                && $0.productValue > 0 && $0.referenceValue > 0
                && $0.signedDifference.isFinite && $0.effectiveWeight.isFinite
                && $0.effectiveWeight > 0
                && $0.measurementCode != .unknown && $0.measurementCode != .legacyUnknown
        } : []
        let kinds = Set(used.map(\.kind))
        var missing: [String] = []
        func require(_ kind: MeasurementKind, _ name: String) {
            if !kinds.contains(kind) { missing.append(name) }
        }
        switch group {
        case .tops, .outerwear:
            require(.chest, "품"); require(.totalLength, "옷 길이")
        case .pants, .skirts:
            require(.waist, "허리"); require(.hip, "엉덩이"); require(.totalLength, "옷 길이")
        case .onePiece:
            require(.chest, "품"); require(.totalLength, "옷 길이")
            if !kinds.contains(.waist) && !kinds.contains(.hip) { missing.append("허리·엉덩이") }
        case .innerwear, .homewear, .none:
            // These groups contain multiple structures. Never guess an upper
            // or lower garment policy from whichever sparse rows are present.
            missing.append("전체 치수")
        }
        let order: [MeasurementKind] = [.chest, .waist, .hip, .totalLength, .shoulder, .thigh, .rise, .sleeveLength, .hem, .underBust, .upperWaist, .upperAbdomen, .footLength]
        let additional = status == .confirmed ? additionalMeasurements : []
        let summary = (used + additional).sorted {
            (order.firstIndex(of: $0.kind) ?? 99) < (order.firstIndex(of: $1.kind) ?? 99)
        }.prefix(3).map { measurement in
            let title: String
            switch measurement.kind {
            case .chest: title = measurement.measurementCode == .chestCircumferenceGarment ? "가슴둘레" : "가슴단면"
            case .totalLength: title = "옷 길이"
            case .waist: title = measurement.measurementCode == .waistCircumferenceGarment ? "허리둘레" : "허리단면"
            case .hip: title = "엉덩이"
            case .shoulder: title = "어깨"
            default: title = measurement.displayTitle ?? measurement.kind.title
            }
            let delta = measurement.signedDifference
            if abs(delta) < 0.05 { return "\(title) 같음" }
            let direction = measurement.kind == .totalLength || measurement.kind == .sleeveLength
                ? (delta > 0 ? "김" : "짧음") : (delta > 0 ? "큼" : "작음")
            return "\(title) \(String(format: "%.1f", abs(delta)))cm \(direction)"
        }.joined(separator: ", ")
        return Self(overallScore: !used.isEmpty && missing.isEmpty ? score : nil,
                    comparedCount: used.count, missingCoreDimensions: missing,
                    differenceSummary: summary.isEmpty ? "" : "내 옷과 비교: \(summary).",
                    hasAdditionalMeasurements: !additional.isEmpty)
    }
}

extension RecommendationHistory {
    var sizeComparisonDecision: SizeComparisonDecision {
        SizeComparisonDecision.make(
            group: userFit.comparisonGroup, score: recommendationScore, status: comparisonStatus,
            measurements: calculationSnapshot?.usedMeasurements ?? [],
            additionalMeasurements: calculationSnapshot?.additionalMeasurements ?? []
        )
    }
}
