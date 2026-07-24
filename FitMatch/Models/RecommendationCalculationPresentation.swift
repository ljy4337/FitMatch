import Foundation

struct RecommendationCalculationPresentation {
    let coveragePercent: Int
    let bodyShapeTitle: String?
    let bodyShapeMessages: [String]
    let exclusionMessages: [String]

    @MainActor
    init(snapshot: RecommendationCalculationSnapshot) {
        coveragePercent = Int((min(1, max(0, snapshot.comparisonCoverage)) * 100).rounded())

        let applications = snapshot.bodyShapeApplications
        if applications.isEmpty {
            bodyShapeTitle = nil
            bodyShapeMessages = []
        } else {
            let appliedCount = applications.filter { $0.status == .applied }.count
            if appliedCount == applications.count {
                bodyShapeTitle = "선택한 체형을 모두 반영했어요"
            } else if appliedCount == 0 {
                bodyShapeTitle = "체형 설정을 반영하지 못했어요"
            } else {
                bodyShapeTitle = "체형 설정 일부 반영"
            }
            bodyShapeMessages = applications.map(Self.bodyShapeMessage)
        }

        exclusionMessages = snapshot.excludedMeasurements.map {
            "\($0.kind.title) · \(Self.exclusionReason($0.reason))"
        }
    }

    @MainActor
    private static func bodyShapeMessage(
        _ application: BodyShapeApplicationSnapshot
    ) -> String {
        let preferenceName = preferenceName(application.preference)
        switch application.status {
        case .applied:
            let measurements = appliedMeasurementNames(application)
            return "\(preferenceName)을 \(measurements) 비교에 반영했어요."
        case .missingProductMeasurement:
            return "\(preferenceName)은 상품의 관련 치수가 없어 반영하지 못했어요."
        case .missingReferenceMeasurement:
            return "\(preferenceName)은 기준 옷의 관련 치수가 없어 반영하지 못했어요."
        case .missingBothMeasurements:
            return "\(preferenceName)은 상품과 기준 옷 모두 관련 치수가 없어 반영하지 못했어요."
        case .unverifiedDefinition, .incompatibleMeasurementCode:
            return "관련 치수의 측정 기준이 달라 \(preferenceName)을 반영하지 못했어요."
        case .notApplicableCategory, .unavailable:
            return "\(preferenceName)은 해당 상품의 비교 대상이 아니어서 반영하지 못했어요."
        }
    }

    @MainActor
    private static func preferenceName(_ preference: BodyShapePreferenceCode) -> String {
        switch preference {
        case .broadShoulders: return "넓은 어깨 설정"
        case .developedChest: return "가슴 체형"
        case .prominentAbdomen: return "복부 체형"
        case .prominentLowerWaist: return "허리·복부 체형"
        case .developedHips: return "엉덩이 체형"
        case .developedThighs: return "허벅지 체형"
        }
    }

    @MainActor
    private static func appliedMeasurementNames(
        _ application: BodyShapeApplicationSnapshot
    ) -> String {
        let names = application.measurementCodes.map(measurementName)
        if !names.isEmpty {
            return names.joined(separator: "·")
        }
        switch application.preference {
        case .broadShoulders: return MeasurementKind.shoulder.title
        case .developedChest: return MeasurementKind.chest.title
        case .prominentAbdomen: return "복부 관련 치수"
        case .prominentLowerWaist: return MeasurementKind.waist.title
        case .developedHips: return MeasurementKind.hip.title
        case .developedThighs: return MeasurementKind.thigh.title
        }
    }

    @MainActor
    private static func measurementName(_ code: MeasurementCode) -> String {
        switch code {
        case .shoulderWidthSeamToSeam: return MeasurementKind.shoulder.title
        case .chestWidthPitToPit, .chestCircumferenceGarment,
             .chestWidthUniqloBodyWidth, .standardBodyChestCircumference:
            return MeasurementKind.chest.title
        case .upperAbdomenWidthEdgeToEdge: return MeasurementKind.upperAbdomen.title
        case .upperWaistWidthEdgeToEdge: return MeasurementKind.upperWaist.title
        case .waistWidthEdgeToEdge, .waistCircumferenceGarment: return MeasurementKind.waist.title
        case .hipWidthAtWidest: return MeasurementKind.hip.title
        case .thighWidthCrotchToOuter: return MeasurementKind.thigh.title
        default: return "관련 실측"
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
        }
    }
}
