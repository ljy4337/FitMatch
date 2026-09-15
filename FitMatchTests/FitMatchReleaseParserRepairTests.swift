import Foundation
import Testing
@testable import FitMatch

@MainActor
struct FitMatchReleaseParserRepairTests {
    @Test func preservesOfficialArmCircumferenceWithoutInventingComparisonMeaning() throws {
        let sizes = try #require(MusinsaFallbackTableParser.parseGrid([
            ["사이즈", "어깨너비", "가슴둘레", "팔둘레", "소매길이", "총장"],
            ["S", "36", "84", "28", "13", "55"],
            ["M", "37", "88", "29.5", "14", "56"],
            ["L", "39", "94", "30.5", "15", "57"]
        ], context: "단위 cm", family: .upper))
        #expect(sizes.count == 3)
        #expect(sizes.flatMap(\.measurementRecords).count == 15)
        let arms = sizes.compactMap { $0.measurementRecords.first { $0.rawLabel == "팔둘레" } }
        #expect(arms.map(\.value) == [28, 29.5, 30.5])
        #expect(arms.allSatisfy { $0.semanticStatus == .unknownDefinition && $0.displayKind == .unknown })
        var product = HeadlessJourneyFixture(provider: .musinsa).parsedProduct()
        product.sizes = sizes
        let observation = try #require(product.fitMatchProductObservationRequest())
        let sentArms = observation.payload.variants.flatMap(\.sizes).flatMap(\.measurements)
            .filter { $0.rawLabel == "팔둘레" }
        #expect(sentArms.map(\.rawValue) == [28, 29.5, 30.5])
        #expect(sizes.compactMap { $0.measurementRecords.first { $0.rawLabel == "가슴둘레" }?.value } == [84, 88, 94])
    }

    @Test func prioritizesEmbeddedOfficialFitChartBeforeLongMarketingImages() {
        let images = MusinsaFallbackImageExtractor.images(in: """
        <img src="https://image.msscdn.net/images/prd_img/marketing.jpg" width="800" height="4748">
        <img src="https://fit6.cre.ma/mixxo.cafe24.com/fit/products/12726/combined_fit_product.jpg?width=780">
        """)
        let ranked = images.sorted { $0.candidateScore > $1.candidateScore }
        #expect(ranked.first?.url.lastPathComponent == "combined_fit_product.jpg")
        #expect(ranked.first?.isExplicitSizeImage == true)
        #expect(ranked.last?.isExplicitSizeImage == false)
    }
    @Test func storedRetailerVariantSurvivesReplayAndOldPayloadRemainsReadable() throws {
        var parsed = HeadlessJourneyFixture(provider: .musinsa).parsedProduct()
        parsed.productMetadata.externalVariantID = "blue"
        let stored = Product(name: parsed.productName, category: parsed.category,
                             productCode: parsed.productID, sourceURLString: parsed.sourceURL.absoluteString,
                             metadata: parsed.productMetadata, sourceType: parsed.sourceType,
                             sourceName: parsed.sourceName)
        let replay = try #require(stored.fitMatchStoredRetailerFactsForRecompare())
        #expect(replay.productMetadata.externalVariantID == "blue")
        #expect(replay.fitMatchProductObservationRequest()?.payload.variants.first?.externalVariantID == "blue")
        let old = Data(#"{"version":1,"structuredFacts":{"family":"티셔츠"}}"#.utf8).base64EncodedString()
        let decoded = FitMatchStoredRetailerFacts.decode("__fitmatch_retailer_facts_v1__:" + old)
        #expect(decoded.hasVersionedPayload)
        #expect(decoded.externalVariantID == nil)
        #expect(decoded.structuredFacts == ["family": "티셔츠"])
    }

    @Test func prefersNumericSizeSuffixEvidenceWithoutRewritingRetailerIdentity() {
        func rows(_ names: [String]) -> [ParsedProductSize] {
            names.map { ParsedProductSize(name: $0, measurements: .init(shoulder: 36, chest: 42, totalLength: 55, sleeveLength: 13)) }
        }
        let ambiguous = rows(["S(090)", "M(O95)", "L(100)"])
        let numeric = rows(["S(090)", "M(095)", "L(100)"])
        #expect(MusinsaFallbackImageOCR.preferredSizes(ambiguous, numeric)?.map(\.name) == numeric.map(\.name))
        #expect(MusinsaFallbackImageOCR.preferredSizes(numeric, ambiguous)?.map(\.name) == numeric.map(\.name))
    }

}
