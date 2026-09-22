import Foundation
import Testing
@testable import FitMatch

@MainActor
struct UniqloParserConcurrencyTests {
    @Test func chartsAndAvailabilityBeginBeforeAnyResponseAndKeepLargerChartChoice() async throws {
        let loader = UniqloControlledResponseLoader()
        let parser = UniqloSizeAPIParser(responseLoader: { url in
            try await loader.response(for: url)
        })

        let resultTask = Task { @MainActor in
            try await parser.parseWithGenericColorFallback(
                productID: "E123456",
                preferredProductIDWithColorCode: "E123456-065",
                selectedColorDisplayCode: "065",
                selectedPLDDisplayCode: "000"
            )
        }

        let expected: Set<UniqloControlledResponseLoader.Endpoint> = [
            .chart("E123456-065"), .chart("E123456-000"), .product, .stock
        ]
        await loader.waitUntilStarted(expected)
        let started = await loader.startedEndpoints()
        #expect(Set(started) == expected)
        #expect(started.count == expected.count)

        await loader.respond(
            .chart("E123456-065"),
            body: UniqloHTTPFixture.sizeChart(productID: "E123456-065", sizes: ["M"])
        )
        await loader.respond(
            .chart("E123456-000"),
            body: UniqloHTTPFixture.sizeChart(productID: "E123456-000", sizes: ["M", "L"])
        )
        await loader.respond(.product, body: UniqloHTTPFixture.productAvailability)
        await loader.respond(.stock, body: UniqloHTTPFixture.stockAvailability)

        let result = try await resultTask.value
        #expect(result.sizes.map(\.name) == ["M", "L"])
        #expect(result.sizes.first?.availabilityStatus == "AVAILABLE")
        #expect(result.sizes.last?.availabilityStatus == nil)
        #expect(result.responseCapture?.requestURL.contains("E123456-000") == true)
    }

    @Test func chartFailuresAndSameAddressKeepExistingFallbackAndRequestCounts() async throws {
        let genericChart = UniqloHTTPFixture.sizeChart(productID: "E123456-000", sizes: ["M", "L"])
        let preferredChart = UniqloHTTPFixture.sizeChart(productID: "E123456-065", sizes: ["M"])

        let preferredFailure = UniqloSizeAPIParser(responseLoader: { url in
            let endpoint = UniqloHTTPFixture.endpoint(for: url)
            return UniqloHTTPFixture.capture(
                url: url,
                status: endpoint == .chart("E123456-065") ? 500 : 200,
                body: genericChart
            )
        })
        let preferredFailureResult = try await preferredFailure.parseWithGenericColorFallback(
            productID: "E123456",
            preferredProductIDWithColorCode: "E123456-065"
        )
        #expect(preferredFailureResult.sizes.map(\.name) == ["M", "L"])

        let genericFailure = UniqloSizeAPIParser(responseLoader: { url in
            let endpoint = UniqloHTTPFixture.endpoint(for: url)
            return UniqloHTTPFixture.capture(
                url: url,
                status: endpoint == .chart("E123456-000") ? 500 : 200,
                body: preferredChart
            )
        })
        let genericFailureResult = try await genericFailure.parseWithGenericColorFallback(
            productID: "E123456",
            preferredProductIDWithColorCode: "E123456-065"
        )
        #expect(genericFailureResult.sizes.map(\.name) == ["M"])

        let calls = UniqloImmediateCallRecorder()
        let sameAddress = UniqloSizeAPIParser(responseLoader: { url in
            await calls.record(url)
            return UniqloHTTPFixture.capture(url: url, body: genericChart)
        })
        _ = try await sameAddress.parseWithGenericColorFallback(
            productID: "E123456",
            preferredProductIDWithColorCode: "E123456-000"
        )
        let sameAddressCalls = await calls.urls()
        #expect(sameAddressCalls.count == 1)
        #expect(UniqloHTTPFixture.endpoint(for: sameAddressCalls[0]) == .chart("E123456-000"))

        let bothFail = UniqloSizeAPIParser(responseLoader: { url in
            UniqloHTTPFixture.capture(url: url, status: 500, body: Data("{}".utf8))
        })
        do {
            _ = try await bothFail.parseWithGenericColorFallback(
                productID: "E123456",
                preferredProductIDWithColorCode: "E123456-065"
            )
            Issue.record("Both official charts must preserve the existing failure.")
        } catch ProductURLParserError.automaticParsingUnavailable {
            // Expected: neither official size chart can be used.
        }
    }

    @Test func tiedChartsKeepPreferredResponseAndAvailabilityFailureDoesNotRetry() async throws {
        let calls = UniqloImmediateCallRecorder()
        let parser = UniqloSizeAPIParser(responseLoader: { url in
            await calls.record(url)
            let endpoint = UniqloHTTPFixture.endpoint(for: url)
            switch endpoint {
            case .chart(let productID):
                return UniqloHTTPFixture.capture(
                    url: url,
                    body: UniqloHTTPFixture.sizeChart(productID: productID, sizes: ["M"])
                )
            case .product:
                return UniqloHTTPFixture.capture(url: url, status: 500, body: Data("{}".utf8))
            case .stock:
                return UniqloHTTPFixture.capture(url: url, body: UniqloHTTPFixture.stockAvailability)
            }
        })

        let result = try await parser.parseWithGenericColorFallback(
            productID: "E123456",
            preferredProductIDWithColorCode: "E123456-065",
            selectedColorDisplayCode: "065",
            selectedPLDDisplayCode: "000"
        )

        #expect(result.sizes.map(\.name) == ["M"])
        #expect(result.sizes[0].availabilityStatus == nil)
        #expect(result.responseCapture?.requestURL.contains("E123456-065") == true)

        let urls = await calls.urls()
        let endpoints = urls.map(UniqloHTTPFixture.endpoint(for:))
        #expect(endpoints.filter { $0 == .chart("E123456-065") }.count == 1)
        #expect(endpoints.filter { $0 == .chart("E123456-000") }.count == 1)
        #expect(endpoints.filter { $0 == .product }.count == 1)
        #expect(endpoints.filter { $0 == .stock }.count <= 1)
    }

    @Test func cancellationAfterDelayedChartsDoesNotProduceAResult() async throws {
        let loader = UniqloControlledResponseLoader()
        let parser = UniqloSizeAPIParser(responseLoader: { url in
            try await loader.response(for: url)
        })
        let resultTask = Task { @MainActor in
            try await parser.parseWithGenericColorFallback(
                productID: "E123456",
                preferredProductIDWithColorCode: "E123456-065"
            )
        }

        await loader.waitUntilStarted([.chart("E123456-065"), .chart("E123456-000")])
        resultTask.cancel()
        await loader.respond(
            .chart("E123456-065"),
            body: UniqloHTTPFixture.sizeChart(productID: "E123456-065", sizes: ["M"])
        )
        await loader.respond(
            .chart("E123456-000"),
            body: UniqloHTTPFixture.sizeChart(productID: "E123456-000", sizes: ["M"])
        )

        do {
            _ = try await resultTask.value
            Issue.record("A cancelled parser request must not return a late product result.")
        } catch is CancellationError {
            // Expected: a later chart response cannot revive the cancelled load.
        }
    }

    @Test func cancellationPropagatesToChartAndAvailabilityChildren() async throws {
        let loader = UniqloControlledResponseLoader()
        let parser = UniqloSizeAPIParser(responseLoader: { url in
            try await loader.response(for: url)
        })
        let resultTask = Task { @MainActor in
            try await parser.parseWithGenericColorFallback(
                productID: "E123456",
                preferredProductIDWithColorCode: "E123456-065",
                selectedColorDisplayCode: "065",
                selectedPLDDisplayCode: "000"
            )
        }

        let expected: Set<UniqloControlledResponseLoader.Endpoint> = [
            .chart("E123456-065"), .chart("E123456-000"), .product, .stock
        ]
        await loader.waitUntilStarted(expected)
        resultTask.cancel()
        await loader.waitUntilCancelled(expected)

        do {
            _ = try await resultTask.value
            Issue.record("A cancelled request must not recover through availability fallback.")
        } catch is CancellationError {
            // Expected: every structured child receives the parent cancellation.
        }
        #expect(await loader.cancelledEndpoints() == expected)
    }
}

private actor UniqloControlledResponseLoader {
    enum Endpoint: Hashable, Sendable {
        case chart(String)
        case product
        case stock
    }

    private var started: [Endpoint] = []
    private var continuations: [Endpoint: (URL, CheckedContinuation<FitMatchRetailerAPIResponseCapture, Error>)] = [:]
    private var cancelled: Set<Endpoint> = []

    func response(for url: URL) async throws -> FitMatchRetailerAPIResponseCapture {
        let endpoint = UniqloHTTPFixture.endpoint(for: url)
        started.append(endpoint)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[endpoint] = (url, continuation)
            }
        } onCancel: {
            Task { await self.cancel(endpoint) }
        }
    }

    func waitUntilStarted(_ expected: Set<Endpoint>) async {
        while !expected.isSubset(of: Set(started)) {
            await Task.yield()
        }
    }

    func startedEndpoints() -> [Endpoint] {
        started
    }

    func waitUntilCancelled(_ expected: Set<Endpoint>) async {
        while !expected.isSubset(of: cancelled) {
            await Task.yield()
        }
    }

    func cancelledEndpoints() -> Set<Endpoint> {
        cancelled
    }

    func respond(_ endpoint: Endpoint, status: Int = 200, body: Data) {
        guard let (url, continuation) = continuations.removeValue(forKey: endpoint) else {
            return
        }
        continuation.resume(returning: UniqloHTTPFixture.capture(url: url, status: status, body: body))
    }

    private func cancel(_ endpoint: Endpoint) {
        cancelled.insert(endpoint)
        guard let (_, continuation) = continuations.removeValue(forKey: endpoint) else {
            return
        }
        continuation.resume(throwing: CancellationError())
    }
}

private actor UniqloImmediateCallRecorder {
    private var recordedURLs: [URL] = []

    func record(_ url: URL) {
        recordedURLs.append(url)
    }

    func urls() -> [URL] {
        recordedURLs
    }
}

private enum UniqloHTTPFixture {
    static let productAvailability = Data(
        """
        {"status":"ok","result":{"l2s":[
          {"l2Id":"m-65","color":{"displayCode":"65"},"size":{"displayCode":"004","name":"M"},"pld":{"displayCode":"000"}}
        ]}}
        """.utf8
    )

    static let stockAvailability = Data(
        """
        {"status":"ok","result":{"m-65":{"statusCode":"IN_STOCK","quantity":1}}}
        """.utf8
    )

    static func sizeChart(productID: String, sizes: [String]) -> Data {
        let charts = sizes.enumerated().map { index, size in
            """
            {"name":"\(size)","sizeParts":[{"code":"body-width","name":"몸 너비","measurements":[{"value":"\(50 + index)","unit":"cm"}]}]}
            """
        }.joined(separator: ",")
        return Data(
            """
            {"status":"ok","result":[{"productId":"\(productID)","sizeChart":[\(charts)]}]}
            """.utf8
        )
    }

    static func endpoint(for url: URL) -> UniqloControlledResponseLoader.Endpoint {
        if url.path.hasSuffix("/stock") {
            return .stock
        }
        if url.path.contains("/price-groups/") {
            return .product
        }
        let productID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "productIdsWithColorCode" })?
            .value ?? ""
        return .chart(productID)
    }

    static func capture(
        url: URL,
        status: Int = 200,
        body: Data
    ) -> FitMatchRetailerAPIResponseCapture {
        FitMatchRetailerAPIResponseCapture(
            requestURL: url,
            httpStatus: status,
            collectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: body
        )
    }
}
