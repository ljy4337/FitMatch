//
//  FitMatchTests.swift
//  FitMatchTests
//
//  Created by 이진영 on 7/3/26.
//

import Testing
import UIKit
@testable import FitMatch

struct FitMatchTests {

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
                    { "code": "sleeve-length-cb", "name": "소매", "measurements": [{ "value": "82", "unit": "cm" }] }
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

}
