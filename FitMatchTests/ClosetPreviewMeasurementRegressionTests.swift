import Foundation
import Testing
import SwiftData
@testable import FitMatch

@MainActor
struct ClosetPreviewMeasurementRegressionTests {
    // Regression: the production adapter previously discarded all canonical
    // records whenever even one immutable raw snapshot was present.
    @Test(arguments: ["uniqlo", "musinsa", "zara"])
    func rawSnapshotsDoNotReplaceComparisonEvidence(source: String) throws {
        let json = """
        {"id":"\(UUID())","client_item_id":"\(UUID())","product_id":"\(UUID())",
         "item_name":"Fixture","size_label":"XL","audience_code":"UNISEX",
         "category_code":"tops","garment_type_code":"shirt","classification_source":"PRODUCT",
         "source_code":"\(source)","is_reference":false,
         "created_at":"2026-09-22T00:00:00Z","updated_at":"2026-09-22T00:00:00Z",
         "measurements":[{"fitmatch_measurement_code":"chest_width","value":59,"unit_code":"cm","value_source":"PRODUCT"}],
         "source_measurements":[{"raw_measurement_key":"raw-1","source_code":"\(source)",
          "parser_code":"fixture","raw_code":"raw-chest","raw_label":"공식 원본","raw_value":59,
          "raw_value_text":"59.0","raw_unit_code":"cm","resolution_status":"RESOLVED"},
          {"raw_measurement_key":"raw-2","source_code":"\(source)","parser_code":"fixture",
          "raw_code":"future-field","raw_label":"새 항목","raw_value":7,"raw_value_text":"7",
          "raw_unit_code":"cm","resolution_status":"UNMAPPED"}]}
        """
        let dto = try JSONDecoder().decode(VNextClosetItemDTO.self, from: Data(json.utf8))
        let mapped = FitMatchSupabaseDomainClient.mapClosetItem(dto)
        #expect(mapped.measurements["chest_width"] == 59)
        #expect(mapped.measurementRecords.filter { $0.semanticStatus == "mapped" }.count == 1)
        let raw = mapped.measurementRecords.filter { $0.methodSource != "fitmatch_vnext_snapshot" }
        #expect(raw.count == 2)
        #expect(raw.map(\.rawValueText) == ["59.0", "7"])
        #expect(raw.allSatisfy { $0.semanticStatus == "unknown_definition" })

        // Exercise the real persisted Closet hydration owner, then the same
        // local engine used by the candidate preview. No mock mapper.
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let context = ModelContext(container)
        let coordinator = FitMatchClosetSyncCoordinator()
        let empty = GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0)
        let draft = UserFit(brandName: "Fixture", productName: "Fixture", category: .top,
            sizeName: "XL", measurements: empty, fitMemo: "", satisfaction: 3)
        let request = FitMatchUpsertClosetItemRequest(clientItemID: mapped.clientItemID,
            item: coordinator.payload(for: draft), productID: mapped.productID,
            productVariantID: mapped.variantID, productSizeID: mapped.productSizeID, override: nil)
        let restored = try coordinator.projectAuthoritativeRegistration(mapped, expected: request,
            acceptedClosetItemID: mapped.closetItemID, modelContext: context)
        #expect(restored.measurementRecords.filter(\.isComparable).count == 1)
        #expect(MeasurementResolver.sourceDisplayRows(records: restored.measurementRecords).count == 2)
        let size = ProductSize(name: "XL", measurements: empty)
        size.measurementRecords = [record(code: .chestWidthPitToPit,
            source: "fitmatch_vnext_snapshot", label: "chest_width")]
        let result = MeasurementComparisonEngine().compare(productSize: size,
            referenceItem: restored, productCategory: .top, productDetailCategory: .shirt)
        #expect(result.comparedItems.count == 1)
        #expect(result.comparedItems.first?.absoluteDifference == 0)
        #expect(restored.measurementRecords.filter { $0.measurementCode == .unknown }.count == 2)
        let group = try #require(FitMatchComparisonGroup(rawValue: "A"))
        restored.comparisonGroup = group
        let product = Product(name: "Target", category: .top, sizes: [size])
        let summary = try #require(RecommendationService().makeClosetComparisonBatchSummary(
            product: product, productDetailCategory: .shirt, comparisonGroup: group,
            candidates: [restored]).items.first)
        // Preview's old two-metric threshold is not a server rejection.
        #expect(summary.similarityPercent == nil)
        #expect(summary.reason?.contains("최소") == false)
        #expect(summary.reason?.contains("선택") == true)
    }

    @Test func rawPresentationDoesNotDuplicateCanonicalProjection() {
        let canonical = record(code: .chestWidthPitToPit, source: "fitmatch_vnext_snapshot", label: "chest_width")
        let raw = record(code: .unknown, source: "uniqlo_size_chart", label: "원본 가슴")
        let rows = MeasurementResolver.sourceDisplayRows(records: [raw, canonical])
        #expect(rows.count == 1)
        #expect(rows.first?.title == "원본 가슴")
        // A pre-raw-snapshot Closet row must remain readable.
        #expect(MeasurementResolver.sourceDisplayRows(records: [canonical]).count == 1)
        #expect(MeasurementResolver.sourceDisplayRows(records: [raw, canonical], includeAllRecords: true).count == 1)
    }

    private func record(code: MeasurementCode, source: String, label: String) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(value: 59, measurementCode: code, displayKind: .chest,
            methodSource: source, inputSource: .importedSizeChart, mappingVersion: "fixture",
            rawLabel: label, evidenceLevel: .officialText,
            semanticStatus: code == .unknown ? .unknownDefinition : .mapped)
    }
}
