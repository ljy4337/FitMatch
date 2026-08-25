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
        let parser = DatabaseShadowParserStub(product: product)
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

    @Test func productLoadRecordsMatchingDatabaseShadowWithoutChangingLocalResult() async throws {
        let product = ParsedProductInfo(
            sourceURL: try #require(URL(string: "https://www.musinsa.com/products/123")),
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: "테스트",
            productName: "반팔 티셔츠",
            category: .top,
            detailCategory: .shortSleeve,
            sizes: [],
            productID: "123",
            sourceCategoryPath: "상의 > 반소매 티셔츠"
        )
        let parser = DatabaseShadowParserStub(product: product)
        let service = ProductURLParserService(musinsaParser: parser, uniqloParser: parser)
        let response = FitMatchProductResolutionResponse(
            productID: UUID(),
            intakeRequestID: nil,
            catalogState: "current",
            categoryEvidenceMatches: true,
            classification: FitMatchDatabaseClassification(
                classificationID: UUID(),
                categoryCode: "tops",
                detailCode: "short_sleeve",
                familyCode: "tshirt",
                lengthCode: "short_sleeve",
                bodyLengthCode: nil,
                status: "confirmed",
                method: nil,
                confidence: nil,
                requiresUserConfirmation: false,
                taxonomyPolicyVersion: nil,
                decisionVersion: "test"
            ),
            comparisonReady: true
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: product.sourceURL.absoluteString,
            parserService: service,
            metricsRecorder: DatabaseShadowNoopMetricsRecorder(),
            databaseProductResolver: DatabaseShadowResolverStub(response: response)
        )

        #expect(await viewModel.loadProductInfoFromURL())
        for _ in 0..<100 where viewModel.databaseShadowState == .checking {
            await Task.yield()
        }
        guard case .matched = viewModel.databaseShadowState else {
            Issue.record("DB shadow 결과가 matched가 아닙니다: \(viewModel.databaseShadowState)")
            return
        }
        #expect(viewModel.category == .top)
        #expect(viewModel.detailCategory == .shortSleeve)
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
}

@MainActor
private final class DatabaseShadowParserStub: ProductURLParsing {
    let product: ParsedProductInfo

    init(product: ParsedProductInfo) {
        self.product = product
    }

    func canParse(_ url: URL) -> Bool { true }

    func parse(from url: URL) async throws -> ParsedProductInfo { product }
}

private actor DatabaseShadowResolverStub: FitMatchProductResolving {
    let response: FitMatchProductResolutionResponse

    init(response: FitMatchProductResolutionResponse) {
        self.response = response
    }

    func resolve(_ request: FitMatchProductResolutionRequest) async throws
        -> FitMatchProductResolutionResponse {
        response
    }
}

private final class DatabaseShadowNoopMetricsRecorder: FitMatchMetricsRecording {
    func record(_ event: FitMatchMetricEvent) {}
}
