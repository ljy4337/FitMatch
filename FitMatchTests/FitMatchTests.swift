//
//  FitMatchTests.swift
//  FitMatchTests
//
//  Created by 이진영 on 7/3/26.
//

import Testing
import UIKit
import SwiftData
@testable import FitMatch

@MainActor
struct FitMatchTests {
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
            "sleeveless", "short_sleeve", "three_quarter_sleeve", "long_sleeve", "other_tops"
        ]))
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

    @Test func unknownSleeveLengthRequiresConfirmation() {
        let product = comparisonProduct(name: "베이직 니트", sourceCategory: "상의 > 니트/가디건", sleeve: 40)
        let item = comparisonUserFit(name: "니트", detail: .knitTop, sleeve: 40)

        let result = ComparisonProfileMatcher().match(product: product, productDetailCategory: .knitTop, userFits: [item])

        #expect(result.state == .requiresConfirmation)
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

    @Test func manualLengthMismatchExcludesLengthMeasurement() {
        let matcher = ComparisonProfileMatcher()
        let topProduct = comparisonProduct(name: "긴팔 니트", sourceCategory: "상의 > 니트/가디건", sleeve: 60)
        let shortTop = comparisonUserFit(name: "반팔 니트", detail: .shortSleeve, sleeve: 24)
        let bottomProduct = comparisonProduct(name: "롱 팬츠", category: .bottom, sourceCategory: "바지 > 롱 팬츠", sleeve: 0, totalLength: 100)
        let shorts = comparisonUserFit(name: "쇼츠", category: .bottom, sourceCategory: "바지 > 숏 팬츠", detail: .shorts, sleeve: 0, totalLength: 55)

        #expect(matcher.manualMismatch(product: topProduct, productDetailCategory: .knitTop, selectedItem: shortTop).excludedKinds == [.sleeveLength])
        #expect(matcher.manualMismatch(product: bottomProduct, productDetailCategory: .slacks, selectedItem: shorts).excludedKinds == [.totalLength])
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
            #expect(crossSourceComparison.status == .insufficientEvidence)
            #expect(crossSourceComparison.exclusions.contains {
                $0.kind == .chest && $0.reason == .incompatibleMeasurementCode
            })
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
        #expect(records.first { $0.rawCode == "rising-length" }?.measurementCode == .riseCrotchToWaistFront)
        #expect(records.first { $0.rawCode == "bottom-width" }?.measurementCode == .hemWidthEdgeToEdge)
        #expect(records.first { $0.rawCode == "inseam" }?.measurementCode == .pantsInseamCrotchToHem)
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

        #expect(plan.automaticallySelectedCandidate?.id == richer.id)
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

    @Test func singleCompatibleReferenceIsAutomaticallySelected() {
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

        #expect(plan.automaticallySelectedCandidate?.id == item.id)
        #expect(!plan.requiresUserSelection)
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

    @Test func richerMeasurementEvidenceMakesReferenceClearlyBest() {
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

        #expect(plan.automaticallySelectedCandidate?.id == richer.id)
    }

    @Test func differentGarmentTypeShowsManualComparisonLimit() {
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

        #expect(note?.contains("다른 종류") == true)
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

    @Test func matchingComparisonAttributesCanCrossClosetCategories() {
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
        #expect(match.state == .compatible)
        #expect(match.compatibleCandidates.map(\.id) == [item.id])
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

        #expect(match.compatibleCandidates.map(\.id) == [compatibleOtherBrand.id])
        #expect(history?.userFit.id == compatibleOtherBrand.id)
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
        let suiteName = "FitMatchTests.SharedURLStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedURLStore(defaults: defaults)
        let url = URL(string: "https://www.musinsa.com/products/4668060")!

        store.savePendingProductURL(url)

        #expect(store.pendingProductURL() == url.absoluteString)
        #expect(store.consumePendingProductURL() == url.absoluteString)
        #expect(store.consumePendingProductURL() == nil)
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
            sleeveCode: .sleeveShoulderSeamToCuff
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
            sleeveCode: .sleeveCenterBackToCuff
        )
        let secondReference = comparisonItem(
            shoulder: 49,
            sleeve: 63,
            shoulderCode: .shoulderWidthSeamToSeam,
            sleeveCode: .sleeveCenterBackToCuff
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
        let savedMeasurementRecords = try context.fetch(FetchDescriptor<GarmentMeasurementRecord>())
        #expect(updated.userFit.id == lastReference.id)
        #expect(updated.recommendedSize.name == "L")
        #expect(savedHistories.count == 1)
        #expect(savedHistories.first?.userFit.id == lastReference.id)
        #expect(savedHistories.first?.recommendedSize.name == "L")
        #expect(savedProducts.count == 1)
        #expect(Set(savedSizes.map(\.id)) == sizeIDsBefore)
        #expect(Set(savedMeasurementRecords.map(\.id)) == measurementRecordIDsBefore)
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
        viewModel.detailCategory = .slacks
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
        viewModel.detailCategory = .jacket
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

        #expect(metadata.category == .top)
        #expect(metadata.detailCategory == .cardigan)
        #expect(metadata.productMetadata.baseCategoryFullPath == "니트 & 가디건 > 니트 > 가디건")
        #expect(metadata.productMetadata.categoryDepth1Name == "니트 & 가디건")
        #expect(metadata.productMetadata.categoryDepth2Name == "니트")
        #expect(metadata.productMetadata.categoryDepth3Name == "가디건")
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
        sleeveCode: MeasurementCode
    ) -> UserFit {
        let item = UserFit(
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "티셔츠",
            category: .top,
            detailCategory: .shortSleeve,
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
        productSize: ProductSize? = nil,
        userFit: UserFit? = nil
    ) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(
            value: value,
            measurementCode: code,
            displayKind: kind.displayKind,
            methodSource: "test",
            inputSource: .importedSizeChart,
            mappingVersion: "test_v1",
            rawLabel: kind.title,
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

    @Test func musinsaFallbackDetectsAndParsesUpperTableAtTopOfLongImage() throws {
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
        #expect(!FitMatchTaxonomyProvider.shared.isValidDetail("shirt", for: "tops"))
        let result = try #require(ParsedClosetClassification.resolve(
            category: .top,
            detailCategory: .shirt,
            sourceDepths: ["상의", "셔츠", nil, nil],
            sourcePath: "상의 > 셔츠",
            productName: "옥스포드 셔츠"
        ))
        #expect(result.detailCode == "other_tops")
        #expect(result.garmentFamily == .shirt)
        #expect(result.isValid)
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
            ("속옷/홈웨어 > 여성 속옷 > 브라", "와이어리스 브라", .underwear, .underwear, "underwear", "underwear"),
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
