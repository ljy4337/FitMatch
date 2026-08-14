import Foundation
import XCTest
@testable import FitMatch

@MainActor
final class CategoryValidation5026AuditTests: XCTestCase {
    private struct Input: Decodable {
        let source: String
        let productID: String
        let productName: String
        let sourcePath: String
        let productURL: String?
        let originInput: String
        let previousCategoryCode: String?
        let previousDetailCode: String?
        let externalCategoryID: String

        enum CodingKeys: String, CodingKey {
            case source
            case productID = "product_id"
            case productName = "product_name"
            case sourcePath = "source_path"
            case productURL = "product_url"
            case originInput = "origin_input"
            case previousCategoryCode = "previous_category_code"
            case previousDetailCode = "previous_detail_code"
            case externalCategoryID = "external_category_id"
        }
    }

    private struct Record: Encodable {
        let inputIndex: Int
        let source: String
        let productID: String
        let productName: String
        let productURL: String?
        let sourcePath: String
        let originInput: String
        let externalCategoryID: String
        let providerCategory: String
        let providerMajorCode: String
        let providerDetail: String
        let finalCategoryCode: String?
        let finalDetailCode: String?
        let normalizedProductTypeCode: String?
        let garmentFamily: String?
        let lengthType: String?
        let constructionType: String?
        let classificationIsValid: Bool
        let userConfirmationRequired: Bool
        let decisionTrace: String
        let previousCategoryCode: String?
        let previousDetailCode: String?
        let previousMajorChanged: Bool?
        let previousDetailChanged: Bool?
    }

    private struct LiveRevalidationRecord: Encodable {
        let source: String
        let productID: String
        let productName: String
        let productURL: String?
        let storedSourcePath: String
        let offlineFinalCategoryCode: String?
        let offlineFinalDetailCode: String?
        let offlineUserConfirmationRequired: Bool
        let liveParsingSucceeded: Bool
        let livePartialParsingUsed: Bool
        let liveSourceCategoryPath: String?
        let liveParsedCategory: String?
        let liveParsedDetail: String?
        let liveFinalCategoryCode: String?
        let liveFinalDetailCode: String?
        let liveClassificationIsValid: Bool
        let liveUserConfirmationRequired: Bool
        let dangerousOtherAutoConfirmation: Bool
        let liveRegistrationAvailable: Bool
        let liveSizeCount: Int
        let failureReason: String?
    }

    func testCurrentProductionClassifierReclassifiesAll5026Products() throws {
        let bundle = Bundle(for: CategoryValidation5026AuditTests.self)
        let inputURL = try XCTUnwrap(
            bundle.url(forResource: "CategoryValidation5026Inputs", withExtension: "json")
        )
        let inputs = try JSONDecoder().decode([Input].self, from: Data(contentsOf: inputURL))
        XCTAssertEqual(inputs.count, 5_026)

        var identities = Set<String>()
        var records: [Record] = []
        var categoryCounts: [String: Int] = [:]
        var detailCounts: [String: Int] = [:]
        var confirmationRequired = 0
        var invalidClassifications = 0
        var placeholderClassifications = 0
        var previousMajorChanges = 0
        var previousDetailChanges = 0
        let uniqloParser = UniqloProductMetadataParser()

        for (offset, input) in inputs.enumerated() {
            let identity = "\(input.source):\(input.productID)"
            XCTAssertTrue(identities.insert(identity).inserted, "duplicate input \(identity)")

            let depths = input.sourcePath
                .components(separatedBy: ">")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let providerCategory: ClothingCategory
            let providerDetail: ClosetDetailCategory
            if input.source == "musinsa" {
                providerCategory = MusinsaProductMetadataParser.mapCategory(from: input.sourcePath)
                providerDetail = MusinsaProductMetadataParser.mapDetailCategory(
                    from: depths.count > 1 ? depths[1] : input.sourcePath
                )
            } else {
                // Match UniqloProductMetadataParser.parse exactly: official
                // source path determines the major category; product name may
                // only refine the detail category.
                providerCategory = uniqloParser.mapCategory(from: input.sourcePath)
                providerDetail = uniqloParser.mapDetailCategory(
                    from: "\(input.sourcePath) \(input.productName)"
                )
            }

            let classification = ParsedClosetClassification.resolve(
                category: providerCategory,
                detailCategory: providerDetail,
                sourceDepths: depths.map(Optional.some),
                sourcePath: input.sourcePath,
                productName: input.productName
            )
            let isValid = classification?.isValid == true
            let needsConfirmation = !isValid
            if needsConfirmation { confirmationRequired += 1 }
            if classification?.categoryCode == "other",
               classification?.detailCode == "other" {
                placeholderClassifications += 1
            } else if classification != nil, !isValid {
                invalidClassifications += 1
            }

            if let categoryCode = classification?.categoryCode {
                categoryCounts[categoryCode, default: 0] += 1
            }
            if let detailCode = classification?.detailCode {
                detailCounts[detailCode, default: 0] += 1
            }

            let previousMajorChanged = input.previousCategoryCode.map {
                $0 != classification?.categoryCode
            }
            let previousDetailChanged = input.previousDetailCode.map {
                $0 != classification?.detailCode
            }
            if previousMajorChanged == true { previousMajorChanges += 1 }
            if previousDetailChanged == true { previousDetailChanges += 1 }

            let decisionTrace: String
            if classification == nil {
                decisionTrace = "canonical_resolution_nil_requires_user_confirmation"
            } else if !isValid {
                decisionTrace = "canonical_taxonomy_contract_invalid_requires_user_confirmation"
            } else if classification?.categoryCode != providerCategory.serviceGroup.taxonomyCode {
                decisionTrace = "canonical_resolution_changed_provider_major"
            } else if classification?.detailCategory != providerDetail {
                decisionTrace = "canonical_resolution_refined_provider_detail"
            } else {
                decisionTrace = "provider_mapping_confirmed_by_canonical_resolution"
            }

            records.append(Record(
                inputIndex: offset + 1,
                source: input.source,
                productID: input.productID,
                productName: input.productName,
                productURL: input.productURL,
                sourcePath: input.sourcePath,
                originInput: input.originInput,
                externalCategoryID: input.externalCategoryID,
                providerCategory: providerCategory.rawValue,
                providerMajorCode: providerCategory.serviceGroup.taxonomyCode,
                providerDetail: providerDetail.rawValue,
                finalCategoryCode: classification?.categoryCode,
                finalDetailCode: classification?.detailCode,
                normalizedProductTypeCode: classification?.normalizedProductTypeCode,
                garmentFamily: classification?.garmentFamily.rawValue,
                lengthType: classification?.lengthType.rawValue,
                constructionType: classification?.constructionType.rawValue,
                classificationIsValid: isValid,
                userConfirmationRequired: needsConfirmation,
                decisionTrace: decisionTrace,
                previousCategoryCode: input.previousCategoryCode,
                previousDetailCode: input.previousDetailCode,
                previousMajorChanged: previousMajorChanged,
                previousDetailChanged: previousDetailChanged
            ))
        }

        XCTAssertEqual(identities.count, 5_026)
        XCTAssertEqual(records.count, 5_026)
        XCTAssertEqual(invalidClassifications, 0)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let resultData = try encoder.encode(records)
        let attachment = XCTAttachment(data: resultData, uniformTypeIdentifier: "public.json")
        attachment.name = "category-validation-5026-results.json"
        attachment.lifetime = .keepAlways
        add(attachment)

        let summary: [String: Any] = [
            "input_count": inputs.count,
            "unique_count": identities.count,
            "output_count": records.count,
            "classified_count": records.count - confirmationRequired,
            "user_confirmation_required_count": confirmationRequired,
            "invalid_classification_count": invalidClassifications,
            "placeholder_other_classification_count": placeholderClassifications,
            "previous_major_change_count": previousMajorChanges,
            "previous_detail_change_count": previousDetailChanges,
            "category_counts": categoryCounts,
            "detail_counts": detailCounts,
        ]
        let summaryData = try JSONSerialization.data(
            withJSONObject: summary,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let summaryText = try XCTUnwrap(String(data: summaryData, encoding: .utf8))
        print("CATEGORY_5026_SUMMARY \(summaryText)")
    }

    func testLiveProductionParserRevalidatesOfflineAmbiguousAndOtherProducts() async throws {
        let bundle = Bundle(for: CategoryValidation5026AuditTests.self)
        let inputURL = try XCTUnwrap(
            bundle.url(forResource: "CategoryValidation5026Inputs", withExtension: "json")
        )
        let inputs = try JSONDecoder().decode([Input].self, from: Data(contentsOf: inputURL))
        let uniqloParser = UniqloProductMetadataParser()

        var candidates: [(Input, ParsedClosetClassification?)] = []
        for input in inputs {
            let depths = input.sourcePath
                .components(separatedBy: ">")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let providerCategory: ClothingCategory
            let providerDetail: ClosetDetailCategory
            if input.source == "musinsa" {
                providerCategory = MusinsaProductMetadataParser.mapCategory(from: input.sourcePath)
                providerDetail = MusinsaProductMetadataParser.mapDetailCategory(
                    from: depths.count > 1 ? depths[1] : input.sourcePath
                )
            } else {
                providerCategory = uniqloParser.mapCategory(from: input.sourcePath)
                providerDetail = uniqloParser.mapDetailCategory(
                    from: "\(input.sourcePath) \(input.productName)"
                )
            }
            let classification = ParsedClosetClassification.resolve(
                category: providerCategory,
                detailCategory: providerDetail,
                sourceDepths: depths.map(Optional.some),
                sourcePath: input.sourcePath,
                productName: input.productName
            )
            if classification?.isValid != true || classification?.categoryCode == "other" {
                candidates.append((input, classification))
            }
        }

        XCTAssertEqual(inputs.count, 5_026)
        XCTAssertFalse(candidates.isEmpty)
        var records: [LiveRevalidationRecord] = []
        var liveSucceeded = 0
        var liveFailed = 0
        var liveConfirmationRequired = 0
        var dangerousOther = 0
        let parser = ProductURLParserService()

        for (offset, candidate) in candidates.enumerated() {
            let input = candidate.0
            guard let productURL = input.productURL else {
                liveFailed += 1
                records.append(LiveRevalidationRecord(
                    source: input.source,
                    productID: input.productID,
                    productName: input.productName,
                    productURL: nil,
                    storedSourcePath: input.sourcePath,
                    offlineFinalCategoryCode: candidate.1?.categoryCode,
                    offlineFinalDetailCode: candidate.1?.detailCode,
                    offlineUserConfirmationRequired: candidate.1?.isValid != true,
                    liveParsingSucceeded: false,
                    livePartialParsingUsed: false,
                    liveSourceCategoryPath: nil,
                    liveParsedCategory: nil,
                    liveParsedDetail: nil,
                    liveFinalCategoryCode: nil,
                    liveFinalDetailCode: nil,
                    liveClassificationIsValid: false,
                    liveUserConfirmationRequired: true,
                    dangerousOtherAutoConfirmation: false,
                    liveRegistrationAvailable: false,
                    liveSizeCount: 0,
                    failureReason: "missing_product_url"
                ))
                continue
            }

            var partialParsingUsed = false
            let info: ParsedProductInfo
            do {
                info = try await parser.parse(urlString: productURL)
            } catch let partialError as ProductURLParserPartialError {
                partialParsingUsed = true
                info = partialError.productInfo.normalizedSizes()
            } catch {
                liveFailed += 1
                liveConfirmationRequired += 1
                records.append(LiveRevalidationRecord(
                    source: input.source,
                    productID: input.productID,
                    productName: input.productName,
                    productURL: productURL,
                    storedSourcePath: input.sourcePath,
                    offlineFinalCategoryCode: candidate.1?.categoryCode,
                    offlineFinalDetailCode: candidate.1?.detailCode,
                    offlineUserConfirmationRequired: candidate.1?.isValid != true,
                    liveParsingSucceeded: false,
                    livePartialParsingUsed: false,
                    liveSourceCategoryPath: nil,
                    liveParsedCategory: nil,
                    liveParsedDetail: nil,
                    liveFinalCategoryCode: nil,
                    liveFinalDetailCode: nil,
                    liveClassificationIsValid: false,
                    liveUserConfirmationRequired: true,
                    dangerousOtherAutoConfirmation: false,
                    liveRegistrationAvailable: false,
                    liveSizeCount: 0,
                    failureReason: error.localizedDescription
                ))
                print("CATEGORY_5026_LIVE_PROGRESS index=\(offset + 1)/\(candidates.count) source=\(input.source) id=\(input.productID) status=failure")
                continue
            }

            let viewModel = ShoppingProductViewModel(initialURL: productURL)
            viewModel.apply(info)
            let product = viewModel.makeProductForClosetRegistration(brand: viewModel.makeBrand())
            let classification: ParsedClosetClassification?
            if let product {
                classification = ParsedClosetClassification.resolve(
                    product: product,
                    detailCategory: viewModel.detailCategory
                )
            } else {
                classification = ParsedClosetClassification.resolve(
                    category: viewModel.category,
                    detailCategory: viewModel.detailCategory,
                    sourceDepths: [
                        info.sourceCategoryDepth1,
                        info.sourceCategoryDepth2,
                        info.sourceCategoryDepth3,
                        info.sourceCategoryDepth4,
                    ],
                    sourcePath: info.sourceCategoryPath,
                    productName: info.productName
                )
            }
            let isValid = classification?.isValid == true
            let needsConfirmation = !isValid
            let isDangerousOther = isValid && classification?.categoryCode == "other"
            if needsConfirmation { liveConfirmationRequired += 1 }
            if isDangerousOther { dangerousOther += 1 }
            liveSucceeded += 1
            records.append(LiveRevalidationRecord(
                source: input.source,
                productID: input.productID,
                productName: info.productName,
                productURL: productURL,
                storedSourcePath: input.sourcePath,
                offlineFinalCategoryCode: candidate.1?.categoryCode,
                offlineFinalDetailCode: candidate.1?.detailCode,
                offlineUserConfirmationRequired: candidate.1?.isValid != true,
                liveParsingSucceeded: true,
                livePartialParsingUsed: partialParsingUsed,
                liveSourceCategoryPath: info.sourceCategoryPath,
                liveParsedCategory: viewModel.category.rawValue,
                liveParsedDetail: viewModel.detailCategory.rawValue,
                liveFinalCategoryCode: classification?.categoryCode,
                liveFinalDetailCode: classification?.detailCode,
                liveClassificationIsValid: isValid,
                liveUserConfirmationRequired: needsConfirmation,
                dangerousOtherAutoConfirmation: isDangerousOther,
                liveRegistrationAvailable: product != nil,
                liveSizeCount: product?.sizes.count ?? info.sizes.count,
                failureReason: nil
            ))
            if (offset + 1).isMultiple(of: 10) || offset + 1 == candidates.count {
                print("CATEGORY_5026_LIVE_PROGRESS index=\(offset + 1)/\(candidates.count) source=\(input.source) id=\(input.productID) status=success")
            }
        }

        XCTAssertEqual(records.count, candidates.count)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let resultData = try encoder.encode(records)
        let attachment = XCTAttachment(data: resultData, uniformTypeIdentifier: "public.json")
        attachment.name = "category-validation-live-revalidation-results.json"
        attachment.lifetime = .keepAlways
        add(attachment)

        let summary: [String: Any] = [
            "candidate_count": candidates.count,
            "live_succeeded_count": liveSucceeded,
            "live_failed_count": liveFailed,
            "live_user_confirmation_required_count": liveConfirmationRequired,
            "dangerous_other_auto_confirmation_count": dangerousOther,
        ]
        let summaryData = try JSONSerialization.data(
            withJSONObject: summary,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let summaryText = try XCTUnwrap(String(data: summaryData, encoding: .utf8))
        print("CATEGORY_5026_LIVE_SUMMARY \(summaryText)")
    }
}
