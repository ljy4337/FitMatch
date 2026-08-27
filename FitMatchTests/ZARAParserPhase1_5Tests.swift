import Foundation
import Testing
@testable import FitMatch

private let runsLiveZARAProductionLoaderAudit =
    ProcessInfo.processInfo.arguments.contains("-fitmatchRunLiveZARAProductionLoaderAudit")
    || ProcessInfo.processInfo.environment["FITMATCH_RUN_LIVE_ZARA_PRODUCTION_LOADER_AUDIT"] == "1"

@MainActor
struct ZARAParserPhase1_5Tests {
    private struct ShadowCategoryRow: Decodable {
        let sourceProductID: String
        let productName: String
        let familyName: String?
        let subfamilyName: String?
        let fitmatchMajorCandidate: String?
        let productStructure: String
        let section: String
        let styleReference: String?
        let productURL: String?
        let officialListed: Bool?
        let reviewStatus: String?
        let goldApproved: Bool?

        enum CodingKeys: String, CodingKey {
            case sourceProductID = "source_product_id"
            case productName = "product_name"
            case familyName = "family_name"
            case subfamilyName = "subfamily_name"
            case fitmatchMajorCandidate = "fitmatch_major_candidate"
            case productStructure = "product_structure"
            case section
            case styleReference = "style_reference"
            case productURL = "product_url"
            case officialListed = "official_listed"
            case reviewStatus = "review_status"
            case goldApproved = "gold_approved"
        }
    }

    @Test func identitySeparatesStyleVariantAndInternalProductID() throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: "B. Camisería"
        )

        let identity = try #require(ZARAProductPageParser.identity(
            requestedURL: url,
            resolvedURL: url,
            html: html
        ))

        #expect(identity.styleNumber == "04166166")
        #expect(identity.catentryID == "545490346")
        #expect(identity.internalProductID == "545486853")
        #expect(identity.productReference == "04166166-000")
        #expect(identity.resolutionSource == .urlVariantVerifiedByEmbeddedAnalytics)
    }

    @Test func identityRecordsSelectedVariantWhenURLHasNoV1() throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: "F. Camisería"
        )

        let identity = try #require(ZARAProductPageParser.identity(
            requestedURL: url,
            resolvedURL: url,
            html: html
        ))
        #expect(identity.resolutionSource == .embeddedAnalyticsSelectedVariant)
    }

    @Test func identityRequiresJSONLDToCorroborateStyleAndVariantWhenPublished() throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let matching = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: "B. Camisería"
        )
        #expect(ZARAProductPageParser.identity(requestedURL: url, resolvedURL: url, html: matching) != nil)

        let mismatchedStyle = matching.replacingOccurrences(
            of: #""productGroupID":"04166166""#,
            with: #""productGroupID":"99999999""#
        )
        #expect(ZARAProductPageParser.identity(requestedURL: url, resolvedURL: url, html: mismatchedStyle) == nil)

        let mismatchedVariant = matching.replacingOccurrences(
            of: #"v1=545490346"#,
            with: #"v1=999999999"#
        )
        #expect(ZARAProductPageParser.identity(requestedURL: url, resolvedURL: url, html: mismatchedVariant) == nil)
    }

    @Test func identityAcceptsSelectedColourAmongMultipleStructuredVariants() throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04174325.html?v1=555526397"))
        let html = productHTML(
            internalProductID: "545408873",
            styleNumber: "04174325",
            catentryID: "555526397",
            section: "WOMAN",
            family: "티셔츠",
            subfamily: "C.CTAS BASICAS",
            additionalVariantIDs: ["547793140", "555529728"]
        )

        let identity = try #require(ZARAProductPageParser.identity(
            requestedURL: url,
            resolvedURL: url,
            html: html
        ))
        #expect(identity.catentryID == "555526397")
    }

    @Test func parsedMetadataPreservesVariantAndCategoryPolicyProvenance() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: "F. Camisería"
        )
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: Data("{\"measureGuideInfo\":null}".utf8))
        )

        let info = try #require(await partialResult(parser: parser, url: url))
        #expect(info.productMetadata.externalVariantID == "545490346")
        #expect(info.productMetadata.variantSelectionMethod == "url_variant_verified_by_embedded_analytics")
        #expect(info.productMetadata.variantSelectionConfidence == 1)
        #expect(info.productMetadata.categoryMappingPolicyVersion == "zara-kr-structured-category-2026-08-25-v5")
        #expect(info.category == .top)
        #expect(info.detailCategory == .shirt)
    }

    @Test func URLVariantRequestsOfficialSizeGuideBeforeProductPage() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: "B. Camisería"
        )
        let events = Phase15ZARAFlowRecorder()
        let parser = ZARAParser(
            pageLoader: Phase15RecordingZARAPageLoader(
                page: .init(url: url, statusCode: 200, html: html),
                event: "page:direct",
                recorder: events
            ),
            sizeGuideLoader: Phase15FlowRecordingZARAGuideLoader(
                data: verifiedUpperGuideData(),
                recorder: events
            )
        )

        let info = try await parser.parse(from: url)

        #expect(await events.values() == ["guide:545490346", "page:direct"])
        #expect(info.measurementAvailability == .actualMeasurements)
        #expect(!info.sizes.isEmpty)
    }

    @Test func URLWithoutVariantLoadsProductIdentityBeforeSizeGuide() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: "B. Camisería"
        )
        let events = Phase15ZARAFlowRecorder()
        let parser = ZARAParser(
            pageLoader: Phase15RecordingZARAPageLoader(
                page: .init(url: url, statusCode: 200, html: html),
                event: "page:direct",
                recorder: events
            ),
            sizeGuideLoader: Phase15FlowRecordingZARAGuideLoader(
                data: verifiedUpperGuideData(),
                recorder: events
            )
        )

        _ = try await parser.parse(from: url)

        #expect(await events.values() == ["page:direct", "guide:545490346"])
    }

    @Test func invalidDirectPageUsesStructuredWebViewFallbackWithoutChangingVariant() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let validHTML = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: "B. Camisería"
        )
        let events = Phase15ZARAFlowRecorder()
        let parser = ZARAParser(
            pageLoader: Phase15RecordingZARAPageLoader(
                page: .init(url: url, statusCode: 403, html: "Access Denied"),
                event: "page:direct",
                recorder: events
            ),
            sizeGuideLoader: Phase15FlowRecordingZARAGuideLoader(
                data: verifiedUpperGuideData(),
                recorder: events
            ),
            fallbackPageLoader: Phase15RecordingZARAPageLoader(
                page: .init(url: url, statusCode: 200, html: validHTML),
                event: "page:webview",
                recorder: events
            )
        )

        let info = try await parser.parse(from: url)

        #expect(await events.values() == [
            "guide:545490346",
            "page:direct",
            "page:webview"
        ])
        #expect(info.productMetadata.externalVariantID == "545490346")
        #expect(info.measurementAvailability == .actualMeasurements)
    }

    @Test(.enabled(
        if: runsLiveZARAProductionLoaderAudit,
        "ZARA 실제 기본 loader 검증은 명시적으로만 실행합니다."
    ))
    func liveDefaultLoaderResolvesOfficialProductIdentityAndGarmentGuide() async throws {
        let url = try #require(URL(
            string: "https://www.zara.com/kr/ko/item-p04174325.html?v1=547793140"
        ))

        let info: ParsedProductInfo
        do {
            info = try await ZARAParser().parse(from: url)
        } catch let partial as ProductURLParserPartialError {
            info = partial.productInfo
        }

        #expect(info.productName.localizedCaseInsensitiveContains("티셔츠"))
        #expect(info.productMetadata.styleNo == "04174325")
        #expect(info.productMetadata.externalVariantID == "547793140")
        #expect(info.productID == "545408873")
        #expect(info.category == .top)
        #expect(info.detailCategory == .shortSleeve)
        #expect(info.measurementAvailability == .actualMeasurements)
        #expect(!info.sizes.isEmpty)
    }

    @Test(.enabled(
        if: runsLiveZARAProductionLoaderAudit,
        "ZARA v1 실측 API 직행 검증은 명시적으로만 실행합니다."
    ))
    func liveURLVariantDirectlyResolvesOfficialGarmentGuideWithoutProductPage() async throws {
        let data = try await ZARASizeGuideLoader().load(productID: "547793140")
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let guide = try #require(object["measureGuideInfo"] as? [String: Any])
        let sizes = try #require(guide["sizes"] as? [[String: Any]])

        #expect(!sizes.isEmpty)
        #expect(sizes.contains { size in
            guard let measures = size["measures"] as? [[String: Any]] else { return false }
            return measures.contains { measure in
                guard let dimensions = measure["dimensions"] as? [[String: Any]] else {
                    return false
                }
                return dimensions.contains { dimension in
                    dimension["unitId"] as? String == "cm"
                        && !(dimension["value"] as? String ?? "").isEmpty
                }
            }
        })
    }

    @Test(.enabled(
        if: runsLiveZARAProductionLoaderAudit,
        "사용자 ZARA 공유 URL 검증은 명시적으로만 실행합니다."
    ))
    func liveUserSharedZARAURLReachesProductionParser() async throws {
        let url = try #require(URL(string:
            "https://www.zara.com/kr/ko/%E1%84%8B%E1%85%AA%E1%84%91%E1%85%B3%E1%86%AF-%E1%84%8C%E1%85%A9%E1%84%8C%E1%85%B5%E1%86%A8-%E1%84%85%E1%85%A6%E1%84%80%E1%85%B2%E1%86%AF%E1%84%85%E1%85%A5%E1%84%91%E1%85%B5%E1%86%BA-%E1%84%89%E1%85%B3%E1%84%8B%E1%85%B0%E1%84%90%E1%85%B3%E1%84%89%E1%85%A7%E1%84%8E%E1%85%B3-p05372320.html?v1=549582583&utm_campaign=productShare&utm_medium=mobile_sharing_iOS&utm_source=red_social_movil"
        ))

        #expect(ProductURLSupport.supportedProviderName(for: url.absoluteString) == "ZARA")
        let info: ParsedProductInfo
        do {
            info = try await ProductURLParserService().parse(urlString: url.absoluteString)
        } catch let partial as ProductURLParserPartialError {
            info = partial.productInfo
        }

        #expect(info.productMetadata.styleNo == "05372320")
        #expect(info.productMetadata.externalVariantID == "549582583")
        #expect(info.sourceName == "ZARA 공식몰")
    }

    @Test func reviewedStructuredCategoryPathsMapToExactFitMatchDetails() {
        let cases: [(String, String, String, ClothingCategory, ClosetDetailCategory)] = [
            ("MAN", "셔츠", "B. Camisería", .top, .shirt),
            ("MAN", "브레이저", "Blasier", .outer, .blazer),
            ("MAN", "바지", "F. Pant Resto", .bottom, .longPants),
            ("MAN", "바지", "B. Pant Denim", .bottom, .denim),
            ("MAN", "스웨터", "B. Jersey M/C", .top, .knitTop),
            ("MAN", "스포츠 재킷", "B. Cazadora", .outer, .jacket),
            ("MAN", "버뮤다반바지", "F.Bermuda Resto", .bottom, .shorts),
            ("MAN", "BERMUDA", "ATH Bottoms", .bottom, .shorts),
            ("MAN", "BERMUDA", "ATH Short", .bottom, .shorts),
            ("MAN", "BERMUDA", "B. Bermuda Rest", .bottom, .shorts),
            ("MAN", "BERMUDA", "Bermuda Denim", .bottom, .denim),
            ("MAN", "BERMUDA", "F.Bermuda Rest", .bottom, .shorts),
            ("MAN", "PANTY/UNDERPANT", "ATH Underwear", .underwear, .menBriefs),
            ("MAN", "PANTY/UNDERPANT", "Underwear", .underwear, .menBriefs),
            ("MAN", "스웨트 셔츠", "F. Sudadera", .top, .sweatshirt),
            ("WOMAN", "드레스", "C.VESTIDO FANTA", .dress, .onePiece),
            ("WOMAN", "셔츠", "B.SHIRT", .top, .shirt),
            ("WOMAN", "가디건", "KNIT CARDIGAN", .outer, .cardigan),
            ("WOMAN", "스포츠 재킷", "T.SHORT-OUTWEAR", .outer, .jacket),
            ("WOMAN", "버뮤다반바지", "T.BERMUDAS", .bottom, .shorts),
            ("WOMAN", "BERMUDA", "C-LEGGING", .bottom, .shorts),
            ("WOMAN", "BERMUDA", "ST. BERMUDA", .bottom, .shorts),
            ("WOMAN", "BERMUDA", "W.BERMUDAS", .bottom, .shorts),
            ("WOMAN", "BRA", "SUJE CON B", .underwear, .womenBra),
            ("WOMAN", "BRA", "SUJETADOR", .underwear, .womenBra),
            ("WOMAN", "PANTY/UNDERPANT", "BRAGA", .underwear, .womenPanty),
            ("WOMAN", "브레이저", "B.BLAZER", .outer, .blazer),
            ("WOMAN", "치마", "T.SKIRT", .bottom, .skirt)
        ]

        for item in cases {
            let result = ZARACategoryClassifier.classify(
                section: item.0,
                family: item.1,
                subfamily: item.2
            )
            #expect(result.category == item.3)
            #expect(result.detailCategory == item.4)
        }
    }

    @Test func userConfirmedAmbiguousZARAProductsHaveStableCategories() {
        let cases: [(String, String, String, String, ClothingCategory, ClosetDetailCategory)] = [
            ("WOMAN", "바지", "B.FOLDER PANTS", "01934230", .bottom, .denim),
            ("WOMAN", "바지", "C.PTON-LEGGING", "05644812", .bottom, .longPants),
            ("WOMAN", "바지", "L. PANT. PIJAMA", "01377700", .bottom, .longPants),
            ("WOMAN", "브레이저", "B.BLAZER", "07782343", .outer, .jacket)
        ]

        for item in cases {
            let result = ZARACategoryClassifier.classify(
                section: item.0,
                family: item.1,
                subfamily: item.2,
                styleNumber: item.3
            )
            #expect(result.category == item.4)
            #expect(result.detailCategory == item.5)
        }

        let actualBlazer = ZARACategoryClassifier.classify(
            section: "WOMAN",
            family: "브레이저",
            subfamily: "B.BLAZER",
            styleNumber: "02753522"
        )
        #expect(actualBlazer.detailCategory == .blazer)
    }

    @Test func shadowDiscoveredAmbiguousFamiliesAndStructuredConflictsFailClosed() {
        let cases: [(String, String, String)] = [
            ("WOMAN", "OVERALL", "B.PANTS"),
            ("WOMAN", "TOPS AND OTHERS", "SHIRT-TOPS"),
            ("WOMAN", "WAISTCOAT", "B.VEST"),
            ("MAN", "OVERSHIRT", "Overshirt"),
            ("MAN", "SHIRT", "F. Jacket"),
            ("MAN", "WIND-JACKET", "ATH BSweatshirt"),
            ("WOMAN", "BERMUDA", "B.BERMUDAS")
        ]

        for item in cases {
            let result = ZARACategoryClassifier.classify(
                section: item.0,
                family: item.1,
                subfamily: item.2
            )
            #expect(result.category == .other)
            #expect(result.detailCategory == .other)
        }

        let conflictingBermuda = ZARACategoryClassifier.classify(
            section: "WOMAN",
            family: "BERMUDA",
            subfamily: "W.FOLDER PANTS"
        )
        let conflict = ParsedClosetClassification.auditExplicitContradictions(
            category: conflictingBermuda.category,
            detailCategory: conflictingBermuda.detailCategory,
            sourceDepths: ["ZARA", "여성", "BERMUDA", "W.FOLDER PANTS"].map(Optional.some),
            sourcePath: conflictingBermuda.path,
            productName: "ZW 컬렉션 플리츠 스트라이프 쇼츠"
        )
        #expect(conflict.requiresReview)
    }

    @Test func userConfirmedProductOverridesFlowThroughURLParser() async throws {
        let cases: [(style: String, variant: String, name: String, family: String,
                     subfamily: String, expected: ClosetDetailCategory)] = [
            ("01934230", "585050955", "JEANS Z1975 로우라이즈 레귤러",
             "바지", "B.FOLDER PANTS", .denim),
            ("07782343", "545431375", "스트라이프 봄버 재킷",
             "브레이저", "B.BLAZER", .jacket),
            ("02753522", "585277985", "오버사이즈 더블 브레스트 블레이저",
             "브레이저", "B.BLAZER", .blazer)
        ]

        for item in cases {
            let url = try #require(URL(
                string: "https://www.zara.com/kr/ko/item-p\(item.style).html?v1=\(item.variant)"
            ))
            let html = productHTML(
                internalProductID: "9\(item.style)",
                styleNumber: item.style,
                catentryID: item.variant,
                section: "WOMAN",
                family: item.family,
                subfamily: item.subfamily,
                productName: item.name
            )
            let parser = ZARAParser(
                pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
                sizeGuideLoader: Phase15ZARAGuideLoader(data: Data("{\"measureGuideInfo\":null}".utf8))
            )

            let info = try #require(await partialResult(parser: parser, url: url))
            #expect(info.detailCategory == item.expected)
        }
    }

    @Test func shadowCorpusStructuredCategoriesNeverCrossGarmentDomain() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let corpusURL = repositoryRoot
            .appendingPathComponent("Docs/Research/FitMatchCategoryMappingV2-20260824-shadow")
            .appendingPathComponent("zara_products.jsonl")
        let rows = try String(contentsOf: corpusURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { try JSONDecoder().decode(ShadowCategoryRow.self, from: Data($0.utf8)) }
        #expect(rows.count == 3_983)

        var evaluatedCount = 0
        var classifiedCount = 0
        var sourceDomainMismatchSamples: [String] = []
        var ambiguousFamilyLeakSamples: [String] = []
        var shadowCandidateDifferenceCount = 0
        var structuredPaths = Set<String>()

        for row in rows where row.productStructure == "STANDARD_PRODUCT" {
            guard let family = row.familyName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !family.isEmpty,
                  let subfamily = row.subfamilyName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !subfamily.isEmpty else { continue }

            evaluatedCount += 1
            structuredPaths.insert("\(row.section)|\(family)|\(subfamily)")
            let styleNumber = row.sourceProductID.split(separator: "_").last.map(String.init)
            let result = ZARACategoryClassifier.classify(
                section: row.section,
                family: family,
                subfamily: subfamily,
                styleNumber: styleNumber
            )
            guard result.category.serviceGroup != .other else { continue }
            classifiedCount += 1
            if isShadowAmbiguousFamily(family) {
                ambiguousFamilyLeakSamples.append(
                    "\(row.sourceProductID) \(family)|\(subfamily) "
                        + "actual=\(result.category.serviceGroup.taxonomyCode) "
                        + "name=\(row.productName)"
                )
            }
            if let expected = expectedDomainForStructuredFamily(family),
               result.category.serviceGroup != expected {
                sourceDomainMismatchSamples.append(
                    "\(row.sourceProductID) \(family)|\(subfamily) "
                        + "expected=\(expected.taxonomyCode) actual=\(result.category.serviceGroup.taxonomyCode) "
                        + "name=\(row.productName)"
                )
            }
            if let shadowCandidate = expectedServiceGroup(row.fitmatchMajorCandidate),
               result.category.serviceGroup != shadowCandidate {
                shadowCandidateDifferenceCount += 1
            }
        }

        print(
            "ZARA_SHADOW_CATEGORY_AUDIT rows=\(rows.count) evaluated=\(evaluatedCount) "
                + "structured_paths=\(structuredPaths.count) classified=\(classifiedCount) "
                + "unclassified=\(evaluatedCount - classifiedCount) "
                + "source_domain_mismatches=\(sourceDomainMismatchSamples.count) "
                + "ambiguous_family_leaks=\(ambiguousFamilyLeakSamples.count) "
                + "shadow_candidate_differences=\(shadowCandidateDifferenceCount)"
        )
        #expect(
            ambiguousFamilyLeakSamples.isEmpty,
            "검토 전용 source family가 자동 분류됨: \(ambiguousFamilyLeakSamples.prefix(20).joined(separator: "\n"))"
        )
        #expect(
            sourceDomainMismatchSamples.isEmpty,
            "명시적 source family와 다른 garment domain 분류: \(sourceDomainMismatchSamples.prefix(20).joined(separator: "\n"))"
        )
    }

    @Test func currentOfficialZARALive300RemainsShadowOnlyAndFailClosed() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let collectionURL = repositoryRoot
            .appendingPathComponent("ZARAAudit/live_zara_300_20260825/zara_live_300.jsonl")
        let rows = try String(contentsOf: collectionURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { try JSONDecoder().decode(ShadowCategoryRow.self, from: Data($0.utf8)) }

        #expect(rows.count == 300)
        #expect(Set(rows.compactMap(\.styleReference)).count == 300)
        #expect(rows.allSatisfy { $0.officialListed == true })
        #expect(rows.allSatisfy { $0.reviewStatus == "PENDING_HUMAN_REVIEW" })
        #expect(rows.allSatisfy { $0.goldApproved == false })
        #expect(rows.allSatisfy {
            $0.productURL?.hasPrefix("https://www.zara.com/kr/ko/") == true
        })

        var confirmedCount = 0
        var reviewRequiredCount = 0
        var unclassifiedCount = 0
        var silentConflictConfirmationCount = 0
        var strictConflictLeakCount = 0
        var sourceDomainMismatchSamples: [String] = []
        var detailCounts: [String: Int] = [:]
        var reviewFamilyCounts: [String: Int] = [:]
        var unclassifiedFamilyCounts: [String: Int] = [:]

        for row in rows {
            let family = row.familyName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let subfamily = row.subfamilyName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = ZARACategoryClassifier.classify(
                section: row.section,
                family: family,
                subfamily: subfamily,
                styleNumber: row.styleReference
            )
            let depths = ["ZARA", result.sectionName, family, subfamily]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            let conflict = ParsedClosetClassification.auditExplicitContradictions(
                category: result.category,
                detailCategory: result.detailCategory,
                sourceDepths: depths.map(Optional.some),
                sourcePath: result.path,
                productName: row.productName
            )
            let classification = ParsedClosetClassification.resolve(
                category: result.category,
                detailCategory: result.detailCategory,
                sourceDepths: depths.map(Optional.some),
                sourcePath: result.path,
                productName: row.productName
            )
            let hasAtomicServiceCategory = result.category.serviceGroup != .other
                && result.detailCategory != .other
                && classification?.isValid == true
            let familySignature = [family, subfamily]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
            let status: String
            if conflict.requiresReview {
                status = "review_required"
            } else if hasAtomicServiceCategory {
                status = "confirmed"
            } else {
                status = "unclassified"
            }
            let strictComparisonEligible = hasAtomicServiceCategory
                && !conflict.requiresReview

            if status == "review_required" {
                reviewRequiredCount += 1
                reviewFamilyCounts[familySignature, default: 0] += 1
            } else if status == "confirmed" {
                confirmedCount += 1
                detailCounts[result.detailCategory.rawValue, default: 0] += 1
            } else {
                unclassifiedCount += 1
                unclassifiedFamilyCounts[familySignature, default: 0] += 1
            }

            if conflict.requiresReview && status == "confirmed" {
                silentConflictConfirmationCount += 1
            }
            if conflict.requiresReview && strictComparisonEligible {
                strictConflictLeakCount += 1
            }
            if let family,
               let expected = expectedDomainForStructuredFamily(family),
               result.category.serviceGroup != .other,
               result.category.serviceGroup != expected {
                sourceDomainMismatchSamples.append(
                    "\(row.sourceProductID) \(family)|\(subfamily ?? "") "
                        + "expected=\(expected.taxonomyCode) "
                        + "actual=\(result.category.serviceGroup.taxonomyCode)"
                )
            }
        }

        print(
            "ZARA_LIVE_300_CLASSIFICATION_AUDIT rows=\(rows.count) "
                + "confirmed=\(confirmedCount) review_required=\(reviewRequiredCount) "
                + "unclassified=\(unclassifiedCount) "
                + "source_domain_mismatches=\(sourceDomainMismatchSamples.count) "
                + "silent_conflict_confirmations=\(silentConflictConfirmationCount) "
                + "strict_conflict_leaks=\(strictConflictLeakCount) "
                + "details=\(detailCounts.sorted { $0.key < $1.key }) "
                + "top_review_families=\(topCounts(reviewFamilyCounts)) "
                + "top_unclassified_families=\(topCounts(unclassifiedFamilyCounts))"
        )
        #expect(confirmedCount + reviewRequiredCount + unclassifiedCount == rows.count)
        #expect(confirmedCount == 188)
        #expect(reviewRequiredCount == 19)
        #expect(unclassifiedCount == 93)
        #expect(silentConflictConfirmationCount == 0)
        #expect(strictConflictLeakCount == 0)
        #expect(
            sourceDomainMismatchSamples.isEmpty,
            "공식 source family와 다른 대분류: \(sourceDomainMismatchSamples.prefix(20).joined(separator: "\n"))"
        )
    }

    private func topCounts(_ counts: [String: Int], limit: Int = 15) -> [(key: String, value: Int)] {
        Array(counts.sorted {
            if $0.value == $1.value { return $0.key < $1.key }
            return $0.value > $1.value
        }.prefix(limit))
    }

    @Test func identityRejectsVariantMismatchRedirectedStyleAndMissingProductID() throws {
        let requested = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let differentStyle = try #require(URL(string: "https://www.zara.com/kr/ko/item-p05552381.html?v1=545490346"))
        let mismatch = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "999999999",
            section: "MAN",
            family: "셔츠",
            subfamily: nil
        )
        let missingProductID = "<script>zara.analyticsData = {\"productRef\":\"04166166-000\",\"catentryId\":545490346};</script>"

        #expect(ZARAProductPageParser.identity(
            requestedURL: requested,
            resolvedURL: requested,
            html: mismatch
        ) == nil)
        #expect(ZARAProductPageParser.identity(
            requestedURL: requested,
            resolvedURL: differentStyle,
            html: mismatch
        ) == nil)
        #expect(ZARAProductPageParser.identity(
            requestedURL: requested,
            resolvedURL: requested,
            html: missingProductID
        ) == nil)
    }

    @Test func identityAcceptsSameStyleRedirectWithoutGuessingIDs() throws {
        let requested = try #require(URL(string: "https://www.zara.com/kr/ko/old-slug-p04166166.html?v1=545490346"))
        let resolved = try #require(URL(string: "https://www.zara.com/kr/ko/current-slug-p04166166.html?v1=545490346"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: nil
        )

        let identity = ZARAProductPageParser.identity(
            requestedURL: requested,
            resolvedURL: resolved,
            html: html
        )
        #expect(identity?.styleNumber == "04166166")
        #expect(identity?.catentryID == "545490346")
        #expect(identity?.internalProductID == "545486853")
    }

    @Test func URLIdentityParsingHandlesNoVariantAndMalformedURL() throws {
        let noVariant = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html"))
        let malformed = try #require(URL(string: "https://www.zara.com/kr/ko/item-p4166166.html?v1=abc"))

        #expect(ZARAProductPageParser.styleNumber(from: noVariant) == "04166166")
        #expect(ZARAProductPageParser.variantID(from: noVariant) == nil)
        #expect(ZARAProductPageParser.styleNumber(from: malformed) == nil)
        #expect(ZARAProductPageParser.variantID(from: malformed) == nil)
    }

    @Test func challengeHTMLFailsBeforeIdentityOrSizeRequest() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let challenge = try String(contentsOf: fixtureURL("fixtures/zara_challenge_sanitized.html"), encoding: .utf8)
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: challenge)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: Data())
        )

        #expect(ZARAProductPageParser.isBotChallenge(challenge))
        await expectAutomaticParsingUnavailable(parser: parser, url: url)
    }

    @Test func inertChallengeSymbolInsideValidProductPageDoesNotBlockImport() throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: "B. Camisería"
        ) + "<script>function triggerInterstitialChallenge() {}</script>"

        #expect(ZARAProductPageParser.isBotChallenge(html) == false)
        #expect(ZARAProductPageParser.identity(requestedURL: url, resolvedURL: url, html: html) != nil)
    }

    @Test func unavailableProductPageFailsExplicitly() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/deleted-p04166166.html?v1=545490346"))
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 404, html: "")),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: Data())
        )

        await expectAutomaticParsingUnavailable(parser: parser, url: url)
    }

    @Test func verifiedUpperGarmentSubsetMapsChestShoulderAndSleeveOnly() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p06224446.html?v1=498706001"))
        let html = productHTML(
            internalProductID: "498702922",
            styleNumber: "06224446",
            catentryID: "498706001",
            section: "MAN",
            family: "티셔츠",
            subfamily: "F. Camiseta"
        )
        let data = Data("""
        {"measureGuideInfo":{"sizes":[{"name":"S","measures":[
          {"zoneId":"A","tableTitleZone":"zone-name-chest","dimensions":[{"unitId":"cm","value":"48.5"}]},
          {"zoneId":"B","tableTitleZone":"zone-name-front-length","dimensions":[{"unitId":"cm","value":"62.5"}]},
          {"zoneId":"C","tableTitleZone":"zone-name-sleeve-length","dimensions":[{"unitId":"cm","value":"17.0"}]},
          {"zoneId":"D","tableTitleZone":"zone-name-back-width","dimensions":[{"unitId":"cm","value":"40.0"}]},
          {"zoneId":"E","tableTitleZone":"zone-name-arm-width","dimensions":[{"unitId":"cm","value":"14.0"}]}
        ]}]}}
        """.utf8)
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: data)
        )

        let info = try await parser.parse(from: url)
        #expect(info.productID == "498702922")
        #expect(info.productMetadata.styleNo == "06224446")
        #expect(info.productMetadata.externalVariantID == "498706001")
        #expect(info.measurementAvailability == .actualMeasurements)
        #expect(!info.sizes.isEmpty)
        let records = info.sizes.flatMap(\.measurementRecords)
        #expect(records.first { $0.rawCode == "zone-name-chest" }?.measurementCode == .chestWidthPitToPit)
        #expect(records.first { $0.rawCode == "zone-name-back-width" }?.measurementCode == .shoulderWidthSeamToSeam)
        #expect(records.first { $0.rawCode == "zone-name-sleeve-length" }?.measurementCode == .sleeveShoulderSeamToCuff)
        #expect(records.first { $0.rawCode == "zone-name-front-length" }?.semanticStatus == .unknownDefinition)
        #expect(records.first { $0.rawCode == "zone-name-arm-width" }?.semanticStatus == .unknownDefinition)
        #expect(records.filter { $0.semanticStatus == .mapped }.allSatisfy {
            $0.evidenceLevel == .officialText
                && $0.mappingVersion == "zara_kr_measure_guide_verified_subset_v4"
        })
        #expect(records.contains {
            $0.rawCode == "zone-name-chest"
                && $0.rawLabel == "zone-name-chest"
                && $0.rawInfo?.contains("raw_zone_id=A") == true
                && $0.rawValueText == "48.5"
        })
    }

    @Test func verifiedOuterGarmentSubsetIsComparisonReadyWithoutPromotingFrontLengthOrArmWidth() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04391892.html?v1=545431375"))
        let html = productHTML(
            internalProductID: "545406831",
            styleNumber: "04391892",
            catentryID: "545431375",
            section: "WOMAN",
            family: "스포츠 재킷",
            subfamily: "T.SHORT-OUTWEAR"
        )
        let data = Data("""
        {"measureGuideInfo":{"sizes":[{"name":"S","measures":[
          {"zoneId":"A","tableTitleZone":"zone-name-chest","dimensions":[{"unitId":"cm","value":"56.0"}]},
          {"zoneId":"B","tableTitleZone":"zone-name-front-length","dimensions":[{"unitId":"cm","value":"58.0"}]},
          {"zoneId":"C","tableTitleZone":"zone-name-sleeve-length","dimensions":[{"unitId":"cm","value":"49.0"}]},
          {"zoneId":"D","tableTitleZone":"zone-name-back-width","dimensions":[{"unitId":"cm","value":"60.5"}]},
          {"zoneId":"E","tableTitleZone":"zone-name-arm-width","dimensions":[{"unitId":"cm","value":"25.5"}]}
        ]}]}}
        """.utf8)
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: data)
        )

        let info = try await parser.parse(from: url)
        let records = try #require(info.sizes.first?.measurementRecords)
        #expect(info.category == .outer)
        #expect(info.measurementAvailability == .actualMeasurements)
        #expect(records.first { $0.rawCode == "zone-name-chest" }?.measurementCode == .chestWidthPitToPit)
        #expect(records.first { $0.rawCode == "zone-name-back-width" }?.measurementCode == .shoulderWidthSeamToSeam)
        #expect(records.first { $0.rawCode == "zone-name-sleeve-length" }?.measurementCode == .sleeveShoulderSeamToCuff)
        #expect(records.first { $0.rawCode == "zone-name-front-length" }?.semanticStatus == .unknownDefinition)
        #expect(records.first { $0.rawCode == "zone-name-arm-width" }?.semanticStatus == .unknownDefinition)
    }

    @Test func verifiedPantsSubsetMapsWaistHipAndFrontRiseOnly() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p08372248.html?v1=582770476"))
        let html = productHTML(
            internalProductID: "548577264",
            styleNumber: "08372248",
            catentryID: "582770476",
            section: "WOMAN",
            family: "바지",
            subfamily: "B.PANTS"
        )
        let data = Data("""
        {"measureGuideInfo":{"sizes":[{"name":"S","measures":[
          {"zoneId":"A","tableTitleZone":"zone-name-waist","dimensions":[{"unitId":"cm","value":"34.5"}]},
          {"zoneId":"B","tableTitleZone":"zone-name-hips","dimensions":[{"unitId":"cm","value":"46.0"}]},
          {"zoneId":"C","tableTitleZone":"zone-name-front-length-lower","dimensions":[{"unitId":"cm","value":"104.0"}]},
          {"zoneId":"D","tableTitleZone":"zone-name-front-rise","dimensions":[{"unitId":"cm","value":"31.0"}]},
          {"zoneId":"E","tableTitleZone":"zone-name-back-rise","dimensions":[{"unitId":"cm","value":"40.0"}]}
        ]}]}}
        """.utf8)
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: data)
        )

        let info = try await parser.parse(from: url)
        let records = try #require(info.sizes.first?.measurementRecords)
        #expect(info.measurementAvailability == .actualMeasurements)
        #expect(records.first { $0.rawCode == "zone-name-waist" }?.measurementCode == .waistWidthEdgeToEdge)
        #expect(records.first { $0.rawCode == "zone-name-hips" }?.measurementCode == .hipWidthAtWidest)
        #expect(records.first { $0.rawCode == "zone-name-front-rise" }?.measurementCode == .riseCrotchToWaistFront)
        #expect(records.first { $0.rawCode == "zone-name-front-length-lower" }?.semanticStatus == .unknownDefinition)
        #expect(records.first { $0.rawCode == "zone-name-back-rise" }?.semanticStatus == .unknownDefinition)
        #expect(records.filter { $0.semanticStatus == .mapped }.allSatisfy { $0.evidenceLevel == .officialText })

        let observation = try #require(info.fitMatchProductObservationRequest())
        let observedMeasurements = try #require(observation.payload.variants.first?.sizes.first?.measurements)
        #expect(observedMeasurements.first { $0.rawCode == "zone-name-waist" }?.evidence["raw_value_text"] == "34.5")
        #expect(observedMeasurements.first { $0.rawCode == "zone-name-front-length-lower" } != nil)
    }

    @Test func verifiedDressSubsetMapsFlatChestWaistAndHip() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p09081018.html?v1=558218256"))
        let html = productHTML(
            internalProductID: "558215502",
            styleNumber: "09081018",
            catentryID: "558218256",
            section: "WOMAN",
            family: "드레스",
            subfamily: "W.DRESS"
        )
        let data = Data("""
        {"measureGuideInfo":{"sizes":[{"name":"M","measures":[
          {"zoneId":"A","tableTitleZone":"zone-name-chest","dimensions":[{"unitId":"cm","value":"39.0"}]},
          {"zoneId":"B","tableTitleZone":"zone-name-waist-full-body","dimensions":[{"unitId":"cm","value":"35.0"}]},
          {"zoneId":"C","tableTitleZone":"zone-name-hips","dimensions":[{"unitId":"cm","value":"47.0"}]},
          {"zoneId":"D","tableTitleZone":"zone-name-front-length-full-body","dimensions":[{"unitId":"cm","value":"132.0"}]}
        ]}]}}
        """.utf8)
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: data)
        )

        let info = try await parser.parse(from: url)
        let records = try #require(info.sizes.first?.measurementRecords)
        #expect(info.measurementAvailability == .actualMeasurements)
        #expect(records.first { $0.rawCode == "zone-name-chest" }?.measurementCode == .chestWidthPitToPit)
        #expect(records.first { $0.rawCode == "zone-name-waist-full-body" }?.measurementCode == .waistWidthEdgeToEdge)
        #expect(records.first { $0.rawCode == "zone-name-hips" }?.measurementCode == .hipWidthAtWidest)
        #expect(records.first { $0.rawCode == "zone-name-front-length-full-body" }?.semanticStatus == .unknownDefinition)
    }

    @Test func incompletePantsSubsetFailsClosedEvenWhenOneFieldMaps() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p08372248.html?v1=582770476"))
        let html = productHTML(
            internalProductID: "548577264",
            styleNumber: "08372248",
            catentryID: "582770476",
            section: "WOMAN",
            family: "바지",
            subfamily: "B.PANTS"
        )
        let data = Data("""
        {"measureGuideInfo":{"sizes":[{"name":"S","measures":[
          {"zoneId":"A","tableTitleZone":"zone-name-waist","dimensions":[{"unitId":"cm","value":"34.5"}]}
        ]}]}}
        """.utf8)
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: data)
        )

        let info = try #require(await partialResult(parser: parser, url: url))
        #expect(info.measurementAvailability == .unavailable)
        #expect(info.sizes.first?.measurementRecords.first?.measurementCode == .waistWidthEdgeToEdge)
    }

    @Test func bodyOnlyFixtureNeverCreatesParsedMeasurements() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: "B. Camisería"
        )
        let data = try Data(contentsOf: fixtureURL("cache/545486853.json"))
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: data)
        )

        let info = try #require(await partialResult(parser: parser, url: url))
        #expect(info.measurementAvailability == .unavailable)
        #expect(info.sizes.isEmpty)
    }

    @Test func onlyCatentryIDIsPassedToSizeGuideLoader() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: nil
        )
        let recorder = Phase15ProductIDRecorder()
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15RecordingZARAGuideLoader(
                data: Data("{\"measureGuideInfo\":null,\"sizeGuideInfo\":null}".utf8),
                recorder: recorder
            )
        )

        _ = await partialResult(parser: parser, url: url)
        let requestedProductIDs = await recorder.values()
        #expect(requestedProductIDs == ["545490346"])
        #expect(requestedProductIDs.contains("04166166") == false)
        #expect(requestedProductIDs.contains("545486853") == false)
    }

    @Test func sizeGuideHTTPFailureIsPartialAndNonComparable() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: nil
        )
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ThrowingZARAGuideLoader(error: .automaticParsingUnavailable)
        )

        let partial = await partialResult(parser: parser, url: url)
        #expect(partial?.measurementAvailability == .unavailable)
        #expect(partial?.sizes.isEmpty == true)
    }

    @Test func missingOrNonCentimeterUnitsNeverCreateComparableMeasurements() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: nil
        )
        let responses = [
            Data("{\"measureGuideInfo\":{\"sizes\":[{\"name\":\"S\",\"measures\":[{\"zoneId\":\"A\",\"tableTitleZone\":\"zone-name-chest\",\"dimensions\":[{\"unitId\":\"in\",\"value\":\"19.1\"}]}]}]}}".utf8),
            Data("{\"measureGuideInfo\":{\"sizes\":[{\"name\":\"S\",\"measures\":[{\"zoneId\":\"A\",\"tableTitleZone\":\"zone-name-chest\",\"dimensions\":[{\"value\":\"48.5\"}]}]}]}}".utf8)
        ]

        for data in responses {
            let parser = ZARAParser(
                pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
                sizeGuideLoader: Phase15ZARAGuideLoader(data: data)
            )
            let info = try #require(await partialResult(parser: parser, url: url))
            #expect(info.measurementAvailability == .unavailable)
            #expect(info.sizes.isEmpty)
        }
    }

    @Test func partiallyMissingSizeMeasurementsPreserveOnlyValidRawValues() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: nil
        )
        let data = Data("{\"measureGuideInfo\":{\"sizes\":[{\"name\":\"S\",\"measures\":[{\"zoneId\":\"A\",\"tableTitleZone\":\"zone-name-chest\",\"dimensions\":[{\"unitId\":\"cm\",\"value\":\"48.5\"}]},{\"zoneId\":\"B\",\"tableTitleZone\":\"zone-name-sleeve-length\",\"dimensions\":[]}]}]}}".utf8)
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: data)
        )

        let info = try #require(await partialResult(parser: parser, url: url))
        #expect(info.measurementAvailability == .unavailable)
        #expect(info.sizes.count == 1)
        #expect(info.sizes[0].measurementRecords.count == 1)
        #expect(info.sizes[0].measurementRecords[0].rawValueText == "48.5")
        #expect(info.sizes[0].measurementRecords[0].measurementCode == .chestWidthPitToPit)
        #expect(info.sizes[0].measurementRecords[0].semanticStatus == .mapped)
    }

    @Test func malformedAndEmptyGuideFailClosed() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"))
        let html = productHTML(
            internalProductID: "545486853",
            styleNumber: "04166166",
            catentryID: "545490346",
            section: "MAN",
            family: "셔츠",
            subfamily: nil
        )
        let malformed = try Data(contentsOf: fixtureURL("fixtures/zara_malformed_synthetic.json"))
        let empty = Data("{\"sizeGuideInfo\":null,\"measureGuideInfo\":null}".utf8)

        for data in [malformed, empty] {
            let parser = ZARAParser(
                pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
                sizeGuideLoader: Phase15ZARAGuideLoader(data: data)
            )
            let info = try #require(await partialResult(parser: parser, url: url))
            #expect(info.measurementAvailability == .unavailable)
            #expect(info.sizes.isEmpty)
        }
    }

    @Test func unknownMixedAndExcludedCategoriesDoNotBecomeShortSleeveTops() async throws {
        let cases: [(style: String, variant: String, html: String)] = [
            (
                "01234567",
                "900000011",
                try String(contentsOf: fixtureURL("fixtures/zara_unknown_category_synthetic.html"), encoding: .utf8)
            ),
            (
                "01234568",
                "900000012",
                try String(contentsOf: fixtureURL("fixtures/zara_mixed_category_synthetic.html"), encoding: .utf8)
            ),
            (
                "01234569",
                "900000013",
                productHTML(
                    internalProductID: "900000003",
                    styleNumber: "01234569",
                    catentryID: "900000013",
                    section: "WOMAN",
                    family: "액세서리",
                    subfamily: "BAG",
                    productName: "티셔츠라는 상품명 힌트"
                )
            )
        ]

        for item in cases {
            let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p\(item.style).html?v1=\(item.variant)"))
            let parser = ZARAParser(
                pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: item.html)),
                sizeGuideLoader: Phase15ZARAGuideLoader(data: Data())
            )
            let info = try #require(await partialResult(parser: parser, url: url))
            #expect(info.category == .other)
            #expect(info.detailCategory == .other)
            #expect(info.measurementAvailability == .unavailable)
            #expect(info.recoveryAction == .confirmCategoryBeforeMeasurements)
        }
    }

    @Test func userConfirmedBottomResumesVerifiedZARAMeasurements() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p01234567.html?v1=900000011"))
        let html = try String(
            contentsOf: fixtureURL("fixtures/zara_unknown_category_synthetic.html"),
            encoding: .utf8
        )
        let guide = try sizeGuideResponseData(
            from: fixtureURL("production_sample_30_cache/561619028.json")
        )
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: guide)
        )

        let info = try await parser.parse(
            from: url,
            confirmedCategory: .bottom,
            confirmedDetailCategory: .longPants,
            onProgress: { _ in }
        )

        #expect(info.category == .bottom)
        #expect(info.detailCategory == .longPants)
        #expect(info.measurementAvailability == .actualMeasurements)
        #expect(info.recoveryAction == nil)
        #expect(!info.sizes.isEmpty)
        #expect(info.sizes.contains { size in
            let kinds = Set(size.measurementRecords.map(\.displayKind))
            return kinds.contains(.waist) && kinds.contains(.hip)
        })
    }

    @Test func userConfirmedTopWithoutVerifiedUpperFieldsStillRequestsManualEntry() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p01234567.html?v1=900000011"))
        let html = try String(
            contentsOf: fixtureURL("fixtures/zara_unknown_category_synthetic.html"),
            encoding: .utf8
        )
        let guide = try sizeGuideResponseData(
            from: fixtureURL("production_sample_30_cache/561619028.json")
        )
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: guide)
        )

        do {
            _ = try await parser.parse(
                from: url,
                confirmedCategory: .top,
                confirmedDetailCategory: .shortSleeve,
                onProgress: { _ in }
            )
            Issue.record("검증되지 않은 ZARA 상의 실측 기준이 자동 비교로 통과했습니다.")
        } catch let error as ProductURLParserPartialError {
            #expect(error.productInfo.category == .top)
            #expect(error.productInfo.detailCategory == .shortSleeve)
            #expect(error.productInfo.recoveryAction == .enterMeasurementsManually)
            #expect(error.productInfo.measurementAvailability == .unavailable)
        } catch {
            Issue.record("직접 입력 복구 상태 대신 예상하지 못한 오류가 발생했습니다: \(error)")
        }
    }

    @Test func viewModelKeepsUserCategoryWhileResumingZARAImport() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p01234567.html?v1=900000011"))
        let resumedProduct = ParsedProductInfo(
            sourceURL: url,
            sourceType: .officialStore,
            sourceName: "ZARA 공식몰",
            brandName: "ZARA",
            productName: "분류 미확정 상품",
            category: .bottom,
            detailCategory: .longPants,
            sizes: [ParsedProductSize(
                name: "M",
                measurements: GarmentMeasurements(
                    shoulder: 0,
                    chest: 0,
                    totalLength: 0,
                    sleeveLength: 0,
                    waist: 39,
                    hip: 52
                ),
                measurementRecords: [
                    ParsedMeasurement(
                        value: 39,
                        measurementCode: .waistWidthEdgeToEdge,
                        displayKind: .waist,
                        methodSource: "zara",
                        inputSource: .importedSizeChart,
                        rawLabel: "zone-name-waist",
                        evidenceLevel: .officialText,
                        semanticStatus: .mapped
                    ),
                    ParsedMeasurement(
                        value: 52,
                        measurementCode: .hipWidthAtWidest,
                        displayKind: .hip,
                        methodSource: "zara",
                        inputSource: .importedSizeChart,
                        rawLabel: "zone-name-hips",
                        evidenceLevel: .officialText,
                        semanticStatus: .mapped
                    )
                ]
            )],
            productID: "900000011"
        )
        let service = ProductURLParserService(
            zaraParser: Phase15ResumableZARAParser(result: resumedProduct)
        )
        let authorityRemote = FitMatchEchoServerAuthorityRemote(
            categoryCode: "bottoms",
            detailCode: "long_pants",
            familyCode: "pants",
            lengthCode: "long"
        )
        let viewModel = ShoppingProductViewModel(
            parserService: service,
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(
                remote: authorityRemote
            )
        )
        var unresolved = resumedProduct
        unresolved.category = .other
        unresolved.detailCategory = .other
        unresolved.sizes = []
        unresolved.measurementAvailability = .unavailable
        unresolved.recoveryAction = .confirmCategoryBeforeMeasurements
        viewModel.apply(unresolved)
        viewModel.category = .bottom
        viewModel.detailCategory = .longPants

        let didResume = await viewModel.resumeZARAParsingAfterCategoryConfirmation()

        #expect(didResume)
        #expect(viewModel.category == .bottom)
        #expect(viewModel.detailCategory == .longPants)
        #expect(viewModel.productAnalysisRecoveryAction == nil)
        #expect(viewModel.sizeOptions.count == 1)
    }

    @Test func missingStructuredSectionOrFamilyFailsClosed() async throws {
        let url = try #require(URL(string: "https://www.zara.com/kr/ko/item-p01234570.html?v1=900000014"))
        let html = productHTML(
            internalProductID: "900000004",
            styleNumber: "01234570",
            catentryID: "900000014",
            section: "UNKNOWN",
            family: nil,
            subfamily: nil,
            productName: "반팔 티셔츠"
        )
        let parser = ZARAParser(
            pageLoader: Phase15ZARAPageLoader(page: .init(url: url, statusCode: 200, html: html)),
            sizeGuideLoader: Phase15ZARAGuideLoader(data: Data())
        )

        let info = try #require(await partialResult(parser: parser, url: url))
        #expect(info.category == .other)
        #expect(info.detailCategory == .other)
        #expect(info.productTargetGender == .unknown)
    }

    @Test func structuredKnitAndCardiganRemainCanonicalAfterViewModelApply() async throws {
        let cases: [(style: String, variant: String, product: String, section: String,
                     family: String, subfamily: String, expectedCategory: ClothingCategory,
                     expectedDetail: ClosetDetailCategory)] = [
            (
                "05987400", "545479232", "레귤러핏 니트 폴로셔츠", "MAN",
                "스웨터", "B. Jersey M/C", .top, .knitTop
            ),
            (
                "02893103", "545474606", "100% 울 지퍼 재킷", "WOMAN",
                "가디건", "KNIT CARDIGAN", .outer, .cardigan
            )
        ]

        for item in cases {
            let url = try #require(URL(
                string: "https://www.zara.com/kr/ko/item-p\(item.style).html?v1=\(item.variant)"
            ))
            let html = productHTML(
                internalProductID: "9\(item.style)",
                styleNumber: item.style,
                catentryID: item.variant,
                section: item.section,
                family: item.family,
                subfamily: item.subfamily,
                productName: item.product
            )
            let parser = ZARAParser(
                pageLoader: Phase15ZARAPageLoader(
                    page: .init(url: url, statusCode: 200, html: html)
                ),
                sizeGuideLoader: Phase15ZARAGuideLoader(
                    data: Data("{\"sizeGuideInfo\":null,\"measureGuideInfo\":null}".utf8)
                )
            )

            let info = try #require(await partialResult(parser: parser, url: url))
            #expect(info.category == item.expectedCategory)
            #expect(info.detailCategory == item.expectedDetail)

            let viewModel = ShoppingProductViewModel()
            viewModel.apply(info)
            #expect(viewModel.category == item.expectedCategory)
            #expect(viewModel.detailCategory == item.expectedDetail)
        }
    }

    @Test func zipJacketDoesNotMatchFurOuterwearSubstring() {
        let cardigan = ParsedClosetClassification.resolve(
            category: .outer,
            detailCategory: .cardigan,
            sourceDepths: ["WOMAN", "가디건", "KNIT CARDIGAN"],
            sourcePath: "WOMAN > 가디건 > KNIT CARDIGAN",
            productName: "100% 울 지퍼 재킷"
        )
        let furJacket = ParsedClosetClassification.resolve(
            category: .outer,
            detailCategory: .jacket,
            sourceDepths: ["WOMAN", "재킷"],
            sourcePath: "WOMAN > 재킷",
            productName: "페이크 퍼 재킷"
        )

        #expect(cardigan?.detailCategory == .cardigan)
        #expect(furJacket?.detailCategory == .mouton)
    }

    private func partialResult(parser: ZARAParser, url: URL) async -> ParsedProductInfo? {
        do {
            _ = try await parser.parse(from: url)
            Issue.record("fail-closed가 필요한 ZARA 표본이 성공으로 반환됐습니다.")
            return nil
        } catch let error as ProductURLParserPartialError {
            return error.productInfo
        } catch {
            Issue.record("부분 결과 대신 예상하지 못한 오류가 발생했습니다: \(error)")
            return nil
        }
    }

    private func expectAutomaticParsingUnavailable(parser: ZARAParser, url: URL) async {
        do {
            _ = try await parser.parse(from: url)
            Issue.record("challenge 응답이 파싱됐습니다.")
        } catch ProductURLParserError.automaticParsingUnavailable {
            // Expected explicit failure.
        } catch {
            Issue.record("예상하지 못한 challenge 오류: \(error)")
        }
    }

    private func fixtureURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ZARAAudit")
            .appendingPathComponent(relativePath)
    }

    private func sizeGuideResponseData(from cacheURL: URL) throws -> Data {
        let cache = try Data(contentsOf: cacheURL)
        let object = try JSONSerialization.jsonObject(with: cache)
        let dictionary = try #require(object as? [String: Any])
        let response = try #require(dictionary["response"])
        return try JSONSerialization.data(withJSONObject: response)
    }

    private func isShadowAmbiguousFamily(_ family: String) -> Bool {
        ["OVERALL", "TOPS AND OTHERS", "WAISTCOAT", "OVERSHIRT"].contains(family.uppercased())
    }

    private func expectedDomainForStructuredFamily(_ family: String) -> ClothingCategory? {
        switch family.uppercased() {
        case "SHIRT", "T-SHIRT", "SWEATER", "POLO SHIRT", "SWEATSHIRT":
            return .top
        case "TROUSERS", "BERMUDA", "SKIRT", "LEGGINGS", "SHORTS":
            return .bottom
        case "WIND-JACKET", "BLAZER", "TRENCH RAINCOAT", "SLEEVELESS PAD. JACKET", "CARDIGAN":
            return .outer
        case "DRESS":
            return .dress
        default:
            return nil
        }
    }

    private func expectedServiceGroup(_ candidate: String?) -> ClothingCategory? {
        switch candidate {
        case "TOP": return .top
        case "BOTTOM", "SKIRT": return .bottom
        case "OUTER": return .outer
        case "DRESS": return .dress
        case "UNDERWEAR": return .underwear
        default: return nil
        }
    }

    private func productHTML(
        internalProductID: String,
        styleNumber: String,
        catentryID: String,
        section: String,
        family: String?,
        subfamily: String?,
        productName: String = "테스트 상품",
        additionalVariantIDs: [String] = []
    ) -> String {
        let familyField = family.map { ",\"family\":\"\($0)\"" } ?? ""
        let subfamilyField = subfamily.map { ",\"subfamily\":\"\($0)\"" } ?? ""
        let structuredVariants = ([catentryID] + additionalVariantIDs)
            .map {
                #"{"@type":"Product","offers":{"url":"https://www.zara.com/kr/ko/item-p\#(styleNumber).html?v1=\#($0)"}}"#
            }
            .joined(separator: ",")
        return """
        <html><head>
        <script type="application/ld+json">{"@type":"ProductGroup","name":"\(productName)","productGroupID":"\(styleNumber)","hasVariant":[\(structuredVariants)]}</script>
        <script>zara.analyticsData = {"productId":\(internalProductID),"productRef":"\(styleNumber)-000","catentryId":\(catentryID),"section":"\(section)"\(familyField)\(subfamilyField)};</script>
        </head></html>
        """
    }

    private func verifiedUpperGuideData() -> Data {
        Data(
            """
            {"measureGuideInfo":{"sizes":[{"name":"S","measures":[
              {"zoneId":"A","tableTitleZone":"zone-name-chest","dimensions":[{"unitId":"cm","value":"48.0"}]},
              {"zoneId":"D","tableTitleZone":"zone-name-back-width","dimensions":[{"unitId":"cm","value":"42.0"}]}
            ]}]},"sizeGuideInfo":null}
            """.utf8
        )
    }
}

private struct Phase15ZARAPageLoader: ZARAProductPageLoading {
    let page: ZARAProductPage

    func load(url: URL) async throws -> ZARAProductPage {
        page
    }
}

private actor Phase15ZARAFlowRecorder {
    private var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func values() -> [String] {
        events
    }
}

private struct Phase15RecordingZARAPageLoader: ZARAProductPageLoading {
    let page: ZARAProductPage
    let event: String
    let recorder: Phase15ZARAFlowRecorder

    func load(url: URL) async throws -> ZARAProductPage {
        await recorder.record(event)
        return page
    }
}

private struct Phase15FlowRecordingZARAGuideLoader: ZARASizeGuideLoading {
    let data: Data
    let recorder: Phase15ZARAFlowRecorder

    func load(productID: String) async throws -> Data {
        await recorder.record("guide:\(productID)")
        return data
    }
}

private struct Phase15ZARAGuideLoader: ZARASizeGuideLoading {
    let data: Data

    func load(productID: String) async throws -> Data {
        data
    }
}

private struct Phase15ResumableZARAParser: ZARACategoryResumableParsing {
    let result: ParsedProductInfo

    func canParse(_ url: URL) -> Bool {
        ProductURLSupport.isZARAURL(url)
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        throw ProductURLParserError.automaticParsingUnavailable
    }

    func parse(
        from url: URL,
        confirmedCategory: ClothingCategory,
        confirmedDetailCategory: ClosetDetailCategory,
        onProgress: @escaping (ProductAnalysisPhase) -> Void
    ) async throws -> ParsedProductInfo {
        onProgress(.loadingSizeChart)
        var copy = result
        copy.category = confirmedCategory
        copy.detailCategory = confirmedDetailCategory
        copy.recoveryAction = nil
        return copy
    }
}

private actor Phase15ProductIDRecorder {
    private var productIDs: [String] = []

    func record(_ productID: String) {
        productIDs.append(productID)
    }

    func values() -> [String] {
        productIDs
    }
}

private struct Phase15RecordingZARAGuideLoader: ZARASizeGuideLoading {
    let data: Data
    let recorder: Phase15ProductIDRecorder

    func load(productID: String) async throws -> Data {
        await recorder.record(productID)
        return data
    }
}

private struct Phase15ThrowingZARAGuideLoader: ZARASizeGuideLoading {
    let error: ProductURLParserError

    func load(productID: String) async throws -> Data {
        throw error
    }
}
