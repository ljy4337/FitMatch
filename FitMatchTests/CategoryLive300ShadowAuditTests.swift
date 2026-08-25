import Foundation
import XCTest
@testable import FitMatch

@MainActor
final class CategoryLive300ShadowAuditTests: XCTestCase {
    private struct Input: Decodable {
        let retailerCode: String
        let sourceProductID: String
        let productName: String
        let sourceCategoryPaths: [String]
        let sourceAppCategory: String?
        let sourceAppDetailCategory: String?
        let familyName: String?
        let subfamilyName: String?
        let fitmatchMajorCandidate: String?
        let productURL: String
        let officialListed: Bool

        enum CodingKeys: String, CodingKey {
            case retailerCode = "retailer_code"
            case sourceProductID = "source_product_id"
            case productName = "product_name"
            case sourceCategoryPaths = "source_category_paths"
            case sourceAppCategory = "source_app_category"
            case sourceAppDetailCategory = "source_app_detail_category"
            case familyName = "family_name"
            case subfamilyName = "subfamily_name"
            case fitmatchMajorCandidate = "fitmatch_major_candidate"
            case productURL = "product_url"
            case officialListed = "official_listed"
        }
    }

    private struct AuditRecord: Encodable {
        let source: String
        let productID: String
        let productName: String
        let sourcePath: String
        let providerCategory: String
        let providerDetail: String
        let categoryCode: String?
        let detailCode: String?
        let classificationValid: Bool
        let shadowStatus: String
        let strictComparisonEligible: Bool
        let conflictDimensions: [String]
        let sourceAuthority: String
        let productURL: String
    }

    func testCurrentClassifierAuditsLive300WithoutGoldPromotion() throws {
        let inputs = try loadInputs()
        XCTAssertEqual(inputs.count, 300)
        XCTAssertEqual(inputs.filter { $0.retailerCode == "MUSINSA" }.count, 100)
        XCTAssertEqual(inputs.filter { $0.retailerCode == "UNIQLO" }.count, 100)
        XCTAssertEqual(inputs.filter { $0.retailerCode == "ZARA" }.count, 100)
        XCTAssertTrue(inputs.allSatisfy(\.officialListed))

        var identities = Set<String>()
        var records: [AuditRecord] = []
        var statusCounts: [String: Int] = [:]
        var sourceStatusCounts: [String: [String: Int]] = [:]

        for input in inputs {
            let identity = "\(input.retailerCode):\(input.sourceProductID)"
            XCTAssertTrue(identities.insert(identity).inserted, "duplicate input \(identity)")

            let sourcePath = resolvedSourcePath(input)
            let depths = sourcePath
                .components(separatedBy: ">")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let provider = providerClassification(input, sourcePath: sourcePath, depths: depths)
            let classification = ParsedClosetClassification.resolve(
                category: provider.category,
                detailCategory: provider.detail,
                sourceDepths: depths.map(Optional.some),
                sourcePath: sourcePath,
                productName: input.productName
            )
            let conflictAudit = ParsedClosetClassification.auditExplicitContradictions(
                category: provider.category,
                detailCategory: provider.detail,
                sourceDepths: depths.map(Optional.some),
                sourcePath: sourcePath,
                productName: input.productName
            )

            let status: String
            if conflictAudit.requiresReview {
                status = "review_required"
            } else if classification?.isValid == true {
                status = "confirmed"
            } else {
                status = "unclassified"
            }
            let strictComparisonEligible = classification?.isValid == true
                && !conflictAudit.requiresReview

            XCTAssertFalse(
                conflictAudit.requiresReview && status == "confirmed",
                "critical conflict silently confirmed: \(identity)"
            )
            XCTAssertFalse(
                conflictAudit.requiresReview && strictComparisonEligible,
                "critical conflict reached strict comparison: \(identity)"
            )

            statusCounts[status, default: 0] += 1
            sourceStatusCounts[input.retailerCode, default: [:]][status, default: 0] += 1
            records.append(AuditRecord(
                source: input.retailerCode,
                productID: input.sourceProductID,
                productName: input.productName,
                sourcePath: sourcePath,
                providerCategory: provider.category.rawValue,
                providerDetail: provider.detail.rawValue,
                categoryCode: classification?.categoryCode,
                detailCode: classification?.detailCode,
                classificationValid: classification?.isValid == true,
                shadowStatus: status,
                strictComparisonEligible: strictComparisonEligible,
                conflictDimensions: conflictAudit.conflicts.map(\.dimension.rawValue),
                sourceAuthority: input.retailerCode == "ZARA"
                    ? "archive_source_candidate_not_gold"
                    : "current_parser_mapping_from_archived_source_facts",
                productURL: input.productURL
            ))
        }

        XCTAssertEqual(identities.count, 300)
        XCTAssertEqual(records.count, 300)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let resultData = try encoder.encode(records)
        let resultAttachment = XCTAttachment(data: resultData, uniformTypeIdentifier: "public.json")
        resultAttachment.name = "live-300-current-fitmatch-shadow-results.json"
        resultAttachment.lifetime = .keepAlways
        add(resultAttachment)

        let anomalies = records.filter { $0.shadowStatus != "confirmed" }
        let anomalyData = try encoder.encode(anomalies)
        let anomalyAttachment = XCTAttachment(data: anomalyData, uniformTypeIdentifier: "public.json")
        anomalyAttachment.name = "live-300-gold-review-candidates.json"
        anomalyAttachment.lifetime = .keepAlways
        add(anomalyAttachment)

        let summary: [String: Any] = [
            "input_count": inputs.count,
            "unique_count": identities.count,
            "independent_gold_label_count": 0,
            "status_counts": statusCounts,
            "source_status_counts": sourceStatusCounts,
            "gold_review_candidate_count": anomalies.count,
            "silent_conflict_confirmation_count": records.filter {
                !$0.conflictDimensions.isEmpty && $0.shadowStatus == "confirmed"
            }.count,
            "strict_comparison_conflict_leak_count": records.filter {
                !$0.conflictDimensions.isEmpty && $0.strictComparisonEligible
            }.count,
            "zara_runtime_parser_verified_count": 0,
        ]
        let summaryData = try JSONSerialization.data(
            withJSONObject: summary,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        print("LIVE_300_SHADOW_SUMMARY \(try XCTUnwrap(String(data: summaryData, encoding: .utf8)))")
    }

    private func loadInputs() throws -> [Input] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let inputURL = repositoryRoot
            .appendingPathComponent("Docs/Research/FitMatchCategoryMappingV2-20260824-shadow")
            .appendingPathComponent("live300-v2_3/live_products_300.jsonl")
        let text = try String(contentsOf: inputURL, encoding: .utf8)
        return try text
            .split(whereSeparator: \.isNewline)
            .map { try JSONDecoder().decode(Input.self, from: Data($0.utf8)) }
    }

    private func resolvedSourcePath(_ input: Input) -> String {
        if !input.sourceCategoryPaths.isEmpty {
            return input.sourceCategoryPaths.joined(separator: " > ")
        }
        return ["ZARA", input.familyName, input.subfamilyName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " > ")
    }

    private func providerClassification(
        _ input: Input,
        sourcePath: String,
        depths: [String]
    ) -> (category: ClothingCategory, detail: ClosetDetailCategory) {
        switch input.retailerCode {
        case "MUSINSA":
            return (
                MusinsaProductMetadataParser.mapCategory(from: sourcePath),
                MusinsaProductMetadataParser.mapDetailCategory(
                    from: depths.count > 1 ? depths[1] : sourcePath
                )
            )
        case "UNIQLO":
            let parser = UniqloProductMetadataParser()
            return (
                parser.mapCategory(from: sourcePath),
                parser.mapDetailCategory(from: "\(sourcePath) \(input.productName)")
            )
        case "ZARA":
            // The archive has no current PDP HTML or verified catentryId, so
            // its major candidate is deliberately treated as untrusted shadow
            // input. This exercises fail-closed classification/conflict logic;
            // it cannot approve a ZARA Gold label.
            let category: ClothingCategory
            switch input.fitmatchMajorCandidate {
            case "TOP": category = .top
            case "BOTTOM", "SKIRT": category = .bottom
            case "OUTER": category = .outer
            case "DRESS": category = .dress
            case "UNDERWEAR": category = .underwear
            default: category = .other
            }
            return (category, .other)
        default:
            return (.other, .other)
        }
    }
}
