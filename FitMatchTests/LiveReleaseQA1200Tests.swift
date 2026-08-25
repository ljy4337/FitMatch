import Foundation
import XCTest
@testable import FitMatch

@MainActor
final class LiveReleaseQA1200Tests: XCTestCase {
    private struct Input: Decodable {
        let caseNumber: Int
        let source: String
        let productID: String
        let productName: String
        let productURL: String
        let shoppingMallCategory: String
        let plannedScenario: String
        let referenceSource: String
        let referenceProductID: String
        let referenceProductName: String
        let referenceProductURL: String
        let referenceShoppingMallCategory: String

        enum CodingKeys: String, CodingKey {
            case caseNumber = "case_number"
            case source
            case productID = "product_id"
            case productName = "product_name"
            case productURL = "product_url"
            case shoppingMallCategory = "shopping_mall_category"
            case plannedScenario = "planned_scenario"
            case referenceSource = "reference_source"
            case referenceProductID = "reference_product_id"
            case referenceProductName = "reference_product_name"
            case referenceProductURL = "reference_product_url"
            case referenceShoppingMallCategory = "reference_shopping_mall_category"
        }
    }

    private struct Loaded {
        let viewModel: ShoppingProductViewModel
        let product: Product
    }

    private struct Record: Encodable {
        let caseNumber: Int
        let source: String
        let productID: String
        let productName: String
        let productURL: String
        let shoppingMallCategoryPlanned: String
        let shoppingMallCategoryLive: String
        let fitMatchCategory: String
        let fitMatchDetail: String
        let referenceSource: String
        let referenceProductID: String
        let referenceProductName: String
        let referenceProductURL: String
        let referenceShoppingMallCategoryPlanned: String
        let referenceShoppingMallCategoryLive: String
        let referenceFitMatchCategory: String
        let referenceFitMatchDetail: String
        let plannedScenario: String
        let expectedOutcome: String
        let actualOutcome: String
        let targetSizeCount: Int
        let referenceSizeCount: Int
        let unavailableReason: String
        let result: String
    }

    func testSelectedTenCaseBatchOnPhysicalDevice() async throws {
        executionTimeAllowance = 600
        guard let batchValue = ProcessInfo.processInfo.environment["FITMATCH_LIVE_QA_BATCH"],
              let batchIndex = Int(batchValue),
              (0..<120).contains(batchIndex) else {
            throw XCTSkip(
                "실기기 live QA 전용 테스트입니다. FITMATCH_LIVE_QA_BATCH=0...119를 지정해 실행하세요."
            )
        }
        let bundle = Bundle(for: LiveReleaseQA1200Tests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "LiveReleaseQA1200Inputs", withExtension: "json")
        )
        let allInputs = try JSONDecoder().decode([Input].self, from: Data(contentsOf: url))
        XCTAssertEqual(allInputs.count, 1_200)
        let start = batchIndex * 10
        let inputs = Array(allInputs[start..<(start + 10)])
        var records: [Record] = []

        for input in inputs {
            let record = await execute(input)
            records.append(record)
            if record.result != "PASS" {
                XCTFail("case=\(input.caseNumber) outcome=\(record.actualOutcome) reason=\(record.unavailableReason)")
            }
            let data = try JSONEncoder().encode(record)
            print("FITMATCH_LIVE_QA_CASE \(String(decoding: data, as: UTF8.self))")
        }

        let data = try JSONEncoder().encode(records)
        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = String(format: "fitmatch-live-qa-batch-%03d.json", batchIndex + 1)
        attachment.lifetime = .keepAlways
        add(attachment)
        print("FITMATCH_LIVE_QA_BATCH batch=\(batchIndex + 1) range=\(start + 1)-\(start + 10) pass=\(records.filter { $0.result == "PASS" }.count) fail=\(records.filter { $0.result != "PASS" }.count)")
    }

    private func execute(_ input: Input) async -> Record {
        do {
            async let targetResult = load(input.productURL)
            async let referenceResult = load(input.referenceProductURL)
            let (target, reference) = try await (targetResult, referenceResult)
            let referenceItem = makeUserFit(
                reference,
                isRepresentative: input.plannedScenario != "reference_off"
            )
            let service = RecommendationService()
            let plan = service.referenceSelectionPlan(
                product: target.product,
                productDetailCategory: target.viewModel.detailCategory,
                userFits: [referenceItem]
            )
            let recommendation = service.recommend(
                product: target.product,
                userFits: [referenceItem],
                productDetailCategory: target.viewModel.detailCategory,
                allowsGlobalFallback: false
            )

            let expected: String
            let actual: String
            let passed: Bool
            switch input.plannedScenario {
            case "reference_on":
                expected = "automatic_compare"
                if plan.automaticallySelectedCandidate != nil, recommendation != nil {
                    actual = "automatic_compare"
                    passed = true
                } else if plan.requiresUserSelection {
                    actual = "manual_selection"
                    passed = false
                } else {
                    actual = "comparison_unavailable"
                    passed = false
                }
            case "reference_off":
                expected = "manual_selection"
                if plan.automaticallySelectedCandidate == nil,
                   !plan.recommendedCandidates.isEmpty,
                   recommendation != nil {
                    actual = "manual_selection"
                    passed = true
                } else if plan.automaticallySelectedCandidate != nil {
                    actual = "unexpected_automatic_compare"
                    passed = false
                } else {
                    actual = "comparison_unavailable"
                    passed = false
                }
            default:
                expected = "blocked"
                if plan.automaticallySelectedCandidate == nil,
                   plan.recommendedCandidates.isEmpty,
                   recommendation == nil {
                    actual = "blocked"
                    passed = true
                } else {
                    actual = "unexpected_comparison_available"
                    passed = false
                }
            }
            return makeRecord(
                input,
                target: target,
                reference: reference,
                expected: expected,
                actual: actual,
                reason: passed ? "" : "기준 옷 선택·비교 결과가 사전 시나리오와 다름",
                passed: passed
            )
        } catch {
            return Record(
                caseNumber: input.caseNumber,
                source: input.source,
                productID: input.productID,
                productName: input.productName,
                productURL: input.productURL,
                shoppingMallCategoryPlanned: input.shoppingMallCategory,
                shoppingMallCategoryLive: "",
                fitMatchCategory: "",
                fitMatchDetail: "",
                referenceSource: input.referenceSource,
                referenceProductID: input.referenceProductID,
                referenceProductName: input.referenceProductName,
                referenceProductURL: input.referenceProductURL,
                referenceShoppingMallCategoryPlanned: input.referenceShoppingMallCategory,
                referenceShoppingMallCategoryLive: "",
                referenceFitMatchCategory: "",
                referenceFitMatchDetail: "",
                plannedScenario: input.plannedScenario,
                expectedOutcome: expectedOutcome(input.plannedScenario),
                actualOutcome: "live_parser_failure",
                targetSizeCount: 0,
                referenceSizeCount: 0,
                unavailableReason: error.localizedDescription,
                result: "FAIL"
            )
        }
    }

    private func load(_ url: String) async throws -> Loaded {
        let viewModel = ShoppingProductViewModel(initialURL: url)
        guard await viewModel.loadProductInfoFromURL() else {
            throw NSError(
                domain: "FitMatchLiveReleaseQA",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: viewModel.errorMessage ?? "상품 분석 실패"]
            )
        }
        guard let product = viewModel.makeProductForClosetRegistration(brand: viewModel.makeBrand()) else {
            throw NSError(
                domain: "FitMatchLiveReleaseQA",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "공식 실측 상품 생성 실패"]
            )
        }
        return Loaded(viewModel: viewModel, product: product)
    }

    private func makeUserFit(_ loaded: Loaded, isRepresentative: Bool) -> UserFit {
        let product = loaded.product
        let viewModel = loaded.viewModel
        let size = product.sizes[product.sizes.count / 2]
        let item = UserFit(
            sourceType: product.sourceType,
            sourceName: product.sourceDisplayName,
            sourceCategoryPath: product.sourceCategoryPath,
            sourceCategoryDepth1: product.sourceCategoryDepth1,
            sourceCategoryDepth2: product.sourceCategoryDepth2,
            sourceCategoryDepth3: product.sourceCategoryDepth3,
            sourceCategoryDepth4: product.sourceCategoryDepth4,
            brandName: viewModel.brand,
            gender: product.productTargetGender,
            productName: product.name,
            category: product.category,
            detailCategory: viewModel.detailCategory,
            sizeName: size.name,
            measurements: size.measurements,
            fitMemo: "live-release-qa",
            satisfaction: 3,
            isRepresentative: isRepresentative,
            sourceProduct: product,
            sourceProductSize: size
        )
        item.replaceMeasurementRecords(with: size.measurementRecords)
        CanonicalComparisonProfileResolver().apply(product.canonicalProfileSnapshot, to: item)
        _ = ComparisonProfileMatcher().profile(for: item)
        return item
    }

    private func makeRecord(
        _ input: Input,
        target: Loaded,
        reference: Loaded,
        expected: String,
        actual: String,
        reason: String,
        passed: Bool
    ) -> Record {
        Record(
            caseNumber: input.caseNumber,
            source: input.source,
            productID: input.productID,
            productName: target.viewModel.productName,
            productURL: input.productURL,
            shoppingMallCategoryPlanned: input.shoppingMallCategory,
            shoppingMallCategoryLive: target.viewModel.productMetadata.sourceCategoryPath ?? "",
            fitMatchCategory: target.viewModel.category.rawValue,
            fitMatchDetail: target.viewModel.detailCategory.rawValue,
            referenceSource: input.referenceSource,
            referenceProductID: input.referenceProductID,
            referenceProductName: reference.viewModel.productName,
            referenceProductURL: input.referenceProductURL,
            referenceShoppingMallCategoryPlanned: input.referenceShoppingMallCategory,
            referenceShoppingMallCategoryLive: reference.viewModel.productMetadata.sourceCategoryPath ?? "",
            referenceFitMatchCategory: reference.viewModel.category.rawValue,
            referenceFitMatchDetail: reference.viewModel.detailCategory.rawValue,
            plannedScenario: input.plannedScenario,
            expectedOutcome: expected,
            actualOutcome: actual,
            targetSizeCount: target.product.sizes.count,
            referenceSizeCount: reference.product.sizes.count,
            unavailableReason: reason,
            result: passed ? "PASS" : "FAIL"
        )
    }

    private func expectedOutcome(_ scenario: String) -> String {
        switch scenario {
        case "reference_on": return "automatic_compare"
        case "reference_off": return "manual_selection"
        default: return "blocked"
        }
    }
}
