import Foundation
import Testing
@testable import FitMatch

@MainActor
struct FitMatchSupabaseProductResolverTests {
    @Test func retailerPayloadUsesStableProductAndCategoryEvidence() throws {
        let metadata = ProductMetadata(
            sourceCategoryPath: "상의 > 셔츠 > 긴팔",
            categoryDepth1Code: "001",
            categoryDepth2Code: "001002",
            categoryDepth3Code: "001002003",
            genderCodes: ["MEN"]
        )
        let product = ParsedProductInfo(
            sourceURL: try #require(URL(string: "https://www.musinsa.com/products/123")),
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "옥스포드 셔츠",
            category: .top,
            detailCategory: .shirt,
            sizes: [],
            productID: "123",
            sourceCategoryPath: "상의 > 셔츠 > 긴팔",
            productMetadata: metadata
        )

        let request = try #require(product.fitMatchDatabaseResolutionRequest())
        #expect(request.source == "musinsa")
        #expect(request.externalProductID == "123")
        #expect(request.productName == "옥스포드 셔츠")
        #expect(request.sourceCategoryPath == "상의 > 셔츠 > 긴팔")
        #expect(request.audience == "MEN")
        #expect(request.sourceCategoryCodes == ["001", "001002", "001002003"])
        #expect(request.structuredFacts.isEmpty)
    }

    @Test func typedRetailerFactsAreEncodedAtTheResolutionAndObservationPayloadLevel() throws {
        let metadata = ProductMetadata(
            sourceCategoryPath: "상의 > 반소매 티셔츠",
            categoryDepth1Code: "001",
            categoryDepth2Code: "001001",
            categoryDepth2Name: "반소매 티셔츠",
            structuredFacts: ["size_type": " 반소매티셔츠 "]
        )
        let product = ParsedProductInfo(
            sourceURL: try #require(URL(string: "https://www.musinsa.com/products/123")),
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "반소매 티셔츠",
            category: .top,
            detailCategory: .shortSleeve,
            sizes: [],
            productID: "123",
            sourceCategoryPath: "상의 > 반소매 티셔츠",
            productMetadata: metadata
        )

        let resolution = try #require(product.fitMatchDatabaseResolutionRequest())
        #expect(resolution.structuredFacts == ["size_type": "반소매티셔츠"])
        let resolutionJSON = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(resolution)) as? [String: Any]
        )
        let resolutionFacts = try #require(
            resolutionJSON["structured_facts"] as? [String: Any]
        )
        #expect(resolutionFacts["size_type"] as? String == "반소매티셔츠")

        let observation = try #require(product.fitMatchProductObservationRequest())
        #expect(observation.payload.structuredFacts == ["size_type": "반소매티셔츠"])
        let observationJSON = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(observation)) as? [String: Any]
        )
        let payloadJSON = try #require(observationJSON["payload"] as? [String: Any])
        let observationFacts = try #require(
            payloadJSON["structured_facts"] as? [String: Any]
        )
        #expect(observationFacts["size_type"] as? String == "반소매티셔츠")
    }

    @Test func musinsaActualSizeTypeNameIsForwardedWithoutReplacingNumericSizeType() throws {
        let sourceURL = try #require(URL(string: "https://www.musinsa.com/products/123"))
        var metadata = MusinsaProductMetadata(
            sourceURL: sourceURL,
            productID: "123",
            brandName: "테스트",
            productName: "반소매 티셔츠",
            category: .top,
            detailCategory: .shortSleeve,
            categoryDepth1Name: "상의",
            categoryDepth2Name: "반소매 티셔츠",
            imageURLString: nil,
            price: nil,
            canonicalURLString: sourceURL.absoluteString
        )

        metadata.applyActualSizeProfile(typeNumber: 5, typeName: " 반소매티셔츠 ")
        let parsed = metadata.parsedProductInfo(sizes: [])

        #expect(parsed.productMetadata.sizeType == "5")
        #expect(parsed.productMetadata.structuredFacts["size_type"] == "반소매티셔츠")
        #expect(
            parsed.fitMatchDatabaseResolutionRequest()?.structuredFacts["size_type"]
                == "반소매티셔츠"
        )
    }

    @Test func persistedProductReplayPreservesStructuredFactsExactly() throws {
        let sourceURL = try #require(URL(string: "https://www.musinsa.com/products/123"))
        let metadata = ProductMetadata(
            sourceCategoryPath: "상의 > 반소매 티셔츠",
            categoryDepth1Code: "001",
            categoryDepth2Code: "001001",
            categoryDepth2Name: "반소매 티셔츠",
            structuredFacts: [
                "product_structure": "single",
                "retailer_fit": "oversized / relaxed",
                "size_type": " 반소매티셔츠 "
            ],
            sizeType: "5",
            genderCodes: ["MEN"],
            labelNames: ["단독", "리미티드"]
        )
        let parsed = ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "반소매 티셔츠",
            category: .top,
            detailCategory: .shortSleeve,
            sizes: [],
            productID: "123",
            sourceCategoryPath: metadata.sourceCategoryPath,
            productMetadata: metadata
        )
        let initialRequest = try #require(parsed.fitMatchDatabaseResolutionRequest())
        let persisted = Product(
            name: parsed.productName,
            category: parsed.category,
            productCode: parsed.productID,
            sourceURLString: parsed.canonicalURLString ?? parsed.sourceURL.absoluteString,
            metadata: metadata,
            sourceType: parsed.sourceType,
            sourceName: parsed.sourceName,
            source: .catalog
        )
        let replayRequest = try #require(persisted.fitMatchDatabaseResolutionRequest())
        let storedEnvelope = FitMatchStoredRetailerFacts.decode(persisted.labelNames)

        #expect(replayRequest.structuredFacts == initialRequest.structuredFacts)
        #expect(replayRequest.structuredFacts["size_type"] == "반소매티셔츠")
        #expect(replayRequest.structuredFacts["size_type"] != persisted.sizeType)
        #expect(storedEnvelope.hasVersionedPayload)
        #expect(storedEnvelope.structuredFacts == metadata.structuredFacts)
        #expect(storedEnvelope.labelNames == metadata.labelNames)
    }

    @Test func numericSizeTypeIsNeverSynthesizedAsStructuredAuthorityOnReplay() throws {
        let persisted = Product(
            name: "실측 프로필 상품",
            category: .top,
            productCode: "124",
            sourceURLString: "https://www.musinsa.com/products/124",
            metadata: ProductMetadata(
                sourceCategoryPath: "상의 > 반소매 티셔츠",
                categoryDepth1Code: "001",
                categoryDepth2Code: "001001",
                sizeType: "5",
                labelNames: ["일반 라벨"]
            ),
            sourceType: .marketplace,
            sourceName: "무신사",
            source: .catalog
        )

        let replayRequest = try #require(persisted.fitMatchDatabaseResolutionRequest())
        #expect(replayRequest.structuredFacts.isEmpty)
        #expect(FitMatchStoredRetailerFacts.decode(persisted.labelNames).labelNames == ["일반 라벨"])
    }

    @Test func persistedReplayDoesNotCreateObservedStructureFromStoredName() throws {
        let sourceURL = try #require(URL(string: "https://www.musinsa.com/products/5982920"))
        let metadata = ProductMetadata(
            sourceCategoryPath: "상의 > 반소매 티셔츠",
            categoryDepth1Code: "001",
            categoryDepth2Code: "001001",
            structuredFacts: ["size_type": "반소매티셔츠"]
        )
        let parsed = ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "티셔츠 팬츠 세트",
            category: .top,
            detailCategory: .shortSleeve,
            sizes: [],
            productID: "5982920",
            sourceCategoryPath: metadata.sourceCategoryPath,
            productMetadata: metadata
        )
        let persisted = Product(
            name: parsed.productName,
            category: parsed.category,
            productCode: parsed.productID,
            sourceURLString: sourceURL.absoluteString,
            metadata: metadata,
            sourceType: parsed.sourceType,
            sourceName: parsed.sourceName,
            source: .catalog
        )

        let initialFacts = try #require(parsed.fitMatchDatabaseResolutionRequest()).structuredFacts
        let replayFacts = try #require(persisted.fitMatchDatabaseResolutionRequest()).structuredFacts
        #expect(initialFacts == ["size_type": "반소매티셔츠"])
        #expect(replayFacts == initialFacts)
        #expect(replayFacts["product_structure"] == nil)
    }

    @Test func existingSetSemanticsEmitExplicitRetailerStructureWithoutGarmentInference() throws {
        let sourceURL = try #require(URL(string: "https://www.musinsa.com/products/5982920"))
        let namedSet = ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "티셔츠 팬츠 세트",
            category: .top,
            detailCategory: .shortSleeve,
            sizes: [],
            productID: "5982920",
            sourceCategoryPath: "상의 > 반소매 티셔츠"
        )
        #expect(namedSet.fitMatchDatabaseResolutionRequest()?.structuredFacts["product_structure"] == nil)
        #expect(namedSet.fitMatchProductObservationRequest()?.payload
            .structuredFacts["product_structure"] == nil)

        let explicitRetailerSet = ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "공식 구성 상품",
            category: .top,
            detailCategory: .other,
            sizes: [],
            productID: "5982920",
            sourceCategoryPath: "상의 > 상하의 세트",
            sourceCategoryDepth2: "상하의 세트",
            productMetadata: ProductMetadata(structuredFacts: [
                "product_structure": "set",
                "product_structure_source": "musinsa_official_category",
                "product_structure_evidence": "official_category:top_bottom_set"
            ])
        )
        #expect(
            explicitRetailerSet.fitMatchDatabaseResolutionRequest()?.structuredFacts["product_structure"]
                == "set"
        )
    }

    @Test func productObservationPreservesRawSizeChartEvidence() throws {
        let observedAt = try #require(
            ISO8601DateFormatter().date(from: "2026-08-19T03:00:00Z")
        )
        let measurement = ParsedMeasurement(
            value: 55.5,
            measurementCode: .chestWidthUniqloBodyWidth,
            displayKind: .chest,
            methodSource: "uniqlo_official_size_chart",
            inputSource: .importedSizeChart,
            mappingVersion: "uniqlo_kr_size_chart_mapping_v7",
            rawCode: "chest-width",
            rawLabel: "가슴너비",
            rawInfo: "official_api",
            rawValueText: "55.5",
            evidenceLevel: .officialText,
            semanticStatus: .mapped
        )
        let metadata = ProductMetadata(
            sourceCategoryPath: "셔츠 & 블라우스 > 긴팔",
            categoryDepth1Code: "95354",
            categoryDepth2Code: "95362",
            categoryDepth3Code: "95381",
            genderCodes: ["MEN"],
            checkedColorName: "09"
        )
        let product = ParsedProductInfo(
            sourceURL: try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/E492123")),
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            brandName: "유니클로",
            productName: "데님릴렉스셔츠재킷",
            category: .top,
            detailCategory: .shirt,
            sizes: [
                ParsedProductSize(
                    name: "M",
                    measurements: GarmentMeasurements(
                        shoulder: 0,
                        chest: 55.5,
                        totalLength: 0,
                        sleeveLength: 0
                    ),
                    measurementRecords: [measurement]
                )
            ],
            productID: "E492123",
            sourceCategoryPath: "셔츠 & 블라우스 > 긴팔",
            productMetadata: metadata
        )

        let request = try #require(
            product.fitMatchProductObservationRequest(observedAt: observedAt)
        )
        #expect(request.payload.source == "uniqlo")
        #expect(request.payload.externalProductID == "E492123")
        #expect(request.payload.sourceCategoryCodes == ["95354", "95362", "95381"])
        let variant = try #require(request.payload.variants.first)
        #expect(variant.externalVariantID == "09")
        let size = try #require(variant.sizes.first)
        #expect(size.sizeIdentity == "M")
        let raw = try #require(size.measurements.first)
        #expect(raw.rawCode == "chest-width")
        #expect(raw.rawLabel == "가슴너비")
        #expect(raw.rawValue == 55.5)
        #expect(raw.evidence["mapping_version"] == "uniqlo_kr_size_chart_mapping_v7")
        #expect(request.payload.rawPayload["parser_provenance_available"] == "false")
        #expect(request.payload.rawPayload["parser_code"] == "legacy_unknown")
        #expect(request.payload.structuredFacts.isEmpty)
    }

    @Test func parserServiceRecordsTypedProvenanceInObservationPayload() async throws {
        let product = ParsedProductInfo(
            sourceURL: try #require(URL(string: "https://www.musinsa.com/products/123")),
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "반팔 티셔츠",
            category: .top,
            detailCategory: .shortSleeve,
            sizes: [
                ParsedProductSize(
                    name: "M",
                    measurements: GarmentMeasurements(
                        shoulder: 48,
                        chest: 54,
                        totalLength: 70,
                        sleeveLength: 24
                    )
                )
            ],
            productID: "123",
            sourceCategoryPath: "상의 > 반소매 티셔츠"
        )
        let parser = DatabaseAuthorityParserStub(product: product)
        let service = ProductURLParserService(musinsaParser: parser, uniqloParser: parser)

        let parsed = try await service.parse(urlString: product.sourceURL.absoluteString)
        #expect(parsed.parserProvenance?.parserCode == "musinsa")
        #expect(parsed.parserProvenance?.parserVersion == nil)
        #expect(parsed.parserProvenance?.fieldSources["source_url"] == "user_supplied_url")
        #expect(parsed.parserProvenance?.fieldSources["source_category_path"] == "retailer_parser")
        #expect(parsed.parserProvenance?.fieldSources["sizes"] == "retailer_parser")

        let request = try #require(parsed.fitMatchProductObservationRequest())
        #expect(request.payload.rawPayload["parser_provenance_available"] == "true")
        #expect(request.payload.rawPayload["parser_provenance_contract"] == "ios-parser-provenance-v1")
        #expect(request.payload.rawPayload["parser_code"] == "musinsa")
        #expect(request.payload.rawPayload["parser_version"] == "not_declared")
        let fieldSources = try #require(request.payload.rawPayload["parser_field_sources"])
        #expect(fieldSources.contains("\"product_id\":\"retailer_parser\""))
        #expect(fieldSources.contains("\"source_url\":\"user_supplied_url\""))
    }

    @Test func zaraObservationKeepsStyleVariantAndInternalProductIDsSeparate() throws {
        let metadata = ProductMetadata(
            styleNo: "04166166",
            externalVariantID: "545490346",
            externalProductReference: "04166166-I2026",
            sourceCategoryPath: "ZARA > 남성 > 셔츠 > B. Camisería",
            categoryDepth1Code: "MAN",
            categoryDepth2Code: "MAN:셔츠",
            genderCodes: ["MEN"]
        )
        let product = ParsedProductInfo(
            sourceURL: try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346")),
            sourceType: .officialStore,
            sourceName: "ZARA 공식몰",
            brandName: "ZARA",
            productName: "레귤러 핏 셔츠",
            category: .top,
            detailCategory: .shirt,
            sizes: [],
            productID: "545486853",
            sourceCategoryPath: "ZARA > 남성 > 셔츠 > B. Camisería",
            productMetadata: metadata
        )

        let request = try #require(product.fitMatchProductObservationRequest())
        #expect(request.payload.source == "zara")
        #expect(request.payload.externalProductID == "545486853")
        #expect(request.payload.variants.first?.externalVariantID == "545490346")
        #expect(request.payload.rawPayload["style_number"] == "04166166")
        #expect(request.payload.rawPayload["external_variant_id"] == "545490346")
        #expect(request.payload.rawPayload["external_product_reference"] == "04166166-I2026")
        #expect(request.payload.rawPayload["internal_product_id"] == "545486853")
    }

    @Test func uniqloBraTopKeepsUnderwearFamilyInLocalSnapshot() throws {
        let product = ParsedProductInfo(
            sourceURL: try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/E482202-000/01")),
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
            brandName: "유니클로",
            productName: "립브라탑(컬러블록)",
            category: .top,
            detailCategory: .womenBra,
            sizes: [],
            productID: "E482202",
            sourceCategoryPath: "티셔츠 & UT > 브라탑 > 코튼"
        )

        let local = product.fitMatchLocalClassificationSnapshot()
        #expect(local.categoryCode == "underwear")
        #expect(local.detailCode == "women_bra")
        #expect(local.familyCode == "underwear")
        #expect(local.lengthCode == "unknown")
        #expect(local.requiresUserConfirmation == false)
    }

    @Test func shoppingProductUsesServerConfirmedTupleOverConflictingLocalInference() async throws {
        let parsed = try Self.authorityTestProduct(
            source: "musinsa",
            externalProductID: "123",
            localCategory: .bottom,
            localDetail: .longPants
        )
        let fixture = DatabaseAuthorityFixture(
            source: "musinsa",
            externalProductID: "123",
            status: .confirmed,
            categoryCode: "tops",
            detailCode: "short_sleeve",
            familyCode: "tshirt",
            lengthCode: "short_sleeve"
        )
        let remote = DatabaseAuthorityRemoteStub(
            resolutions: [fixture.resolution()],
            observations: [],
            runtimes: [fixture.runtime]
        )
        let viewModel = Self.authorityViewModel(product: parsed, remote: remote)

        #expect(await viewModel.loadProductInfoFromURL())
        #expect(viewModel.hasServerConfirmedAuthority)
        #expect(viewModel.category == .top)
        #expect(viewModel.detailCategory == .shortSleeve)

        let product = try #require(
            viewModel.makeProductForClosetRegistration(brand: nil)
        )
        #expect(product.category == .top)
        #expect(product.categoryCode == "tops")
        #expect(product.normalizedProductTypeCode == "short_sleeve")
        #expect(product.garmentTypeRawValue == "tshirt")
        #expect(product.sleeveTypeRawValue == "short_sleeve")
        #expect(product.classificationAuthorityProvenance == .serverConfirmed)
        #expect(product.canonicalEligibility == true)
    }

    @Test func reviewAndNotComparableServerResultsNeverBecomeEligibleProducts() async throws {
        let scenarios: [(
            status: FitMatchServerProductAuthorityStatus,
            provenance: FitMatchClassificationAuthorityProvenance
        )] = [
            (.reviewRequired, .serverReviewRequired),
            (.notComparable, .serverNotComparable)
        ]

        for scenario in scenarios {
            let externalID = scenario.status.rawValue
            let parsed = try Self.authorityTestProduct(
                source: "musinsa",
                externalProductID: externalID,
                localCategory: .top,
                localDetail: .shortSleeve
            )
            let fixture = DatabaseAuthorityFixture(
                source: "musinsa",
                externalProductID: externalID,
                status: scenario.status
            )
            let remote = DatabaseAuthorityRemoteStub(
                resolutions: [fixture.resolution()],
                observations: [],
                runtimes: [fixture.runtime]
            )
            let viewModel = Self.authorityViewModel(product: parsed, remote: remote)

            #expect(!(await viewModel.loadProductInfoFromURL()))
            #expect(!viewModel.hasServerConfirmedAuthority)
            let product = try #require(
                viewModel.makeProductForClosetRegistration(brand: nil)
            )
            #expect(product.classificationAuthorityProvenance == scenario.provenance)
            #expect(product.canonicalEligibility == false)
        }
    }

    @Test func networkAndRejectedPromotionRemainUnavailableWithoutLocalConfirmation() async throws {
        let networkProduct = try Self.authorityTestProduct(
            source: "musinsa",
            externalProductID: "network-failure",
            localCategory: .top,
            localDetail: .shortSleeve
        )
        let networkRemote = DatabaseAuthorityRemoteStub(
            resolutions: [],
            observations: [],
            runtimes: [],
            resolveFailure: .network
        )
        let networkViewModel = Self.authorityViewModel(
            product: networkProduct,
            remote: networkRemote
        )

        #expect(!(await networkViewModel.loadProductInfoFromURL()))
        let networkResult = try #require(
            networkViewModel.makeProductForClosetRegistration(brand: nil)
        )
        #expect(networkResult.classificationAuthorityProvenance == .serverUnavailable)
        #expect(networkResult.canonicalEligibility == false)

        let promotionProduct = try Self.authorityTestProduct(
            source: "musinsa",
            externalProductID: "promotion-failure",
            localCategory: .top,
            localDetail: .shortSleeve
        )
        let fixture = DatabaseAuthorityFixture(
            source: "musinsa",
            externalProductID: "promotion-failure",
            status: .confirmed,
            categoryCode: "tops",
            detailCode: "short_sleeve",
            familyCode: "tshirt",
            lengthCode: "short_sleeve"
        )
        let promotionRemote = DatabaseAuthorityRemoteStub(
            resolutions: [fixture.resolution(catalogState: "new")],
            observations: [fixture.observation(status: "rejected")],
            runtimes: []
        )
        let promotionViewModel = Self.authorityViewModel(
            product: promotionProduct,
            remote: promotionRemote
        )

        #expect(!(await promotionViewModel.loadProductInfoFromURL()))
        let promotionResult = try #require(
            promotionViewModel.makeProductForClosetRegistration(brand: nil)
        )
        #expect(promotionResult.classificationAuthorityProvenance == .serverUnavailable)
        #expect(promotionResult.canonicalEligibility == false)
        #expect(await promotionRemote.observationCallCount == 1)
        #expect(await promotionRemote.runtimeCallCount == 0)
    }

    @Test func shoppingProductGoldThreePersistExactServerTuples() async throws {
        let gold: [(id: String, detail: String, family: String)] = [
            ("E482514", "short_sleeve", "tshirt"),
            ("E454311", "base_layer_top", "base_layer_top"),
            ("E456567", "base_layer_top", "base_layer_top")
        ]

        for expected in gold {
            let parsed = try Self.authorityTestProduct(
                source: "uniqlo",
                externalProductID: expected.id,
                localCategory: .bottom,
                localDetail: .longPants
            )
            let fixture = DatabaseAuthorityFixture(
                source: "uniqlo",
                externalProductID: expected.id,
                status: .confirmed,
                categoryCode: "tops",
                detailCode: expected.detail,
                familyCode: expected.family,
                lengthCode: "short_sleeve"
            )
            let remote = DatabaseAuthorityRemoteStub(
                resolutions: [fixture.resolution()],
                observations: [],
                runtimes: [fixture.runtime]
            )
            let viewModel = Self.authorityViewModel(product: parsed, remote: remote)

            #expect(await viewModel.loadProductInfoFromURL())
            let product = try #require(
                viewModel.makeProductForClosetRegistration(brand: nil)
            )
            #expect(product.categoryCode == "tops")
            #expect(product.normalizedProductTypeCode == expected.detail)
            #expect(product.garmentTypeRawValue == expected.family)
            #expect(product.sleeveTypeRawValue == "short_sleeve")
            #expect(product.classificationAuthorityProvenance == .serverConfirmed)
            #expect(product.canonicalEligibility == true)
        }
    }

    @Test func referenceCandidateContractDecodesDatabasePolicyEvidence() throws {
        let closetID = UUID()
        let payload = Data(
            """
            {
              "state": "manual_selection",
              "automatic_count": 0,
              "manual_count": 1,
              "structural_count": 1,
              "policy_version": "db-comparison-2026-08-18-v2",
              "candidates": [{
                "closet_item_id": "\(closetID.uuidString)",
                "product_name": "내 셔츠",
                "size_name": "M",
                "is_reference": true,
                "automatic_ready": false,
                "manual_ready": true,
                "measurement_overlap_count": 3,
                "automatic_compatibility": {
                  "allowed": false,
                  "level": "incompatible",
                  "reason": "length_mismatch"
                },
                "manual_compatibility": {
                  "allowed": true,
                  "level": "extended",
                  "excluded_measurements": ["sleeve_length"],
                  "minimum_common_measurements": 2
                }
              }]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(FitMatchReferenceCandidatesResponse.self, from: payload)
        #expect(response.state == "manual_selection")
        #expect(response.manualCount == 1)
        #expect(response.policyVersion == "db-comparison-2026-08-18-v2")
        let candidate = try #require(response.candidates.first)
        #expect(candidate.closetItemID == closetID)
        #expect(candidate.measurementOverlapCount == 3)
        #expect(candidate.manualCompatibility.allowed)
        #expect(candidate.manualCompatibility.excludedMeasurements == ["sleeve_length"])
    }

    @Test func productRuntimeContractDecodesSizeIDsAndCanonicalMeasurements() throws {
        let productID = UUID()
        let classificationID = UUID()
        let variantID = UUID()
        let sizeID = UUID()
        let payload = Data(
            """
            {
              "runtime_state": "ready",
              "comparison_ready": true,
              "product": {
                "product_id": "\(productID.uuidString)",
                "source": "uniqlo",
                "external_product_id": "E492123",
                "product_name": "데님릴렉스셔츠재킷",
                "canonical_url": "https://example.com/E492123",
                "audience": "MEN",
                "source_category_path": "상의 > 셔츠",
                "source_category_codes": ["001", "002"],
                "image_url": null,
                "lifecycle_status": "active",
                "input_fingerprint": "fingerprint"
              },
              "classification": {
                "classification_id": "\(classificationID.uuidString)",
                "category_code": "tops",
                "detail_code": "shirt",
                "family_code": "shirt",
                "length_code": "long_sleeve",
                "body_length_code": null,
                "status": "confirmed",
                "method": "verified_path_profile",
                "confidence": 1.0,
                "requires_user_confirmation": false,
                "taxonomy_policy_version": "taxonomy-v1",
                "decision_version": "decision-v1"
              },
              "variants": [{
                "variant_id": "\(variantID.uuidString)",
                "external_variant_id": "01",
                "variant_name": "BLACK",
                "color_code": "09",
                "color_name": "BLACK",
                "sizes": [{
                  "product_size_id": "\(sizeID.uuidString)",
                  "external_size_id": "004",
                  "size_label": "M",
                  "normalized_size_label": "M",
                  "display_order": 2,
                  "stock_status": "in_stock",
                  "measurements": [{
                    "measurement_code": "chest_width",
                    "raw_label": "몸폭",
                    "raw_value": 55.0,
                    "raw_unit": "cm",
                    "normalized_value": 55.0,
                    "normalized_unit": "cm",
                    "comparison_basis": "width",
                    "is_comparable": true,
                    "exclusion_reason": null,
                    "policy_version": "measurement-v1"
                  }]
                }]
              }]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(FitMatchProductRuntimeResponse.self, from: payload)
        #expect(response.runtimeState == "ready")
        #expect(response.product.productID == productID)
        #expect(response.classification?.bodyLengthCode == nil)
        let size = try #require(response.variants.first?.sizes.first)
        #expect(size.productSizeID == sizeID)
        #expect(size.measurements.first?.measurementCode == "chest_width")
        #expect(size.measurements.first?.normalizedValue == 55)
    }

    @Test func beginAndCompleteContractsDecodeTransactionalIdentifiers() throws {
        let runID = UUID()
        let beginPayload = Data(
            """
            {
              "run_id": "\(runID.uuidString)",
              "status": "pending",
              "compatibility": {
                "allowed": true,
                "level": "direct",
                "minimum_common_measurements": 3
              }
            }
            """.utf8
        )
        let completePayload = Data(
            """
            {
              "run_id": "\(runID.uuidString)",
              "status": "completed",
              "result_count": 4
            }
            """.utf8
        )

        let begin = try JSONDecoder().decode(FitMatchBeginComparisonResponse.self, from: beginPayload)
        let complete = try JSONDecoder().decode(FitMatchCompleteComparisonResponse.self, from: completePayload)
        #expect(begin.runID == runID)
        #expect(begin.status == "pending")
        #expect(begin.compatibility.minimumCommonMeasurements == 3)
        #expect(complete.runID == runID)
        #expect(complete.status == "completed")
        #expect(complete.resultCount == 4)
    }

    @Test func authenticatedClosetContractDecodesCanonicalSnapshotAndMeasurements() throws {
        let closetItemID = UUID()
        let clientItemID = UUID()
        let productID = UUID()
        let payload = Data(
            """
            {
              "state": "ready",
              "items": [{
                "closet_item_id": "\(closetItemID.uuidString)",
                "client_item_id": "\(clientItemID.uuidString)",
                "product_id": "\(productID.uuidString)",
                "external_product_id": "E492123",
                "product_audience": "MEN",
                "source_category_codes": ["001", "002"],
                "variant_id": null,
                "product_size_id": null,
                "brand": "유니클로",
                "product_name": "데님릴렉스셔츠재킷",
                "size_name": "M",
                "gender_code": "MEN",
                "source": "uniqlo",
                "source_category_path": "상의 > 셔츠",
                "product_url": "https://example.com/E492123",
                "image_url": null,
                "measurements": {"chest_width": 55.0},
                "measurement_records": [{
                  "value": 55.0,
                  "unit": "cm",
                  "measurement_code": "chest_width",
                  "display_kind": "width",
                  "method_source": "retailer_size_chart",
                  "method_profile": null,
                  "input_source": "api",
                  "standard_version": "measurement-v1",
                  "mapping_version": "uniqlo-v1",
                  "raw_code": "body-width",
                  "raw_label": "몸폭",
                  "raw_info": null,
                  "raw_value_text": "55",
                  "evidence_level": "official",
                  "semantic_status": "confirmed"
                }],
                "fit_memo": "잘 맞음",
                "fit_preference_code": "regular",
                "satisfaction": 5,
                "is_reference": true,
                "classification_status": "confirmed",
                "classification_source": "canonical_product_decision",
                "category_code": "tops",
                "detail_code": "shirt",
                "canonical_category_code": "tops",
                "canonical_detail_code": "shirt",
                "family_code": "shirt",
                "length_code": "long_sleeve",
                "body_length_code": null,
                "classification_snapshot": {
                  "category_code": "tops",
                  "detail_code": "shirt",
                  "body_length_code": null
                },
                "client_snapshot": {"source": "ios"},
                "client_created_at": "2026-08-19T08:00:00Z",
                "client_updated_at": "2026-08-19T08:00:00Z",
                "sync_revision": 2,
                "created_at": "2026-08-19T08:00:00Z",
                "updated_at": "2026-08-19T08:01:00Z"
              }]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(FitMatchClosetItemsResponse.self, from: payload)
        #expect(response.state == "ready")
        let item = try #require(response.items.first)
        #expect(item.closetItemID == closetItemID)
        #expect(item.clientItemID == clientItemID)
        #expect(item.productID == productID)
        #expect(item.externalProductID == "E492123")
        #expect(item.sourceCategoryCodes == ["001", "002"])
        #expect(item.measurements["chest_width"] == 55)
        #expect(item.measurementRecords.first?.rawLabel == "몸폭")
        #expect(item.classificationSnapshot["category_code"] == "tops")
        let bodyLengthEntry = item.classificationSnapshot["body_length_code"]
        #expect(bodyLengthEntry != nil)
        #expect(bodyLengthEntry! == nil)
        #expect(item.syncRevision == 2)
    }

    @Test func linkClosetPreparationUsesExactServerTupleInsteadOfLocalParserHint() async throws {
        let parsed = try Self.authorityTestProduct(
            source: "musinsa",
            externalProductID: "link-server-wins",
            localCategory: .bottom,
            localDetail: .longPants
        )
        let fixture = DatabaseAuthorityFixture(
            source: "musinsa",
            externalProductID: "link-server-wins",
            status: .confirmed,
            categoryCode: "tops",
            detailCode: "short_sleeve",
            familyCode: "tshirt",
            lengthCode: "short_sleeve"
        )
        let remote = DatabaseAuthorityRemoteStub(
            resolutions: [fixture.resolution()],
            observations: [],
            runtimes: [fixture.runtime]
        )
        let viewModel = Self.authorityViewModel(product: parsed, remote: remote)

        #expect(await viewModel.loadProductInfoFromURL())
        let preparation = LinkClosetRegistrationPreparation.make(
            from: viewModel,
            brand: nil
        )
        let product = try #require(preparation.parsedProduct)
        #expect(preparation.partialProduct == nil)
        #expect(product.categoryCode == "tops")
        #expect(product.normalizedProductTypeCode == "short_sleeve")
        #expect(product.garmentTypeRawValue == "tshirt")
        #expect(product.sleeveTypeRawValue == "short_sleeve")
        #expect(product.classificationAuthorityProvenance == .serverConfirmed)
        #expect(product.canonicalEligibility == true)
    }

    @Test func linkClosetPreparationKeepsReviewRequiredFailClosed() async throws {
        let parsed = try Self.authorityTestProduct(
            source: "musinsa",
            externalProductID: "link-review",
            localCategory: .top,
            localDetail: .shortSleeve
        )
        let fixture = DatabaseAuthorityFixture(
            source: "musinsa",
            externalProductID: "link-review",
            status: .reviewRequired
        )
        let remote = DatabaseAuthorityRemoteStub(
            resolutions: [fixture.resolution()],
            observations: [],
            runtimes: [fixture.runtime]
        )
        let viewModel = Self.authorityViewModel(product: parsed, remote: remote)

        #expect(!(await viewModel.loadProductInfoFromURL()))
        let preparation = LinkClosetRegistrationPreparation.make(
            from: viewModel,
            brand: nil
        )
        let product = try #require(preparation.parsedProduct)
        #expect(product.classificationAuthorityProvenance == .serverReviewRequired)
        #expect(product.canonicalEligibility == false)
        #expect(preparation.errorMessage != nil)
    }

    @Test func reviewRequiredLinkKeepsParserFactsAndExactRuntimeSizeIdentity() async throws {
        let parsed = try Self.authorityTestProduct(
            source: "musinsa",
            externalProductID: "link-review-exact-size",
            localCategory: .top,
            localDetail: .shortSleeve
        )
        let productID = UUID()
        let variantID = UUID()
        let sizeID = UUID()
        let classification = FitMatchDatabaseClassification(
            classificationID: UUID(),
            categoryCode: nil,
            detailCode: nil,
            garmentTypeCode: nil,
            familyCode: nil,
            lengthCode: nil,
            bodyLengthCode: nil,
            status: "review_required",
            method: "needs_user_closet_tuple",
            authorityStatus: nil,
            confidence: nil,
            requiresUserConfirmation: true,
            taxonomyPolicyVersion: "test-vnext",
            decisionVersion: "test-review"
        )
        let runtime = FitMatchProductRuntimeResponse(
            runtimeState: "classification_required",
            comparisonReady: false,
            product: FitMatchRuntimeProduct(
                productID: productID,
                source: "musinsa",
                externalProductID: "link-review-exact-size",
                productName: parsed.productName,
                canonicalURL: parsed.sourceURL.absoluteString,
                audience: "MEN",
                sourceCategoryPath: parsed.sourceCategoryPath,
                sourceCategoryCodes: ["001", "001001"],
                imageURL: nil,
                lifecycleStatus: "active",
                inputFingerprint: "review-runtime"
            ),
            classification: classification,
            variants: [
                FitMatchRuntimeVariant(
                    variantID: variantID,
                    externalVariantID: "__default__",
                    variantName: nil,
                    colorCode: nil,
                    colorName: nil,
                    sizes: [
                        FitMatchRuntimeSize(
                            productSizeID: sizeID,
                            externalSizeID: "m-source-key",
                            sizeLabel: "M",
                            normalizedSizeLabel: "M",
                            displayOrder: 0,
                            stockStatus: "UNKNOWN",
                            measurements: []
                        )
                    ]
                )
            ]
        )
        let resolution = FitMatchProductResolutionResponse(
            productID: productID,
            intakeRequestID: nil,
            catalogState: "current",
            categoryEvidenceMatches: true,
            authorityPersisted: true,
            classification: classification,
            comparisonReady: false
        )
        let remote = DatabaseAuthorityRemoteStub(
            resolutions: [resolution],
            observations: [],
            runtimes: [runtime]
        )
        let viewModel = Self.authorityViewModel(product: parsed, remote: remote)

        // The legacy Bool remains a comparison-authority gate, but parser
        // facts are independently available for the link registration UI.
        #expect(!(await viewModel.loadProductInfoFromURL()))
        #expect(viewModel.hasLoadedProductInfo)
        guard case .reviewRequired = viewModel.serverAuthorityState else {
            Issue.record("Expected REVIEW_REQUIRED server state")
            return
        }

        let preparation = LinkClosetRegistrationPreparation.make(
            from: viewModel,
            brand: nil
        )
        let product = try #require(preparation.parsedProduct)
        let displayedSize = try #require(product.sizes.first)
        #expect(preparation.serverRegistrationContext.classificationState == .reviewRequired)
        #expect(
            preparation.serverRegistrationContext.identity(for: displayedSize.id)
                == FitMatchClosetRegistrationServerIdentity(
                    productID: productID,
                    productVariantID: variantID,
                    productSizeID: sizeID
                )
        )
    }

    @Test func nonComparableAndUnavailableLinksKeepFactsVisibleButBlockRegistration() async throws {
        let nonComparableParsed = try Self.authorityTestProduct(
            source: "musinsa",
            externalProductID: "link-not-applicable",
            localCategory: .top,
            localDetail: .shortSleeve
        )
        let nonComparableFixture = DatabaseAuthorityFixture(
            source: "musinsa",
            externalProductID: "link-not-applicable",
            status: .notComparable
        )
        let nonComparableViewModel = Self.authorityViewModel(
            product: nonComparableParsed,
            remote: DatabaseAuthorityRemoteStub(
                resolutions: [nonComparableFixture.resolution()],
                observations: [],
                runtimes: [nonComparableFixture.runtime]
            )
        )

        #expect(!(await nonComparableViewModel.loadProductInfoFromURL()))
        #expect(nonComparableViewModel.hasLoadedProductInfo)
        let nonComparablePreparation = LinkClosetRegistrationPreparation.make(
            from: nonComparableViewModel,
            brand: nil
        )
        #expect(nonComparablePreparation.parsedProduct != nil)
        #expect(
            nonComparablePreparation.serverRegistrationContext.classificationState
                == .notApplicable
        )
        #expect(
            nonComparablePreparation.serverRegistrationContext.registrationBlockMessage
                == "현재 이 상품은 옷장 등록 대상이 아닙니다."
        )

        let unavailableParsed = try Self.authorityTestProduct(
            source: "musinsa",
            externalProductID: "link-server-unavailable",
            localCategory: .top,
            localDetail: .shortSleeve
        )
        let unavailableViewModel = Self.authorityViewModel(
            product: unavailableParsed,
            remote: DatabaseAuthorityRemoteStub(
                resolutions: [],
                observations: [],
                runtimes: [],
                resolveFailure: .network
            )
        )

        #expect(!(await unavailableViewModel.loadProductInfoFromURL()))
        #expect(unavailableViewModel.hasLoadedProductInfo)
        let unavailablePreparation = LinkClosetRegistrationPreparation.make(
            from: unavailableViewModel,
            brand: nil
        )
        #expect(unavailablePreparation.parsedProduct != nil)
        #expect(
            unavailablePreparation.serverRegistrationContext.classificationState
                == .unavailable
        )
        #expect(
            unavailablePreparation.serverRegistrationContext.registrationBlockMessage
                == "서버 연결을 확인한 뒤 다시 저장해 주세요."
        )
    }

    @Test func vNextClosetMutationUsesExactIdentityAndNestedOverrideOnlyWhenExplicit() throws {
        let product = Product(
            id: UUID(),
            name: "서버 기준 티셔츠",
            category: .top,
            productCode: "EXACT-IDENTITY",
            sourceURLString: "https://www.musinsa.com/products/EXACT-IDENTITY",
            metadata: ProductMetadata(genderCodes: ["MEN"]),
            sourceType: .marketplace,
            sourceName: "무신사",
            source: .catalog
        )
        product.garmentTypeRawValue = "tshirt"
        product.sleeveTypeRawValue = "short_sleeve"
        product.markClassificationAuthority(.serverConfirmed)
        let displaySize = ProductSize(
            id: UUID(),
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 47,
                chest: 53,
                totalLength: 69,
                sleeveLength: 23
            ),
            product: product
        )
        product.sizes = [displaySize]
        let exactIdentity = FitMatchClosetRegistrationServerIdentity(
            productID: UUID(),
            productVariantID: UUID(),
            productSizeID: UUID()
        )
        let clientItemID = UUID()
        let confirmed = FitMatchComparedProductClosetRegistration.SaveRequest(
            clientItemID: clientItemID,
            product: product,
            selectedSize: displaySize,
            serverIdentity: exactIdentity,
            activeClosetItems: [],
            brandName: "테스트",
            gender: .men,
            genderCode: "male",
            productName: product.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "short_sleeve",
            isRepresentative: false,
            didExplicitlyChangeClassification: false,
            didExplicitlySelectClosetClassification: false
        )
        let confirmedSubmission = try FitMatchComparedProductClosetRegistration
            .prepareServerFirstSubmission(confirmed)
        #expect(confirmedSubmission.remoteRequest.clientItemID == clientItemID)
        #expect(confirmedSubmission.remoteRequest.productID == exactIdentity.productID)
        #expect(confirmedSubmission.remoteRequest.productVariantID == exactIdentity.productVariantID)
        #expect(confirmedSubmission.remoteRequest.productSizeID == exactIdentity.productSizeID)
        let confirmedJSON = try #require(
            JSONSerialization.jsonObject(
                with: FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
                    confirmedSubmission.remoteRequest
                )
            ) as? [String: Any]
        )
        #expect(confirmedJSON["closet_classification_override"] == nil)
        #expect(confirmedJSON["product_id"] as? String == exactIdentity.productID.uuidString)
        #expect(confirmedJSON["product_variant_id"] as? String == exactIdentity.productVariantID.uuidString)
        #expect(confirmedJSON["product_size_id"] as? String == exactIdentity.productSizeID.uuidString)

        product.markClassificationAuthority(.serverReviewRequired)
        let reviewExplicit = FitMatchComparedProductClosetRegistration.SaveRequest(
            clientItemID: UUID(),
            product: product,
            selectedSize: displaySize,
            serverIdentity: exactIdentity,
            activeClosetItems: [],
            brandName: "테스트",
            gender: .men,
            genderCode: "male",
            productName: product.name,
            category: .top,
            categoryCode: "tops",
            detailCategory: .shortSleeve,
            detailCategoryCode: "short_sleeve",
            isRepresentative: false,
            didExplicitlyChangeClassification: true,
            didExplicitlySelectClosetClassification: true
        )
        let reviewSubmission = try FitMatchComparedProductClosetRegistration
            .prepareServerFirstSubmission(reviewExplicit)
        let reviewJSON = try #require(
            JSONSerialization.jsonObject(
                with: FitMatchSupabaseDomainClient.encodedVNextClosetPayload(
                    reviewSubmission.remoteRequest
                )
            ) as? [String: Any]
        )
        let override = try #require(
            reviewJSON["closet_classification_override"] as? [String: Any]
        )
        #expect(override["audience_code"] as? String == "MEN")
        #expect(override["category_code"] as? String == "tops")
        #expect(override["garment_type_code"] as? String == "tshirt")
        #expect(override["sleeve_length_code"] as? String == "short_sleeve")
        #expect(override["lower_length_code"] is NSNull)
        #expect(override["body_length_code"] is NSNull)
    }

    @Test func linkedRegistrationKeepsDuplicateDisplayLabelsAsDistinctExactSizes() {
        let product = Product(name: "동일 라벨 variant", category: .top)
        let firstM = ProductSize(
            id: UUID(),
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 46,
                chest: 51,
                totalLength: 68,
                sleeveLength: 22
            ),
            product: product
        )
        let secondM = ProductSize(
            id: UUID(),
            name: "M",
            measurements: GarmentMeasurements(
                shoulder: 48,
                chest: 54,
                totalLength: 70,
                sleeveLength: 23
            ),
            product: product
        )

        #expect(
            AddComparedProductToClosetSheet.initialSelectedSizeID(
                recommendedSize: secondM,
                productSizes: [firstM, secondM],
                allowsLabelFallback: false
            ) == secondM.id
        )
    }

    @Test func vNextClosetListKeepsBothPersonalServerSourcesAsManualAuthority() {
        #expect(
            FitMatchSupabaseDomainClient.closetClassificationSource(
                from: "USER_EXPLICIT"
            ) == "manual_override"
        )
        #expect(
            FitMatchSupabaseDomainClient.closetClassificationSource(
                from: "USER_EDITED"
            ) == "manual_override"
        )
        #expect(
            FitMatchSupabaseDomainClient.closetClassificationSource(
                from: "RETAILER_SNAPSHOT"
            ) == "product_metadata"
        )
    }

    @Test func linkClosetMeasurementRecoveryRequiresServerConfirmedAuthority() async throws {
        var parsed = try Self.authorityTestProduct(
            source: "uniqlo",
            externalProductID: "E499998",
            localCategory: .bottom,
            localDetail: .longPants
        )
        parsed.sizes = []
        parsed.recoveryAction = .enterMeasurementsManually
        let fixture = DatabaseAuthorityFixture(
            source: "uniqlo",
            externalProductID: "E499998",
            status: .confirmed,
            categoryCode: "tops",
            detailCode: "base_layer_top",
            familyCode: "base_layer_top",
            lengthCode: "short_sleeve"
        )
        let remote = DatabaseAuthorityRemoteStub(
            resolutions: [fixture.resolution()],
            observations: [],
            runtimes: [fixture.runtime]
        )
        let viewModel = Self.authorityViewModel(product: parsed, remote: remote)

        #expect(await viewModel.loadProductInfoFromURL())
        let preparation = LinkClosetRegistrationPreparation.make(
            from: viewModel,
            brand: nil
        )
        #expect(preparation.parsedProduct == nil)
        let recoveryProduct = try #require(preparation.partialProduct)
        #expect(preparation.recoveryViewModel === viewModel)
        #expect(recoveryProduct.categoryCode == "tops")
        #expect(recoveryProduct.normalizedProductTypeCode == "base_layer_top")
        #expect(recoveryProduct.garmentTypeRawValue == "base_layer_top")
        #expect(recoveryProduct.classificationAuthorityProvenance == .serverConfirmed)
        #expect(recoveryProduct.canonicalEligibility == true)
    }

    private static func authorityViewModel(
        product: ParsedProductInfo,
        remote: DatabaseAuthorityRemoteStub
    ) -> ShoppingProductViewModel {
        let parser = DatabaseAuthorityParserStub(product: product)
        let service = ProductURLParserService(
            musinsaParser: parser,
            uniqloParser: parser
        )
        return ShoppingProductViewModel(
            initialURL: product.sourceURL.absoluteString,
            parserService: service,
            metricsRecorder: DatabaseAuthorityNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote)
        )
    }

    private static func authorityTestProduct(
        source: String,
        externalProductID: String,
        localCategory: ClothingCategory,
        localDetail: ClosetDetailCategory
    ) throws -> ParsedProductInfo {
        let sourceURL: URL
        let sourceType: ProductSourceType
        let sourceName: String
        switch source {
        case "uniqlo":
            sourceURL = try #require(
                URL(string: "https://www.uniqlo.com/kr/ko/products/\(externalProductID)-000/01")
            )
            sourceType = .officialStore
            sourceName = "유니클로 공식몰"
        default:
            sourceURL = try #require(
                URL(string: "https://www.musinsa.com/products/\(externalProductID)")
            )
            sourceType = .marketplace
            sourceName = "무신사"
        }

        return ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: sourceType,
            sourceName: sourceName,
            brandName: "테스트",
            productName: localCategory.serviceGroup == .bottom
                ? "로컬 데님 긴바지"
                : "로컬 반팔 티셔츠",
            category: localCategory,
            detailCategory: localDetail,
            sizes: [
                ParsedProductSize(
                    name: "M",
                    measurements: GarmentMeasurements(
                        shoulder: 46,
                        chest: 54,
                        totalLength: 70,
                        sleeveLength: 24,
                        waist: 39,
                        hip: 52,
                        thigh: 31,
                        rise: 28,
                        hem: 20
                    )
                )
            ],
            productID: externalProductID,
            sourceCategoryPath: localCategory.serviceGroup == .bottom
                ? "하의 > 데님 > 긴바지"
                : "상의 > 반소매 티셔츠",
            productMetadata: ProductMetadata(
                sourceCategoryPath: localCategory.serviceGroup == .bottom
                    ? "하의 > 데님 > 긴바지"
                    : "상의 > 반소매 티셔츠",
                categoryDepth1Code: localCategory.serviceGroup == .bottom ? "003" : "001",
                categoryDepth2Code: localCategory.serviceGroup == .bottom ? "003002" : "001001"
            )
        )
    }
}

@MainActor
private final class DatabaseAuthorityParserStub: ProductURLParsing {
    let product: ParsedProductInfo

    init(product: ParsedProductInfo) {
        self.product = product
    }

    func canParse(_ url: URL) -> Bool { true }

    func parse(from url: URL) async throws -> ParsedProductInfo { product }
}

private final class DatabaseAuthorityNoopMetricsRecorder: FitMatchMetricsRecording {
    func record(_ event: FitMatchMetricEvent) {}
}

private struct DatabaseAuthorityFixture {
    let source: String
    let externalProductID: String
    let status: FitMatchServerProductAuthorityStatus
    let productID = UUID()
    let classification: FitMatchDatabaseClassification

    init(
        source: String,
        externalProductID: String,
        status: FitMatchServerProductAuthorityStatus,
        categoryCode: String? = nil,
        detailCode: String? = nil,
        familyCode: String? = nil,
        lengthCode: String? = nil
    ) {
        self.source = source
        self.externalProductID = externalProductID
        self.status = status
        classification = FitMatchDatabaseClassification(
            classificationID: UUID(),
            categoryCode: categoryCode,
            detailCode: detailCode,
            garmentTypeCode: familyCode,
            familyCode: familyCode,
            lengthCode: lengthCode,
            bodyLengthCode: nil,
            status: status.rawValue,
            method: status == .notComparable
                ? "structured_exclusion"
                : status == .confirmed ? "canonical_product_decision" : "unknown",
            authorityStatus: status == .confirmed ? "verified" : nil,
            confidence: status == .confirmed ? 1 : nil,
            requiresUserConfirmation: status == .reviewRequired,
            taxonomyPolicyVersion: "db-classifier-2026-08-26-final",
            decisionVersion: "classification-db-final-closure-2026-08-26-v1"
        )
    }

    func resolution(catalogState: String = "current") -> FitMatchProductResolutionResponse {
        FitMatchProductResolutionResponse(
            productID: catalogState == "new" ? nil : productID,
            intakeRequestID: catalogState == "current" ? nil : UUID(),
            catalogState: catalogState,
            categoryEvidenceMatches: catalogState == "current",
            authorityPersisted: catalogState == "current",
            classification: classification,
            comparisonReady: catalogState == "current" && status == .confirmed
        )
    }

    var runtime: FitMatchProductRuntimeResponse {
        let runtimeState: String
        switch status {
        case .confirmed: runtimeState = "ready"
        case .reviewRequired: runtimeState = "classification_required"
        case .notComparable: runtimeState = "not_comparable"
        }
        return FitMatchProductRuntimeResponse(
            runtimeState: runtimeState,
            comparisonReady: status == .confirmed,
            product: FitMatchRuntimeProduct(
                productID: productID,
                source: source,
                externalProductID: externalProductID,
                productName: "Server Product",
                canonicalURL: nil,
                audience: "UNISEX",
                sourceCategoryPath: "server > category",
                sourceCategoryCodes: ["server-category"],
                imageURL: nil,
                lifecycleStatus: "active",
                inputFingerprint: "fixture"
            ),
            classification: classification,
            variants: []
        )
    }

    func observation(status: String) -> FitMatchProductObservationResponse {
        let observationID = UUID()
        return FitMatchProductObservationResponse(
            observation: .init(
                observationID: observationID,
                status: status == "promoted" ? "promoted" : "pending",
                rawMeasurementCount: 0
            ),
            processing: .init(
                observationID: observationID,
                status: status,
                productID: status == "promoted" ? productID : nil
            )
        )
    }
}

private actor DatabaseAuthorityRemoteStub: FitMatchServerAuthorityRemoteServicing {
    enum ResolveFailure: Sendable {
        case network
    }

    private var resolutions: [FitMatchProductResolutionResponse]
    private var observations: [FitMatchProductObservationResponse]
    private var runtimes: [FitMatchProductRuntimeResponse]
    private let resolveFailure: ResolveFailure?

    private(set) var observationCallCount = 0
    private(set) var runtimeCallCount = 0

    init(
        resolutions: [FitMatchProductResolutionResponse],
        observations: [FitMatchProductObservationResponse],
        runtimes: [FitMatchProductRuntimeResponse],
        resolveFailure: ResolveFailure? = nil
    ) {
        self.resolutions = resolutions
        self.observations = observations
        self.runtimes = runtimes
        self.resolveFailure = resolveFailure
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse {
        if resolveFailure == .network {
            throw URLError(.notConnectedToInternet)
        }
        guard !resolutions.isEmpty else { throw StubError.missingResolution }
        return resolutions.removeFirst()
    }

    func submitProductObservation(_ request: FitMatchProductObservationRequest) async throws
        -> FitMatchProductObservationResponse {
        observationCallCount += 1
        guard !observations.isEmpty else { throw StubError.missingObservation }
        return observations.removeFirst()
    }

    func fetchProductRuntime(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductRuntimeResponse {
        runtimeCallCount += 1
        guard !runtimes.isEmpty else { throw StubError.missingRuntime }
        return runtimes.removeFirst()
    }

    func listClosetItems() async throws -> FitMatchClosetItemsResponse {
        .init(state: "ready", items: [])
    }

    func findReferenceCandidates(targetProductID: UUID) async throws
        -> FitMatchReferenceCandidatesResponse {
        throw StubError.unexpectedCandidateLookup
    }

    enum StubError: Error {
        case missingResolution
        case missingObservation
        case missingRuntime
        case unexpectedCandidateLookup
    }
}
