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
        do {
            try await guideGate.waitUntilStarted()
            try await details.waitUntilStarted()
        } catch {
            await cancelAndDrain(task, guideGate: guideGate)
            throw error
        }
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

        do {
            try await guideGate.waitUntilStarted()
            try await details.waitUntilStarted()
            task.cancel()
            try await guideGate.waitUntilCancelled()
        } catch {
            await cancelAndDrain(task, guideGate: guideGate)
            throw error
        }

        do {
            _ = try await task.value
            Issue.record("A cancelled ZARA load must not return a late product result.")
        } catch is CancellationError {
            // Expected: the caller cannot receive a result after cancellation.
        }
    }

    @Test func cancellationWhilePageIsPendingCancelsSpeculativeGuideBeforePageCompletes() async throws {
        let pageGate = ZARAPendingPageGate()
        let guideGate = ZARAGuideGate()
        let details = ZARADetailsRecorder()
        let parser = ZARAParser(
            pageLoader: ZARAPendingPageLoader(gate: pageGate),
            sizeGuideLoader: ZARAConcurrencyGuideLoader(gate: guideGate),
            productDetailsLoader: ZARAConcurrencyDetailsLoader(recorder: details)
        )
        let task = Task { @MainActor in
            try await parser.parse(from: ZARAConcurrencyFixture.url)
        }

        do {
            try await pageGate.waitUntilStarted()
            try await guideGate.waitUntilStarted()
            task.cancel()
            try await guideGate.waitUntilCancelled()
            #expect(await details.hasStarted() == false)

            await pageGate.release(with: ZARAConcurrencyFixture.page)
            do {
                _ = try await task.value
                Issue.record("A cancelled page wait must not start details or return a product.")
            } catch is CancellationError {
                // Expected: cancellation remains terminal after the pending page releases.
            }
            #expect(await details.hasStarted() == false)
        } catch {
            task.cancel()
            await guideGate.forceCancel()
            await pageGate.release(with: ZARAConcurrencyFixture.page)
            _ = try? await task.value
            throw error
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

        do {
            try await guideGate.waitUntilStarted(
                ZARAConcurrencyFixture.requestedVariantID
            )
            try await guideGate.waitUntilStarted(
                ZARAConcurrencyFixture.redirectedVariantID
            )
        } catch {
            await cancelAndDrain(task, guideGate: guideGate)
            throw error
        }

        let product = try await task.value
        #expect(product.productMetadata.externalVariantID == ZARAConcurrencyFixture.redirectedVariantID)
        #expect(await guideGate.startedProductIDs() == [
            ZARAConcurrencyFixture.requestedVariantID,
            ZARAConcurrencyFixture.redirectedVariantID
        ])
    }

    private func cancelAndDrain(
        _ task: Task<ParsedProductInfo, Error>,
        guideGate: ZARAGuideGate
    ) async {
        task.cancel()
        await guideGate.forceCancel()
        _ = try? await task.value
    }

    private func cancelAndDrain(
        _ task: Task<ParsedProductInfo, Error>,
        guideGate: ZARARedirectGuideGate
    ) async {
        task.cancel()
        await guideGate.forceCancel()
        _ = try? await task.value
    }
}

private struct ZARAConcurrencyPageLoader: ZARAProductPageLoading {
    let page: ZARAProductPage

    func load(url: URL) async throws -> ZARAProductPage {
        page
    }
}

private struct ZARAPendingPageLoader: ZARAProductPageLoading {
    let gate: ZARAPendingPageGate

    func load(url: URL) async throws -> ZARAProductPage {
        try await gate.waitForPage()
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

    func waitUntilStarted() async throws {
        try await RetailerParserConcurrencyTestWait.until(
            "ZARA speculative guide did not start"
        ) {
            await self.hasStarted()
        }
    }

    func isFinished() -> Bool {
        finished
    }

    func waitUntilCancelled() async throws {
        try await RetailerParserConcurrencyTestWait.until(
            "ZARA speculative guide did not receive cancellation"
        ) {
            await self.hasCancelled()
        }
    }

    func succeed(with data: Data) {
        finished = true
        continuation?.resume(returning: data)
        continuation = nil
    }

    func forceCancel() {
        cancelGuide()
    }

    private func hasStarted() -> Bool {
        started
    }

    private func hasCancelled() -> Bool {
        cancelled
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

    func waitUntilStarted(_ productID: String) async throws {
        try await RetailerParserConcurrencyTestWait.until(
            "ZARA expected guide did not start"
        ) {
            await self.hasStarted(productID)
        }
    }

    func startedProductIDs() -> [String] {
        started
    }

    private func hasStarted(_ productID: String) -> Bool {
        started.contains(productID)
    }

    private func cancelRequestedGuide() {
        requestedContinuation?.resume(throwing: CancellationError())
        requestedContinuation = nil
    }

    func forceCancel() {
        cancelRequestedGuide()
    }
}

private actor ZARADetailsRecorder {
    private var started = false

    func recordStart() {
        started = true
    }

    func waitUntilStarted() async throws {
        try await RetailerParserConcurrencyTestWait.until(
            "ZARA details request did not start"
        ) {
            await self.hasStarted()
        }
    }

    func hasStarted() -> Bool {
        started
    }
}

/// Intentionally ignores cancellation until the fixture releases the page.
/// This proves the speculative guide is tied to the parent parse lifetime,
/// not merely to normal completion of the page request.
private actor ZARAPendingPageGate {
    private var continuation: CheckedContinuation<ZARAProductPage, Error>?
    private var started = false

    func waitForPage() async throws -> ZARAProductPage {
        started = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async throws {
        try await RetailerParserConcurrencyTestWait.until(
            "ZARA verified page did not start"
        ) {
            await self.hasStarted()
        }
    }

    func release(with page: ZARAProductPage) {
        continuation?.resume(returning: page)
        continuation = nil
    }

    private func hasStarted() -> Bool {
        started
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
