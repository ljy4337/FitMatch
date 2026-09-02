//
//  FitMatchTests.swift
//  FitMatchTests
//
//  Created by 이진영 on 7/3/26.
//

import Testing
import XCTest
import UIKit
import SwiftData
@testable import FitMatch

private final class FitMatchCorpusBundleToken {}

private let runsLongImageAudit =
    ProcessInfo.processInfo.arguments.contains("-fitmatchRunLongImageAudit")
    || ProcessInfo.processInfo.environment["FITMATCH_RUN_LONG_IMAGE_AUDIT"] == "1"

private let runsFitPairCorpusAudit =
    ProcessInfo.processInfo.arguments.contains("-fitmatchRunFitPairCorpusAudit")
    || ProcessInfo.processInfo.environment["FITMATCH_RUN_FIT_PAIR_CORPUS_AUDIT"] == "1"

@MainActor
@Suite(.serialized)
struct FitMatchTests {
    @Test func comparisonLengthDisplayUsesGarmentContext() {
        #expect(ComparisonLengthType.long.displayName(for: .pants) == "긴바지")
        #expect(ComparisonLengthType.short.displayName(for: .pants) == "반바지")
        #expect(ComparisonLengthType.long.displayName(for: .leggings) == "롱 레깅스")
        #expect(ComparisonLengthType.long.displayName(for: .shirt) == "긴팔")
    }

    @Test func productTargetTreatsCombinedAdultProviderCodesAsUnisex() {
        #expect(UserGender.productTarget(from: ["M", "W"]) == .unisex)
        #expect(UserGender.productTarget(from: ["MEN", "WOMEN"]) == .unisex)
        #expect(UserGender.productTarget(from: ["W"]) == .women)
        #expect(UserGender.productTarget(from: ["M"]) == .men)
    }

    @Test func parserServiceRejectsUnsupportedHostsWithoutCallingProviderParsers() async {
        let musinsa = ProductURLParserSpy(canParse: false)
        let uniqlo = ProductURLParserSpy(canParse: false)
        let service = ProductURLParserService(musinsaParser: musinsa, uniqloParser: uniqlo)

        do {
            _ = try await service.parse(urlString: "https://example.com/products/1")
            Issue.record("지원하지 않는 URL이 파싱에 성공했습니다.")
        } catch let error as ProductURLParserError {
            guard case .unsupportedURL = error else {
                Issue.record("unsupportedURL이 아닌 오류가 반환됐습니다: \(error)")
                return
            }
        } catch {
            Issue.record("예상하지 못한 오류가 반환됐습니다: \(error)")
        }

        #expect(musinsa.parseCallCount == 0)
        #expect(uniqlo.parseCallCount == 0)
    }

    @Test func parserServiceDoesNotRouteFailedMusinsaRequestToAnotherProvider() async {
        let musinsa = ProductURLParserSpy(canParse: true, result: .failure(ParserSpyError.failed))
        let uniqlo = ProductURLParserSpy(canParse: false)
        let service = ProductURLParserService(musinsaParser: musinsa, uniqloParser: uniqlo)

        do {
            _ = try await service.parse(urlString: "https://www.musinsa.com/products/123")
            Issue.record("실패하도록 설정한 무신사 파서가 성공했습니다.")
        } catch let error as ProductURLParserError {
            guard case .automaticParsingUnavailable = error else {
                Issue.record("automaticParsingUnavailable이 아닌 오류가 반환됐습니다: \(error)")
                return
            }
        } catch {
            Issue.record("예상하지 못한 오류가 반환됐습니다: \(error)")
        }

        #expect(musinsa.parseCallCount == 1)
        #expect(uniqlo.parseCallCount == 0)
    }

    @Test func cancelledProductLoadCannotApplyLateParserResult() async {
        let parser = DelayedProductURLParserSpy(delays: ["cancelled": 80_000_000])
        let service = ProductURLParserService(musinsaParser: parser, uniqloParser: parser)
        let viewModel = ShoppingProductViewModel(
            initialURL: "https://www.musinsa.com/products/cancelled",
            parserService: service
        )

        let loadTask = Task { await viewModel.loadProductInfoFromURL() }
        await waitUntilParserStarts(parser)
        viewModel.cancelProductLoading()

        #expect(await loadTask.value == false)
        #expect(viewModel.hasLoadedProductInfo == false)
        #expect(viewModel.productName.isEmpty)
        #expect(viewModel.isLoadingProductInfo == false)
    }

    @Test func latestProductLoadOwnsViewModelState() async {
        let parser = DelayedProductURLParserSpy(delays: [
            "first": 120_000_000,
            "second": 5_000_000
        ])
        let service = ProductURLParserService(musinsaParser: parser, uniqloParser: parser)
        let viewModel = ShoppingProductViewModel(
            initialURL: "https://www.musinsa.com/products/first",
            parserService: service,
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(
                remote: FitMatchEchoServerAuthorityRemote()
            )
        )

        let firstTask = Task { await viewModel.loadProductInfoFromURL() }
        await waitUntilParserStarts(parser)

        viewModel.productURL = "https://www.musinsa.com/products/second"
        let secondTask = Task { await viewModel.loadProductInfoFromURL() }

        #expect(await secondTask.value)
        #expect(await firstTask.value == false)
        #expect(viewModel.productName == "second")
        #expect(viewModel.productURL.hasSuffix("/second"))
        #expect(viewModel.isLoadingProductInfo == false)
    }

    @Test func musinsaTopBottomSetIsExplicitlyUnsupported() {
        #expect(MusinsaUnsupportedProductPolicy.isTopBottomSet(
            categoryDepth2Name: "상하의세트"
        ))
        #expect(MusinsaUnsupportedProductPolicy.isTopBottomSet(
            categoryDepth2Name: " 상하의 세트 "
        ))
        #expect(!MusinsaUnsupportedProductPolicy.isTopBottomSet(
            categoryDepth2Name: "트레이닝 세트"
        ))
        #expect(!MusinsaUnsupportedProductPolicy.isTopBottomSet(
            categoryDepth2Name: "반소매 티셔츠"
        ))
        #expect(!MusinsaUnsupportedProductPolicy.isTopBottomSet(
            categoryDepth2Name: nil
        ))
    }

    @Test func sizeTableRecoveryRejectsDuplicateSizeNames() {
        let forms = [
            ClothingSizeForm(sizeName: "M", chest: "52", totalLength: "68"),
            ClothingSizeForm(sizeName: " m ", chest: "54", totalLength: "70")
        ]

        #expect(SizeTableRecoveryValidator.validationMessage(
            for: forms,
            category: .top,
            detailCategory: .shortSleeve
        ) == "중복된 사이즈명은 저장할 수 없습니다.")
    }

    @Test func sizeTableRecoveryRejectsEmptyAndMeasurementlessRows() {
        #expect(SizeTableRecoveryValidator.validationMessage(
            for: [ClothingSizeForm(sizeName: "", chest: "52", totalLength: "68")],
            category: .top,
            detailCategory: .shortSleeve
        ) == "모든 행에 사이즈명을 입력해 주세요.")

        #expect(SizeTableRecoveryValidator.validationMessage(
            for: [ClothingSizeForm(sizeName: "M")],
            category: .top,
            detailCategory: .shortSleeve
        ) == "각 사이즈 행에 비교 가능한 치수를 입력해 주세요.")
    }

    @Test func sizeTableRecoveryAcceptsExistingSupportedMeasurements() {
        let forms = [
            ClothingSizeForm(sizeName: "S", chest: "50", totalLength: "66"),
            ClothingSizeForm(sizeName: "M", chest: "52", totalLength: "68")
        ]

        #expect(SizeTableRecoveryValidator.validationMessage(
            for: forms,
            category: .top,
            detailCategory: .shortSleeve
        ) == nil)
    }

    @Test func sizeTableRecoveryContextDistinguishesCandidateStates() {
        let candidates = SizeTableRecoveryContext(
            failure: .imageCandidatesAvailable,
            imageURLStrings: ["https://example.com/size.jpg"]
        )
        let empty = SizeTableRecoveryContext(
            failure: .noImageCandidates,
            imageURLStrings: []
        )

        #expect(candidates.failure == .imageCandidatesAvailable)
        #expect(candidates.imageURLStrings.count == 1)
        #expect(empty.failure == .noImageCandidates)
        #expect(empty.imageURLStrings.isEmpty)
        #expect(SizeTableRecoveryFeature.isEnabled)
    }


    @Test func taxonomyCodesAndParentsAreValidAndDeterministic() throws {
        let taxonomy = FitMatchTaxonomyProvider.shared.taxonomy
        #expect(Set(taxonomy.genders.map(\.code)).count == taxonomy.genders.count)
        #expect(Set(taxonomy.categories.map(\.code)).count == taxonomy.categories.count)
        #expect(taxonomy.categories.allSatisfy { category in
            Set(category.details.map(\.code)).count == category.details.count
        })
        #expect(taxonomy.normalizedProductTypes.allSatisfy { type in
            taxonomy.categories.contains { $0.code == type.categoryCode }
        })

        let active = FitMatchTaxonomyProvider.shared.activeCategories
        #expect(active == active.sorted { ($0.sortOrder, $0.code) < ($1.sortOrder, $1.code) })
        #expect(active.allSatisfy { $0.isActive })
    }

    @Test func requiredAtomicTaxonomyOptionsExist() {
        let provider = FitMatchTaxonomyProvider.shared
        #expect(Set(provider.activeDetails(categoryCode: "tops").map(\.code)).isSuperset(of: [
            "sleeveless", "short_sleeve", "three_quarter_sleeve", "long_sleeve",
            "shirt", "blouse", "knit_top", "sweatshirt", "hoodie"
        ]))
        #expect(!provider.isValidDetail("other_tops", for: "tops"))
        #expect(Set(provider.activeDetails(categoryCode: "bottoms").map(\.code)).isSuperset(of: [
            "short_pants", "shorts", "cropped_pants", "three_quarter_pants", "nine_tenths_pants", "long_pants"
        ]))
        #expect(Set(provider.activeDetails(categoryCode: "outerwear").map(\.code)).isSuperset(of: [
            "jacket", "blazer", "jumper", "blouson", "vest", "padded_vest"
        ]))
    }

    @Test func inactiveTaxonomyOptionsAreHidden() throws {
        let taxonomy = FitMatchTaxonomy(
            schemaVersion: 1,
            taxonomyVersion: "test",
            genders: [
                .init(code: "male", displayName: "남성", sortOrder: 0, isActive: true),
                .init(code: "unknown", displayName: "미분류", sortOrder: 1, isActive: false)
            ],
            categories: [
                .init(code: "tops", displayName: "상의", sortOrder: 0, isActive: true, details: [
                    .init(code: "short_sleeve", displayName: "반팔", sortOrder: 0, isActive: true),
                    .init(code: "retired", displayName: "종료", sortOrder: 1, isActive: false)
                ])
            ],
            normalizedProductTypes: [],
            legacyAliases: []
        )
        let provider = FitMatchTaxonomyProvider(
            repository: DataFitMatchTaxonomyRepository(data: try JSONEncoder().encode(taxonomy))
        )

        #expect(provider.selectableGenders.map(\.code) == ["male"])
        #expect(provider.activeDetails(categoryCode: "tops").map(\.code) == ["short_sleeve"])
    }

    @Test func categoryChangeRejectsInvalidDetail() {
        let provider = FitMatchTaxonomyProvider.shared
        #expect(provider.isValidDetail("short_sleeve", for: "tops"))
        #expect(!provider.isValidDetail("short_sleeve", for: "bottoms"))
    }

    @Test func legacyKoreanTaxonomyAliasesMapWithoutOverwritingSnapshots() {
        let provider = FitMatchTaxonomyProvider.shared
        #expect(provider.genderCode(for: "남성") == "male")
        #expect(provider.genderCode(for: "여성") == "female")
        #expect(provider.genderCode(for: "공용") == "unisex")
        #expect(provider.genderCode(for: "키즈") == "kids_unisex")
        #expect(provider.genderCode(for: "남아") == "boys")
        #expect(provider.genderCode(for: "여아") == "girls")
        #expect(provider.genderCode(for: "키즈 공용") == "kids_unisex")
        #expect(provider.detailCode(for: "반팔 티셔츠", categoryCode: "tops") == "short_sleeve")
        #expect(provider.detailCode(for: "긴팔티", categoryCode: "tops") == "long_sleeve")
        #expect(provider.detailCode(for: "반바지", categoryCode: "bottoms") == "shorts")
    }

    @Test func invalidTaxonomyUsesControlledFallback() {
        let provider = FitMatchTaxonomyProvider(
            repository: DataFitMatchTaxonomyRepository(data: Data("not-json".utf8))
        )
        #expect(provider.loadingError != nil)
        #expect(!provider.activeCategories.isEmpty)
    }

    @Test func normalizedProductTypeDoesNotSplitReferenceGarmentScope() {
        let tshirt = comparisonUserFit(name: "반팔 티셔츠", sourceCategory: "상의 > 반소매 티셔츠", detail: .shortSleeve, sleeve: 24)
        let knit = comparisonUserFit(name: "반팔 니트", sourceCategory: "상의 > 니트/스웨터", detail: .shortSleeve, sleeve: 24)
        tshirt.normalizedProductTypeCode = "tops.tshirt"
        knit.normalizedProductTypeCode = "tops.knit_sweater"

        #expect(ReferenceGarmentPolicy.conflicts(tshirt, knit))
    }

    @Test func referenceGarmentScopeKeepsDifferentGenderOrDetail() {
        let maleShort = comparisonUserFit(name: "남성 반팔", detail: .shortSleeve, sleeve: 24)
        maleShort.gender = .men
        let femaleShort = comparisonUserFit(name: "여성 반팔", detail: .shortSleeve, sleeve: 24)
        femaleShort.gender = .women
        let maleLong = comparisonUserFit(name: "남성 긴팔", detail: .longSleeve, sleeve: 60)
        maleLong.gender = .men

        #expect(!ReferenceGarmentPolicy.conflicts(maleShort, femaleShort))
        #expect(!ReferenceGarmentPolicy.conflicts(maleShort, maleLong))
    }

    @Test func musinsaActualSizeLengthPreservesKnitFamily() {
        var metadata = MusinsaProductMetadata(
            sourceURL: URL(string: "https://www.musinsa.com/products/4668060")!,
            productID: "4668060",
            brandName: "무신사",
            productName: "루이 니트 - 다크 네이비",
            category: .knit,
            detailCategory: .knitTop,
            categoryDepth1Name: "상의",
            categoryDepth2Name: "니트/스웨터"
        )

        metadata.applyActualSizeTypeName("긴소매티셔츠")

        #expect(metadata.category == .knit)
        #expect(metadata.detailCategory == .longSleeve)
    }

    @Test func shortSleeveSourceHistoryDoesNotOverrideDetectedLongSleeve() {
        let sourceCategory = "상의 > 니트/스웨터 > \(UUID().uuidString)"
        let product = comparisonProduct(
            name: "루이 니트 - 다크 네이비",
            category: .knit,
            sourceCategory: sourceCategory,
            sleeve: 70
        )
        let shortSleeveHistory = comparisonUserFit(
            name: "반팔 니트",
            sourceCategory: sourceCategory,
            detail: .shortSleeve,
            sleeve: 24
        )
        SourceCategoryHistoryMatcher.saveMapping(
            for: product,
            category: .top,
            detailCategory: .shortSleeve
        )

        let matches = SourceCategoryHistoryMatcher.matches(
            for: product,
            detectedDetailCategory: .longSleeve,
            userFits: [shortSleeveHistory]
        )

        #expect(matches.isEmpty)
    }

    @Test func userCategoryChoiceIsReusedForTheExactProviderProductOnly() {
        let sourceCategory = "상의 > 기타 상의 > \(UUID().uuidString)"
        let selectedProduct = comparisonProduct(
            name: "모호한 첫 상품",
            sourceCategory: sourceCategory,
            sleeve: 60
        )
        selectedProduct.productCode = "selected-\(UUID().uuidString)"
        let anotherProduct = comparisonProduct(
            name: "같은 공급사 경로의 다른 상품",
            sourceCategory: sourceCategory,
            sleeve: 60
        )
        anotherProduct.productCode = "other-\(UUID().uuidString)"

        SourceCategoryHistoryMatcher.saveMapping(
            for: selectedProduct,
            category: .shirt,
            detailCategory: .shirt
        )

        let exactMatches = SourceCategoryHistoryMatcher.matches(
            for: selectedProduct,
            detectedDetailCategory: .other,
            userFits: []
        )
        let otherMatches = SourceCategoryHistoryMatcher.matches(
            for: anotherProduct,
            detectedDetailCategory: .other,
            userFits: []
        )

        #expect(exactMatches.map(\.detailCategory) == [.shirt])
        #expect(otherMatches.isEmpty)
    }

    @Test func explicitCurrentClassificationOverridesConflictingStoredProductChoice() {
        let defaultsKey = "FitMatch.sourceCategoryMappings"
        let previousMappings = UserDefaults.standard.data(forKey: defaultsKey)
        defer {
            if let previousMappings {
                UserDefaults.standard.set(previousMappings, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }

        let product = Product(
            name: "분류가 충돌하는 상품",
            category: .top,
            productCode: "user-authority-conflict",
            metadata: ProductMetadata(sourceCategoryPath: "상의 > 기타 상의"),
            sourceName: "무신사",
            sizes: []
        )
        SourceCategoryHistoryMatcher.saveMapping(
            for: product,
            category: .bottom,
            detailCategory: .longPants
        )

        let matches = SourceCategoryHistoryMatcher.matches(
            for: product,
            detectedDetailCategory: .longSleeve,
            userFits: []
        )

        #expect(matches.isEmpty)
    }

    @Test func uniqloUnknownOfficialPathDoesNotDefaultToTops() {
        let parser = UniqloProductMetadataParser()

        #expect(parser.mapCategory(from: "의류 > 기타") == .other)
        #expect(parser.mapCategory(from: "") == .other)
        #expect(parser.mapCategory(from: "상의 > 긴소매 티셔츠") == .top)
        #expect(parser.mapCategory(from: "하의 > 아노락 팬츠") == .bottom)
    }

    @Test func singleExactRepresentativeForUserResolvedCategoryIsAutomaticallySelected() {
        let productSize = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24
            )
        )
        let product = Product(
            name: "모호한 카테고리 UI 검증 상품",
            category: .top,
            productCode: "fitmatch-ambiguous-category-ui",
            metadata: ProductMetadata(sourceCategoryPath: "스포츠/레저 > 상의 > 기타상의"),
            sourceName: "무신사",
            sizes: [productSize]
        )
        let reference = UserFit(
            sourceName: "직접 입력",
            brandName: "기존 브랜드",
            gender: .unisex,
            productName: "기존 기준옷",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24
            ),
            fitMemo: "",
            satisfaction: 5,
            isRepresentative: true
        )
        productSize.measurementRecords = [
            comparisonRecord(
                value: 48,
                code: .shoulderWidthSeamToSeam,
                kind: .shoulder,
                methodSource: "fitmatch_manual",
                productSize: productSize
            ),
            comparisonRecord(
                value: 54,
                code: .chestWidthPitToPit,
                kind: .chest,
                methodSource: "fitmatch_manual",
                productSize: productSize
            )
        ]
        reference.measurementRecords = [
            comparisonRecord(
                value: 48,
                code: .shoulderWidthSeamToSeam,
                kind: .shoulder,
                methodSource: "fitmatch_manual",
                userFit: reference
            ),
            comparisonRecord(
                value: 54,
                code: .chestWidthPitToPit,
                kind: .chest,
                methodSource: "fitmatch_manual",
                userFit: reference
            )
        ]

        let plan = RecommendationService().referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [reference]
        )

        #expect(plan.recommendedCandidates.map(\.id) == [reference.id])
        #expect(plan.automaticallySelectedCandidate?.id == reference.id)
    }

    @Test func musinsaSweatshirtNamesDoNotBecomeShirtsBySubstring() throws {
        for name in [
            "하프 집업 스웻셔츠-네이비",
            "시그니처 레더 패치드 스웻셔츠 CHARCOAL",
            "BLUER TEAM SWEATSHIRTS DUSTY BLUE"
        ] {
            let classification = try #require(ParsedClosetClassification.resolve(
                category: .top,
                detailCategory: .other,
                sourceDepths: ["상의", "맨투맨/스웨트", nil, nil],
                sourcePath: "상의 > 맨투맨/스웨트",
                productName: name
            ))
            #expect(classification.categoryCode == "tops")
            #expect(classification.detailCode == "sweatshirt")
            #expect(classification.garmentFamily == .sweatshirt)
        }
    }

    @Test func detectedLongSleeveKnitDoesNotMatchShortKnitWithoutNameKeyword() {
        let product = comparisonProduct(
            name: "루이 니트 - 다크 네이비",
            category: .knit,
            sourceCategory: "상의 > 니트/스웨터",
            sleeve: 70
        )
        let shortKnit = comparisonUserFit(
            name: "반팔 니트",
            detail: .shortSleeve,
            sleeve: 24
        )

        let result = ComparisonProfileMatcher().match(
            product: product,
            productDetailCategory: .longSleeve,
            userFits: [shortKnit]
        )

        #expect(result.incomingProfile.garmentFamily == .knitCardigan)
        #expect(result.incomingProfile.lengthType == .long)
        #expect(result.state == .sameFamilyLengthConflict)
        #expect(result.compatibleCandidates.isEmpty)
    }

    @Test func detectedLongSleeveKnitMatchesLongSleeveKnit() {
        let product = comparisonProduct(
            name: "루이 니트 - 다크 네이비",
            category: .knit,
            sourceCategory: "상의 > 니트/스웨터",
            sleeve: 70
        )
        let longKnit = comparisonUserFit(
            name: "긴팔 니트",
            detail: .longSleeve,
            sleeve: 68
        )

        let result = ComparisonProfileMatcher().match(
            product: product,
            productDetailCategory: .longSleeve,
            userFits: [longKnit]
        )

        #expect(result.state == .compatible)
        #expect(result.compatibleCandidates.first?.id == longKnit.id)
    }

    @Test func shortSleeveKnitDoesNotAutoMatchLongSleeveKnit() {
        let product = comparisonProduct(name: "롱 니트", sourceCategory: "상의 > 니트/가디건", sleeve: 60)
        let item = comparisonUserFit(name: "반팔 니트", detail: .shortSleeve, sleeve: 24)

        let result = ComparisonProfileMatcher().match(product: product, productDetailCategory: .knitTop, userFits: [item])

        #expect(result.state == .sameFamilyLengthConflict)
        #expect(result.compatibleCandidates.isEmpty)
    }

    @Test func longSleeveKnitMayAutoMatchLongSleeveKnit() {
        let product = comparisonProduct(name: "롱 니트", sourceCategory: "상의 > 니트/가디건", sleeve: 60)
        let item = comparisonUserFit(name: "긴팔 니트", detail: .knitTop, sleeve: 58)

        let result = ComparisonProfileMatcher().match(product: product, productDetailCategory: .knitTop, userFits: [item])

        #expect(result.state == .compatible)
        #expect(result.compatibleCandidates.first?.id == item.id)
    }

    @Test func shortSleeveTShirtDoesNotAutoMatchLongSleeveKnit() {
        let product = comparisonProduct(name: "긴팔 니트", sourceCategory: "상의 > 니트/가디건", sleeve: 60)
        let item = comparisonUserFit(name: "반팔 티셔츠", sourceCategory: "상의 > 티셔츠", detail: .shortSleeve, sleeve: 24)

        let result = ComparisonProfileMatcher().match(product: product, productDetailCategory: .knitTop, userFits: [item])

        #expect(result.state == .noCompatibleGarment)
        #expect(result.compatibleCandidates.isEmpty)
    }

    @Test func shortsDoNotAutoMatchLongPants() {
        let product = comparisonProduct(name: "롱 팬츠", category: .bottom, sourceCategory: "바지 > 롱 팬츠", sleeve: 0, totalLength: 100)
        let item = comparisonUserFit(name: "쇼츠", category: .bottom, sourceCategory: "바지 > 숏 팬츠", detail: .shorts, sleeve: 0, totalLength: 55)

        let result = ComparisonProfileMatcher().match(product: product, productDetailCategory: .slacks, userFits: [item])

        #expect(result.state == .sameFamilyLengthConflict)
    }

    @Test func uniqloChinoLongPantsMatchesStoredUniqloStraightJeans() {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 101, sleeveLength: 0,
                waist: 40, hip: 52, thigh: 31
            )
        )
        let metadata = ProductMetadata(
            sourceCategoryPath: "팬츠 > 치노팬츠",
            sourceCategoryDepth1: "팬츠",
            sourceCategoryDepth2: "치노팬츠"
        )
        let chino = Product(
            name: "와이드치노팬츠",
            category: .bottom,
            metadata: metadata,
            sourceName: "유니클로 공식몰",
            sizes: [size]
        )
        let straightJeans = UserFit(
            sourceName: "유니클로 공식몰",
            sourceCategoryPath: "팬츠 > 진(청바지) > 스트레이트",
            sourceCategoryDepth1: "팬츠",
            sourceCategoryDepth2: "진(청바지)",
            sourceCategoryDepth3: "스트레이트",
            brandName: "유니클로",
            productName: "스트레이트진",
            category: .bottom,
            detailCategory: .longPants,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 100, sleeveLength: 0,
                waist: 39, hip: 51, thigh: 30
            ),
            fitMemo: "",
            satisfaction: 3
        )

        let result = ComparisonProfileMatcher().match(
            product: chino,
            productDetailCategory: .longPants,
            userFits: [straightJeans]
        )

        #expect(result.incomingProfile.garmentFamily == .pants)
        #expect(ComparisonProfileMatcher().profile(for: straightJeans).garmentFamily == .denim)
        #expect(result.state == .compatible)
        #expect(result.compatibleCandidates.map(\.id) == [straightJeans.id])
    }

    @Test func comparisonProfileCoversEverySupportedClosetDetailFamily() {
        let cases: [(ClothingCategory, ClosetDetailCategory, ComparisonGarmentFamily)] = [
            (.top, .sleeveless, .tshirt), (.top, .shortSleeve, .tshirt),
            (.top, .threeQuarterSleeve, .tshirt), (.top, .longSleeve, .tshirt),
            (.top, .shirt, .shirt), (.top, .blouse, .shirt),
            (.top, .knitTop, .knitCardigan), (.top, .cardigan, .knitCardigan),
            (.top, .sweatshirt, .sweatshirt), (.top, .hoodie, .hoodie),
            (.bottom, .shortPants, .pants), (.bottom, .croppedPants, .pants),
            (.bottom, .threeQuarterPants, .pants), (.bottom, .nineTenthsPants, .pants),
            (.bottom, .longPants, .pants), (.bottom, .slacks, .pants),
            (.bottom, .shorts, .pants), (.bottom, .trainingPants, .pants),
            (.bottom, .denim, .denim), (.bottom, .skirt, .skirt),
            (.bottom, .shortLeggings, .leggings), (.bottom, .threeQuarterLeggings, .leggings),
            (.bottom, .nineTenthsLeggings, .leggings), (.bottom, .longLeggings, .leggings),
            (.bottom, .leggings, .leggings),
            (.outer, .windbreaker, .outerwear), (.outer, .anorak, .outerwear),
            (.outer, .jacket, .outerwear), (.outer, .blazer, .outerwear),
            (.outer, .jumper, .outerwear), (.outer, .blouson, .outerwear),
            (.outer, .fleece, .outerwear), (.outer, .padding, .outerwear),
            (.outer, .coat, .outerwear), (.outer, .trenchCoat, .outerwear),
            (.outer, .mouton, .outerwear), (.outer, .paddedVest, .outerwear),
            (.dress, .onePiece, .dress), (.underwear, .underwear, .underwear),
            (.underwear, .menBriefs, .underwear), (.underwear, .menTrunks, .underwear),
            (.underwear, .menUndershirt, .underwear), (.underwear, .womenBra, .underwear),
            (.underwear, .womenPanty, .underwear), (.underwear, .womenCamisole, .underwear),
            (.underwear, .womenSlip, .underwear),
            (.shoes, .sneakers, .shoes), (.shoes, .runningShoes, .shoes),
            (.shoes, .loafers, .shoes), (.shoes, .boots, .shoes),
            (.shoes, .sandals, .shoes), (.shoes, .heels, .shoes),
            (.accessory, .watch, .accessory), (.accessory, .ring, .accessory),
            (.accessory, .bracelet, .accessory), (.accessory, .necklace, .accessory),
            (.accessory, .bag, .accessory), (.accessory, .hat, .accessory),
            (.accessory, .belt, .accessory), (.accessory, .scarf, .accessory)
        ]
        let matcher = ComparisonProfileMatcher()
        for (category, detail, expectedFamily) in cases {
            let product = Product(name: "테스트 상품", category: category)
            let profile = matcher.profile(for: product, detailCategory: detail)
            #expect(profile.garmentFamily == expectedFamily, "\(category.rawValue)/\(detail.rawValue)")
        }
    }

    @Test func typedBlouseDetailOverridesBroadTShirtSourceFamily() {
        let product = Product(
            name: "레이온블라우스",
            category: .top,
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E489227-000",
            metadata: ProductMetadata(
                sourceCategoryPath: "셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 긴팔"
            ),
            sourceName: "유니클로",
            sizes: []
        )
        product.normalizedProductTypeCode = "tops.tshirt"

        let profile = ComparisonProfileMatcher().profile(for: product, detailCategory: .blouse)

        #expect(profile.garmentFamily == .shirt)

        let closetItem = UserFit(
            sourceType: .officialStore,
            sourceName: "유니클로",
            sourceCategoryPath: "셔츠 & 블라우스 & 폴로셔츠 > 셔츠 & 블라우스 > 긴팔",
            brandName: "유니클로",
            gender: .women,
            productName: "레이온블라우스",
            category: .top,
            detailCategory: .blouse,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0
            ),
            fitMemo: "fixture",
            satisfaction: 3
        )
        closetItem.normalizedProductTypeCode = "tops.tshirt"

        #expect(ComparisonProfileMatcher().profile(for: closetItem).garmentFamily == .shirt)
    }

    @Test func intermediateSleeveAndPantsLengthsDoNotCrossMatch() {
        let matcher = ComparisonProfileMatcher()
        let product = Product(
            name: "테스트 팬츠",
            category: .bottom,
            metadata: ProductMetadata(sourceCategoryPath: "하의"),
            sizes: [
                ProductSize(
                    name: "M",
                    measurements: GarmentMeasurements(
                        shoulder: 0, chest: 0, totalLength: 82, sleeveLength: 0,
                        waist: 38, hip: 50, thigh: 30
                    )
                )
            ]
        )
        let seven = comparisonUserFit(
            name: "7부 팬츠", category: .bottom, sourceCategory: "하의",
            detail: .threeQuarterPants, sleeve: 0, totalLength: 82
        )
        let nine = comparisonUserFit(
            name: "9부 팬츠", category: .bottom, sourceCategory: "하의",
            detail: .nineTenthsPants, sleeve: 0, totalLength: 92
        )

        let sameLength = matcher.match(
            product: product, productDetailCategory: .threeQuarterPants, userFits: [seven]
        )
        let differentLength = matcher.match(
            product: product, productDetailCategory: .threeQuarterPants, userFits: [nine]
        )

        #expect(sameLength.state == .compatible)
        #expect(differentLength.state == .sameFamilyLengthConflict)
    }

    @Test func lengthAwareAndLengthIndependentCategoriesUseTheirOwnRules() {
        func result(
            category: ClothingCategory,
            detail: ClosetDetailCategory,
            name: String,
            source: String,
            measurements: GarmentMeasurements
        ) -> AutomaticComparisonMatchResult {
            let size = ProductSize(name: "M", measurements: measurements)
            let product = Product(
                name: name, category: category,
                metadata: ProductMetadata(sourceCategoryPath: source), sizes: [size]
            )
            let item = UserFit(
                sourceCategoryPath: source, brandName: "테스트", productName: name,
                category: category, detailCategory: detail, sizeName: "M",
                measurements: measurements, fitMemo: "", satisfaction: 3
            )
            return ComparisonProfileMatcher().match(
                product: product, productDetailCategory: detail, userFits: [item]
            )
        }

        let dress = result(
            category: .dress, detail: .onePiece, name: "원피스", source: "원피스",
            measurements: GarmentMeasurements(shoulder: 0, chest: 48, totalLength: 110, sleeveLength: 0, waist: 40, hip: 50)
        )
        let skirt = result(
            category: .bottom, detail: .skirt, name: "스커트", source: "하의 > 스커트",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 75, sleeveLength: 0, waist: 36, hip: 48, thigh: 28)
        )
        let underwear = result(
            category: .underwear, detail: .menBriefs, name: "브리프", source: "속옷 > 브리프",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0, waist: 34, hip: 43)
        )
        let shoes = result(
            category: .shoes, detail: .sneakers, name: "스니커즈", source: "신발 > 스니커즈",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0, footLength: 270)
        )

        #expect(dress.state == .requiresConfirmation)
        #expect(skirt.state == .compatible)
        #expect(underwear.state == .compatible)
        #expect(shoes.state == .compatible)
    }

    @Test func canonicalTaxonomyBundleDecodesAndResolvesMusinsaID() throws {
        let store = try CanonicalTaxonomyBundleStore(bundle: .main)
        let profile = try #require(store.profile(for: CanonicalTaxonomyLookupInput(
            source: "무신사",
            externalCategoryID: "001001",
            target: nil,
            sourceCategoryPath: "잘못된 경로"
        )))

        #expect(profile.decision == .confirmed)
        #expect(profile.eligibility)
        #expect(profile.semanticCategoryCode == "tops")
        #expect(profile.appGarmentFamily == .tshirt)
        #expect(profile.appLengthType == .short)
        #expect(profile.policyVersion == "taxonomy-refined-2026-08-03")
    }

    @Test func canonicalTaxonomyRejectsMusinsaBriefcasesAsBags() throws {
        let store = try CanonicalTaxonomyBundleStore(bundle: .main)
        let cases = [
            ("004008", "가방 > 브리프 케이스"),
            ("105003002009", "부티크 > 지갑/가방 > 가방 > 브리프케이스"),
            ("107003001007", "아울렛 > 패션소품 > 가방 > 브리프케이스"),
            ("108003001007", "어스 > 패션소품 > 가방 > 브리프케이스")
        ]

        for (id, path) in cases {
            let profile = try #require(store.profile(for: CanonicalTaxonomyLookupInput(
                source: "musinsa", externalCategoryID: id, target: nil, sourceCategoryPath: path
            )))
            #expect(profile.decision == .rejected)
            #expect(!profile.eligibility)
            #expect(profile.semanticCategoryCode == nil)
            #expect(profile.semanticGarmentType == nil)
            #expect(profile.comparisonFamily == nil)
        }
    }

    @Test func adultCrossGenderBottomsCanUseDirectMeasurements() throws {
        var metadata = ProductMetadata(sourceCategoryPath: "팬츠 > 슬랙스(트라우저)")
        metadata.genderCodes = ["WOMEN"]
        let productSize = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 72, sleeveLength: 0,
                waist: 36, hip: 52.5, thigh: 34.5
            )
        )
        let product = Product(
            name: "스마트와이드스트레이트팬츠",
            category: .bottom,
            metadata: metadata,
            sourceName: "유니클로 공식몰",
            sizes: [productSize]
        )
        product.garmentType = .pants
        product.sleeveType = .long

        let item = UserFit(
            sourceName: "유니클로 공식몰",
            sourceCategoryPath: "팬츠 > 진(청바지)",
            brandName: "유니클로",
            gender: .men,
            productName: "스트레이트진(셀비지)",
            category: .bottom,
            detailCategory: .denim,
            sizeName: "30",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 78.5, sleeveLength: 0,
                waist: 41, hip: 51, thigh: 33
            ),
            fitMemo: "",
            satisfaction: 3
        )
        item.garmentType = .denim
        item.sleeveType = .long

        let matcher = ComparisonProfileMatcher()
        let result = matcher.match(product: product, productDetailCategory: .longPants, userFits: [item])
        let diagnostic = try #require(matcher.candidateDiagnostics(
            product: product,
            productDetailCategory: .longPants,
            userFits: [item]
        ).first)

        #expect(result.state == .compatible)
        #expect(result.compatibleCandidates.map(\.id) == [item.id])
        #expect(diagnostic.exclusionReasons.isEmpty)
        #expect(diagnostic.commonCoreMeasurementCount >= diagnostic.minimumCommonMeasurementCount)
    }

    @Test func adultCrossGenderUnderwearRemainsIncompatible() {
        var metadata = ProductMetadata(sourceCategoryPath: "이너웨어 > 여성 속옷 하의")
        metadata.genderCodes = ["WOMEN"]
        let product = Product(
            name: "여성 이너웨어",
            category: .underwear,
            metadata: metadata,
            sourceName: "유니클로 공식몰",
            sizes: [ProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0,
                    waist: 34, hip: 44
                )
            )]
        )
        product.garmentType = .underwear

        let item = UserFit(
            sourceName: "유니클로 공식몰",
            sourceCategoryPath: "이너웨어 > 남성 브리프",
            brandName: "유니클로",
            gender: .men,
            productName: "남성 브리프",
            category: .underwear,
            detailCategory: .menBriefs,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0,
                waist: 36, hip: 46
            ),
            fitMemo: "",
            satisfaction: 3
        )
        item.garmentType = .underwear

        let matcher = ComparisonProfileMatcher()
        let result = matcher.match(product: product, productDetailCategory: .womenPanty, userFits: [item])

        #expect(result.state == .noCompatibleGarment)
        #expect(result.compatibleCandidates.isEmpty)
    }

    @Test func automaticMatcherDoesNotTreatAdultUnisexAsKidsCompatible() {
        var metadata = ProductMetadata(sourceCategoryPath: "팬츠 > 롱팬츠")
        metadata.genderCodes = ["UNISEX"]
        let product = Product(
            name: "성인 공용 파라슈트팬츠",
            category: .bottom,
            metadata: metadata,
            sourceName: "유니클로",
            sizes: [ProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 0, chest: 0, totalLength: 101, sleeveLength: 0,
                    waist: 38, hip: 53, thigh: 34
                )
            )]
        )
        product.garmentType = .pants
        product.sleeveType = .long

        let kidsItem = UserFit(
            sourceName: "유니클로",
            sourceCategoryPath: "KIDS > 팬츠 > 롱팬츠",
            brandName: "유니클로",
            gender: .kids,
            productName: "KIDS 배럴팬츠",
            category: .bottom,
            detailCategory: .longPants,
            sizeName: "140",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 81, sleeveLength: 0,
                waist: 31, hip: 45, thigh: 29
            ),
            fitMemo: "",
            satisfaction: 3
        )
        kidsItem.garmentType = .pants
        kidsItem.sleeveType = .long

        let matcher = ComparisonProfileMatcher()
        let result = matcher.match(
            product: product,
            productDetailCategory: .longPants,
            userFits: [kidsItem]
        )
        let diagnostic = matcher.candidateDiagnostics(
            product: product,
            productDetailCategory: .longPants,
            userFits: [kidsItem]
        ).first

        #expect(result.state == .noCompatibleGarment)
        #expect(result.compatibleCandidates.isEmpty)
        #expect(diagnostic?.exclusionReasons.contains("gender_incompatible") == true)
    }

    @Test func automaticMatcherDoesNotCrossMajorCategoriesForSamePantsFamily() {
        let product = Product(
            name: "코튼복서이지쇼트팬츠",
            category: .other,
            metadata: ProductMetadata(
                sourceCategoryPath: "파자마 & 홈웨어 > 라운지 팬츠 > 쇼트 팬츠"
            ),
            sourceName: "유니클로 공식몰",
            sizes: [ProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 0, chest: 0, totalLength: 42, sleeveLength: 0,
                    waist: 36, hip: 52, thigh: 34
                )
            )]
        )
        product.garmentType = .pants
        product.sleeveType = .short

        let item = UserFit(
            sourceName: "유니클로 공식몰",
            sourceCategoryPath: "팬츠 > 쇼트 팬츠(반바지) > 카고 & 기어",
            brandName: "유니클로",
            gender: .men,
            productName: "기어쇼트팬츠",
            category: .bottom,
            detailCategory: .shorts,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 44, sleeveLength: 0,
                waist: 38, hip: 54, thigh: 35
            ),
            fitMemo: "",
            satisfaction: 3
        )
        item.garmentType = .pants
        item.sleeveType = .short

        let matcher = ComparisonProfileMatcher()
        let result = matcher.match(
            product: product,
            productDetailCategory: .loungewear,
            userFits: [item]
        )
        let diagnostic = matcher.candidateDiagnostics(
            product: product,
            productDetailCategory: .loungewear,
            userFits: [item]
        ).first

        #expect(result.state == .noCompatibleGarment)
        #expect(result.compatibleCandidates.isEmpty)
        #expect(diagnostic?.exclusionReasons.contains("major_category_incompatible") == true)
    }

    @Test func refinedCanonicalTaxonomyKeepsLeatherJacketsInTheirOwnFamily() throws {
        let store = try CanonicalTaxonomyBundleStore(bundle: .main)
        let profile = try #require(store.profile(for: CanonicalTaxonomyLookupInput(
            source: "musinsa", externalCategoryID: "002002", target: nil, sourceCategoryPath: nil
        )))
        let matcher = ComparisonProfileMatcher()

        #expect(profile.decision == .confirmed)
        #expect(profile.semanticGarmentType == "leather_jacket")
        #expect(profile.appGarmentFamily == .leatherJacket)
        #expect(profile.requiredMeasurements == ["chest", "total_length"])
        #expect(profile.optionalMeasurements == ["shoulder", "sleeve_length"])
        #expect(matcher.garmentFamiliesAreCompatible(.leatherJacket, .leatherJacket))
        #expect(!matcher.garmentFamiliesAreCompatible(.leatherJacket, .outerwear))
    }

    @Test func canonicalTaxonomyBundleResolvesUniqloTargetPathAndRejectsUnsupportedUse() throws {
        let store = try CanonicalTaxonomyBundleStore(bundle: .main)
        let uniqlo = try #require(store.profile(for: CanonicalTaxonomyLookupInput(
            source: "유니클로 공식몰",
            externalCategoryID: nil,
            target: "MEN",
            sourceCategoryPath: "팬츠  >  진(청바지) > UNIQLO : C"
        )))
        let rejected = try #require(store.profile(for: CanonicalTaxonomyLookupInput(
            source: "musinsa",
            externalCategoryID: "003010",
            target: nil,
            sourceCategoryPath: nil
        )))

        #expect(uniqlo.decision == .confirmed)
        #expect(uniqlo.appGarmentFamily == .pants)
        #expect(uniqlo.appLengthType == .long)
        #expect(rejected.decision == .rejected)
        #expect(!rejected.eligibility)
    }

    @Test func canonicalProfileSnapshotRoundTripsWithoutLosingPolicyIdentity() throws {
        let store = try CanonicalTaxonomyBundleStore(bundle: .main)
        let original = try #require(store.profile(for: CanonicalTaxonomyLookupInput(
            source: "musinsa", externalCategoryID: "001001", target: nil, sourceCategoryPath: nil
        )))
        let encoded = try #require(CanonicalProfileSnapshotCoder.encode(original))
        let decoded = try #require(CanonicalProfileSnapshotCoder.decode(encoded))

        #expect(decoded == original)
        #expect(decoded.sourceIdentity == original.sourceIdentity)
    }

    @Test func unspecifiedSleeveLengthUsesMeasuredFallbackInsteadOfConfirmation() {
        let product = comparisonProduct(name: "베이직 니트", sourceCategory: "상의 > 니트/가디건", sleeve: 40)
        let item = comparisonUserFit(name: "니트", detail: .knitTop, sleeve: 40)

        let result = ComparisonProfileMatcher().match(product: product, productDetailCategory: .knitTop, userFits: [item])

        #expect(result.state == .compatible)
    }

    @Test func previousManualSelectionDoesNotAffectNewProduct() {
        let matcher = ComparisonProfileMatcher()
        let previous = comparisonProduct(name: "반팔 니트", sourceCategory: "상의 > 니트/가디건", sleeve: 24)
        let next = comparisonProduct(name: "긴팔 니트", sourceCategory: "상의 > 니트/가디건", sleeve: 60)
        let item = comparisonUserFit(name: "반팔 니트", detail: .shortSleeve, sleeve: 24)

        _ = matcher.manualCandidates(product: previous, productDetailCategory: .knitTop, userFits: [item])
        let result = matcher.match(product: next, productDetailCategory: .knitTop, userFits: [item])

        #expect(result.state == .sameFamilyLengthConflict)
    }

    @Test func manualTopSleeveLengthMismatchAllowsBodyOnlyComparison() {
        let matcher = ComparisonProfileMatcher()
        let topProduct = comparisonProduct(name: "긴팔 니트", sourceCategory: "상의 > 니트/가디건", sleeve: 60)
        let shortTop = comparisonUserFit(name: "반팔 니트", detail: .shortSleeve, sleeve: 24)
        let topSize = topProduct.sizes[0]
        topSize.measurementRecords = [
            comparisonRecord(value: 48, code: .shoulderWidthSeamToSeam, kind: .shoulder, methodSource: "musinsa", productSize: topSize),
            comparisonRecord(value: 54, code: .chestWidthPitToPit, kind: .chest, methodSource: "musinsa", productSize: topSize),
            comparisonRecord(value: 70, code: .bodyLengthBackNeckToHem, kind: .totalLength, methodSource: "musinsa", productSize: topSize),
            comparisonRecord(value: 60, code: .sleeveShoulderSeamToCuff, kind: .sleeveLength, methodSource: "musinsa", productSize: topSize)
        ]
        shortTop.measurementRecords = [
            comparisonRecord(value: 48, code: .shoulderWidthSeamToSeam, kind: .shoulder, methodSource: "musinsa", userFit: shortTop),
            comparisonRecord(value: 54, code: .chestWidthPitToPit, kind: .chest, methodSource: "musinsa", userFit: shortTop),
            comparisonRecord(value: 70, code: .bodyLengthBackNeckToHem, kind: .totalLength, methodSource: "musinsa", userFit: shortTop),
            comparisonRecord(value: 24, code: .sleeveShoulderSeamToCuff, kind: .sleeveLength, methodSource: "musinsa", userFit: shortTop)
        ]
        let bottomSize = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 100, sleeveLength: 0,
                waist: 38, hip: 50, thigh: 30, rise: 29, hem: 20
            )
        )
        let bottomProduct = Product(
            name: "롱 팬츠",
            category: .bottom,
            metadata: ProductMetadata(sourceCategoryPath: "바지 > 롱 팬츠"),
            sourceName: "무신사",
            sizes: [bottomSize]
        )
        let shorts = UserFit(
            sourceName: "무신사",
            sourceCategoryPath: "바지 > 숏 팬츠",
            brandName: "테스트",
            productName: "쇼츠",
            category: .bottom,
            detailCategory: .shorts,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 55, sleeveLength: 0,
                waist: 39, hip: 51, thigh: 31, rise: 30, hem: 29
            ),
            fitMemo: "",
            satisfaction: 3
        )
        bottomSize.measurementRecords = [
            comparisonRecord(value: 38, code: .waistWidthEdgeToEdge, kind: .waist, methodSource: "musinsa", productSize: bottomSize),
            comparisonRecord(value: 50, code: .hipWidthAtWidest, kind: .hip, methodSource: "musinsa", productSize: bottomSize),
            comparisonRecord(value: 30, code: .thighWidthCrotchToOuter, kind: .thigh, methodSource: "musinsa", productSize: bottomSize),
            comparisonRecord(value: 100, code: .pantsOutseamWaistToHem, kind: .totalLength, methodSource: "musinsa", productSize: bottomSize),
            comparisonRecord(value: 20, code: .hemWidthEdgeToEdge, kind: .hem, methodSource: "musinsa", productSize: bottomSize)
        ]
        shorts.measurementRecords = [
            comparisonRecord(value: 39, code: .waistWidthEdgeToEdge, kind: .waist, methodSource: "musinsa", userFit: shorts),
            comparisonRecord(value: 51, code: .hipWidthAtWidest, kind: .hip, methodSource: "musinsa", userFit: shorts),
            comparisonRecord(value: 31, code: .thighWidthCrotchToOuter, kind: .thigh, methodSource: "musinsa", userFit: shorts),
            comparisonRecord(value: 55, code: .pantsOutseamWaistToHem, kind: .totalLength, methodSource: "musinsa", userFit: shorts),
            comparisonRecord(value: 29, code: .hemWidthEdgeToEdge, kind: .hem, methodSource: "musinsa", userFit: shorts)
        ]

        let topMismatch = matcher.manualMismatch(
            product: topProduct,
            productDetailCategory: .knitTop,
            selectedItem: shortTop
        )
        let bottomMismatch = matcher.manualMismatch(
            product: bottomProduct,
            productDetailCategory: .slacks,
            selectedItem: shorts
        )

        #expect(topMismatch.excludedKinds == [.sleeveLength])
        #expect(topMismatch.note?.contains("소매길이를 제외") == true)
        #expect(bottomMismatch.excludedKinds == [.totalLength, .hem])
        #expect(bottomMismatch.note?.contains("길이 구조가 달라 자동 비교에서 제외") == true)
        #expect(bottomMismatch.note?.contains("공통 실측은 참고용으로 비교") == true)
        #expect(matcher.manualCandidates(
            product: topProduct,
            productDetailCategory: .knitTop,
            userFits: [shortTop]
        ).map(\.id) == [shortTop.id])
        let partialResult = RecommendationService().recommend(
            product: topProduct,
            selectedReferenceItem: shortTop,
            productDetailCategory: .knitTop
        )
        #expect(partialResult?.measurementExclusions.contains {
            $0.kind == .sleeveLength && $0.reason == .sleeveLengthMismatch
        } == true)
        #expect(matcher.manualCandidates(
            product: bottomProduct,
            productDetailCategory: .slacks,
            userFits: [shorts]
        ).map(\.id) == [shorts.id])
        let bottomPartialResult = RecommendationService().recommend(
            product: bottomProduct,
            selectedReferenceItem: shorts,
            productDetailCategory: .slacks
        )
        #expect(bottomPartialResult?.measurementExclusions.contains {
            $0.kind == .totalLength && $0.reason == .garmentLengthMismatch
        } == true)
        #expect(bottomPartialResult?.measurementExclusions.contains {
            $0.kind == .hem && $0.reason == .garmentLengthMismatch
        } == true)
    }

    @Test func manualCrossDetailOuterwearRemainsReferenceOnly() {
        let productMeasurements = GarmentMeasurements(
            shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 60
        )
        let size = ProductSize(name: "M", measurements: productMeasurements)
        size.measurementRecords = [
            comparisonRecord(
                value: 60,
                code: .sleeveShoulderSeamToCuff,
                kind: .sleeveLength,
                methodSource: "musinsa",
                methodProfile: "musinsa_outer",
                rawCode: "sleeve",
                rawLabel: "소매길이",
                productSize: size
            )
        ]
        let product = Product(
            name: "롱 재킷",
            category: .outer,
            metadata: ProductMetadata(sourceCategoryPath: "아우터 > 재킷"),
            sourceName: "무신사",
            sizes: [size]
        )
        product.sleeveTypeRawValue = ComparisonLengthType.long.rawValue

        let item = UserFit(
            sourceName: "무신사",
            sourceCategoryPath: "아우터 > 코트",
            brandName: "테스트",
            productName: "반소매 코트",
            category: .outer,
            detailCategory: .coat,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24
            ),
            fitMemo: "",
            satisfaction: 3
        )
        item.sleeveTypeRawValue = ComparisonLengthType.short.rawValue
        item.measurementRecords = [
            comparisonRecord(
                value: 24,
                code: .sleeveShoulderSeamToCuff,
                kind: .sleeveLength,
                methodSource: "musinsa",
                methodProfile: "musinsa_outer",
                rawCode: "sleeve",
                rawLabel: "소매길이",
                userFit: item
            )
        ]

        let mismatch = ComparisonProfileMatcher().manualMismatch(
            product: product,
            productDetailCategory: .jacket,
            selectedItem: item
        )

        #expect(mismatch.excludedKinds.isEmpty)
        #expect(mismatch.note == "유사한 다른 종류의 옷이라 공통 실측 중심으로 확장 비교했어요.")
    }

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func parsedSizeNormalizerRemovesSameNameAndSameMeasurements() {
        let sizes = [
            parsedSize("M", chest: 52),
            parsedSize("M", chest: 52)
        ]

        let uniqueSizes = ParsedProductSizeNormalizer.uniqueSizes(sizes)

        #expect(uniqueSizes.count == 1)
        #expect(uniqueSizes.first?.name == "M")
        #expect(uniqueSizes.first?.measurements.chest == 52)
    }

    @Test func parsedSizeNormalizerRemovesWhitespaceOnlyNameDuplicates() {
        let sizes = [
            parsedSize("M[080]", chest: 50),
            parsedSize(" M[080] ", chest: 60)
        ]

        let uniqueSizes = ParsedProductSizeNormalizer.uniqueSizes(sizes)

        #expect(uniqueSizes.count == 1)
        #expect(uniqueSizes.first?.name == "M[080]")
        #expect(uniqueSizes.first?.measurements.chest == 50)
    }

    @Test func parsedSizeNormalizerKeepsFirstSMLInOriginalOrder() {
        let sizes = [
            parsedSize("S", chest: 48),
            parsedSize("S", chest: 49),
            parsedSize("M", chest: 52),
            parsedSize("M", chest: 53),
            parsedSize("L", chest: 56),
            parsedSize("L", chest: 57)
        ]

        let uniqueSizes = ParsedProductSizeNormalizer.uniqueSizes(sizes)

        #expect(uniqueSizes.map(\.name) == ["S", "M", "L"])
        #expect(uniqueSizes.map { $0.measurements.chest } == [48, 52, 56])
    }

    @Test func parsedSizeNormalizerKeepsDifferentSizes() {
        let sizes = [
            parsedSize("S", chest: 48),
            parsedSize("M", chest: 52),
            parsedSize("L", chest: 56),
            parsedSize("XL", chest: 60)
        ]

        let uniqueSizes = ParsedProductSizeNormalizer.uniqueSizes(sizes)

        #expect(uniqueSizes.map(\.name) == ["S", "M", "L", "XL"])
    }

    @Test func productSizeCreationRemovesDuplicatesAndResetsDisplayOrder() {
        let sizes = ParsedProductSizeNormalizer.makeProductSizes(from: [
            parsedSize("S", chest: 48),
            parsedSize("S", chest: 49),
            parsedSize(" M ", chest: 52),
            parsedSize("M", chest: 53),
            parsedSize("L", chest: 56)
        ])

        #expect(sizes.map(\.name) == ["S", "M", "L"])
        #expect(sizes.map(\.displayOrder) == [0, 1, 2])
        #expect(sizes.map { $0.measurements.chest } == [48, 52, 56])
    }

    @Test func parsedProductSizeStableIDUsesProductAndSizeName() {
        let firstID = ParsedProductSize.stableID(for: "E465185-000|M")
        let sameID = ParsedProductSize.stableID(for: "E465185-000| M ")
        let otherProductID = ParsedProductSize.stableID(for: "E422992-066|M")
        let otherSizeID = ParsedProductSize.stableID(for: "E465185-000|L")

        #expect(firstID == sameID)
        #expect(firstID != otherProductID)
        #expect(firstID != otherSizeID)
    }

    @Test func productSizeNormalizerKeepsSelectionIdentityByProductSizeID() {
        let firstID = UUID()
        let secondID = UUID()
        let sizes = [
            ProductSize(id: firstID, name: "M", measurements: measurements(chest: 52), displayOrder: 0),
            ProductSize(id: secondID, name: "L", measurements: measurements(chest: 56), displayOrder: 1)
        ]

        let selectedSizeID = secondID
        let selectedSize = ParsedProductSizeNormalizer
            .uniqueProductSizes(sizes)
            .first { $0.id == selectedSizeID }

        #expect(selectedSize?.id == secondID)
        #expect(selectedSize?.name == "L")
        #expect(selectedSize?.measurements.chest == 56)
    }

    @MainActor
    @Test func musinsaDeepLinkCandidates() async throws {
        let candidates = [
            "https://www.musinsa.com",
            "https://www.musinsa.com/main/musinsa/recommend",
            "https://www.musinsa.com/app/",
            "musinsa://",
            "musinsa://main",
            "musinsa://store",
            "musinsa://product",
            "musinsa://goods"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else {
                print("[MusinsaDeepLinkTest] \(candidate) | invalid URL")
                continue
            }

            let canOpen = UIApplication.shared.canOpenURL(url)
            let opened = await withCheckedContinuation { continuation in
                UIApplication.shared.open(url, options: [:]) { didOpen in
                    continuation.resume(returning: didOpen)
                }
            }

            print("[MusinsaDeepLinkTest] \(candidate) | canOpenURL=\(canOpen) | open=\(opened)")
        }
    }

    @Test func uniqloURLResolverExtractsProductAndTwoDigitColor() {
        let resolver = UniqloURLResolver()
        let text = "https://www.uniqlo.com/kr/ko/products/E422992?colorDisplayCode=66 krgoods_66_422992_3x4.jpg"

        let productID = resolver.extractProductID(from: text)
        let colorCode = resolver.extractColorCode(from: text, productID: "E422992", goodsID: "422992")

        #expect(productID == "E422992")
        #expect(colorCode == "66")
        #expect(resolver.normalizeAPIColorCode(colorCode ?? "") == "066")
        #expect(resolver.normalizeImageColorCode(colorCode ?? "") == "66")
    }

    @Test func musinsaURLResolverUsesCanonicalProductURLWithoutRedirectRequest() async throws {
        let resolver = MusinsaURLResolver()
        let url = try #require(URL(string: "https://www.musinsa.com/products/4668060?source=history"))

        let resolved = try await resolver.resolve(url)

        #expect(resolved.productID == "4668060")
        #expect(resolved.resolvedURL.absoluteString == "https://www.musinsa.com/products/4668060")
    }

    @Test func uniqloURLResolverPreservesLeadingZeroColor() {
        let resolver = UniqloURLResolver()
        let text = "https://www.uniqlo.com/kr/ko/products/E465185?colorDisplayCode=00"

        let productID = resolver.extractProductID(from: text)
        let colorCode = resolver.extractColorCode(from: text, productID: "E465185", goodsID: "465185")

        #expect(productID == "E465185")
        #expect(colorCode == "00")
        #expect(resolver.normalizeAPIColorCode(colorCode ?? "") == "000")
        #expect(resolver.normalizeImageColorCode(colorCode ?? "") == "00")
    }

    @Test func uniqloURLResolverPrefersSharedQueryColorOverGenericPathColor() throws {
        let resolver = UniqloURLResolver()
        let sharedURL = try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/E487957-000/00?colorDisplayCode=08&sizeDisplayCode=004"))
        let resolvedURL = try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/E487957-000/00"))
        let fallbackText = "\(sharedURL.absoluteString) \(resolvedURL.absoluteString) krgoods_00_487957_3x4.jpg"

        let colorCode = resolver.resolveColorCode(
            originalURL: sharedURL,
            resolvedURL: resolvedURL,
            fallbackText: fallbackText,
            productID: "E487957",
            goodsID: "487957"
        )

        #expect(colorCode == "08")
        #expect(resolver.normalizeAPIColorCode(colorCode ?? "") == "008")
        #expect(resolver.normalizeImageColorCode(colorCode ?? "") == "08")
    }

    @Test func uniqloSelectedColorThumbnailIsNotReplacedByGenericSizeChartImage() {
        let selected = "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/465185/item/krgoods_03_465185_3x4.jpg"
        let generic = "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/465185/item/krgoods_00_465185_3x4.jpg"
        var metadata = UniqloProductMetadata(
            sourceURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E465185?colorDisplayCode=03")!,
            productID: "E465185",
            goodsID: "465185",
            colorCode: "03",
            brandName: "유니클로",
            productName: "테스트 상품",
            category: .top,
            detailCategory: .longSleeve,
            imageURLString: selected
        )
        metadata.productMetadata.imageURLStrings = [selected]

        let resolved = metadata.withPreferredImageURL(
            generic,
            selectedColorCode: "03",
            goodsID: "465185"
        )

        #expect(resolved.imageURLString == selected)
        #expect(resolved.productMetadata.imageURLStrings == [selected])
    }

    @Test func uniqloGenericColorUsesOfficialSizeAPIRepresentativeImage() {
        let generatedGeneric = "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/422992/item/krgoods_00_422992_3x4.jpg"
        let officialRepresentative = "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/422992/item/krgoods_11_422992_3x4.jpg"
        var metadata = UniqloProductMetadata(
            sourceURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E422992-000/00")!,
            productID: "E422992",
            goodsID: "422992",
            colorCode: "00",
            brandName: "유니클로",
            productName: "크루넥T",
            category: .top,
            detailCategory: .shortSleeve,
            imageURLString: generatedGeneric
        )
        metadata.productMetadata.imageURLStrings = [generatedGeneric]

        let resolved = metadata.withPreferredImageURL(
            officialRepresentative,
            selectedColorCode: "00",
            goodsID: "422992"
        )

        #expect(resolved.imageURLString == officialRepresentative)
        #expect(resolved.productMetadata.imageURLStrings == [officialRepresentative])
    }

    @Test func uniqloThumbnailCandidatesRetainSelectedColorThenDefaultColor() throws {
        let selected = try #require(URL(
            string: "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/465185/item/krgoods_03_465185_3x4.jpg?width=400"
        ))
        let candidates = UniqloImageURLPolicy.candidateURLs(primaryURL: selected)

        #expect(candidates.map(\.absoluteString) == [
            selected.absoluteString,
            "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/465185/item/krgoods_00_465185_3x4.jpg?width=400"
        ])
    }

    @Test func legacyUniqloProductWithoutImageDerivesDefaultThumbnail() {
        let product = Product(
            name: "크루넥T",
            category: .top,
            productCode: "E422992",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E422992-000/00",
            imageURLString: nil,
            sourceType: .officialStore,
            sourceName: "유니클로"
        )

        #expect(product.imageURLStringForDisplay ==
            "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/422992/item/krgoods_00_422992_3x4.jpg?width=400")
    }

    @Test func nonUniqloSixDigitProductDoesNotDeriveUniqloThumbnail() {
        let product = Product(
            name: "무신사 테스트 상품",
            category: .top,
            productCode: "422992",
            imageURLString: nil,
            sourceType: .marketplace,
            sourceName: "무신사"
        )

        #expect(product.imageURLStringForDisplay == nil)
    }

    @Test func musinsaURLResolverPrefersExplicitVariantProductID() {
        let resolver = MusinsaURLResolver()
        let url = URL(string: "https://www.musinsa.com/products/1234567?goodsNo=7654321")!

        #expect(resolver.extractProductID(from: url) == "7654321")
    }

    @Test func uniqloEmptyColorSpecificSizeChartRetriesGenericProductID() {
        let emptyResult = UniqloSizeAPIResult(sizes: [], imageURLString: nil)
        let populatedResult = UniqloSizeAPIResult(
            sizes: [ParsedProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 45, chest: 54, totalLength: 67, sleeveLength: 60
                )
            )],
            imageURLString: nil
        )
        let genericID = UniqloSizeAPIParser.genericProductIDWithColorCode(for: "E475941")

        #expect(genericID == "E475941-000")
        #expect(UniqloSizeAPIParser.shouldRetryWithGenericColor(
            preferredProductIDWithColorCode: "E475941-060",
            genericProductIDWithColorCode: genericID,
            result: emptyResult
        ))
        #expect(!UniqloSizeAPIParser.shouldRetryWithGenericColor(
            preferredProductIDWithColorCode: genericID,
            genericProductIDWithColorCode: genericID,
            result: emptyResult
        ))
        #expect(!UniqloSizeAPIParser.shouldRetryWithGenericColor(
            preferredProductIDWithColorCode: "E475941-060",
            genericProductIDWithColorCode: genericID,
            result: populatedResult
        ))
    }

    @Test func uniqloSizeAPIParserUsesSizeChartAndRemovesDuplicateSizeNames() throws {
        let json = """
        {
          "status": "ok",
          "result": [
            {
              "productId": "E465185-000",
              "sizeChart": [
                {
                  "name": "S",
                  "sizeParts": [
                    { "code": "body-length-back", "name": "전체 길이", "measurements": [{ "value": "64", "unit": "cm" }] },
                    { "code": "shoulder-width", "name": "어깨너비", "measurements": [{ "value": "45", "unit": "cm" }] },
                    { "code": "body-width", "name": "가슴너비", "measurements": [{ "value": "52", "unit": "cm" }] },
                    { "code": "sleeve-length-cb", "name": "소매", "info": "목 중심부터 소매 끝", "measurements": [{ "value": "82", "unit": "cm" }] },
                    { "code": "inseam", "name": "인심", "info": "가랑이부터 밑단까지", "measurements": [{ "value": "76", "unit": "cm" }] }
                  ]
                },
                {
                  "name": " S ",
                  "sizeParts": [
                    { "code": "body-length-back", "name": "전체 길이", "measurements": [{ "value": "99", "unit": "cm" }] },
                    { "code": "body-width", "name": "가슴너비", "measurements": [{ "value": "99", "unit": "cm" }] }
                  ]
                },
                {
                  "name": "M",
                  "sizeParts": [
                    { "code": "body-length-back", "name": "전체 길이", "measurements": [{ "value": "66", "unit": "cm" }] },
                    { "code": "body-width", "name": "가슴너비", "measurements": [{ "value": "54", "unit": "cm" }] }
                  ]
                }
              ],
              "imageUrl": "//image.uniqlo.com/UQ/ST3/kr/imagesgoods/465185/item/krgoods_00_465185_3x4.jpg?width=400",
              "bodyMeasurements": [
                {
                  "name": "S",
                  "sizeParts": [
                    { "code": "height", "name": "키", "measurements": [{ "value": "170", "unit": "cm" }] }
                  ]
                }
              ]
            }
          ]
        }
        """

        let sizes = try UniqloSizeAPIParser().parseSizes(from: Data(json.utf8))

        #expect(sizes.map(\.name) == ["S", "M"])
        #expect(sizes.first?.measurements.totalLength == 64)
        #expect(sizes.first?.measurements.chest == 52)
        #expect(sizes.first?.id == ParsedProductSize.stableID(for: "E465185-000|S"))
        let records = sizes.first?.measurementRecords ?? []
        let shoulder = records.first { $0.rawCode == "shoulder-width" }
        let sleeve = records.first { $0.rawCode == "sleeve-length-cb" }
        let chest = records.first { $0.rawCode == "body-width" }
        let length = records.first { $0.rawCode == "body-length-back" }
        let inseam = records.first { $0.rawCode == "inseam" }
        #expect(shoulder?.measurementCode == .shoulderWidthSeamToSeam)
        #expect(shoulder?.mappingVersion == MeasurementSourceMappingPolicy.uniqloVersion)
        #expect(sleeve?.measurementCode == .sleeveCenterBackToCuff)
        #expect(sleeve?.rawInfo == "목 중심부터 소매 끝")
        #expect(inseam?.measurementCode == .pantsInseamCrotchToHem)
        #expect(inseam?.displayKind == .totalLength)
        #expect(chest?.measurementCode == .chestWidthPitToPit)
        #expect(chest?.semanticStatus == .mapped)
        #expect(chest?.mappingVersion == MeasurementSourceMappingPolicy.uniqloVersion)
        #expect(length?.measurementCode == .bodyLengthBackNeckToHem)
        #expect(length?.semanticStatus == .mapped)
        #expect(records.allSatisfy { $0.methodSource == "uniqlo_kr" })

        let productSize = ParsedProductSizeNormalizer.makeProductSizes(from: sizes)[0]
        let uniqloReference = manualMeasurementViewModel(source: .uniqloSizeChart).makeUserFit()
        let fitmatchReference = manualMeasurementViewModel(source: .fitmatchMeasured).makeUserFit()
        #expect(uniqloReference != nil)
        #expect(fitmatchReference != nil)
        if let uniqloReference, let fitmatchReference {
            let engine = MeasurementComparisonEngine()
            let sameSourceComparison = engine.compare(
                productSize: productSize,
                referenceItem: uniqloReference,
                productCategory: .top,
                productDetailCategory: .shortSleeve
            )
            let crossSourceComparison = engine.compare(
                productSize: productSize,
                referenceItem: fitmatchReference,
                productCategory: .top,
                productDetailCategory: .shortSleeve
            )

            #expect(sameSourceComparison.status == .confirmed)
            #expect(sameSourceComparison.comparedKinds.contains(.chest))
            #expect(crossSourceComparison.status == .confirmed)
            #expect(crossSourceComparison.comparedKinds.contains(.chest))
        }
    }

    @Test func musinsaActualSizePreservesRawFieldsAndRaglanMeaning() throws {
        let json = """
        {
          "data": {
            "typeName": "나그랑",
            "typeNumber": 11,
            "webImage": "https://example.com/web.png",
            "mobileImage": "https://example.com/mobile.png",
            "sizes": [
              {
                "name": "M",
                "items": [
                  { "name": "총장", "value": "70" },
                  { "name": "가슴단면", "value": 54 },
                  { "name": "화장", "value": "82.5" }
                ]
              }
            ]
          }
        }
        """

        let result = try MusinsaActualSizeAPIParser().parseActualSize(
            from: Data(json.utf8),
            isTopCategory: true
        )
        let records = result.sizes.first?.measurementRecords ?? []
        let sleeve = records.first { $0.rawLabel == "화장" }
        let chest = records.first { $0.rawLabel == "가슴단면" }
        let length = records.first { $0.rawLabel == "총장" }

        #expect(result.typeNumber == 11)
        #expect(result.webImage == "https://example.com/web.png")
        #expect(sleeve?.measurementCode == .sleeveRaglanNeckToCuff)
        #expect(sleeve?.mappingVersion == MeasurementSourceMappingPolicy.musinsaVersion)
        #expect(sleeve?.methodProfile == "musinsa_type_11")
        #expect(sleeve?.rawValueText == "82.5")
        #expect(chest?.measurementCode == .chestWidthPitToPit)
        #expect(chest?.semanticStatus == .mapped)
        #expect(length?.measurementCode == .bodyLengthBackNeckToHem)
        #expect(length?.semanticStatus == .mapped)
    }

    @Test func musinsaActualSizeAcceptsLetterSizesWithProductDescriptors() throws {
        let json = """
        {
          "data": {
            "typeName": "셔츠",
            "typeNumber": 20,
            "sizes": [
              {
                "name": "S(린넨)",
                "items": [
                  { "name": "총장", "value": 0 },
                  { "name": "어깨너비", "value": 0 },
                  { "name": "가슴단면", "value": 0 },
                  { "name": "소매길이", "value": 0 }
                ]
              },
              {
                "name": "S(옥스포드)",
                "items": [
                  { "name": "총장", "value": 75 },
                  { "name": "어깨너비", "value": 55 },
                  { "name": "가슴단면", "value": 66 },
                  { "name": "소매길이", "value": 60 }
                ]
              },
              {
                "name": "M(White)",
                "items": [
                  { "name": "총장", "value": 77 },
                  { "name": "어깨너비", "value": 57 },
                  { "name": "가슴단면", "value": 68 },
                  { "name": "소매길이", "value": 61 }
                ]
              }
            ]
          }
        }
        """

        let result = try MusinsaActualSizeAPIParser().parseActualSize(
            from: Data(json.utf8),
            isTopCategory: true
        )
        let valid = ParsedSizeValidator.validSizes(result.sizes, category: .shirt)

        #expect(result.sizes.map(\.name) == ["S(옥스포드)", "M(White)"])
        #expect(valid.map(\.name) == ["S(옥스포드)", "M(White)"])
        #expect(valid.first?.measurements.chest == 66)
        #expect(valid.first?.measurements.totalLength == 75)
    }

    @Test func uniqloBottomCircumferencesBecomeWidthsAndPreserveRawValues() throws {
        let json = """
        {
          "result": {
            "items": [{
              "productId": "E999999-000",
              "sizeChart": [{
                "name": "M",
                "sizeParts": [
                  { "code": "waist-product-size", "name": "허리둘레", "measurements": [{ "value": "70", "unit": "cm" }] },
                  { "code": "hip-product-size", "name": "엉덩이둘레", "measurements": [{ "value": "104", "unit": "cm" }] },
                  { "code": "thigh", "name": "허벅지 너비", "measurements": [{ "value": "31", "unit": "cm" }] },
                  { "code": "rising-length", "name": "밑위 길이", "measurements": [{ "value": "29", "unit": "cm" }] },
                  { "code": "bottom-width", "name": "밑단 너비", "measurements": [{ "value": "22", "unit": "cm" }] },
                  { "code": "inseam", "name": "인심", "measurements": [{ "value": "76", "unit": "cm" }] }
                ]
              }]
            }]
          }
        }
        """

        let sizes = try UniqloSizeAPIParser().parseSizes(from: Data(json.utf8))
        let size = try #require(sizes.first)
        let records = size.measurementRecords
        let waist = records.first { $0.rawCode == "waist-product-size" }
        let hip = records.first { $0.rawCode == "hip-product-size" }

        #expect(size.measurements.waist == 35)
        #expect(size.measurements.hip == 52)
        #expect(waist?.value == 35)
        #expect(waist?.rawValueText == "70")
        #expect(waist?.measurementCode == .waistWidthEdgeToEdge)
        #expect(hip?.value == 52)
        #expect(hip?.rawValueText == "104")
        #expect(hip?.measurementCode == .hipWidthAtWidest)
        #expect(records.first { $0.rawCode == "thigh" }?.measurementCode == .thighWidthCrotchToOuter)
        let rise = records.first { $0.rawCode == "rising-length" }
        #expect(rise?.measurementCode == .riseCrotchToWaistFront)
        #expect(rise?.displayKind == .rise)
        #expect(records.first { $0.rawCode == "bottom-width" }?.measurementCode == .hemWidthEdgeToEdge)
        #expect(records.first { $0.rawCode == "inseam" }?.measurementCode == .pantsInseamCrotchToHem)
    }

    @Test func comparisonRepairsLegacyUniqloRiseStoredAsTotalLength() {
        let size = ProductSize(
            name: "L",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 29, sleeveLength: 0, rise: 0
            )
        )
        size.measurementRecords = [
            GarmentMeasurementRecord(
                value: 29,
                measurementCode: .riseCrotchToWaistFront,
                displayKind: .totalLength,
                methodSource: "uniqlo_kr",
                methodProfile: "legacy",
                inputSource: .importedSizeChart,
                mappingVersion: "legacy",
                rawCode: "rising-length",
                rawLabel: "밑위 길이",
                rawValueText: "29",
                evidenceLevel: .officialText,
                semanticStatus: .mapped,
                productSize: size
            )
        ]
        let item = UserFit(
            sourceName: "유니클로 공식몰",
            brandName: "유니클로",
            productName: "기준 바지",
            category: .bottom,
            detailCategory: .longPants,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 28, sleeveLength: 0, rise: 0
            ),
            fitMemo: "",
            satisfaction: 3
        )
        item.measurementRecords = [
            GarmentMeasurementRecord(
                value: 28,
                measurementCode: .riseCrotchToWaistFront,
                displayKind: .totalLength,
                methodSource: "uniqlo_kr",
                methodProfile: "legacy",
                inputSource: .importedSizeChart,
                mappingVersion: "legacy",
                rawCode: "rising-length",
                rawLabel: "밑위 길이",
                rawValueText: "28",
                evidenceLevel: .officialText,
                semanticStatus: .mapped,
                userFit: item
            )
        ]

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .bottom,
            productDetailCategory: .longPants
        )

        #expect(result.comparedItems.first?.kind == .rise)
        #expect(result.comparedItems.first?.signedDifference == 1)
        #expect(!result.comparedKinds.contains(.totalLength))
    }

    @Test func musinsaBottomWidthsAndExplicitLengthsUseCommonCodes() throws {
        let json = """
        {
          "data": {
            "typeName": "바지",
            "typeNumber": 6,
            "sizes": [{
              "name": "M",
              "items": [
                { "name": "허리단면", "value": 35 },
                { "name": "엉덩이단면", "value": 52 },
                { "name": "허벅지단면", "value": 31 },
                { "name": "밑위", "value": 29 },
                { "name": "밑단단면", "value": 22 },
                { "name": "총장", "value": 102 },
                { "name": "인심", "value": 76 }
              ]
            }]
          }
        }
        """

        let result = try MusinsaActualSizeAPIParser().parseActualSize(from: Data(json.utf8))
        let records = try #require(result.sizes.first).measurementRecords

        #expect(records.first { $0.rawLabel == "허리단면" }?.measurementCode == .waistWidthEdgeToEdge)
        #expect(records.first { $0.rawLabel == "엉덩이단면" }?.measurementCode == .hipWidthAtWidest)
        #expect(records.first { $0.rawLabel == "허벅지단면" }?.measurementCode == .thighWidthCrotchToOuter)
        #expect(records.first { $0.rawLabel == "밑위" }?.measurementCode == .riseCrotchToWaistFront)
        #expect(records.first { $0.rawLabel == "밑단단면" }?.measurementCode == .hemWidthEdgeToEdge)
        #expect(records.first { $0.rawLabel == "총장" }?.measurementCode == .pantsOutseamWaistToHem)
        #expect(records.first { $0.rawLabel == "인심" }?.measurementCode == .pantsInseamCrotchToHem)
    }

    @Test func musinsaTypeFiveMapsOfficialDiagramChestWidth() throws {
        let json = """
        {
          "data": {
            "typeName": "반소매티셔츠",
            "typeNumber": 5,
            "webImage": "https://example.com/type-5.png",
            "mobileImage": null,
            "sizes": [
              {
                "name": "M",
                "items": [
                  { "name": "총장", "value": 70 },
                  { "name": "어깨너비", "value": 48 },
                  { "name": "가슴단면", "value": 54 },
                  { "name": "소매길이", "value": 24 }
                ]
              }
            ]
          }
        }
        """

        let result = try MusinsaActualSizeAPIParser().parseActualSize(
            from: Data(json.utf8),
            isTopCategory: true
        )
        let records = result.sizes.first?.measurementRecords ?? []
        let chest = records.first { $0.rawLabel == "가슴단면" }
        let length = records.first { $0.rawLabel == "총장" }

        #expect(chest?.measurementCode == .chestWidthPitToPit)
        #expect(chest?.evidenceLevel == .officialDiagram)
        #expect(chest?.mappingVersion == MeasurementSourceMappingPolicy.musinsaVersion)
        #expect(length?.measurementCode == .bodyLengthBackNeckToHem)
        #expect(length?.semanticStatus == .mapped)

        let productSize = ParsedProductSizeNormalizer.makeProductSizes(from: result.sizes)[0]
        let referenceItem = manualMeasurementViewModel(source: .fitmatchMeasured).makeUserFit()
        #expect(referenceItem != nil)
        if let referenceItem {
            let comparison = MeasurementComparisonEngine().compare(
                productSize: productSize,
                referenceItem: referenceItem,
                productCategory: .top,
                productDetailCategory: .shortSleeve
            )
            #expect(comparison.status == .confirmed)
            #expect(comparison.comparedKinds.contains(.chest))
        }
    }

    @Test func sourceMeasurementMappingPolicyMapsSourceSpecificUpperMeasurements() {
        let verifiedMusinsaTypes = [5, 7, 8, 9, 10, 20, 21, 38]
        let verifiedMusinsa = MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 5, displayKind: .shoulder, rawLabel: "어깨너비"
        )
        let verifiedMusinsaChest = MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 5, displayKind: .chest, rawLabel: "가슴단면"
        )
        let verifiedMusinsaLength = MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 5,
            displayKind: .totalLength,
            rawLabel: "총장",
            isTopCategory: true
        )
        let unknownMusinsaType = MeasurementSourceMappingPolicy.musinsa(typeNumber: 999, displayKind: .shoulder)
        let verifiedUniqloSleeve = MeasurementSourceMappingPolicy.uniqlo(rawCode: "sleeve-length-cb")
        let verifiedUniqloChest = MeasurementSourceMappingPolicy.uniqlo(rawCode: "body-width")
        let verifiedUniqloLengths = [
            "body-length-back", "body-length", "knit-body-length-front"
        ].compactMap {
            MeasurementSourceMappingPolicy.uniqlo(rawCode: $0)?.code
        }
        let verifiedMusinsaLengths = [5, 11, 20, 21, 24, 999].compactMap {
            MeasurementSourceMappingPolicy.musinsa(
                typeNumber: $0,
                displayKind: .totalLength,
                rawLabel: "총장",
                isTopCategory: true
            )?.code
        }

        #expect(verifiedMusinsaTypes.allSatisfy {
            MeasurementSourceMappingPolicy.musinsa(
                typeNumber: $0, displayKind: .shoulder, rawLabel: "어깨너비"
            )?.code == .shoulderWidthSeamToSeam
        })
        #expect(verifiedMusinsaTypes.allSatisfy {
            MeasurementSourceMappingPolicy.musinsa(
                typeNumber: $0, displayKind: .sleeveLength, rawLabel: "소매길이"
            )?.code == .sleeveShoulderSeamToCuff
        })
        #expect(verifiedMusinsaTypes.allSatisfy {
            MeasurementSourceMappingPolicy.musinsa(
                typeNumber: $0, displayKind: .chest, rawLabel: "가슴단면"
            )?.code == .chestWidthPitToPit
        })
        #expect(verifiedMusinsa?.code == .shoulderWidthSeamToSeam)
        #expect(verifiedMusinsa?.mappingVersion == MeasurementSourceMappingPolicy.musinsaVersion)
        #expect(verifiedMusinsaChest?.code == .chestWidthPitToPit)
        #expect(verifiedMusinsaLength?.code == .bodyLengthBackNeckToHem)
        #expect(unknownMusinsaType == nil)
        #expect(verifiedUniqloSleeve?.code == .sleeveCenterBackToCuff)
        #expect(verifiedUniqloSleeve?.mappingVersion == MeasurementSourceMappingPolicy.uniqloVersion)
        #expect(verifiedUniqloChest?.code == .chestWidthPitToPit)
        #expect(verifiedUniqloChest?.code == verifiedMusinsaChest?.code)
        #expect(verifiedUniqloLengths == [
            .bodyLengthBackNeckToHem,
            .bodyLengthBackNeckToHem,
            .bodyLengthBackNeckToHem
        ])
        #expect(Set(verifiedMusinsaLengths) == [.bodyLengthBackNeckToHem])
        #expect(Set(verifiedUniqloLengths) == [.bodyLengthBackNeckToHem])
    }

    @Test func musinsaOfficialUpperTypesMapExactTotalLengthLabel() {
        for typeNumber in [5, 7, 8, 9, 10, 11, 20, 21, 22, 24, 25, 31, 38] {
            let mapping = MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber,
                displayKind: .totalLength,
                rawLabel: "총장",
                isTopCategory: true
            )
            #expect(mapping?.code == .bodyLengthBackNeckToHem)
            #expect(mapping?.mappingVersion == MeasurementSourceMappingPolicy.musinsaVersion)
        }

        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 999,
            displayKind: .totalLength,
            rawLabel: "기장",
            isTopCategory: true
        ) == nil)
        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 999,
            displayKind: .totalLength,
            rawLabel: "총장",
            isTopCategory: true
        ) == nil)
    }

    @Test func musinsaOfficialTypeTableMapsOnlyAuditedLabels() {
        let setInTypes = [5, 7, 8, 9, 10, 20, 21, 38]
        for typeNumber in setInTypes {
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .totalLength, rawLabel: "총장"
            )?.code == .bodyLengthBackNeckToHem)
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .shoulder, rawLabel: "어깨너비"
            )?.code == .shoulderWidthSeamToSeam)
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .chest, rawLabel: "가슴단면"
            )?.code == .chestWidthPitToPit)
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .sleeveLength, rawLabel: "소매길이"
            )?.code == .sleeveShoulderSeamToCuff)
        }

        for typeNumber in [11, 22, 31] {
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .totalLength, rawLabel: "총장"
            )?.code == .bodyLengthBackNeckToHem)
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .chest, rawLabel: "가슴단면"
            )?.code == .chestWidthPitToPit)
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .sleeveLength, rawLabel: "화장"
            )?.code == .sleeveRaglanNeckToCuff)
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .shoulder, rawLabel: "어깨너비"
            ) == nil)
        }

        for typeNumber in [24, 25] {
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .totalLength, rawLabel: "총장"
            )?.code == .bodyLengthBackNeckToHem)
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .shoulder, rawLabel: "어깨너비"
            )?.code == .shoulderWidthSeamToSeam)
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .chest, rawLabel: "가슴단면"
            )?.code == .chestWidthPitToPit)
            #expect(MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber, displayKind: .sleeveLength, rawLabel: "소매길이"
            ) == nil)
        }

        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 38, displayKind: .hip, rawLabel: "엉덩이단면"
        )?.code == .hipWidthAtWidest)
        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 14, displayKind: .totalLength, rawLabel: "총장"
        )?.code == .skirtLengthWaistToHem)
        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 19, displayKind: .waist, rawLabel: "허리단면"
        )?.code == .waistWidthEdgeToEdge)
        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 19, displayKind: .hip, rawLabel: "엉덩이단면"
        )?.code == .hipWidthAtWidest)
        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 999, displayKind: .chest, rawLabel: "가슴단면"
        ) == nil)
        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 5, displayKind: .totalLength, rawLabel: "기장"
        ) == nil)
    }

    @Test func uniqloAuditedCodesPreserveDifferentDefinitions() {
        #expect(MeasurementSourceMappingPolicy.uniqlo(rawCode: "sleeve-length")?.code == .sleeveShoulderSeamToCuff)
        #expect(MeasurementSourceMappingPolicy.uniqlo(rawCode: "sleeve-length-cb")?.code == .sleeveCenterBackToCuff)
        #expect(MeasurementSourceMappingPolicy.uniqlo(rawCode: "skirt-length")?.code == .skirtLengthWaistToHem)
        let bottomsWaist = MeasurementSourceMappingPolicy.uniqlo(rawCode: "waist-product-size-bottoms")
        #expect(bottomsWaist?.code == .waistWidthEdgeToEdge)
        #expect(bottomsWaist?.valueMultiplier == 0.5)
        #expect(bottomsWaist?.mappingVersion == MeasurementSourceMappingPolicy.uniqloVersion)
        #expect(MeasurementSourceMappingPolicy.uniqlo(rawCode: "body-width-gather-and-tack") == nil)
        #expect(MeasurementSourceMappingPolicy.uniqlo(rawCode: "neck-circumference") == nil)
    }

    @Test func comparisonUsesMatchedRecordValuesInsteadOfScalarMeasurements() {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 999, chest: 999, totalLength: 999, sleeveLength: 999)
        )
        size.measurementRecords = [
            comparisonRecord(value: 52, code: .chestWidthPitToPit, kind: .chest, productSize: size),
            comparisonRecord(value: 70, code: .bodyLengthBackNeckToHem, kind: .totalLength, productSize: size)
        ]
        let item = UserFit(
            brandName: "테스트",
            productName: "기준 옷",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(shoulder: 1, chest: 1, totalLength: 1, sleeveLength: 1),
            fitMemo: "",
            satisfaction: 3
        )
        item.measurementRecords = [
            comparisonRecord(value: 50, code: .chestWidthPitToPit, kind: .chest, userFit: item),
            comparisonRecord(value: 69, code: .bodyLengthBackNeckToHem, kind: .totalLength, userFit: item)
        ]

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )
        #expect(result.comparedItems.first { $0.kind == .chest }?.signedDifference == 2)
        #expect(result.comparedItems.first { $0.kind == .totalLength }?.signedDifference == 1)
    }

    @Test func samePlatformAndFormatUsesMatchingSourceFieldsDirectly() {
        let size = ProductSize(
            name: "L",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 0, sleeveLength: 0)
        )
        size.measurementRecords = [
            comparisonRecord(
                value: 48, code: .shoulderWidthSeamToSeam, kind: .shoulder,
                methodSource: "musinsa", methodProfile: "musinsa_type_5",
                rawCode: "1", rawLabel: "어깨너비", productSize: size
            ),
            comparisonRecord(
                value: 54, code: .chestWidthPitToPit, kind: .chest,
                methodSource: "musinsa", methodProfile: "musinsa_type_5",
                rawCode: "2", rawLabel: "가슴단면", productSize: size
            )
        ]
        let item = comparisonUserFit(name: "기준 옷", detail: .shortSleeve, sleeve: 0)
        item.measurementRecords = [
            comparisonRecord(
                value: 47, code: .upperWaistWidthEdgeToEdge, kind: .shoulder,
                methodSource: "musinsa", methodProfile: "musinsa_type_5",
                rawCode: "1", rawLabel: "어깨너비", userFit: item
            ),
            comparisonRecord(
                value: 53, code: .waistWidthEdgeToEdge, kind: .chest,
                methodSource: "musinsa", methodProfile: "musinsa_type_5",
                rawCode: "2", rawLabel: "가슴단면", userFit: item
            )
        ]

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )

        #expect(result.status == .confirmed)
        #expect(result.comparedItems.first { $0.kind == .shoulder }?.signedDifference == 1)
        #expect(result.comparedItems.first { $0.kind == .chest }?.signedDifference == 1)
    }

    @Test func comparisonSelectsOfficialCircumferenceOrFitMatchWidthBySourceFormat() throws {
        func product(
            source: String,
            profile: String,
            waistValue: Double,
            rawLabel: String,
            rawValue: String
        ) -> ProductSize {
            let size = ProductSize(
                name: "L",
                measurements: GarmentMeasurements(
                    shoulder: 0, chest: 0, totalLength: 100, sleeveLength: 0,
                    waist: waistValue
                )
            )
            size.measurementRecords = [
                comparisonRecord(
                    value: waistValue, code: .waistWidthEdgeToEdge, kind: .waist,
                    methodSource: source, methodProfile: profile,
                    rawCode: "waist-product-size", rawLabel: rawLabel,
                    rawValueText: rawValue, productSize: size
                )
            ]
            return size
        }
        func reference(
            source: String,
            profile: String,
            waistValue: Double,
            rawLabel: String,
            rawValue: String
        ) -> UserFit {
            let item = comparisonUserFit(
                name: "기준 바지", category: .bottom, detail: .longPants,
                sleeve: 0, totalLength: 99
            )
            item.measurementRecords = [
                comparisonRecord(
                    value: waistValue, code: .waistWidthEdgeToEdge, kind: .waist,
                    methodSource: source, methodProfile: profile,
                    rawCode: "waist-product-size", rawLabel: rawLabel,
                    rawValueText: rawValue, userFit: item
                )
            ]
            return item
        }
        func waistItem(_ size: ProductSize, _ item: UserFit) throws -> MeasurementComparisonItem {
            let result = MeasurementComparisonEngine().compare(
                productSize: size,
                referenceItem: item,
                productCategory: .bottom,
                productDetailCategory: .longPants
            )
            return try #require(result.comparedItems.first { $0.kind == .waist })
        }

        let uniqloToUniqlo = try waistItem(
            product(
                source: "uniqlo_kr", profile: "uniqlo_bottom_v1",
                waistValue: 40, rawLabel: "허리둘레", rawValue: "80"
            ),
            reference(
                source: "uniqlo_kr", profile: "uniqlo_bottom_v1",
                waistValue: 39, rawLabel: "허리둘레", rawValue: "78"
            )
        )
        #expect(uniqloToUniqlo.displayTitle == "허리둘레")
        #expect(uniqloToUniqlo.productValue == 80)
        #expect(uniqloToUniqlo.referenceValue == 78)
        #expect(uniqloToUniqlo.signedDifference == 2)

        let circumferenceToWidth = try waistItem(
            product(
                source: "uniqlo_kr", profile: "uniqlo_bottom_v1",
                waistValue: 40, rawLabel: "허리둘레", rawValue: "80"
            ),
            reference(
                source: "musinsa", profile: "musinsa_type_6",
                waistValue: 39, rawLabel: "허리단면", rawValue: "39"
            )
        )
        #expect(circumferenceToWidth.displayTitle == "허리단면")
        #expect(circumferenceToWidth.productValue == 40)
        #expect(circumferenceToWidth.referenceValue == 39)
        #expect(circumferenceToWidth.signedDifference == 1)

        let differentBrandCircumferences = try waistItem(
            product(
                source: "uniqlo_kr", profile: "uniqlo_bottom_v1",
                waistValue: 40, rawLabel: "허리둘레", rawValue: "80"
            ),
            reference(
                source: "other_shop", profile: "brand_chart",
                waistValue: 39, rawLabel: "허리둘레", rawValue: "78"
            )
        )
        #expect(differentBrandCircumferences.displayTitle == "허리둘레")
        #expect(differentBrandCircumferences.productValue == 80)
        #expect(differentBrandCircumferences.referenceValue == 78)
        #expect(differentBrandCircumferences.signedDifference == 2)
    }

    @Test func uniqloOfficialTopComparisonKeepsSleeveAndHasNoManualPenalty() throws {
        let measurements = GarmentMeasurements(
            shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24
        )
        let size = ProductSize(name: "M", measurements: measurements)
        let fields: [(MeasurementKind, MeasurementCode, String, String)] = [
            (.shoulder, .shoulderWidthSeamToSeam, "shoulder-width", "어깨너비"),
            (.chest, .chestWidthPitToPit, "body-width", "가슴너비"),
            (.totalLength, .bodyLengthBackNeckToHem, "body-length", "몸길이"),
            (.sleeveLength, .sleeveShoulderSeamToCuff, "sleeve-length", "소매길이")
        ]
        size.measurementRecords = fields.map { kind, code, rawCode, rawLabel in
            comparisonRecord(
                value: measurements.value(for: kind),
                code: code,
                kind: kind,
                methodSource: "uniqlo_kr",
                methodProfile: "uniqlo_official_top",
                rawCode: rawCode,
                rawLabel: rawLabel,
                rawValueText: String(measurements.value(for: kind)),
                productSize: size
            )
        }
        let product = Product(
            name: "DRY-EX폴로셔츠",
            category: .top,
            metadata: ProductMetadata(
                sourceCategoryPath: "셔츠 > 폴로셔츠 (카라티) > DRY-EX"
            ),
            sourceName: "유니클로 공식몰",
            sizes: [size]
        )
        product.sleeveTypeRawValue = ComparisonLengthType.short.rawValue

        let item = UserFit(
            sourceName: "유니클로 공식몰",
            sourceCategoryPath: "상의 > 티셔츠",
            brandName: "유니클로",
            productName: "크루넥T",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: measurements,
            fitMemo: "",
            satisfaction: 3
        )
        item.sleeveTypeRawValue = ComparisonLengthType.short.rawValue
        item.measurementRecords = fields.map { kind, code, rawCode, rawLabel in
            comparisonRecord(
                value: measurements.value(for: kind),
                code: code,
                kind: kind,
                methodSource: "uniqlo_kr",
                methodProfile: "uniqlo_official_top",
                rawCode: rawCode,
                rawLabel: rawLabel,
                rawValueText: String(measurements.value(for: kind)),
                userFit: item
            )
        }

        let mismatch = ComparisonProfileMatcher().manualMismatch(
            product: product,
            productDetailCategory: .shirt,
            selectedItem: item
        )
        #expect(!mismatch.excludedKinds.contains(.sleeveLength))

        let result = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: item,
            productDetailCategory: .shirt
        ))
        #expect(result.recommendationScore == 100)
        #expect(result.comparedMeasurementUsages.contains { $0.kind == .sleeveLength })
        #expect(!result.measurementExclusions.contains {
            $0.kind == .sleeveLength && $0.reason == .categoryPolicy
        })
    }

    @Test func uniqloPoloInfersShortSleeveFromOfficialSizeChart() {
        let sleeve = ParsedMeasurement(
            value: 24,
            measurementCode: .sleeveShoulderSeamToCuff,
            displayKind: .sleeveLength,
            methodSource: "uniqlo_kr",
            methodProfile: "uniqlo_official_top",
            inputSource: .importedSizeChart,
            mappingVersion: MeasurementSourceMappingPolicy.uniqloVersion,
            rawCode: "sleeve-length",
            rawLabel: "소매길이",
            rawValueText: "24",
            evidenceLevel: .officialText,
            semanticStatus: .mapped
        )
        let size = ParsedProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24
            ),
            measurementRecords: [sleeve]
        )
        let metadata = UniqloProductMetadata(
            sourceURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E482305-000/00")!,
            productID: "E482305-000",
            goodsID: "482305",
            colorCode: "00",
            brandName: "유니클로",
            productName: "DRY-EX폴로셔츠",
            category: .top,
            detailCategory: .other
        )

        #expect(metadata.withInferredSleeveDetail(from: [size]).detailCategory == .shortSleeve)
    }

    @Test func unspecifiedTopSleeveTypeUsesMeasurementMethodSpecificLengthRules() {
        func product(
            name: String,
            sleeveValue: Double,
            sleeveCode: MeasurementCode
        ) -> Product {
            let size = ProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 48, chest: 54, totalLength: 70, sleeveLength: sleeveValue
                )
            )
            size.measurementRecords = [
                comparisonRecord(
                    value: sleeveValue,
                    code: sleeveCode,
                    kind: .sleeveLength,
                    methodSource: "uniqlo_kr",
                    rawCode: sleeveCode == .sleeveCenterBackToCuff
                        ? "sleeve-length-cb"
                        : "sleeve-length",
                    rawLabel: sleeveCode == .sleeveCenterBackToCuff ? "화장" : "소매길이",
                    productSize: size
                )
            ]
            return Product(
                name: name,
                category: .top,
                metadata: ProductMetadata(sourceCategoryPath: "셔츠 > 폴로셔츠"),
                sourceName: "유니클로 공식몰",
                sizes: [size]
            )
        }

        let setInShort = product(
            name: "소매 구분 없는 폴로셔츠",
            sleeveValue: 24,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let centerBackShort = product(
            name: "소매 구분 없는 티셔츠",
            sleeveValue: 45,
            sleeveCode: .sleeveCenterBackToCuff
        )
        let centerBackLong = product(
            name: "소매 구분 없는 셔츠",
            sleeveValue: 78,
            sleeveCode: .sleeveCenterBackToCuff
        )

        let matcher = ComparisonProfileMatcher()
        #expect(matcher.profile(for: setInShort, detailCategory: .other).lengthType == .short)
        #expect(matcher.profile(for: centerBackShort, detailCategory: .other).lengthType == .short)
        #expect(matcher.profile(for: centerBackLong, detailCategory: .other).lengthType == .long)
    }

    @Test func learnedPlatformLengthBoundariesClassifyUnspecifiedGarments() {
        func infer(
            category: ClothingCategory,
            gender: UserGender,
            value: Double,
            code: MeasurementCode,
            source: String
        ) -> ComparisonLengthType {
            GarmentLengthInferencePolicy.infer(
                category: category,
                gender: gender,
                samples: [.init(value: value, code: code, methodSource: source)]
            )
        }

        #expect(infer(
            category: .top, gender: .men, value: 67,
            code: .sleeveCenterBackToCuff, source: "uniqlo_kr"
        ) == .short)
        #expect(infer(
            category: .top, gender: .men, value: 68,
            code: .sleeveCenterBackToCuff, source: "uniqlo_kr"
        ) == .long)
        #expect(infer(
            category: .top, gender: .women, value: 43,
            code: .sleeveShoulderSeamToCuff, source: "musinsa"
        ) == .short)
        #expect(infer(
            category: .top, gender: .women, value: 44,
            code: .sleeveShoulderSeamToCuff, source: "musinsa"
        ) == .long)
        #expect(infer(
            category: .bottom, gender: .women, value: 65,
            code: .pantsOutseamWaistToHem, source: "musinsa"
        ) == .short)
        #expect(infer(
            category: .bottom, gender: .women, value: 66,
            code: .pantsOutseamWaistToHem, source: "musinsa"
        ) == .long)
        #expect(infer(
            category: .bottom, gender: .men, value: 46.5,
            code: .pantsInseamCrotchToHem, source: "uniqlo_kr"
        ) == .short)
        #expect(infer(
            category: .bottom, gender: .men, value: 47,
            code: .pantsInseamCrotchToHem, source: "uniqlo_kr"
        ) == .long)
        #expect(infer(
            category: .top, gender: .kids, value: 34.5,
            code: .sleeveCenterBackToCuff, source: "uniqlo_kr"
        ) == .short)
        #expect(infer(
            category: .top, gender: .kids, value: 35,
            code: .sleeveCenterBackToCuff, source: "uniqlo_kr"
        ) == .long)
    }

    @Test func normalizedParsedProductReplacesOtherWithMeasuredLengthCategory() {
        func parsedSize(
            value: Double,
            code: MeasurementCode,
            kind: MeasurementDisplayKind,
            source: String
        ) -> ParsedProductSize {
            ParsedProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 0,
                    chest: 0,
                    totalLength: kind == .totalLength ? value : 70,
                    sleeveLength: kind == .sleeveLength ? value : 0
                ),
                measurementRecords: [
                    ParsedMeasurement(
                        value: value,
                        measurementCode: code,
                        displayKind: kind,
                        methodSource: source,
                        inputSource: .importedSizeChart,
                        rawLabel: kind == .sleeveLength ? "소매길이" : "총장",
                        evidenceLevel: .officialText,
                        semanticStatus: .mapped
                    )
                ]
            )
        }

        let top = ParsedProductInfo(
            sourceURL: URL(string: "https://example.com/top")!,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "분류 미지정 상의",
            category: .top,
            detailCategory: .other,
            sizes: [parsedSize(
                value: 61,
                code: .sleeveShoulderSeamToCuff,
                kind: .sleeveLength,
                source: "musinsa"
            )],
            productTargetGender: .women
        ).normalizedSizes()
        let bottom = ParsedProductInfo(
            sourceURL: URL(string: "https://example.com/bottom")!,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            brandName: "유니클로",
            productName: "분류 미지정 팬츠",
            category: .bottom,
            detailCategory: .other,
            sizes: [parsedSize(
                value: 72,
                code: .pantsInseamCrotchToHem,
                kind: .totalLength,
                source: "uniqlo_kr"
            )],
            productTargetGender: .men
        ).normalizedSizes()

        #expect(top.detailCategory == .longSleeve)
        #expect(bottom.detailCategory == .longPants)
    }

    @Test func differentPlatformFormatsRequireCanonicalMeasurementCodes() {
        let size = ProductSize(
            name: "L",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 0, sleeveLength: 0)
        )
        size.measurementRecords = [
            comparisonRecord(
                value: 48, code: .shoulderWidthSeamToSeam, kind: .shoulder,
                methodSource: "musinsa", methodProfile: "musinsa_type_5",
                rawCode: "1", rawLabel: "어깨너비", productSize: size
            ),
            comparisonRecord(
                value: 54, code: .chestWidthPitToPit, kind: .chest,
                methodSource: "musinsa", methodProfile: "musinsa_type_5",
                rawCode: "2", rawLabel: "가슴단면", productSize: size
            )
        ]
        let item = comparisonUserFit(name: "기준 옷", detail: .shortSleeve, sleeve: 0)
        item.measurementRecords = [
            comparisonRecord(
                value: 47, code: .upperWaistWidthEdgeToEdge, kind: .shoulder,
                methodSource: "musinsa_fallback", methodProfile: "structured_size_table",
                rawCode: "1", rawLabel: "어깨너비", userFit: item
            ),
            comparisonRecord(
                value: 53, code: .waistWidthEdgeToEdge, kind: .chest,
                methodSource: "musinsa_fallback", methodProfile: "structured_size_table",
                rawCode: "2", rawLabel: "가슴단면", userFit: item
            )
        ]

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )

        #expect(result.status == .insufficientEvidence)
        #expect(result.comparedItems.isEmpty)
    }

    @Test func alternativeSizeSummariesUseCategorySpecificMeasurements() {
        #expect(ClothingCategory.top.alternativeSizeSummaryKinds(
            detailCategory: .shortSleeve,
            gender: .men
        ) == [.shoulder, .chest, .totalLength, .sleeveLength])
        #expect(ClothingCategory.outer.alternativeSizeSummaryKinds(
            detailCategory: .jacket,
            gender: .men
        ) == [.shoulder, .chest, .totalLength, .sleeveLength])
        #expect(ClothingCategory.bottom.alternativeSizeSummaryKinds(
            detailCategory: .longPants,
            gender: .men
        ) == [.waist, .hip, .thigh, .totalLength])
        #expect(ClothingCategory.dress.alternativeSizeSummaryKinds(
            detailCategory: .onePiece,
            gender: .women
        ) == [.chest, .waist, .hip, .totalLength])
        #expect(ClothingCategory.underwear.alternativeSizeSummaryKinds(
            detailCategory: .womenBra,
            gender: .women
        ) == [.underBust, .chest])
        #expect(ClothingCategory.shoes.alternativeSizeSummaryKinds(
            detailCategory: .sneakers,
            gender: .unisex
        ) == [.footLength])
        #expect(ClothingCategory.accessory.alternativeSizeSummaryKinds(
            detailCategory: .watch,
            gender: .unisex
        ).isEmpty)
    }

    @Test func comparisonDifferenceTextUsesClosetItemAsReference() {
        #expect(MeasurementDifferenceReferenceText.text(
            kind: .totalLength,
            difference: 2
        ) == "내 옷보다 2cm 길어요")
        #expect(MeasurementDifferenceReferenceText.text(
            kind: .sleeveLength,
            difference: -2.5
        ) == "내 옷보다 2.5cm 짧아요")
        #expect(MeasurementDifferenceReferenceText.text(
            kind: .chest,
            difference: 3
        ) == "내 옷보다 3cm 넓어요")
        #expect(MeasurementDifferenceReferenceText.text(
            kind: .waist,
            difference: -1
        ) == "내 옷보다 1cm 좁아요")
        #expect(MeasurementDifferenceReferenceText.text(
            kind: .hip,
            difference: 0
        ) == "내 옷과 같아요")
    }

    @Test func uniqloGenericSleeveDoesNotPairWithCenterBackSleeve() {
        let size = comparisonSize(
            shoulder: 0,
            sleeve: 61,
            shoulderCode: .unknown,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let item = comparisonItem(
            shoulder: 0,
            sleeve: 82,
            shoulderCode: .unknown,
            sleeveCode: .sleeveCenterBackToCuff
        )
        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .top,
            productDetailCategory: .longSleeve
        )
        #expect(result.exclusions.contains {
            $0.kind == .sleeveLength && $0.reason == .incompatibleMeasurementCode
        })
    }

    @Test func musinsaTypeFiveAndTwentyOneCompareCommonTotalLength() {
        let size = ProductSize(
            name: "L",
            measurements: GarmentMeasurements(shoulder: 0, chest: 54, totalLength: 70, sleeveLength: 0)
        )
        size.measurementRecords = [
            comparisonRecord(value: 54, code: .chestWidthPitToPit, kind: .chest, productSize: size),
            comparisonRecord(value: 70, code: .bodyLengthBackNeckToHem, kind: .totalLength, productSize: size)
        ]
        let item = UserFit(
            sourceName: "무신사",
            brandName: "테스트",
            productName: "type 21 니트",
            category: .top,
            detailCategory: .longSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(shoulder: 0, chest: 53, totalLength: 69, sleeveLength: 0),
            fitMemo: "",
            satisfaction: 4
        )
        item.measurementRecords = [
            comparisonRecord(value: 53, code: .chestWidthPitToPit, kind: .chest, userFit: item),
            comparisonRecord(value: 69, code: .bodyLengthBackNeckToHem, kind: .totalLength, userFit: item)
        ]

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )

        #expect(result.comparedKinds.contains(.totalLength))
        #expect(!result.exclusions.contains {
            $0.kind == .totalLength && $0.reason == .incompatibleMeasurementCode
        })
    }

    @Test func parsedMeasurementsBecomeOwnedProductSizeRecords() {
        let parsed = ParsedProductSize(
            name: "M",
            measurements: measurements(chest: 54),
            measurementRecords: [
                ParsedMeasurement(
                    value: 54,
                    measurementCode: .unknown,
                    displayKind: .chest,
                    methodSource: "uniqlo_kr",
                    inputSource: .importedSizeChart,
                    rawCode: "body-width",
                    rawLabel: "가슴너비",
                    rawValueText: "54",
                    evidenceLevel: .unknown,
                    semanticStatus: .unknownDefinition
                )
            ]
        )

        let size = ParsedProductSizeNormalizer.makeProductSizes(from: [parsed])[0]

        #expect(size.measurementRecords.count == 1)
        #expect(size.measurementRecords.first?.productSize === size)
        #expect(size.measurementSchemaVersion == 1)
        #expect(size.measurementMigrationStatus == .completed)
    }

    @Test func userFitCopiesMeasurementRecordsAsIndependentSnapshot() {
        let sourceSize = ParsedProductSizeNormalizer.makeProductSizes(from: [
            ParsedProductSize(
                name: "M",
                measurements: measurements(chest: 54),
                measurementRecords: [
                    ParsedMeasurement(
                        value: 54,
                        measurementCode: .unknown,
                        displayKind: .chest,
                        methodSource: "uniqlo_kr",
                        inputSource: .importedSizeChart,
                        rawCode: "body-width",
                        rawLabel: "가슴너비",
                        rawValueText: "54",
                        evidenceLevel: .unknown,
                        semanticStatus: .unknownDefinition
                    )
                ]
            )
        ])[0]
        let item = UserFit(
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            brandName: "유니클로",
            productName: "티셔츠",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: sourceSize.measurements,
            fitMemo: "",
            satisfaction: 0,
            sourceProductSize: sourceSize
        )

        item.replaceMeasurementRecords(with: sourceSize.measurementRecords)

        #expect(item.measurementRecords.count == 1)
        #expect(item.measurementRecords[0].id != sourceSize.measurementRecords[0].id)
        #expect(item.measurementRecords[0].userFit === item)
        #expect(item.measurementRecords[0].productSize == nil)
        #expect(item.measurementMigrationStatus == .completed)
    }

    @Test func measurementComparisonUsesOnlyIdenticalVerifiedCodes() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let item = comparisonItem(
            shoulder: 48,
            sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )

        #expect(result.status == .confirmed)
        #expect(result.comparedKinds == [.shoulder, .sleeveLength])
        #expect(result.score == 90)
        #expect(result.exclusions.contains { $0.kind == .chest && $0.reason == .unverifiedProductDefinition })
    }

    @Test func measurementComparisonExcludesDifferentSleeveDefinitions() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 47,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff
        )
        let item = comparisonItem(
            shoulder: 48,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )

        #expect(result.status == .insufficientEvidence)
        #expect(result.comparedKinds == [.shoulder])
        #expect(result.exclusions.contains {
            $0.kind == .sleeveLength
                && $0.reason == .incompatibleMeasurementCode
                && $0.productCode == .sleeveCenterBackToCuff
                && $0.referenceCode == .sleeveShoulderSeamToCuff
                && $0.productDefinition == "등 중심부터 소매 끝까지"
                && $0.referenceDefinition == "어깨 봉제선부터 소매 끝까지"
        })
    }

    @Test func bottomComparisonRequiresTwoCoreWidthMeasurements() {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 100,
                sleeveLength: 0,
                waist: 39,
                hip: 51
            )
        )
        size.measurementRecords = [
            comparisonRecord(value: 39, code: .waistWidthEdgeToEdge, kind: .waist, productSize: size),
            comparisonRecord(value: 51, code: .hipWidthAtWidest, kind: .hip, productSize: size),
            comparisonRecord(value: 100, code: .pantsOutseamWaistToHem, kind: .totalLength, productSize: size)
        ]
        let item = UserFit(
            sourceName: "직접 측정",
            brandName: "테스트",
            productName: "기준 바지",
            category: .bottom,
            detailCategory: .slacks,
            sizeName: "기준",
            measurements: GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 99,
                sleeveLength: 0,
                waist: 38,
                hip: 50
            ),
            fitMemo: "",
            satisfaction: 4
        )
        item.measurementRecords = [
            comparisonRecord(value: 38, code: .waistWidthEdgeToEdge, kind: .waist, userFit: item),
            comparisonRecord(value: 50, code: .hipWidthAtWidest, kind: .hip, userFit: item),
            comparisonRecord(value: 99, code: .pantsOutseamWaistToHem, kind: .totalLength, userFit: item)
        ]

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .bottom,
            productDetailCategory: .slacks
        )

        #expect(result.status == .confirmed)
        #expect(result.comparedKinds == [.waist, .hip, .totalLength])
        #expect(result.minimumComparableCount == 2)
        #expect(result.requiredKinds == [.waist, .hip, .thigh])
        #expect(result.minimumRequiredKindCount == 2)
    }

    @Test func bottomWidthAndLengthAloneDoNotConfirmRecommendation() {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 100,
                sleeveLength: 0,
                waist: 39
            )
        )
        size.measurementRecords = [
            comparisonRecord(value: 39, code: .waistWidthEdgeToEdge, kind: .waist, productSize: size),
            comparisonRecord(value: 100, code: .pantsOutseamWaistToHem, kind: .totalLength, productSize: size)
        ]
        let item = UserFit(
            sourceName: "직접 측정",
            brandName: "테스트",
            productName: "기준 바지",
            category: .bottom,
            detailCategory: .slacks,
            sizeName: "기준",
            measurements: GarmentMeasurements(
                shoulder: 0,
                chest: 0,
                totalLength: 99,
                sleeveLength: 0,
                waist: 38
            ),
            fitMemo: "",
            satisfaction: 4
        )
        item.measurementRecords = [
            comparisonRecord(value: 38, code: .waistWidthEdgeToEdge, kind: .waist, userFit: item),
            comparisonRecord(value: 99, code: .pantsOutseamWaistToHem, kind: .totalLength, userFit: item)
        ]

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .bottom,
            productDetailCategory: .slacks
        )

        #expect(result.comparedKinds == [.waist, .totalLength])
        #expect(result.status == .insufficientEvidence)
    }

    @Test func outerComparisonRequiresChestAndOneAdditionalMeasurement() {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 48,
                chest: 58,
                totalLength: 72,
                sleeveLength: 63,
                hem: 56
            )
        )
        size.measurementRecords = [
            comparisonRecord(value: 58, code: .chestWidthPitToPit, kind: .chest, productSize: size),
            comparisonRecord(value: 72, code: .bodyLengthHPSToHemFront, kind: .totalLength, productSize: size),
            comparisonRecord(value: 56, code: .hemWidthEdgeToEdge, kind: .hem, productSize: size)
        ]
        let item = UserFit(
            sourceName: "직접 측정",
            brandName: "테스트",
            productName: "기준 재킷",
            category: .outer,
            detailCategory: .jacket,
            sizeName: "기준",
            measurements: GarmentMeasurements(
                shoulder: 47,
                chest: 57,
                totalLength: 71,
                sleeveLength: 62,
                hem: 55
            ),
            fitMemo: "",
            satisfaction: 4
        )
        item.measurementRecords = [
            comparisonRecord(value: 57, code: .chestWidthPitToPit, kind: .chest, userFit: item),
            comparisonRecord(value: 71, code: .bodyLengthHPSToHemFront, kind: .totalLength, userFit: item),
            comparisonRecord(value: 55, code: .hemWidthEdgeToEdge, kind: .hem, userFit: item)
        ]

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .outer,
            productDetailCategory: .jacket
        )

        #expect(result.status == .confirmed)
        #expect(result.comparedKinds == [.chest, .totalLength, .hem])
        #expect(result.requiredAllKinds == [.chest])
    }

    @Test func outerShoulderAndSleeveWithoutChestAreInsufficient() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 64,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let item = comparisonItem(
            shoulder: 49,
            sleeve: 63,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .outer,
            productDetailCategory: .jacket
        )

        #expect(result.comparedKinds == [.shoulder, .sleeveLength])
        #expect(result.status == .insufficientEvidence)
        #expect(result.requiredAllKinds == [.chest])
    }

    @Test func recommendationIsBlockedWhenCompatibleEvidenceIsInsufficient() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 47,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff
        )
        let product = Product(name: "유니클로 티셔츠", category: .top, sizes: [size])
        let item = comparisonItem(
            shoulder: 48,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let history = RecommendationService().recommend(
            product: product,
            selectedReferenceItem: item,
            productDetailCategory: .shortSleeve
        )

        #expect(history == nil)
    }

    @Test func insufficientRecommendationReturnsUnsavedReferenceEvidence() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 47,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff
        )
        let product = Product(name: "유니클로 티셔츠", category: .top, sizes: [size])
        let item = comparisonItem(
            shoulder: 48,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let service = RecommendationService()
        let history = service.recommend(
            product: product,
            selectedReferenceItem: item,
            productDetailCategory: .shortSleeve
        )
        let evidence = service.insufficientEvidence(
            product: product,
            selectedReferenceItem: item,
            productDetailCategory: .shortSleeve
        )

        #expect(history == nil)
        #expect(evidence?.comparisonResult.status == .insufficientEvidence)
        #expect(evidence?.comparedKinds == [.shoulder])
        #expect(evidence?.comparisonResult.minimumComparableCount == 2)
        #expect(evidence?.comparisonResult.exclusions.contains {
            $0.kind == .sleeveLength && $0.reason == .incompatibleMeasurementCode
        } == true)
    }

    @Test func resultReferenceSelectionReplacesResultWhenEvidenceIsCompatible() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "무신사 티셔츠", category: .top, sizes: [size])
        let selectedItem = comparisonItem(
            shoulder: 48,
            sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let outcome = ResultReferenceComparisonResolver.resolve(
            product: product,
            selectedReferenceItem: selectedItem,
            productDetailCategory: .shortSleeve
        )

        guard case .success(let history) = outcome else {
            Issue.record("호환 가능한 옷 선택은 새 추천 결과를 반환해야 합니다.")
            return
        }
        let selectedID = selectedItem.id
        let resultReferenceID = history.userFit.id
        #expect(outcome.shouldDismissPicker)
        #expect(resultReferenceID == selectedID)
        #expect(history.comparisonStatus == .confirmed)
    }

    @Test func resultReferenceSelectionKeepsPickerForInsufficientEvidence() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 47,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff
        )
        let product = Product(name: "유니클로 티셔츠", category: .top, sizes: [size])
        let selectedItem = comparisonItem(
            shoulder: 48,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let outcome = ResultReferenceComparisonResolver.resolve(
            product: product,
            selectedReferenceItem: selectedItem,
            productDetailCategory: .shortSleeve
        )

        guard case .insufficient(let evidence) = outcome else {
            Issue.record("근거가 부족한 옷 선택은 실패 상태를 반환해야 합니다.")
            return
        }
        #expect(!outcome.shouldDismissPicker)
        #expect(evidence?.comparisonResult.status == .insufficientEvidence)
        #expect(evidence?.comparedKinds == [.shoulder])
        #expect(evidence?.missingKinds.contains(.sleeveLength) == true)
    }

    @Test func automaticFlowKeepsProfileCompatibleItemForInsufficientEvidenceScreen() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 47,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff
        )
        let product = Product(name: "유니클로 티셔츠", category: .top, sizes: [size])
        let item = comparisonItem(
            shoulder: 48,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let service = RecommendationService()

        let match = service.automaticMatchResult(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [item]
        )
        let history = service.recommend(
            product: product,
            userFits: [item],
            productDetailCategory: .shortSleeve,
            allowsGlobalFallback: false
        )
        let evidence = service.insufficientEvidence(
            product: product,
            userFits: [item],
            productDetailCategory: .shortSleeve,
            allowsGlobalFallback: false
        )

        #expect(match.state == .compatible)
        #expect(match.compatibleCandidates.map(\.id) == [item.id])
        #expect(history == nil)
        #expect(evidence?.referenceItem.id == item.id)
        #expect(evidence?.comparisonResult.status == .insufficientEvidence)
    }

    @Test func recommendationStoresUsedCodesAndExclusionReasons() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "무신사 티셔츠", category: .top, sizes: [size])
        let item = comparisonItem(
            shoulder: 48,
            sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let history = RecommendationService().recommend(
            product: product,
            selectedReferenceItem: item,
            productDetailCategory: .shortSleeve
        )

        #expect(history?.comparisonStatus == .confirmed)
        #expect(history?.comparedMeasurementUsages.map(\.measurementCode) == [
            .shoulderWidthSeamToSeam, .sleeveShoulderSeamToCuff
        ])
        #expect(history?.measurementExclusions.contains {
            $0.kind == .chest && $0.reason == .unverifiedProductDefinition
        } == true)
    }

    @Test func automaticMatchRejectsKnownConstructionConflict() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let setIn = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let raglan = comparisonItem(
            shoulder: 49,
            sleeve: 45,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveRaglanNeckToCuff
        )

        let result = ComparisonProfileMatcher().match(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [raglan, setIn]
        )

        #expect(result.state == .compatible)
        #expect(result.compatibleCandidates.map(\.id) == [setIn.id])
    }

    @Test func compatibleRepresentativeOutranksRicherMeasurementEvidence() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        markChestComparable(size.measurementRecords)
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let representative = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        representative.isRepresentative = true
        let richerEvidence = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        markChestComparable(richerEvidence.measurementRecords)

        let ranked = RecommendationService().rankedFitMatches(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [representative, richerEvidence]
        )

        #expect(ranked.first?.userFit.id == representative.id)
        #expect(ranked.first?.compatibleMeasurementCount == 2)
        let plan = RecommendationService().referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [representative, richerEvidence]
        )
        #expect(plan.automaticallySelectedCandidate?.id == representative.id)
        #expect(!plan.requiresUserSelection)
    }

    @Test func compatibleRepresentativeOutranksHigherSimilarity() {
        let size = comparisonSize(
            shoulder: 50, sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let representative = comparisonItem(
            shoulder: 45, sleeve: 19,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        representative.isRepresentative = true
        let closer = comparisonItem(
            shoulder: 50, sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let plan = RecommendationService().referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [closer, representative]
        )

        #expect(plan.automaticallySelectedCandidate?.id == representative.id)
    }

    @Test func compatibleRepresentativeOutranksSameBrandCandidate() {
        let size = comparisonSize(
            shoulder: 50, sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(
            name: "반팔 티셔츠",
            brand: Brand(name: "같은 브랜드"),
            category: .top,
            sizes: [size]
        )
        let representative = comparisonItem(
            shoulder: 48, sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        representative.isRepresentative = true
        representative.brandName = "다른 브랜드"
        let sameBrand = comparisonItem(
            shoulder: 50, sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        sameBrand.brandName = "같은 브랜드"

        let plan = RecommendationService().referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [sameBrand, representative]
        )

        #expect(plan.automaticallySelectedCandidate?.id == representative.id)
    }

    @Test func multipleCompatibleRepresentativesSelectDeterministically() {
        let size = comparisonSize(
            shoulder: 50, sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let older = comparisonItem(
            shoulder: 49, sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        older.isRepresentative = true
        older.updatedAt = Date(timeIntervalSince1970: 100)
        let newer = comparisonItem(
            shoulder: 49, sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        newer.isRepresentative = true
        newer.updatedAt = Date(timeIntervalSince1970: 200)

        let service = RecommendationService()
        let first = service.referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [older, newer]
        )
        let second = service.referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [newer, older]
        )

        #expect(first.automaticallySelectedCandidate?.id == newer.id)
        #expect(second.automaticallySelectedCandidate?.id == newer.id)
    }

    @Test func insufficientRepresentativeEvidenceBlocksAutomaticSelection() {
        let size = comparisonSize(
            shoulder: 50, sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let representative = comparisonItem(
            shoulder: 49, sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        representative.isRepresentative = true
        setComparableCode(.unknown, for: .shoulder, in: representative.measurementRecords)
        let compatibleGeneral = comparisonItem(
            shoulder: 49, sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let plan = RecommendationService().referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [compatibleGeneral, representative]
        )

        #expect(plan.automaticallySelectedCandidate == nil)
        #expect(plan.recommendedCandidates.map(\.id).contains(compatibleGeneral.id))
        #expect(plan.requiresUserSelection)
    }

    @Test func incompatibleRepresentativeBlocksGeneralAutomaticSelection() {
        let size = comparisonSize(
            shoulder: 50, sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let representative = comparisonItem(
            shoulder: 49, sleeve: 60,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        representative.isRepresentative = true
        representative.sleeveTypeRawValue = ComparisonLengthType.long.rawValue
        let compatibleGeneral = comparisonItem(
            shoulder: 49, sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let plan = RecommendationService().referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [compatibleGeneral, representative]
        )

        #expect(plan.automaticallySelectedCandidate == nil)
        #expect(plan.recommendedCandidates.map(\.id) == [compatibleGeneral.id])
        #expect(plan.requiresUserSelection)
        #expect(RecommendationService().recommend(
            product: product,
            userFits: [compatibleGeneral, representative],
            productDetailCategory: .shortSleeve
        ) == nil)
    }

    @Test func representativeFromDifferentDetailHasNoSelectionPriority() {
        let size = comparisonSize(
            shoulder: 50, sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        markChestComparable(size.measurementRecords)
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let otherDetailRepresentative = comparisonItem(
            shoulder: 49, sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        otherDetailRepresentative.detailCategory = .longSleeve
        otherDetailRepresentative.sleeveTypeRawValue = ComparisonLengthType.short.rawValue
        otherDetailRepresentative.isRepresentative = true
        let richer = comparisonItem(
            shoulder: 49, sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        markChestComparable(richer.measurementRecords)

        let plan = RecommendationService().referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [otherDetailRepresentative, richer]
        )

        #expect(plan.recommendedCandidates.first?.id == richer.id)
        #expect(plan.automaticallySelectedCandidate == nil)
        #expect(plan.requiresUserSelection)
    }

    @Test func manualSelectionRecommendationIsUnaffectedByRepresentativePolicy() throws {
        let size = comparisonSize(
            shoulder: 50, sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let selected = comparisonItem(
            shoulder: 49, sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let before = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: selected,
            productDetailCategory: .shortSleeve
        ))
        selected.isRepresentative = true
        let after = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: selected,
            productDetailCategory: .shortSleeve
        ))

        #expect(after.recommendedSize.name == before.recommendedSize.name)
        #expect(after.recommendationScore == before.recommendationScore)
        #expect(after.comparisonStatus == before.comparisonStatus)
    }

    @Test func poloUsesTshirtFamilyAndAutomaticallyMatchesSameLengthTshirt() throws {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "드라이컬러크루넥T", category: .top, sizes: [size])
        product.garmentTypeRawValue = ComparisonGarmentFamily.tshirt.rawValue
        product.sleeveTypeRawValue = ComparisonLengthType.short.rawValue

        let polo = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        polo.productName = "DRY-EX폴로셔츠"
        // 과거 저장 데이터가 shirt여도 폴로 원본 증거로 tshirt에 교정되어야 한다.
        polo.sourceCategoryPath = "상의 > 피케/카라 티셔츠"
        polo.garmentTypeRawValue = ComparisonGarmentFamily.shirt.rawValue
        polo.sleeveTypeRawValue = ComparisonLengthType.short.rawValue
        polo.isRepresentative = true

        let service = RecommendationService()
        let automatic = service.automaticMatchResult(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [polo]
        )
        let plan = service.referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [polo]
        )
        let manual = try #require(service.recommend(
            product: product,
            selectedReferenceItem: polo,
            productDetailCategory: .shortSleeve
        ))

        #expect(automatic.compatibleCandidates.map(\.id) == [polo.id])
        #expect(automatic.incomingProfile.garmentFamily == .tshirt)
        #expect(ComparisonProfileMatcher().profile(for: polo).garmentFamily == .tshirt)
        #expect(plan.automaticallySelectedCandidate?.id == polo.id)
        #expect(!plan.requiresUserSelection)
        #expect(manual.userFit.id == polo.id)
        #expect(manual.comparisonStatus == .confirmed)
    }

    @Test func singleCompatibleNonReferenceStillRequiresUserSelection() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let item = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let plan = RecommendationService().referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [item]
        )

        #expect(plan.recommendedCandidates.map(\.id) == [item.id])
        #expect(plan.automaticallySelectedCandidate == nil)
        #expect(plan.requiresUserSelection)
    }

    @Test func poloDoesNotAutomaticallyCompareWithWovenShirt() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let polo = Product(
            name: "드라이피케폴로셔츠",
            category: .top,
            metadata: ProductMetadata(sourceCategoryPath: "셔츠 > 폴로셔츠 (카라티) > 반팔"),
            sizes: [size]
        )
        polo.sleeveTypeRawValue = ComparisonLengthType.short.rawValue

        let oxford = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        oxford.productName = "옥스포드셔츠"
        oxford.sourceCategoryPath = "셔츠 > 캐주얼셔츠 > 옥스포드"
        oxford.detailCategory = .shirt
        oxford.garmentTypeRawValue = ComparisonGarmentFamily.shirt.rawValue
        oxford.sleeveTypeRawValue = ComparisonLengthType.short.rawValue
        oxford.isRepresentative = true

        let service = RecommendationService()
        let result = service.automaticMatchResult(
            product: polo,
            productDetailCategory: .shortSleeve,
            userFits: [oxford]
        )
        let plan = service.referenceSelectionPlan(
            product: polo,
            productDetailCategory: .shortSleeve,
            userFits: [oxford]
        )

        #expect(result.incomingProfile.garmentFamily == .tshirt)
        #expect(result.compatibleCandidates.isEmpty)
        #expect(plan.automaticallySelectedCandidate == nil)
    }

    @Test func similarReferenceCandidatesRequireUserSelection() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let first = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let second = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let plan = RecommendationService().referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [first, second]
        )

        #expect(plan.recommendedCandidates.count == 2)
        #expect(plan.automaticallySelectedCandidate?.id == nil)
        #expect(plan.requiresUserSelection)
    }

    @Test func richerMeasurementEvidenceRanksFirstWithoutBypassingUserSelection() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        markChestComparable(size.measurementRecords)
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let basic = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let richer = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        markChestComparable(richer.measurementRecords)

        let plan = RecommendationService().referenceSelectionPlan(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [basic, richer]
        )

        #expect(plan.recommendedCandidates.first?.id == richer.id)
        #expect(plan.automaticallySelectedCandidate == nil)
        #expect(plan.requiresUserSelection)
    }

    @Test func differentShortTopStructureShowsManualExpansionNotice() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let hoodie = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        hoodie.garmentTypeRawValue = ComparisonGarmentFamily.hoodie.rawValue

        let note = RecommendationService().manualCandidateNote(
            product: product,
            productDetailCategory: .shortSleeve,
            item: hoodie
        )

        #expect(note?.contains("사용자 선택 확장 비교") == true)
        #expect(note?.contains("다른 반팔 상의 구조") == true)
    }

    @Test func representativeOutranksSimilarityWhenEvidenceIsEqual() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let representative = comparisonItem(
            shoulder: 46,
            sleeve: 20,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        representative.isRepresentative = true
        let closer = comparisonItem(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let history = RecommendationService().recommend(
            product: product,
            userFits: [closer, representative],
            productDetailCategory: .shortSleeve
        )

        #expect(history?.userFit.id == representative.id)
    }

    @Test func sameBrandIsOnlyATieBreakerAfterSimilarity() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", brand: Brand(name: "브랜드A"), category: .top, sizes: [size])
        let sameBrand = comparisonItem(
            shoulder: 46,
            sleeve: 20,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        sameBrand.brandName = "브랜드A"
        let closerOtherBrand = comparisonItem(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        closerOtherBrand.brandName = "브랜드B"

        let ranked = RecommendationService().rankedFitMatches(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [sameBrand, closerOtherBrand]
        )

        #expect(ranked.first?.userFit.id == closerOtherBrand.id)
    }

    @Test func musinsaAndUniqloCompareCommonUpperMeasurementsButExcludeSleeve() {
        let uniqloSize = comparisonSize(
            shoulder: 50,
            sleeve: 47,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff
        )
        setComparableCode(.chestWidthPitToPit, for: .chest, in: uniqloSize.measurementRecords)
        setComparableCode(.bodyLengthBackNeckToHem, for: .totalLength, in: uniqloSize.measurementRecords)
        let musinsaItem = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        setComparableCode(.chestWidthPitToPit, for: .chest, in: musinsaItem.measurementRecords)
        setComparableCode(.bodyLengthBackNeckToHem, for: .totalLength, in: musinsaItem.measurementRecords)
        let product = Product(name: "유니클로 반팔 티셔츠", category: .top, sizes: [uniqloSize])
        let service = RecommendationService()

        let result = MeasurementComparisonEngine().compare(
            productSize: uniqloSize,
            referenceItem: musinsaItem,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )
        let recommendation = service.recommend(
            product: product,
            selectedReferenceItem: musinsaItem,
            productDetailCategory: .shortSleeve
        )
        let evidence = service.insufficientEvidence(
            product: product,
            selectedReferenceItem: musinsaItem,
            productDetailCategory: .shortSleeve
        )

        #expect(result.status == .confirmed)
        #expect(result.comparedKinds == [.shoulder, .chest, .totalLength])
        #expect(recommendation != nil)
        #expect(evidence == nil)
        #expect(result.exclusions.contains {
            $0.kind == .sleeveLength
                && $0.reason == .incompatibleMeasurementCode
                && $0.productCode == .sleeveCenterBackToCuff
                && $0.referenceCode == .sleeveShoulderSeamToCuff
        })
    }

    @Test func identicalSetInSleeveCodesRemainComparable() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let item = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let result = MeasurementComparisonEngine().compare(
            productSize: size,
            referenceItem: item,
            productCategory: .top,
            productDetailCategory: .shortSleeve
        )

        #expect(result.comparedKinds.contains(.sleeveLength))
        #expect(!result.exclusions.contains {
            $0.kind == .sleeveLength && $0.reason == .incompatibleMeasurementCode
        })
    }

    @Test func crossPlatformBottomWidthsCompareWhileOutseamAndInseamStaySeparate() {
        let uniqloSize = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 76, sleeveLength: 0,
                waist: 35, hip: 52, thigh: 31, rise: 29, hem: 22
            )
        )
        uniqloSize.measurementRecords = [
            comparisonRecord(value: 35, code: .waistWidthEdgeToEdge, kind: .waist, productSize: uniqloSize),
            comparisonRecord(value: 52, code: .hipWidthAtWidest, kind: .hip, productSize: uniqloSize),
            comparisonRecord(value: 31, code: .thighWidthCrotchToOuter, kind: .thigh, productSize: uniqloSize),
            comparisonRecord(value: 29, code: .riseCrotchToWaistFront, kind: .rise, productSize: uniqloSize),
            comparisonRecord(value: 22, code: .hemWidthEdgeToEdge, kind: .hem, productSize: uniqloSize),
            comparisonRecord(value: 76, code: .pantsInseamCrotchToHem, kind: .totalLength, productSize: uniqloSize)
        ]
        let musinsaItem = UserFit(
            sourceName: "무신사",
            brandName: "테스트",
            productName: "바지",
            category: .bottom,
            detailCategory: .longPants,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 102, sleeveLength: 0,
                waist: 35, hip: 52, thigh: 31, rise: 29, hem: 22
            ),
            fitMemo: "",
            satisfaction: 3
        )
        musinsaItem.measurementRecords = [
            comparisonRecord(value: 35, code: .waistWidthEdgeToEdge, kind: .waist, userFit: musinsaItem),
            comparisonRecord(value: 52, code: .hipWidthAtWidest, kind: .hip, userFit: musinsaItem),
            comparisonRecord(value: 31, code: .thighWidthCrotchToOuter, kind: .thigh, userFit: musinsaItem),
            comparisonRecord(value: 29, code: .riseCrotchToWaistFront, kind: .rise, userFit: musinsaItem),
            comparisonRecord(value: 22, code: .hemWidthEdgeToEdge, kind: .hem, userFit: musinsaItem),
            comparisonRecord(value: 102, code: .pantsOutseamWaistToHem, kind: .totalLength, userFit: musinsaItem)
        ]

        let differentPaths = MeasurementComparisonEngine().compare(
            productSize: uniqloSize,
            referenceItem: musinsaItem,
            productCategory: .bottom,
            productDetailCategory: .longPants
        )

        #expect(differentPaths.comparedKinds == [.waist, .hip, .thigh, .rise, .hem])
        #expect(differentPaths.exclusions.contains {
            $0.kind == .totalLength
                && $0.reason == .incompatibleMeasurementCode
                && $0.productCode == .pantsInseamCrotchToHem
                && $0.referenceCode == .pantsOutseamWaistToHem
        })

        let musinsaLength = musinsaItem.measurementRecords.first { $0.displayKind == .totalLength }
        #expect(musinsaLength != nil)
        musinsaLength?.measurementCodeRawValue = MeasurementCode.pantsInseamCrotchToHem.rawValue
        musinsaItem.measurements.totalLength = 76
        musinsaLength?.value = 76
        let sameInseam = MeasurementComparisonEngine().compare(
            productSize: uniqloSize,
            referenceItem: musinsaItem,
            productCategory: .bottom,
            productDetailCategory: .longPants
        )
        #expect(sameInseam.comparedKinds.contains(.totalLength))
    }

    @Test func compatibleOtherBrandOutranksSameBrandWithLessMeasurementEvidence() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        setComparableCode(.chestWidthPitToPit, for: .chest, in: size.measurementRecords)
        setComparableCode(.bodyLengthBackNeckToHem, for: .totalLength, in: size.measurementRecords)
        let product = Product(name: "반팔 티셔츠", brand: Brand(name: "브랜드A"), category: .top, sizes: [size])
        let sameBrand = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        sameBrand.brandName = "브랜드A"
        let compatibleOtherBrand = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        compatibleOtherBrand.brandName = "브랜드B"
        setComparableCode(.chestWidthPitToPit, for: .chest, in: compatibleOtherBrand.measurementRecords)
        setComparableCode(.bodyLengthBackNeckToHem, for: .totalLength, in: compatibleOtherBrand.measurementRecords)

        let ranked = RecommendationService().rankedFitMatches(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [sameBrand, compatibleOtherBrand]
        )

        #expect(ranked.first?.userFit.id == compatibleOtherBrand.id)
        #expect(ranked.first?.compatibleMeasurementCount == 4)
        #expect(ranked.last?.userFit.id == sameBrand.id)
        #expect(ranked.last?.compatibleMeasurementCount == 2)
    }

    @Test func comparisonProfileStoresGarmentSleeveAndConstructionAttributes() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let item = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let matcher = ComparisonProfileMatcher()

        let productProfile = matcher.profile(for: product, detailCategory: .shortSleeve)
        let itemProfile = matcher.profile(for: item)

        #expect(productProfile.garmentType == .tshirt)
        #expect(productProfile.sleeveType == .short)
        #expect(productProfile.constructionType == .setIn)
        #expect(product.garmentTypeRawValue == ComparisonGarmentFamily.tshirt.rawValue)
        #expect(product.sleeveTypeRawValue == ComparisonLengthType.short.rawValue)
        #expect(product.constructionTypeRawValue == ComparisonConstructionType.setIn.rawValue)
        #expect(itemProfile.garmentType == .tshirt)
        #expect(item.garmentTypeRawValue == ComparisonGarmentFamily.tshirt.rawValue)
    }

    @Test func matchingComparisonAttributesCannotCrossClosetCategories() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "분류가 다른 반팔", category: .outer, sizes: [size])
        product.garmentTypeRawValue = ComparisonGarmentFamily.tshirt.rawValue
        product.sleeveTypeRawValue = ComparisonLengthType.short.rawValue
        product.constructionTypeRawValue = ComparisonConstructionType.setIn.rawValue
        let item = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        item.category = .top
        item.garmentTypeRawValue = ComparisonGarmentFamily.tshirt.rawValue
        item.sleeveTypeRawValue = ComparisonLengthType.short.rawValue
        item.constructionTypeRawValue = ComparisonConstructionType.setIn.rawValue

        let match = RecommendationService().automaticMatchResult(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [item]
        )

        #expect(product.category != item.category)
        #expect(match.state == .noCompatibleGarment)
        #expect(match.compatibleCandidates.isEmpty)
    }

    @Test func sameClosetCategoryDoesNotOverrideDifferentGarmentType() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        product.garmentTypeRawValue = ComparisonGarmentFamily.tshirt.rawValue
        product.sleeveTypeRawValue = ComparisonLengthType.short.rawValue
        let knitItem = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        knitItem.garmentTypeRawValue = ComparisonGarmentFamily.knitCardigan.rawValue
        knitItem.sleeveTypeRawValue = ComparisonLengthType.short.rawValue

        let match = ComparisonProfileMatcher().match(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [knitItem]
        )

        #expect(product.category == knitItem.category)
        #expect(match.state == .noCompatibleGarment)
        #expect(match.compatibleCandidates.isEmpty)
    }

    @Test func exactDetailCategoryOutranksRepresentativeFromAnotherOuterwearDetail() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 62,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "테일러드 재킷", category: .outer, sizes: [size])
        product.garmentTypeRawValue = ComparisonGarmentFamily.outerwear.rawValue
        product.sleeveTypeRawValue = ComparisonLengthType.long.rawValue

        let exactJacket = comparisonItem(
            shoulder: 49,
            sleeve: 61,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        exactJacket.category = .outer
        exactJacket.detailCategory = .jacket
        exactJacket.garmentTypeRawValue = ComparisonGarmentFamily.outerwear.rawValue
        exactJacket.sleeveTypeRawValue = ComparisonLengthType.long.rawValue
        exactJacket.updatedAt = .distantPast

        let representativeCoat = comparisonItem(
            shoulder: 49,
            sleeve: 61,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        representativeCoat.category = .outer
        representativeCoat.detailCategory = .coat
        representativeCoat.garmentTypeRawValue = ComparisonGarmentFamily.outerwear.rawValue
        representativeCoat.sleeveTypeRawValue = ComparisonLengthType.long.rawValue
        representativeCoat.isRepresentative = true
        representativeCoat.updatedAt = .now

        let match = RecommendationService().automaticMatchResult(
            product: product,
            productDetailCategory: .jacket,
            userFits: [representativeCoat, exactJacket]
        )

        #expect(match.state == .compatible)
        #expect(match.compatibleCandidates.first?.id == exactJacket.id)
    }

    @Test func automaticMatcherRequiresCompatibleDetailCategoryWithinOuterwearFamily() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 62,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "윈드브레이커", category: .outer, sizes: [size])
        product.garmentTypeRawValue = ComparisonGarmentFamily.outerwear.rawValue
        product.sleeveTypeRawValue = ComparisonLengthType.long.rawValue

        let coat = comparisonItem(
            shoulder: 49,
            sleeve: 61,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        coat.category = .outer
        coat.detailCategory = .coat
        coat.garmentTypeRawValue = ComparisonGarmentFamily.outerwear.rawValue
        coat.sleeveTypeRawValue = ComparisonLengthType.long.rawValue

        let matcher = ComparisonProfileMatcher()
        let match = matcher.match(
            product: product,
            productDetailCategory: .windbreaker,
            userFits: [coat]
        )
        let diagnostic = matcher.candidateDiagnostics(
            product: product,
            productDetailCategory: .windbreaker,
            userFits: [coat]
        ).first

        #expect(match.state == .noCompatibleGarment)
        #expect(match.compatibleCandidates.isEmpty)
        #expect(diagnostic?.exclusionReasons.contains("detail_category_incompatible") == true)
    }

    @Test func closetCategoryChangeInvalidatesStoredComparisonAttributes() {
        let item = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        item.garmentTypeRawValue = ComparisonGarmentFamily.tshirt.rawValue
        item.sleeveTypeRawValue = ComparisonLengthType.short.rawValue
        item.constructionTypeRawValue = ComparisonConstructionType.setIn.rawValue

        item.category = .outer

        #expect(item.garmentTypeRawValue == nil)
        #expect(item.sleeveTypeRawValue == nil)
        #expect(item.constructionTypeRawValue == nil)
    }

    @Test func fitMatchCandidateRecommendationsAreLimitedToThree() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", category: .top, sizes: [size])
        let items = (0..<4).map { index in
            comparisonItem(
                shoulder: 50 - Double(index),
                sleeve: 24 - Double(index),
                shoulderCode: .shoulderWidthSeamToSeam,
                sleeveCode: .sleeveShoulderSeamToCuff
            )
        }

        let ranked = RecommendationService().rankedFitMatches(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: items
        )

        #expect(ranked.count == 3)
    }

    @Test func identicalChestDefinitionIsUsedForConfirmedRecommendation() {
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        markChestComparable(size.measurementRecords)
        let product = Product(name: "가슴 비교 티셔츠", category: .top, sizes: [size])
        let item = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        markChestComparable(item.measurementRecords)

        let history = RecommendationService().recommend(
            product: product,
            selectedReferenceItem: item,
            productDetailCategory: .shortSleeve
        )

        #expect(history?.comparisonStatus == .confirmed)
        #expect(history?.comparedMeasurementUsages.contains {
            $0.kind == .chest && $0.measurementCode == .chestWidthPitToPit
        } == true)
    }

    @Test func compatibleOtherBrandOutranksSameBrandWithDifferentMeasurementMethod() {
        let brand = Brand(name: "브랜드A")
        let size = comparisonSize(
            shoulder: 50,
            sleeve: 24,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let product = Product(name: "반팔 티셔츠", brand: brand, category: .top, sizes: [size])
        let incompatibleSameBrand = comparisonItem(
            shoulder: 50,
            sleeve: 47,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff
        )
        incompatibleSameBrand.brandName = "브랜드A"
        let compatibleOtherBrand = comparisonItem(
            shoulder: 49,
            sleeve: 23,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        compatibleOtherBrand.brandName = "브랜드B"

        let match = RecommendationService().automaticMatchResult(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [incompatibleSameBrand, compatibleOtherBrand]
        )
        let history = RecommendationService().recommend(
            product: product,
            userFits: [incompatibleSameBrand, compatibleOtherBrand],
            productDetailCategory: .shortSleeve,
            allowsGlobalFallback: false
        )
        let manuallySelected = RecommendationService().recommend(
            product: product,
            selectedReferenceItem: compatibleOtherBrand,
            productDetailCategory: .shortSleeve
        )

        #expect(match.compatibleCandidates.map(\.id) == [compatibleOtherBrand.id])
        #expect(history == nil)
        #expect(manuallySelected?.userFit.id == compatibleOtherBrand.id)
    }

    @Test func changingReferenceItemRecalculatesRecommendedSize() {
        let medium = comparisonSize(
            shoulder: 48,
            sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        medium.name = "M"
        medium.displayOrder = 0
        let large = comparisonSize(
            shoulder: 52,
            sleeve: 26,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        large.name = "L"
        large.displayOrder = 1
        let product = Product(name: "사이즈 재계산 티셔츠", category: .top, sizes: [medium, large])
        let smallReference = comparisonItem(
            shoulder: 48,
            sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let largeReference = comparisonItem(
            shoulder: 52,
            sleeve: 26,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )

        let smallResult = RecommendationService().recommend(
            product: product,
            selectedReferenceItem: smallReference,
            productDetailCategory: .shortSleeve
        )
        let largeResult = RecommendationService().recommend(
            product: product,
            selectedReferenceItem: largeReference,
            productDetailCategory: .shortSleeve
        )

        #expect(smallResult?.recommendedSize.name == "M")
        #expect(largeResult?.recommendedSize.name == "L")
        #expect(smallResult?.userFit.id == smallReference.id)
        #expect(largeResult?.userFit.id == largeReference.id)
    }

    @Test func sharedURLStoreConsumesPendingURLOnlyOnce() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchTests.SharedURLStore.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = SharedURLStore(fileURL: fileURL)
        let url = URL(string: "https://www.musinsa.com/products/4668060")!

        store.savePendingProductURL(url)

        #expect(store.pendingProductURL() == url.absoluteString)
        #expect(store.consumePendingProductURL() == url.absoluteString)
        #expect(store.consumePendingProductURL() == nil)
    }

    @Test func sharedURLStoreClearsOnlyThePresentedURL() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchTests.SharedURLStore.Presented.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = SharedURLStore(fileURL: fileURL)
        let pendingURL = URL(string: "https://www.musinsa.com/products/4668060")!

        store.savePendingProductURL(pendingURL)

        #expect(store.clearPendingProductURL(ifMatching: "https://www.uniqlo.com/kr/ko/products/E123456") == false)
        #expect(store.pendingProductURL() == pendingURL.absoluteString)
        #expect(store.clearPendingProductURL(ifMatching: pendingURL.absoluteString) == true)
        #expect(store.pendingProductURL() == nil)
    }

    @Test func productURLSupportAcceptsOfficialHostsAndRejectsLookalikes() {
        #expect(ProductURLSupport.supportedProviderName(for: "https://www.musinsa.com/products/4668060") == "무신사")
        #expect(ProductURLSupport.supportedProviderName(for: "https://musinsa.onelink.me/PvkC/example") == "무신사")
        #expect(ProductURLSupport.supportedProviderName(for: "https://www.uniqlo.com/kr/ko/products/E123456") == "유니클로")
        #expect(ProductURLSupport.isZARAURL(URL(string: "https://www.zara.com/kr/ko/example-p01165305.html")!))
        #expect(ProductURLSupport.supportedProviderName(for: "https://www.zara.com/kr/ko/example-p01165305.html") == "ZARA")
        let sharedZARAURL = "https://www.zara.com/kr/ko/%E1%84%8B%E1%85%AA%E1%84%91%E1%85%B3%E1%86%AF-p05372320.html?v1=549582583&utm_campaign=productShare&utm_medium=mobile_sharing_iOS&utm_source=red_social_movil"
        #expect(ProductURLSupport.supportedProviderName(for: sharedZARAURL) == "ZARA")
        #expect(ProductURLSupport.isSupportedProductURL(sharedZARAURL))
        #expect(ProductURLSupport.supportedProviderName(for: "https://www.cos.com/ko-kr/men/t-shirts/product.example.1229297007.html") == nil)
        #expect(!ProductURLSupport.isSupportedProductURL("https://www.cos.com/ko-kr/men/t-shirts/product.example.1229297007.html"))

        #expect(ProductURLSupport.supportedProviderName(for: "https://musinsa.example.com/products/4668060") == nil)
        #expect(ProductURLSupport.supportedProviderName(for: "https://example.com/?next=musinsa") == nil)
        #expect(ProductURLSupport.supportedProviderName(for: "https://uniqlo.com.example.com/products/E123456") == nil)
        #expect(ProductURLSupport.supportedProviderName(for: "https://zara.com.example.com/kr/ko/example-p01165305.html") == nil)
        #expect(ProductURLSupport.supportedProviderName(for: "https://cos.com.example.com/product.1229297007.html") == nil)
    }

    @Test func officialProductURLParserRejectsCOSBeforeAnyProviderParserRuns() async {
        let service = ProductURLParserService()
        let cosURL = "https://www.cos.com/ko-kr/men/t-shirts/product.example.1229297007.html"

        do {
            _ = try await service.parse(urlString: cosURL)
            Issue.record("공식 COS URL이 지원되지 않는 링크로 차단되지 않았습니다.")
        } catch let error as ProductURLParserError {
            guard case .unsupportedURL = error else {
                Issue.record("COS URL이 unsupportedURL이 아닌 오류로 처리됐습니다: \(error)")
                return
            }
            #expect(error.errorDescription?.contains("COS") == false)
        } catch {
            Issue.record("예상하지 못한 COS URL 오류: \(error)")
        }
    }

    @Test func zaraParserMapsOnlyVerifiedUpperGarmentBasis() async {
        let url = URL(string: "https://www.zara.com/kr/ko/heart-stamping-t-shirt-p06224446.html?v1=498706001")!
        let html = """
        <html><head>
        <script type="application/ld+json">{"@type":"ProductGroup","name":"하트 스탬핑 티셔츠","image":["https://static.zara.net/example.jpg"],"offers":{"price":"49900"}}</script>
        <script>zara.analyticsData = {"productId":498702922,"productRef":"06224446-000","catentryId":498706001,"section":"MAN","family":"티셔츠","subfamily":"F. Camiseta"};</script>
        </head><body></body></html>
        """
        let guide = """
        {"sizeGuideInfo":{"name":"신체 사이즈표"},"measureGuideInfo":{"name":"하트 스탬핑 티셔츠","sizes":[
          {"id":"2","name":"S (KR 90)","measures":[
            {"zoneId":"A","tableTitleZone":"zone-name-chest","descriptionZone":"zone-name-chest-description","dimensions":[{"unitId":"cm","value":"48.5"}]},
            {"zoneId":"B","tableTitleZone":"zone-name-front-length","descriptionZone":"zone-name-front-length-description","dimensions":[{"unitId":"cm","value":"62.5"}]},
            {"zoneId":"C","tableTitleZone":"zone-name-sleeve-length","descriptionZone":"zone-name-sleeve-length-description","dimensions":[{"unitId":"cm","value":"15.0"}]},
            {"zoneId":"D","tableTitleZone":"zone-name-back-width","descriptionZone":"zone-name-back-width-description","dimensions":[{"unitId":"cm","value":"42.5"}]}
          ]}
        ]}}
        """.data(using: .utf8)!
        let parser = ZARAParser(
            pageLoader: ZARAProductPageLoaderSpy(page: ZARAProductPage(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: ZARASizeGuideLoaderSpy(data: guide)
        )

        do {
            let info = try await parser.parse(from: url)
            #expect(info.productID == "498702922")
            #expect(info.productMetadata.styleNo == "06224446")
            #expect(info.sourceName == "ZARA 공식몰")
            #expect(info.productTargetGender == .men)
            #expect(info.category == .top)
            #expect(info.detailCategory == .shortSleeve)
            #expect(info.productMetadata.structuredFacts["section"] == "MAN")
            #expect(info.productMetadata.structuredFacts["family"] == "티셔츠")
            #expect(info.productMetadata.structuredFacts["subfamily"] == "F. Camiseta")
            #expect(
                info.fitMatchDatabaseResolutionRequest()?.structuredFacts["family"]
                    == "티셔츠"
            )
            #expect(info.measurementAvailability == .actualMeasurements)
            #expect(info.sizes.map(\.name) == ["S (KR 90)"])
            #expect(info.sizes[0].measurements.chest == 48.5)
            #expect(info.sizes[0].measurements.totalLength == 0)
            #expect(info.sizes[0].measurements.sleeveLength == 15.0)
            #expect(info.sizes[0].measurements.shoulder == 42.5)
            #expect(info.sizes[0].measurementRecords.count == 4)
            let chestCandidate = info.sizes[0].measurementRecords.first {
                $0.rawCode == "zone-name-chest"
            }
            #expect(chestCandidate?.measurementCode == .chestWidthPitToPit)
            #expect(chestCandidate?.semanticStatus == .mapped)
            #expect(chestCandidate?.evidenceLevel == .officialText)
            #expect(chestCandidate?.rawValueText == "48.5")
            #expect(chestCandidate?.rawInfo?.contains("raw_zone_id=A") == true)
            let frontLengthCandidate = info.sizes[0].measurementRecords.first {
                $0.rawCode == "zone-name-front-length"
            }
            #expect(frontLengthCandidate?.measurementCode == .unknown)
            #expect(frontLengthCandidate?.semanticStatus == .unknownDefinition)
            #expect(frontLengthCandidate?.evidenceLevel == .unknown)
        } catch {
            Issue.record("예상하지 못한 ZARA 파서 오류: \(error)")
        }
    }

    @Test func zaraParserFailsClosedWhenOnlyBodySizeGuideExists() async {
        let url = URL(string: "https://www.zara.com/kr/ko/striped-t-shirt-p01165305.html?v1=557391091")!
        let html = """
        <html><head>
        <script type="application/ld+json">{"@type":"ProductGroup","name":"스트라이프 티셔츠"}</script>
        <script>zara.analyticsData = {"productId":557391090,"productRef":"01165305-000","catentryId":557391091,"section":"MAN","family":"티셔츠"};</script>
        </head><body></body></html>
        """
        let bodyGuideOnly = """
        {"sizeGuideInfo":{"name":"신체 사이즈표","sizes":[{"name":"M (KR 95-100)"}]},"measureGuideInfo":null}
        """.data(using: .utf8)!
        let parser = ZARAParser(
            pageLoader: ZARAProductPageLoaderSpy(page: ZARAProductPage(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: ZARASizeGuideLoaderSpy(data: bodyGuideOnly)
        )

        do {
            _ = try await parser.parse(from: url)
            Issue.record("ZARA 신체 사이즈표를 의류 실측으로 처리했습니다.")
        } catch let error as ProductURLParserPartialError {
            #expect(error.productInfo.productID == "557391090")
            #expect(error.productInfo.measurementAvailability == .unavailable)
            #expect(error.productInfo.sizes.isEmpty)
        } catch {
            Issue.record("예상하지 못한 ZARA 파서 오류: \(error)")
        }
    }

    @Test func cosParserPreservesOfficialMetadataButFailsClosedWithoutSizeChart() async {
        let url = URL(string: "https://www.cos.com/ko-kr/men/t-shirts/product.slim-ribbed-cotton-t-shirt.1229297007.html")!
        let html = """
        <html><head>
        <meta property="og:title" content="슬림 리브드 코튼 티셔츠" />
        <meta property="og:image" content="https://images.cos.com/example.jpg" />
        <meta property="og:url" content="https://www.cos.com/ko-kr/men/t-shirts/product.slim-ribbed-cotton-t-shirt.1229297007.html" />
        <script type="application/ld+json">{"@type":"Product","name":"슬림 리브드 코튼 티셔츠","offers":{"price":"59000"}}</script>
        </head><body></body></html>
        """
        let parser = COSParser(pageLoader: COSProductPageLoaderSpy(page: COSProductPage(url: url, statusCode: 200, html: html)))

        do {
            _ = try await parser.parse(from: url)
            Issue.record("실측표 없는 COS 상품이 자동 비교용 파싱에 성공했습니다.")
        } catch let error as ProductURLParserPartialError {
            let info = error.productInfo
            #expect(info.sourceName == "COS 공식몰")
            #expect(info.productID == "1229297007")
            #expect(info.productName == "슬림 리브드 코튼 티셔츠")
            #expect(info.category == .top)
            #expect(info.detailCategory == .other)
            #expect(info.productMetadata.categoryDepth2Code == "t-shirts")
            #expect(info.measurementAvailability == .unavailable)
        } catch {
            Issue.record("예상하지 못한 COS 파서 오류: \(error)")
        }
    }

    @Test func cosParserUsesOfficialSizeGuideForGarmentMeasurements() async throws {
        let url = URL(string: "https://www.cos.com/ko-kr/men/view-all/product.ribbed-wool-cotton-t-shirt-cobalt-blue.1349394002.html")!
        let html = """
        <html><head>
        <script type="application/ld+json">{"@type":"Product","name":"리브드 메리노 울 코튼 티셔츠","offers":{"price":115000}}</script>
        </head><body>
        <script>window.__DATA__ = {"productInfo":{"slitmCd":"40B1490048","sectId":"254652"}};</script>
        </body></html>
        """
        let guide = """
        {"data":{"sizeHeaders":["S","M"],"rows":[
          {"name":"Shoulder to shoulder","values":["41.5","43.0"]},
          {"name":"½ Chest","values":["50.5","53.5"]},
          {"name":"Sleeve length","values":["24.75","25.25"]},
          {"name":"Back length","values":["63.0","64.0"]}
        ]}}
        """.data(using: .utf8)!
        let parser = COSParser(
            pageLoader: COSProductPageLoaderSpy(page: COSProductPage(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: COSSizeGuideLoaderSpy(data: guide)
        )

        let info = try await parser.parse(from: url)

        #expect(info.productID == "40B1490048")
        #expect(info.productMetadata.styleNo == "1349394002")
        #expect(info.measurementAvailability == .actualMeasurements)
        #expect(info.sizes.map(\.name) == ["S", "M"])
        #expect(info.sizes[1].measurements.shoulder == 43.0)
        #expect(info.sizes[1].measurements.chest == 53.5)
        #expect(info.sizes[1].measurements.totalLength == 64.0)
        #expect(info.sizes[1].measurements.sleeveLength == 25.25)
    }

    @Test func manualClosetItemAndMeasurementRecordsPersistTogether() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let viewModel = manualMeasurementViewModel(source: .fitmatchMeasured)
        guard let item = viewModel.makeUserFit() else {
            Issue.record("수동 옷장 항목 생성 실패")
            return
        }

        context.insert(item)
        try context.save()

        let savedItems = try context.fetch(FetchDescriptor<UserFit>())
        #expect(savedItems.count == 1)
        #expect(savedItems.first?.measurementRecords.count == 4)
        #expect(savedItems.first?.measurementRecords.allSatisfy(\.isComparable) == true)
        #expect(savedItems.first?.garmentTypeRawValue == ComparisonGarmentFamily.tshirt.rawValue)
        #expect(savedItems.first?.sleeveTypeRawValue == ComparisonLengthType.short.rawValue)
        #expect(savedItems.first?.constructionTypeRawValue == ComparisonConstructionType.setIn.rawValue)
    }

    @Test func recommendationHistorySaveReplacesSameProductHistory() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let reference = comparisonItem(
            shoulder: 48,
            sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        context.insert(reference)
        try context.save()

        func makeHistory(sizeName: String, shoulder: Double) -> RecommendationHistory? {
            let size = comparisonSize(
                shoulder: shoulder,
                sleeve: 22,
                shoulderCode: .shoulderWidthSeamToSeam,
                sleeveCode: .sleeveShoulderSeamToCuff
            )
            size.name = sizeName
            let product = Product(
                name: "동일 상품",
                category: .top,
                sourceURLString: "https://www.musinsa.com/products/4668060",
                sizes: [size]
            )
            return RecommendationService().recommend(
                product: product,
                selectedReferenceItem: reference,
                productDetailCategory: .shortSleeve
            )
        }

        guard let first = makeHistory(sizeName: "M", shoulder: 48) else {
            Issue.record("첫 추천 결과 생성 실패")
            return
        }
        try RecommendationHistoryStore.saveUnique(first, existing: [], modelContext: context)

        let existing = try context.fetch(FetchDescriptor<RecommendationHistory>())
        guard let second = makeHistory(sizeName: "L", shoulder: 49) else {
            Issue.record("두 번째 추천 결과 생성 실패")
            return
        }
        try RecommendationHistoryStore.saveUnique(second, existing: existing, modelContext: context)

        let saved = try context.fetch(FetchDescriptor<RecommendationHistory>())
        #expect(saved.count == 1)
        #expect(saved.first?.recommendedSize.name == "L")
    }

    @Test func recommendationHistoryRecompareReusesPersistedDeterministicSize() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let reference = comparisonItem(
            shoulder: 48,
            sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        context.insert(reference)
        try context.save()

        let sizeID = ParsedProductSize.stableID(for: "E4668060|M")

        func makeHistory(shoulder: Double) -> RecommendationHistory? {
            let size = comparisonSize(
                shoulder: shoulder,
                sleeve: 22,
                shoulderCode: .shoulderWidthSeamToSeam,
                sleeveCode: .sleeveShoulderSeamToCuff
            )
            size.id = sizeID
            let product = Product(
                name: "동일 상품",
                category: .top,
                sourceURLString: "https://www.musinsa.com/products/4668060",
                sizes: [size]
            )
            return RecommendationService().recommend(
                product: product,
                selectedReferenceItem: reference,
                productDetailCategory: .shortSleeve
            )
        }

        let first = try #require(makeHistory(shoulder: 48))
        try RecommendationHistoryStore.saveUnique(first, existing: [], modelContext: context)
        let storedSize = try #require(context.fetch(FetchDescriptor<ProductSize>()).first)

        let second = try #require(makeHistory(shoulder: 49))
        let existing = try context.fetch(FetchDescriptor<RecommendationHistory>())
        try RecommendationHistoryStore.saveUnique(second, existing: existing, modelContext: context)

        let saved = try context.fetch(FetchDescriptor<RecommendationHistory>())
        let savedSizes = try context.fetch(FetchDescriptor<ProductSize>())
        #expect(saved.count == 1)
        #expect(saved.first?.recommendedSize === storedSize)
        #expect(savedSizes.count == 1)
    }

    @Test func musinsaRecompareReusesPersistedSizeByName() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let reference = comparisonItem(
            shoulder: 48,
            sleeve: 62,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff,
            detailCategory: .longSleeve
        )
        context.insert(reference)
        try context.save()

        func makeHistory() -> RecommendationHistory? {
            let size = comparisonSize(
                shoulder: 49,
                sleeve: 63,
                shoulderCode: .shoulderWidthSeamToSeam,
                sleeveCode: .sleeveShoulderSeamToCuff
            )
            size.name = "M"
            let product = Product(
                name: "무신사 재비교 상품",
                category: .top,
                productCode: "4668060",
                sourceURLString: "https://www.musinsa.com/products/4668060",
                sourceName: "무신사",
                sizes: [size]
            )
            return RecommendationService().recommend(
                product: product,
                selectedReferenceItem: reference,
                productDetailCategory: .longSleeve
            )
        }

        let first = try #require(makeHistory())
        try RecommendationHistoryStore.saveUnique(first, existing: [], modelContext: context)
        let persistedSizeID = first.recommendedSize.id

        let second = try #require(makeHistory())
        let existing = try context.fetch(FetchDescriptor<RecommendationHistory>())
        try RecommendationHistoryStore.saveUnique(second, existing: existing, modelContext: context)

        let savedHistories = try context.fetch(FetchDescriptor<RecommendationHistory>())
        let savedProducts = try context.fetch(FetchDescriptor<Product>())
        let savedSizes = try context.fetch(FetchDescriptor<ProductSize>())
        #expect(savedHistories.count == 1)
        #expect(savedProducts.count == 1)
        #expect(savedSizes.count == 1)
        #expect(savedHistories.first?.recommendedSize.id == persistedSizeID)
    }

    @Test func uniqloRecompareWithDifferentReferenceKeepsSingleProductGraph() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let firstReference = comparisonItem(
            shoulder: 47,
            sleeve: 61,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff,
            detailCategory: .longSleeve
        )
        let secondReference = comparisonItem(
            shoulder: 49,
            sleeve: 63,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff,
            detailCategory: .longSleeve
        )
        context.insert(firstReference)
        context.insert(secondReference)
        try context.save()

        let sizeID = ParsedProductSize.stableID(for: "E465185-000|M")
        func makeHistory(reference: UserFit) -> RecommendationHistory? {
            let size = comparisonSize(
                shoulder: 48,
                sleeve: 62,
                shoulderCode: .shoulderWidthSeamToSeam,
                sleeveCode: .sleeveCenterBackToCuff
            )
            size.id = sizeID
            size.name = "M"
            let product = Product(
                name: "유니클로 재비교 상품",
                category: .top,
                productCode: "E465185-000",
                sourceURLString: "https://www.uniqlo.com/kr/ko/products/E465185?colorDisplayCode=00",
                sourceName: "유니클로 공식몰",
                sizes: [size]
            )
            return RecommendationService().recommend(
                product: product,
                selectedReferenceItem: reference,
                productDetailCategory: .longSleeve
            )
        }

        let first = try #require(makeHistory(reference: firstReference))
        try RecommendationHistoryStore.saveUnique(first, existing: [], modelContext: context)
        let second = try #require(makeHistory(reference: secondReference))
        let existing = try context.fetch(FetchDescriptor<RecommendationHistory>())
        try RecommendationHistoryStore.saveUnique(second, existing: existing, modelContext: context)

        let savedHistories = try context.fetch(FetchDescriptor<RecommendationHistory>())
        let savedProducts = try context.fetch(FetchDescriptor<Product>())
        let savedSizes = try context.fetch(FetchDescriptor<ProductSize>())
        #expect(savedHistories.count == 1)
        #expect(savedHistories.first?.userFit.id == secondReference.id)
        #expect(savedHistories.first?.recommendedSize.id == sizeID)
        #expect(savedProducts.count == 1)
        #expect(savedSizes.count == 1)
    }

    @Test func resultReferenceChangePersistsLatestSelectionWithoutDuplicatingProductGraph() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let firstReference = comparisonItem(
            shoulder: 46,
            sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        let lastReference = comparisonItem(
            shoulder: 52,
            sleeve: 26,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        context.insert(firstReference)
        context.insert(lastReference)

        let small = comparisonSize(
            shoulder: 46,
            sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        small.id = ParsedProductSize.stableID(for: "4668060|S")
        small.name = "S"
        let large = comparisonSize(
            shoulder: 52,
            sleeve: 26,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        large.id = ParsedProductSize.stableID(for: "4668060|L")
        large.name = "L"
        let product = Product(
            name: "기준 옷 변경 상품",
            category: .top,
            productCode: "4668060",
            sourceURLString: "https://www.musinsa.com/products/4668060",
            sourceName: "무신사",
            sizes: [small, large]
        )

        let initial = try #require(
            RecommendationService().recommend(
                product: product,
                selectedReferenceItem: firstReference,
                productDetailCategory: .shortSleeve
            )
        )
        try RecommendationHistoryStore.saveUnique(initial, existing: [], modelContext: context)

        let storedBefore = try context.fetch(FetchDescriptor<RecommendationHistory>())
        let storedProduct = try #require(storedBefore.first?.product)
        let sizeIDsBefore = Set(storedProduct.sizes.map(\.id))
        let measurementRecordIDsBefore = Set(storedProduct.sizes.flatMap(\.measurementRecords).map(\.id))

        let outcome = ResultReferenceComparisonPersistence.resolveAndSave(
            product: storedProduct,
            selectedReferenceItem: lastReference,
            productDetailCategory: .shortSleeve,
            existingHistories: storedBefore,
            modelContext: context
        )

        guard case .success(let updated) = outcome else {
            Issue.record("마지막 기준 옷 결과가 저장되어야 합니다.")
            return
        }
        let savedHistories = try context.fetch(FetchDescriptor<RecommendationHistory>())
        let savedProducts = try context.fetch(FetchDescriptor<Product>())
        let savedSizes = try context.fetch(FetchDescriptor<ProductSize>())
        let savedProductMeasurementRecordIDs = Set(
            savedProducts.flatMap(\.sizes).flatMap(\.measurementRecords).map(\.id)
        )
        #expect(updated.userFit.id == lastReference.id)
        #expect(updated.recommendedSize.name == "L")
        #expect(savedHistories.count == 1)
        #expect(savedHistories.first?.userFit.id == lastReference.id)
        #expect(savedHistories.first?.recommendedSize.name == "L")
        #expect(savedProducts.count == 1)
        #expect(Set(savedSizes.map(\.id)) == sizeIDsBefore)
        #expect(savedProductMeasurementRecordIDs == measurementRecordIDsBefore)
    }

    @Test func insufficientResultReferenceChangeKeepsPersistedHistory() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let originalReference = comparisonItem(
            shoulder: 48,
            sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff
        )
        let incompatibleReference = comparisonItem(
            shoulder: 49,
            sleeve: 63,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        context.insert(originalReference)
        context.insert(incompatibleReference)

        let size = comparisonSize(
            shoulder: 48,
            sleeve: 47,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff
        )
        let product = Product(name: "근거 부족 상품", category: .top, sizes: [size])
        let initial = try #require(
            RecommendationService().recommend(
                product: product,
                selectedReferenceItem: originalReference,
                productDetailCategory: .shortSleeve
            )
        )
        try RecommendationHistoryStore.saveUnique(initial, existing: [], modelContext: context)
        let storedBefore = try context.fetch(FetchDescriptor<RecommendationHistory>())

        let outcome = ResultReferenceComparisonPersistence.resolveAndSave(
            product: try #require(storedBefore.first?.product),
            selectedReferenceItem: incompatibleReference,
            productDetailCategory: .shortSleeve,
            existingHistories: storedBefore,
            modelContext: context
        )

        #expect(!outcome.shouldDismissPicker)
        let storedAfter = try context.fetch(FetchDescriptor<RecommendationHistory>())
        #expect(storedAfter.count == 1)
        #expect(storedAfter.first?.userFit.id == originalReference.id)
    }

    @Test func comparingDifferentProductsKeepsSeparateHistoriesAndGraphs() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let reference = comparisonItem(
            shoulder: 48,
            sleeve: 22,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveShoulderSeamToCuff
        )
        context.insert(reference)
        try context.save()

        func makeHistory(code: String) -> RecommendationHistory? {
            let size = comparisonSize(
                shoulder: 48,
                sleeve: 22,
                shoulderCode: .shoulderWidthSeamToSeam,
                sleeveCode: .sleeveShoulderSeamToCuff
            )
            size.id = ParsedProductSize.stableID(for: "\(code)|M")
            let product = Product(
                name: "상품 \(code)",
                category: .top,
                productCode: code,
                sourceURLString: "https://www.musinsa.com/products/\(code)",
                sizes: [size]
            )
            return RecommendationService().recommend(
                product: product,
                selectedReferenceItem: reference,
                productDetailCategory: .shortSleeve
            )
        }

        let first = try #require(makeHistory(code: "100001"))
        try RecommendationHistoryStore.saveUnique(first, existing: [], modelContext: context)
        let second = try #require(makeHistory(code: "100002"))
        let existing = try context.fetch(FetchDescriptor<RecommendationHistory>())
        try RecommendationHistoryStore.saveUnique(second, existing: existing, modelContext: context)

        let savedHistories = try context.fetch(FetchDescriptor<RecommendationHistory>())
        let savedProducts = try context.fetch(FetchDescriptor<Product>())
        let savedSizes = try context.fetch(FetchDescriptor<ProductSize>())
        #expect(savedHistories.count == 2)
        #expect(savedProducts.count == 2)
        #expect(savedSizes.count == 2)
    }

    @Test func manualClosetEntryRequiresMeasurementSource() {
        let viewModel = AddClosetItemViewModel()
        viewModel.brand = "테스트"
        viewModel.productName = "반팔 티셔츠"
        viewModel.shoulder = "48"
        viewModel.measurementEntrySource = nil

        #expect(!viewModel.canSave)

        viewModel.measurementEntrySource = .fitmatchMeasured

        #expect(viewModel.canSave)
    }

    @Test func uniqloClosetSourceOffersOnlyUniqloChartAndDirectMeasurement() {
        let viewModel = AddClosetItemViewModel()

        viewModel.selectProductSource(.uniqlo)

        #expect(viewModel.sourceType == .officialStore)
        #expect(viewModel.sourceName == "유니클로 공식몰")
        #expect(viewModel.measurementEntrySource == .uniqloSizeChart)
        #expect(viewModel.measurementEntrySourceOptions == [.uniqloSizeChart, .fitmatchMeasured])
        #expect(!viewModel.measurementEntrySourceOptions.contains(.otherSizeChart))
    }

    @Test func musinsaClosetSourceOffersOnlyMusinsaChartAndDirectMeasurement() {
        let viewModel = AddClosetItemViewModel()

        viewModel.selectProductSource(.musinsa)

        #expect(viewModel.sourceType == .marketplace)
        #expect(viewModel.sourceName == "무신사")
        #expect(viewModel.measurementEntrySource == .musinsaSizeChart)
        #expect(viewModel.measurementEntrySourceOptions == [.musinsaSizeChart, .fitmatchMeasured])
        #expect(!viewModel.measurementEntrySourceOptions.contains(.otherSizeChart))
    }

    @Test func linkedMusinsaClosetEntryKeepsSourceAndRequiresUnknownGenderSelection() {
        let viewModel = AddClosetItemViewModel(
            prefillCategory: .top,
            prefillDetailCategory: .sleeveless,
            prefillGender: .unknown,
            prefillSourceOption: .musinsa,
            prefillBrand: "리복",
            prefillProductName: "탱크 탑"
        )
        viewModel.totalLength = "49"
        viewModel.chest = "45"

        #expect(viewModel.sourceType == .marketplace)
        #expect(viewModel.sourceName == "무신사")
        #expect(viewModel.measurementEntrySource == .musinsaSizeChart)
        #expect(!viewModel.canSave)

        viewModel.gender = .women
        viewModel.genderCode = viewModel.gender.taxonomyCode
        #expect(viewModel.canSave)
    }

    @Test func manualComparisonEntryPreservesChestCircumferenceMeaning() throws {
        var form = ClothingSizeForm(
            sizeName: "M",
            shoulder: "34",
            chest: "100",
            totalLength: "53"
        )
        form.chestUsesCircumference = true

        let size = try #require(form.makeSizeOption(
            category: .top,
            detailCategory: .sleeveless
        ))
        #expect(size.measurements.chest == 0)
        #expect(size.measurementRecords.contains {
            $0.measurementCode == .chestCircumferenceGarment && $0.value == 100
        })
        #expect(size.measurementRecords.contains {
            $0.measurementCode == .shoulderWidthSeamToSeam && $0.value == 34
        })
    }

    @Test func manualComparisonEntryPreservesWaistCircumferenceMeaning() throws {
        var form = ClothingSizeForm(
            sizeName: "M",
            totalLength: "100",
            waist: "80",
            hip: "50"
        )
        form.waistUsesCircumference = true

        let size = try #require(form.makeSizeOption(
            category: .bottom,
            detailCategory: .longPants
        ))
        #expect(size.measurements.waist == 0)
        #expect(size.measurementRecords.contains {
            $0.measurementCode == .waistCircumferenceGarment && $0.value == 80
        })
        #expect(size.measurementRecords.contains {
            $0.measurementCode == .hipWidthAtWidest && $0.value == 50
        })
    }

    @Test func manualClosetSourceAutomaticallyUsesFitMatchMeasurement() {
        let viewModel = AddClosetItemViewModel()

        viewModel.selectProductSource(.manual)

        #expect(viewModel.sourceType == .manual)
        #expect(viewModel.measurementEntrySource == .fitmatchMeasured)
        #expect(viewModel.measurementEntrySourceOptions == [.fitmatchMeasured])
        #expect(viewModel.skipsMeasurementSourceSelection)
    }

    @Test func zaraClosetSourcePreservesRetailerIdentityWithoutClaimingAnUnverifiedChart() {
        let viewModel = AddClosetItemViewModel(prefillSourceOption: .zara)

        #expect(viewModel.sourceType == .officialStore)
        #expect(viewModel.sourceName == "ZARA 공식몰")
        #expect(viewModel.brand == "ZARA")
        #expect(viewModel.productSourceOption == .zara)
        #expect(viewModel.measurementEntrySource == .fitmatchMeasured)
        #expect(viewModel.measurementEntrySourceOptions == [.fitmatchMeasured])
    }

    @Test func manualClosetSourceStoresFitMatchStandardVersion() throws {
        let viewModel = AddClosetItemViewModel()
        viewModel.selectProductSource(.manual)
        viewModel.brand = "테스트"
        viewModel.productName = "반팔 티셔츠"
        viewModel.shoulder = "48"
        viewModel.chest = "54"

        let item = try #require(viewModel.makeUserFit())

        #expect(!item.measurementRecords.isEmpty)
        #expect(item.measurementRecords.allSatisfy { $0.standardVersion == "fitmatch_standard_v1" })
        #expect(item.measurementRecords.allSatisfy { $0.methodSource == "fitmatch" })
    }

    @Test func editingLegacyOtherSizeChartPreservesMeasurementSource() throws {
        let original = try #require(manualMeasurementViewModel(source: .otherSizeChart).makeUserFit())
        let editViewModel = AddClosetItemViewModel(item: original)

        #expect(editViewModel.measurementEntrySource == .otherSizeChart)
        #expect(editViewModel.measurementEntrySourceOptions.contains(.otherSizeChart))

        let edited = try #require(editViewModel.makeUserFit())
        #expect(MeasurementEntrySource.infer(from: edited.measurementRecords) == .otherSizeChart)
        #expect(edited.measurementRecords.allSatisfy { $0.methodSource == "other_size_chart" })
        #expect(edited.measurementRecords.allSatisfy { $0.methodProfile == "other_size_chart_manual:29CM" })
    }

    @Test func fitmatchMeasuredEntryCreatesComparableStandardRecords() {
        let viewModel = manualMeasurementViewModel(source: .fitmatchMeasured)

        let item = viewModel.makeUserFit()
        let byKind = Dictionary(uniqueKeysWithValues: (item?.measurementRecords ?? []).compactMap { record in
            record.displayKind.map { ($0, record) }
        })
        let shoulderCode = byKind[.shoulder]?.measurementCode
        let chestCode = byKind[.chest]?.measurementCode
        let totalLengthCode = byKind[.totalLength]?.measurementCode
        let sleeveCode = byKind[.sleeveLength]?.measurementCode
        let recordsAreComparable = (item?.measurementRecords ?? []).allSatisfy(\.isComparable)
        let recordsUseFitMatchStandard = (item?.measurementRecords ?? []).allSatisfy {
            $0.standardVersion == FitMatchMeasurementStandard.version
        }

        #expect(item?.measurementInputSourceRawValue == MeasurementInputSource.userMeasured.rawValue)
        #expect(shoulderCode == .shoulderWidthSeamToSeam)
        #expect(chestCode == .chestWidthPitToPit)
        #expect(totalLengthCode == .bodyLengthHPSToHemFront)
        #expect(sleeveCode == .sleeveShoulderSeamToCuff)
        #expect(recordsAreComparable)
        #expect(recordsUseFitMatchStandard)
    }

    @Test func directMeasurementStandardDefinesEveryMeasurementKind() {
        let definitions = MeasurementKind.allCases.map { FitMatchMeasurementStandard.definition(for: $0) }

        #expect(definitions.count == MeasurementKind.allCases.count)
        #expect(definitions.allSatisfy { !$0.instruction.isEmpty })
        #expect(definitions.allSatisfy { !$0.caution.isEmpty })
        #expect(definitions.allSatisfy { $0.validRange.lowerBound > 0 })
        #expect(definitions.allSatisfy { $0.standardVersion == "fitmatch_standard_v1" })
    }

    @Test func directMeasuredBottomUsesBottomSpecificCodes() {
        let viewModel = AddClosetItemViewModel()
        viewModel.brand = "테스트"
        viewModel.productName = "기준 바지"
        viewModel.category = .bottom
        viewModel.categoryCode = ClothingCategory.bottom.taxonomyCode
        // The shipped picker maps a current bottom selection to this active
        // taxonomy detail; the legacy `.slacks` display value is not an
        // active service-taxonomy detail.
        viewModel.detailCategory = .longPants
        viewModel.detailCategoryCode = "long_pants"
        viewModel.measurementEntrySource = .fitmatchMeasured
        viewModel.totalLength = "100"
        viewModel.waist = "38"
        viewModel.hip = "50"
        viewModel.thigh = "30"
        viewModel.rise = "29"
        viewModel.hem = "22"

        let item = viewModel.makeUserFit()
        let byKind = Dictionary(uniqueKeysWithValues: (item?.measurementRecords ?? []).compactMap { record in
            record.displayKind.map { ($0, record.measurementCode) }
        })

        #expect(byKind[.totalLength] == .pantsOutseamWaistToHem)
        #expect(byKind[.waist] == .waistWidthEdgeToEdge)
        #expect(byKind[.hip] == .hipWidthAtWidest)
        #expect(byKind[.thigh] == .thighWidthCrotchToOuter)
        #expect(byKind[.rise] == .riseCrotchToWaistFront)
        #expect(byKind[.hem] == .hemWidthEdgeToEdge)
        #expect((item?.measurementRecords ?? []).allSatisfy { $0.standardVersion == FitMatchMeasurementStandard.version })
    }

    @Test func bottomLengthGuideUsesOutseamDefinition() {
        let definition = FitMatchMeasurementStandard.definition(for: .totalLength, category: .bottom)

        #expect(definition.instruction.contains("허리단"))
        #expect(definition.caution.contains("인심"))
    }

    @Test func directMeasuredOuterIncludesHemWidth() {
        let viewModel = AddClosetItemViewModel()
        viewModel.brand = "테스트"
        viewModel.productName = "기준 재킷"
        viewModel.category = .outer
        viewModel.categoryCode = ClothingCategory.outer.taxonomyCode
        viewModel.detailCategory = .jacket
        viewModel.detailCategoryCode = "jacket"
        viewModel.measurementEntrySource = .fitmatchMeasured
        viewModel.totalLength = "72"
        viewModel.shoulder = "48"
        viewModel.chest = "58"
        viewModel.sleeveLength = "63"
        viewModel.hem = "56"

        let item = viewModel.makeUserFit()
        let hem = item?.measurementRecords.first { $0.displayKind == .hem }

        #expect(item?.measurementRecords.count == 5)
        #expect(hem?.measurementCode == .hemWidthEdgeToEdge)
        #expect(hem?.standardVersion == FitMatchMeasurementStandard.version)
    }

    @Test func outerHemGuideUsesUnstretchedGarmentDefinition() {
        let definition = FitMatchMeasurementStandard.definition(for: .hem, category: .outer)

        #expect(definition.instruction.contains("아우터 밑단"))
        #expect(definition.caution.contains("조절끈"))
    }

    @Test func directMeasurementRejectsValuesOutsideSafetyRange() {
        let viewModel = manualMeasurementViewModel(source: .fitmatchMeasured)
        viewModel.shoulder = "480"

        #expect(viewModel.directMeasurementValidationMessage?.contains("어깨너비") == true)
        #expect(!viewModel.canSave)
        #expect(viewModel.makeUserFit() == nil)
    }

    @Test func sizeChartValuesDoNotUseDirectMeasurementSafetyRange() {
        let viewModel = manualMeasurementViewModel(source: .uniqloSizeChart)
        viewModel.shoulder = "480"

        #expect(viewModel.directMeasurementValidationMessage == nil)
        #expect(viewModel.canSave)
        #expect(viewModel.makeUserFit() != nil)
    }

    @Test func uniqloTranscribedEntryUsesCommonChestAndCenterBackSleeve() {
        let viewModel = manualMeasurementViewModel(source: .uniqloSizeChart)

        let item = viewModel.makeUserFit()
        let sleeve = item?.measurementRecords.first { $0.displayKind == .sleeveLength }
        let chest = item?.measurementRecords.first { $0.displayKind == .chest }

        #expect(item?.measurementInputSourceRawValue == MeasurementInputSource.transcribedSizeChart.rawValue)
        #expect(sleeve?.measurementCode == .sleeveCenterBackToCuff)
        #expect(sleeve?.rawCode == "sleeve-length-cb")
        #expect(chest?.measurementCode == .chestWidthPitToPit)
        #expect(chest?.rawCode == "body-width")
        #expect(chest?.rawValueText == "54")
        #expect(chest?.semanticStatus == .mapped)
        #expect(chest?.mappingVersion == MeasurementSourceMappingPolicy.uniqloVersion)
    }

    @Test func musinsaTranscribedEntryRequiresExplicitSleeveMethodForMapping() {
        let raglanViewModel = manualMeasurementViewModel(source: .musinsaSizeChart)
        raglanViewModel.musinsaSleeveMeasurementMethod = .raglan
        let raglanItem = raglanViewModel.makeUserFit()

        let unknownViewModel = manualMeasurementViewModel(source: .musinsaSizeChart)
        unknownViewModel.musinsaSleeveMeasurementMethod = .unknown
        let unknownItem = unknownViewModel.makeUserFit()

        #expect(raglanItem?.measurementRecords.first { $0.displayKind == .sleeveLength }?.measurementCode == .sleeveRaglanNeckToCuff)
        #expect(raglanItem?.measurementRecords.first { $0.displayKind == .shoulder }?.measurementCode == .unknown)
        #expect(unknownItem?.measurementRecords.allSatisfy { !$0.isComparable } == true)
    }

    @Test func otherSizeChartPreservesValuesWithoutClaimingCompatibility() {
        let viewModel = manualMeasurementViewModel(source: .otherSizeChart)

        let item = viewModel.makeUserFit()

        #expect(item?.measurementRecords.count == 4)
        #expect(item?.measurementRecords.allSatisfy { $0.methodSource == "other_size_chart" } == true)
        #expect(item?.measurementRecords.allSatisfy { $0.methodProfile == "other_size_chart_manual:29CM" } == true)
        #expect(item?.measurementRecords.allSatisfy { $0.rawInfo == "출처: 29CM" } == true)
        #expect(item?.measurementRecords.first { $0.displayKind == .chest }?.rawLabel == "가슴단면")
        #expect(item?.measurementRecords.allSatisfy { $0.measurementCode == .unknown } == true)
        #expect(item?.measurementRecords.allSatisfy { !$0.isComparable } == true)
    }

    @Test func uniqloSizeAPIParserReturnsNormalizedImageURL() throws {
        let json = """
        {
          "status": "ok",
          "result": [
            {
              "productId": "E465185-000",
              "imageUrl": "//image.uniqlo.com/UQ/ST3/kr/imagesgoods/465185/item/krgoods_00_465185_3x4.jpg?width=400",
              "sizeChart": [
                {
                  "name": "M",
                  "sizeParts": [
                    { "code": "body-length-back", "name": "전체 길이", "measurements": [{ "value": "66", "unit": "cm" }] }
                  ]
                }
              ]
            }
          ]
        }
        """

        let result = try UniqloSizeAPIParser().parseResult(from: Data(json.utf8))

        #expect(result.imageURLString == "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/465185/item/krgoods_00_465185_3x4.jpg?width=400")
        #expect(result.sizes.map(\.name) == ["M"])
    }

    @Test func uniqloJSONLDParserHandlesSingleProductObject() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Product",
          "name": "라이트 불루 니트 가디건",
          "brand": { "name": "UNIQLO" },
          "image": "//image.uniqlo.com/UQ/ST3/kr/imagesgoods/465185/item/krgoods_00_465185_3x4.jpg?width=400",
          "offers": { "price": "39900" }
        }
        </script>
        </head></html>
        """
        let parser = UniqloProductMetadataParser()
        let resolved = ResolvedUniqloURL(
            originalURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E465185?colorDisplayCode=00")!,
            resolvedURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E465185?colorDisplayCode=00")!,
            productID: "E465185",
            goodsID: "465185",
            apiColorCode: "000",
            imageColorCode: "00",
            productIDWithColorCode: "E465185-000",
            html: html
        )

        let metadata = parser.parse(resolved: resolved)

        #expect(metadata.productName == "라이트 불루 니트 가디건")
        #expect(metadata.brandName == "UNIQLO")
        #expect(metadata.price == 39_900)
        #expect(metadata.detailCategory == .cardigan)
        #expect(metadata.imageURLString?.hasPrefix("https://image.uniqlo.com") == true)
    }

    @Test func uniqloJSONLDParserHandlesArrayAndBreadcrumb() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        [
          {
            "@type": "BreadcrumbList",
            "itemListElement": [
              { "position": 1, "name": "WOMEN" },
              { "position": 2, "name": "니트 & 가디건" },
              { "position": 3, "name": "니트" },
              { "position": 4, "name": "가디건" },
              { "position": 5, "name": "수플레얀 가디건" }
            ]
          },
          {
            "@type": "Product",
            "name": "수플레얀 가디건",
            "brand": "유니클로"
          }
        ]
        </script>
        </head></html>
        """
        let parser = UniqloProductMetadataParser()
        let resolved = ResolvedUniqloURL(
            originalURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E465185?colorDisplayCode=00")!,
            resolvedURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E465185?colorDisplayCode=00")!,
            productID: "E465185",
            goodsID: "465185",
            apiColorCode: "000",
            imageColorCode: "00",
            productIDWithColorCode: "E465185-000",
            html: html
        )

        let metadata = parser.parse(resolved: resolved)

        #expect(metadata.category == .outer)
        #expect(metadata.detailCategory == .cardigan)
        #expect(metadata.productMetadata.baseCategoryFullPath == "니트 & 가디건 > 니트 > 가디건")
        #expect(metadata.productMetadata.categoryDepth1Name == "니트 & 가디건")
        #expect(metadata.productMetadata.categoryDepth2Name == "니트")
        #expect(metadata.productMetadata.categoryDepth3Name == "가디건")
        #expect(metadata.productMetadata.genderCodes == ["WOMEN"])
    }

    @Test func uniqloEmbeddedBreadcrumbRestoresOfficialLeafAndCategoryCodes() throws {
        let html = """
        <script type="application/ld+json">
        [{"@type":"BreadcrumbList","itemListElement":[
          {"position":1,"name":"MEN"},
          {"position":2,"name":"Special Collaborations"},
          {"position":3,"name":"UNIQLO and JW ANDERSON"},
          {"position":4,"name":"바이컬러T"}
        ]},{"@type":"Product","name":"바이컬러T"}]
        </script>
        <script>
        window.__PRELOADED_STATE__ = {
          "entity": {
            "pdpEntity": {
              "E485454-000-00": {
                "product": {
                  "breadcrumbs": {
                    "gender": {"id":"57893","level":1,"name":"men","locale":"MEN"},
                    "class": {"id":"107543","level":2,"name":"special collaboration","locale":"Special Collaborations"},
                    "category": {"id":"107552","level":3,"name":"uniqlo and jw anderson","locale":"UNIQLO and JW ANDERSON"},
                    "subcategory": {"id":"107621","level":4,"name":"t-shirts","locale":"Cut & Sewn"}
                  }
                }
              }
            }
          }
        };
        </script>
        """
        let resolved = ResolvedUniqloURL(
            originalURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E485454-000/00?colorDisplayCode=65&sizeDisplayCode=004")!,
            resolvedURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E485454-000/00")!,
            productID: "E485454",
            goodsID: "485454",
            apiColorCode: "065",
            imageColorCode: "65",
            productIDWithColorCode: "E485454-065",
            html: html
        )

        let metadata = UniqloProductMetadataParser().parse(resolved: resolved)
        let canonical = try #require(ParsedClosetClassification.resolve(
            category: metadata.category,
            detailCategory: metadata.detailCategory,
            sourceDepths: [
                metadata.productMetadata.sourceCategoryDepth1,
                metadata.productMetadata.sourceCategoryDepth2,
                metadata.productMetadata.sourceCategoryDepth3,
                metadata.productMetadata.sourceCategoryDepth4
            ],
            sourcePath: metadata.productMetadata.sourceCategoryPath,
            productName: metadata.productName
        ))

        #expect(metadata.productMetadata.sourceCategoryPath == "Special Collaborations > UNIQLO and JW ANDERSON > Cut & Sewn")
        #expect(metadata.productMetadata.categoryDepth1Code == "107543")
        #expect(metadata.productMetadata.categoryDepth2Code == "107552")
        #expect(metadata.productMetadata.categoryDepth3Code == "107621")
        #expect(metadata.imageURLString == "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/485454/item/krgoods_65_485454_3x4.jpg?width=400")
        #expect(metadata.category == .top)
        #expect(metadata.detailCategory == .shortSleeve)
        #expect(canonical.categoryCode == "tops")
        #expect(canonical.detailCode == "short_sleeve")
        #expect(canonical.garmentFamily == .tshirt)
        #expect(canonical.isValid)
    }

    @Test func uniqloHydrationProductTypeKrIsForwardedVerbatimAsStructuredFact() throws {
        let fixtures = [
            (productID: "E478307", variantID: "E478307-000", value: "캡/모자"),
            (productID: "E485008", variantID: "E485008-001", value: "선글라스"),
            (productID: "E482815", variantID: "E482815-000", value: "슈즈/신발")
        ]

        for fixture in fixtures {
            let html = """
            <script>
            window.__PRELOADED_STATE__ = {
              "entity": {
                "pdpEntity": {
                  "\(fixture.variantID)-00": {
                    "product": {
                      "productId": "\(fixture.variantID)",
                      "productTypeKr": "\(fixture.value)",
                      "breadcrumbs": {
                        "gender": {"id":"57893","level":1,"name":"men","locale":"MEN"},
                        "class": {"id":"57972","level":2,"name":"accessories","locale":"액세서리"},
                        "category": {"id":"58071","level":3,"name":"headwear","locale":"모자"},
                        "subcategory": {"id":"58558","level":4,"name":"caps","locale":"캡"}
                      }
                    }
                  }
                }
              }
            };
            </script>
            """
            let resolved = ResolvedUniqloURL(
                originalURL: try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/\(fixture.variantID)")),
                resolvedURL: try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/\(fixture.variantID)")),
                productID: fixture.productID,
                goodsID: String(fixture.productID.dropFirst()),
                apiColorCode: String(fixture.variantID.suffix(3)),
                imageColorCode: String(fixture.variantID.suffix(2)),
                productIDWithColorCode: fixture.variantID,
                html: html
            )

            let metadata = UniqloProductMetadataParser().parse(resolved: resolved)
            let request = try #require(
                metadata.parsedProductInfo(sizes: []).fitMatchDatabaseResolutionRequest()
            )

            let expectedFacts = [
                "product_type_kr": fixture.value,
                "source_category_path_completeness": "complete",
                "source_category_path_source": "uniqlo_pdp_breadcrumbs"
            ]
            #expect(metadata.productMetadata.structuredFacts == expectedFacts)
            #expect(request.structuredFacts == expectedFacts)
        }
    }

    @Test func uniqloHydrationProductTypeKrOmitsMissingOrAmbiguousEvidence() throws {
        func parsedFacts(pdpEntityJSON: String) -> [String: String] {
            let html = """
            <script>
            window.__PRELOADED_STATE__ = {
              "entity": {"pdpEntity": {\(pdpEntityJSON)}}
            };
            </script>
            """
            let resolved = ResolvedUniqloURL(
                originalURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E478307-000")!,
                resolvedURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E478307-000")!,
                productID: "E478307",
                goodsID: "478307",
                apiColorCode: "000",
                imageColorCode: "00",
                productIDWithColorCode: "E478307-000",
                html: html
            )
            return UniqloProductMetadataParser()
                .parse(resolved: resolved)
                .productMetadata
                .structuredFacts
        }

        let missing = parsedFacts(pdpEntityJSON: """
        "E478307-000-00": {
          "product": {"productId":"E478307-000","breadcrumbs":{}}
        }
        """)
        let ambiguous = parsedFacts(pdpEntityJSON: """
        "E478307-001-00": {
          "product": {"productId":"E478307-001","productTypeKr":"캡/모자","breadcrumbs":{}}
        },
        "E478307-002-00": {
          "product": {"productId":"E478307-002","productTypeKr":"선글라스","breadcrumbs":{}}
        }
        """)
        let malformed = parsedFacts(pdpEntityJSON: """
        "E478307-000-00": {
          "product": {"productId":"E478307-000","productTypeKr":123,"breadcrumbs":{}}
        }
        """)

        #expect(missing["product_type_kr"] == nil)
        #expect(ambiguous["product_type_kr"] == nil)
        #expect(malformed["product_type_kr"] == nil)
    }

    @Test func persistedProductReceivesNewRetailerThumbnailWithoutLosingItLater() {
        let stored = Product(
            name: "바이컬러T",
            category: .top,
            productCode: "E485454",
            imageURLString: nil
        )
        let incoming = Product(
            name: "바이컬러T",
            category: .top,
            productCode: "E485454",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E485454",
            imageURLString: "https://image.uniqlo.com/example.jpg",
            metadata: ProductMetadata(imageURLStrings: ["https://image.uniqlo.com/example.jpg"])
        )

        stored.refreshExternalPresentation(from: incoming)

        #expect(stored.imageURLString == "https://image.uniqlo.com/example.jpg")
        #expect(stored.imageURLStrings == "https://image.uniqlo.com/example.jpg")
        #expect(stored.sourceURLString == "https://www.uniqlo.com/kr/ko/products/E485454")

        stored.refreshExternalPresentation(from: Product(name: "바이컬러T", category: .top))
        #expect(stored.imageURLString == "https://image.uniqlo.com/example.jpg")
    }

    @Test func closetSaveMatchesStoredProductBeforeMatchingSize() {
        let stored = Product(
            name: "크루넥T",
            category: .top,
            productCode: "E485454",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E485454-000/00",
            sourceType: .officialStore,
            sourceName: "유니클로"
        )
        let sameProductFromNewFetch = Product(
            name: "크루넥T",
            category: .top,
            productCode: "E485454",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E485454-000/00/",
            sourceType: .officialStore,
            sourceName: "유니클로"
        )
        let differentProductWithSameSizeLabel = Product(
            name: "에어리즘T",
            category: .top,
            productCode: "E465185",
            sourceURLString: "https://www.uniqlo.com/kr/ko/products/E465185-000/00",
            sourceType: .officialStore,
            sourceName: "유니클로"
        )

        #expect(AddComparedProductToClosetSheet.isSameRetailerProduct(stored, sameProductFromNewFetch))
        #expect(!AddComparedProductToClosetSheet.isSameRetailerProduct(stored, differentProductWithSameSizeLabel))
    }

    @Test func uniqloExplicitUnisexAudienceOverridesFemaleCategoryTarget() {
        let html = """
        <script type="application/ld+json">
        [{"@type":"BreadcrumbList","itemListElement":[
          {"position":1,"name":"WOMEN"},{"position":2,"name":"니트 & 가디건"},
          {"position":3,"name":"니트"},{"position":4,"name":"메리노V넥가디건"}
        ]},{"@type":"Product","name":"메리노V넥가디건"}]
        </script>
        <script>window.product={"genderName":"unisex","genderCategory":"UNISEX","sizeGender":"MEN","topCategories":["men","women"]};</script>
        """
        let resolved = ResolvedUniqloURL(
            originalURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E450540-000/00")!,
            resolvedURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E450540-000/00")!,
            productID: "E450540",
            goodsID: "450540",
            apiColorCode: "000",
            imageColorCode: "00",
            productIDWithColorCode: "E450540-000",
            html: html
        )

        let metadata = UniqloProductMetadataParser().parse(resolved: resolved)

        #expect(metadata.productMetadata.genderCodes == ["UNISEX"])
        #expect(metadata.productMetadata.baseCategoryFullPath == "니트 & 가디건 > 니트")
        #expect(metadata.productMetadata.categoryDepth1Name == "니트 & 가디건")
    }

    @Test func uniqloSizeGenderAloneDoesNotOverrideFemaleAudience() {
        let html = """
        <script type="application/ld+json">
        [{"@type":"BreadcrumbList","itemListElement":[
          {"position":1,"name":"WOMEN"},{"position":2,"name":"팬츠"},{"position":3,"name":"상품"}
        ]},{"@type":"Product","name":"상품"}]
        </script>
        <script>window.product={"sizeGender":"MEN"};</script>
        """
        let resolved = ResolvedUniqloURL(
            originalURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E000001")!,
            resolvedURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E000001")!,
            productID: "E000001", goodsID: "000001", apiColorCode: "000",
            imageColorCode: "00", productIDWithColorCode: "E000001-000", html: html
        )

        let metadata = UniqloProductMetadataParser().parse(resolved: resolved)

        #expect(metadata.productMetadata.genderCodes == ["WOMEN"])
    }

    @Test func musinsaLegacyTypeFiveRestoresVerifiedShoulderChestAndSleeve() {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        let product = Product(
            name: "반소매 티셔츠",
            category: .top,
            metadata: ProductMetadata(sizeType: "5"),
            sourceType: .marketplace,
            sourceName: "무신사",
            sizes: [size]
        )

        let records = MeasurementLegacyBackfillFactory.records(for: size, product: product)
        let byKind = Dictionary(uniqueKeysWithValues: records.compactMap { record in
            record.displayKind.map { ($0, record) }
        })

        #expect(byKind[.shoulder]?.measurementCode == .shoulderWidthSeamToSeam)
        #expect(byKind[.sleeveLength]?.measurementCode == .sleeveShoulderSeamToCuff)
        #expect(byKind[.chest]?.measurementCode == .chestWidthPitToPit)
        #expect(byKind[.totalLength]?.measurementCode == .bodyLengthBackNeckToHem)
        #expect(byKind[.shoulder]?.isComparable == true)
        #expect(byKind[.chest]?.isComparable == true)
        #expect(records.allSatisfy { $0.mappingVersion == MeasurementLegacyBackfillService.mappingVersion })
        #expect(MeasurementLegacyBackfillService.migrationVersion == 9)
    }

    @Test func uniqloLegacyMeasurementsRemainUnknownWithoutRawCodes() {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 46.5, chest: 53, totalLength: 69, sleeveLength: 45)
        )
        let product = Product(
            name: "크루넥T",
            category: .top,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            sizes: [size]
        )

        let records = MeasurementLegacyBackfillFactory.records(for: size, product: product)

        #expect(records.count == 4)
        #expect(records.allSatisfy { $0.measurementCode == .legacyUnknown })
        #expect(records.allSatisfy { !$0.isComparable })
    }

    @Test func mappingUpgradePreservesCanonicalRecordsAndRemovesLegacyDuplicates() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 0, chest: 54, totalLength: 0, sleeveLength: 0)
        )
        let product = Product(
            name: "유니클로 티셔츠",
            category: .top,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            sizes: [size]
        )
        let canonicalRecord = GarmentMeasurementRecord(
            value: 54,
            measurementCode: .unknown,
            displayKind: .chest,
            methodSource: "uniqlo_kr",
            inputSource: .importedSizeChart,
            mappingVersion: "uniqlo_kr_size_chart_mapping_v1",
            rawCode: "body-width",
            rawLabel: "가슴너비",
            evidenceLevel: .unknown,
            semanticStatus: .unknownDefinition,
            productSize: size
        )
        let legacyDuplicate = GarmentMeasurementRecord(
            value: 54,
            measurementCode: .legacyUnknown,
            displayKind: .chest,
            methodSource: "uniqlo_kr",
            inputSource: .migratedLegacy,
            mappingVersion: "legacy_backfill_v2",
            rawLabel: "legacy_chest",
            evidenceLevel: .unknown,
            semanticStatus: .legacyUnknown,
            productSize: size
        )
        size.measurementRecords = [canonicalRecord, legacyDuplicate]
        size.measurementMigrationVersion = 2
        size.measurementMigrationStatus = .completed
        context.insert(product)
        try context.save()

        try MeasurementLegacyBackfillService.run(
            modelContext: context,
            products: [product],
            userFits: []
        )

        let savedRecords = try context.fetch(FetchDescriptor<GarmentMeasurementRecord>())
            .filter { $0.productSize?.id == size.id }
        #expect(savedRecords.count == 1)
        #expect(savedRecords.first?.id == canonicalRecord.id)
        #expect(savedRecords.first?.measurementCode == .chestWidthPitToPit)
        #expect(savedRecords.first?.mappingVersion == MeasurementSourceMappingPolicy.uniqloVersion)
        #expect(size.measurementMigrationVersion == MeasurementLegacyBackfillService.migrationVersion)
    }

    @Test func migrationVersionSevenConvertsLegacyPlatformChestAndLengthsWithoutChangingSleeves() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        let product = Product(name: "기존 상품", category: .top, sourceName: "무신사", sizes: [size])
        let item = comparisonItem(
            shoulder: 48,
            sleeve: 82,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff
        )

        func record(
            code: MeasurementCode,
            kind: MeasurementDisplayKind,
            rawCode: String,
            methodSource: String,
            rawLabel: String
        ) -> GarmentMeasurementRecord {
            GarmentMeasurementRecord(
                value: 50,
                measurementCode: code,
                displayKind: kind,
                methodSource: methodSource,
                methodProfile: "preserved_profile",
                inputSource: .importedSizeChart,
                mappingVersion: "previous_mapping",
                rawCode: rawCode,
                rawLabel: rawLabel,
                evidenceLevel: .officialText,
                semanticStatus: .mapped
            )
        }

        let sizeRecords = [
            record(code: .chestWidthUniqloBodyWidth, kind: .chest, rawCode: "body-width", methodSource: "uniqlo_kr", rawLabel: "가슴너비"),
            record(code: .bodyLengthMusinsaType5, kind: .totalLength, rawCode: "musinsa-5", methodSource: "musinsa", rawLabel: "총장"),
            record(code: .bodyLengthMusinsaType20, kind: .totalLength, rawCode: "musinsa-20", methodSource: "musinsa", rawLabel: "총장"),
            record(code: .bodyLengthMusinsaType21, kind: .totalLength, rawCode: "musinsa-21", methodSource: "musinsa", rawLabel: "총장"),
            record(code: .bodyLengthUniqloBack, kind: .totalLength, rawCode: "body-length-back", methodSource: "uniqlo_kr", rawLabel: "총장"),
            record(code: .bodyLengthUniqloShirt, kind: .totalLength, rawCode: "body-length", methodSource: "uniqlo_kr", rawLabel: "총장"),
            record(code: .bodyLengthUniqloKnitFront, kind: .totalLength, rawCode: "knit-body-length-front", methodSource: "uniqlo_kr", rawLabel: "총장"),
            record(code: .sleeveShoulderSeamToCuff, kind: .sleeveLength, rawCode: "musinsa-sleeve", methodSource: "musinsa", rawLabel: "소매길이")
        ]
        size.measurementRecords = sizeRecords
        sizeRecords.forEach { $0.productSize = size }
        size.measurementMigrationVersion = 4
        size.measurementMigrationStatus = .completed

        let itemChest = record(code: .chestWidthUniqloBodyWidth, kind: .chest, rawCode: "body-width", methodSource: "uniqlo_kr", rawLabel: "가슴너비")
        let itemLength = record(code: .bodyLengthUniqloBack, kind: .totalLength, rawCode: "body-length-back", methodSource: "uniqlo_kr", rawLabel: "총장")
        let itemSleeve = record(code: .sleeveCenterBackToCuff, kind: .sleeveLength, rawCode: "sleeve-length-cb", methodSource: "uniqlo_kr", rawLabel: "소매길이")
        item.measurementRecords = [itemChest, itemLength, itemSleeve]
        item.measurementRecords.forEach { $0.userFit = item }
        item.measurementMigrationVersion = 4
        item.measurementMigrationStatus = .completed

        context.insert(product)
        context.insert(item)
        try context.save()
        try MeasurementLegacyBackfillService.run(
            modelContext: context,
            products: [product],
            userFits: [item]
        )

        #expect(sizeRecords.first?.measurementCode == .chestWidthPitToPit)
        #expect(sizeRecords.dropFirst().dropLast().allSatisfy {
            $0.measurementCode == .bodyLengthBackNeckToHem
        })
        #expect(sizeRecords.last?.measurementCode == .sleeveShoulderSeamToCuff)
        #expect(itemChest.measurementCode == .chestWidthPitToPit)
        #expect(itemLength.measurementCode == .bodyLengthBackNeckToHem)
        #expect(itemSleeve.measurementCode == .sleeveCenterBackToCuff)
        #expect(sizeRecords.allSatisfy { $0.methodProfile == "preserved_profile" })
        #expect(sizeRecords.compactMap(\.rawCode) == [
            "body-width", "musinsa-5", "musinsa-20", "musinsa-21",
            "body-length-back", "body-length", "knit-body-length-front", "musinsa-sleeve"
        ])
        #expect(size.measurementMigrationVersion == MeasurementLegacyBackfillService.migrationVersion)
        #expect(item.measurementMigrationVersion == MeasurementLegacyBackfillService.migrationVersion)
    }

    @Test func migrationVersionSevenRecoversOnlyVerifiedMusinsaTopUnknownTotalLength() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 71, sleeveLength: 0)
        )
        let product = Product(name: "기존 type 24 민소매", category: .top, sourceName: "무신사", sizes: [size])
        let record = GarmentMeasurementRecord(
            value: 71,
            measurementCode: .legacyUnknown,
            displayKind: .totalLength,
            methodSource: "musinsa",
            methodProfile: "musinsa_type_24",
            inputSource: .importedSizeChart,
            mappingVersion: "musinsa_actual_size_mapping_v5",
            rawCode: "legacy-type-24-length",
            rawLabel: "총장",
            rawValueText: "71",
            evidenceLevel: .unknown,
            semanticStatus: .legacyUnknown,
            productSize: size
        )
        size.measurementRecords = [record]
        size.measurementMigrationVersion = 6
        size.measurementMigrationStatus = .completed
        context.insert(product)
        try context.save()

        try MeasurementLegacyBackfillService.run(modelContext: context, products: [product], userFits: [])

        #expect(record.measurementCode == .bodyLengthBackNeckToHem)
        #expect(record.semanticStatus == .mapped)
        #expect(record.value == 71)
        #expect(record.methodSource == "musinsa")
        #expect(record.methodProfile == "musinsa_type_24")
        #expect(record.rawCode == "legacy-type-24-length")
        #expect(record.rawLabel == "총장")
        #expect(record.rawValueText == "71")
        #expect(record.mappingVersion == MeasurementSourceMappingPolicy.musinsaVersion)
        #expect(size.measurementMigrationVersion == MeasurementLegacyBackfillService.migrationVersion)
    }

    @Test func migrationVersionSevenHalvesUniqloCircumferencesExactlyOnce() throws {
        let container = try inMemoryModelContainer()
        let context = ModelContext(container)
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 76, sleeveLength: 0,
                waist: 70, hip: 104
            )
        )
        let product = Product(name: "기존 유니클로 바지", category: .bottom, sourceName: "유니클로 공식몰", sizes: [size])
        let waist = GarmentMeasurementRecord(
            value: 70,
            measurementCode: .unknown,
            displayKind: .waist,
            methodSource: "uniqlo_kr",
            methodProfile: "uniqlo_size_chart",
            inputSource: .importedSizeChart,
            mappingVersion: "uniqlo_kr_size_chart_mapping_v4",
            rawCode: "waist-product-size",
            rawLabel: "허리둘레",
            rawValueText: "70",
            evidenceLevel: .officialText,
            semanticStatus: .mapped,
            productSize: size
        )
        let hip = GarmentMeasurementRecord(
            value: 104,
            measurementCode: .unknown,
            displayKind: .hip,
            methodSource: "uniqlo_kr",
            methodProfile: "uniqlo_size_chart",
            inputSource: .importedSizeChart,
            mappingVersion: "uniqlo_kr_size_chart_mapping_v4",
            rawCode: "hip-product-size",
            rawLabel: "엉덩이둘레",
            rawValueText: "104",
            evidenceLevel: .officialText,
            semanticStatus: .mapped,
            productSize: size
        )
        size.measurementRecords = [waist, hip]
        size.measurementMigrationVersion = 5
        size.measurementMigrationStatus = .completed
        context.insert(product)
        try context.save()

        try MeasurementLegacyBackfillService.run(modelContext: context, products: [product], userFits: [])
        #expect(waist.value == 35)
        #expect(hip.value == 52)
        #expect(size.measurements.waist == 35)
        #expect(size.measurements.hip == 52)
        #expect(waist.rawValueText == "70")
        #expect(hip.rawValueText == "104")

        try MeasurementLegacyBackfillService.run(modelContext: context, products: [product], userFits: [])
        #expect(waist.value == 35)
        #expect(hip.value == 52)
        #expect(size.measurements.waist == 35)
        #expect(size.measurements.hip == 52)
        #expect(size.measurementMigrationVersion == MeasurementLegacyBackfillService.migrationVersion)
    }

    @Test func musinsaLegacyRaglanAndSetInSleevesStaySeparate() {
        let measurements = GarmentMeasurements(shoulder: 0, chest: 54, totalLength: 70, sleeveLength: 42)
        let raglanSize = ProductSize(name: "M", measurements: measurements)
        let setInSize = ProductSize(name: "M", measurements: measurements)
        let raglanProduct = Product(
            name: "라글란 티셔츠",
            category: .top,
            metadata: ProductMetadata(sizeType: "11"),
            sourceName: "무신사",
            sizes: [raglanSize]
        )
        let setInProduct = Product(
            name: "긴소매 티셔츠",
            category: .top,
            metadata: ProductMetadata(sizeType: "21"),
            sourceName: "무신사",
            sizes: [setInSize]
        )

        let raglanSleeve = MeasurementLegacyBackfillFactory.records(for: raglanSize, product: raglanProduct)
            .first { $0.displayKind == .sleeveLength }
        let setInSleeve = MeasurementLegacyBackfillFactory.records(for: setInSize, product: setInProduct)
            .first { $0.displayKind == .sleeveLength }

        #expect(raglanSleeve?.measurementCode == .sleeveRaglanNeckToCuff)
        #expect(setInSleeve?.measurementCode == .sleeveShoulderSeamToCuff)
        #expect(raglanSleeve?.measurementCode != setInSleeve?.measurementCode)
    }

    @Test func userFitOnlyInheritsUnmodifiedVerifiedLegacyValues() {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        let product = Product(
            name: "반소매 티셔츠",
            category: .top,
            metadata: ProductMetadata(sizeType: "5"),
            sourceType: .marketplace,
            sourceName: "무신사",
            sizes: [size]
        )
        size.measurementRecords = MeasurementLegacyBackfillFactory.records(for: size, product: product)

        let item = UserFit(
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "반소매 티셔츠",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(shoulder: 49, chest: 54, totalLength: 70, sleeveLength: 24),
            fitMemo: "",
            satisfaction: 3,
            sourceProduct: product,
            sourceProductSize: size
        )

        let records = MeasurementLegacyBackfillFactory.records(for: item)
        let byKind = Dictionary(uniqueKeysWithValues: records.compactMap { record in
            record.displayKind.map { ($0, record) }
        })

        #expect(byKind[.shoulder]?.measurementCode == .legacyUnknown)
        #expect(byKind[.sleeveLength]?.measurementCode == .sleeveShoulderSeamToCuff)
    }

    private func parsedSize(_ name: String, chest: Double) -> ParsedProductSize {
        ParsedProductSize(name: name, measurements: measurements(chest: chest))
    }

    @Test func shortKnitCanUseShortTshirtAndSleevelessAsManualExpansionCandidates() {
        let product = Product(
            name: "워셔블니트폴로스웨터(반팔)",
            category: .top,
            productCode: "E476997",
            metadata: ProductMetadata(sourceCategoryPath: "니트 & 가디건 > 니트 > 반팔 니트"),
            sourceType: .officialStore,
            sourceName: "유니클로",
            sizes: [ProductSize(
                name: "L",
                measurements: GarmentMeasurements(
                    shoulder: 46, chest: 57, totalLength: 69, sleeveLength: 24
                )
            )]
        )
        let shortTshirt = UserFit(
            sourceType: .officialStore,
            sourceName: "유니클로",
            brandName: "유니클로",
            productName: "AIRism코튼오버사이즈크루넥T",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "XL",
            measurements: GarmentMeasurements(
                shoulder: 56, chest: 62.5, totalLength: 75, sleeveLength: 57
            ),
            fitMemo: "short",
            satisfaction: 4
        )
        let sleeveless = UserFit(
            sourceType: .manual,
            sourceName: "직접 입력",
            brandName: "테스트",
            productName: "민소매 상의",
            category: .top,
            detailCategory: .sleeveless,
            sizeName: "L",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 58, totalLength: 70, sleeveLength: 0
            ),
            fitMemo: "sleeveless",
            satisfaction: 4
        )

        let matcher = ComparisonProfileMatcher()
        let automatic = matcher.match(
            product: product,
            productDetailCategory: .knitTop,
            userFits: [shortTshirt, sleeveless]
        )
        let manual = matcher.manualCandidates(
            product: product,
            productDetailCategory: .knitTop,
            userFits: [shortTshirt, sleeveless]
        )

        #expect(automatic.compatibleCandidates.isEmpty)
        #expect(manual.map(\.id).contains(shortTshirt.id))
        #expect(manual.map(\.id).contains(sleeveless.id))
        #expect(matcher.manualComparisonCompatibility(
            product: product,
            productDetailCategory: .knitTop,
            item: shortTshirt
        ).level == .extended)
    }

    @Test func shortTopManualExpansionPolicyMatrix() {
        let matcher = ComparisonProfileMatcher()
        let shortKnit = topComparisonProduct(
            name: "워셔블니트폴로스웨터(반팔)",
            detail: .knitTop
        )
        let cases: [(String, UserFit, Bool)] = [
            ("반팔티", topComparisonItem(name: "반팔 티셔츠", detail: .shortSleeve), true),
            ("민소매", topComparisonItem(name: "민소매 탑", detail: .sleeveless), true),
            ("반팔셔츠", topComparisonItem(name: "반팔 셔츠", detail: .shirt), true),
            ("반팔스웨트", topComparisonItem(name: "반팔 스웨트셔츠", detail: .sweatshirt), true),
            ("반팔후드", topComparisonItem(name: "반팔 후드티", detail: .hoodie), true),
            ("긴팔티", topComparisonItem(
                name: "긴팔 티셔츠",
                detail: .longSleeve,
                measurements: GarmentMeasurements(shoulder: 47, chest: 58, totalLength: 70, sleeveLength: 60)
            ), true),
            ("긴팔셔츠", topComparisonItem(
                name: "긴팔 셔츠",
                detail: .shirt,
                measurements: GarmentMeasurements(shoulder: 47, chest: 58, totalLength: 70, sleeveLength: 60)
            ), true),
            ("긴팔니트", topComparisonItem(
                name: "긴팔 니트",
                detail: .knitTop,
                measurements: GarmentMeasurements(shoulder: 47, chest: 58, totalLength: 70, sleeveLength: 60)
            ), true)
        ]

        for (label, item, expected) in cases {
            let compatibility = matcher.manualComparisonCompatibility(
                product: shortKnit,
                productDetailCategory: .knitTop,
                item: item
            )
            #expect(compatibility.level.isAllowed == expected, Comment(rawValue: label))
        }
    }

    @Test func shortTopExpansionRequiresTwoCommonCoreMeasurements() {
        let matcher = ComparisonProfileMatcher()
        let product = topComparisonProduct(
            name: "반팔 니트",
            detail: .knitTop,
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 57, totalLength: 69, sleeveLength: 0
            )
        )
        let oneCommon = topComparisonItem(
            name: "반팔 티셔츠",
            detail: .shortSleeve,
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 58, totalLength: 0, sleeveLength: 0
            )
        )
        let twoCommon = topComparisonItem(
            name: "민소매 탑",
            detail: .sleeveless,
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 58, totalLength: 70, sleeveLength: 0
            )
        )

        #expect(!matcher.manualComparisonCompatibility(
            product: product,
            productDetailCategory: .knitTop,
            item: oneCommon
        ).level.isAllowed)
        #expect(matcher.manualComparisonCompatibility(
            product: product,
            productDetailCategory: .knitTop,
            item: twoCommon
        ).level == .extended)
    }

    @Test func longTopStructureGroupsRemainSeparated() {
        let matcher = ComparisonProfileMatcher()
        let longTshirt = topComparisonProduct(name: "긴팔 티셔츠", detail: .longSleeve)
        let sweatshirt = topComparisonProduct(name: "긴팔 맨투맨", detail: .sweatshirt)
        let longKnit = topComparisonItem(name: "긴팔 니트", detail: .knitTop)
        let longShirt = topComparisonItem(name: "긴팔 셔츠", detail: .shirt)
        let hoodie = topComparisonItem(name: "긴팔 후드티", detail: .hoodie)

        #expect(!matcher.manualComparisonCompatibility(
            product: longTshirt,
            productDetailCategory: .longSleeve,
            item: longKnit
        ).level.isAllowed)
        #expect(!matcher.manualComparisonCompatibility(
            product: longTshirt,
            productDetailCategory: .longSleeve,
            item: longShirt
        ).level.isAllowed)
        #expect(matcher.manualComparisonCompatibility(
            product: sweatshirt,
            productDetailCategory: .sweatshirt,
            item: hoodie
        ).level.isAllowed)
    }

    @Test func legacyShortTopWithoutStoredProfileStillBecomesExpansionCandidate() {
        let product = topComparisonProduct(name: "반팔 니트", detail: .knitTop)
        let legacyItem = topComparisonItem(name: "반팔 티셔츠", detail: .shortSleeve)
        legacyItem.garmentType = .unknown
        legacyItem.sleeveType = .unknown
        legacyItem.constructionType = .unknown
        legacyItem.measurementRecords = []

        let candidates = ComparisonProfileMatcher().manualCandidates(
            product: product,
            productDetailCategory: .knitTop,
            userFits: [legacyItem]
        )

        #expect(candidates.map(\.id) == [legacyItem.id])
    }

    private func topComparisonProduct(
        name: String,
        detail: ClosetDetailCategory,
        measurements: GarmentMeasurements = GarmentMeasurements(
            shoulder: 46, chest: 57, totalLength: 69, sleeveLength: 24
        )
    ) -> Product {
        Product(
            name: name,
            category: .top,
            productCode: UUID().uuidString,
            metadata: ProductMetadata(sourceCategoryPath: "상의 > \(detail.rawValue)"),
            sourceType: .officialStore,
            sourceName: "테스트 공식몰",
            sizes: [ProductSize(name: "L", measurements: measurements)]
        )
    }

    private func topComparisonItem(
        name: String,
        detail: ClosetDetailCategory,
        measurements: GarmentMeasurements = GarmentMeasurements(
            shoulder: 47, chest: 58, totalLength: 70, sleeveLength: 25
        )
    ) -> UserFit {
        UserFit(
            sourceType: .manual,
            sourceName: "직접 입력",
            brandName: "테스트",
            productName: name,
            category: .top,
            detailCategory: detail,
            sizeName: "L",
            measurements: measurements,
            fitMemo: name,
            satisfaction: 4
        )
    }

    private func measurements(chest: Double) -> GarmentMeasurements {
        GarmentMeasurements(
            shoulder: 45,
            chest: chest,
            totalLength: 68,
            sleeveLength: 22
        )
    }

    private func comparisonSize(
        shoulder: Double,
        sleeve: Double,
        shoulderCode: MeasurementCode,
        sleeveCode: MeasurementCode
    ) -> ProductSize {
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: shoulder, chest: 54, totalLength: 70, sleeveLength: sleeve)
        )
        size.measurementRecords = [
            comparisonRecord(value: shoulder, code: shoulderCode, kind: .shoulder, productSize: size),
            comparisonRecord(value: sleeve, code: sleeveCode, kind: .sleeveLength, productSize: size),
            comparisonRecord(value: 54, code: .unknown, kind: .chest, productSize: size),
            comparisonRecord(value: 70, code: .unknown, kind: .totalLength, productSize: size)
        ]
        return size
    }

    private func comparisonItem(
        shoulder: Double,
        sleeve: Double,
        shoulderCode: MeasurementCode,
        sleeveCode: MeasurementCode,
        detailCategory: ClosetDetailCategory = .shortSleeve
    ) -> UserFit {
        let item = UserFit(
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "티셔츠",
            category: .top,
            detailCategory: detailCategory,
            sizeName: "M",
            measurements: GarmentMeasurements(shoulder: shoulder, chest: 53, totalLength: 69, sleeveLength: sleeve),
            fitMemo: "",
            satisfaction: 3
        )
        item.measurementRecords = [
            comparisonRecord(value: shoulder, code: shoulderCode, kind: .shoulder, userFit: item),
            comparisonRecord(value: sleeve, code: sleeveCode, kind: .sleeveLength, userFit: item),
            comparisonRecord(value: 53, code: .unknown, kind: .chest, userFit: item),
            comparisonRecord(value: 69, code: .unknown, kind: .totalLength, userFit: item)
        ]
        return item
    }

    private func comparisonRecord(
        value: Double,
        code: MeasurementCode,
        kind: MeasurementKind,
        methodSource: String = "test",
        methodProfile: String? = nil,
        rawCode: String? = nil,
        rawLabel: String? = nil,
        rawValueText: String? = nil,
        productSize: ProductSize? = nil,
        userFit: UserFit? = nil
    ) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(
            value: value,
            measurementCode: code,
            displayKind: kind.displayKind,
            methodSource: methodSource,
            methodProfile: methodProfile,
            inputSource: .importedSizeChart,
            mappingVersion: "test_v1",
            rawCode: rawCode,
            rawLabel: rawLabel ?? kind.title,
            rawValueText: rawValueText,
            evidenceLevel: code == .unknown ? .unknown : .officialText,
            semanticStatus: code == .unknown ? .unknownDefinition : .mapped,
            productSize: productSize,
            userFit: userFit
        )
    }

    private func markChestComparable(_ records: [GarmentMeasurementRecord]) {
        setComparableCode(.chestWidthPitToPit, for: .chest, in: records)
    }

    private func setComparableCode(
        _ code: MeasurementCode,
        for kind: MeasurementKind,
        in records: [GarmentMeasurementRecord]
    ) {
        guard let record = records.first(where: { $0.displayKind == kind.displayKind }) else { return }
        record.measurementCodeRawValue = code.rawValue
        record.evidenceLevelRawValue = MeasurementEvidenceLevel.officialText.rawValue
        record.semanticStatusRawValue = MeasurementSemanticStatus.mapped.rawValue
    }

    private func manualMeasurementViewModel(source: MeasurementEntrySource) -> AddClosetItemViewModel {
        let viewModel = AddClosetItemViewModel()
        viewModel.brand = "테스트"
        viewModel.productName = "반팔 티셔츠"
        viewModel.measurementEntrySource = source
        if source == .otherSizeChart {
            viewModel.measurementSourceName = "29CM"
            viewModel.measurementSourceLabels = [
                .shoulder: "어깨너비",
                .chest: "가슴단면",
                .totalLength: "총장",
                .sleeveLength: "소매길이"
            ]
        }
        viewModel.shoulder = "48"
        viewModel.chest = "54"
        viewModel.totalLength = "70"
        viewModel.sleeveLength = "24"
        return viewModel
    }

    @Test func musinsaStandardSizeAvailabilityUsesFlagsAndActualData() throws {
        let nullData = try MusinsaActualSizeAPIParser().parseActualSize(from: Data(#"{"meta":{"result":"SUCCESS"},"data":null}"#.utf8))
        #expect(nullData.sizes.isEmpty)
        #expect(MusinsaSizeAvailabilityResolver.resolve(
            isUseSize: true, sizeType: "", actualSizes: nullData.sizes, category: .top
        ) == .standardSizeChart)

        let actual = ParsedProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24)
        )
        #expect(MusinsaSizeAvailabilityResolver.resolve(isUseSize: true, sizeType: "5", actualSizes: [actual]) == .actualMeasurements)
        #expect(MusinsaSizeAvailabilityResolver.resolve(isUseSize: false, sizeType: "", actualSizes: []) == .unavailable)
    }

    @Test func musinsaStandardSizeFallbackIsLimitedToBodyChestCategories() {
        for category in [ClothingCategory.top, .outer, .dress] {
            #expect(MusinsaSizeAvailabilityResolver.resolve(
                isUseSize: true, sizeType: " ", actualSizes: [], category: category
            ) == .standardSizeChart)
        }
        for category in [ClothingCategory.bottom, .underwear, .other] {
            #expect(MusinsaSizeAvailabilityResolver.resolve(
                isUseSize: true, sizeType: "", actualSizes: [], category: category
            ) == .unavailable)
        }
        #expect(MusinsaSizeAvailabilityResolver.resolve(
            isUseSize: true, sizeType: "5", actualSizes: [], category: .top
        ) == .unavailable)
    }

    @Test func musinsaFallbackParsesValidUpperHTMLTable() throws {
        let html = """
        <table>
          <tr><th>사이즈</th><th>가슴단면</th><th>총장</th></tr>
          <tr><td>M</td><td>54</td><td>70</td></tr>
          <tr><td>L</td><td>56</td><td>72</td></tr>
        </table><p>단위: cm</p>
        """
        let sizes = MusinsaFallbackTableParser.parseHTML(html, family: .upper)
        let first = try #require(sizes.first)
        #expect(sizes.map(\.name) == ["M", "L"])
        #expect(first.measurements.chest == 54)
        #expect(first.measurements.totalLength == 70)
        #expect(first.measurementRecords.allSatisfy { $0.methodSource == "musinsa_fallback" })
    }

    @Test func musinsaSizeTokenNormalizerSupportsSharedHTMLAndOCRFormats() {
        let valid = [
            "XS", "S", "M", "L", "XL", "XXL", "2XL", "3XL", "4XL", "5XL",
            "FREE", "ONE", "093(S)", "095(M)", "100(L)", "65 (S)", "70 (WM)",
            "85 / XS", "85/XS", "110 / 2XL", "115 / 3XL", "70/S/25~26",
            "225", "230", "235", "S(옥스포드)", "M(White)", "XL(Navy)"
        ]
        #expect(valid.allSatisfy(SizeTokenNormalizer.isValid))
        #expect(["85 / 일반", "가슴 / 113", "85 / XS 상품입니다", "6045676", "M()", "M(옵션/기타)"].allSatisfy {
            !SizeTokenNormalizer.isValid($0)
        })
        #expect(SizeTokenNormalizer.normalizedKey(for: "85 / XS") == "85/XS")
    }

    @Test func musinsaPipelineFixturesParseDeterministically() throws {
        let transposed = MusinsaFallbackTableParser.parseHTML(
            MusinsaSizePipelineFixtures.product6219777HTML,
            family: .upper
        )
        #expect(transposed.map(\.name) == ["093(S)", "095(M)", "100(L)", "105(XL)", "110(XXL)"])
        #expect(transposed.compactMap {
            $0.measurementRecords.first { $0.measurementCode == .chestCircumferenceGarment }?.value
        } == [110, 115, 120, 125, 130])

        let slash = MusinsaFallbackTableParser.parseHTML(
            MusinsaSizePipelineFixtures.product6045676HTML,
            family: .upper
        )
        #expect(slash.map(\.name) == [
            "85 / XS", "90 / S", "95 / M", "100 / L",
            "105 / XL", "110 / 2XL", "115 / 3XL"
        ])
        let first = try #require(slash.first)
        let last = try #require(slash.last)
        #expect(first.measurementRecords.contains {
            $0.measurementCode == .chestCircumferenceGarment && $0.value == 113
        })
        #expect(first.measurements.totalLength == 57)
        #expect(first.measurementRecords.contains {
            $0.measurementCode == .sleeveCenterBackToCuff && $0.value == 46
        })
        #expect(last.measurementRecords.contains {
            $0.measurementCode == .chestCircumferenceGarment && $0.value == 147
        })
        #expect(last.measurements.totalLength == 74)
    }

    @Test func musinsaSingleFreeSizeRequiresAValidMeasurementStructure() {
        let valid = """
        <table><caption>제품 실측 사이즈</caption>
        <tr><th>사이즈</th><th>가슴단면</th><th>총장</th></tr>
        <tr><td>FREE</td><td>54</td><td>70</td></tr></table>
        """
        #expect(MusinsaFallbackTableParser.parseHTML(valid, family: .upper).map(\.name) == ["FREE"])
        #expect(MusinsaFallbackTableParser.parseHTML(
            MusinsaSizePipelineFixtures.productNoticeHTML,
            family: .upper
        ).isEmpty)
        #expect(MusinsaFallbackTableParser.parseHTML(
            MusinsaSizePipelineFixtures.bodyRecommendationHTML,
            family: .upper
        ).isEmpty)
    }

    @Test func musinsaFallbackParsesSlashCompositeSizesFrom6045676HTML() throws {
        let html = """
        <table>
          <tr><th>사이즈</th><th>가슴둘레</th><th>밑단둘레</th><th>총길이</th><th>화장</th></tr>
          <tr><td>85 / XS</td><td>113</td><td>103</td><td>57</td><td>46</td></tr>
          <tr><td>90 / S</td><td>122</td><td>108</td><td>66</td><td>51</td></tr>
          <tr><td>95 / M</td><td>127</td><td>113</td><td>68</td><td>52.5</td></tr>
          <tr><td>100 / L</td><td>132</td><td>118</td><td>70</td><td>54</td></tr>
          <tr><td>105 / XL</td><td>137</td><td>123</td><td>72</td><td>55.5</td></tr>
          <tr><td>110 / 2XL</td><td>142</td><td>128</td><td>74</td><td>57</td></tr>
          <tr><td>115 / 3XL</td><td>147</td><td>133</td><td>74</td><td>57</td></tr>
        </table><p>단위: cm</p>
        """
        let sizes = MusinsaFallbackTableParser.parseHTML(html, family: .upper)
        #expect(sizes.map(\.name) == [
            "85 / XS", "90 / S", "95 / M", "100 / L",
            "105 / XL", "110 / 2XL", "115 / 3XL"
        ])

        let xs = try #require(sizes.first)
        #expect(xs.measurementRecords.contains {
            $0.measurementCode == .chestCircumferenceGarment && $0.value == 113
        })
        #expect(xs.measurements.totalLength == 57)
        #expect(xs.measurementRecords.contains {
            $0.measurementCode == .sleeveCenterBackToCuff && $0.value == 46
        })

        let threeXL = try #require(sizes.last)
        #expect(threeXL.measurementRecords.contains {
            $0.measurementCode == .chestCircumferenceGarment && $0.value == 147
        })
        #expect(threeXL.measurements.totalLength == 74)
        #expect(threeXL.measurementRecords.contains {
            $0.measurementCode == .sleeveCenterBackToCuff && $0.value == 57
        })
    }

    @Test func musinsaFallbackRejectsNonSizeSlashLabels() {
        for invalidSize in ["85 / 일반", "가슴 / 113"] {
            let html = """
            <table>
              <tr><th>사이즈</th><th>가슴둘레</th><th>총길이</th></tr>
              <tr><td>\(invalidSize)</td><td>113</td><td>57</td></tr>
              <tr><td>90 / S</td><td>122</td><td>66</td></tr>
            </table><p>단위: cm</p>
            """
            #expect(MusinsaFallbackTableParser.parseHTML(html, family: .upper).isEmpty)
        }
    }

    @Test func musinsaFallbackParsesMeasurementItemTransposedCompositeSizes() throws {
        let html = """
        <table>
          <tr><th>치수항목</th><th>093(S)</th><th>095(M)</th><th>100(L)</th></tr>
          <tr><th>가슴둘레</th><td>104</td><td>108</td><td>112</td></tr>
          <tr><th>어깨너비</th><td>43</td><td>45</td><td>47</td></tr>
        </table><p>단위: cm</p>
        """
        let sizes = MusinsaFallbackTableParser.parseHTML(html, family: .upper)
        #expect(sizes.map(\.name) == ["093(S)", "095(M)", "100(L)"])
        #expect(sizes[0].measurementRecords.contains {
            $0.measurementCode == .chestCircumferenceGarment && $0.value == 104
        })
        #expect(sizes[0].measurements.chest == 0)
    }

    @Test func musinsaFallbackPreservesSeparateFrontAndBackLengths() throws {
        for labels in [("앞기장", "뒷기장"), ("앞길이", "뒷길이")] {
            let grid = [
                ["치수항목", "S", "M"],
                ["가슴단면", "50", "53"],
                [labels.0, "66", "68"],
                [labels.1, "69", "71"]
            ]
            let sizes = try #require(MusinsaFallbackTableParser.parseGrid(
                grid,
                context: "단위 cm",
                family: .upper
            ))
            #expect(sizes.count == 2)
            #expect(sizes[0].measurements.totalLength == 0)
            #expect(sizes[0].measurementRecords.contains {
                $0.rawLabel == labels.0 && $0.measurementCode == .bodyLengthHPSToHemFront
            })
            #expect(sizes[0].measurementRecords.contains {
                $0.rawLabel == labels.1 && $0.measurementCode == .bodyLengthBackNeckToHem
            })
        }
    }

    @Test func musinsaFallbackParsesCellUnitsAndLowerCircumferenceAliases() throws {
        let grid = [
            ["치수항목", "65 (S)", "70 (WM)"],
            ["허리둘레", "73.5 cm", "780mm"],
            ["허벅지둘레", "58CM", "620mm"],
            ["밑위길이", "27", "28"],
            ["밑단둘레", "44cm", "460mm"]
        ]
        let sizes = try #require(MusinsaFallbackTableParser.parseGrid(
            grid,
            context: "실측 사이즈",
            family: .lower
        ))
        #expect(sizes.map(\.name) == ["65 (S)", "70 (WM)"])
        #expect(sizes[0].measurements.waist == 36.75)
        #expect(sizes[1].measurements.waist == 39)
        #expect(sizes[0].measurements.thigh == 29)
        #expect(sizes[1].measurements.rise == 28)
        let hem = try #require(sizes[1].measurementRecords.first { $0.displayKind == .hem })
        #expect(hem.value == 23)
        #expect(hem.rawLabel == "밑단둘레")
        #expect(hem.rawValueText == "460mm")
        #expect(hem.rawInfo == "cell_unit_mm_to_cm_multiplier=0.1;circumference_to_width_multiplier=0.5")
    }

    @Test func musinsaFallbackParsesLetterFirstCompositeSizesForExplicitSpecTables() throws {
        let grid = [
            ["사이즈", "M(95)", "L(100)", "XL(105)", "XXL(110)"],
            ["가슴둘레", "105", "110", "115", "120"],
            ["어깨너비", "51", "53", "55", "57"],
            ["총기장", "70.5", "72", "73.5", "75"]
        ]
        let sizes = try #require(MusinsaFallbackTableParser.parseGrid(
            grid,
            context: "실측사이즈 단위 cm",
            family: .upper
        ))
        #expect(sizes.map(\.name) == ["M(95)", "L(100)", "XL(105)", "XXL(110)"])
        #expect(sizes[0].measurementRecords.contains {
            $0.measurementCode == .chestCircumferenceGarment && $0.value == 105
        })
    }

    @Test func importedChestCircumferenceReachesSizeFormWithoutWidthConversion() throws {
        let parsed = ParsedProductSize(
            name: "M(95)",
            measurements: GarmentMeasurements(
                shoulder: 51,
                chest: 0,
                totalLength: 70.5,
                sleeveLength: 24.7
            ),
            measurementRecords: [
                ParsedMeasurement(
                    value: 105,
                    measurementCode: .chestCircumferenceGarment,
                    displayKind: .chest,
                    methodSource: "musinsa_fallback",
                    inputSource: .importedSizeChart,
                    rawLabel: "가슴둘레",
                    rawValueText: "105",
                    evidenceLevel: .officialText,
                    semanticStatus: .mapped
                )
            ]
        )

        let form = ShoppingProductViewModel.makeSizeForm(
            from: parsed,
            displayOrder: 0,
            allowsStandardSizeFallback: false
        )
        #expect(form.chest == "105")
        #expect(form.chestUsesCircumference)
        let saved = try #require(form.makeSizeOption(
            category: .top,
            detailCategory: .shortSleeve
        ))
        #expect(saved.measurements.chest == 0)
        #expect(saved.measurementRecords.contains {
            $0.measurementCode == .chestCircumferenceGarment && $0.value == 105
        })
    }

    @Test func measurementResolverUsesCanonicalRecordBeforeZeroLegacyScalar() {
        let record = GarmentMeasurementRecord(
            value: 113,
            measurementCode: .chestCircumferenceGarment,
            displayKind: .chest,
            methodSource: "musinsa_fallback",
            inputSource: .importedSizeChart,
            mappingVersion: "test",
            rawLabel: "가슴둘레",
            rawValueText: "113",
            evidenceLevel: .officialText,
            semanticStatus: .mapped
        )
        let measurements = GarmentMeasurements(
            shoulder: 0,
            chest: 0,
            totalLength: 57,
            sleeveLength: 0
        )
        #expect(MeasurementResolver.value(
            for: .chest,
            measurements: measurements,
            records: [record]
        ) == 113)
        #expect(MeasurementResolver.value(
            for: .chest,
            measurements: measurements,
            records: [record],
            requiredCode: .chestWidthPitToPit
        ) == nil)
    }

    @Test func measurementResolverRejectsUnknownAndAmbiguousRecords() {
        let unknown = GarmentMeasurementRecord(
            value: 113,
            measurementCode: .unknown,
            displayKind: .chest,
            methodSource: "musinsa",
            inputSource: .importedSizeChart,
            mappingVersion: "test",
            rawLabel: "가슴",
            evidenceLevel: .unknown,
            semanticStatus: .unknownDefinition
        )
        let front = GarmentMeasurementRecord(
            value: 66,
            measurementCode: .bodyLengthHPSToHemFront,
            displayKind: .totalLength,
            methodSource: "musinsa_fallback",
            inputSource: .importedSizeChart,
            mappingVersion: "test",
            rawLabel: "앞기장",
            evidenceLevel: .officialText,
            semanticStatus: .mapped
        )
        let back = GarmentMeasurementRecord(
            value: 69,
            measurementCode: .bodyLengthBackNeckToHem,
            displayKind: .totalLength,
            methodSource: "musinsa_fallback",
            inputSource: .importedSizeChart,
            mappingVersion: "test",
            rawLabel: "뒷기장",
            evidenceLevel: .officialText,
            semanticStatus: .mapped
        )
        let legacy = GarmentMeasurements(
            shoulder: 0,
            chest: 54,
            totalLength: 70,
            sleeveLength: 0
        )
        #expect(MeasurementResolver.value(
            for: .chest,
            measurements: legacy,
            records: [unknown]
        ) == nil)
        #expect(MeasurementResolver.value(
            for: .totalLength,
            measurements: legacy,
            records: [front, back]
        ) == nil)
        #expect(MeasurementResolver.value(
            for: .chest,
            measurements: legacy,
            records: [GarmentMeasurementRecord]()
        ) == 54)
    }

    @Test func measurementResolverDisplaysCircumferenceRecordsWithTheirMeaning() {
        let parsed = ParsedMeasurement(
            value: 113,
            measurementCode: .chestCircumferenceGarment,
            displayKind: .chest,
            methodSource: "html",
            inputSource: .importedSizeChart,
            rawLabel: "가슴둘레",
            evidenceLevel: .officialText,
            semanticStatus: .mapped
        )
        let stored = parsed.makeRecord()
        let empty = GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0)

        #expect(MeasurementResolver.value(
            for: .chest,
            measurements: empty,
            records: [parsed]
        ) == 113)
        #expect(MeasurementResolver.title(for: .chest, records: [parsed]) == "가슴둘레")
        #expect(MeasurementResolver.value(
            for: .chest,
            measurements: empty,
            records: [stored]
        ) == 113)
        #expect(MeasurementResolver.title(for: .chest, records: [stored]) == "가슴둘레")
    }

    @Test func musinsaFallbackKeepsStrictTableRejections() {
        let singleSize = """
        <table><tr><th>치수항목</th><th>093(S)</th></tr>
        <tr><th>가슴둘레</th><td>104cm</td></tr>
        <tr><th>어깨너비</th><td>43cm</td></tr></table>
        """
        let bodyRecommendation = """
        <h2>신체 권장 치수</h2><table>
        <tr><th>사이즈</th><th>가슴둘레</th><th>총장</th></tr>
        <tr><td>S</td><td>90</td><td>165</td></tr>
        <tr><td>M</td><td>95</td><td>170</td></tr></table><p>cm</p>
        """
        let descriptiveNumber = """
        <table><tr><th>사이즈</th><th>가슴단면</th><th>총장</th></tr>
        <tr><td>S</td><td>약 52cm (오차 1~2cm)</td><td>68cm</td></tr>
        <tr><td>M</td><td>약 55cm (오차 1~2cm)</td><td>70cm</td></tr></table>
        """
        #expect(MusinsaFallbackTableParser.parseHTML(singleSize, family: .upper).isEmpty)
        #expect(MusinsaFallbackTableParser.parseHTML(bodyRecommendation, family: .upper).isEmpty)
        #expect(MusinsaFallbackTableParser.parseHTML(descriptiveNumber, family: .upper).isEmpty)
    }

    @Test func musinsaFallbackDefaultsMissingUnitToCentimetersAndRejectsSingleSizeRows() {
        let missingUnit = """
        <table><tr><th>size</th><th>chest width</th><th>length</th></tr>
        <tr><td>M</td><td>54</td><td>70</td></tr>
        <tr><td>L</td><td>56</td><td>72</td></tr></table>
        """
        let singleRow = """
        <table><tr><th>size</th><th>chest width</th><th>length (cm)</th></tr>
        <tr><td>FREE</td><td>54</td><td>70</td></tr></table>
        """
        let missingUnitSizes = MusinsaFallbackTableParser.parseHTML(missingUnit, family: .upper)
        #expect(missingUnitSizes.count == 2)
        #expect(missingUnitSizes.first?.measurements.chest == 54)
        #expect(MusinsaFallbackTableParser.parseHTML(singleRow, family: .upper).isEmpty)
    }

    @Test func musinsaFallbackConvertsLowerCircumferencesToComparableWidths() throws {
        let html = """
        <table>
          <tr><th>사이즈</th><th>허리둘레</th><th>인심</th></tr>
          <tr><td>90</td><td>76</td><td>74</td></tr>
          <tr><td>95</td><td>81</td><td>75</td></tr>
        </table><span>cm</span>
        """
        let sizes = MusinsaFallbackTableParser.parseHTML(html, family: .lower)
        let first = try #require(sizes.first)
        let waist = try #require(first.measurementRecords.first { $0.displayKind == .waist })
        #expect(waist.measurementCode == .waistWidthEdgeToEdge)
        #expect(waist.rawInfo == "circumference_to_width_multiplier=0.5")
        #expect(first.measurements.waist == 38)
        #expect(first.measurements.totalLength == 74)
    }

    @Test func musinsaFallbackParsesUnitCellTransposedGiordanoTable() throws {
        let grid = [
            ["(cm)", "28", "29", "30", "31"],
            ["허리둘레", "78.1", "80.6", "83.2", "85.7"],
            ["앞밑위", "26.0", "26.7", "27.3", "27.9"],
            ["총기장", "99.7", "100.3", "101.0", "101.6"]
        ]
        let sizes = try #require(MusinsaFallbackTableParser.parseGrid(
            grid,
            context: "DETAIL SIZE (cm)",
            family: .lower
        ))
        #expect(sizes.map(\.name) == ["28", "29", "30", "31"])
        #expect(sizes[0].measurements.waist == 39.05)
        #expect(sizes[0].measurements.rise == 26)
        #expect(sizes[0].measurements.totalLength == 99.7)
        #expect(sizes[0].measurementRecords.contains {
            $0.measurementCode == .waistWidthEdgeToEdge
        })
    }

    @Test func musinsaFallbackRetriesAndParsesSmallNoisyGiordanoTable() throws {
        let initialGrid = [
            ["59.1", "610", "62.9"],
            ["38.7", "40.6", "42.5"],
            ["44.5", "47.0", "49.5"],
            ["17.1", "17.8", "18.4"]
        ]
        #expect(MusinsaFallbackImageOCR.hasRepeatedNumericRows(initialGrid))

        let retryGrid = [
            ["어서", "너비"],
            ["(cm)", "S", "M", "L"],
            ["총길이", "59.1", "61.0", "62.9"],
            ["총장", "가슴", "너비", "어깨너비", "38.7", "40.6", "42.5"],
            ["가슴너비", "44.5", "47.0", "49.5"],
            ["소매길이", "17.1", "17.8", "18.4"]
        ]
        let sizes = try #require(MusinsaFallbackTableParser.parseGrid(
            retryGrid,
            context: "DETAIL SIZE (cm)",
            family: .upper
        ))
        #expect(sizes.map(\.name) == ["S", "M", "L"])
        #expect(sizes[0].measurements.totalLength == 59.1)
        #expect(sizes[1].measurements.shoulder == 40.6)
        #expect(sizes[1].measurements.chest == 47)
        #expect(sizes[2].measurements.sleeveLength == 18.4)
    }

    @Test func musinsaFallbackParsesProduct4351517WidthsAndFiveSizes() throws {
        let grid = [
            ["사이즈", "064", "067", "070", "073", "076"],
            ["허리둘레", "67", "71", "75", "79", "84"],
            ["엉덩이둘레", "94", "98", "102", "106", "111"],
            ["앞 밑위길이", "30.7", "31.5", "32.3", "33.1", "33.9"],
            ["옷길이(아웃심)", "105.5", "107", "108.5", "110", "111.5"]
        ]
        let sizes = try #require(MusinsaFallbackTableParser.parseGrid(
            grid,
            context: "Size",
            family: .lower
        ))
        #expect(sizes.count == 5)
        #expect(sizes[0].measurements.waist == 33.5)
        #expect(sizes[0].measurements.hip == 47)
        #expect(sizes[0].measurements.rise == 30.7)
        #expect(sizes[0].measurements.totalLength == 105.5)
        #expect(sizes[4].measurements.waist == 42)
        #expect(sizes[4].measurements.hip == 55.5)
    }

    @Test func musinsaFallbackParsesProduct4351517HTMLTable() throws {
        let html = """
        <div class="tblWrap" name="sizeTable">
        <table class="tbl_info" summary="Size"><tbody>
        <tr><th><span>사이즈</span></th><td><span>064</span></td><td><span>067</span></td></tr>
        <tr><th><span>허리둘레</span></th><td><span>67</span></td><td><span>71</span></td></tr>
        <tr><th><span>엉덩이둘레</span></th><td><span>94</span></td><td><span>98</span></td></tr>
        <tr><th><span>앞 밑위길이</span></th><td><span>30.7</span></td><td><span>31.5</span></td></tr>
        <tr><th><span>옷길이(아웃심)</span></th><td><span>105.5</span></td><td><span>107</span></td></tr>
        </tbody></table></div>
        """
        let sizes = MusinsaFallbackTableParser.parseHTML(html, family: .lower)
        #expect(sizes.count == 2)
        #expect(sizes[0].measurements.waist == 33.5)
        #expect(sizes[0].measurements.hip == 47)
    }

    @Test func musinsaFallbackParsesReebokUpperImageTables() throws {
        let tankTop = try #require(MusinsaFallbackTableParser.parseGrid(
            [
                ["사이즈(cm)", "총 기장", "어깨 너비", "가슴 둘레"],
                ["XS", "49", "30", "90"],
                ["S", "51", "32", "95"],
                ["M", "53", "34", "100"]
            ],
            context: "SIZE",
            family: .upper
        ))
        #expect(tankTop.count == 3)
        #expect(tankTop[0].measurements.totalLength == 49)
        #expect(tankTop[0].measurements.shoulder == 30)

        let tee = try #require(MusinsaFallbackTableParser.parseGrid(
            [
                ["사이즈(cm)", "총장", "어깨", "가슴", "소매"],
                ["XS", "64", "38.5", "45", "16"],
                ["2XL", "72", "48.5", "57.5", "21"],
                ["3XL", "72", "50.5", "60", "22"]
            ],
            context: "SIZE",
            family: .upper
        ))
        #expect(tee.map(\.name) == ["XS", "2XL", "3XL"])
        #expect(tee[0].measurements.chest == 45)
        #expect(tee[2].measurements.sleeveLength == 22)
    }

    @Test func musinsaFallbackRecoversReebokBrokenSizeHeaderSafely() throws {
        let sizes = try #require(MusinsaFallbackTableParser.parseGrid(
            [
                ["1/0|2(cm)", "총장", "가슴", "소매"],
                ["S", "61", "63", "86"],
                ["M", "64", "66.5", "89"],
                ["L", "66", "69", "91"],
                ["XL", "68", "71.5", "93"]
            ],
            context: "SIZE cm",
            family: .upper
        ))
        #expect(sizes.map(\.name) == ["S", "M", "L", "XL"])
        #expect(sizes.map(\.measurements.totalLength) == [61, 64, 66, 68])
        #expect(sizes.map(\.measurements.chest) == [63, 66.5, 69, 71.5])
        #expect(sizes.map(\.measurements.sleeveLength) == [86, 89, 91, 93])
    }

    @Test func musinsaFallbackKeepsRowWithOneMissingOptionalMeasurement() throws {
        let sizes = try #require(MusinsaFallbackTableParser.parseGrid(
            [
                ["사이즈(cm)", "총장", "가슴", "소매"],
                ["S", "61", "63", "86"],
                ["M", "64", "66.5", "89"],
                ["L", "66", "69", ""],
                ["XL", "68", "71.5", "93"]
            ],
            context: "사이즈(cm) 총장 가슴 소매",
            family: .upper
        ))

        #expect(sizes.map(\.name) == ["S", "M", "L", "XL"])
        #expect(sizes[2].measurementRecords.map(\.value) == [66, 69])
    }

    @Test func musinsaFallbackJoinsAdjacentAndOverlappingTableFragments() {
        let headerAndTopRows = CGRect(x: 0.05, y: 0.82, width: 0.9, height: 0.12)
        let lowerRows = CGRect(x: 0.06, y: 0.73, width: 0.88, height: 0.12)
        let unrelatedCopy = CGRect(x: 0.15, y: 0.30, width: 0.65, height: 0.08)
        let joined = MusinsaFallbackImageOCR.joinedTableRegions([
            headerAndTopRows, lowerRows, unrelatedCopy
        ])
        #expect(joined.contains {
            $0.minY < lowerRows.minY
                && $0.maxY > headerAndTopRows.maxY
                && $0.minX < headerAndTopRows.minX
                && $0.maxX > headerAndTopRows.maxX
        })
        #expect(!joined.contains { $0.minY < 0.3 && $0.maxY > 0.7 })
    }

    @Test func musinsaFallbackCombinesSplitOCRGridsAndDeduplicatesRows() throws {
        let sizes = try #require(MusinsaFallbackTableParser.parseCandidateGrids(
            [
                [
                    ["사이즈(cm)", "가슴", "소매"],
                    ["S", "61", "63", "86"],
                    ["M", "64", "66.5", "89"],
                    ["L", "66", "69", "91"],
                    ["XL", "68", "71.5", "93"]
                ],
                [
                    ["1/0|2(cm)", "총장", "가슴", "소매"],
                    ["S", "61", "63", "86"],
                    ["M", "64", "66.5", "89"]
                ],
                [
                    ["M", "64", "66.5", "89"],
                    ["L", "66", "69", "91"],
                    ["XL", "68", "71.5", "93"]
                ]
            ],
            context: "SIZE cm",
            family: .upper
        ))
        #expect(sizes.map(\.name) == ["S", "M", "L", "XL"])
        #expect(sizes.map(\.measurements.totalLength) == [61, 64, 66, 68])
        #expect(sizes.map(\.measurements.chest) == [63, 66.5, 69, 71.5])
        #expect(sizes.map(\.measurements.sleeveLength) == [86, 89, 91, 93])
    }

    @Test func musinsaFallbackDoesNotInventSizesFromNumericFragment() {
        #expect(MusinsaFallbackTableParser.parseGrid(
            [
                ["61", "63", "86"],
                ["64", "66.5", "89"],
                ["66", "69", "91"]
            ],
            context: "SIZE cm",
            family: .upper
        ) == nil)
        #expect(MusinsaFallbackTableParser.parseGrid(
            [
                ["깨진헤더", "총장", "가슴", "소매"],
                ["S", "61", "63", "86"]
            ],
            context: "SIZE cm",
            family: .upper
        ) == nil)
    }

    @Test(.enabled(
        if: runsLongImageAudit,
        "Vision 긴이미지 스트레스 검증은 독립 프로세스로 실행합니다."
    ))
    func musinsaFallbackDetectsAndParsesUpperTableAtTopOfLongImage() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 962, height: 3062),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 962, height: 3062))

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 52, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let cellAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 31, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            "SIZE".draw(at: CGPoint(x: 44, y: 28), withAttributes: titleAttributes)

            let columns: [(String, CGFloat)] = [
                ("사이즈(cm)", 65),
                ("총기장", 320),
                ("어깨너비", 535),
                ("가슴둘레", 750)
            ]
            for (text, x) in columns {
                text.draw(at: CGPoint(x: x, y: 150), withAttributes: cellAttributes)
            }
            let rows = [
                ["XS", "49", "30", "90"],
                ["S", "51", "32", "95"],
                ["M", "53", "34", "100"]
            ]
            for (rowIndex, row) in rows.enumerated() {
                let y = CGFloat(245 + rowIndex * 105)
                for (columnIndex, value) in row.enumerated() {
                    value.draw(
                        at: CGPoint(x: columns[columnIndex].1 + 35, y: y),
                        withAttributes: cellAttributes
                    )
                }
            }
            UIColor.darkGray.setStroke()
            context.cgContext.setLineWidth(2)
            for y in [130, 215, 320, 425, 530] {
                context.cgContext.move(to: CGPoint(x: 44, y: y))
                context.cgContext.addLine(to: CGPoint(x: 918, y: y))
            }
            context.cgContext.strokePath()

            "WASHING TIP".draw(
                at: CGPoint(x: 44, y: 760),
                withAttributes: titleAttributes
            )
            for index in 0..<12 {
                "세탁 시 제품에 부착된 취급 주의사항을 확인해 주세요."
                    .draw(
                        at: CGPoint(x: 60, y: 900 + CGFloat(index * 110)),
                        withAttributes: cellAttributes
                    )
            }
        }
        let cgImage = try #require(image.cgImage)
        let regions = MusinsaFallbackImageOCR.denseTableRegions(in: cgImage)
        #expect(regions.prefix(8).contains { $0.maxY >= 0.96 && $0.height > 0.12 })

        let sizes = try #require(MusinsaFallbackImageOCR.parse(
            image: cgImage,
            family: .upper,
            requiresTableRectangle: true,
            sourceDescription: "synthetic-long-top-table"
        ))
        #expect(sizes.map(\.name) == ["XS", "S", "M"])
        #expect(sizes[0].measurements.totalLength == 49)
        #expect(sizes[0].measurements.shoulder == 30)
        let chestCircumference = try #require(sizes[0].measurementRecords.first {
            $0.measurementCode == .chestCircumferenceGarment
        })
        #expect(chestCircumference.value == 90)
        #expect(sizes[0].measurements.chest == 0)
    }

    @Test func musinsaFallbackDetectsSmallTableInsideVeryLongImage() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 1000, height: 6000),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 6000))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18),
                .foregroundColor: UIColor.darkGray
            ]
            let columns: [(String, CGFloat)] = [
                ("사이즈(cm)", 250), ("허리단면", 410), ("엉덩이단면", 555), ("총기장", 720)
            ]
            for (text, x) in columns {
                text.draw(at: CGPoint(x: x, y: 4500), withAttributes: attributes)
            }
            for (rowIndex, row) in [["S", "38", "54", "46"], ["M", "40", "56", "47"], ["L", "42", "58", "48"]].enumerated() {
                for (columnIndex, value) in row.enumerated() {
                    value.draw(
                        at: CGPoint(x: columns[columnIndex].1, y: 4540 + CGFloat(rowIndex * 38)),
                        withAttributes: attributes
                    )
                }
            }
        }
        let cgImage = try #require(image.cgImage)
        let regions = MusinsaFallbackImageOCR.denseTableRegions(in: cgImage)
        #expect(regions.contains { $0.minY < 0.28 && $0.maxY > 0.18 })
    }

    @Test func musinsaFallbackParsesGiordanoUpperLongImageTableGrid() throws {
        let grid = [
            ["(cm)", "S", "M", "L"],
            ["총길이", "59.1", "61.0", "62.9"],
            ["어깨너비", "38.7", "40.6", "42.5"],
            ["가슴너비", "44.5", "47.0", "49.5"],
            ["소매길이", "17.1", "17.8", "18.4"]
        ]
        let sizes = try #require(MusinsaFallbackTableParser.parseGrid(
            grid,
            context: "DETAIL SIZE (cm)",
            family: .upper
        ))
        #expect(sizes.map(\.name) == ["S", "M", "L"])
        #expect(sizes[0].measurements.totalLength == 59.1)
        #expect(sizes[1].measurements.shoulder == 40.6)
        #expect(sizes[1].measurements.chest == 47)
        #expect(sizes[2].measurements.sleeveLength == 18.4)
    }

    @Test func musinsaFallbackSeparatesShoesFromApparelFootRanges() throws {
        let html = """
        <table>
          <tr><th>사이즈</th><th>발길이(mm)</th></tr>
          <tr><td>260</td><td>260</td></tr>
          <tr><td>270</td><td>270</td></tr>
        </table>
        """
        let shoes = MusinsaFallbackTableParser.parseHTML(html, family: .shoes)
        let first = try #require(shoes.first)
        #expect(first.measurements.footLength == 26)
        #expect(MusinsaFallbackTableParser.parseHTML(html, family: .upper).isEmpty)
        #expect(MusinsaFallbackTableParser.parseHTML(html, family: .lower).isEmpty)
    }

    @Test func musinsaFallbackParsesLooseHeaderAndScopesUnitsToCurrentTable() throws {
        let html = """
        <p>신발 사이즈 안내: KOREA 260mm</p>
        <table>
          <th>사이즈</th><th>가슴단면</th><th>상의 길이</th>
          <tr><td>70/S/25~26</td><td>52cm</td><td>68cm</td></tr>
          <tr><td>75/M/27~28</td><td>55cm</td><td>70cm</td></tr>
        </table>
        """
        let sizes = MusinsaFallbackTableParser.parseHTML(html, family: .upper)
        #expect(sizes.map(\.name) == ["70/S/25~26", "75/M/27~28"])
        #expect(sizes[0].measurements.chest == 52)
        #expect(sizes[0].measurements.totalLength == 68)
    }

    @Test func musinsaFallbackCanonicalizesKoreanAliasesWithoutMergingDifferentMethods() throws {
        let sizes = try #require(MusinsaFallbackTableParser.parseGrid(
            [
                ["치수항목", "S", "M"],
                ["어깨 넓이", "42", "44"],
                ["가슴너비", "51", "54"],
                ["앞기장", "66", "68"],
                ["뒷기장", "69", "71"],
                ["화장", "78", "80"],
                ["소매장", "61", "62"]
            ],
            context: "단위 cm",
            family: .upper
        ))
        let records = sizes[0].measurementRecords
        #expect(records.contains {
            $0.rawLabel == "어깨 넓이" && $0.measurementCode == .shoulderWidthSeamToSeam
        })
        #expect(records.contains {
            $0.rawLabel == "화장" && $0.measurementCode == .sleeveCenterBackToCuff
        })
        #expect(records.contains {
            $0.rawLabel == "소매장" && $0.measurementCode == .sleeveShoulderSeamToCuff
        })
        #expect(records.contains {
            $0.rawLabel == "앞기장" && $0.measurementCode == .bodyLengthHPSToHemFront
        })
        #expect(records.contains {
            $0.rawLabel == "뒷기장" && $0.measurementCode == .bodyLengthBackNeckToHem
        })
    }

    @Test func musinsaFallbackParsesKoreanShoeConversionRowAndRejectsSingleReference() throws {
        let conversion = """
        <table>
          <tr><th>국가</th><th>1</th><th>2</th><th>3</th></tr>
          <tr><th>US</th><td>5</td><td>5.5</td><td>6</td></tr>
          <tr><th>KOREA</th><td>225</td><td>230</td><td>235</td></tr>
        </table>
        """
        let sizes = MusinsaFallbackTableParser.parseHTML(conversion, family: .shoes)
        #expect(sizes.map(\.name) == ["225", "230", "235"])
        #expect(sizes.map(\.measurements.footLength) == [22.5, 23, 23.5])
        #expect(sizes[0].measurementRecords[0].rawLabel == "KOREA")
        #expect(sizes[0].measurementRecords[0].rawInfo == "table_unit_mm_to_cm_multiplier=0.1")

        let singleReference = """
        <table><tr><th>US</th><td>6</td></tr>
        <tr><th>KOREA</th><td>240</td></tr>
        <tr><th>굽 높이</th><td>3cm</td></tr></table>
        """
        #expect(MusinsaFallbackTableParser.parseHTML(singleReference, family: .shoes).isEmpty)
    }

    @Test func musinsaFallbackRejectsDescriptionNumbersWithoutTableStructure() {
        let html = """
        <div>배송은 2~3일 소요됩니다. 세탁은 30도 이하를 권장합니다.</div>
        <img src="https://example.com/delivery_100.jpg">
        """
        #expect(MusinsaFallbackTableParser.parseHTML(html, family: .upper).isEmpty)
        #expect(MusinsaFallbackImageExtractor.images(in: html).allSatisfy { !$0.isExplicitSizeImage })
    }

    @Test func standardBodySizeChartNormalizesSupportedOptionsOnly() {
        #expect(StandardBodySizeChart.normalizedSize(from: "그레이/M") == "M")
        #expect(StandardBodySizeChart.chestCircumferenceCm(for: "95(M)") == 95)
        #expect(StandardBodySizeChart.chestCircumferenceCm(for: "XL") == 105)
        #expect(StandardBodySizeChart.chestCircumferenceCm(for: "44(85)") == 85)
        #expect(StandardBodySizeChart.chestCircumferenceCm(for: "FREE") == nil)
        #expect(StandardBodySizeChart.chestCircumferenceCm(for: "3XL") == nil)
        #expect(StandardBodySizeChart.chestCircumferenceCm(for: "브라_S 팬티_L") == nil)
    }

    @Test func standardSizeFallbackComparesCircumferencesWithoutStoringActualChest() throws {
        let metadata = ProductMetadata(sizeType: StandardBodySizeChart.metadataMarker)
        let size = ProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0)
        )
        let product = Product(name: "기준표 상품", category: .top, metadata: metadata, sourceName: "무신사", sizes: [size])
        let reference = UserFit(
            brandName: "테스트",
            productName: "기준 옷",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "L",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24),
            fitMemo: "",
            satisfaction: 3
        )

        let history = try #require(RecommendationService().recommend(
            product: product,
            selectedReferenceItem: reference,
            productDetailCategory: .shortSleeve
        ))
        #expect(history.comparisonMode == .standardSizeFallback)
        #expect(history.measurementDifferences.chest == -5)
        #expect(history.comparedMeasurementUsages == [MeasurementComparisonUsage(kind: .chest, measurementCode: .standardBodyChestCircumference)])
        #expect(size.chest == 0)
        #expect(history.trueToSizeRecommendation.contains("5cm"))
    }

    @Test func mixedActualAndStandardComparisonConvertsBothOptionNames() throws {
        let actualSize = ProductSize(
            name: "L",
            measurements: GarmentMeasurements(shoulder: 48, chest: 55, totalLength: 70, sleeveLength: 24)
        )
        let actualProduct = Product(name: "실측 상품", category: .top, metadata: ProductMetadata(sizeType: "5"), sizes: [actualSize])
        let standardSource = Product(
            name: "기준표 옷",
            category: .top,
            metadata: ProductMetadata(sizeType: StandardBodySizeChart.metadataMarker),
            sizes: []
        )
        let reference = UserFit(
            brandName: "테스트",
            productName: "기준 옷",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "M",
            measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: 70, sleeveLength: 24),
            fitMemo: "",
            satisfaction: 3,
            sourceProduct: standardSource
        )

        let history = try #require(RecommendationService().recommend(
            product: actualProduct,
            selectedReferenceItem: reference,
            productDetailCategory: .shortSleeve
        ))
        #expect(history.comparisonMode == .standardSizeFallback)
        #expect(history.measurementDifferences.chest == 5)
        #expect(history.recommendedSize.chest == 55)
    }

    @Test func unsupportedStandardSizeDoesNotCreateZeroPercentRecommendation() {
        let product = Product(
            name: "프리 상품",
            category: .top,
            metadata: ProductMetadata(sizeType: StandardBodySizeChart.unavailableMarker),
            sizes: [ProductSize(name: "FREE", measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0))]
        )
        let reference = comparisonUserFit(name: "기준 옷", detail: .shortSleeve, sleeve: 24)
        let history = RecommendationService().recommend(
            product: product,
            selectedReferenceItem: reference,
            productDetailCategory: .shortSleeve
        )
        #expect(history == nil)
    }

    @Test func parsedCanonicalClassificationFallsBackToActiveTaxonomyDetail() throws {
        #expect(FitMatchTaxonomyProvider.shared.isValidDetail("shirt", for: "tops"))
        let result = try #require(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .shirt,
            sourceDepths: ["상의", "셔츠", nil, nil],
            sourcePath: "상의 > 셔츠",
            productName: "옥스포드 셔츠"
        ))
        #expect(result.detailCode == "shirt")
        #expect(result.garmentFamily == .shirt)
        #expect(result.isValid)
    }

    @Test func parsedCanonicalClassificationPreservesRefinedUniqloDetail() throws {
        let graphicTeePath = "티셔츠 & 스웨트셔츠 & UT > PEACE FOR ALL > 그래픽 티셔츠"
        let graphicTee = try #require(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .shortSleeve,
            sourceDepths: graphicTeePath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: graphicTeePath,
            productName: "PEACE FOR ALL 그래픽T(레귤러핏)Kei Nishikori"
        ))
        #expect(graphicTee.categoryCode == "tops")
        #expect(graphicTee.detailCode == "short_sleeve")
        #expect(graphicTee.garmentFamily == .tshirt)
        #expect(graphicTee.lengthType == .short)

        let unresolvedGraphicTee = ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .other,
            sourceDepths: graphicTeePath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: graphicTeePath,
            productName: "소매 정보 없는 그래픽T"
        )
        #expect(unresolvedGraphicTee == nil)

        let braCamisolePath = "이너웨어 > 브라탑 > 코튼"
        let braCamisole = try #require(ParsedClosetClassification.resolve(
            category: .underwear,
            detailCategory: .womenBra,
            sourceDepths: braCamisolePath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: braCamisolePath,
            productName: "스퀘어넥브라캐미솔"
        ))
        #expect(braCamisole.categoryCode == "underwear")
        #expect(braCamisole.detailCode == "women_bra")
        #expect(braCamisole.detailCategory == .womenBra)
    }

    @Test func uniqloKoreanUnderwearPathOverridesIncorrectTopCategory() throws {
        for fixture in [
            ("BOYS AIRism복서브리프3P", "E478656"),
            ("AIRism메쉬심리스복서브리프(프린트)A", "E482565"),
            ("AIRism복서브리프(로라이즈)", "E484997"),
        ] {
            let result: ParsedClosetClassification = try #require(ParsedClosetClassification.resolve(
                category: .top,
                detailCategory: .menBriefs,
                sourceDepths: ["에어리즘", "언더웨어"],
                sourcePath: "에어리즘 > 언더웨어",
                productName: fixture.0
            ))
            #expect(result.categoryCode == "underwear")
            #expect(result.detailCode == "men_briefs")
            #expect(result.category == .underwear)
            #expect(result.detailCategory == .menBriefs)
        }
    }

    @Test func uniqloAirismCottonCrewNeckTUsesTShirtStructureDespiteInnerwearPath() throws {
        let sourcePath = "이너웨어 > 에어리즘 > 코튼"
        let shortSleeve = try #require(ParsedClosetClassification.resolve(
            category: .underwear,
            detailCategory: .underwear,
            sourceDepths: sourcePath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: sourcePath,
            productName: "AIRism코튼크루넥T"
        ))
        #expect(shortSleeve.categoryCode == "tops")
        #expect(shortSleeve.detailCode == "short_sleeve")
        #expect(shortSleeve.category == .top)
        #expect(shortSleeve.detailCategory == .shortSleeve)
        #expect(shortSleeve.garmentFamily == .tshirt)

        let longSleeve = try #require(ParsedClosetClassification.resolve(
            category: .underwear,
            detailCategory: .underwear,
            sourceDepths: sourcePath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: sourcePath,
            productName: "AIRism코튼크루넥T(긴팔)"
        ))
        #expect(longSleeve.categoryCode == "tops")
        #expect(longSleeve.detailCode == "long_sleeve")
        #expect(longSleeve.detailCategory == .longSleeve)

        let vNeck = try #require(ParsedClosetClassification.resolve(
            category: .underwear,
            detailCategory: .underwear,
            sourceDepths: sourcePath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: sourcePath,
            productName: "AIRism코튼V넥T(반팔)"
        ))
        #expect(vNeck.categoryCode == "tops")
        #expect(vNeck.detailCode == "short_sleeve")
        #expect(vNeck.garmentFamily == .tshirt)

        for productName in ["AIRismU넥T", "AIRism메쉬크루넥T"] {
            let undershirt = try #require(ParsedClosetClassification.resolve(
                category: .underwear,
                detailCategory: .underwear,
                sourceDepths: ["이너웨어", "에어리즘", "에어리즘"].map(Optional.some),
                sourcePath: "이너웨어 > 에어리즘 > 에어리즘",
                productName: productName
            ))
            #expect(undershirt.categoryCode == "underwear", "\(productName)은 실제 이너웨어 라인을 유지해야 합니다.")
        }

        let explicitUnderwearFixtures: [(String, String)] = [
            ("AIRism메쉬심리스복서브리프(프린트)A", "men_briefs"),
            ("AIRism쉐이퍼쇼츠(스무드)", "women_panty"),
            ("GIRLS AIRism퍼스트브라", "women_bra"),
        ]
        for fixture in explicitUnderwearFixtures {
            let underwear = try #require(ParsedClosetClassification.resolve(
                category: .top,
                detailCategory: .other,
                sourceDepths: ["이너웨어", "에어리즘", "언더웨어"].map(Optional.some),
                sourcePath: "이너웨어 > 에어리즘 > 언더웨어",
                productName: fixture.0
            ))
            #expect(underwear.categoryCode == "underwear")
            #expect(underwear.detailCode == fixture.1)
        }
    }

    @Test func uniqloAirismLineUsesGarmentCategoryInsteadOfAirismToken() throws {
        let fixtures: [(ClothingCategory, ClosetDetailCategory, String, String, String)] = [
            (.underwear, .menBriefs, "이너웨어 > 에어리즘 > 브리프", "AIRism복서브리프", "underwear"),
            (.top, .shortSleeve, "티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 에어리즘 코튼", "AIRism코튼T", "tops"),
            (.bottom, .other, "팬츠 > 조거팬츠", "W울트라스트레치AIRism조거팬츠", "bottoms"),
            (.dress, .onePiece, "원피스 & 스커트 > 원피스 > 반팔원피스", "AIRism코튼T원피스(반팔)", "dresses")
        ]

        for fixture in fixtures {
            let result = try #require(ParsedClosetClassification.resolve(
                category: fixture.0,
                detailCategory: fixture.1,
                sourceDepths: fixture.2.components(separatedBy: " > ").map(Optional.some),
                sourcePath: fixture.2,
                productName: fixture.3
            ))
            #expect(result.categoryCode == fixture.4, "\(fixture.3)의 AIRism 기능명이 의류 대분류를 덮어쓰면 안 됩니다.")
        }
    }

    @Test func uniqloNestedKnitStructureSurvivesGenericLeafCategories() throws {
        let parser = UniqloProductMetadataParser()
        let fixtures = [
            ("니트 & 가디건 > 니트 > 브이넥", "메리노V넥스웨터", "knit_top"),
            ("니트 & 가디건 > 니트 > 터틀넥", "캐시미어터틀넥스웨터", "knit_top"),
            ("니트 & 가디건 > 니트 > 워셔블", "워셔블니트V넥스웨터(스무드)", "knit_top"),
            ("니트 & 가디건 > 니트 > GU", "GU워셔블니트폴로셔츠 (반팔)", "polo_shirt"),
        ]

        for fixture in fixtures {
            let category = parser.mapCategory(from: fixture.0)
            let detail = parser.mapDetailCategory(from: "\(fixture.0) \(fixture.1)")
            let classification = try #require(ParsedClosetClassification.resolve(
                category: category,
                detailCategory: detail,
                sourceDepths: fixture.0.components(separatedBy: " > ").map(Optional.some),
                sourcePath: fixture.0,
                productName: fixture.1
            ))
            #expect(category == .knit)
            #expect(classification.categoryCode == "tops")
            #expect(classification.detailCode == fixture.2)
        }

        #expect(parser.mapCategory(
            from: "Special Collaborations > UNIQLO and JW ANDERSON > Cut & Sewn"
        ) == .top)
    }

    @Test func uniqloGenericInnerwearTMeasurementsSurviveProductCreation() throws {
        let sourcePath = "이너웨어 > 에어리즘 > 에어리즘"
        let parser = UniqloProductMetadataParser()
        let info = ParsedProductInfo(
            sourceURL: URL(string: "https://www.uniqlo.com/kr/ko/products/E454311-000/00")!,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            brandName: "유니클로",
            productName: "AIRism V넥T",
            category: parser.mapCategory(from: sourcePath),
            detailCategory: parser.mapDetailCategory(from: "\(sourcePath) AIRism V넥T"),
            sizes: [ParsedProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 0,
                    chest: 49,
                    totalLength: 68,
                    sleeveLength: 0
                )
            )],
            productID: "E454311",
            sourceCategoryPath: sourcePath,
            sourceCategoryDepth1: "이너웨어",
            sourceCategoryDepth2: "에어리즘",
            sourceCategoryDepth3: "에어리즘",
            productTargetGender: .men,
            productMetadata: ProductMetadata(
                sourceCategoryPath: sourcePath,
                sourceCategoryDepth1: "이너웨어",
                sourceCategoryDepth2: "에어리즘",
                sourceCategoryDepth3: "에어리즘",
                genderCodes: ["MEN"]
            )
        )
        let viewModel = ShoppingProductViewModel(initialURL: info.sourceURL.absoluteString)
        viewModel.apply(info)
        let product = try #require(viewModel.makeProductForClosetRegistration(brand: nil as Brand?))

        #expect(product.category == .underwear)
        #expect(product.categoryCode == "underwear")
        #expect(product.sizes.count == 1)
        #expect(product.sizes[0].measurements.chest == 49)
        #expect(product.sizes[0].measurements.totalLength == 68)
    }

    @Test func uniqloAirismInnerShortsRemainUnderwearDespitePantsToken() throws {
        let sourcePath = "이너웨어 > 에어리즘 > 속바지"
        let result = try #require(ParsedClosetClassification.resolve(
            category: .bottom,
            detailCategory: .other,
            sourceDepths: sourcePath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: sourcePath,
            productName: "AIRism속바지"
        ))
        #expect(result.categoryCode == "underwear")
        #expect(result.detailCode == "women_panty")
    }

    @Test func uniqloGraphicTeeUsesSourceCategoryAndOfficialSleeveMeasurement() throws {
        let parser = UniqloProductMetadataParser()
        let sourcePath = "티셔츠 & 스웨트셔츠 & UT > 그래픽티셔츠 > NY POP ART"

        // "티셔츠"가 "셔츠"로 잘못 선판정되지 않고 실측 판정을 기다린다.
        #expect(parser.mapDetailCategory(from: sourcePath) == .other)

        func parsedProduct(productID: String, productName: String) -> ParsedProductInfo {
            let sleeve = ParsedMeasurement(
                value: 50,
                measurementCode: .sleeveCenterBackToCuff,
                displayKind: .sleeveLength,
                methodSource: "uniqlo_kr",
                methodProfile: "uniqlo_top_back",
                inputSource: .importedSizeChart,
                rawCode: "sleeve-length-cb",
                rawLabel: "등 중심부터 소매까지 길이",
                evidenceLevel: .officialDiagram,
                semanticStatus: .mapped
            )
            return ParsedProductInfo(
                sourceURL: URL(string: "https://store-kr.uniqlo.com/kr/ko/products/\(productID)-000/00")!,
                sourceType: .officialStore,
                sourceName: "유니클로 공식몰",
                brandName: "UNIQLO",
                productName: productName,
                category: .top,
                detailCategory: parser.mapDetailCategory(from: "\(sourcePath) \(productName)"),
                sizes: [ParsedProductSize(
                    name: "L",
                    measurements: GarmentMeasurements(
                        shoulder: 53, chest: 55.5, totalLength: 70, sleeveLength: 50
                    ),
                    measurementRecords: [sleeve]
                )],
                productID: productID,
                sourceCategoryPath: sourcePath,
                sourceCategoryDepth1: "티셔츠 & 스웨트셔츠 & UT",
                sourceCategoryDepth2: "그래픽티셔츠",
                sourceCategoryDepth3: "NY POP ART",
                productTargetGender: .men,
                productMetadata: ProductMetadata(
                    sourceCategoryPath: sourcePath,
                    sourceCategoryDepth1: "티셔츠 & 스웨트셔츠 & UT",
                    sourceCategoryDepth2: "그래픽티셔츠",
                    sourceCategoryDepth3: "NY POP ART",
                    genderCodes: ["MEN"]
                )
            ).normalizedSizes()
        }

        for fixture in [
            ("E493045", "NY POP ART UT(그래픽T)Andy Warhol"),
            ("E493046", "NY POP ART UT(그래픽T)Keith Haring")
        ] {
            let parsed = parsedProduct(productID: fixture.0, productName: fixture.1)
            #expect(parsed.detailCategory == .shortSleeve)
            let canonical = try #require(ParsedClosetClassification.resolve(
                category: parsed.category,
                detailCategory: parsed.detailCategory,
                sourceDepths: [parsed.sourceCategoryDepth1, parsed.sourceCategoryDepth2,
                               parsed.sourceCategoryDepth3, parsed.sourceCategoryDepth4],
                sourcePath: parsed.sourceCategoryPath,
                productName: parsed.productName
            ))
            #expect(canonical.detailCode == "short_sleeve")
            #expect(canonical.detailCategory == .shortSleeve)
            #expect(canonical.garmentFamily == .tshirt)
            #expect(canonical.lengthType == .short)
        }
    }

    @Test func parsedCanonicalClassificationUsesDeepestPaddingCategory() throws {
        let fixtures: [([String?], String)] = [
            (["아우터", "경량 패딩/패딩 베스트", "경량 패딩", nil], "light_padding"),
            (["아우터", "경량 패딩/패딩 베스트", "패딩 베스트", nil], "padded_vest"),
            (["아우터", "패딩", "롱패딩", nil], "long_padding"),
            (["아우터", "코트", "트렌치 코트", nil], "trench_coat"),
            (["아우터", "재킷", "블레이저", nil], "blazer")
        ]
        for (depths, expected) in fixtures {
            let result = try #require(ParsedClosetClassification.resolve(
                category: .outer,
                detailCategory: .padding,
                sourceDepths: depths,
                sourcePath: depths.compactMap { $0 }.joined(separator: " > "),
                productName: "테스트 상품"
            ))
            #expect(result.detailCode == expected)
        }
    }

    @Test func parsedCanonicalClassificationResolvesRequiredSourceFixtures() throws {
        let fixtures: [(String, String, ClothingCategory, ClosetDetailCategory, String, String)] = [
            ("스커트 > 롱 스커트", "롱 스커트", .bottom, .skirt, "skirts", "skirt"),
            ("원피스/스커트 > 미니원피스", "미니 원피스", .dress, .onePiece, "dresses", "one_piece"),
            ("원피스/스커트 > 원피스 > 미디", "미디 원피스", .dress, .onePiece, "dresses", "one_piece"),
            ("원피스/스커트 > 스커트 > 롱", "롱 스커트", .bottom, .skirt, "skirts", "skirt"),
            ("여성 > 여성 속옷 하의", "팬티", .bottom, .other, "underwear", "women_panty"),
            ("속옷/홈웨어 > 여성 속옷 > 브라", "와이어리스 브라", .underwear, .underwear, "underwear", "women_bra"),
            ("홈웨어 > 파자마", "라운지 세트", .other, .other, "homewear", "loungewear"),
            ("아우터 > 카디건", "긴팔 카디건", .outer, .longSleeve, "outerwear", "cardigan"),
            ("Women > Bottoms > Short Pants", "협업 쇼트 팬츠", .bottom, .shorts, "bottoms", "shorts"),
            ("Women > Tops > Sleeveless", "슬리브리스 탑", .top, .sleeveless, "tops", "sleeveless"),
            ("Women > Skirts", "플레어 스커트", .bottom, .skirt, "skirts", "skirt")
        ]
        for fixture in fixtures {
            let result = try #require(ParsedClosetClassification.resolve(
                category: fixture.2, detailCategory: fixture.3,
                sourceDepths: fixture.0.components(separatedBy: " > ").map(Optional.some),
                sourcePath: fixture.0, productName: fixture.1
            ))
            #expect(result.categoryCode == fixture.4)
            #expect(result.detailCode == fixture.5)
            #expect(result.isValid)
        }

        let overshirt = try #require(ParsedClosetClassification.resolve(
            category: .top, detailCategory: .shortSleeve,
            sourceDepths: ["Men", "Tops", "Shirts", nil],
            sourcePath: "Men > Tops > Shirts", productName: "데님 오버셔츠 반팔"
        ))
        #expect(overshirt.categoryCode == "tops")
        #expect(overshirt.detailCode == "short_sleeve")
        #expect(overshirt.garmentFamily == .shirt)
    }

    @Test func genericMusinsaPathsUseProductNameForSpecificComparisonCategory() throws {
        let fixtures: [(String, String, ClothingCategory, String)] = [
            ("바지 > 기타 하의", "시어서커 원 턱 와이드 밴딩 팬츠", .bottom, "long_pants"),
            ("바지 > 기타 하의", "CHAMBRAY EASY PANTS", .bottom, "long_pants"),
            ("바지 > 기타 하의", "워시드 레귤러 워크 팬츠", .bottom, "long_pants"),
            ("아우터 > 기타 아우터", "메트로폴리스 퍼텍스 오버셔츠 재킷", .outer, "jacket"),
            ("아우터 > 기타 아우터", "시어서커 체크 윈드브레이커", .outer, "windbreaker"),
            ("아우터 > 기타 아우터", "윈드러너 오버사이즈 데님 재킷", .outer, "jacket"),
            ("아우터 > 기타 아우터", "아디컬러 트랙탑", .outer, "jacket")
        ]

        for fixture in fixtures {
            let result = try #require(ParsedClosetClassification.resolve(
                category: fixture.2,
                detailCategory: .other,
                sourceDepths: fixture.0.components(separatedBy: " > ").map(Optional.some),
                sourcePath: fixture.0,
                productName: fixture.1
            ))
            #expect(result.detailCode == fixture.3, "\(fixture.1)의 세부 분류가 잘못됐습니다.")
        }
    }

    @Test func genericBottomPathDoesNotTreatJumpsuitAsLongPants() throws {
        let result = try #require(ParsedClosetClassification.resolve(
            category: .bottom,
            detailCategory: .other,
            sourceDepths: ["바지", "기타 하의", nil, nil],
            sourcePath: "바지 > 기타 하의",
            productName: "유틸리티 오버올 점프수트 팬츠"
        ))

        #expect(result.detailCode == "other_bottoms")
    }

    @Test func genericBottomAndLeggingsPathsUseExplicitProductLength() throws {
        let fixtures: [(String, String, ClothingCategory, ClosetDetailCategory, String)] = [
            ("바지 > 코튼 팬츠", "우먼즈 코튼 카프리 팬츠", .bottom, .other, "cropped_pants"),
            ("스포츠/레저 > 하의 > 레깅스", "포켓 로고 3.5 바이커 쇼츠", .bottom, .leggings, "short_leggings"),
            ("스포츠/레저 > 하의 > 레깅스", "익스트림 프로 4.5부 레깅스", .bottom, .leggings, "short_leggings"),
            ("스포츠/레저 > 하의 > 레깅스", "무브먼트 하프 타이즈", .bottom, .leggings, "short_leggings"),
            ("스포츠/레저 > 하의 > 레깅스", "패스트 드라이 핏 러닝 하프 타이츠", .bottom, .leggings, "short_leggings"),
            ("스포츠/레저 > 하의 > 레깅스", "사이드 셔링 카프리팬츠", .bottom, .leggings, "three_quarter_leggings"),
            ("스포츠/레저 > 하의 > 레깅스", "컬러 블록 부츠컷 레깅스 팬츠", .bottom, .leggings, "long_leggings"),
            ("팬츠 > 캐주얼 팬츠 > 큐롯", "코듀로이큐롯", .bottom, .other, "shorts")
        ]

        for fixture in fixtures {
            let result = try #require(ParsedClosetClassification.resolve(
                category: fixture.2,
                detailCategory: fixture.3,
                sourceDepths: fixture.0.components(separatedBy: " > ").map(Optional.some),
                sourcePath: fixture.0,
                productName: fixture.1
            ))
            #expect(result.detailCode == fixture.4, "\(fixture.1)의 길이 분류가 잘못됐습니다.")
        }
    }

    @Test func explicitOuterwearNameRefinesOnlyCompatibleProviderMajor() throws {
        let coachJacket = try #require(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .shortSleeve,
            sourceDepths: ["티셔츠 & UT", "티셔츠 (반팔 & 긴팔)", "그래픽 티셔츠", nil],
            sourcePath: "티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 그래픽 티셔츠",
            productName: "KIDS PEANUTS코치재킷"
        ))
        #expect(coachJacket.categoryCode == "tops")
        #expect(coachJacket.detailCode == "short_sleeve")
        #expect(coachJacket.garmentFamily == .tshirt)

        let tailoredJacket = try #require(ParsedClosetClassification.resolve(
            category: .outer,
            detailCategory: .jacket,
            sourceDepths: ["아우터", "재킷 & 코트", "캐주얼 재킷", nil],
            sourcePath: "아우터 > 재킷 & 코트 > 캐주얼 재킷",
            productName: "테일러드재킷(릴랙스핏)"
        ))
        #expect(tailoredJacket.categoryCode == "outerwear")
        #expect(tailoredJacket.detailCode == "blazer")
    }

    @Test func productNameRefinesOuterwearWithoutTurningFleeceTopsIntoOuterwear() throws {
        let fixtures: [(String, String, ClothingCategory, String, String)] = [
            ("상의 > 맨투맨/스웨트", "라이트 플리스 로고 크루넥 맨투맨", .top, "tops", "sweatshirt"),
            ("상의 > 후드 티셔츠", "OVER FIT FLEECE-LINED HOODIE", .top, "tops", "hoodie"),
            ("아우터 > 환절기 코트", "Point Half Trench Coat", .outer, "outerwear", "trench_coat"),
            ("아우터 > 환절기 코트", "하이넥 사파리 하프 자켓", .outer, "outerwear", "jacket"),
            ("아우터 > 겨울 기타 코트", "포카포카 코듀로이 뽀글이 자켓", .outer, "outerwear", "fleece"),
            ("아우터 > 겨울 기타 코트", "OVERFIT HALF LEATHER MUSTANG", .outer, "outerwear", "mouton"),
            ("아우터 > 파카 & 블루종 > UNIQLO and JW ANDERSON", "패디드유틸리티쇼트재킷", .outer, "outerwear", "padding"),
            ("아우터 > 나일론/코치 재킷", "Ray Yacht Parka Carrot", .outer, "outerwear", "windbreaker"),
            ("아우터 > 겨울 기타 코트", "울 블렌드 오버 숄더 블레이저 코트", .outer, "outerwear", "coat")
        ]

        for fixture in fixtures {
            let result = try #require(ParsedClosetClassification.resolve(
                category: fixture.2,
                detailCategory: .other,
                sourceDepths: fixture.0.components(separatedBy: " > ").map(Optional.some),
                sourcePath: fixture.0,
                productName: fixture.1
            ))
            #expect(result.categoryCode == fixture.3, "\(fixture.1)의 대분류가 잘못됐습니다.")
            #expect(result.detailCode == fixture.4, "\(fixture.1)의 세부 분류가 잘못됐습니다.")
        }
    }

    @Test func ambiguousUniqloTShirtPathUsesStrongProductFamily() throws {
        let sourcePath = "티셔츠 & UT > 티셔츠 (반팔 & 긴팔) > 그래픽 티셔츠"
        let sweatshirtClassification = try #require(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .shortSleeve,
            sourceDepths: sourcePath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: sourcePath,
            productName: "GIRLS CHIIKAWA스웨트셔츠C"
        ))
        let hoodieClassification = try #require(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .shortSleeve,
            sourceDepths: sourcePath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: sourcePath,
            productName: "KIDS Mario Kart World스웨트후디D"
        ))

        #expect(sweatshirtClassification.detailCode == "sweatshirt")
        #expect(sweatshirtClassification.garmentFamily == .sweatshirt)
        #expect(hoodieClassification.detailCode == "hoodie")
        #expect(hoodieClassification.garmentFamily == .hoodie)

        let product = Product(
            name: "GIRLS CHIIKAWA스웨트셔츠C",
            category: .top,
            metadata: ProductMetadata(sourceCategoryPath: sourcePath, genderCodes: ["KIDS"]),
            sourceName: "유니클로 공식몰",
            sizes: [ProductSize(
                name: "130",
                measurements: GarmentMeasurements(shoulder: 35, chest: 41, totalLength: 48, sleeveLength: 43)
            )]
        )
        let graphicTee = UserFit(
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            sourceCategoryPath: sourcePath,
            brandName: "유니클로",
            gender: .kids,
            productName: "GIRLS CHIIKAWA UT(그래픽T)B",
            category: .top,
            detailCategory: .other,
            sizeName: "130",
            measurements: GarmentMeasurements(shoulder: 34, chest: 40, totalLength: 47, sleeveLength: 18),
            fitMemo: "",
            satisfaction: 3
        )
        let match = ComparisonProfileMatcher().match(
            product: product,
            productDetailCategory: .other,
            userFits: [graphicTee]
        )

        #expect(match.incomingProfile.garmentFamily == .sweatshirt)
        #expect(match.state == .noCompatibleGarment)
        #expect(match.compatibleCandidates.isEmpty)
    }

    @Test func explicitProviderPoloFamilyWinsOverConflictingKnitName() {
        let sourcePath = "상의 > 피케/카라 티셔츠"
        let classification = ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .shirt,
            sourceDepths: ["상의", "피케/카라 티셔츠"],
            sourcePath: sourcePath,
            productName: "썸머 쿨 터치 카라 반팔 니트 [그레이]"
        )
        let product = Product(
            name: "썸머 쿨 터치 카라 반팔 니트 [그레이]",
            category: .top,
            metadata: ProductMetadata(sourceCategoryPath: sourcePath, genderCodes: ["MEN"]),
            sourceName: "무신사",
            sizes: [ProductSize(
                name: "L",
                measurements: GarmentMeasurements(
                    shoulder: 47, chest: 55, totalLength: 68, sleeveLength: 24
                )
            )]
        )
        let poloShirt = UserFit(
            sourceType: .marketplace,
            sourceName: "무신사",
            sourceCategoryPath: sourcePath,
            brandName: "테스트",
            gender: .men,
            productName: "로고 코튼 피케 폴로셔츠",
            category: .top,
            detailCategory: .shortSleeve,
            sizeName: "L",
            measurements: GarmentMeasurements(
                shoulder: 47, chest: 55, totalLength: 68, sleeveLength: 24
            ),
            fitMemo: "",
            satisfaction: 3
        )

        let matcher = ComparisonProfileMatcher()
        let match = matcher.match(
            product: product,
            productDetailCategory: .shortSleeve,
            userFits: [poloShirt]
        )

        #expect(match.incomingProfile.garmentFamily == .tshirt)
        #expect(matcher.profile(for: poloShirt).garmentFamily == .tshirt)
        #expect(classification?.detailCode == "polo_shirt")
        #expect(classification?.detailCategory == .poloShirt)
        #expect(classification?.lengthType == .short)
        #expect(match.state == .compatible)
        #expect(match.compatibleCandidates.map(\.id) == [poloShirt.id])
    }

    @Test func uniqloSweatFullZipParkaUsesOuterwearJumper() throws {
        let parser = UniqloProductMetadataParser()
        let sourcePath = "티셔츠 & UT > 스웨트셔츠 & 후드티 > 스웨트파카"
        let productName = "KIDS드라이스웨트풀집파카(컬러블록)"
        let classification = try #require(ParsedClosetClassification.resolve(
            category: parser.mapCategory(from: sourcePath),
            detailCategory: parser.mapDetailCategory(from: "\(sourcePath) \(productName)"),
            sourceDepths: sourcePath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: sourcePath,
            productName: productName
        ))
        #expect(classification.category == .outer)
        #expect(classification.detailCategory == .jumper)
        #expect(classification.garmentFamily == .outerwear)
    }

    @Test func explicitCardiganNameUsesCardiganStructureAcrossProviderBuckets() throws {
        let parser = UniqloProductMetadataParser()

        let cardiganPath = "니트 & 가디건 > 가디건 > 스무드 코튼"
        let cardiganName = "포인텔가디건(긴팔)"
        let explicitCardigan = try #require(ParsedClosetClassification.resolve(
            category: parser.mapCategory(from: "\(cardiganPath) \(cardiganName)"),
            detailCategory: parser.mapDetailCategory(from: "\(cardiganPath) \(cardiganName)"),
            sourceDepths: cardiganPath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: cardiganPath,
            productName: cardiganName
        ))
        #expect(explicitCardigan.categoryCode == "outerwear")
        #expect(explicitCardigan.detailCode == "cardigan")
        #expect(explicitCardigan.garmentFamily == .knitCardigan)

        let officialTopPath = "상의 > 니트/스웨터"
        let officialTopName = "여성 브이넥 케이블 반팔 니트 가디건"
        let officialTop = try #require(ParsedClosetClassification.resolve(
            category: parser.mapCategory(from: officialTopPath),
            detailCategory: parser.mapDetailCategory(from: "\(officialTopPath) \(officialTopName)"),
            sourceDepths: officialTopPath.components(separatedBy: " > ").map(Optional.some),
            sourcePath: officialTopPath,
            productName: officialTopName
        ))
        #expect(officialTop.categoryCode == "outerwear")
        #expect(officialTop.detailCode == "cardigan")
        #expect(officialTop.garmentFamily == .knitCardigan)
    }

    @Test func explicitHalfSleeveUsesShortSleeveDetail() throws {
        for productName in [
            "카울넥 하프 슬리브 카라티 블랙",
            "ROUND COLLAR SHIRRING S/S TEE(STRIPE RED)",
            "Cap sleeve V-neck knit"
        ] {
            let result = try #require(ParsedClosetClassification.resolve(
                category: .top,
                detailCategory: .other,
                sourceDepths: ["상의", "피케/카라 티셔츠", nil, nil],
                sourcePath: "상의 > 피케/카라 티셔츠",
                productName: productName
            ))
            #expect(result.detailCode == "polo_shirt", "\(productName)의 폴로셔츠 분류가 누락됐습니다.")
            #expect(result.lengthType == .short, "\(productName)의 길이 코드가 누락됐습니다.")
        }

        let seasonal = try #require(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .other,
            sourceDepths: ["상의", "니트/스웨터", nil, nil],
            sourcePath: "상의 > 니트/스웨터",
            productName: "26 S/S 워셔블 니트"
        ))
        #expect(seasonal.detailCode == "knit_top")
    }

    @Test func musinsaSourcePriorityAndGenericTopFallbackAreDeterministic() throws {
        let sweater = try #require(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .other,
            sourceDepths: ["상의", "기타 상의", nil, nil],
            sourcePath: "상의 > 기타 상의",
            productName: "토털 룩 재스퍼 니트 스웨터"
        ))
        #expect(sweater.detailCode == "knit_top")
        #expect(sweater.garmentFamily == .knitCardigan)

        let ambiguous = ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .other,
            sourceDepths: ["스포츠/레저", "상의", "기타상의", nil],
            sourcePath: "스포츠/레저 > 상의 > 기타상의",
            productName: "멘즈 롱-슬리브드 R0 탑 / 86141R5"
        )
        #expect(ambiguous == nil)

        let providerPolo = try #require(ParsedClosetClassification.resolve(
            category: .shirt,
            detailCategory: .other,
            sourceDepths: ["스포츠/레저", "상의", "피케/카라 티셔츠", nil],
            sourcePath: "스포츠/레저 > 상의 > 피케/카라 티셔츠",
            productName: "컨트리 커버업"
        ))
        #expect(providerPolo.detailCode == "polo_shirt")
        #expect(providerPolo.garmentFamily == .tshirt)
    }

    @Test func explicitThreeQuarterFractionUsesThreeQuarterSleeveDetail() throws {
        let result = try #require(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .longSleeve,
            sourceDepths: ["상의", "후드 티셔츠", nil, nil],
            sourcePath: "상의 > 후드 티셔츠",
            productName: "3/4 LAYERED CONTRAST HOODIE (DUST BLUE)"
        ))

        #expect(result.detailCode == "three_quarter_sleeve")
        #expect(result.lengthType == .threeQuarter)
    }

    @Test func explicitLengthOverridesConflictingCanonicalSourcePathLength() {
        let fixtures: [(String, ClosetDetailCategory, ComparisonLengthType)] = [
            ("Pleated Boat Neck Short Sleeve T-Shirt", .shortSleeve, .short),
            ("레이어드 롱슬리브리스 세트", .sleeveless, .sleeveless),
            ("Reversible 3/4 Sleeve Tee", .threeQuarterSleeve, .threeQuarter),
        ]
        let matcher = ComparisonProfileMatcher()

        for (name, detail, expectedLength) in fixtures {
            let classification = ParsedClosetClassification.resolve(
                category: .top,
                detailCategory: detail,
                sourceDepths: ["상의", "긴소매 티셔츠", nil, nil],
                sourcePath: "상의 > 긴소매 티셔츠",
                productName: name
            )
            let product = Product(
                name: name,
                category: .top,
                metadata: ProductMetadata(sourceCategoryPath: "상의 > 긴소매 티셔츠"),
                sourceName: "무신사",
                sizes: [ProductSize(
                    name: "M",
                    measurements: GarmentMeasurements(
                        shoulder: 40, chest: 50, totalLength: 65, sleeveLength: 60
                    )
                )]
            )
            product.sleeveType = classification?.lengthType ?? .unknown

            #expect(
                matcher.profile(for: product, detailCategory: detail).lengthType == expectedLength,
                "\(name)의 구체적인 길이 정보가 상위 카테고리 길이보다 우선해야 합니다."
            )
        }

        let croppedLongSleeve = ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .longSleeve,
            sourceDepths: ["상의", "긴소매 티셔츠", nil, nil],
            sourcePath: "상의 > 긴소매 티셔츠",
            productName: "와플 크롭 헨리넥 티셔츠"
        )
        #expect(croppedLongSleeve?.lengthType == .long)
    }

    @Test func skirtAndDressLengthConflictsDoNotAutoMatch() {
        let longSkirt = Product(
            name: "플레어롱스커트",
            category: .bottom,
            metadata: ProductMetadata(sourceCategoryPath: "원피스 & 스커트 > 스커트 > 롱 (맥시)"),
            sizes: [ProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 0, chest: 0, totalLength: 90, sleeveLength: 0,
                    waist: 36, hip: 50, thigh: 0
                )
            )]
        )
        let miniSkort = UserFit(
            brandName: "테스트",
            productName: "플리츠미니스코츠",
            category: .bottom,
            detailCategory: .skirt,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 0, chest: 0, totalLength: 38, sleeveLength: 0,
                waist: 35, hip: 49, thigh: 0
            ),
            fitMemo: "",
            satisfaction: 3
        )
        let sleevelessDress = Product(
            name: "GIRLS셔링원피스(슬리브리스)",
            category: .dress,
            sizes: [ProductSize(
                name: "130",
                measurements: GarmentMeasurements(shoulder: 30, chest: 38, totalLength: 70, sleeveLength: 0)
            )]
        )
        let shortSleeveDress = UserFit(
            brandName: "테스트",
            productName: "GIRLS프릴원피스(반팔)",
            category: .dress,
            detailCategory: .onePiece,
            sizeName: "130",
            measurements: GarmentMeasurements(shoulder: 30, chest: 38, totalLength: 70, sleeveLength: 15),
            fitMemo: "",
            satisfaction: 3
        )
        let matcher = ComparisonProfileMatcher()
        let skirtResult = matcher.match(
            product: longSkirt,
            productDetailCategory: .skirt,
            userFits: [miniSkort]
        )
        let dressResult = matcher.match(
            product: sleevelessDress,
            productDetailCategory: .onePiece,
            userFits: [shortSleeveDress]
        )

        #expect(skirtResult.incomingProfile.lengthType == .long)
        #expect(matcher.profile(for: miniSkort).lengthType == .short)
        #expect(skirtResult.state == .sameFamilyLengthConflict)
        #expect(dressResult.incomingProfile.lengthType == .sleeveless)
        #expect(matcher.profile(for: shortSleeveDress).lengthType == .short)
        #expect(dressResult.state == .sameFamilyLengthConflict)
    }

    @Test func outerwearBodyLengthPreventsLongAndShortGarmentPairing() {
        let longCoat = Product(
            name: "울 맥시 숄 코트",
            category: .outer,
            sizes: [ProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 48, chest: 60, totalLength: 127, sleeveLength: 61
                )
            )]
        )
        let halfCoat = UserFit(
            brandName: "테스트",
            productName: "울 부클 하프 코트",
            category: .outer,
            detailCategory: .coat,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 47, chest: 59, totalLength: 77, sleeveLength: 60
            ),
            fitMemo: "half",
            satisfaction: 3
        )
        let measuredLongCoat = UserFit(
            brandName: "테스트",
            productName: "캐시미어 발마칸 코트",
            category: .outer,
            detailCategory: .coat,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 47, chest: 59, totalLength: 115, sleeveLength: 60
            ),
            fitMemo: "long",
            satisfaction: 3
        )
        let matcher = ComparisonProfileMatcher()
        let conflict = matcher.match(
            product: longCoat,
            productDetailCategory: .coat,
            userFits: [halfCoat]
        )
        let compatible = matcher.match(
            product: longCoat,
            productDetailCategory: .coat,
            userFits: [halfCoat, measuredLongCoat]
        )
        let shortTrench = Product(
            name: "하이넥 숏 트렌치 코트",
            category: .outer,
            sizes: [ProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 47, chest: 58, totalLength: 72, sleeveLength: 60
                )
            )]
        )
        let halfTrench = UserFit(
            brandName: "테스트",
            productName: "Linen Blend High-neck Half Trench Coat",
            category: .outer,
            detailCategory: .trenchCoat,
            sizeName: "M",
            measurements: GarmentMeasurements(
                shoulder: 47, chest: 58, totalLength: 73, sleeveLength: 60
            ),
            fitMemo: "half-trench",
            satisfaction: 3
        )
        let trenchConflict = matcher.match(
            product: shortTrench,
            productDetailCategory: .trenchCoat,
            userFits: [halfTrench]
        )

        #expect(conflict.incomingProfile.bodyLengthType == .long)
        #expect(matcher.profile(for: halfCoat).bodyLengthType == .threeQuarter)
        #expect(conflict.state == .sameFamilyLengthConflict)
        #expect(compatible.compatibleCandidates.map(\.fitMemo) == ["long"])
        #expect(trenchConflict.incomingProfile.bodyLengthType == .short)
        #expect(matcher.profile(for: halfTrench).bodyLengthType == .threeQuarter)
        #expect(trenchConflict.state == .sameFamilyLengthConflict)
        #expect(matcher.manualCandidates(
            product: longCoat,
            productDetailCategory: .coat,
            userFits: [halfCoat]
        ).map(\.id) == [halfCoat.id])
    }

    @Test func brownBottomNamesDoNotBecomeBras() throws {
        for name in [
            "카펜터 버뮤다 밴딩 팬츠 브라운",
            "원턱 8부 썬스턴 버뮤다 카고팬츠 브라운"
        ] {
            let result = try #require(ParsedClosetClassification.resolve(
                category: .bottom,
                detailCategory: .shorts,
                sourceDepths: ["바지", "숏 팬츠", nil, nil],
                sourcePath: "바지 > 숏 팬츠",
                productName: name
            ))
            #expect(result.categoryCode == "bottoms")
            #expect(result.detailCode == "shorts")
        }
    }

    @Test func briefLinedRunningBottomsDoNotBecomeUnderwear() throws {
        for fixture in [
            ("프로 드라이 핏 브리프 쇼츠", "스포츠/레저 > 하의 > 숏 팬츠", "shorts"),
            ("Brief Lined Running Tights", "스포츠/레저 > 하의 > 숏 레깅스", "short_leggings")
        ] {
            let result = try #require(ParsedClosetClassification.resolve(
                category: .bottom,
                detailCategory: .other,
                sourceDepths: fixture.1.components(separatedBy: " > ").map(Optional.some),
                sourcePath: fixture.1,
                productName: fixture.0
            ))
            #expect(result.categoryCode != "underwear")
            #expect(result.detailCode == fixture.2)
        }
    }

    @Test func explicitShirtAndBlouseStructureWinsOverSleeveLength() throws {
        for fixture in [
            ("옥스포드쇼트셔츠(반팔)", "shirt"),
            ("볼륨슬리브블라우스(긴팔)", "blouse")
        ] {
            let result = try #require(ParsedClosetClassification.resolve(
                category: .top,
                detailCategory: .other,
                sourceDepths: ["상의", "셔츠/블라우스"],
                sourcePath: "상의 > 셔츠/블라우스",
                productName: fixture.0
            ))
            #expect(result.detailCode == fixture.1)
            #expect(result.garmentFamily == .shirt)
        }
    }

    @Test func compositeAndOptionDependentGarmentsRequireConfirmation() {
        for name in [
            "[SET] T-shirt + Shorts",
            "탑 가디건 세트",
            "민소매/반팔 2종",
            "나시 레이어드 반팔티",
            "[나시 선택] 반팔 셔츠"
        ] {
            let result = ParsedClosetClassification.resolve(
                category: .top,
                detailCategory: .other,
                sourceDepths: ["상의", "기타 상의"],
                sourcePath: "상의 > 기타 상의",
                productName: name
            )
            #expect(result == nil, "\(name)은 단일 의류로 자동 확정하면 안 됩니다.")
        }
    }

    @Test func hyphenatedSleeveNamesResolveLength() throws {
        for fixture in [("Short-Sleeve Shirt", "shirt", ComparisonLengthType.short),
                        ("Long-Sleeve Blouse", "blouse", ComparisonLengthType.long)] {
            let result = try #require(ParsedClosetClassification.resolve(
                category: .top,
                detailCategory: .other,
                sourceDepths: ["상의", "셔츠/블라우스"],
                sourcePath: "상의 > 셔츠/블라우스",
                productName: fixture.0
            ))
            #expect(result.detailCode == fixture.1)
            #expect(result.lengthType == fixture.2)
        }
    }

    @Test func explicitLeggingsAndCoachJacketOverrideWrongProviderBuckets() throws {
        let leggings = try #require(ParsedClosetClassification.resolve(
            category: .underwear,
            detailCategory: .underwear,
            sourceDepths: ["이너웨어", "히트텍"],
            sourcePath: "이너웨어 > 히트텍",
            productName: "히트텍울트라웜레깅스"
        ))
        #expect(leggings.categoryCode == "leggings")
        #expect(leggings.garmentFamily == .leggings)

        let coachJacket = try #require(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .shortSleeve,
            sourceDepths: ["티셔츠 & UT", "UT 그래픽 티셔츠"],
            sourcePath: "티셔츠 & UT > UT 그래픽 티셔츠",
            productName: "KIDS PEANUTS코치재킷"
        ))
        #expect(coachJacket.categoryCode == "outerwear")
        #expect(coachJacket.detailCode == "jacket")
        #expect(coachJacket.garmentFamily == .outerwear)
    }

    @Test func skortsResolveAsSkirts() throws {
        for fixture in [
            ("GIRLS데님미니스코츠", "팬츠 > 쇼트 팬츠(반바지) > 스코츠"),
            ("플리츠스코츠", "원피스 & 스커트 > 스커트 > 스코츠")
        ] {
            let result = try #require(ParsedClosetClassification.resolve(
                category: .bottom,
                detailCategory: .shortPants,
                sourceDepths: fixture.1.components(separatedBy: " > ").map(Optional.some),
                sourcePath: fixture.1,
                productName: fixture.0
            ))
            #expect(result.categoryCode == "skirts")
            #expect(result.detailCode == "skirt")
            #expect(result.garmentFamily == .skirt)
        }
    }

    @Test func explicitManualComparisonOpensForMaxiCoatAndHalfOuterwear() {
        let maxiCoat = UserFit(
            sourceType: .marketplace,
            sourceName: "무신사",
            sourceCategoryPath: "아우터 > 겨울 기타 코트",
            brandName: "제로스트릿",
            gender: .women,
            productName: "[2컬러] 르제로 울 맥시 숄 코트",
            category: .outer,
            detailCategory: .coat,
            sizeName: "FREE",
            measurements: GarmentMeasurements(
                shoulder: 52, chest: 61, totalLength: 127, sleeveLength: 50
            ),
            fitMemo: "5782783",
            satisfaction: 3
        )
        let halfOuterwear: [(Product, ClosetDetailCategory)] = [
            (Product(
                name: "하이넥 사파리 하프 자켓 [LIGHT KHAKI] / WBE3L09504",
                category: .outer,
                productCode: "5380617",
                metadata: ProductMetadata(sourceCategoryPath: "아우터 > 환절기 코트"),
                sourceName: "무신사",
                sizes: [ProductSize(
                    name: "M",
                    measurements: GarmentMeasurements(
                        shoulder: 69, chest: 0, totalLength: 81, sleeveLength: 56
                    )
                )]
            ), .jacket),
            (Product(
                name: "(CT-1472)OVERFIT HALF LEATHER MUSTANG",
                category: .outer,
                productCode: "5635659",
                metadata: ProductMetadata(sourceCategoryPath: "아우터 > 겨울 기타 코트"),
                sourceName: "무신사",
                sizes: [ProductSize(
                    name: "FREE",
                    measurements: GarmentMeasurements(
                        shoulder: 53.3, chest: 0, totalLength: 85.7, sleeveLength: 61
                    )
                )]
            ), .mouton)
        ]
        let matcher = ComparisonProfileMatcher()
        let service = RecommendationService()

        for (product, detail) in halfOuterwear {
            let automatic = matcher.match(
                product: product,
                productDetailCategory: detail,
                userFits: [maxiCoat]
            )
            #expect(automatic.compatibleCandidates.isEmpty)
            #expect(matcher.manualCandidates(
                product: product,
                productDetailCategory: detail,
                userFits: [maxiCoat]
            ).map(\.id) == [maxiCoat.id])
            #expect(service.comparisonCompatibility(
                product: product,
                productDetailCategory: detail,
                item: maxiCoat
            ).level == .extended)
        }
    }

    @Test func uniqloGenericPathsUseProductNameForHoodiesAndShortPants() throws {
        let fixtures: [(String, String, ClothingCategory, String)] = [
            ("영유아(6개월~5세) > 아우터 > UV Protection", "BT UV PROTECTION메쉬후디(긴팔)", .outer, "jumper"),
            ("Special Collaborations > Uniqlo U > Bottoms", "턱와이드쇼트팬츠", .bottom, "shorts"),
            ("스포츠 유틸리티 웨어 > 아우터 > 풀집 후디", "울트라스트레치AIRism UV PROTECTION풀집후디", .outer, "jumper"),
            ("팬츠 > 조거팬츠", "W울트라스트레치AIRism조거팬츠", .bottom, "long_pants")
        ]

        for fixture in fixtures {
            let result = try #require(ParsedClosetClassification.resolve(
                category: fixture.2,
                detailCategory: .other,
                sourceDepths: fixture.0.components(separatedBy: " > ").map(Optional.some),
                sourcePath: fixture.0,
                productName: fixture.1
            ))
            #expect(result.detailCode == fixture.3, "\(fixture.1)의 세부 분류가 잘못됐습니다.")
        }
    }

    @Test func uniqloThirdCorpusUsesOfficialCutAndSewnAndLoungewearFamilies() throws {
        let cutAndSewn = try #require(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .other,
            sourceDepths: ["Special Collaborations", "UNIQLO and JW ANDERSON", "Cut & Sewn", nil],
            sourcePath: "Special Collaborations > UNIQLO and JW ANDERSON > Cut & Sewn",
            productName: "바이컬러T"
        ))
        #expect(cutAndSewn.categoryCode == "tops")
        #expect(cutAndSewn.detailCode == "short_sleeve")
        #expect(cutAndSewn.isValid)

        let loungewear = try #require(ParsedClosetClassification.resolve(
            category: .other,
            detailCategory: .loungewear,
            sourceDepths: ["라운지 & 언더웨어 컬렉션", "Effortless Charm", "저스트 웨이스트", nil],
            sourcePath: "라운지 & 언더웨어 컬렉션 > Effortless Charm > 저스트 웨이스트",
            productName: "코튼저지쇼츠(저스트웨이스트)플라워C"
        ))
        #expect(loungewear.categoryCode == "homewear")
        #expect(loungewear.detailCode == "loungewear")
        #expect(loungewear.isValid)
    }

    @Test func storedMusinsaFourthCorpusActualSizesPassProductionParser() throws {
        guard let root = ProcessInfo.processInfo.environment["FITMATCH_MUSINSA_SIZE_CORPUS_DIR"] else {
            return
        }
        let directory = URL(fileURLWithPath: root).appendingPathComponent("raw/musinsa/actual_size")
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        #expect(files.count == 320)

        let parser = MusinsaActualSizeAPIParser()
        var parsedProducts = 0
        var parsedSizeRows = 0
        for file in files {
            let result = try parser.parseActualSize(from: Data(contentsOf: file))
            if !result.sizes.isEmpty { parsedProducts += 1 }
            parsedSizeRows += result.sizes.count
        }
        #expect(parsedProducts >= 300)
        #expect(parsedSizeRows >= 900)
    }

    @Test func storedLargeCorpusExportsProductionClassification() throws {
        var output: [[String: Any]] = []
        var unclassified: [[String: Any]] = []
        var productKeys = Set<String>()
        let uniqloParser = UniqloProductMetadataParser()
        let bundle = Bundle(for: FitMatchCorpusBundleToken.self)
        let resources = [
            "LegacyMixed320ClassificationInputs",
            "LegacyUniqloRetest320ClassificationInputs",
            "LegacyUniqloThird320ClassificationInputs",
            "LegacyMusinsaFourth320ClassificationInputs",
            "Musinsa1037ClassificationInputs",
            "Uniqlo243ClassificationInputs",
        ]
        for resource in resources {
            let inputURL = try #require(bundle.url(forResource: resource, withExtension: "json"))
            let inputs = try #require(
                try JSONSerialization.jsonObject(with: Data(contentsOf: inputURL)) as? [[String: Any]]
            )
            for input in inputs {
                let source = try #require(input["source"] as? String)
                let productID = try #require(input["product_id"] as? String)
                let name = try #require(input["product_name"] as? String)
                let sourcePath = try #require(input["source_path"] as? String)
                let depths = sourcePath.components(separatedBy: ">").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                let providerCategory: ClothingCategory
                let providerDetail: ClosetDetailCategory
                if source == "musinsa" {
                    providerCategory = MusinsaProductMetadataParser.mapCategory(from: sourcePath)
                    providerDetail = MusinsaProductMetadataParser.mapDetailCategory(
                        from: depths.count > 1 ? depths[1] : sourcePath
                    )
                } else {
                    providerCategory = uniqloParser.mapCategory(from: "\(sourcePath) \(name)")
                    providerDetail = uniqloParser.mapDetailCategory(from: "\(sourcePath) \(name)")
                }
                let classification = ParsedClosetClassification.resolve(
                    category: providerCategory, detailCategory: providerDetail,
                    sourceDepths: depths.map(Optional.some), sourcePath: sourcePath,
                    productName: name
                )
                let productKey = "\(source):\(productID)"
                productKeys.insert(productKey)
                if let classification {
                    output.append([
                        "source": source, "product_id": productID, "product_name": name,
                        "source_path": sourcePath, "category_code": classification.categoryCode,
                        "detail_code": classification.detailCode, "is_valid": classification.isValid
                    ])
                    #expect(classification.detailCode != "other_tops")
                } else {
                    output.append([
                        "source": source, "product_id": productID, "product_name": name,
                        "source_path": sourcePath, "category_code": NSNull(),
                        "detail_code": NSNull(), "is_valid": false
                    ])
                    unclassified.append([
                        "source": source,
                        "product_id": productID,
                        "product_name": name,
                        "source_path": sourcePath,
                        "provider_category": providerCategory.rawValue,
                        "provider_detail": providerDetail.rawValue,
                        "reason": "현재 공식 카테고리·상품명 정보만으로 FitMatch 세부 카테고리를 확정할 수 없음"
                    ])
                }
            }
        }

        #expect(output.count == 2560)
        #expect(productKeys.count == 2560)
        let encoded = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        let documentDirectory = try #require(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        )
        let outputURL = documentDirectory.appendingPathComponent("fitmatch-cumulative-2560-swift-classification.json")
        try encoded.write(to: outputURL, options: .atomic)
        let unclassifiedData = try JSONSerialization.data(
            withJSONObject: unclassified,
            options: [.prettyPrinted, .sortedKeys]
        )
        let unclassifiedURL = documentDirectory.appendingPathComponent("fitmatch-unclassified-2560.json")
        try unclassifiedData.write(to: unclassifiedURL, options: .atomic)
        print("FITMATCH_2560_RESULT total=\(output.count) classified=\(output.count - unclassified.count) unclassified=\(unclassified.count)")
        print("FITMATCH_2560_UNCLASSIFIED_PATH \(unclassifiedURL.path)")
    }

    @Test(.enabled(
        if: runsFitPairCorpusAudit,
        "1,037건 Musinsa corpus 검증은 독립 프로세스로 실행합니다."
    ))
    func storedMusinsaCorpusBuildsActualMeasurementFitPairs() throws {
        struct Specimen {
            let productID: String
            let productName: String
            let category: ClothingCategory
            let detail: ClosetDetailCategory
            let length: ComparisonLengthType
            let gender: UserGender
            let sourcePath: String
            let size: ParsedProductSize
        }

        let bundle = Bundle(for: FitMatchCorpusBundleToken.self)
        let inputURL = try #require(bundle.url(
            forResource: "Musinsa1037FitPairInputs", withExtension: "json"
        ))
        let inputs = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: inputURL)) as? [[String: Any]]
        )
        #expect(inputs.count == 1037)

        let parser = MusinsaActualSizeAPIParser()
        var specimens: [Specimen] = []
        var sourceProductsWithRows = 0
        var selectionRequiredWithRows = 0
        var parsedSizeRows = 0
        for input in inputs {
            let productID = try #require(input["product_id"] as? String)
            let productName = try #require(input["product_name"] as? String)
            let sourcePath = try #require(input["source_path"] as? String)
            let genderCodes = input["gender_codes"] as? [String] ?? []
            let response = try #require(input["response"])
            let depths = sourcePath.components(separatedBy: ">").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            let providerCategory = MusinsaProductMetadataParser.mapCategory(from: sourcePath)
            let providerDetail = MusinsaProductMetadataParser.mapDetailCategory(
                from: depths.count > 1 ? depths[1] : sourcePath
            )
            let data = try JSONSerialization.data(withJSONObject: response)
            let parsed = try parser.parseActualSize(
                from: data,
                isTopCategory: providerCategory.serviceGroup == .top
            )
            if !parsed.sizes.isEmpty { sourceProductsWithRows += 1 }
            guard let classification = ParsedClosetClassification.resolve(
                category: providerCategory,
                detailCategory: providerDetail,
                sourceDepths: depths.map(Optional.some),
                sourcePath: sourcePath,
                productName: productName
            ) else {
                if !parsed.sizes.isEmpty { selectionRequiredWithRows += 1 }
                continue
            }
            let category = ClothingCategory.fromTaxonomyCode(classification.categoryCode)
            let detail = ClosetDetailCategory.fromTaxonomyCode(classification.detailCode)
            let validSizes = ParsedSizeValidator.validSizes(parsed.sizes, category: category)
            parsedSizeRows += validSizes.count
            guard !validSizes.isEmpty else { continue }
            specimens.append(Specimen(
                productID: productID,
                productName: productName,
                category: category,
                detail: detail,
                length: classification.lengthType,
                gender: UserGender.productTarget(from: genderCodes),
                sourcePath: sourcePath,
                size: validSizes[validSizes.count / 2]
            ))
        }

        var products: [String: Product] = [:]
        var references: [String: UserFit] = [:]
        for specimen in specimens {
            let size = ParsedProductSizeNormalizer.makeProductSizes(from: [specimen.size])[0]
            let product = Product(
                name: specimen.productName,
                category: specimen.category,
                productCode: specimen.productID,
                sourceURLString: "https://www.musinsa.com/products/\(specimen.productID)",
                metadata: ProductMetadata(
                    sourceCategoryPath: specimen.sourcePath,
                    genderCodes: [specimen.gender.rawValue]
                ),
                sourceName: "무신사",
                sizes: [size]
            )
            product.sleeveType = specimen.length
            products[specimen.productID] = product
            let item = UserFit(
                sourceType: .marketplace,
                sourceName: "무신사",
                sourceCategoryPath: specimen.sourcePath,
                brandName: "검증 코퍼스",
                gender: specimen.gender,
                productName: specimen.productName,
                category: specimen.category,
                detailCategory: specimen.detail,
                sizeName: specimen.size.name,
                measurements: specimen.size.measurements,
                fitMemo: specimen.productID,
                satisfaction: 3
            )
            item.sleeveType = specimen.length
            item.measurementRecords = specimen.size.measurementRecords.map { $0.makeRecord(userFit: item) }
            references[specimen.productID] = item
        }

        var pairResults: [[String: Any]] = []
        var usedPairKeys = Set<String>()
        let matcher = ComparisonProfileMatcher()
        for specimen in specimens.sorted(by: { $0.productID < $1.productID }) {
            guard let productObject = products[specimen.productID],
                  let productSize = productObject.sizes.first else { continue }
            let candidatePool = references.filter { $0.key != specimen.productID }.map(\.value)
            let match = matcher.match(
                product: productObject,
                productDetailCategory: specimen.detail,
                userFits: candidatePool
            )
            guard let referenceItem = match.compatibleCandidates.first else { continue }
            let comparisonProfile = matcher.profile(for: productObject, detailCategory: specimen.detail)
            let referenceProfile = matcher.profile(for: referenceItem)
            let referenceID = referenceItem.fitMemo
            let pairKey = [specimen.productID, referenceID].sorted().joined(separator: "|")
            guard usedPairKeys.insert(pairKey).inserted else { continue }
                let result = MeasurementComparisonEngine().compare(
                    productSize: productSize,
                    referenceItem: referenceItem,
                    productCategory: specimen.category,
                    productDetailCategory: specimen.detail
                )
                pairResults.append([
                    "reference_product_id": referenceID,
                    "reference_product_name": referenceItem.productName,
                    "reference_size_name": referenceItem.sizeName,
                    "reference_source_path": referenceItem.sourceCategoryPath ?? "",
                    "reference_url": "https://www.musinsa.com/products/\(referenceID)",
                    "reference_category_code": referenceItem.category.serviceGroup.taxonomyCode,
                    "reference_detail_code": referenceItem.detailCategory.rawValue,
                    "reference_gender_code": referenceItem.resolvedGenderCode,
                    "reference_garment_family": referenceProfile.garmentFamily.rawValue,
                    "reference_construction_type": referenceProfile.constructionType.rawValue,
                    "reference_body_length_type": referenceProfile.bodyLengthType.rawValue,
                    "reference_length_type": referenceProfile.lengthType.rawValue,
                    "comparison_product_id": specimen.productID,
                    "comparison_product_name": specimen.productName,
                    "comparison_size_name": productSize.name,
                    "comparison_source_path": specimen.sourcePath,
                    "comparison_url": "https://www.musinsa.com/products/\(specimen.productID)",
                    "comparison_category_code": specimen.category.serviceGroup.taxonomyCode,
                    "comparison_detail_code": specimen.detail.rawValue,
                    "comparison_gender_code": specimen.gender.taxonomyCode,
                    "comparison_garment_family": comparisonProfile.garmentFamily.rawValue,
                    "comparison_construction_type": comparisonProfile.constructionType.rawValue,
                    "comparison_body_length_type": comparisonProfile.bodyLengthType.rawValue,
                    "comparison_length_type": comparisonProfile.lengthType.rawValue,
                    "category_code": specimen.category.serviceGroup.taxonomyCode,
                    "detail_code": specimen.detail.rawValue,
                    "status": result.status.rawValue,
                    "score": result.score,
                    "compared_item_count": result.comparedItems.count,
                    "coverage": result.comparisonCoverage,
                    "reliability": result.reliabilityTitle,
                    "exclusion_count": result.exclusions.count,
                    "exclusion_reasons": result.exclusions.map(\.reason.rawValue),
                    "minimum_comparable_count": result.minimumComparableCount,
                    "minimum_required_kind_count": result.minimumRequiredKindCount,
                    "required_kinds": result.requiredKinds.map(\.rawValue),
                    "required_all_kinds": result.requiredAllKinds.map(\.rawValue),
                    "compared_items": result.comparedItems.map { item in
                        [
                            "kind": item.kind.rawValue,
                            "measurement_code": item.measurementCode.rawValue,
                            "display_title": item.displayTitle ?? item.kind.title,
                            "reference_value_cm": item.referenceValue,
                            "comparison_value_cm": item.productValue,
                            "signed_difference_cm": item.signedDifference,
                            "absolute_difference_cm": item.absoluteDifference,
                            "item_score": item.score,
                            "weight": item.weight,
                        ] as [String: Any]
                    },
                    "exclusions": result.exclusions.map { exclusion in
                        [
                            "kind": exclusion.kind.rawValue,
                            "reason": exclusion.reason.rawValue,
                            "reference_code": exclusion.referenceCode?.rawValue ?? "",
                            "comparison_code": exclusion.productCode?.rawValue ?? "",
                        ]
                    },
                ])
        }

        #expect(sourceProductsWithRows == 914)
        #expect(specimens.count + selectionRequiredWithRows == sourceProductsWithRows)
        #expect(selectionRequiredWithRows <= 64)
        #expect(parsedSizeRows > 2000)
        #expect(pairResults.count >= 650)
        #expect(pairResults.filter { ($0["status"] as? String) == "confirmed" }.count
                >= pairResults.count - 2)
        #expect(pairResults.allSatisfy {
            ($0["comparison_category_code"] as? String) == ($0["reference_category_code"] as? String)
        })
        let allowedSimilarFamilies: Set<Set<String>> = [
            [ComparisonGarmentFamily.denim.rawValue, ComparisonGarmentFamily.pants.rawValue],
            [ComparisonGarmentFamily.tshirt.rawValue, ComparisonGarmentFamily.shirt.rawValue],
            [ComparisonGarmentFamily.sweatshirt.rawValue, ComparisonGarmentFamily.hoodie.rawValue],
            [ComparisonGarmentFamily.outerwear.rawValue, ComparisonGarmentFamily.hoodie.rawValue],
        ]
        #expect(pairResults.allSatisfy { pair in
            guard let comparisonFamily = pair["comparison_garment_family"] as? String,
                  let referenceFamily = pair["reference_garment_family"] as? String else { return false }
            return comparisonFamily == referenceFamily
                || allowedSimilarFamilies.contains([comparisonFamily, referenceFamily])
        })
        #expect(pairResults.allSatisfy { pair in
            guard (pair["comparison_garment_family"] as? String)
                    != (pair["reference_garment_family"] as? String) else { return true }
            return (pair["comparison_length_type"] as? String) != ComparisonLengthType.unknown.rawValue
                && (pair["comparison_length_type"] as? String)
                    == (pair["reference_length_type"] as? String)
        })
        #expect(pairResults.allSatisfy {
            ($0["category_code"] as? String) != "outerwear"
                || (($0["comparison_body_length_type"] as? String) != "unknown"
                    && ($0["comparison_body_length_type"] as? String)
                        == ($0["reference_body_length_type"] as? String))
        })
        let encoded = try JSONSerialization.data(
            withJSONObject: pairResults, options: [.prettyPrinted, .sortedKeys]
        )
        let outputURL = try #require(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ).appendingPathComponent("fitmatch-musinsa-actual-measurement-pairs.json")
        try encoded.write(to: outputURL, options: .atomic)
    }

    @Test func storedMusinsaCorpusExportsActualSizeAttritionDiagnostics() throws {
        let bundle = Bundle(for: FitMatchCorpusBundleToken.self)
        let inputURL = try #require(bundle.url(
            forResource: "Musinsa1037FitPairInputs", withExtension: "json"
        ))
        let inputs = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: inputURL)) as? [[String: Any]]
        )
        let parser = MusinsaActualSizeAPIParser()
        var diagnostics: [[String: Any]] = []

        for input in inputs {
            let productID = try #require(input["product_id"] as? String)
            let productName = try #require(input["product_name"] as? String)
            let categoryCode = try #require(input["category_code"] as? String)
            let detailCode = try #require(input["detail_code"] as? String)
            let sourcePath = try #require(input["source_path"] as? String)
            let response = try #require(input["response"] as? [String: Any])
            let dataBody = response["data"] as? [String: Any]
            let rawSizes = dataBody?["sizes"] as? [[String: Any]] ?? []
            let rawSizeNames = rawSizes.compactMap { $0["name"] as? String }
            let rawMeasurementLabels = Array(Set(rawSizes.flatMap { size -> [String] in
                let items = size["items"] as? [[String: Any]] ?? []
                return items.compactMap { $0["name"] as? String }
            })).sorted()
            let rawPositiveMeasurementCount = rawSizes.reduce(into: 0) { count, size in
                let items = size["items"] as? [[String: Any]] ?? []
                count += items.filter { item in
                    if let value = item["value"] as? Double { return value > 0 }
                    if let value = item["value"] as? Int { return value > 0 }
                    if let value = item["value"] as? String,
                       let number = Double(value) { return number > 0 }
                    return false
                }.count
            }
            let category = ClothingCategory.fromTaxonomyCode(categoryCode)
            let responseData = try JSONSerialization.data(withJSONObject: response)
            let parsed = try parser.parseActualSize(
                from: responseData,
                isTopCategory: category.serviceGroup == .top
            )
            let validSizes = ParsedSizeValidator.validSizes(parsed.sizes, category: category)
            let parsedSizeNames = parsed.sizes.map(\.name)
            let invalidTokenNames = parsed.sizes
                .filter { !SizeTokenNormalizer.isValid($0.name) }
                .map(\.name)
            let maximumValue: Double = category.serviceGroup == .shoes ? 400 : 300
            let sizesWithoutMappedMeasurement = parsed.sizes.filter { size in
                !size.measurementRecords.contains {
                    $0.semanticStatus == .mapped
                        && $0.measurementCode != .unknown
                        && $0.measurementCode != .legacyUnknown
                        && $0.value.isFinite
                        && $0.value > 0
                        && $0.value <= maximumValue
                }
            }.map(\.name)
            let parsedMeasurementRecords = parsed.sizes.flatMap(\.measurementRecords)
            let unknownMeasurementRecords = parsedMeasurementRecords.filter { record in
                record.semanticStatus != .mapped
                    || record.measurementCode == .unknown
                    || record.measurementCode == .legacyUnknown
            }
            let unknownRawLabels = unknownMeasurementRecords.compactMap { $0.rawLabel }
            let unknownLabels = Array(Set(unknownRawLabels)).sorted()

            let stage: String
            var reasons: [String] = []
            if rawSizes.isEmpty {
                stage = "official_size_rows_missing"
                reasons.append("official_response_has_no_size_rows")
            } else if parsed.sizes.isEmpty {
                stage = "official_measurement_values_missing"
                reasons.append(rawPositiveMeasurementCount == 0
                    ? "official_rows_have_no_positive_measurements"
                    : "parser_produced_no_size")
            } else if validSizes.isEmpty {
                stage = "validator_rejected"
                if invalidTokenNames.count == parsed.sizes.count {
                    reasons.append("all_size_tokens_invalid")
                } else if !invalidTokenNames.isEmpty {
                    reasons.append("some_size_tokens_invalid")
                }
                if sizesWithoutMappedMeasurement.count == parsed.sizes.count {
                    reasons.append("no_size_has_mapped_measurement_in_range")
                } else if !sizesWithoutMappedMeasurement.isEmpty {
                    reasons.append("some_sizes_have_no_mapped_measurement_in_range")
                }
                if category.serviceGroup == .shoes && parsed.sizes.count < 2 {
                    reasons.append("shoe_requires_at_least_two_sizes")
                }
                if reasons.isEmpty { reasons.append("validator_rejected_unspecified") }
            } else {
                stage = "eligible"
            }

            diagnostics.append([
                "product_id": productID,
                "product_name": productName,
                "category_code": categoryCode,
                "detail_code": detailCode,
                "source_path": sourcePath,
                "stage": stage,
                "reasons": reasons,
                "raw_size_count": rawSizes.count,
                "raw_positive_measurement_count": rawPositiveMeasurementCount,
                "parsed_size_count": parsed.sizes.count,
                "valid_size_count": validSizes.count,
                "raw_size_names": rawSizeNames,
                "parsed_size_names": parsedSizeNames,
                "invalid_size_token_names": invalidTokenNames,
                "sizes_without_mapped_measurement": sizesWithoutMappedMeasurement,
                "raw_measurement_labels": rawMeasurementLabels,
                "unknown_measurement_labels": unknownLabels,
            ])
        }

        let stageCounts = Dictionary(grouping: diagnostics, by: { $0["stage"] as? String ?? "unknown" })
            .mapValues(\.count)
        try #require(diagnostics.count == 1037)
        try #require(stageCounts["official_size_rows_missing"] == 113)
        try #require(stageCounts["official_measurement_values_missing"] == 10)
        try #require(stageCounts["validator_rejected", default: 0] == 0)
        try #require(stageCounts["eligible"] == 914)

        let encoded = try JSONSerialization.data(
            withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys]
        )
        let outputURL = try #require(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ).appendingPathComponent("fitmatch-musinsa-actual-size-attrition.json")
        try encoded.write(to: outputURL, options: .atomic)
    }

    @Test(.enabled(
        if: runsFitPairCorpusAudit,
        "243건 Uniqlo corpus 검증은 독립 프로세스로 실행합니다."
    ))
    func storedUniqloCorpusBuildsActualMeasurementFitPairs() throws {
        struct Specimen {
            let productID: String
            let productName: String
            let category: ClothingCategory
            let detail: ClosetDetailCategory
            let length: ComparisonLengthType
            let gender: UserGender
            let sourcePath: String
            let size: ParsedProductSize
        }

        let bundle = Bundle(for: FitMatchCorpusBundleToken.self)
        let inputURL = try #require(bundle.url(
            forResource: "Uniqlo243FitPairInputs", withExtension: "json"
        ))
        let inputs = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: inputURL)) as? [[String: Any]]
        )
        let sizeParser = UniqloSizeAPIParser()
        let metadataParser = UniqloProductMetadataParser()
        var diagnostics: [[String: Any]] = []
        var specimens: [Specimen] = []
        var parsedSizeRows = 0

        for input in inputs {
            let productID = try #require(input["product_id"] as? String)
            let productName = try #require(input["product_name"] as? String)
            let sourcePath = try #require(input["source_path"] as? String)
            let genderCodes = input["gender_codes"] as? [String] ?? []
            let response = try #require(input["response"])
            let depths = sourcePath.components(separatedBy: ">").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            let providerCategory = metadataParser.mapCategory(from: "\(sourcePath) \(productName)")
            let providerDetail = metadataParser.mapDetailCategory(from: "\(sourcePath) \(productName)")
            let data = try JSONSerialization.data(withJSONObject: response)
            let parsedSizes = try sizeParser.parseSizes(from: data)
            let normalized = ParsedProductInfo(
                sourceURL: URL(string: "https://store-kr.uniqlo.com/kr/ko/products/\(productID)-000/00")!,
                sourceType: .officialStore,
                sourceName: "유니클로 공식몰",
                brandName: "UNIQLO",
                productName: productName,
                category: providerCategory,
                detailCategory: providerDetail,
                sizes: parsedSizes,
                productID: productID,
                sourceCategoryPath: sourcePath,
                sourceCategoryDepth1: depths.indices.contains(0) ? depths[0] : nil,
                sourceCategoryDepth2: depths.indices.contains(1) ? depths[1] : nil,
                sourceCategoryDepth3: depths.indices.contains(2) ? depths[2] : nil,
                sourceCategoryDepth4: depths.indices.contains(3) ? depths[3] : nil,
                productTargetGender: UserGender.productTarget(from: genderCodes)
            ).normalizedSizes()
            guard let classification = ParsedClosetClassification.resolve(
                category: providerCategory,
                detailCategory: normalized.detailCategory,
                sourceDepths: depths.map(Optional.some),
                sourcePath: sourcePath,
                productName: productName
            ) else {
                diagnostics.append([
                    "product_id": productID,
                    "product_name": productName,
                    "source_path": sourcePath,
                    "stage": "taxonomy_unsupported",
                    "parsed_size_count": parsedSizes.count,
                    "valid_size_count": 0,
                    "size_names": parsedSizes.map(\.name),
                ])
                continue
            }
            let category = ClothingCategory.fromTaxonomyCode(classification.categoryCode)
            let detail = ClosetDetailCategory.fromTaxonomyCode(classification.detailCode)
            let validSizes = ParsedSizeValidator.validSizes(parsedSizes, category: category)
            parsedSizeRows += validSizes.count
            let stage: String
            if parsedSizes.isEmpty {
                stage = "official_size_rows_missing"
            } else if validSizes.isEmpty {
                stage = "validator_rejected"
            } else {
                stage = "eligible"
                specimens.append(Specimen(
                    productID: productID,
                    productName: productName,
                    category: category,
                    detail: detail,
                    length: classification.lengthType,
                    gender: UserGender.productTarget(from: genderCodes),
                    sourcePath: sourcePath,
                    size: validSizes[validSizes.count / 2]
                ))
            }
            diagnostics.append([
                "product_id": productID,
                "product_name": productName,
                "category_code": classification.categoryCode,
                "detail_code": classification.detailCode,
                "source_path": sourcePath,
                "stage": stage,
                "parsed_size_count": parsedSizes.count,
                "valid_size_count": validSizes.count,
                "size_names": parsedSizes.map(\.name),
                "unknown_measurement_codes": Array(Set(parsedSizes
                    .flatMap(\.measurementRecords)
                    .filter { $0.semanticStatus != .mapped }
                    .compactMap(\.rawCode))).sorted(),
            ])
        }

        var products: [String: Product] = [:]
        var references: [String: UserFit] = [:]
        for specimen in specimens {
            let size = ParsedProductSizeNormalizer.makeProductSizes(from: [specimen.size])[0]
            let product = Product(
                name: specimen.productName,
                category: specimen.category,
                productCode: specimen.productID,
                sourceURLString: "https://www.uniqlo.com/kr/ko/products/\(specimen.productID)-000",
                metadata: ProductMetadata(
                    sourceCategoryPath: specimen.sourcePath,
                    genderCodes: [specimen.gender.rawValue]
                ),
                sourceName: "유니클로",
                sizes: [size]
            )
            product.sleeveType = specimen.length
            products[specimen.productID] = product
            let item = UserFit(
                sourceType: .officialStore,
                sourceName: "유니클로",
                sourceCategoryPath: specimen.sourcePath,
                brandName: "유니클로",
                gender: specimen.gender,
                productName: specimen.productName,
                category: specimen.category,
                detailCategory: specimen.detail,
                sizeName: specimen.size.name,
                measurements: specimen.size.measurements,
                fitMemo: specimen.productID,
                satisfaction: 3
            )
            item.sleeveType = specimen.length
            item.measurementRecords = specimen.size.measurementRecords.map { $0.makeRecord(userFit: item) }
            references[specimen.productID] = item
        }

        var pairResults: [[String: Any]] = []
        var usedPairKeys = Set<String>()
        let matcher = ComparisonProfileMatcher()
        for specimen in specimens.sorted(by: { $0.productID < $1.productID }) {
            guard let product = products[specimen.productID],
                  let productSize = product.sizes.first else { continue }
            let candidates = references.filter { $0.key != specimen.productID }.map(\.value)
            let match = matcher.match(
                product: product,
                productDetailCategory: specimen.detail,
                userFits: candidates
            )
            guard let reference = match.compatibleCandidates.first else { continue }
            let comparisonProfile = matcher.profile(for: product, detailCategory: specimen.detail)
            let referenceProfile = matcher.profile(for: reference)
            let pairKey = [specimen.productID, reference.fitMemo].sorted().joined(separator: "|")
            guard usedPairKeys.insert(pairKey).inserted else { continue }
            let result = MeasurementComparisonEngine().compare(
                productSize: productSize,
                referenceItem: reference,
                productCategory: specimen.category,
                productDetailCategory: specimen.detail
            )
            pairResults.append([
                "reference_product_id": reference.fitMemo,
                "reference_product_name": reference.productName,
                "reference_size_name": reference.sizeName,
                "reference_source_path": reference.sourceCategoryPath ?? "",
                "reference_url": "https://www.uniqlo.com/kr/ko/products/\(reference.fitMemo)-000",
                "reference_category_code": reference.category.serviceGroup.taxonomyCode,
                "reference_detail_code": reference.detailCategory.rawValue,
                "reference_gender_code": reference.resolvedGenderCode,
                "reference_garment_family": referenceProfile.garmentFamily.rawValue,
                "reference_construction_type": referenceProfile.constructionType.rawValue,
                "reference_body_length_type": referenceProfile.bodyLengthType.rawValue,
                "reference_length_type": referenceProfile.lengthType.rawValue,
                "comparison_product_id": specimen.productID,
                "comparison_product_name": specimen.productName,
                "comparison_size_name": productSize.name,
                "comparison_source_path": specimen.sourcePath,
                "comparison_url": "https://www.uniqlo.com/kr/ko/products/\(specimen.productID)-000",
                "comparison_category_code": specimen.category.serviceGroup.taxonomyCode,
                "comparison_detail_code": specimen.detail.rawValue,
                "comparison_gender_code": specimen.gender.taxonomyCode,
                "comparison_garment_family": comparisonProfile.garmentFamily.rawValue,
                "comparison_construction_type": comparisonProfile.constructionType.rawValue,
                "comparison_body_length_type": comparisonProfile.bodyLengthType.rawValue,
                "comparison_length_type": comparisonProfile.lengthType.rawValue,
                "category_code": specimen.category.serviceGroup.taxonomyCode,
                "detail_code": specimen.detail.rawValue,
                "status": result.status.rawValue,
                "score": result.score,
                "compared_item_count": result.comparedItems.count,
                "coverage": result.comparisonCoverage,
                "reliability": result.reliabilityTitle,
                "exclusion_count": result.exclusions.count,
                "exclusion_reasons": result.exclusions.map(\.reason.rawValue),
                "minimum_comparable_count": result.minimumComparableCount,
                "minimum_required_kind_count": result.minimumRequiredKindCount,
                "required_kinds": result.requiredKinds.map(\.rawValue),
                "required_all_kinds": result.requiredAllKinds.map(\.rawValue),
                "compared_items": result.comparedItems.map { item in
                    [
                        "kind": item.kind.rawValue,
                        "measurement_code": item.measurementCode.rawValue,
                        "display_title": item.displayTitle ?? item.kind.title,
                        "reference_value_cm": item.referenceValue,
                        "comparison_value_cm": item.productValue,
                        "signed_difference_cm": item.signedDifference,
                        "absolute_difference_cm": item.absoluteDifference,
                        "item_score": item.score,
                        "weight": item.weight,
                    ] as [String: Any]
                },
                "exclusions": result.exclusions.map { exclusion in
                    [
                        "kind": exclusion.kind.rawValue,
                        "reason": exclusion.reason.rawValue,
                        "reference_code": exclusion.referenceCode?.rawValue ?? "",
                        "comparison_code": exclusion.productCode?.rawValue ?? "",
                    ]
                },
            ])
        }

        print("[UniqloCorpus] stage=summary inputs=\(inputs.count) specimens=\(specimens.count) parsedRows=\(parsedSizeRows) pairs=\(pairResults.count)")
        for diagnostic in diagnostics where (diagnostic["stage"] as? String) != "eligible" {
            print(
                "[UniqloCorpus] stage=excluded product=\(diagnostic["product_id"] ?? "") "
                    + "reason=\(diagnostic["stage"] ?? "") name=\(diagnostic["product_name"] ?? "")"
            )
        }
        // Persist the diagnostic artifacts before enforcing the frozen totals so
        // a legitimate safety-policy change can be compared with the previous
        // corpus result instead of hiding the changed pair behind a count error.
        let diagnosticsData = try JSONSerialization.data(
            withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys]
        )
        let pairData = try JSONSerialization.data(
            withJSONObject: pairResults, options: [.prettyPrinted, .sortedKeys]
        )
        let documents = try #require(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        )
        try diagnosticsData.write(
            to: documents.appendingPathComponent("fitmatch-uniqlo-size-diagnostics.json"),
            options: .atomic
        )
        try pairData.write(
            to: documents.appendingPathComponent("fitmatch-uniqlo-actual-measurement-pairs.json"),
            options: .atomic
        )
        try #require(inputs.count == 243)
        try #require(specimens.count == 238)
        try #require(parsedSizeRows == 1_574)
        try #require(pairResults.count == 184)
        try #require(pairResults.allSatisfy { ($0["status"] as? String) == "confirmed" })
        try #require(pairResults.allSatisfy {
            ($0["comparison_category_code"] as? String) == ($0["reference_category_code"] as? String)
        })
        let allowedSimilarFamilies: Set<Set<String>> = [
            [ComparisonGarmentFamily.denim.rawValue, ComparisonGarmentFamily.pants.rawValue],
            [ComparisonGarmentFamily.tshirt.rawValue, ComparisonGarmentFamily.shirt.rawValue],
            [ComparisonGarmentFamily.sweatshirt.rawValue, ComparisonGarmentFamily.hoodie.rawValue],
            [ComparisonGarmentFamily.outerwear.rawValue, ComparisonGarmentFamily.hoodie.rawValue],
        ]
        try #require(pairResults.allSatisfy { pair in
            guard let comparisonFamily = pair["comparison_garment_family"] as? String,
                  let referenceFamily = pair["reference_garment_family"] as? String else { return false }
            return comparisonFamily == referenceFamily
                || allowedSimilarFamilies.contains([comparisonFamily, referenceFamily])
        })
        try #require(pairResults.allSatisfy { pair in
            guard (pair["comparison_garment_family"] as? String)
                    != (pair["reference_garment_family"] as? String) else { return true }
            return (pair["comparison_length_type"] as? String) != ComparisonLengthType.unknown.rawValue
                && (pair["comparison_length_type"] as? String)
                    == (pair["reference_length_type"] as? String)
        })
        try #require(pairResults.allSatisfy {
            ($0["category_code"] as? String) != "outerwear"
                || (($0["comparison_body_length_type"] as? String) != "unknown"
                    && ($0["comparison_body_length_type"] as? String)
                        == ($0["reference_body_length_type"] as? String))
        })
    }

    @Test func musinsaSourceDepthPriorityKeepsUmbrellaFamiliesOutOfGenericBottoms() {
        #expect(MusinsaProductMetadataParser.mapCategory(
            from: "속옷/홈웨어 > 여성 속옷 > 여성 속옷 하의"
        ) == .underwear)
        #expect(MusinsaProductMetadataParser.mapCategory(
            from: "원피스/스커트 > 스커트 > 롱 스커트"
        ) == .bottom)
        #expect(MusinsaProductMetadataParser.mapCategory(
            from: "원피스/스커트 > 원피스 > 미디 원피스"
        ) == .dress)
        #expect(MusinsaProductMetadataParser.mapCategory(
            from: "스포츠/레저 > 스포츠 하의 > 숏 팬츠"
        ) == .bottom)
        #expect(MusinsaProductMetadataParser.mapCategory(
            from: "Clothing > 바지 > 데님 팬츠"
        ) == .bottom)
        #expect(MusinsaProductMetadataParser.mapCategory(
            from: "Clothing > 점퍼/재킷 > 데님/트러커 재킷"
        ) == .outer)
        #expect(MusinsaProductMetadataParser.mapCategory(
            from: "Clothing > 후드 집업"
        ) == .outer)
        #expect(MusinsaProductMetadataParser.mapCategory(
            from: "Clothing > 무스탕/퍼"
        ) == .outer)
        #expect(MusinsaProductMetadataParser.mapCategory(
            from: "Clothing > 베스트"
        ) == .outer)
        #expect(MusinsaProductMetadataParser.mapCategory(
            from: "상의 > 니트 > 니트 베스트"
        ) == .knit)
    }

    @Test func musinsaOfficialOuterwearLeavesResolveBeforeMaterialKeywords() throws {
        let fixtures: [(String, String, String)] = [
            ("Clothing > 점퍼/재킷 > 데님/트러커 재킷", "워싱 크롭 데님 재킷", "jacket"),
            ("Clothing > 후드 집업", "LACE HOOD ZIP-UP WHITE", "jumper"),
            ("Clothing > 무스탕/퍼", "와이드 카라 플러피 퍼 코트", "mouton"),
            ("Clothing > 베스트", "레저 포켓 베스트", "vest"),
        ]

        for (sourcePath, productName, expectedDetail) in fixtures {
            let depths = sourcePath.components(separatedBy: " > ")
            let category = MusinsaProductMetadataParser.mapCategory(from: sourcePath)
            let detail = MusinsaProductMetadataParser.mapDetailCategory(
                from: depths.last ?? sourcePath
            )
            let result = try #require(ParsedClosetClassification.resolve(
                category: category,
                detailCategory: detail,
                sourceDepths: depths.map(Optional.some),
                sourcePath: sourcePath,
                productName: productName
            ))
            #expect(result.categoryCode == "outerwear")
            #expect(result.detailCode == expectedDetail)
            #expect(result.isValid)
        }
    }

    @Test func musinsaDenimPantsMapToLongPantsWhilePreservingDenimFamily() throws {
        let result = try #require(ParsedClosetClassification.resolve(
            category: .bottom,
            detailCategory: .denim,
            sourceDepths: ["바지", "데님 팬츠", nil, nil],
            sourcePath: "바지 > 데님 팬츠",
            productName: "사이드 절개 와이드 데님 팬츠"
        ))
        #expect(result.categoryCode == "bottoms")
        #expect(result.detailCode == "long_pants")
        #expect(result.detailCategory == .longPants)
        #expect(result.garmentFamily == .denim)
        #expect(result.isValid)
    }

    @Test func uniqloStraightJeansMapToLongPantsWhilePreservingDenimFamily() throws {
        let result = try #require(ParsedClosetClassification.resolve(
            category: .bottom,
            detailCategory: .denim,
            sourceDepths: ["팬츠", "진(청바지)", "스트레이트", nil],
            sourcePath: "팬츠 > 진(청바지) > 스트레이트",
            productName: "스트레이트진"
        ))

        #expect(result.categoryCode == "bottoms")
        #expect(result.detailCode == "long_pants")
        #expect(result.detailCategory == .longPants)
        #expect(result.garmentFamily == .denim)
        #expect(result.lengthType == .long)
        #expect(result.isValid)
    }

    @Test func uniqloWideChinoPantsMapToLongPants() throws {
        let result = try #require(ParsedClosetClassification.resolve(
            category: .bottom,
            detailCategory: .other,
            sourceDepths: ["팬츠", "치노팬츠", "와이드", nil],
            sourcePath: "팬츠 > 치노팬츠 > 와이드",
            productName: "와이드치노팬츠"
        ))

        #expect(result.categoryCode == "bottoms")
        #expect(result.detailCode == "long_pants")
        #expect(result.detailCategory == .longPants)
        #expect(result.lengthType == .long)
        #expect(result.isValid)
    }

    @Test func uniqloShortPantsRemainShortsBeforeGenericPantsRule() throws {
        let result = try #require(ParsedClosetClassification.resolve(
            category: .bottom,
            detailCategory: .other,
            sourceDepths: ["팬츠", "쇼트팬츠", "와이드", nil],
            sourcePath: "팬츠 > 쇼트팬츠 > 와이드",
            productName: "와이드핏쇼트팬츠"
        ))

        #expect(result.categoryCode == "bottoms")
        #expect(result.detailCode == "shorts")
        #expect(result.detailCategory == .shorts)
        #expect(result.lengthType == .short)
        #expect(result.isValid)
    }

    @Test func musinsaTopAndOuterExactTotalLengthUseCommonCode() {
        for (upperCategory, typeNumber) in [(ClothingCategory.top, 5), (.outer, 7)] {
            let mapping = MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber,
                displayKind: .totalLength,
                rawLabel: "총장",
                isTopCategory: upperCategory.isMusinsaUpperBodyCategory
            )
            #expect(mapping?.code == .bodyLengthBackNeckToHem)
        }
        #expect(MeasurementSourceMappingPolicy.musinsa(
            typeNumber: 6, displayKind: .totalLength, rawLabel: "총장",
            isTopCategory: false
        )?.code == .pantsOutseamWaistToHem)
    }

    @Test func parsedSizeValidatorRejectsUnknownOnlyActualSizeAndKeepsMappedFallback() {
        let unknown = ParsedMeasurement(
            value: 90,
            measurementCode: .unknown,
            displayKind: .chest,
            methodSource: "actual-size",
            inputSource: .importedSizeChart,
            rawLabel: "기타",
            evidenceLevel: .unknown,
            semanticStatus: .unknownDefinition
        )
        let mapped = ParsedMeasurement(
            value: 90,
            measurementCode: .chestCircumferenceGarment,
            displayKind: .chest,
            methodSource: "html",
            inputSource: .transcribedSizeChart,
            rawLabel: "가슴둘레",
            evidenceLevel: .officialText,
            semanticStatus: .mapped
        )
        let actual = ParsedProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0),
            measurementRecords: [unknown]
        )
        let fallback = ParsedProductSize(
            name: "M",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0),
            measurementRecords: [mapped]
        )

        #expect(ParsedSizeValidator.validSizes(
            [actual],
            category: .top
        ).isEmpty)
        #expect(ParsedSizeValidator.validSizes(
            [fallback],
            category: .top
        ).map(\.name) == ["M"])
        #expect(MusinsaSizeAvailabilityResolver.resolve(
            isUseSize: false,
            sizeType: nil,
            actualSizes: [actual],
            category: .top
        ) == .unavailable)
    }

    @Test func parsedSizeValidatorRejectsSingleShoeReference() {
        let footLength = ParsedMeasurement(
            value: 235,
            measurementCode: .footLengthHeelToToe,
            displayKind: .footLength,
            methodSource: "html",
            inputSource: .transcribedSizeChart,
            rawLabel: "발길이",
            evidenceLevel: .officialText,
            semanticStatus: .mapped
        )
        let reference = ParsedProductSize(
            name: "235",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0),
            measurementRecords: [footLength]
        )

        #expect(ParsedSizeValidator.validSizes(
            [reference],
            category: .shoes
        ).isEmpty)
    }

    @Test func parsedSizeValidatorAllowsNonstandardNamesOnlyForTrustedProviderMeasurements() {
        func measurement(methodSource: String, inputSource: MeasurementInputSource) -> ParsedMeasurement {
            ParsedMeasurement(
                value: 58,
                measurementCode: .chestWidthPitToPit,
                displayKind: .chest,
                methodSource: methodSource,
                inputSource: inputSource,
                rawLabel: "가슴단면",
                evidenceLevel: .officialText,
                semanticStatus: .mapped
            )
        }
        func size(_ name: String, measurement: ParsedMeasurement) -> ParsedProductSize {
            ParsedProductSize(
                name: name,
                measurements: GarmentMeasurements(
                    shoulder: 0, chest: 58, totalLength: 0, sleeveLength: 0
                ),
                measurementRecords: [measurement]
            )
        }

        let officialMusinsa = size(
            "세미오버핏_블레이저_M",
            measurement: measurement(methodSource: "musinsa", inputSource: .importedSizeChart)
        )
        let transcribed = size(
            "세미오버핏_블레이저_M",
            measurement: measurement(methodSource: "html", inputSource: .transcribedSizeChart)
        )
        let officialUniqlo = size(
            "WOMEN_090",
            measurement: measurement(methodSource: "uniqlo_kr", inputSource: .importedSizeChart)
        )

        #expect(ParsedSizeValidator.validSizes([officialMusinsa], category: .outer).count == 1)
        #expect(ParsedSizeValidator.validSizes([officialUniqlo], category: .top).count == 1)
        #expect(ParsedSizeValidator.validSizes([transcribed], category: .outer).isEmpty)
    }

    private func inMemoryModelContainer() throws -> ModelContainer {
        let schema = Schema([
            Brand.self,
            Product.self,
            ProductSize.self,
            UserFit.self,
            RecommendationHistory.self,
            GarmentMeasurementRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func waitUntilParserStarts(_ parser: DelayedProductURLParserSpy) async {
        for _ in 0..<100 where parser.startedURLs.isEmpty {
            await Task.yield()
        }
        #expect(!parser.startedURLs.isEmpty)
    }

}

@MainActor
private final class ProductURLParserSpy: ProductURLParsing {
    let canParseResult: Bool
    let result: Result<ParsedProductInfo, Error>
    private(set) var parseCallCount = 0

    init(
        canParse: Bool,
        result: Result<ParsedProductInfo, Error> = .failure(ParserSpyError.failed)
    ) {
        canParseResult = canParse
        self.result = result
    }

    func canParse(_ url: URL) -> Bool {
        canParseResult
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        parseCallCount += 1
        return try result.get()
    }
}

private enum ParserSpyError: Error {
    case failed
}

private struct COSProductPageLoaderSpy: COSProductPageLoading {
    let page: COSProductPage

    func load(url: URL) async throws -> COSProductPage {
        page
    }
}

private struct COSSizeGuideLoaderSpy: COSSizeGuideLoading {
    let data: Data

    func load(request: COSSizeGuideRequest, referringProductURL: URL) async throws -> Data {
        data
    }
}

private struct ZARAProductPageLoaderSpy: ZARAProductPageLoading {
    let page: ZARAProductPage

    func load(url: URL) async throws -> ZARAProductPage {
        page
    }
}

private struct ZARASizeGuideLoaderSpy: ZARASizeGuideLoading {
    let data: Data

    func load(productID: String) async throws -> Data {
        data
    }
}

@MainActor
private final class DelayedProductURLParserSpy: ProductURLParsing {
    let delays: [String: UInt64]
    private(set) var startedURLs: [URL] = []

    init(delays: [String: UInt64]) {
        self.delays = delays
    }

    func canParse(_ url: URL) -> Bool {
        true
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        startedURLs.append(url)
        let productName = url.lastPathComponent
        try await Task.sleep(nanoseconds: delays[productName] ?? 0)
        return ParsedProductInfo(
            sourceURL: url,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: productName,
            category: .top,
            detailCategory: .shortSleeve,
            sizes: [
                ParsedProductSize(
                    name: "M",
                    measurements: GarmentMeasurements(
                        shoulder: 45,
                        chest: 52,
                        totalLength: 68,
                        sleeveLength: 22
                    )
                )
            ],
            productID: productName
        )
    }

}

private func comparisonProduct(
    name: String,
    category: ClothingCategory = .top,
    sourceCategory: String,
    sleeve: Double,
    totalLength: Double = 70
) -> Product {
    let metadata = ProductMetadata(sourceCategoryPath: sourceCategory)
    let size = ProductSize(
        name: "M",
        measurements: GarmentMeasurements(shoulder: 48, chest: 54, totalLength: totalLength, sleeveLength: sleeve)
    )
    return Product(name: name, category: category, metadata: metadata, sourceName: "무신사", sizes: [size])
}

private func comparisonUserFit(
    name: String,
    category: ClothingCategory = .top,
    sourceCategory: String = "상의 > 니트/가디건",
    detail: ClosetDetailCategory,
    sleeve: Double,
    totalLength: Double = 70
) -> UserFit {
    UserFit(
        sourceName: "무신사",
        sourceCategoryPath: sourceCategory,
        brandName: "테스트",
        productName: name,
        category: category,
        detailCategory: detail,
        sizeName: "M",
        measurements: GarmentMeasurements(
            shoulder: 48,
            chest: 54,
            totalLength: totalLength,
            sleeveLength: sleeve,
            waist: category == .bottom ? 38 : 0,
            hip: category == .bottom ? 50 : 0,
            thigh: category == .bottom ? 30 : 0
        ),
        fitMemo: "",
        satisfaction: 3
    )
}

/// Physical-device bridge. This toolchain can report a successful zero-test run
/// when filtering Swift Testing members directly, so XCTest owns the entrypoints.
@MainActor
final class FitPairCorpusXCTests: XCTestCase {
    func testMusinsa1037OfficialMeasurementCorpus() throws {
        try XCTSkipUnless(
            runsFitPairCorpusAudit,
            "1,037건 Musinsa corpus 검증은 FITMATCH_RUN_FIT_PAIR_CORPUS_AUDIT=1로 독립 실행합니다."
        )
        try FitMatchTests().storedMusinsaCorpusBuildsActualMeasurementFitPairs()
    }

    func testUniqlo243OfficialMeasurementCorpus() throws {
        try XCTSkipUnless(
            runsFitPairCorpusAudit,
            "243건 Uniqlo corpus 검증은 FITMATCH_RUN_FIT_PAIR_CORPUS_AUDIT=1로 독립 실행합니다."
        )
        try FitMatchTests().storedUniqloCorpusBuildsActualMeasurementFitPairs()
    }
}
