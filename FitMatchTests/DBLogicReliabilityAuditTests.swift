import Foundation
import XCTest
@testable import FitMatch

@MainActor
final class DBLogicReliabilityAuditTests: XCTestCase {
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
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let inputURL = repositoryRoot
            .appendingPathComponent("Docs/TestEvidence/DBLogicReliability-20260815/current-batch-new-products.json")
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

    func testLegacyDBLogicAdjudicationCorpusRemainsParsableWithoutDefiningSourcedAuthority() throws {
        let bundle = Bundle(for: Self.self)
        let inputURL = try XCTUnwrap(
            bundle.url(forResource: "DBLogicReliabilityAdjudicationInputs", withExtension: "json")
        )
        let inputs = try JSONDecoder().decode([AdjudicatedInput].self, from: Data(contentsOf: inputURL))
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
            // This historical 207-row corpus records pre-vNext global
            // adjudications. Its expected tuple is server-owned Product
            // authority, while this loop deliberately runs only retailer
            // parser/local-Closet interpretation. Global sourced comparison
            // paths now consume the server effective-authority contract;
            // asserting equality here would require Swift to reclassify a
            // sourced product from its name/path, which is forbidden. Keep a
            // complete attachment for drift review without turning it into a
            // false release gate for the obsolete authority direction.
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
        let attachment = XCTAttachment(
            data: try JSONEncoder().encode(parserFacts),
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = "legacy-local-parser-facts-not-sourced-authority.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
