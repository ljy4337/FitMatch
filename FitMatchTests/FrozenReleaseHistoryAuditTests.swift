import Foundation
import SwiftData
import Testing
@testable import FitMatch

/// Existing completed test data, captured read-only. No retailer/DB network calls.
@MainActor
struct FrozenReleaseHistoryAuditTests {
    private func rows() throws -> [VNextComparisonHistoryDTO] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ReleaseAuditPreviouslyCompleted20260930.json")
        return try JSONDecoder().decode([VNextComparisonHistoryDTO].self, from: Data(contentsOf: file))
    }

    @Test(arguments: ["musinsa", "uniqlo", "zara"])
    func existingCompletedResultReplays(source: String) throws {
        let row = try #require(rows().first { $0.targetSourceCode == source })
        let analysis = try VNextComparisonEngineAdapter().analyze(#require(row.snapshotBegin))
        #expect(analysis.recommended.productSizeID == row.recommendedProductSizeID)
        #expect(analysis.completionPayload.score == row.fitScore)
    }

    @Test(arguments: ["musinsa", "uniqlo", "zara"])
    func existingCompletedHistoryHydratesWithoutLosingMeasurements(source: String) throws {
        let row = try #require(rows().first { $0.targetSourceCode == source })
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let context = ModelContext(container)
        _ = try VNextHistoryCacheHydrator().hydrateCompleted(
            [row], existingHistories: [], existingProducts: [], existingClosetItems: [], modelContext: context
        )
        let history = try #require(context.fetch(FetchDescriptor<RecommendationHistory>()).first)
        let candidate = try #require(row.targetSnapshot?.candidates.first {
            $0.productSizeID == row.recommendedProductSizeID
        })
        #expect(history.recommendedSize.measurementRecords.count == candidate.comparisonMeasurements.count)
        for metric in candidate.comparisonMeasurements {
            let record = try #require(history.recommendedSize.measurementRecords.first {
                $0.measurementCodeRawValue == metric.measurementCode
            })
            #expect(record.value == metric.targetValue)
            #expect(record.methodSource == "fitmatch_vnext_snapshot")
        }
        #expect(Double(history.recommendationScore) == row.fitScore)
        #expect(history.recommendedSize.name == row.recommendedSizeLabel)
        // The completed canonical snapshot is not a new retailer observation.
        #expect(history.product.fitMatchStoredRetailerFactsForRecompare() == nil)


    }
    @Test
    func rejectedReplacementKeepsExistingHistory() throws {
        let row = try #require(rows().first)
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let context = ModelContext(container)
        let hydrator = VNextHistoryCacheHydrator()
        _ = try hydrator.hydrateCompleted([row], existingHistories: [], existingProducts: [],
                                         existingClosetItems: [], modelContext: context)
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ReleaseAuditPreviouslyCompleted20260930.json")
        var object = try #require((JSONSerialization.jsonObject(with: Data(contentsOf: file))
                                  as? [[String: Any]])?.first)
        object["client_comparison_id"] = UUID().uuidString
        var authority = try #require(object["authority_snapshot"] as? [String: Any])
        var effective = try #require(authority["effective_classification_at_begin"] as? [String: Any])
        effective["state"] = "REVIEW_REQUIRED"
        authority["effective_classification_at_begin"] = effective
        object["authority_snapshot"] = authority
        let invalid = try JSONDecoder().decode(VNextComparisonHistoryDTO.self,
                        from: JSONSerialization.data(withJSONObject: object))
        #expect(throws: VNextHistoryCacheHydrationError.self) {
            try hydrator.hydrateCompleted([invalid], existingHistories: [], existingProducts: [],
                                         existingClosetItems: [], modelContext: context)
        }
        #expect(try context.fetch(FetchDescriptor<RecommendationHistory>()).map(\.id) == [row.clientComparisonID])
        #expect(!context.hasChanges)
    }

    @Test(arguments: ["musinsa", "uniqlo", "zara"])
    func restoredHistorySurvivesStoreReopen(source: String) throws {
        let row = try #require(rows().first { $0.targetSourceCode == source })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.store")
        try writeHistory(row, to: url)
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        let history = try #require(context.fetch(FetchDescriptor<RecommendationHistory>()).first)
        #expect(history.id == row.clientComparisonID)
        #expect(Double(history.recommendationScore) == row.fitScore)
        let candidate = try #require(row.targetSnapshot?.candidates.first {
            $0.productSizeID == row.recommendedProductSizeID
        })
        #expect(history.recommendedSize.measurementRecords.count == candidate.comparisonMeasurements.count)
    }

    private func writeHistory(_ row: VNextComparisonHistoryDTO, to url: URL) throws {
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        _ = try VNextHistoryCacheHydrator().hydrateCompleted([row], existingHistories: [],
                existingProducts: [], existingClosetItems: [], modelContext: context)
    }

    @Test
    func existingUserSelectedGroupHistoryRestoresAsSessionAuthority() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ReleaseAuditSessionHistory20260930.json")
        let row = try #require(JSONDecoder().decode([VNextComparisonHistoryDTO].self,
                                                   from: Data(contentsOf: url)).first)
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let context = ModelContext(container)
        _ = try VNextHistoryCacheHydrator().hydrateCompleted([row], existingHistories: [],
                existingProducts: [], existingClosetItems: [], modelContext: context)
        let history = try #require(context.fetch(FetchDescriptor<RecommendationHistory>()).first)
        #expect(history.product.classificationAuthorityProvenance == .serverSessionComparison)
        #expect(Double(history.recommendationScore) == row.fitScore)
        #expect(history.recommendedSize.name == row.recommendedSizeLabel)
        #expect(history.product.fitMatchStoredRetailerFactsForRecompare() == nil)
    }

    @Test(arguments: ["state", "effective_source", "comparison_group_code", "effective_authority_fingerprint"])
    func sessionHistoryRejectsConflictingAuthority(field: String) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ReleaseAuditSessionHistory20260930.json")
        var object = try #require((JSONSerialization.jsonObject(with: Data(contentsOf: url))
                                  as? [[String: Any]])?.first)
        var authority = try #require(object["authority_snapshot"] as? [String: Any])
        var effective = try #require(authority["effective_classification_at_begin"] as? [String: Any])
        effective[field] = "CONFLICT"
        authority["effective_classification_at_begin"] = effective
        object["authority_snapshot"] = authority
        let row = try JSONDecoder().decode(VNextComparisonHistoryDTO.self,
                        from: JSONSerialization.data(withJSONObject: object))
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let context = ModelContext(container)
        #expect(throws: VNextHistoryCacheHydrationError.self) {
            try VNextHistoryCacheHydrator().hydrateCompleted([row], existingHistories: [],
                    existingProducts: [], existingClosetItems: [], modelContext: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<RecommendationHistory>()) == 0)
        #expect(!context.hasChanges)
    }

}
