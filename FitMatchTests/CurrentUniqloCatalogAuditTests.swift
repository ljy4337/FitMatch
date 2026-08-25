import Foundation
import XCTest
@testable import FitMatch

@MainActor
final class CurrentUniqloCatalogAuditTests: XCTestCase {
    private struct LoadedProduct {
        let id: String
        let name: String
        let url: String
        let sourcePath: String
        let detail: ClosetDetailCategory
        let classification: ParsedClosetClassification?
        let product: Product
    }

    private struct ClassificationRecord: Encodable {
        let productID: String
        let productName: String
        let productURL: String
        let shoppingMallCategory: String
        let providerCategory: String
        let providerDetailCategory: String
        let fitMatchCategoryCode: String?
        let fitMatchDetailCode: String?
        let garmentFamily: String?
        let lengthType: String?
        let userConfirmationRequired: Bool
        let canonicalEligibility: Bool?
        let rawSizeRowCount: Int
        let parsedSizeRowCount: Int
        let sizeCount: Int
        let observedURLCount: Int
    }

    private struct ScenarioRecord: Encodable {
        let caseNumber: Int
        let scenario: String
        let targetID: String
        let targetName: String
        let targetURL: String
        let targetShoppingMallCategory: String
        let targetFitMatchCategory: String
        let referenceID: String
        let referenceName: String
        let referenceShoppingMallCategory: String
        let referenceFitMatchCategory: String
        let expectedOutcome: String
        let actualOutcome: String
        let passed: Bool
    }

    func testCurrentOfficialCatalogProductionClassificationAndATest() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.arguments.contains("-fitmatchRunCurrentUniqloCatalogAudit")
                || ProcessInfo.processInfo.environment["FITMATCH_RUN_CURRENT_UNIQLO_CATALOG_AUDIT"] == "1",
            "880건 Uniqlo 카탈로그 검증은 FITMATCH_RUN_CURRENT_UNIQLO_CATALOG_AUDIT=1로 독립 실행합니다."
        )
        executionTimeAllowance = 1_200
        let bundle = Bundle(for: CurrentUniqloCatalogAuditTests.self)
        let inputURL = try XCTUnwrap(
            bundle.url(forResource: "CurrentUniqloCatalogInputs", withExtension: "json")
        )
        let rows = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: inputURL)) as? [[String: Any]]
        )
        XCTAssertEqual(rows.count, 880)

        let sizeParser = UniqloSizeAPIParser()
        var loaded: [LoadedProduct] = []
        var classificationRecords: [ClassificationRecord] = []
        var uniqueIDs = Set<String>()
        var parsedSizeRows = 0
        var rawSizeRows = 0
        var invalidClassifications = 0

        for row in rows {
            let id = try XCTUnwrap(row["product_id"] as? String)
            let name = try XCTUnwrap(row["product_name"] as? String)
            let url = try XCTUnwrap(row["canonical_url"] as? String)
            let sourcePath = try XCTUnwrap(row["source_path"] as? String)
            let audience = try XCTUnwrap(row["audience"] as? String)
            let depthNames = try XCTUnwrap(row["source_depth_names"] as? [String])
            let depthCodes = try XCTUnwrap(row["source_depth_codes"] as? [String])
            let observedIDs = try XCTUnwrap(row["observed_ids"] as? [String])
            let payload = try XCTUnwrap(row["size_chart_payload"])
            let rawSizeRowCount = rawSizeRowCount(in: payload)
            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            let parsedSizes = try sizeParser.parseSizes(from: payloadData)
            rawSizeRows += rawSizeRowCount
            parsedSizeRows += parsedSizes.count

            XCTAssertTrue(uniqueIDs.insert(id).inserted, "duplicate product id: \(id)")
            let providerCategory = UniqloProductMetadataParser().mapCategory(from: sourcePath)
            let providerDetail = UniqloProductMetadataParser().mapDetailCategory(
                from: "\(sourcePath) \(name)"
            )
            let info = ParsedProductInfo(
                sourceURL: try XCTUnwrap(URL(string: url)),
                sourceType: .officialStore,
                sourceName: "유니클로 공식몰",
                brandName: "유니클로",
                productName: name,
                category: providerCategory,
                detailCategory: providerDetail,
                sizes: parsedSizes,
                productID: id,
                canonicalURLString: url,
                sourceCategoryPath: sourcePath,
                sourceCategoryDepth1: depthNames.indices.contains(0) ? depthNames[0] : nil,
                sourceCategoryDepth2: depthNames.indices.contains(1) ? depthNames[1] : nil,
                sourceCategoryDepth3: depthNames.indices.contains(2) ? depthNames[2] : nil,
                sourceCategoryDepth4: depthNames.indices.contains(3) ? depthNames[3] : nil,
                productTargetGender: UserGender.productTarget(from: [audience]),
                productMetadata: ProductMetadata(
                    sourceCategoryPath: sourcePath,
                    sourceCategoryDepth1: depthNames.indices.contains(0) ? depthNames[0] : nil,
                    sourceCategoryDepth2: depthNames.indices.contains(1) ? depthNames[1] : nil,
                    sourceCategoryDepth3: depthNames.indices.contains(2) ? depthNames[2] : nil,
                    sourceCategoryDepth4: depthNames.indices.contains(3) ? depthNames[3] : nil,
                    categoryDepth1Code: depthCodes.indices.contains(0) ? depthCodes[0] : nil,
                    categoryDepth1Name: depthNames.indices.contains(0) ? depthNames[0] : nil,
                    categoryDepth2Code: depthCodes.indices.contains(1) ? depthCodes[1] : nil,
                    categoryDepth2Name: depthNames.indices.contains(1) ? depthNames[1] : nil,
                    categoryDepth3Code: depthCodes.indices.contains(2) ? depthCodes[2] : nil,
                    categoryDepth3Name: depthNames.indices.contains(2) ? depthNames[2] : nil,
                    categoryDepth4Code: depthCodes.indices.contains(3) ? depthCodes[3] : nil,
                    categoryDepth4Name: depthNames.indices.contains(3) ? depthNames[3] : nil,
                    genderCodes: [audience]
                )
            ).normalizedSizes()
            let viewModel = ShoppingProductViewModel(initialURL: url)
            viewModel.apply(info)
            guard let product = viewModel.makeProductForClosetRegistration(
                brand: viewModel.makeBrand()
            ) else {
                classificationRecords.append(ClassificationRecord(
                    productID: id, productName: name, productURL: url,
                    shoppingMallCategory: sourcePath,
                    providerCategory: providerCategory.rawValue,
                    providerDetailCategory: providerDetail.rawValue,
                    fitMatchCategoryCode: nil,
                    fitMatchDetailCode: nil, garmentFamily: nil, lengthType: nil,
                    userConfirmationRequired: true, canonicalEligibility: nil,
                    rawSizeRowCount: rawSizeRowCount,
                    parsedSizeRowCount: parsedSizes.count,
                    sizeCount: 0, observedURLCount: observedIDs.count
                ))
                continue
            }
            let classification = ParsedClosetClassification.resolve(
                product: product,
                detailCategory: viewModel.detailCategory
            )
            if classification != nil, classification?.isValid != true {
                invalidClassifications += 1
            }
            if let classification {
                product.category = classification.category
                product.categoryCode = classification.categoryCode
                product.normalizedProductTypeCode = classification.normalizedProductTypeCode
                product.garmentType = classification.garmentFamily
                product.sleeveType = classification.lengthType
                product.constructionType = classification.constructionType
            }
            let canonical = CanonicalComparisonProfileResolver().resolve(
                source: product.sourceDisplayName,
                externalCategoryID: nil,
                target: canonicalTarget(for: product.productTargetGender),
                sourceCategoryPath: product.sourceCategoryPath
            )
            CanonicalComparisonProfileResolver().apply(canonical, to: product)
            _ = ComparisonProfileMatcher().profile(
                for: product,
                detailCategory: viewModel.detailCategory
            )
            classificationRecords.append(ClassificationRecord(
                productID: id, productName: name, productURL: url,
                shoppingMallCategory: sourcePath,
                providerCategory: providerCategory.rawValue,
                providerDetailCategory: providerDetail.rawValue,
                fitMatchCategoryCode: classification?.categoryCode,
                fitMatchDetailCode: classification?.detailCode,
                garmentFamily: product.garmentTypeRawValue,
                lengthType: product.sleeveTypeRawValue,
                userConfirmationRequired: classification?.isValid != true,
                canonicalEligibility: product.canonicalEligibility,
                rawSizeRowCount: rawSizeRowCount,
                parsedSizeRowCount: parsedSizes.count,
                sizeCount: product.sizes.count,
                observedURLCount: observedIDs.count
            ))
            loaded.append(LoadedProduct(
                id: id, name: name, url: url, sourcePath: sourcePath,
                detail: viewModel.detailCategory,
                classification: classification,
                product: product
            ))
        }

        XCTAssertEqual(uniqueIDs.count, 880)
        XCTAssertEqual(classificationRecords.count, 880)
        XCTAssertEqual(invalidClassifications, 0)
        XCTAssertEqual(rawSizeRows, 5_193)
        // The production parser intentionally de-duplicates repeated product/color
        // size rows. The current corpus contains 12 such duplicates.
        XCTAssertEqual(parsedSizeRows, 5_181)

        let eligible = loaded.filter {
            !$0.product.sizes.isEmpty
                && $0.classification?.isValid == true
                && $0.product.canonicalEligibility != false
        }
        var scenarioRecords: [ScenarioRecord] = []
        var caseNumber = 0
        let matcher = ComparisonProfileMatcher()
        let service = RecommendationService()

        // Empty-closet behavior is a required A-test branch for every product
        // that can reach the comparison model, including confirmation-required
        // and policy-ineligible products.
        for target in loaded {
            caseNumber += 1
            let plan = service.referenceSelectionPlan(
                product: target.product,
                productDetailCategory: target.detail,
                userFits: []
            )
            let manual = service.temporaryComparisonCandidates(
                product: target.product,
                productDetailCategory: target.detail,
                userFits: []
            )
            let recommendation = service.recommend(
                product: target.product,
                userFits: [],
                productDetailCategory: target.detail,
                allowsGlobalFallback: false
            )
            let actual = plan.automaticallySelectedCandidate == nil
                && plan.recommendedCandidates.isEmpty
                && manual.isEmpty
                && recommendation == nil
                ? "missing_reference" : "unexpected_comparison_available"
            scenarioRecords.append(makeScenario(
                number: caseNumber,
                name: "empty_closet",
                target: target,
                reference: target,
                expected: "missing_reference",
                actual: actual
            ))
        }

        for target in eligible {
            guard let compatibleReference = eligible.first(where: { candidate in
                guard candidate.id != target.id else { return false }
                let item = makeUserFit(candidate, representative: true)
                return matcher.match(
                    product: target.product,
                    productDetailCategory: target.detail,
                    userFits: [item]
                ).state == .compatible
            }) else { continue }

            // Profile compatibility is intentionally broader than a complete
            // recommendation. Only generate ON/OFF scenarios when production
            // ranking confirms that this exact garment can be selected.
            let representativeProbe = makeUserFit(compatibleReference, representative: true)
            guard service.referenceSelectionPlan(
                product: target.product,
                productDetailCategory: target.detail,
                userFits: [representativeProbe]
            ).automaticallySelectedCandidate != nil else { continue }

            for representative in [true, false] {
                caseNumber += 1
                let reference = makeUserFit(compatibleReference, representative: representative)
                let plan = service.referenceSelectionPlan(
                    product: target.product,
                    productDetailCategory: target.detail,
                    userFits: [reference]
                )
                let recommendation = service.recommend(
                    product: target.product,
                    userFits: [reference],
                    productDetailCategory: target.detail,
                    allowsGlobalFallback: false
                )
                let expected = representative ? "automatic_compare" : "manual_selection"
                let manual = service.temporaryComparisonCandidates(
                    product: target.product,
                    productDetailCategory: target.detail,
                    userFits: [reference]
                )
                let actual: String
                if plan.automaticallySelectedCandidate != nil, recommendation != nil {
                    actual = "automatic_compare"
                } else if plan.automaticallySelectedCandidate == nil,
                          !manual.isEmpty,
                          recommendation == nil {
                    actual = "manual_selection"
                } else {
                    actual = "comparison_unavailable"
                }
                scenarioRecords.append(makeScenario(
                    number: caseNumber,
                    name: representative ? "reference_on" : "reference_off",
                    target: target,
                    reference: compatibleReference,
                    expected: expected,
                    actual: actual
                ))
            }

            if let blockedReference = eligible.first(where: {
                $0.id != target.id
                    && $0.product.category.serviceGroup != target.product.category.serviceGroup
            }) {
                caseNumber += 1
                let reference = makeUserFit(blockedReference, representative: true)
                let plan = service.referenceSelectionPlan(
                    product: target.product,
                    productDetailCategory: target.detail,
                    userFits: [reference]
                )
                let recommendation = service.recommend(
                    product: target.product,
                    userFits: [reference],
                    productDetailCategory: target.detail,
                    allowsGlobalFallback: false
                )
                let manual = service.temporaryComparisonCandidates(
                    product: target.product,
                    productDetailCategory: target.detail,
                    userFits: [reference]
                )
                let actual = plan.automaticallySelectedCandidate == nil
                    && plan.recommendedCandidates.isEmpty
                    && manual.isEmpty
                    && recommendation == nil
                    ? "blocked" : "unexpected_comparison_available"
                scenarioRecords.append(makeScenario(
                    number: caseNumber,
                    name: "cross_major_block",
                    target: target,
                    reference: blockedReference,
                    expected: "blocked",
                    actual: actual
                ))
            }
        }

        // P1 conflict detection intentionally removes explicit category/name
        // contradictions from the eligible set. Keep those products in this
        // production-path audit and prove that even a structurally related,
        // otherwise eligible reference cannot move them into comparison.
        let reviewRequired = loaded.filter {
            !$0.product.sizes.isEmpty
                && $0.classification?.isValid == true
                && $0.product.canonicalEligibility == false
        }
        for target in reviewRequired {
            guard let referenceProduct = eligible.first(where: {
                $0.id != target.id
                    && $0.product.category.serviceGroup == target.product.category.serviceGroup
            }) else { continue }

            caseNumber += 1
            let reference = makeUserFit(referenceProduct, representative: true)
            let plan = service.referenceSelectionPlan(
                product: target.product,
                productDetailCategory: target.detail,
                userFits: [reference]
            )
            let manual = service.temporaryComparisonCandidates(
                product: target.product,
                productDetailCategory: target.detail,
                userFits: [reference]
            )
            let recommendation = service.recommend(
                product: target.product,
                userFits: [reference],
                productDetailCategory: target.detail,
                allowsGlobalFallback: false
            )
            let actual = plan.automaticallySelectedCandidate == nil
                && plan.recommendedCandidates.isEmpty
                && manual.isEmpty
                && recommendation == nil
                ? "review_required" : "unexpected_comparison_available"
            scenarioRecords.append(makeScenario(
                number: caseNumber,
                name: "classification_conflict_block",
                target: target,
                reference: referenceProduct,
                expected: "review_required",
                actual: actual
            ))
        }

        let failed = scenarioRecords.filter { !$0.passed }
        attach(classificationRecords, name: "current-uniqlo-classification-results.json")
        attach(scenarioRecords, name: "current-uniqlo-a-test-results.json")
        print("CURRENT_UNIQLO_CATALOG_SUMMARY products=\(classificationRecords.count) raw_size_rows=\(rawSizeRows) parsed_size_rows=\(parsedSizeRows) eligible=\(eligible.count) scenarios=\(scenarioRecords.count) pass=\(scenarioRecords.count - failed.count) fail=\(failed.count)")
        XCTAssertGreaterThanOrEqual(scenarioRecords.count, 2_000)
        XCTAssertTrue(failed.isEmpty, "unexpected A-test outcomes: \(failed.count)")
    }

    private func rawSizeRowCount(in payload: Any) -> Int {
        guard let object = payload as? [String: Any],
              let results = object["result"] as? [[String: Any]] else { return 0 }
        return results.reduce(0) { partial, result in
            partial + ((result["sizeChart"] as? [[String: Any]])?.count ?? 0)
        }
    }

    private func makeUserFit(_ loaded: LoadedProduct, representative: Bool) -> UserFit {
        let product = loaded.product
        let size = product.sizes[product.sizes.count / 2]
        let item = UserFit(
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            sourceCategoryPath: product.sourceCategoryPath,
            sourceCategoryDepth1: product.sourceCategoryDepth1,
            sourceCategoryDepth2: product.sourceCategoryDepth2,
            sourceCategoryDepth3: product.sourceCategoryDepth3,
            sourceCategoryDepth4: product.sourceCategoryDepth4,
            brandName: "유니클로",
            gender: product.productTargetGender,
            productName: product.name,
            category: product.category,
            detailCategory: loaded.detail,
            sizeName: size.name,
            measurements: size.measurements,
            fitMemo: "current-uniqlo-catalog-a-test",
            satisfaction: 3,
            isRepresentative: representative,
            sourceProduct: product,
            sourceProductSize: size
        )
        item.replaceMeasurementRecords(with: size.measurementRecords)
        item.categoryCode = loaded.classification?.categoryCode
        item.detailCategoryCode = loaded.classification?.detailCode
        CanonicalComparisonProfileResolver().apply(product.canonicalProfileSnapshot, to: item)
        _ = ComparisonProfileMatcher().profile(for: item)
        return item
    }

    private func makeScenario(
        number: Int,
        name: String,
        target: LoadedProduct,
        reference: LoadedProduct,
        expected: String,
        actual: String
    ) -> ScenarioRecord {
        ScenarioRecord(
            caseNumber: number,
            scenario: name,
            targetID: target.id,
            targetName: target.name,
            targetURL: target.url,
            targetShoppingMallCategory: target.sourcePath,
            targetFitMatchCategory: "\(target.classification?.categoryCode ?? "nil")/\(target.classification?.detailCode ?? "nil")",
            referenceID: reference.id,
            referenceName: reference.name,
            referenceShoppingMallCategory: reference.sourcePath,
            referenceFitMatchCategory: "\(reference.classification?.categoryCode ?? "nil")/\(reference.classification?.detailCode ?? "nil")",
            expectedOutcome: expected,
            actualOutcome: actual,
            passed: expected == actual
        )
    }

    private func attach<T: Encodable>(_ value: T, name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func canonicalTarget(for gender: UserGender) -> String {
        switch gender {
        case .men: return "MEN"
        case .women: return "WOMEN"
        case .kids: return "KIDS"
        case .baby: return "BABY"
        case .unisex, .unknown: return "UNKNOWN"
        }
    }
}
