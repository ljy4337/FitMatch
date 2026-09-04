import Foundation

struct RecommendationCalculationPresentation {
    let coveragePercent: Int
    let exclusionMessages: [String]

    @MainActor
    init(snapshot: RecommendationCalculationSnapshot) {
        coveragePercent = Int((min(1, max(0, snapshot.comparisonCoverage)) * 100).rounded())
        exclusionMessages = snapshot.excludedMeasurements.map {
            "\($0.kind.title) · \(Self.exclusionReason($0.reason))"
        }
    }

    @MainActor
    private static func exclusionReason(_ reason: MeasurementExclusionReason) -> String {
        switch reason {
        case .missingProductValue: return "상품 치수 없음"
        case .missingReferenceValue: return "기준 옷 치수 없음"
        case .missingBothValues: return "상품과 기준 옷 모두 치수 없음"
        case .incompatibleMeasurementCode,
             .unverifiedProductDefinition,
             .unverifiedReferenceDefinition:
            return "측정 기준이 달라 비교 제외"
        case .categoryPolicy:
            return "해당 카테고리의 비교 대상이 아님"
        case .designAxisDifference:
            return "서버 정책상 디자인 축 차이로 비교 제외"
        case .sleeveLengthMismatch:
            return "반팔·긴팔 소매 구조 차이로 비교 제외"
        case .garmentLengthMismatch:
            return "긴바지·반바지 길이 구조 차이로 비교 제외"
        }
    }
}
