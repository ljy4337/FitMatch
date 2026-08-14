import Foundation
import Testing
import XCTest
@testable import FitMatch

private final class CategoryLiveComparisonBundleToken {}

@MainActor
struct MixedTopClassificationRegressionTests {
    @Test func mixedProviderBucketsDoNotOverrideExplicitProductType() throws {
        let shirtPath = "셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 긴팔"
        let shortShirtPath = "셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 반팔"
        let teePath = "영유아(6개월~5세) > 티셔츠 & 스웨트셔츠 > 티셔츠(반팔)"
        let cases: [(String, String, ClosetDetailCategory, String)] = [
            (shirtPath, "옥스포드박시셔츠", .longSleeve, "shirt"),
            (shortShirtPath, "나일론박시쇼트셔츠(5부)", .shortSleeve, "shirt"),
            (teePath, "BT PEANUTS AIRism코튼UT(그래픽T)B", .shortSleeve, "short_sleeve"),
            (teePath, "GIRLS CHIIKAWA스웨트셔츠C", .shortSleeve, "sweatshirt")
        ]

        for (path, name, initialDetail, expectedDetail) in cases {
            let result = try #require(ParsedClosetClassification.resolve(
                category: .top,
                detailCategory: initialDetail,
                sourceDepths: path.components(separatedBy: " > ").map(Optional.some),
                sourcePath: path,
                productName: name
            ))
            #expect(result.detailCode == expectedDetail, Comment(rawValue: name))
        }
    }

    @Test func sizeNormalizationPreservesShirtStructure() throws {
        let url = try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/E488520-000"))
        let info = ParsedProductInfo(
            sourceURL: url,
            brandName: "유니클로",
            productName: "옥스포드박시셔츠",
            category: .top,
            detailCategory: .shirt,
            sizes: [ParsedProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 50, chest: 60, totalLength: 75, sleeveLength: 60
                )
            )]
        )
        #expect(info.normalizedSizes().detailCategory == .shirt)
    }
}

@MainActor
@Suite(.enabled(
    if: ProcessInfo.processInfo.arguments.contains("-fitmatchRunLiveTests"),
    "유니클로 실상품 분류 회귀는 라이브 검증 스킴으로 실행합니다."
))
struct MixedTopLiveRegressionTests {
    @Test func affectedUniqloProductsUseCorrectCurrentClassification() async throws {
        let cases: [(String, String)] = [
            ("E488520", "셔츠"),
            ("E488448", "셔츠"),
            ("E488648", "반팔")
        ]
        for (id, expected) in cases {
            let info = try await ProductURLParserService().parse(
                urlString: "https://www.uniqlo.com/kr/ko/products/\(id)-000"
            )
            #expect(info.detailCategory.rawValue == expected, Comment(rawValue: id))
        }
    }
}

@MainActor
@Suite(.enabled(
    if: ProcessInfo.processInfo.arguments.contains("-fitmatchRunCategoryLiveAudit")
        || ProcessInfo.processInfo.arguments.contains("-fitmatchRunLiveTests")
        || ProcessInfo.processInfo.arguments.contains("-fitmatchRunUniqloReferenceAudit")
        || ProcessInfo.processInfo.arguments.contains("-fitmatchRunMusinsaReferenceAudit")
        || ProcessInfo.processInfo.arguments.contains("-fitmatchRunReferenceClosetSetup")
        || ProcessInfo.processInfo.environment["FITMATCH_RUN_CATEGORY_LIVE_AUDIT"] == "1"
        || ProcessInfo.processInfo.environment["FITMATCH_RUN_UNIQLO_REFERENCE_AUDIT"] == "1"
        || ProcessInfo.processInfo.environment["FITMATCH_RUN_MUSINSA_REFERENCE_AUDIT"] == "1"
        || ProcessInfo.processInfo.environment["FITMATCH_RUN_REFERENCE_CLOSET_SETUP"] == "1",
    "카테고리별 실서버 전수 비교는 명시적으로 실행합니다."
))
struct CategoryLiveComparisonAuditTests {
    private struct ReferenceManifest: Decodable {
        let candidates: [ReferenceCandidate]
    }

    private struct ReferenceCandidate: Decodable {
        let source: String
        let productID: String
        let productName: String
        let targetCategory: String
        let targetDetail: String
        let url: String

        enum CodingKeys: String, CodingKey {
            case source, url
            case productID = "product_id"
            case productName = "product_name"
            case targetCategory = "target_category"
            case targetDetail = "target_detail"
        }
    }
    private struct Manifest: Decodable {
        let products: [Input]
        let coverageGaps: [CoverageGap]

        enum CodingKeys: String, CodingKey {
            case products
            case coverageGaps = "coverage_gaps"
        }
    }

    private struct Input: Decodable {
        let source: String
        let productID: String
        let productName: String
        let expectedDetail: String
        let url: String
        let sampleKind: String

        enum CodingKeys: String, CodingKey {
            case source, url
            case productID = "product_id"
            case productName = "product_name"
            case expectedDetail = "expected_detail"
            case sampleKind = "sample_kind"
        }
    }

    private struct CoverageGap: Decodable {
        let source: String
        let expectedDetail: String
        let available: Int
        let required: Int

        enum CodingKeys: String, CodingKey {
            case source, available, required
            case expectedDetail = "expected_detail"
        }
    }

    private struct LoadedProduct {
        let input: Input
        let info: ParsedProductInfo
        let product: Product
    }

    private struct OfficialComparisonAuditRecord: Encodable {
        let audit: String
        let targetSource: String
        let targetID: String
        let targetName: String
        let targetCategory: String
        let targetDetail: String
        let targetOfficialMeasurementTable: Bool
        let targetParsingSucceeded: Bool
        let targetRegistrationAvailable: Bool
        let referenceSource: String
        let referenceID: String
        let referenceName: String
        let referenceCategory: String
        let referenceDetail: String
        let referenceOfficialMeasurementTable: Bool
        let referenceParsingSucceeded: Bool
        let referenceRegistrationAvailable: Bool
        let pairComparisonLevel: String
        let directComparisonAvailable: Bool
        let baseExtendedComparisonAvailable: Bool
        let automaticCandidateAvailable: Bool
        let automaticallySelectedReference: Bool
        let referenceSelectionRequired: Bool
        let manualExtendedComparisonAvailable: Bool
        let recommendationGenerated: Bool
        let recommendedSize: String?
        let unavailableReason: String?
        let unavailableReasonDetail: String?
        let targetHasSameDetailReference: Bool
        let automaticMatchState: String
        let uxState: String
        let nextAction: String
        let recoveryPathAvailable: Bool
    }

    private struct OfficialProductAuditRecord: Encodable {
        let audit: String
        let source: String
        let productID: String
        let manifestProductName: String
        let parsedProductName: String?
        let productURL: String
        let expectedHistoricalDetail: String
        let sampleKind: String
        let sourceCategoryPath: String?
        let parsedCategory: String?
        let parsedDetail: String?
        let finalCategoryCode: String?
        let finalDetailCode: String?
        let parsingSucceeded: Bool
        let registrationAvailable: Bool
        let officialMeasurementTableAvailable: Bool
        let sizeCount: Int
        let classificationIsValid: Bool
        let userConfirmationRequired: Bool
        let failureReason: String?
    }


    @Test(.enabled(
        if: ProcessInfo.processInfo.arguments.contains("-fitmatchRunCategoryLiveAudit")
            || ProcessInfo.processInfo.arguments.contains("-fitmatchRunLiveTests")
            || ProcessInfo.processInfo.environment["FITMATCH_RUN_CATEGORY_LIVE_AUDIT"] == "1",
        "기존 카테고리별 실서버 전수 비교는 명시적으로 실행합니다."
    ))
    func auditsEveryDirectedPairAndReferenceSize() async throws {
        let manifest = try loadManifest()
        var loaded: [LoadedProduct] = []
        var parseFailures: [(Input, String)] = []
        var classificationChanges: [(Input, String)] = []

        for (index, input) in manifest.products.enumerated() {
            do {
                let info = try await parseWithRetry(input.url, maximumAttempts: 2)
                guard !info.sizes.isEmpty else {
                    parseFailures.append((input, "no_sizes"))
                    continue
                }
                guard let product = makeProduct(info), !product.sizes.isEmpty else {
                    parseFailures.append((input, "registration_product_unavailable"))
                    continue
                }
                loaded.append(LoadedProduct(input: input, info: info, product: product))
                if input.expectedDetail != info.detailCategory.rawValue {
                    classificationChanges.append((input, info.detailCategory.rawValue))
                }
                print(
                    "CATEGORY_LIVE_PRODUCT index=\(index + 1)/\(manifest.products.count) "
                        + "source=\(input.source) id=\(input.productID) expected=\(input.expectedDetail) "
                        + "actual=\(info.detailCategory.rawValue) sizes=\(product.sizes.map(\.name).joined(separator: ","))"
                )
            } catch {
                parseFailures.append((input, error.localizedDescription))
                print("CATEGORY_LIVE_PARSE_FAILURE source=\(input.source) id=\(input.productID) error=\(error.localizedDescription)")
            }
        }

        var attempted = 0
        var allowed = 0
        var blocked = 0
        var recommended = 0
        var insufficient = 0
        var nondeterministic = 0
        var nonBestSelections = 0

        let regularGroups = Dictionary(grouping: loaded.filter { $0.input.sampleKind == "category_three" }) {
            $0.input.expectedDetail
        }.values
        let otherGroup = loaded.filter { $0.input.sampleKind == "other_focus" }
        let groups = Array(regularGroups) + [otherGroup]

        for group in groups where group.count > 1 {
            for target in group {
                for reference in group where reference.input.productID != target.input.productID
                    || reference.input.source != target.input.source {
                    for referenceSize in reference.product.sizes {
                        attempted += 1
                        let item = makeUserFit(reference, size: referenceSize)
                        let compatibility = ComparisonProfileMatcher().manualComparisonCompatibility(
                            product: target.product,
                            productDetailCategory: target.info.detailCategory,
                            item: item
                        )
                        let first = RecommendationService().recommend(
                            product: target.product,
                            selectedReferenceItem: item,
                            productDetailCategory: target.info.detailCategory
                        )
                        let second = RecommendationService().recommend(
                            product: target.product,
                            selectedReferenceItem: item,
                            productDetailCategory: target.info.detailCategory
                        )

                        if compatibility.level.isAllowed {
                            allowed += 1
                            guard let first else {
                                insufficient += 1
                                continue
                            }
                            recommended += 1
                            if first.recommendedSize.name != second?.recommendedSize.name
                                || first.recommendationScore != second?.recommendationScore {
                                nondeterministic += 1
                            }
                            let analyses = target.product.sizes.compactMap {
                                RecommendationService().analyzeSizeWithoutSaving(
                                    $0,
                                    product: target.product,
                                    referenceItem: item,
                                    productDetailCategory: target.info.detailCategory,
                                    comparisonMethod: first.comparisonMethod,
                                    excludedKinds: first.measurementExclusions
                                        .filter { $0.reason == .categoryPolicy }
                                        .map(\.kind),
                                    scorePenalty: 0
                                )
                            }
                            if let maxScore = analyses.map(\.recommendationScore).max(),
                               !analyses.contains(where: {
                                   $0.productSize.name == first.recommendedSize.name
                                       && $0.recommendationScore == maxScore
                               }) {
                                nonBestSelections += 1
                            }
                        } else {
                            blocked += 1
                            #expect(first == nil)
                            #expect(second == nil)
                        }
                    }
                }
            }
        }

        for gap in manifest.coverageGaps {
            print(
                "CATEGORY_LIVE_GAP source=\(gap.source) detail=\(gap.expectedDetail) "
                    + "available=\(gap.available) required=\(gap.required)"
            )
        }
        for (input, actual) in classificationChanges {
            print(
                "CATEGORY_LIVE_CLASSIFICATION_CHANGE source=\(input.source) id=\(input.productID) "
                    + "historical=\(input.expectedDetail) current=\(actual)"
            )
        }
        print(
            "CATEGORY_LIVE_SUMMARY selected=\(manifest.products.count) loaded=\(loaded.count) "
                + "parse_failures=\(parseFailures.count) classification_changes=\(classificationChanges.count) "
                + "attempted=\(attempted) allowed=\(allowed) blocked=\(blocked) recommended=\(recommended) "
                + "insufficient=\(insufficient) nondeterministic=\(nondeterministic) non_best=\(nonBestSelections)"
        )

        #expect(loaded.count + parseFailures.count == manifest.products.count)
        #expect(attempted > 0)
        #expect(nondeterministic == 0)
        #expect(nonBestSelections == 0)
    }

    @Test(.enabled(
        if: ProcessInfo.processInfo.arguments.contains("-fitmatchRunUniqloReferenceAudit")
            || ProcessInfo.processInfo.environment["FITMATCH_RUN_UNIQLO_REFERENCE_AUDIT"] == "1",
        "유니클로 기준 옷장 1차 감사는 명시적으로 실행합니다."
    ))
    func auditsAllProductsAgainstUniqloReferenceCloset() async throws {
        try await auditReferenceCloset(referenceSource: "uniqlo", auditName: "UNIQLO_REFERENCE")
    }

    @Test(.enabled(
        if: ProcessInfo.processInfo.arguments.contains("-fitmatchRunMusinsaReferenceAudit")
            || ProcessInfo.processInfo.environment["FITMATCH_RUN_MUSINSA_REFERENCE_AUDIT"] == "1",
        "무신사 기준 옷장 2차 감사는 명시적으로 실행합니다."
    ))
    func auditsAllProductsAgainstMusinsaReferenceCloset() async throws {
        try await auditReferenceCloset(referenceSource: "musinsa", auditName: "MUSINSA_REFERENCE")
    }

    @Test(.enabled(
        if: ProcessInfo.processInfo.arguments.contains("-fitmatchRunReferenceClosetSetup")
            || ProcessInfo.processInfo.environment["FITMATCH_RUN_REFERENCE_CLOSET_SETUP"] == "1",
        "기준 옷장 설정 검증은 명시적으로 실행합니다. 비교는 수행하지 않습니다."
    ))
    func registersOneOfficialMeasurementReferencePerStoredCategoryWithoutComparing() async throws {
        try await auditReferenceRegistrationManifest(
            resourceName: "ReferenceClosetTargetCandidates",
            auditName: "REFERENCE_SETUP"
        )
    }

    /// Probes several ranked candidates per taxonomy without claiming that a
    /// keyword-derived source listing is a usable reference garment.
    func auditReferenceRegistrationManifest(resourceName: String, auditName: String) async throws {
        let manifest = try loadReferenceManifest(resourceName: resourceName)
        let offset = max(0, Int(ProcessInfo.processInfo.environment["FITMATCH_REFERENCE_PROBE_OFFSET"] ?? "0") ?? 0)
        let requestedLimit = Int(ProcessInfo.processInfo.environment["FITMATCH_REFERENCE_PROBE_LIMIT"] ?? "0") ?? 0
        let auditCandidates: [ReferenceCandidate]
        if offset < manifest.candidates.count {
            let remaining = manifest.candidates[offset...]
            auditCandidates = requestedLimit > 0 ? Array(remaining.prefix(requestedLimit)) : Array(remaining)
        } else {
            auditCandidates = []
        }
        guard !auditCandidates.isEmpty else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        var registered: [(ReferenceCandidate, ParsedProductInfo, UserFit)] = []
        var failures: [(ReferenceCandidate, String)] = []

        for candidate in auditCandidates {
            do {
                let info = try await parseReferenceCandidateWithRetry(candidate, maximumAttempts: 2)
                guard let product = makeProduct(info), !product.sizes.isEmpty else {
                    failures.append((candidate, "registration_product_unavailable"))
                    continue
                }
                let item = makeUserFit(
                    LoadedProduct(
                        input: Input(source: candidate.source, productID: candidate.productID,
                                     productName: candidate.productName, expectedDetail: candidate.targetDetail,
                                     url: candidate.url, sampleKind: "reference_setup"),
                        info: info,
                        product: product
                    ),
                    size: representativeSize(for: product)
                )
                let classification = ParsedClosetClassification.resolve(
                    category: info.category,
                    detailCategory: info.detailCategory,
                    sourceDepths: [
                        product.sourceCategoryDepth1, product.sourceCategoryDepth2,
                        product.sourceCategoryDepth3, product.sourceCategoryDepth4
                    ],
                    sourcePath: product.sourceCategoryPath,
                    productName: info.productName
                )
                guard let classification,
                      classification.categoryCode == candidate.targetCategory,
                      classification.detailCode == candidate.targetDetail,
                      item.resolvedCategoryCode == classification.categoryCode,
                      item.resolvedDetailCategoryCode == classification.detailCode,
                      product.canonicalEligibility != false,
                      item.canonicalEligibility != false else {
                    failures.append((candidate, "stored_taxonomy_mismatch"))
                    print(
                        "\(auditName)_FAILURE source=\(candidate.source) id=\(candidate.productID) "
                            + "error=target_stored_taxonomy_or_eligibility_mismatch target=\(candidate.targetCategory)/\(candidate.targetDetail) "
                            + "parsed=\(classification?.categoryCode ?? "nil")/\(classification?.detailCode ?? "nil") "
                            + "actual=\(item.resolvedCategoryCode ?? "nil")/\(item.resolvedDetailCategoryCode ?? "nil") "
                            + "product_eligibility=\(String(describing: product.canonicalEligibility)) "
                            + "item_eligibility=\(String(describing: item.canonicalEligibility))"
                    )
                    continue
                }
                registered.append((candidate, info, item))
                print(
                    "\(auditName)_REGISTERED source=\(candidate.source) id=\(candidate.productID) "
                        + "target=\(candidate.targetCategory)/\(candidate.targetDetail) current_detail=\(info.detailCategory.rawValue) "
                        + "size=\(item.sizeName)"
                )
            } catch {
                failures.append((candidate, error.localizedDescription))
                print("\(auditName)_FAILURE source=\(candidate.source) id=\(candidate.productID) error=\(error.localizedDescription)")
            }
        }

        for source in ["uniqlo", "musinsa"] {
            let sourceRegistered = registered.filter { $0.0.source == source }
            let currentDetails = Set(sourceRegistered.map { $0.1.detailCategory.rawValue })
            print(
                "\(auditName)_SUMMARY source=\(source) candidates=\(auditCandidates.filter { $0.source == source }.count) "
                    + "registered=\(sourceRegistered.count) current_details=\(currentDetails.count)"
            )
        }
        print("\(auditName)_TOTAL offset=\(offset) candidates=\(auditCandidates.count) registered=\(registered.count) failures=\(failures.count) comparisons=0")

        #expect(registered.count + failures.count == auditCandidates.count)
        #expect(failures.isEmpty)
    }

    private func auditReferenceCloset(referenceSource: String, auditName: String) async throws {
        let manifest = try loadManifest()
        var loaded: [LoadedProduct] = []
        var parseFailures: [(Input, String)] = []

        for input in manifest.products {
            do {
                let info = try await parseInputWithOfficialMeasurement(input, maximumAttempts: 2)
                guard !info.sizes.isEmpty else {
                    parseFailures.append((input, "no_sizes"))
                    printOfficialProductRecord(
                        audit: auditName,
                        input: input,
                        info: info,
                        product: nil,
                        failureReason: "no_sizes"
                    )
                    continue
                }
                guard let product = makeProduct(info), !product.sizes.isEmpty else {
                    parseFailures.append((input, "registration_product_unavailable"))
                    printOfficialProductRecord(
                        audit: auditName,
                        input: input,
                        info: info,
                        product: nil,
                        failureReason: "registration_product_unavailable"
                    )
                    continue
                }
                loaded.append(LoadedProduct(input: input, info: info, product: product))
                printOfficialProductRecord(
                    audit: auditName,
                    input: input,
                    info: info,
                    product: product,
                    failureReason: nil
                )
            } catch {
                parseFailures.append((input, error.localizedDescription))
                printOfficialProductRecord(
                    audit: auditName,
                    input: input,
                    info: nil,
                    product: nil,
                    failureReason: error.localizedDescription
                )
                print("REFERENCE_AUDIT_PARSE_FAILURE audit=\(auditName) source=\(input.source) id=\(input.productID) error=\(error.localizedDescription)")
            }
        }

        let referenceResource = referenceSource == "uniqlo"
            ? "ReferenceClosetValidatedUniqlo"
            : "ReferenceClosetValidatedMusinsa"
        let referenceManifest = try loadReferenceManifest(resourceName: referenceResource)
        var references: [LoadedProduct] = []
        var referenceFailures: [(ReferenceCandidate, String)] = []
        for candidate in referenceManifest.candidates {
            do {
                let info = try await parseReferenceCandidateWithRetry(candidate, maximumAttempts: 2)
                guard let product = makeProduct(info), !product.sizes.isEmpty else {
                    referenceFailures.append((candidate, "registration_product_unavailable"))
                    continue
                }
                references.append(LoadedProduct(
                    input: Input(
                        source: candidate.source,
                        productID: candidate.productID,
                        productName: candidate.productName,
                        expectedDetail: candidate.targetDetail,
                        url: candidate.url,
                        sampleKind: "validated_reference"
                    ),
                    info: info,
                    product: product
                ))
            } catch {
                referenceFailures.append((candidate, error.localizedDescription))
                print("REFERENCE_AUDIT_REFERENCE_FAILURE audit=\(auditName) source=\(candidate.source) id=\(candidate.productID) error=\(error.localizedDescription)")
            }
        }

        guard !references.isEmpty else {
            Issue.record("No reference products loaded for \(referenceSource)")
            return
        }

        for reference in references {
            let size = representativeSize(for: reference.product)
            print(
                "REFERENCE_AUDIT_REFERENCE audit=\(auditName) source=\(reference.input.source) "
                    + "id=\(reference.input.productID) detail=\(reference.info.detailCategory.rawValue) size=\(size.name)"
            )
        }

        let matcher = ComparisonProfileMatcher()
        var pairCount = 0
        var strictAllowed = 0
        var manualExtended = 0
        var blocked = 0
        var recommendationFailures = 0
        var extendedRecommendationFailures = 0
        var sameDetailBlocks = 0
        var automaticNoCandidate = 0
        var automaticCandidatePairs = 0
        var automaticallySelectedPairs = 0
        var targetsWithoutSameDetailReference = 0

        for target in loaded {
            let usableReferences = references.filter {
                $0.input.source != target.input.source || $0.input.productID != target.input.productID
            }
            let referenceItems = usableReferences.map {
                let item = makeUserFit($0, size: representativeSize(for: $0.product))
                item.isRepresentative = true
                return item
            }
            let hasSameDetailReference = usableReferences.contains {
                $0.info.detailCategory == target.info.detailCategory
            }
            if !hasSameDetailReference {
                targetsWithoutSameDetailReference += 1
            }

            let automatic = matcher.match(
                product: target.product,
                productDetailCategory: target.info.detailCategory,
                userFits: referenceItems
            )
            let manualCandidates = matcher.manualCandidates(
                product: target.product,
                productDetailCategory: target.info.detailCategory,
                userFits: referenceItems
            )
            let selectionPlan = RecommendationService().referenceSelectionPlan(
                product: target.product,
                productDetailCategory: target.info.detailCategory,
                userFits: referenceItems
            )
            let automaticCandidateIDs = Set(automatic.compatibleCandidates.map(\.id))
            let automaticallySelectedID = selectionPlan.automaticallySelectedCandidate?.id
            let ux = referenceAuditUX(
                automatic: automatic,
                hasManualCandidates: !manualCandidates.isEmpty
            )
            if hasSameDetailReference && automatic.compatibleCandidates.isEmpty {
                automaticNoCandidate += 1
                print(
                    "REFERENCE_AUDIT_AUTO_NONE audit=\(auditName) target_source=\(target.input.source) "
                        + "target_id=\(target.input.productID) detail=\(target.info.detailCategory.rawValue) state=\(automatic.state)"
                )
            }

            for (index, reference) in usableReferences.enumerated() {
                pairCount += 1
                let item = referenceItems[index]
                let strict = matcher.comparisonCompatibility(
                    product: target.product,
                    productDetailCategory: target.info.detailCategory,
                    item: item
                )
                let manual = matcher.manualComparisonCompatibility(
                    product: target.product,
                    productDetailCategory: target.info.detailCategory,
                    item: item
                )
                let isAutomaticCandidate = automaticCandidateIDs.contains(item.id)
                let isAutomaticallySelected = automaticallySelectedID == item.id
                if isAutomaticCandidate { automaticCandidatePairs += 1 }
                if isAutomaticallySelected { automaticallySelectedPairs += 1 }
                let recommendation: RecommendationHistory?
                if strict.level.isAllowed || manual.level == .extended {
                    recommendation = RecommendationService().recommend(
                        product: target.product,
                        selectedReferenceItem: item,
                        productDetailCategory: target.info.detailCategory
                    )
                } else {
                    recommendation = nil
                }

                if strict.level.isAllowed {
                    strictAllowed += 1
                    if recommendation == nil {
                        recommendationFailures += 1
                        print(
                            "REFERENCE_AUDIT_RECOMMENDATION_FAILURE audit=\(auditName) target_source=\(target.input.source) "
                                + "target_id=\(target.input.productID) target_detail=\(target.info.detailCategory.rawValue) "
                                + "reference_id=\(reference.input.productID) reference_detail=\(reference.info.detailCategory.rawValue)"
                        )
                    }
                } else if manual.level == .extended {
                    manualExtended += 1
                    if recommendation == nil {
                        extendedRecommendationFailures += 1
                    }
                } else {
                    blocked += 1
                    if target.info.detailCategory == reference.info.detailCategory {
                        sameDetailBlocks += 1
                        print(
                            "REFERENCE_AUDIT_SAME_DETAIL_BLOCK audit=\(auditName) target_source=\(target.input.source) "
                                + "target_id=\(target.input.productID) detail=\(target.info.detailCategory.rawValue) "
                                + "reference_id=\(reference.input.productID) reason=\(strict.reason ?? "unknown")"
                        )
                    }
                }


                let diagnostics = matcher.candidateDiagnostics(
                    product: target.product,
                    productDetailCategory: target.info.detailCategory,
                    userFits: [item]
                ).first
                let unavailableReason = strict.level.isAllowed || manual.level == .extended
                    ? nil
                    : referenceUnavailableReason(
                        strictReason: strict.reason,
                        diagnostics: diagnostics,
                        hasSameDetailReference: hasSameDetailReference
                    )
                let pairUX = referencePairUX(
                    unavailableReason: unavailableReason,
                    fallback: ux
                )
                let record = OfficialComparisonAuditRecord(
                    audit: auditName,
                    targetSource: target.input.source,
                    targetID: target.input.productID,
                    targetName: target.info.productName,
                    targetCategory: target.product.categoryCode ?? target.info.category.serviceGroup.rawValue,
                    targetDetail: target.info.detailCategory.rawValue,
                    targetOfficialMeasurementTable: !target.product.sizes.isEmpty,
                    targetParsingSucceeded: true,
                    targetRegistrationAvailable: true,
                    referenceSource: reference.input.source,
                    referenceID: reference.input.productID,
                    referenceName: reference.info.productName,
                    referenceCategory: item.categoryCode ?? reference.info.category.serviceGroup.rawValue,
                    referenceDetail: reference.info.detailCategory.rawValue,
                    referenceOfficialMeasurementTable: !reference.product.sizes.isEmpty,
                    referenceParsingSucceeded: true,
                    referenceRegistrationAvailable: true,
                    pairComparisonLevel: String(describing: strict.level),
                    directComparisonAvailable: strict.level == .direct,
                    baseExtendedComparisonAvailable: strict.level == .extended,
                    automaticCandidateAvailable: isAutomaticCandidate,
                    automaticallySelectedReference: isAutomaticallySelected,
                    referenceSelectionRequired: selectionPlan.requiresUserSelection,
                    manualExtendedComparisonAvailable: !strict.level.isAllowed && manual.level == .extended,
                    recommendationGenerated: recommendation != nil,
                    recommendedSize: recommendation?.recommendedSize.name,
                    unavailableReason: unavailableReason,
                    unavailableReasonDetail: unavailableReason == nil ? nil : strict.reason,
                    targetHasSameDetailReference: hasSameDetailReference,
                    automaticMatchState: String(describing: automatic.state),
                    uxState: pairUX.state,
                    nextAction: pairUX.nextAction,
                    recoveryPathAvailable: true
                )
                printAuditRecord(record)
            }
        }

        print(
            "REFERENCE_AUDIT_SUMMARY audit=\(auditName) manifest=\(manifest.products.count) loaded=\(loaded.count) "
                + "parse_failures=\(parseFailures.count) references=\(references.count) reference_failures=\(referenceFailures.count) pairs=\(pairCount) "
                + "strict_allowed=\(strictAllowed) manual_extended=\(manualExtended) blocked=\(blocked) "
                + "automatic_candidate_pairs=\(automaticCandidatePairs) automatically_selected_pairs=\(automaticallySelectedPairs) "
                + "recommendation_failures=\(recommendationFailures) extended_recommendation_failures=\(extendedRecommendationFailures) "
                + "same_detail_blocks=\(sameDetailBlocks) "
                + "automatic_no_candidate=\(automaticNoCandidate) targets_without_same_detail_reference=\(targetsWithoutSameDetailReference)"
        )

        #expect(pairCount > 0)
        #expect(recommendationFailures == 0)
        #expect(extendedRecommendationFailures == 0)
    }

    private func referenceUnavailableReason(
        strictReason: String,
        diagnostics: ComparisonProfileMatcher.CandidateDiagnostic?,
        hasSameDetailReference: Bool
    ) -> String {
        if strictReason.contains("분류 검증") || strictReason.contains("옷 종류를 확인") {
            return "분류 모호: 사용자 카테고리 선택 필요"
        }
        if strictReason.contains("착용 대상") { return "성별·연령 보호 차단" }
        if strictReason.contains("착용 부위")
            || strictReason.contains("용도와 구조")
            || strictReason.contains("다른 구조") {
            return "의류 구조 불일치"
        }
        if strictReason.contains("길이 형태") { return "길이 구조 불일치" }
        if strictReason.contains("공통 핵심 실측") || strictReason.contains("공통 실측") {
            return "공통 비교 실측 부족"
        }
        guard let reasons = diagnostics?.exclusionReasons else {
            return hasSameDetailReference ? "의류 구조 불일치" : "같은 구조 기준옷 없음"
        }
        if reasons.contains("incoming_ineligible")
            || reasons.contains("candidate_ineligible")
            || reasons.contains("incoming_family_unknown") {
            return "분류 모호: 사용자 카테고리 선택 필요"
        }
        if reasons.contains("gender_incompatible") { return "성별·연령 보호 차단" }
        if reasons.contains("major_category_incompatible")
            || reasons.contains("family_incompatible")
            || reasons.contains("detail_category_incompatible")
            || reasons.contains("construction_incompatible") {
            return "의류 구조 불일치"
        }
        if reasons.contains("length_incompatible") { return "길이 구조 불일치" }
        if reasons.contains("common_measurements_insufficient") { return "공통 비교 실측 부족" }
        return hasSameDetailReference ? "의류 구조 불일치" : "같은 구조 기준옷 없음"
    }

    private func referenceAuditUX(
        automatic: AutomaticComparisonMatchResult,
        hasManualCandidates: Bool
    ) -> (state: String, nextAction: String) {
        if !automatic.compatibleCandidates.isEmpty {
            return ("자동 비교 결과", "추천 사이즈와 비교 실측 확인")
        }
        if automatic.state == .requiresConfirmation {
            return ("사용자 카테고리 선택 화면", "FitMatch 카테고리 선택")
        }
        if hasManualCandidates {
            return ("기준 옷 직접 선택", "기준옷 직접 선택 또는 유사 의류 수동 비교")
        }
        return ("직접 선택할 옷이 없어요", "다른 상품 입력")
    }

    private func referencePairUX(
        unavailableReason: String?,
        fallback: (state: String, nextAction: String)
    ) -> (state: String, nextAction: String) {
        guard let unavailableReason else { return fallback }
        if unavailableReason == "분류 모호: 사용자 카테고리 선택 필요" {
            return ("사용자 카테고리 선택 화면", "FitMatch 카테고리 선택")
        }
        if unavailableReason == "같은 구조 기준옷 없음" {
            return ("직접 선택할 옷이 없어요", "다른 상품 입력")
        }
        return fallback
    }

    private func printAuditRecord(_ record: OfficialComparisonAuditRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(record),
              let json = String(data: data, encoding: .utf8) else {
            Issue.record("Official comparison audit record encoding failed")
            return
        }
        print("OFFICIAL_COMPARISON_RECORD \(json)")
    }

    private func printOfficialProductRecord(
        audit: String,
        input: Input,
        info: ParsedProductInfo?,
        product: Product?,
        failureReason: String?
    ) {
        let classification = info.flatMap {
            ParsedClosetClassification.resolve(
                category: $0.category,
                detailCategory: $0.detailCategory,
                sourceDepths: [
                    $0.sourceCategoryDepth1,
                    $0.sourceCategoryDepth2,
                    $0.sourceCategoryDepth3,
                    $0.sourceCategoryDepth4,
                ],
                sourcePath: $0.sourceCategoryPath,
                productName: $0.productName
            )
        }
        let isValid = classification?.isValid == true
        let record = OfficialProductAuditRecord(
            audit: audit,
            source: input.source,
            productID: input.productID,
            manifestProductName: input.productName,
            parsedProductName: info?.productName,
            productURL: input.url,
            expectedHistoricalDetail: input.expectedDetail,
            sampleKind: input.sampleKind,
            sourceCategoryPath: info?.sourceCategoryPath,
            parsedCategory: info?.category.rawValue,
            parsedDetail: info?.detailCategory.rawValue,
            finalCategoryCode: classification?.categoryCode ?? product?.categoryCode,
            finalDetailCode: classification?.detailCode,
            parsingSucceeded: info != nil,
            registrationAvailable: product != nil,
            officialMeasurementTableAvailable: !(info?.sizes.isEmpty ?? true),
            sizeCount: product?.sizes.count ?? info?.sizes.count ?? 0,
            classificationIsValid: isValid,
            userConfirmationRequired: info != nil && !isValid,
            failureReason: failureReason
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(record),
              let json = String(data: data, encoding: .utf8) else {
            Issue.record("Official product audit record encoding failed")
            return
        }
        print("OFFICIAL_PRODUCT_RECORD \(json)")
    }

    private func loadManifest() throws -> Manifest {
        let bundle = Bundle(for: CategoryLiveComparisonBundleToken.self)
        let url = try #require(bundle.url(forResource: "CategoryLiveComparisonInputs", withExtension: "json"))
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    private func loadReferenceManifest(resourceName: String = "ReferenceClosetTargetCandidates") throws -> ReferenceManifest {
        let bundle = Bundle(for: CategoryLiveComparisonBundleToken.self)
        let url = try #require(bundle.url(forResource: resourceName, withExtension: "json"))
        return try JSONDecoder().decode(ReferenceManifest.self, from: Data(contentsOf: url))
    }

    private func parseWithRetry(_ url: String, maximumAttempts: Int) async throws -> ParsedProductInfo {
        var lastError: Error?
        for attempt in 1...maximumAttempts {
            do {
                return try await ProductURLParserService().parse(urlString: url)
            } catch {
                lastError = error
                if attempt < maximumAttempts {
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
        throw lastError ?? ProductURLParserError.automaticParsingUnavailable
    }

    /// Reference garments must have an official numeric table. For the
    /// Musinsa probe, deliberately stop at its actual-size API instead of
    /// triggering the user-facing image-OCR recovery path; that recovery is
    /// valuable in the app but makes a catalog audit unbounded and would turn
    /// an unavailable official table into a misleading test timeout.
    private func parseReferenceCandidateWithRetry(
        _ candidate: ReferenceCandidate,
        maximumAttempts: Int
    ) async throws -> ParsedProductInfo {
        var lastError: Error?
        for attempt in 1...maximumAttempts {
            do {
                if candidate.source == "musinsa" {
                    guard let url = URL(string: candidate.url) else {
                        throw ProductURLParserError.invalidURL
                    }
                    return try await MusinsaActualSizeAPIParser().parse(from: url).normalizedSizes()
                }
                return try await ProductURLParserService().parse(urlString: candidate.url)
            } catch {
                lastError = error
                if attempt < maximumAttempts {
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
        throw lastError ?? ProductURLParserError.automaticParsingUnavailable
    }

    private func parseInputWithOfficialMeasurement(
        _ input: Input,
        maximumAttempts: Int
    ) async throws -> ParsedProductInfo {
        var lastError: Error?
        for attempt in 1...maximumAttempts {
            do {
                if input.source == "musinsa" {
                    guard let url = URL(string: input.url) else {
                        throw ProductURLParserError.invalidURL
                    }
                    return try await MusinsaActualSizeAPIParser().parse(from: url).normalizedSizes()
                }
                return try await ProductURLParserService().parse(urlString: input.url)
            } catch {
                lastError = error
                if attempt < maximumAttempts {
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
        throw lastError ?? ProductURLParserError.automaticParsingUnavailable
    }

    private func makeProduct(_ info: ParsedProductInfo) -> Product? {
        let viewModel = ShoppingProductViewModel(initialURL: info.sourceURL.absoluteString)
        viewModel.apply(info)
        return viewModel.makeProductForClosetRegistration(brand: viewModel.makeBrand())
    }

    private func makeUserFit(_ loaded: LoadedProduct, size: ProductSize) -> UserFit {
        let info = loaded.info
        let product = loaded.product
        let item = UserFit(
            sourceType: product.sourceType,
            sourceName: product.sourceDisplayName,
            sourceCategoryPath: product.sourceCategoryPath,
            sourceCategoryDepth1: product.sourceCategoryDepth1,
            sourceCategoryDepth2: product.sourceCategoryDepth2,
            sourceCategoryDepth3: product.sourceCategoryDepth3,
            sourceCategoryDepth4: product.sourceCategoryDepth4,
            brandName: info.brandName,
            gender: UserGender.productTarget(from: info.productMetadata.genderCodes),
            productName: info.productName,
            category: info.category,
            detailCategory: info.detailCategory,
            sizeName: size.name,
            measurements: size.measurements,
            fitMemo: "category-live-audit",
            satisfaction: 3,
            sourceProduct: product,
            sourceProductSize: size
        )
        item.replaceMeasurementRecords(with: size.measurementRecords)
        if let classification = ParsedClosetClassification.resolve(
            category: info.category,
            detailCategory: info.detailCategory,
            sourceDepths: [
                product.sourceCategoryDepth1, product.sourceCategoryDepth2,
                product.sourceCategoryDepth3, product.sourceCategoryDepth4
            ],
            sourcePath: product.sourceCategoryPath,
            productName: info.productName
        ) {
            item.categoryCode = classification.categoryCode
            item.detailCategoryCode = classification.detailCode
            item.garmentType = classification.garmentFamily
            item.sleeveType = classification.lengthType
            item.constructionType = classification.constructionType
        }
        CanonicalComparisonProfileResolver().apply(product.canonicalProfileSnapshot, to: item)
        _ = ComparisonProfileMatcher().profile(for: item)
        return item
    }

    private func representativeSize(for product: Product) -> ProductSize {
        product.sizes[product.sizes.count / 2]
    }
}

/// Xcode's `-only-testing` filter does not select the Swift Testing member above
/// on this toolchain. Keep this XCTest bridge so the live, networked reference
/// registration audit can be executed in isolation from unrelated test suites.
@MainActor
final class ReferenceClosetSetupXCTests: XCTestCase {
    func testOfficialMeasurementReferenceRegistration() async throws {
        try await CategoryLiveComparisonAuditTests()
            .registersOneOfficialMeasurementReferencePerStoredCategoryWithoutComparing()
    }

    func testUniqloReferenceCandidateProbe() async throws {
        try await CategoryLiveComparisonAuditTests().auditReferenceRegistrationManifest(
            resourceName: "ReferenceClosetUniqloProbeCandidates",
            auditName: "UNIQLO_REFERENCE_PROBE"
        )
    }

    func testMusinsaReferenceCandidateProbe() async throws {
        try await CategoryLiveComparisonAuditTests().auditReferenceRegistrationManifest(
            resourceName: "ReferenceClosetMusinsaProbeCandidates",
            auditName: "MUSINSA_REFERENCE_PROBE"
        )
    }

    func testUniqloExpandedReferenceCandidateProbe() async throws {
        try await CategoryLiveComparisonAuditTests().auditReferenceRegistrationManifest(
            resourceName: "ReferenceClosetUniqloExpandedProbeCandidates",
            auditName: "UNIQLO_EXPANDED_REFERENCE_PROBE"
        )
    }

    func testMusinsaExpandedReferenceCandidateProbe() async throws {
        try await CategoryLiveComparisonAuditTests().auditReferenceRegistrationManifest(
            resourceName: "ReferenceClosetMusinsaExpandedProbeCandidates",
            auditName: "MUSINSA_EXPANDED_REFERENCE_PROBE"
        )
    }

    func testUniqloLiveDiscoveryReferenceCandidateProbe() async throws {
        try await CategoryLiveComparisonAuditTests().auditReferenceRegistrationManifest(
            resourceName: "ReferenceClosetUniqloLiveDiscoveryProbeCandidates",
            auditName: "UNIQLO_LIVE_DISCOVERY_REFERENCE_PROBE"
        )
    }

    func testMusinsaDeepReferenceCandidateProbe() async throws {
        try await CategoryLiveComparisonAuditTests().auditReferenceRegistrationManifest(
            resourceName: "ReferenceClosetMusinsaDeepProbeCandidates",
            auditName: "MUSINSA_DEEP_REFERENCE_PROBE"
        )
    }

    func testMusinsaEligibleReplacementReferenceCandidateProbe() async throws {
        try await CategoryLiveComparisonAuditTests().auditReferenceRegistrationManifest(
            resourceName: "ReferenceClosetMusinsaEligibleReplacementProbeCandidates",
            auditName: "MUSINSA_ELIGIBLE_REPLACEMENT_PROBE"
        )
    }

    func testRemainingLocalOfficialReferenceCandidateProbe() async throws {
        try await CategoryLiveComparisonAuditTests().auditReferenceRegistrationManifest(
            resourceName: "ReferenceClosetRemainingLocalOfficialProbeCandidates",
            auditName: "REMAINING_LOCAL_OFFICIAL_REFERENCE_PROBE"
        )
    }

    func testComparisonClassificationBoundaryPolicy() throws {
        let tests = FitMatchTests()
        tests.singleExactRepresentativeForUserResolvedCategoryIsAutomaticallySelected()
        tests.multipleCompatibleRepresentativesSelectDeterministically()
        tests.singleCompatibleNonReferenceStillRequiresUserSelection()
        tests.similarReferenceCandidatesRequireUserSelection()
        tests.differentShortTopStructureShowsManualExpansionNotice()
        tests.userCategoryChoiceIsReusedForTheExactProviderProductOnly()
        try tests.poloUsesTshirtFamilyAndAutomaticallyMatchesSameLengthTshirt()
        tests.poloDoesNotAutomaticallyCompareWithWovenShirt()
    }

    func testUniqloReferenceCrossPlatformComparison() async throws {
        try await CategoryLiveComparisonAuditTests()
            .auditsAllProductsAgainstUniqloReferenceCloset()
    }

    func testMusinsaReferenceCrossPlatformComparison() async throws {
        try await CategoryLiveComparisonAuditTests()
            .auditsAllProductsAgainstMusinsaReferenceCloset()
    }

    func testAnorakPantsRetainsBottomTaxonomy() throws {
        let classification = try XCTUnwrap(ParsedClosetClassification.resolve(
            category: .pants,
            detailCategory: .longPants,
            sourceDepths: ["스포츠/레저", "하의", "일자 팬츠"],
            sourcePath: "스포츠/레저 > 하의 > 일자 팬츠",
            productName: "테크라인 립포켓 아노락 팬츠 라이트그레이"
        ))

        XCTAssertEqual(classification.categoryCode, "bottoms")
        XCTAssertEqual(classification.detailCode, "long_pants")
    }

    func testOfficialTopTaxonomyIsNotOverriddenByOuterwearName() throws {
        let classification = try XCTUnwrap(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .longSleeve,
            sourceDepths: ["상의", "긴소매 티셔츠"],
            sourcePath: "상의 > 긴소매 티셔츠",
            productName: "라이트 바람막이 재킷"
        ))

        XCTAssertEqual(classification.categoryCode, "tops")
        XCTAssertEqual(classification.detailCode, "long_sleeve")
    }

    func testOuterwearNameCanResolveMissingOfficialMajorCategory() throws {
        let classification = try XCTUnwrap(ParsedClosetClassification.resolve(
            category: .other,
            detailCategory: .other,
            sourceDepths: ["의류", "기타"],
            sourcePath: "의류 > 기타",
            productName: "라이트 바람막이 재킷"
        ))

        XCTAssertEqual(classification.categoryCode, "outerwear")
        XCTAssertEqual(classification.detailCode, "windbreaker")
    }

    func testUniqloMixedKnitBucketKeepsSpecificKnitLeaf() throws {
        let parser = UniqloProductMetadataParser()
        let evidence = "니트 & 가디건 > 니트 메리노크루넥스웨터"
        let providerCategory = parser.mapCategory(from: evidence)
        let providerDetail = parser.mapDetailCategory(from: evidence)
        let classification = try XCTUnwrap(ParsedClosetClassification.resolve(
            category: providerCategory,
            detailCategory: providerDetail,
            sourceDepths: ["니트 & 가디건", "니트"],
            sourcePath: "니트 & 가디건 > 니트",
            productName: "메리노크루넥스웨터"
        ))

        XCTAssertEqual(providerCategory, .knit)
        XCTAssertEqual(providerDetail, .knitTop)
        XCTAssertEqual(classification.categoryCode, "tops")
        XCTAssertEqual(classification.detailCode, "knit_top")
    }

    func testUniqloMixedKnitBucketKeepsExplicitCardiganProduct() throws {
        let parser = UniqloProductMetadataParser()
        let evidence = "니트 & 가디건 > 니트 메리노V넥가디건"
        let providerCategory = parser.mapCategory(from: evidence)
        let providerDetail = parser.mapDetailCategory(from: evidence)
        let classification = try XCTUnwrap(ParsedClosetClassification.resolve(
            category: providerCategory,
            detailCategory: providerDetail,
            sourceDepths: ["니트 & 가디건", "니트"],
            sourcePath: "니트 & 가디건 > 니트",
            productName: "메리노V넥가디건"
        ))

        XCTAssertEqual(providerCategory, .outer)
        XCTAssertEqual(providerDetail, .cardigan)
        XCTAssertEqual(classification.categoryCode, "outerwear")
        XCTAssertEqual(classification.detailCode, "cardigan")
    }

    func testExplicitSweatshirtCanResolveMissingOfficialMajorCategory() throws {
        let classification = try XCTUnwrap(ParsedClosetClassification.resolve(
            category: .other,
            detailCategory: .sweatshirt,
            sourceDepths: ["Special Collaborations", "UNIQLO : C"],
            sourcePath: "Special Collaborations > UNIQLO : C",
            productName: "스웨트하프집풀오버"
        ))

        XCTAssertEqual(classification.categoryCode, "tops")
        XCTAssertEqual(classification.detailCode, "sweatshirt")
    }

    func testPlaceholderOtherClassificationIsNotAutoConfirmable() throws {
        let classification = try XCTUnwrap(ParsedClosetClassification.resolve(
            category: .other,
            detailCategory: .other,
            sourceDepths: ["Special Collaborations", "UNIQLO and JW ANDERSON"],
            sourcePath: "Special Collaborations > UNIQLO and JW ANDERSON",
            productName: "바이컬러T"
        ))

        XCTAssertFalse(classification.isValid)
    }

    func testUniqloSweatFullZipParkaIsJumperNotPadding() throws {
        let parser = UniqloProductMetadataParser()
        let sourcePath = "티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트파카"
        let name = "KIDS드라이스웨트풀집파카(컬러블록)"
        let classification = try XCTUnwrap(ParsedClosetClassification.resolve(
            category: parser.mapCategory(from: sourcePath),
            detailCategory: parser.mapDetailCategory(from: "\(sourcePath) \(name)"),
            sourceDepths: sourcePath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: sourcePath,
            productName: name
        ))

        XCTAssertEqual(classification.categoryCode, "outerwear")
        XCTAssertEqual(classification.detailCode, "jumper")
    }

    func testUniqloMixedPantsAndLeggingsBucketKeepsTerminalPants() throws {
        let parser = UniqloProductMetadataParser()
        let fixtures: [(path: String, name: String, detail: String)] = [
            (
                "UV Protection > 팬츠 & 레깅스 > 팬츠",
                "울트라스트레치액티브와이드팬츠",
                "long_pants"
            ),
            (
                "영유아(6개월~5세) > 레깅스 & 팬츠 > 쇼트팬츠",
                "BT이지쇼트팬츠(트윌)",
                "shorts"
            ),
        ]

        for fixture in fixtures {
            let classification = try XCTUnwrap(ParsedClosetClassification.resolve(
                category: parser.mapCategory(from: fixture.path),
                detailCategory: parser.mapDetailCategory(from: "\(fixture.path) \(fixture.name)"),
                sourceDepths: fixture.path.components(separatedBy: " > ").map(Optional.some),
                sourcePath: fixture.path,
                productName: fixture.name
            ))

            XCTAssertEqual(classification.categoryCode, "bottoms")
            XCTAssertEqual(classification.detailCode, fixture.detail)
        }

        let leggingsPath = "팬츠 > 레깅스 > 울트라 스트레치"
        let leggings = try XCTUnwrap(ParsedClosetClassification.resolve(
            category: parser.mapCategory(from: leggingsPath),
            detailCategory: parser.mapDetailCategory(
                from: "\(leggingsPath) 울트라스트레치액티브레깅스"
            ),
            sourceDepths: leggingsPath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: leggingsPath,
            productName: "울트라스트레치액티브레깅스"
        ))
        XCTAssertEqual(leggings.categoryCode, "leggings")
        XCTAssertEqual(leggings.detailCode, "long_leggings")
    }

    func testExplicitCompositeGarmentSetsRequireUserConfirmation() throws {
        let fixtures = [
            ("SWEET DREAM LACE PAJAMA SET_PINK", "바지 > 점프 슈트/오버올"),
            ("Jenny Soft Drape Blouse&Pants Set-up (Shadow Black)", "바지 > 점프 슈트/오버올"),
        ]
        for (name, sourcePath) in fixtures {
            XCTAssertNil(ParsedClosetClassification.resolve(
                category: .bottom,
                detailCategory: .other,
                sourceDepths: sourcePath.components(separatedBy: " > ").map(Optional.some),
                sourcePath: sourcePath,
                productName: name
            ))
        }

        XCTAssertNotNil(ParsedClosetClassification.resolve(
            category: .bottom,
            detailCategory: .leggings,
            sourceDepths: ["영유아(6개월~5세)", "레깅스 & 팬츠", "레깅스"],
            sourcePath: "영유아(6개월~5세) > 레깅스 & 팬츠 > 레깅스",
            productName: "BT레깅스(셋업가능)"
        ))
    }
}
