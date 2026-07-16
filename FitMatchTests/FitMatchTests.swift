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

    @Test func tshirtAndKnitMayBothBeReferenceGarments() {
        let tshirt = comparisonUserFit(name: "반팔 티셔츠", sourceCategory: "상의 > 반소매 티셔츠", detail: .shortSleeve, sleeve: 24)
        let knit = comparisonUserFit(name: "반팔 니트", sourceCategory: "상의 > 니트/스웨터", detail: .shortSleeve, sleeve: 24)
        tshirt.normalizedProductTypeCode = "tops.tshirt"
        knit.normalizedProductTypeCode = "tops.knit_sweater"

        #expect(!ReferenceGarmentPolicy.conflicts(tshirt, knit))
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
        #expect(chest?.measurementCode == .chestWidthUniqloBodyWidth)
        #expect(chest?.semanticStatus == .mapped)
        #expect(chest?.mappingVersion == "uniqlo_kr_size_chart_mapping_v2")
        #expect(length?.measurementCode == .unknown)
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

        let result = try MusinsaActualSizeAPIParser().parseActualSize(from: Data(json.utf8))
        let records = result.sizes.first?.measurementRecords ?? []
        let sleeve = records.first { $0.rawLabel == "화장" }
        let chest = records.first { $0.rawLabel == "가슴단면" }

        #expect(result.typeNumber == 11)
        #expect(result.webImage == "https://example.com/web.png")
        #expect(sleeve?.measurementCode == .sleeveRaglanNeckToCuff)
        #expect(sleeve?.mappingVersion == MeasurementSourceMappingPolicy.musinsaVersion)
        #expect(sleeve?.methodProfile == "musinsa_type_11")
        #expect(sleeve?.rawValueText == "82.5")
        #expect(chest?.measurementCode == .unknown)
        #expect(chest?.semanticStatus == .unknownDefinition)
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

        let result = try MusinsaActualSizeAPIParser().parseActualSize(from: Data(json.utf8))
        let records = result.sizes.first?.measurementRecords ?? []
        let chest = records.first { $0.rawLabel == "가슴단면" }
        let length = records.first { $0.rawLabel == "총장" }

        #expect(chest?.measurementCode == .chestWidthPitToPit)
        #expect(chest?.evidenceLevel == .officialDiagram)
        #expect(chest?.mappingVersion == "musinsa_actual_size_mapping_v2")
        #expect(length?.measurementCode == .unknown)
        #expect(length?.semanticStatus == .unknownDefinition)

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

    @Test func sourceMeasurementMappingPolicyMapsVerifiedMusinsaChestOnly() {
        let verifiedMusinsaTypes = [5, 20, 21]
        let verifiedMusinsa = MeasurementSourceMappingPolicy.musinsa(typeNumber: 5, displayKind: .shoulder)
        let verifiedMusinsaChest = MeasurementSourceMappingPolicy.musinsa(typeNumber: 5, displayKind: .chest)
        let unknownMusinsaLength = MeasurementSourceMappingPolicy.musinsa(typeNumber: 5, displayKind: .totalLength)
        let unknownMusinsaType = MeasurementSourceMappingPolicy.musinsa(typeNumber: 999, displayKind: .shoulder)
        let verifiedUniqloSleeve = MeasurementSourceMappingPolicy.uniqlo(rawCode: "sleeve-length-cb")
        let verifiedUniqloChest = MeasurementSourceMappingPolicy.uniqlo(rawCode: "body-width")

        #expect(verifiedMusinsaTypes.allSatisfy {
            MeasurementSourceMappingPolicy.musinsa(typeNumber: $0, displayKind: .shoulder)?.code == .shoulderWidthSeamToSeam
        })
        #expect(verifiedMusinsaTypes.allSatisfy {
            MeasurementSourceMappingPolicy.musinsa(typeNumber: $0, displayKind: .sleeveLength)?.code == .sleeveShoulderSeamToCuff
        })
        #expect(verifiedMusinsaTypes.allSatisfy {
            MeasurementSourceMappingPolicy.musinsa(typeNumber: $0, displayKind: .chest)?.code == .chestWidthPitToPit
        })
        #expect(verifiedMusinsa?.code == .shoulderWidthSeamToSeam)
        #expect(verifiedMusinsa?.mappingVersion == MeasurementSourceMappingPolicy.musinsaVersion)
        #expect(verifiedMusinsaChest?.code == .chestWidthPitToPit)
        #expect(unknownMusinsaLength == nil)
        #expect(unknownMusinsaType == nil)
        #expect(verifiedUniqloSleeve?.code == .sleeveCenterBackToCuff)
        #expect(verifiedUniqloSleeve?.mappingVersion == MeasurementSourceMappingPolicy.uniqloVersion)
        #expect(verifiedUniqloChest?.code == .chestWidthUniqloBodyWidth)
        #expect(verifiedUniqloChest?.code != verifiedMusinsaChest?.code)
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

    @Test func compatibleMeasurementCountOutranksRepresentativeFlag() {
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

        #expect(ranked.first?.userFit.id == richerEvidence.id)
        #expect(ranked.first?.compatibleMeasurementCount == 3)
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

    @Test func manualClosetEntryRequiresMeasurementSource() {
        let viewModel = AddClosetItemViewModel()
        viewModel.brand = "테스트"
        viewModel.productName = "반팔 티셔츠"
        viewModel.shoulder = "48"

        #expect(!viewModel.canSave)

        viewModel.measurementEntrySource = .fitmatchMeasured

        #expect(viewModel.canSave)
    }

    @Test func fitmatchMeasuredEntryCreatesComparableStandardRecords() {
        let viewModel = manualMeasurementViewModel(source: .fitmatchMeasured)

        let item = viewModel.makeUserFit()
        let byKind = Dictionary(uniqueKeysWithValues: (item?.measurementRecords ?? []).compactMap { record in
            record.displayKind.map { ($0, record) }
        })

        #expect(item?.measurementInputSourceRawValue == MeasurementInputSource.userMeasured.rawValue)
        #expect(byKind[.shoulder]?.measurementCode == .shoulderWidthSeamToSeam)
        #expect(byKind[.chest]?.measurementCode == .chestWidthPitToPit)
        #expect(byKind[.totalLength]?.measurementCode == .bodyLengthHPSToHemFront)
        #expect(byKind[.sleeveLength]?.measurementCode == .sleeveShoulderSeamToCuff)
        #expect((item?.measurementRecords ?? []).allSatisfy(\.isComparable))
        #expect((item?.measurementRecords ?? []).allSatisfy { $0.standardVersion == FitMatchMeasurementStandard.version })
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

    @Test func uniqloTranscribedEntryKeepsSourceSpecificChestAndCenterBackSleeve() {
        let viewModel = manualMeasurementViewModel(source: .uniqloSizeChart)

        let item = viewModel.makeUserFit()
        let sleeve = item?.measurementRecords.first { $0.displayKind == .sleeveLength }
        let chest = item?.measurementRecords.first { $0.displayKind == .chest }

        #expect(item?.measurementInputSourceRawValue == MeasurementInputSource.transcribedSizeChart.rawValue)
        #expect(sleeve?.measurementCode == .sleeveCenterBackToCuff)
        #expect(sleeve?.rawCode == "sleeve-length-cb")
        #expect(chest?.measurementCode == .chestWidthUniqloBodyWidth)
        #expect(chest?.rawCode == "body-width")
        #expect(chest?.rawValueText == "54")
        #expect(chest?.semanticStatus == .mapped)
        #expect(chest?.mappingVersion == "uniqlo_kr_size_chart_mapping_v2")
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
        #expect(byKind[.totalLength]?.measurementCode == .legacyUnknown)
        #expect(byKind[.shoulder]?.isComparable == true)
        #expect(byKind[.chest]?.isComparable == true)
        #expect(records.allSatisfy { $0.mappingVersion == "legacy_backfill_v3" })
        #expect(MeasurementLegacyBackfillService.migrationVersion == 3)
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
        #expect(savedRecords.first?.measurementCode == .chestWidthUniqloBodyWidth)
        #expect(savedRecords.first?.mappingVersion == "uniqlo_kr_size_chart_mapping_v2")
        #expect(size.measurementMigrationVersion == 3)
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
        guard let chest = records.first(where: { $0.displayKind == .chest }) else { return }
        chest.measurementCodeRawValue = MeasurementCode.chestWidthPitToPit.rawValue
        chest.evidenceLevelRawValue = MeasurementEvidenceLevel.officialText.rawValue
        chest.semanticStatusRawValue = MeasurementSemanticStatus.mapped.rawValue
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
