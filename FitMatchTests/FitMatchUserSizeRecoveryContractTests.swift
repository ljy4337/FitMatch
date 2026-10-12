import Foundation
import Testing
@testable import FitMatch

/// Offline client contract evidence only; no SQL deployment or server write.
struct FitMatchUserSizeRecoveryContractTests {
    @Test func receiptRequiresTheExactPersistedRequestAndEveryIdentity() throws {
        let request = UserSizeRecoveryContractFixture.request()
        try UserSizeRecoveryContractFixture.receipt(for: request).validate(for: request)
        let wrongFields: [(String, Any)] = [
            ("state", "pending"), ("request_id", UUID().uuidString),
            ("owner_id", UUID().uuidString), ("product_id", UUID().uuidString),
            ("variant_id", UUID().uuidString), ("official_size_id", NSNull()),
            ("size_id", UUID().uuidString), ("identity_kind", "USER_RECOVERY")
        ]
        for (field, value) in wrongFields {
            let receipt = try UserSizeRecoveryContractFixture.receipt(for: request, replacing: [field: value])
            #expect(throws: FitMatchUserSizeRecoveryError.self) {
                try receipt.validate(for: request)
            }
        }
    }

    @Test func receiptRejectsChangedValuesRawRowsAndObservation() throws {
        let request = UserSizeRecoveryContractFixture.request()
        let encoded = try JSONEncoder().encode(request)
        let original = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for field in ["source_observation_id", "input_source", "size_label", "measurements", "original_rows"] {
            var payload = original
            switch field {
            case "source_observation_id": payload[field] = UUID().uuidString
            case "input_source": payload[field] = "RETAILER_API"
            case "size_label": payload[field] = "L"
            case "measurements":
                var rows = try #require(payload[field] as? [[String: Any]])
                rows[0]["value"] = 99.0
                payload[field] = rows
            default: payload[field] = []
            }
            let receipt = try UserSizeRecoveryContractFixture.receipt(for: request, replacing: ["request_payload": payload])
            #expect(throws: FitMatchUserSizeRecoveryError.self) {
                try receipt.validate(for: request)
            }
        }
    }

    @Test func customRecoveryReceiptRetainsUserIdentityAndNullOfficialSize() throws {
        let request = UserSizeRecoveryContractFixture.request(officialSizeID: nil)
        let receipt = try UserSizeRecoveryContractFixture.receipt(for: request)
        try receipt.validate(for: request)
        #expect(receipt.identityKind == "USER_RECOVERY")
        #expect(receipt.officialSizeID == nil)
        #expect(receipt.sizeID == UserSizeRecoveryContractFixture.recoveredSizeID)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(object["official_size_id"] is NSNull)
        #expect(object["source_observation_id"] as? String == request.sourceObservationID.uuidString)
        #expect(object["input_source"] as? String == "USER_MANUAL")
    }
}

enum UserSizeRecoveryContractFixture {
    static let ownerID = UUID(uuidString: "71000000-0000-4000-8000-000000000001")!
    static let recoveredSizeID = UUID(uuidString: "71000000-0000-4000-8000-000000000002")!
    static let officialSizeID = UUID(uuidString: "71000000-0000-4000-8000-000000000003")!

    static func request(officialSizeID: UUID? = officialSizeID) -> FitMatchUserSizeRecoveryRequest {
        .init(
            requestID: UUID(), ownerID: ownerID, productID: UUID(), variantID: UUID(),
            officialSizeID: officialSizeID, sourceObservationID: UUID(), inputSource: "USER_MANUAL",
            sizeLabel: "M",
            measurements: [
                .init(fitmatchMeasurementCode: "chest_width", value: 51, unitCode: "cm", basisCode: "WIDTH", rawLabel: "가슴", rawValueText: "51"),
                .init(fitmatchMeasurementCode: "shoulder_width", value: 48, unitCode: "cm", basisCode: "WIDTH", rawLabel: "어깨", rawValueText: "48")
            ],
            originalRows: [.init(rawCode: "user-chest", rawLabel: "가슴", rawValueText: "51", value: 51, unitCode: "cm")]
        )
    }

    static func receipt(
        for request: FitMatchUserSizeRecoveryRequest,
        replacing replacements: [String: Any] = [:]
    ) throws -> FitMatchUserSizeRecoveryReceipt {
        var object: [String: Any] = [
            "state": "saved", "request_id": request.requestID.uuidString,
            "owner_id": request.ownerID.uuidString, "product_id": request.productID.uuidString,
            "variant_id": request.variantID.uuidString,
            "official_size_id": request.officialSizeID?.uuidString as Any? ?? NSNull(),
            "size_id": (request.officialSizeID ?? recoveredSizeID).uuidString,
            "identity_kind": request.officialSizeID == nil ? "USER_RECOVERY" : "RETAILER_SIZE",
            "request_payload": try JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
        ]
        replacements.forEach { object[$0.key] = $0.value }
        return try JSONDecoder().decode(FitMatchUserSizeRecoveryReceipt.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
