import Foundation
import Testing
@testable import FitMatch

/// Actual archived measurement bodies. ZARA page/identity shell below is
/// synthetic because the archived guide has no matching captured product page.
/// These are parser replay tests, not authenticated ingestion or live identity proof.
@MainActor
struct FitMatchReleaseRawFixtureTests {
    @Test func uniqloArchivedChartPreserves32RawFacts() throws {
        let source = try fixture("uniqlo-E465185")
        let data = try JSONSerialization.data(withJSONObject: #require(source["size_chart_payload"]))
        let sizes = try UniqloSizeAPIParser().parseSizes(from: data)
        #expect(sizes.count == 8)
        #expect(sizes.flatMap(\.measurementRecords).count == 32)
        let xs = try #require(sizes.first(where: { $0.name == "XS" }))
        #expect(xs.measurementRecords.map(\.value) == [64, 49.5, 49.5, 50])
        #expect(xs.measurementRecords.map(\.rawCode) == ["body-length-back", "shoulder-width", "body-width", "sleeve-length-cb"])
    }

    @Test func musinsaArchivedChartPreserves24RawFacts() throws {
        let data = try JSONSerialization.data(withJSONObject: fixture("musinsa-6566713"))
        let sizes = try MusinsaActualSizeAPIParser().parseActualSize(from: data, isTopCategory: false).sizes
        #expect(sizes.count == 4)
        #expect(sizes.flatMap(\.measurementRecords).count == 24)
        let small = try #require(sizes.first(where: { $0.name == "0. S" }))
        #expect(small.measurementRecords.map(\.value) == [102, 38, 56, 32, 32, 23.5])
        #expect(small.measurementRecords.map(\.rawLabel) == ["총장", "허리단면", "엉덩이단면", "허벅지단면", "밑위", "밑단단면"])
    }

    @Test func zaraArchivedGuidePreserves20RawFactsWithSyntheticPageShell() async throws {
        let body = try JSONSerialization.data(withJSONObject: #require(fixture("zara-545410220")["response"]))
        let url = URL(string: "https://www.zara.com/kr/ko/test-p04166166.html?v1=545410220")!
        let page = ZARAProductPage(url: url, statusCode: 200, html: """
        <html><head><title>Fixture shirt | ZARA</title>
        <script type="application/ld+json">{"@type":"ProductGroup","name":"Fixture shirt","productGroupID":"04166166","hasVariant":[{"@type":"Product","offers":{"url":"https://www.zara.com/kr/ko/test-p04166166.html?v1=545410220"}}]}</script>
        <script>zara.analyticsData = {"productId":545486853,"productRef":"04166166-000","catentryId":545410220,"section":"MAN","family":"셔츠","subfamily":"B. Camisería"};</script>
        </head><body></body></html>
        """)
        let parser = ZARAParser(pageLoader: ReleaseRawPageLoader(page: page),
                                sizeGuideLoader: ReleaseRawGuideLoader(body: body))
        let product = try await parser.parse(from: url)
        #expect(product.sizes.count == 4)
        #expect(product.sizes.flatMap(\.measurementRecords).count == 20)
        let small = try #require(product.sizes.first(where: { $0.name.contains("S (KR 90)") }))
        #expect(small.measurementRecords.map(\.value) == [61.5, 65.5, 58.5, 22, 53.5])
        #expect(small.measurementRecords.map(\.rawCode) == ["zone-name-chest", "zone-name-front-length", "zone-name-sleeve-length", "zone-name-arm-width", "zone-name-back-width"])
    }

    private func fixture(_ name: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("Docs/QA/ReleasePreparation20261002/data/fixtures/\(name).json")
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
    }
}

private struct ReleaseRawPageLoader: ZARAProductPageLoading {
    let page: ZARAProductPage
    func load(url: URL) async throws -> ZARAProductPage { page }
}
private struct ReleaseRawGuideLoader: ZARASizeGuideLoading {
    let body: Data
    func load(productID: String) async throws -> Data { body }
}
