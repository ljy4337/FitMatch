import Foundation

/// One immutable retailer response captured at the network boundary.
///
/// `body` keeps the exact bytes for retry/fingerprint evidence. Only a decoded
/// JSON object is embedded in the observation payload; it is never base64
/// encoded or rebuilt from a typed DTO.
nonisolated struct FitMatchRetailerAPIResponseCapture: Equatable, Sendable {
    let requestURL: String
    let httpStatus: Int
    let collectedAt: String
    let body: Data

    init(
        requestURL: URL,
        httpStatus: Int,
        collectedAt: Date = Date(),
        body: Data
    ) {
        self.requestURL = requestURL.absoluteString
        self.httpStatus = httpStatus
        self.collectedAt = Self.timestamp(from: collectedAt)
        self.body = body
    }

    var jsonObject: FitMatchJSONValue? {
        guard let value = try? JSONDecoder().decode(FitMatchJSONValue.self, from: body),
              case .object = value else {
            return nil
        }
        return value
    }

    var requestMetadata: FitMatchJSONValue {
        .object([
            "url": .string(requestURL),
            "http_status": .number(Double(httpStatus)),
            "collected_at": .string(collectedAt)
        ])
    }

    private static func timestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

nonisolated struct FitMatchRetailerAPIResponseError: Error, Sendable {
    let capture: FitMatchRetailerAPIResponseCapture
    let reason: String
}

/// Typed transport-only envelope for `structured_facts.retailer_api`.
/// Existing `[String: String]` facts stay unchanged everywhere else.
nonisolated struct FitMatchRetailerAPIEvidence: Equatable, Sendable {
    static let v1Contract = "fitmatch-retailer-api-v1"
    static let zaraParentVariantContract = "fitmatch-retailer-api-v2"
    static let zaraParentVariantIdentityScheme =
        "provider_parent_with_selected_variant"

    let contractVersion: String
    let sourceCode: String
    let sourceProductKey: String
    let identityScheme: String?
    let selectedVariantKey: String?
    let details: FitMatchRetailerAPIResponseCapture
    let measurements: FitMatchRetailerAPIResponseCapture?

    var jsonValue: FitMatchJSONValue? {
        guard let detailsObject = details.jsonObject else { return nil }
        var requests: [String: FitMatchJSONValue] = [
            "details": details.requestMetadata
        ]
        var object: [String: FitMatchJSONValue] = [
            "contract_version": .string(contractVersion),
            "source_code": .string(sourceCode),
            "source_product_key": .string(sourceProductKey),
            "requests": .object(requests),
            "details": detailsObject
        ]
        if let measurements,
           let measurementsObject = measurements.jsonObject {
            requests["measurements"] = measurements.requestMetadata
            object["requests"] = .object(requests)
            object["measurements"] = measurementsObject
        }
        if let identityScheme {
            object["identity_scheme"] = .string(identityScheme)
        }
        if let selectedVariantKey {
            object["selected_variant_key"] = .string(selectedVariantKey)
        }
        return .object(object)
    }
}

extension ParsedProductInfo {
    func withRetailerAPIEvidence(
        _ evidence: FitMatchRetailerAPIEvidence?
    ) -> ParsedProductInfo {
        var copy = self
        copy.retailerAPIEvidence = evidence
        return copy
    }
}
