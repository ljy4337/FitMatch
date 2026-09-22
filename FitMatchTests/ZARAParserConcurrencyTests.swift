import Foundation
import Testing
@testable import FitMatch

@MainActor
struct ZARAParserConcurrencyTests {
    @Test func verifiedPageStartsDetailsBeforeSlowSelectedVariantGuideCompletes() async throws {
        let guideGate = ZARAGuideGate()
        let details = ZARADetailsRecorder()
        let parser = ZARAParser(
            pageLoader: ZARAConcurrencyPageLoader(page: ZARAConcurrencyFixture.page),
            sizeGuideLoader: ZARAConcurrencyGuideLoader(gate: guideGate),
            productDetailsLoader: ZARAConcurrencyDetailsLoader(recorder: details)
        )

        let task = Task { @MainActor in
            try await parser.parse(from: ZARAConcurrencyFixture.url)
        }
        await guideGate.waitUntilStarted()
        await details.waitUntilStarted()
        #expect(await guideGate.isFinished() == false)

        await guideGate.succeed(with: ZARAConcurrencyFixture.guideJSON)
        let product = try await task.value
        #expect(product.productID == "545486853")
        #expect(product.productMetadata.externalVariantID == "545490346")
        #expect(product.sizes.map(\.name) == ["M"])
        #expect(product.retailerAPIEvidence?.details.httpStatus == 200)
        #expect(product.retailerAPIEvidence?.measurements?.httpStatus == 200)
    }

    @Test func cancelledSlowGuideCannotProduceALateZaraProduct() async throws {
        let guideGate = ZARAGuideGate()
        let details = ZARADetailsRecorder()
        let parser = ZARAParser(
            pageLoader: ZARAConcurrencyPageLoader(page: ZARAConcurrencyFixture.page),
            sizeGuideLoader: ZARAConcurrencyGuideLoader(gate: guideGate),
            productDetailsLoader: ZARAConcurrencyDetailsLoader(recorder: details)
        )
        let task = Task { @MainActor in
            try await parser.parse(from: ZARAConcurrencyFixture.url)
        }

        await guideGate.waitUntilStarted()
        await details.waitUntilStarted()
        task.cancel()
        await guideGate.waitUntilCancelled()

        do {
            _ = try await task.value
            Issue.record("A cancelled ZARA load must not return a late product result.")
        } catch is CancellationError {
            // Expected: the caller cannot receive a result after cancellation.
        }
    }

    /// Synthetic redirect fixture: it exercises the production identity
    /// function with a resolved B variant rather than injecting an identity.
    @Test func verifiedRedirectStartsResolvedVariantGuideWithoutWaitingForSupersededV1() async throws {
        let guideGate = ZARARedirectGuideGate()
        let requestedURL = ZARAConcurrencyFixture.requestedRedirectURL
        let page = ZARAConcurrencyFixture.redirectedPage
        let identity = try #require(ZARAProductPageParser.identity(
            requestedURL: requestedURL,
            resolvedURL: page.url,
            html: page.html
        ))
        #expect(identity.catentryID == ZARAConcurrencyFixture.redirectedVariantID)

        let parser = ZARAParser(
            pageLoader: ZARAConcurrencyPageLoader(page: page),
            sizeGuideLoader: ZARARedirectGuideLoader(gate: guideGate),
            productDetailsLoader: ZARAConcurrencyDetailsLoader(
                recorder: ZARADetailsRecorder()
            )
        )
        let task = Task { @MainActor in
            try await parser.parse(from: requestedURL)
        }

        await guideGate.waitUntilStarted(
            ZARAConcurrencyFixture.requestedVariantID
        )
        await Task.yield()
        let startedResolvedGuide = await guideGate.startedProductIDs().contains(
            ZARAConcurrencyFixture.redirectedVariantID
        )
        #expect(startedResolvedGuide)
        guard startedResolvedGuide else {
            task.cancel()
            _ = try? await task.value
            return
        }

        let product = try await task.value
        #expect(product.productMetadata.externalVariantID == ZARAConcurrencyFixture.redirectedVariantID)
        #expect(await guideGate.startedProductIDs() == [
            ZARAConcurrencyFixture.requestedVariantID,
            ZARAConcurrencyFixture.redirectedVariantID
        ])
    }
}

private struct ZARAConcurrencyPageLoader: ZARAProductPageLoading {
    let page: ZARAProductPage

    func load(url: URL) async throws -> ZARAProductPage {
        page
    }
}

private struct ZARAConcurrencyGuideLoader: ZARASizeGuideLoading {
    let gate: ZARAGuideGate

    func load(productID: String) async throws -> Data {
        try await gate.waitForGuide()
    }

    func loadResponse(
        productID: String
    ) async throws -> FitMatchRetailerAPIResponseCapture {
        let body = try await gate.waitForGuide()
        return FitMatchRetailerAPIResponseCapture(
            requestURL: ZARASizeGuideLoader.requestURL(productID: productID)!,
            httpStatus: 200,
            collectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: body
        )
    }
}

private struct ZARARedirectGuideLoader: ZARASizeGuideLoading {
    let gate: ZARARedirectGuideGate

    func load(productID: String) async throws -> Data {
        try await gate.response(for: productID)
    }

    func loadResponse(
        productID: String
    ) async throws -> FitMatchRetailerAPIResponseCapture {
        let body = try await gate.response(for: productID)
        return FitMatchRetailerAPIResponseCapture(
            requestURL: ZARASizeGuideLoader.requestURL(productID: productID)!,
            httpStatus: 200,
            collectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: body
        )
    }
}

private struct ZARAConcurrencyDetailsLoader: ZARAProductDetailsLoading {
    let recorder: ZARADetailsRecorder

    func loadResponse(
        sourceURL: URL,
        selectedVariantID: String
    ) async throws -> FitMatchRetailerAPIResponseCapture {
        await recorder.recordStart()
        return FitMatchRetailerAPIResponseCapture(
            requestURL: ZARAProductDetailsLoader.requestURL(
                sourceURL: sourceURL,
                selectedVariantID: selectedVariantID
            )!,
            httpStatus: 200,
            collectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: Data("{}".utf8)
        )
    }
}

private actor ZARAGuideGate {
    private var continuation: CheckedContinuation<Data, Error>?
    private var started = false
    private var finished = false
    private var cancelled = false

    func waitForGuide() async throws -> Data {
        started = true
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { await self.cancelGuide() }
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func isFinished() -> Bool {
        finished
    }

    func waitUntilCancelled() async {
        while !cancelled {
            await Task.yield()
        }
    }

    func succeed(with data: Data) {
        finished = true
        continuation?.resume(returning: data)
        continuation = nil
    }

    private func cancelGuide() {
        cancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private actor ZARARedirectGuideGate {
    private var started: [String] = []
    private var requestedContinuation: CheckedContinuation<Data, Error>?

    func response(for productID: String) async throws -> Data {
        started.append(productID)
        if productID == ZARAConcurrencyFixture.requestedVariantID {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    requestedContinuation = continuation
                }
            } onCancel: {
                Task { await self.cancelRequestedGuide() }
            }
        }
        return ZARAConcurrencyFixture.guideJSON
    }

    func waitUntilStarted(_ productID: String) async {
        while !started.contains(productID) {
            await Task.yield()
        }
    }

    func startedProductIDs() -> [String] {
        started
    }

    private func cancelRequestedGuide() {
        requestedContinuation?.resume(throwing: CancellationError())
        requestedContinuation = nil
    }
}

private actor ZARADetailsRecorder {
    private var started = false

    func recordStart() {
        started = true
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }
}

private enum ZARAConcurrencyFixture {
    static let requestedVariantID = "545490346"
    static let redirectedVariantID = "545490347"
    static let url = URL(string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346")!
    static let requestedRedirectURL = URL(
        string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=\(requestedVariantID)"
    )!
    static let page = ZARAProductPage(
        url: url,
        statusCode: 200,
        html: """
        <html><head>
        <script type="application/ld+json">{"@type":"ProductGroup","name":"공식 셔츠","productGroupID":"04166166","hasVariant":[{"@type":"Product","offers":{"url":"https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346"}}]}</script>
        <script>zara.analyticsData = {"productId":545486853,"productRef":"04166166-000","catentryId":545490346,"section":"MAN","family":"셔츠","subfamily":"B. Camisería"};</script>
        </head></html>
        """
    )
    static let guideJSON = Data(
        """
        {"measureGuideInfo":{"sizes":[{"name":"M","measures":[
        {"zoneId":"A","tableTitleZone":"zone-name-chest","dimensions":[{"unitId":"cm","value":"54"}]},
        {"zoneId":"D","tableTitleZone":"zone-name-sleeve-length","dimensions":[{"unitId":"cm","value":"65"}]}
        ]}]},"sizeGuideInfo":null}
        """.utf8
    )
    static let redirectedPage = ZARAProductPage(
        url: URL(
            string: "https://www.zara.com/kr/ko/item-p04166166.html?v1=\(redirectedVariantID)"
        )!,
        statusCode: 200,
        html: """
        <html><head>
        <script type="application/ld+json">{"@type":"ProductGroup","name":"합성 리다이렉트 셔츠","productGroupID":"04166166","hasVariant":[{"@type":"Product","offers":{"url":"https://www.zara.com/kr/ko/item-p04166166.html?v1=545490347"}}]}</script>
        <script>zara.analyticsData = {"productId":545486853,"productRef":"04166166-000","catentryId":545490347,"section":"MAN","family":"셔츠","subfamily":"B. Camisería"};</script>
        </head></html>
        """
    )
}
