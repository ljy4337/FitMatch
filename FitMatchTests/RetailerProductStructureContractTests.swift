import Foundation
import Testing
@testable import FitMatch

struct RetailerProductStructureContractTests {
    @Test func uniqloExplicitProviderStructureIsForwardedWithoutLocalClassification() throws {
        let metadata = UniqloProductMetadataParser().parse(resolved: uniqloResolvedURL(
            productID: "E100001",
            variantID: "E100001-000",
            productName: "공식 크루넥 니트",
            extraProductJSON: #""productStructure":"single""#
        ))

        #expect(metadata.productMetadata.structuredFacts == [
            "product_type_kr": "니트",
            "product_structure": "single",
            "product_structure_source": "uniqlo_pdp_entity",
            "product_structure_evidence": "productStructure:provider_declared"
        ])
        let request = try #require(
            metadata.parsedProductInfo(sizes: []).fitMatchDatabaseResolutionRequest()
        )
        #expect(request.structuredFacts == metadata.productMetadata.structuredFacts)
    }

    @Test func uniqloPDPIdentityOnlyDoesNotSynthesizeSingle() throws {
        let metadata = UniqloProductMetadataParser().parse(resolved: uniqloResolvedURL(
            productID: "E100002",
            variantID: "E100002-000",
            productName: "공식 티셔츠"
        ))

        #expect(metadata.productMetadata.structuredFacts == ["product_type_kr": "니트"])
        #expect(
            metadata.parsedProductInfo(sizes: [coherentSize("M")])
                .normalizedSizes()
                .fitMatchProductObservationRequest()?
                .payload.structuredFacts["product_structure"] == nil
        )
    }

    @Test func musinsaGenericGoodsMetadataDoesNotSynthesizeSingle() throws {
        let metadata = try MusinsaProductMetadataParser().parseStoredProductDetail(
            data: Data("""
            {
              "data": {
                "goodsNo": 101,
                "goodsNm": "공식 긴소매 티셔츠",
                "goodsType": "P",
                "optKindCd": "CLOTHES",
                "isUseSize": true
              }
            }
            """.utf8),
            productID: "101",
            sourceURL: try #require(URL(string: "https://www.musinsa.com/products/101"))
        )

        #expect(metadata.productMetadata.structuredFacts.isEmpty)
        let observed = metadata.parsedProductInfo(sizes: [coherentSize("M")])
            .normalizedSizes()
        #expect(observed.productMetadata.structuredFacts["product_structure"] == nil)
        #expect(observed.productMetadata.structuredFacts["comparison_measurement_contract"] == "single_coherent")
    }

    @Test(arguments: [
        "공식 반팔 티셔츠 2P",
        "공식 반팔 티셔츠 3P",
        "공식 반팔 티셔츠 2PACK",
        "공식 반팔 티셔츠 3장 세트",
        "Official T-shirt 4 pc",
        "Official socks 5 pairs"
    ])
    func explicitRetailerMultipackWordingIsMultipack(text: String) {
        let fact = RetailerProductStructureFact.explicitCompositeRetailerText(
            text,
            source: "fixture_retailer_pdp",
            evidenceField: "product_name"
        )
        #expect(fact?.structure == .multipack)
        #expect(fact?.evidence == "product_name:explicit_multipack")
    }

    @Test func explicitMixedGarmentSetWinsOverPackCount() {
        let fact = RetailerProductStructureFact.explicitCompositeRetailerText(
            "셔츠 + 팬츠 2피스 세트",
            source: "fixture_retailer_pdp",
            evidenceField: "product_description"
        )
        #expect(fact?.structure == .set)
        #expect(fact?.evidence == "product_description:explicit_mixed_garment_set")
    }

    @Test func insufficientRetailerStructureEvidenceStaysAbsent() {
        #expect(
            RetailerProductStructureFact.explicitCompositeRetailerText(
                "일반 의류 2026 신상품",
                source: "fixture_retailer_pdp",
                evidenceField: "product_name"
            ) == nil
        )
    }

    @Test func uniqloE485393IsMultipackWithoutProductSpecificCode() {
        // Provider-faithful PDP fields observed for the regression product.
        // The production parser sees only retailer text; no product ID is used
        // by the structure detector.
        let metadata = UniqloProductMetadataParser().parse(resolved: uniqloResolvedURL(
            productID: "E485393",
            variantID: "E485393-000",
            productName: "BOYS AIRism복서브리프3P",
            extraProductJSON: #""longDescription":"3장 세트""#,
            audience: "KIDS"
        ))
        #expect(metadata.productMetadata.structuredFacts["product_structure"] == "multipack")
        #expect(metadata.productMetadata.structuredFacts["product_structure_source"] == "uniqlo_pdp_entity")

        let observed = metadata.parsedProductInfo(sizes: [coherentSize("120"), coherentSize("130")])
            .normalizedSizes()
        #expect(observed.productMetadata.structuredFacts["product_structure"] == "multipack")
        #expect(observed.productMetadata.structuredFacts["comparison_measurement_contract"] == "single_coherent")
        #expect(observed.productTargetGender == .kids)
    }

    @Test func oneRetailerSizeTableProducesOneCoherentContract() {
        let fact = RetailerComparisonMeasurementContractFact.retailerSizeTable(
            sizes: [coherentSize("S"), coherentSize("M"), coherentSize("L")],
            productStructure: .unknown
        )
        #expect(fact.contract == .singleCoherent)
        #expect(fact.evidence == "one_coherent_imported_measurement_schema")
    }

    @Test func homogeneousMultipackKeepsItsStructureAndGetsOneCoherentContract() {
        let fact = RetailerComparisonMeasurementContractFact.retailerSizeTable(
            sizes: [coherentSize("S"), coherentSize("M"), coherentSize("L")],
            productStructure: .multipack
        )
        #expect(fact.contract == .singleCoherent)
        #expect(RetailerProductStructure.multipack != .single)
    }

    @Test func mixedSetAndMultipleComponentSchemaAreNotCoherent() {
        let mixedSet = RetailerComparisonMeasurementContractFact.retailerSizeTable(
            sizes: [coherentSize("M")],
            productStructure: .set
        )
        #expect(mixedSet.contract == .multipleComponent)

        let disjoint = RetailerComparisonMeasurementContractFact.retailerSizeTable(
            sizes: [
                coherentSize("top", fields: ["shoulder", "chest", "length"]),
                coherentSize("bottom", fields: ["waist", "hip", "inseam"])
            ],
            productStructure: .unknown
        )
        #expect(disjoint.contract == .multipleComponent)
    }

    @Test func missingMeasurementsAreNotAComparisonContract() {
        let fact = RetailerComparisonMeasurementContractFact.retailerSizeTable(
            sizes: [ParsedProductSize(
                name: "M",
                measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0)
            )],
            productStructure: .unknown
        )
        #expect(fact.contract == .absent)
    }

    private func coherentSize(
        _ name: String,
        fields: [String] = ["shoulder", "chest", "length", "sleeve"]
    ) -> ParsedProductSize {
        let records = fields.enumerated().map { index, field in
            ParsedMeasurement(
                value: Double(40 + index),
                measurementCode: .unknown,
                displayKind: .unknown,
                methodSource: "fixture_retailer_size_api",
                inputSource: .importedSizeChart,
                rawCode: field,
                rawLabel: field,
                evidenceLevel: .officialText,
                semanticStatus: .unknownDefinition
            )
        }
        return ParsedProductSize(
            name: name,
            measurements: GarmentMeasurements(shoulder: 45, chest: 50, totalLength: 70, sleeveLength: 60),
            measurementRecords: records
        )
    }

    private func uniqloResolvedURL(
        productID: String,
        variantID: String,
        productName: String,
        extraProductJSON: String = "",
        audience: String = "MEN"
    ) -> ResolvedUniqloURL {
        let separator = extraProductJSON.isEmpty ? "" : ","
        let html = """
        <script type="application/ld+json">
        {"@type":"Product","name":"\(productName)","brand":{"name":"UNIQLO"}}
        </script>
        <script>
        window.__PRELOADED_STATE__ = {
          "entity": {"pdpEntity": {
            "\(variantID)-00": {
              "product": {
                "productId":"\(variantID)",
                "productTypeKr":"니트"\(separator)\(extraProductJSON),
                "breadcrumbs": {
                  "gender":{"id":"57893","locale":"\(audience)"},
                  "class":{"id":"95355","locale":"니트 & 가디건"},
                  "category":{"id":"95357","locale":"니트"},
                  "subcategory":{"id":"100315","locale":"긴팔 니트"}
                }
              }
            }
          }}
        };
        </script>
        """
        return ResolvedUniqloURL(
            originalURL: URL(string: "https://www.uniqlo.com/kr/ko/products/\(variantID)/00")!,
            resolvedURL: URL(string: "https://www.uniqlo.com/kr/ko/products/\(variantID)/00")!,
            productID: productID,
            goodsID: String(productID.dropFirst()),
            apiColorCode: "000",
            imageColorCode: "00",
            productIDWithColorCode: variantID,
            html: html
        )
    }
}
