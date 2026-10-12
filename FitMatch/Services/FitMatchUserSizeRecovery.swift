import Foundation

/// A user transcription. It is never a retailer product observation.
nonisolated struct FitMatchUserSizeRecoveryRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let ownerID: UUID
    let productID: UUID
    let variantID: UUID
    let officialSizeID: UUID?
    let sourceObservationID: UUID
    let inputSource: String
    let sizeLabel: String
    let measurements: [Measurement]
    let originalRows: [OriginalRow]

    struct Measurement: Codable, Equatable, Sendable {
        let fitmatchMeasurementCode: String
        let value: Double
        let unitCode: String
        let basisCode: String?
        let rawLabel: String
        let rawValueText: String
        enum CodingKeys: String, CodingKey {
            case fitmatchMeasurementCode = "fitmatch_measurement_code"
            case value, unitCode = "unit_code", basisCode = "basis_code"
            case rawLabel = "raw_label", rawValueText = "raw_value_text"
        }
    }

    struct OriginalRow: Codable, Equatable, Sendable {
        let rawCode: String?
        let rawLabel: String
        let rawValueText: String?
        let value: Double
        let unitCode: String
        enum CodingKeys: String, CodingKey {
            case rawCode = "raw_code", rawLabel = "raw_label"
            case rawValueText = "raw_value_text", value, unitCode = "unit_code"
        }
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", ownerID = "owner_id"
        case productID = "product_id", variantID = "variant_id"
        case officialSizeID = "official_size_id"
        case sourceObservationID = "source_observation_id"
        case inputSource = "input_source", sizeLabel = "size_label"
        case measurements, originalRows = "original_rows"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestID, forKey: .requestID)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(productID, forKey: .productID)
        try c.encode(variantID, forKey: .variantID)
        try c.encode(officialSizeID, forKey: .officialSizeID)
        try c.encode(sourceObservationID, forKey: .sourceObservationID)
        try c.encode(inputSource, forKey: .inputSource)
        try c.encode(sizeLabel, forKey: .sizeLabel)
        try c.encode(measurements, forKey: .measurements)
        try c.encode(originalRows, forKey: .originalRows)
    }
}

nonisolated struct FitMatchUserSizeRecoveryReceipt: Decodable, Equatable, Sendable {
    let state: String
    let requestID: UUID
    let ownerID: UUID
    let productID: UUID
    let variantID: UUID
    let officialSizeID: UUID?
    let sizeID: UUID
    let identityKind: String
    let requestPayload: FitMatchUserSizeRecoveryRequest
    enum CodingKeys: String, CodingKey {
        case state, requestID = "request_id", ownerID = "owner_id"
        case productID = "product_id", variantID = "variant_id"
        case officialSizeID = "official_size_id", sizeID = "size_id"
        case identityKind = "identity_kind", requestPayload = "request_payload"
    }

    func validate(for request: FitMatchUserSizeRecoveryRequest) throws {
        guard state == "saved", requestPayload == request,
              requestID == request.requestID, ownerID == request.ownerID,
              productID == request.productID, variantID == request.variantID,
              officialSizeID == request.officialSizeID,
              identityKind == (officialSizeID == nil ? "USER_RECOVERY" : "RETAILER_SIZE"),
              officialSizeID == nil || sizeID == officialSizeID else {
            throw FitMatchUserSizeRecoveryError.invalidReceipt
        }
    }
}

nonisolated enum FitMatchUserSizeRecoveryError: LocalizedError {
    case unavailable, invalidReceipt, invalidMeasurements, pendingInputChanged
    var errorDescription: String? {
        switch self {
        case .invalidMeasurements: "입력한 실측값과 측정 기준을 다시 확인해 주세요."
        case .pendingInputChanged: "저장 결과를 확인 중인 입력이 있어요. 이전 입력으로 다시 시도해 주세요."
        case .unavailable, .invalidReceipt: "보완한 사이즈 정보를 서버에서 확인하지 못했어요. 입력을 유지한 채 다시 시도해 주세요."
        }
    }
}
