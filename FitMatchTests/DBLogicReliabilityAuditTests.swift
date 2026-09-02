import CryptoKit
import Foundation
import XCTest
@testable import FitMatch

@MainActor
final class DBLogicReliabilityAuditTests: XCTestCase {
    /// Canonical SHA-256 of the already-produced 2026-09-01
    /// `legacy-local-parser-facts-not-sourced-authority` attachment after
    /// deterministic JSON normalization. This is a parser/provider-fact
    /// oracle only; it is never a server effective-authority tuple.
    private static let legacyParserFactSnapshotSHA256 =
        "487c9a6fca572ca7b31adc0450b9e82fd158d2e174c101bf68243216b4a7670e"

    private struct AdjudicatedInput: Decodable {
        let source: String
        let productID: String
        let productName: String
        let sourceCategoryPath: String
        let expectedCategory: String?
        let expectedDetail: String?
        let expectedFamily: String?
        let expectedLength: String?
        let expectedConfirmation: Bool

        enum CodingKeys: String, CodingKey {
            case source
            case productID = "product_id"
            case productName = "product_name"
            case sourceCategoryPath = "source_category_path"
            case expectedCategory = "expected_category"
            case expectedDetail = "expected_detail"
            case expectedFamily = "expected_family"
            case expectedLength = "expected_length"
            case expectedConfirmation = "expected_confirmation"
        }
    }

    private struct Input: Decodable {
        let source: String
        let productID: String
        let productName: String
        let sourceCategoryPath: String

        enum CodingKeys: String, CodingKey {
            case source
            case productID = "product_id"
            case productName = "product_name"
            case sourceCategoryPath = "source_category_path"
        }
    }

    private struct Result: Encodable {
        let source: String
        let productID: String
        let productName: String
        let sourceCategoryPath: String
        let categoryCode: String?
        let detailCode: String?
        let comparisonFamily: String?
        let lengthType: String?
        let requiresUserConfirmation: Bool
    }

    func testCurrentBatchProductsNotPresentIn5026Corpus() throws {
        // Keep the immutable 346-row input test-owned and tracked.  The
        // original evidence attachment lives under an ignored Docs path, so
        // resolving that path made a clean checkout nondeterministic.
        let inputURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/DBLogicReliabilityCurrentBatchInputs.json")
        let inputs = try JSONDecoder().decode([Input].self, from: Data(contentsOf: inputURL))
        XCTAssertEqual(inputs.count, 346)

        let uniqloParser = UniqloProductMetadataParser()
        var identities = Set<String>()
        var results: [Result] = []

        for input in inputs {
            XCTAssertTrue(identities.insert("\(input.source)|\(input.productID)").inserted)
            let depths = input.sourceCategoryPath
                .components(separatedBy: ">")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let category: ClothingCategory
            let detail: ClosetDetailCategory
            if input.source == "musinsa" {
                category = MusinsaProductMetadataParser.mapCategory(from: input.sourceCategoryPath)
                detail = MusinsaProductMetadataParser.mapDetailCategory(
                    from: depths.count > 1 ? depths[1] : input.sourceCategoryPath
                )
            } else {
                category = uniqloParser.mapCategory(from: input.sourceCategoryPath)
                detail = uniqloParser.mapDetailCategory(
                    from: "\(input.sourceCategoryPath) \(input.productName)"
                )
            }
            let classification = ParsedClosetClassification.resolve(
                category: category,
                detailCategory: detail,
                sourceDepths: depths.map(Optional.some),
                sourcePath: input.sourceCategoryPath,
                productName: input.productName
            )
            results.append(Result(
                source: input.source,
                productID: input.productID,
                productName: input.productName,
                sourceCategoryPath: input.sourceCategoryPath,
                categoryCode: classification?.categoryCode,
                detailCode: classification?.detailCode,
                comparisonFamily: classification?.garmentFamily.rawValue,
                lengthType: classification?.lengthType.rawValue,
                requiresUserConfirmation: classification?.isValid != true
            ))
        }

        XCTAssertEqual(identities.count, 346)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let attachment = XCTAttachment(
            data: try encoder.encode(results),
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = "current-batch-new-products-app-results.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The 207-row corpus contains raw retailer facts plus a historical
    /// server/DB adjudicated tuple. Keep the real parser output frozen, but do
    /// not use the server-owned `expected_*` fields as a local Swift
    /// classifier oracle. Provider-to-server request integration is covered
    /// by FitMatchFinalReleaseProviderSnapshotTests; server tuple consumption
    /// is exercised explicitly below for the reported 5049615 conflict.
    func testLegacyDBLogicParserFactsRemainFrozenWithoutDefiningServerAuthority() throws {
        let inputs = try legacyAdjudicatedInputs()
        XCTAssertEqual(inputs.count, 207)

        let uniqloParser = UniqloProductMetadataParser()
        var identities = Set<String>()
        var parserFacts: [Result] = []
        for input in inputs {
            let identity = "\(input.source)|\(input.productID)"
            XCTAssertTrue(identities.insert(identity).inserted, "duplicate \(identity)")
            let depths = input.sourceCategoryPath
                .components(separatedBy: ">")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let category: ClothingCategory
            let detail: ClosetDetailCategory
            if input.source == "musinsa" {
                category = MusinsaProductMetadataParser.mapCategory(from: input.sourceCategoryPath)
                detail = MusinsaProductMetadataParser.mapDetailCategory(
                    from: depths.count > 1 ? depths[1] : input.sourceCategoryPath
                )
            } else {
                category = uniqloParser.mapCategory(from: input.sourceCategoryPath)
                detail = uniqloParser.mapDetailCategory(
                    from: "\(input.sourceCategoryPath) \(input.productName)"
                )
            }
            let classification = ParsedClosetClassification.resolve(
                category: category,
                detailCategory: detail,
                sourceDepths: depths.map(Optional.some),
                sourcePath: input.sourceCategoryPath,
                productName: input.productName
            )
            parserFacts.append(Result(
                source: input.source,
                productID: input.productID,
                productName: input.productName,
                sourceCategoryPath: input.sourceCategoryPath,
                categoryCode: classification?.categoryCode,
                detailCode: classification?.detailCode,
                comparisonFamily: classification?.garmentFamily.rawValue,
                lengthType: classification?.lengthType.rawValue,
                requiresUserConfirmation: classification?.isValid != true
            ))
        }
        XCTAssertEqual(identities.count, 207)
        XCTAssertEqual(parserFacts.count, inputs.count)

        let encodedFacts = try JSONEncoder().encode(parserFacts)
        let factsObject = try JSONSerialization.jsonObject(with: encodedFacts)
        let canonicalFacts = try JSONSerialization.data(
            withJSONObject: factsObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let digest = sha256Hex(canonicalFacts)
        if digest != Self.legacyParserFactSnapshotSHA256 {
            let attachment = XCTAttachment(
                data: canonicalFacts,
                uniformTypeIdentifier: "public.json"
            )
            attachment.name = "legacy-local-parser-facts-drift.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(
            digest,
            Self.legacyParserFactSnapshotSHA256,
            "207-row retailer parser facts changed; inspect the attached production-parser output."
        )
    }

    /// All 207 rows use the same ownership boundary. This is the known
    /// conflict case: the retailer path fact is sleeveless, while the server
    /// authority tuple is blouse. The production coordinator must consume the
    /// server tuple without requiring Swift to relabel the provider fact.
    func testDBLogic5049615KeepsProviderFactSeparateFromServerAuthority() async throws {
        let input = try XCTUnwrap(
            try legacyAdjudicatedInputs().first(where: { $0.productID == "5049615" })
        )
        let depths = input.sourceCategoryPath
            .components(separatedBy: ">")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let providerDetail = MusinsaProductMetadataParser.mapDetailCategory(
            from: depths.count > 1 ? depths[1] : input.sourceCategoryPath
        )
        XCTAssertEqual(providerDetail, .sleeveless)

        let category = try XCTUnwrap(input.expectedCategory)
        let detail = try XCTUnwrap(input.expectedDetail)
        let family = try XCTUnwrap(input.expectedFamily)
        let length = try XCTUnwrap(input.expectedLength)
        let request = FitMatchProductResolutionRequest(
            source: input.source,
            externalProductID: input.productID,
            productName: input.productName,
            sourceCategoryPath: input.sourceCategoryPath,
            audience: nil,
            sourceCategoryCodes: nil
        )
        let remote = FitMatchEchoServerAuthorityRemote(
            categoryCode: category,
            detailCode: detail,
            familyCode: family,
            lengthCode: length
        )
        let authority = try await FitMatchServerAuthorityCoordinator(remote: remote)
            .resolveProductAuthority(request: request, observation: nil)

        XCTAssertEqual(authority.status, .confirmed)
        XCTAssertEqual(authority.classification.categoryCode, category)
        XCTAssertEqual(authority.classification.detailCode, detail)
        XCTAssertEqual(authority.classification.garmentTypeCode, family)
        XCTAssertEqual(authority.classification.familyCode, family)
        XCTAssertEqual(authority.classification.lengthCode, length)
        XCTAssertEqual(
            authority.classification.requiresUserConfirmation,
            input.expectedConfirmation
        )
        XCTAssertEqual(authority.classification.detailCode, "blouse")
    }

    private func legacyAdjudicatedInputs() throws -> [AdjudicatedInput] {
        let bundle = Bundle(for: Self.self)
        let inputURL = try XCTUnwrap(
            bundle.url(forResource: "DBLogicReliabilityAdjudicationInputs", withExtension: "json")
        )
        return try JSONDecoder().decode(
            [AdjudicatedInput].self,
            from: Data(contentsOf: inputURL)
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
