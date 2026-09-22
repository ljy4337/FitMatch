import Foundation
import Testing
@testable import FitMatch

@MainActor
struct MusinsaParserConcurrencyTests {
    @Test func actualSizeAndMetadataReceiveInParallelWithoutChangingCategoryBasedParsing() async throws {
        let actualFirst = try await parseWithArrivalOrder([.actualSize, .metadata])
        let metadataFirst = try await parseWithArrivalOrder([.metadata, .actualSize])

        for product in [actualFirst, metadataFirst] {
            #expect(product.productName == "공식 반소매 티셔츠")
            #expect(product.category == .top)
            #expect(product.sizes.map(\.name) == ["M"])
            let records = product.sizes[0].measurementRecords
            #expect(records.first(where: { $0.rawLabel == "가슴단면" })?.value == 54)
            #expect(records.first(where: { $0.rawLabel == "소매길이" })?.value == 22)
            #expect(product.retailerAPIEvidence?.details.httpStatus == 200)
            #expect(product.retailerAPIEvidence?.measurements?.httpStatus == 200)
        }
    }

    @Test func metadataFailureStillUsesHTMLFallbackAndActualSizeFailureKeepsItsCapture() async throws {
        let metadata = MusinsaProductMetadataParser(
            productDetailLoader: { url in
                MusinsaHTTPFixture.capture(url: url, status: 500, body: Data("{}".utf8))
            },
            htmlLoader: { url in
                MusinsaHTTPFixture.capture(
                    url: url,
                    body: Data("<title>HTML 복구 상품 - 무신사</title>".utf8)
                )
            }
        )
        let recovered = try await metadata.parse(
            productID: "123456",
            sourceURL: MusinsaHTTPFixture.productURL
        )
        #expect(recovered.productName == "HTML 복구 상품")
        #expect(recovered.retailerDetailsCapture?.httpStatus == 500)

        let failingActual = MusinsaActualSizeAPIParser(responseLoader: { url in
            MusinsaHTTPFixture.capture(url: url, status: 502, body: Data("{}".utf8))
        })
        let parser = MusinsaParser(
            urlResolver: MusinsaURLResolver(),
            metadataParser: MusinsaProductMetadataParser(
                productDetailLoader: { url in
                    MusinsaHTTPFixture.capture(url: url, body: MusinsaHTTPFixture.metadataJSON)
                }
            ),
            actualSizeParser: failingActual,
            fallbackSizeParser: MusinsaFallbackSizeParser()
        )

        do {
            _ = try await parser.parse(
                resolved: MusinsaHTTPFixture.resolvedProduct,
                onProgress: { _ in }
            )
            Issue.record("A failed actual-size response must preserve the existing recovery path.")
        } catch let error as ProductURLParserPartialError {
            #expect(error.productInfo.retailerAPIEvidence?.measurements?.httpStatus == 502)
        }
    }

    @Test func cancellationAfterDelayedResponsesDoesNotReturnAProduct() async throws {
        let loader = MusinsaControlledResponseLoader()
        let parser = MusinsaParser(
            urlResolver: MusinsaURLResolver(),
            metadataParser: MusinsaProductMetadataParser(
                productDetailLoader: { url in try await loader.response(for: url) }
            ),
            actualSizeParser: MusinsaActualSizeAPIParser(
                responseLoader: { url in try await loader.response(for: url) }
            ),
            fallbackSizeParser: MusinsaFallbackSizeParser()
        )
        let task = Task { @MainActor in
            try await parser.parse(
                resolved: MusinsaHTTPFixture.resolvedProduct,
                onProgress: { _ in }
            )
        }

        await loader.waitUntilStarted([.metadata, .actualSize])
        task.cancel()
        await loader.respond(.metadata, body: MusinsaHTTPFixture.metadataJSON)
        await loader.respond(.actualSize, body: MusinsaHTTPFixture.actualSizeJSON)

        do {
            _ = try await task.value
            Issue.record("A cancelled MUSINSA request must not return a late product result.")
        } catch is CancellationError {
            // Expected: a later provider response cannot revive this load.
        }
    }

    @Test func metadataCancellationDoesNotStartHTMLFallback() async {
        await assertMetadataCancellationDoesNotStartHTMLFallback(
            CancellationError()
        )
    }

    @Test func metadataURLSessionCancellationDoesNotStartHTMLFallback() async {
        await assertMetadataCancellationDoesNotStartHTMLFallback(
            URLError(.cancelled)
        )
    }

    private func parseWithArrivalOrder(
        _ order: [MusinsaControlledResponseLoader.Endpoint]
    ) async throws -> ParsedProductInfo {
        let loader = MusinsaControlledResponseLoader()
        let parser = MusinsaParser(
            urlResolver: MusinsaURLResolver(),
            metadataParser: MusinsaProductMetadataParser(
                productDetailLoader: { url in try await loader.response(for: url) }
            ),
            actualSizeParser: MusinsaActualSizeAPIParser(
                responseLoader: { url in try await loader.response(for: url) }
            ),
            fallbackSizeParser: MusinsaFallbackSizeParser()
        )
        let task = Task { @MainActor in
            try await parser.parse(
                resolved: MusinsaHTTPFixture.resolvedProduct,
                onProgress: { _ in }
            )
        }

        await loader.waitUntilStarted([.metadata, .actualSize])
        let started = await loader.startedEndpoints()
        #expect(Set(started) == [.metadata, .actualSize])
        #expect(started.count == 2)
        for endpoint in order {
            switch endpoint {
            case .metadata:
                await loader.respond(.metadata, body: MusinsaHTTPFixture.metadataJSON)
            case .actualSize:
                await loader.respond(.actualSize, body: MusinsaHTTPFixture.actualSizeJSON)
            }
        }
        return try await task.value
    }

    private func assertMetadataCancellationDoesNotStartHTMLFallback(
        _ error: Error
    ) async {
        let fallbackCalls = MusinsaHTMLFallbackCallRecorder()
        let metadata = MusinsaProductMetadataParser(
            productDetailLoader: { _ in throw error },
            htmlLoader: { url in
                await fallbackCalls.record()
                return MusinsaHTTPFixture.capture(
                    url: url,
                    body: Data("<title>취소되어야 할 복구</title>".utf8)
                )
            }
        )

        do {
            _ = try await metadata.parse(
                productID: "123456",
                sourceURL: MusinsaHTTPFixture.productURL
            )
            Issue.record("A cancelled metadata request must terminate without HTML recovery.")
        } catch is CancellationError {
            // Expected: cancellation is not a metadata recovery condition.
        } catch {
            Issue.record("Expected CancellationError, received \(error).")
        }
        #expect(await fallbackCalls.count() == 0)
    }
}

private actor MusinsaHTMLFallbackCallRecorder {
    private var calls = 0

    func record() {
        calls += 1
    }

    func count() -> Int {
        calls
    }
}

private actor MusinsaControlledResponseLoader {
    enum Endpoint: Hashable, Sendable {
        case metadata
        case actualSize
    }

    private var started: [Endpoint] = []
    private var continuations: [Endpoint: (URL, CheckedContinuation<FitMatchRetailerAPIResponseCapture, Error>)] = [:]

    func response(for url: URL) async throws -> FitMatchRetailerAPIResponseCapture {
        let endpoint: Endpoint = url.path.hasSuffix("/actual-size") ? .actualSize : .metadata
        started.append(endpoint)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[endpoint] = (url, continuation)
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

    func respond(_ endpoint: Endpoint, status: Int = 200, body: Data) {
        guard let (url, continuation) = continuations.removeValue(forKey: endpoint) else {
            return
        }
        continuation.resume(returning: MusinsaHTTPFixture.capture(url: url, status: status, body: body))
    }
}

private enum MusinsaHTTPFixture {
    static let productURL = URL(string: "https://www.musinsa.com/products/123456")!
    static let resolvedProduct = ResolvedMusinsaURL(
        originalURL: productURL,
        resolvedURL: productURL,
        productID: "123456"
    )

    static let metadataJSON = Data(
        """
        {"data":{"goodsNo":123456,"goodsNm":"공식 반소매 티셔츠","isUseSize":true,
        "category":{"categoryDepth1Name":"상의","categoryDepth1Title":"상의",
        "categoryDepth2Name":"반소매 티셔츠","categoryDepth2Title":"반소매 티셔츠"}}}
        """.utf8
    )

    static let actualSizeJSON = Data(
        """
        {"data":{"typeName":"반소매티셔츠","typeNumber":5,"sizes":[{"name":"M","items":[
        {"name":"총장","value":"70"},{"name":"가슴단면","value":"54"},{"name":"소매길이","value":"22"}
        ]}]}}
        """.utf8
    )

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
