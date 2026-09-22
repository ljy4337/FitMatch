import Foundation
import Testing
@testable import FitMatch

@MainActor
struct FitMatchRetailerAPIEvidenceTests {
    @Test func reusesCaptureProjectionWithoutChangingObservationEvidence() throws {
        let detailsURL = try #require(URL(string: "https://api.example.com/details"))
        let measurementsURL = try #require(URL(string: "https://api.example.com/measurements"))
        let detailsBody = Data(#"{"product":{"code":"ABC","raw_label":"공식 원문"}}"#.utf8)
        let measurementsBody = Data(#"{"rows":[{"code":"arm-width","value":"18","unit":"cm"}]}"#.utf8)
        let collectedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let details = FitMatchRetailerAPIResponseCapture(
            requestURL: detailsURL,
            httpStatus: 200,
            collectedAt: collectedAt,
            body: detailsBody
        )
        let measurements = FitMatchRetailerAPIResponseCapture(
            requestURL: measurementsURL,
            httpStatus: 200,
            collectedAt: collectedAt,
            body: measurementsBody
        )
        let evidence = FitMatchRetailerAPIEvidence(
            contractVersion: FitMatchRetailerAPIEvidence.v1Contract,
            sourceCode: "musinsa",
            sourceProductKey: "ABC",
            identityScheme: nil,
            selectedVariantKey: nil,
            details: details,
            measurements: measurements
        )

        let first = try #require(evidence.jsonValue)
        let second = try #require(evidence.jsonValue)
        #expect(first == second)
        #expect(details.body == detailsBody)
        #expect(measurements.body == measurementsBody)

        let encoded = try JSONEncoder().encode(first)
        let root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decodedDetails = try #require(root["details"] as? [String: Any])
        let product = try #require(decodedDetails["product"] as? [String: Any])
        #expect(product["code"] as? String == "ABC")
        #expect(product["raw_label"] as? String == "공식 원문")
        let decodedMeasurements = try #require(root["measurements"] as? [String: Any])
        let rows = try #require(decodedMeasurements["rows"] as? [[String: Any]])
        #expect(rows[0]["code"] as? String == "arm-width")
        #expect(rows[0]["value"] as? String == "18")
        #expect(rows[0]["unit"] as? String == "cm")
        let requests = try #require(root["requests"] as? [String: Any])
        let detailRequest = try #require(requests["details"] as? [String: Any])
        #expect(detailRequest["collected_at"] as? String == details.collectedAt)
    }

    @Test func invalidOrNonObjectBodiesKeepExistingOmissionBehavior() throws {
        let url = try #require(URL(string: "https://api.example.com/bad"))
        let malformed = FitMatchRetailerAPIResponseCapture(
            requestURL: url,
            httpStatus: 200,
            body: Data("{not-json".utf8)
        )
        let array = FitMatchRetailerAPIResponseCapture(
            requestURL: url,
            httpStatus: 200,
            body: Data("[]".utf8)
        )

        #expect(malformed.jsonObject == nil)
        #expect(array.jsonObject == nil)
        #expect(
            FitMatchRetailerAPIEvidence(
                contractVersion: FitMatchRetailerAPIEvidence.v1Contract,
                sourceCode: "zara",
                sourceProductKey: "bad",
                identityScheme: nil,
                selectedVariantKey: nil,
                details: malformed,
                measurements: nil
            ).jsonValue == nil
        )
    }

    @Test func dataOnlyCapturePreservesExactBytesWithoutCreatingAnUnusedProjection() throws {
        let url = try #require(URL(string: "https://api.example.com/availability"))
        let body = Data(#"{"status":"ok","raw_code":"unmodified"}"#.utf8)

        let capture = FitMatchRetailerAPIResponseCapture(
            requestURL: url,
            httpStatus: 200,
            collectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: body,
            precomputesJSONObject: false
        )

        #expect(capture.body == body)
        #expect(capture.jsonObject == nil)
    }
}
