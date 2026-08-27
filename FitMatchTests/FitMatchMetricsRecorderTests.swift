import Foundation
import Testing
@testable import FitMatch

@MainActor
struct FitMatchMetricsRecorderTests {
    @Test func recorderPersistsOnlyAggregateCounterKeys() {
        let suiteName = "FitMatchTests.Metrics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let recorder = FitMatchMetricsRecorder(defaults: defaults)

        recorder.record(.appLaunch)
        recorder.record(.appLaunch)
        recorder.record(.shareConsumed(provider: .musinsa))

        let snapshot = recorder.snapshot()
        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.counters["app.launch"] == 2)
        #expect(snapshot.counters["share.consumed|provider=musinsa"] == 1)
        #expect(snapshot.lastUpdatedAt != nil)
        #expect(snapshot.counters.keys.allSatisfy { !$0.contains("http") && !$0.contains("products/") })
    }

    @Test func providerResolutionRejectsLookalikeHosts() {
        #expect(FitMatchMetricProvider.resolve(urlString: "https://www.musinsa.com/products/1") == .musinsa)
        #expect(FitMatchMetricProvider.resolve(urlString: "https://musinsa.onelink.me/PvkC/example") == .musinsa)
        #expect(FitMatchMetricProvider.resolve(urlString: "https://www.uniqlo.com/kr/ko/products/E1") == .uniqlo)
        #expect(FitMatchMetricProvider.resolve(urlString: "https://musinsa.example.com/products/1") == .unsupported)
        #expect(FitMatchMetricProvider.resolve(urlString: "not a url") == .unsupported)
    }

    @Test func diagnosticReportExportsOnlySortedAggregateCounters() {
        let suiteName = "FitMatchTests.Metrics.Export.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let recorder = FitMatchMetricsRecorder(defaults: defaults)

        recorder.record(.parserFailure(provider: .uniqlo, reason: .network))
        recorder.record(.appLaunch)
        let report = recorder.diagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(report.contains("schema_version=1"))
        #expect(report.contains("generated_at=1970-01-01T00:00:00Z"))
        #expect(report.contains("app.launch=1"))
        #expect(report.contains("parser.failure|provider=uniqlo|reason=network=1"))
        #expect(report.range(of: "app.launch=1")!.lowerBound < report.range(of: "parser.failure")!.lowerBound)
        #expect(!report.localizedCaseInsensitiveContains("http"))
        #expect(!report.localizedCaseInsensitiveContains("product"))
        #expect(!report.localizedCaseInsensitiveContains("measurement"))
    }

    @Test func productLoadRecordsFiniteParserDimensionsWithoutProductData() async {
        let metrics = MetricsRecorderSpy()
        let musinsa = MetricsProductParserStub(
            canParse: true,
            result: ParsedProductInfo(
                sourceURL: URL(string: "https://www.musinsa.com/products/123")!,
                sourceType: .marketplace,
                sourceName: "무신사",
                brandName: "테스트 브랜드",
                productName: "기록되면 안 되는 상품명",
                category: .top,
                detailCategory: .shortSleeve,
                sizes: [],
                productID: "123",
                measurementAvailability: .actualMeasurements
            )
        )
        let service = ProductURLParserService(
            musinsaParser: musinsa,
            uniqloParser: MetricsProductParserStub(canParse: false, result: nil)
        )
        let viewModel = ShoppingProductViewModel(
            initialURL: "https://www.musinsa.com/products/123",
            parserService: service,
            metricsRecorder: metrics,
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(
                remote: FitMatchEchoServerAuthorityRemote()
            )
        )

        #expect(await viewModel.loadProductInfoFromURL())
        #expect(metrics.events == [
            .parserAttempt(provider: .musinsa),
            .parserSuccess(
                provider: .musinsa,
                category: .tops,
                detail: .specific,
                measurement: .actual
            )
        ])
        #expect(metrics.events.allSatisfy { !$0.counterKey.contains("123") })
        #expect(metrics.events.allSatisfy { !$0.counterKey.contains("기록되면") })
    }

    @Test func blockedComparisonRecordsFunnelExit() async {
        let metrics = MetricsRecorderSpy()
        let viewModel = ShoppingProductViewModel(metricsRecorder: metrics)

        #expect(await viewModel.calculateRecommendation(userFits: []) == nil)
        #expect(metrics.events == [
            .comparisonAttempt(mode: .automatic),
            .comparisonBlocked(mode: .automatic, reason: .missingReference)
        ])
    }
}

private final class MetricsRecorderSpy: FitMatchMetricsRecording {
    private(set) var events: [FitMatchMetricEvent] = []

    func record(_ event: FitMatchMetricEvent) {
        events.append(event)
    }
}

@MainActor
private final class MetricsProductParserStub: ProductURLParsing {
    let canParseResult: Bool
    let result: ParsedProductInfo?

    init(canParse: Bool, result: ParsedProductInfo?) {
        canParseResult = canParse
        self.result = result
    }

    func canParse(_ url: URL) -> Bool {
        canParseResult
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        guard let result else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return result
    }
}
