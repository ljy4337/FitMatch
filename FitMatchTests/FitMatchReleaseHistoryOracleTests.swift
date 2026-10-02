import Foundation
import SwiftData
import Testing
@testable import FitMatch

/// Literal persisted History oracle; no expected value is computed by the engine.
/// Synthetic schema-4 snapshot, local disk only; no authentication or remote DB.
@MainActor
struct FitMatchReleaseHistoryOracleTests {
    @Test func literalCompletedHistoryKeepsNumbersAndIdentityAfterDiskReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatch-History-Oracle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(FitMatchSchemaV1.models)
        let storeURL = directory.appendingPathComponent("history.store")
        let activeID = UUID()
        let row = try literalCompletedRow(targetProductID: UUID(),
            referenceClientItemID: activeID, garment: "tshirt", revision: 1)
        let selectedID = try #require(row.recommendedProductSizeID)
        // One approved CM/WIDTH metric: ref50, target52, delta+2, score90,
        // reliability1, coverage1. These literals characterize current scoring;
        // they do not resolve the independent product-policy approval gap.
        #expect(row.fitScore == 90)
        #expect(row.resultEvidence?.coverage == 1)
        var savedEnvelope = ""
        do {
            let container = try ModelContainer(for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)])
            let context = ModelContext(container)
            let active = UserFit(id: activeID, brandName: "Oracle", productName: "Active Closet",
                category: .top, sizeName: "M",
                measurements: .init(shoulder: 48, chest: 50, totalLength: 70, sleeveLength: 60),
                fitMemo: "keep", satisfaction: 3)
            context.insert(active)
            try context.save()
            _ = try VNextHistoryCacheHydrator().hydrateCompleted([row], existingHistories: [],
                existingProducts: [], existingClosetItems: [active], modelContext: context)
            let history = try #require(context.fetch(FetchDescriptor<RecommendationHistory>()).first)
            try assertLiteralHistory(history, row: row, selectedID: selectedID, activeID: activeID)
            savedEnvelope = history.comparedMeasurementUsagesJSON
            // Editing the active item must not silently recalculate the frozen History.
            active.chest = 61
            try context.save()
            #expect(history.userFit.chest == 50)
            #expect(history.comparedMeasurementUsagesJSON == savedEnvelope)
        }
        let reopened = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)])
        let fresh = ModelContext(reopened)
        let histories = try fresh.fetch(FetchDescriptor<RecommendationHistory>())
        #expect(histories.count == 1)
        let history = try #require(histories.first)
        try assertLiteralHistory(history, row: row, selectedID: selectedID, activeID: activeID)
        #expect(history.comparedMeasurementUsagesJSON == savedEnvelope)
        let rows = try fresh.fetch(FetchDescriptor<UserFit>())
        let active = try #require(rows.first { $0.id == activeID })
        #expect(active.chest == 61)
        #expect(active.fitMemo == "keep")
        #expect(rows.count == 2) // Active Closet plus the immutable History reference projection.
    }

    private func assertLiteralHistory(_ history: RecommendationHistory,
        row: VNextComparisonHistoryDTO, selectedID: UUID, activeID: UUID) throws {
        #expect(history.id == row.clientComparisonID)
        #expect(history.referencesClosetItem(clientItemID: activeID))
        #expect(history.userFit.id != activeID)
        #expect(history.product.id == VNextHistoryProjectionIdentity.productID(comparisonID: row.clientComparisonID))
        #expect(history.recommendedSize.id == VNextHistoryProjectionIdentity.productSizeID(
            comparisonID: row.clientComparisonID, productSizeID: selectedID))
        #expect(history.userFit.chest == 50)
        #expect(history.recommendedSize.chest == 52)
        #expect(history.recommendationScore == 90)
        #expect(history.chestDifference == 2)
        #expect(history.totalDifference == 2)
        #expect(history.serverApprovedVNextReliability == 1)
        #expect(history.comparisonCoverage == 1)
    }

    private func literalCompletedRow(
        targetProductID: UUID,
        referenceClientItemID: UUID,
        garment: String,
        revision: Int,
        audience: String = "MEN"
    ) throws -> VNextComparisonHistoryDTO {
        let comparisonID = UUID()
        let clientComparisonID = UUID()
        let variantID = UUID()
        let sizeID = UUID()
        let createdAt = String(format: "2026-08-31T00:%02d:00Z", revision)
        let candidateFingerprint = "candidate-\(garment)-r\(revision)"
        let json = """
        {
          "id":"\(comparisonID)",
          "client_comparison_id":"\(clientComparisonID)",
          "reference_client_item_id":"\(referenceClientItemID)",
          "target_product_id":"\(targetProductID)",
          "target_variant_id":"\(variantID)",
          "target_product_name_snapshot":"개인 확정 상품 r\(revision)",
          "target_image_url_snapshot":null,
          "target_source_code_snapshot":"uniqlo",
          "target_source_product_key":"E450259",
          "target_canonical_url":"https://www.uniqlo.com/kr/ko/products/E450259",
          "target_category_code":"tops",
          "result_status":"COMPLETED",
          "recommended_product_size_id":"\(sizeID)",
          "recommended_size_label":"M",
          "fit_score":90,
          "reliability_level":1,
          "coverage_ratio":1,
          "engine_version":"fitmatch-ios-vnext-snapshot-v2",
          "result_evidence":{
            "recommended_product_size_id":"\(sizeID)",
            "score":90,"reliability":1,"coverage":1,
            "engine_version":"fitmatch-ios-vnext-snapshot-v2",
            "candidate_size_ranking":[{
              "product_size_id":"\(sizeID)","rank":1,"score":90
            }],
            "metric_evidence":[{
              "product_size_id":"\(sizeID)",
              "measurement_code":"chest_width_pit_to_pit",
              "reference_value":50,"target_value":52,"difference":2,
              "absolute_difference":2,"weight":1
            }]
          },
          "created_at":"\(createdAt)",
          "snapshot_schema_version":4,
          "excluded_measurement_codes":[],
          "reference_snapshot":{
            "source_code":"manual","item_name":"내 반팔 티셔츠","size_label":"M",
            "garment_type_code":"tshirt","audience_code":"\(audience)",
            "sleeve_length_code":"short_sleeve","lower_length_code":null,
            "body_length_code":null,"classification_source":"USER_EXPLICIT",
            "measurements":[{
              "fitmatch_measurement_code":"chest_width_pit_to_pit",
              "value":50,"unit_code":"CM","value_source":"USER"
            }]
          },
          "target_snapshot":{
            "product_id":"\(targetProductID)","variant_id":"\(variantID)",
            "authorized_candidate_product_size_ids":["\(sizeID)"],
            "candidate_authority_fingerprint":"candidate-authority-r\(revision)",
            "classification_status":"CONFIRMED",
            "garment_type_code":"\(garment)",
            "sleeve_length_code":"short_sleeve",
            "lower_length_code":null,"body_length_code":null,
            "candidates":[{
              "product_size_id":"\(sizeID)","size_label":"M",
              "availability":{
                "status":"AVAILABLE","observed_at":"2026-08-31T00:00:00Z",
                "valid_until":"2026-09-01T00:00:00Z",
                "evidence_fingerprint":"stock-r\(revision)"
              },
              "comparison_measurements":[{
                "measurement_code":"chest_width_pit_to_pit",
                "reference_value":50,"target_value":52,"difference":2,
                "absolute_difference":2,"unit_code":"CM","basis_code":"WIDTH",
                "weight":1,"requirement_mode":"REQUIRED_ANY","priority":1
              }],
              "authorization":{
                "decision":"AUTOMATIC","allowed":true,"mode":"AUTOMATIC",
                "excluded_measurement_codes":[],
                "required_measurement_codes":["chest_width_pit_to_pit"],
                "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
                "policy_code":"\(garment)","policy_version":"v1",
                "policy_checksum":"policy-v1"
              }
            }]
          },
          "authority_snapshot":{
            "global_classification_at_begin":{
              "status":"REVIEW_REQUIRED","garment_type_code":null
            },
            "personal_projection_at_begin":{
              "classification_source":"USER_EXPLICIT",
              "garment_type_code":"\(garment)","revision":\(revision),
              "selected_candidate_fingerprint":"\(candidateFingerprint)",
              "cleared_at":null
            },
            "effective_classification_at_begin":{
              "source":"USER_EXPLICIT","state":"PERSONAL_CONFIRMED",
              "category_code":"tops","garment_type_code":"\(garment)",
              "audience_code":"\(audience)","sleeve_length_code":"short_sleeve"
            }
          },
          "policy_snapshot":{
            "policy_code":"\(garment)","policy_version":"v1",
            "policy_checksum":"policy-v1",
            "metrics":[{
              "metric_mode":"CANONICAL",
              "fitmatch_measurement_code":"chest_width_pit_to_pit",
              "weight":1,"requirement_mode":"REQUIRED_ANY","priority":1,
              "is_active":true
            }]
          },
          "authorization_snapshot":{
            "decision":"AUTOMATIC","allowed":true,"mode":"AUTOMATIC",
            "excluded_measurement_codes":[],
            "required_measurement_codes":["chest_width_pit_to_pit"],
            "minimum_common":1,"common_measurement_count":1,"required_any_count":1,
            "policy_code":"\(garment)","policy_version":"v1",
            "policy_checksum":"policy-v1"
          },
          "input_snapshot":{
            "personal_override_revision":\(revision),
            "selected_candidate_fingerprint":"\(candidateFingerprint)"
          }
        }
        """
        return try JSONDecoder().decode(
            VNextComparisonHistoryDTO.self,
            from: Data(json.utf8)
        )
    }
}
