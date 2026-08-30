import Foundation
import Testing
@testable import FitMatch

struct FitMatchVNextContractTests {
    @Test func runtimeDTOSeparatesGarmentAndAllLengthAxes() throws {
        let productID = UUID()
        let variantID = UUID()
        let sizeID = UUID()
        let runtime: VNextProductRuntimeDTO = try decode(
            """
            {
              "found":true,
              "product":{
                "id":"\(productID)","source_code":"uniqlo",
                "source_product_key":"E500010","product_name":"테스트 팬츠",
                "brand_name":"UNIQLO","canonical_url":null,"image_url":null,
                "classification_status":"CONFIRMED","product_structure_code":"SINGLE",
                "audience_code":"UNISEX","category_code":"bottoms",
                "garment_type_code":"pants","comparison_policy_code":"pants",
                "sleeve_length_code":null,"lower_length_code":"ANKLE",
                "body_length_code":null,"resolver_version":"vnext-v1",
                "input_fingerprint":"input-v1","latest_ingestion_fingerprint":"ingest-v1"
              },
              "readiness":{"status":"READY","reason":null,
                "ready_size_count":1,"policy_metric_count":2},
              "variants":[{
                "id":"\(variantID)","source_variant_key":"09",
                "variant_label":"BLACK","color_name":"BLACK",
                "sizes":[{
                  "id":"\(sizeID)","source_size_key":"M","size_label":"M",
                  "availability":{"status":"AVAILABLE","observed_at":"2026-08-29T00:00:00Z",
                    "valid_until":"2026-08-30T00:00:00Z","evidence_fingerprint":"stock-v1"},
                  "canonical_measurements":{"semantic_conflict_count":0,"measurements":[{
                    "fitmatch_measurement_code":"waist_width_edge_to_edge",
                    "value":39,"unit_code":"CM","basis_code":"WIDTH",
                    "source_measurement_code":"waist"
                  }]}
                }]
              }]
            }
            """
        )

        #expect(runtime.product?.garmentTypeCode == "pants")
        #expect(runtime.product?.sleeveLengthCode == nil)
        #expect(runtime.product?.lowerLengthCode == "ANKLE")
        #expect(runtime.product?.bodyLengthCode == nil)
        #expect(runtime.variants.first?.id == variantID)
        #expect(runtime.variants.first?.sizes.first?.id == sizeID)
        #expect(runtime.variants.first?.sizes.first?.availability.status == "AVAILABLE")
    }

    @Test func observationSizePreservesRetailerAvailabilityEvidence() throws {
        let size = FitMatchProductObservationSize(
            sizeIdentity: "004",
            sizeLabel: "M",
            normalizedSizeLabel: "M",
            displayOrder: 0,
            stockStatus: "AVAILABLE",
            availabilityObservedAt: "2026-08-29T00:00:00Z",
            availabilityValidUntil: "2026-08-30T00:00:00Z",
            availabilityEvidence: ["retailer_stock": "in_stock"],
            measurements: []
        )
        let data = try JSONEncoder().encode(size)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["stock_status"] as? String == "AVAILABLE")
        #expect(json["observed_at"] as? String == "2026-08-29T00:00:00Z")
        #expect(json["valid_until"] as? String == "2026-08-30T00:00:00Z")
        #expect(json["availability_observed_at"] == nil)
        #expect(json["availability_valid_until"] == nil)
    }

    @Test func engineScoresOnlyExactAuthorizedCandidateSetAndRanksDeterministically() throws {
        let fixture = ComparisonBeginFixture()
        let begin: VNextBeginComparisonDTO = try decode(fixture.json())
        let result = try VNextComparisonEngineAdapter().analyze(begin)

        #expect(result.comparisonID == fixture.comparisonID)
        #expect(result.analyses.map(\.productSizeID) == [fixture.sizeA, fixture.sizeB])
        #expect(result.analyses.map(\.rank) == [1, 2])
        #expect(result.recommended.productSizeID == fixture.sizeA)
        #expect(result.completionPayload.candidateSizeRanking.count == 2)
        #expect(Set(result.completionPayload.metricEvidence.map(\.productSizeID))
            == Set([fixture.sizeA, fixture.sizeB]))
    }

    @Test func engineRejectsSnapshotCandidateSetMismatchBeforeScoring() throws {
        let fixture = ComparisonBeginFixture()
        let begin: VNextBeginComparisonDTO = try decode(
            fixture.json(topLevelAuthorizedIDs: [fixture.sizeA])
        )

        #expect(throws: VNextComparisonEngineAdapterError.candidateSetMismatch) {
            try VNextComparisonEngineAdapter().analyze(begin)
        }
    }

    @Test func engineRejectsBlockedAuthorizationBeforeScoring() throws {
        let fixture = ComparisonBeginFixture()
        let begin: VNextBeginComparisonDTO = try decode(fixture.json(allowed: false))

        #expect(throws: VNextComparisonEngineAdapterError.authorizationDenied("blocked")) {
            try VNextComparisonEngineAdapter().analyze(begin)
        }
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

private struct ComparisonBeginFixture {
    let comparisonID = UUID()
    let productID = UUID()
    let variantID = UUID()
    let sizeA = UUID()
    let sizeB = UUID()

    func json(
        topLevelAuthorizedIDs: [UUID]? = nil,
        allowed: Bool = true
    ) -> String {
        let ids = topLevelAuthorizedIDs ?? [sizeA, sizeB]
        let encodedIDs = ids.map { "\"\($0)\"" }.joined(separator: ",")
        let reason = allowed ? "null" : "\"blocked\""
        return """
        {
          "comparison_id":"\(comparisonID)","created":true,"idempotent":false,
          "result_status":"PENDING",
          "authorization":{
            "decision":"AUTOMATIC","allowed":\(allowed),"mode":"AUTOMATIC",
            "reason":\(reason),"excluded_measurement_codes":[],
            "required_measurement_codes":["chest_width_pit_to_pit"],
            "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
            "policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1"
          },
          "authorized_candidate_product_size_ids":[\(encodedIDs)],
          "candidate_authority_fingerprint":"candidate-v1",
          "snapshot":{
            "snapshot_schema_version":3,
            "reference_snapshot":{},"authority_snapshot":{},"input_snapshot":{},
            "excluded_measurement_codes":[],
            "policy_snapshot":{
              "policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1",
              "metrics":[{
                "metric_mode":"CANONICAL","fitmatch_measurement_code":"chest_width_pit_to_pit",
                "weight":1,"requirement_mode":"REQUIRED_ANY","priority":1,"is_active":true
              }]
            },
            "authorization_snapshot":{
              "decision":"AUTOMATIC","allowed":\(allowed),"mode":"AUTOMATIC",
              "reason":\(reason),"excluded_measurement_codes":[],
              "required_measurement_codes":["chest_width_pit_to_pit"],
              "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
              "policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1"
            },
            "target_snapshot":{
              "product_id":"\(productID)","variant_id":"\(variantID)",
              "authorized_candidate_product_size_ids":["\(sizeA)","\(sizeB)"],
              "candidate_authority_fingerprint":"candidate-v1",
              "classification_status":"CONFIRMED","garment_type_code":"tshirt",
              "sleeve_length_code":"short_sleeve","lower_length_code":null,
              "body_length_code":null,
              "candidates":[
                \(candidate(id: sizeA, label: "M", target: 51, difference: 1, allowed: allowed)),
                \(candidate(id: sizeB, label: "L", target: 53, difference: 3, allowed: allowed))
              ]
            }
          }
        }
        """
    }

    private func candidate(
        id: UUID,
        label: String,
        target: Int,
        difference: Int,
        allowed: Bool
    ) -> String {
        let reason = allowed ? "null" : "\"blocked\""
        return """
        {
          "product_size_id":"\(id)","size_label":"\(label)",
          "availability":{"status":"AVAILABLE","observed_at":"2026-08-29T00:00:00Z",
            "valid_until":"2026-08-30T00:00:00Z","evidence_fingerprint":"stock-\(label)"},
          "comparison_measurements":[{
            "measurement_code":"chest_width_pit_to_pit","reference_value":50,
            "target_value":\(target),"difference":\(difference),
            "absolute_difference":\(difference),"unit_code":"CM","basis_code":"WIDTH",
            "weight":1,"requirement_mode":"REQUIRED_ANY","priority":1
          }],
          "authorization":{
            "decision":"AUTOMATIC","allowed":\(allowed),"mode":"AUTOMATIC",
            "reason":\(reason),"excluded_measurement_codes":[],
            "required_measurement_codes":["chest_width_pit_to_pit"],
            "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
            "policy_code":"tshirt","policy_version":"v1","policy_checksum":"policy-v1"
          }
        }
        """
    }
}
