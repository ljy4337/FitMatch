import Foundation
import OSLog

#if DEBUG
nonisolated enum FitMatchDebugLogger {
    private static let runtimeErrors = Logger(subsystem: "com.ljy4337.fitmatch", category: "RuntimeErrors")
    static func flow(
        traceID: UUID? = nil,
        stage: String,
        state: String,
        fields: [String: String] = [:]
    ) {
        let trace = traceID.map { String($0.uuidString.prefix(8)) } ?? "없음"
        let details = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(sanitize($0.value))" }
            .joined(separator: ", ")
        let suffix = details.isEmpty ? "" : " \(details)"
        print("[FitMatch진단][추적: \(trace)][단계: \(stage)][상태: \(state)]\(suffix)")
    }

    static func failure(
        traceID: UUID? = nil,
        stage: String,
        error: Error,
        nextAction: String,
        fields: [String: String] = [:]
    ) {
        var details = fields
        details.merge(errorFields(error), uniquingKeysWith: { _, new in new })
        details["다음조치"] = nextAction
        flow(traceID: traceID, stage: stage, state: "실패", fields: details)
    }

    static func event(
        screen: String,
        action: String,
        state: String,
        details: @autoclosure () -> String = ""
    ) {
        let value = details()
        let suffix = value.isEmpty ? "" : " \(value)"
        print("[화면: \(screen)][동작: \(action)][상태: \(state)]\(suffix)")
        if state == "안전 차단" || state == "실패" {
            runtimeErrors.error("\(sanitize(screen), privacy: .public) / \(sanitize(action), privacy: .public): \(sanitize(value), privacy: .public)")
        }
    }

    static func detail(
        screen: String,
        action: String,
        details: @autoclosure () -> String
    ) {
        print("[DEBUG][화면: \(screen)][동작: \(action)] \(details())")
    }

    private static func errorFields(_ error: Error) -> [String: String] {
        let nsError = error as NSError
        var fields = [
            "오류유형": String(reflecting: type(of: error)),
            "오류메시지": error.localizedDescription,
            "오류도메인": nsError.domain,
            "오류코드": String(nsError.code)
        ]
        if let path = decodingPath(error) {
            fields["디코딩경로"] = path
        }
        return fields
    }

    private static func decodingPath(_ error: Error) -> String? {
        let codingPath: [CodingKey]
        switch error {
        case DecodingError.dataCorrupted(let context):
            codingPath = context.codingPath
        case DecodingError.keyNotFound(let key, let context):
            codingPath = context.codingPath + [key]
        case DecodingError.typeMismatch(_, let context):
            codingPath = context.codingPath
        case DecodingError.valueNotFound(_, let context):
            codingPath = context.codingPath
        default:
            return nil
        }
        return codingPath.map(\.stringValue).joined(separator: ".")
    }

    private static func sanitize(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > 600 else { return singleLine }
        return String(singleLine.prefix(600)) + "..."
    }
}

extension ParsedProductInfo {
    var fitMatchDebugFields: [String: String] {
        let measurementCount = sizes.reduce(0) { $0 + $1.measurementRecords.count }
        let sizeDetails = sizes.prefix(12).map { size in
            let measurements = size.measurementRecords.prefix(12).map { record in
                let code = record.canonicalMeasurementCode ?? record.measurementCode.rawValue
                return "\(code):\(record.value)\(record.unitRawValue ?? record.unit.rawValue)"
            }.joined(separator: "/")
            return measurements.isEmpty ? size.name : "\(size.name)[\(measurements)]"
        }.joined(separator: ";")
        return [
            "쇼핑몰": sourceName,
            "상품ID": productID ?? "없음",
            "상품명": productName,
            "브랜드": brandName,
            "원본카테고리": sourceCategoryPath ?? "없음",
            "Swift분류": "\(category.rawValue)/\(detailCategory.rawValue)",
            "대상성별": productTargetGender.rawValue,
            "사이즈수": String(sizes.count),
            "실측수": String(measurementCount),
            "사이즈별실측": sizeDetails.isEmpty ? "없음" : sizeDetails,
            "정식API근거": retailerAPIEvidence == nil ? "없음" : "있음",
            "정규URL": canonicalURLString ?? sourceURL.absoluteString
        ]
    }
}

extension FitMatchProductObservationRequest {
    var fitMatchDebugFields: [String: String] {
        let sizes = payload.variants.flatMap(\.sizes)
        let measurementCount = sizes.reduce(0) { $0 + $1.measurements.count }
        return [
            "쇼핑몰코드": payload.source,
            "상품ID": payload.externalProductID,
            "상품명": payload.productName,
            "원본카테고리": payload.sourceCategoryPath ?? "없음",
            "카테고리코드": payload.sourceCategoryCodes.joined(separator: "/"),
            "대상": payload.audience ?? "없음",
            "변형수": String(payload.variants.count),
            "사이즈수": String(sizes.count),
            "실측수": String(measurementCount),
            "구조화필드": payload.structuredFacts.keys.sorted().joined(separator: "/"),
            "원본필드": payload.rawPayload.keys.sorted().joined(separator: "/"),
            "정식API근거": payload.retailerAPIEvidence == nil ? "없음" : "있음"
        ]
    }
}
#endif
