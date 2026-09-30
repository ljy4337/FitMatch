import Foundation
import XCTest
@testable import FitMatch

@MainActor
final class FitMatchCollectedFixtureReplayTests: XCTestCase {
    private struct RunConfiguration: Decodable {
        let fixtureRoot: String
        let providers: String
        let limitPerProvider: Int
        let exportPayloads: Bool
        let reportRoot: String
    }

    private struct Counts: Codable {
        var sourceRecords = 0
        var parsedProducts = 0
        var classificationOnly = 0
        var productsWithMeasurements = 0
        var sizes = 0
        var measurements = 0
        var payloads = 0
    }

    private struct Report: Codable {
        var byProvider: [String: Counts]
        var failures: [String]
    }

    func testCollectedRetailerAPIsUseCurrentSwiftParsersAndEncoder() async throws {
        let configuration = try loadRunConfiguration()
        executionTimeAllowance = 1_800

        let fixtureRoot = configuration.fixtureRoot.asFileURL
        let providerFilter = Set(
            configuration.providers
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        let limitPerProvider = max(0, configuration.limitPerProvider)
        let exportPayloads = configuration.exportPayloads
        let reportRoot = configuration.reportRoot.asFileURL
        try FileManager.default.createDirectory(
            at: reportRoot,
            withIntermediateDirectories: true
        )
        let payloadHandle = try makePayloadHandle(
            reportRoot: reportRoot,
            enabled: exportPayloads
        )
        defer { try? payloadHandle?.close() }

        var report = Report(byProvider: [:], failures: [])
        for provider in ["uniqlo", "musinsa", "zara"] where providerFilter.contains(provider) {
            let records = try activeRecords(provider: provider, fixtureRoot: fixtureRoot)
            let selected = limitPerProvider > 0
                ? Array(records.prefix(limitPerProvider))
                : records
            var counts = Counts()
            counts.sourceRecords = selected.count

            for record in selected {
                let productID = Self.text(record["product_id"]) ?? "unknown"
                do {
                    let observedAt = try collectedAt(in: record)
                    let parsed = try await replay(record: record, provider: provider)
                    counts.parsedProducts += 1
                    counts.sizes += parsed.sizes.count
                    let measurementCount = parsed.sizes.reduce(0) {
                        $0 + $1.measurementRecords.count
                    }
                    counts.measurements += measurementCount
                    if measurementCount > 0 {
                        counts.productsWithMeasurements += 1
                    } else {
                        counts.classificationOnly += 1
                    }

                    let request = try XCTUnwrap(
                        parsed.fitMatchProductObservationRequest(observedAt: observedAt),
                        "\(provider)/\(productID): observation 생성 실패"
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys]
                    let first = try encoder.encode(request)
                    let retry = try encoder.encode(request)
                    XCTAssertEqual(
                        first,
                        retry,
                        "\(provider)/\(productID): 동일 request 재인코딩 결과가 변경됨"
                    )
                    try validateEncodedRequest(
                        first,
                        provider: provider,
                        productID: productID
                    )
                    counts.payloads += 1
                    if let payloadHandle {
                        try payloadHandle.write(contentsOf: first)
                        try payloadHandle.write(contentsOf: Data([0x0A]))
                    }
                } catch {
                    report.failures.append("\(provider)/\(productID): \(error)")
                }
            }
            report.byProvider[provider] = counts
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(
            to: reportRoot.appendingPathComponent("swift-replay-report.json"),
            options: .atomic
        )
        let summaryData = try JSONEncoder().encode(report)
        print("FITMATCH_FIXTURE_REPLAY \(String(decoding: summaryData, as: UTF8.self))")
        XCTAssertTrue(
            report.failures.isEmpty,
            report.failures.prefix(20).joined(separator: "\n")
        )
    }

    private func loadRunConfiguration() throws -> RunConfiguration {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRoot.appendingPathComponent(".fitmatch-fixture-replay-config.json")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: url.path),
            "수집 fixture 재생은 scripts/run-fitmatch-fixture-tests.sh로 실행합니다."
        )
        return try JSONDecoder().decode(
            RunConfiguration.self,
            from: Data(contentsOf: url)
        )
    }

    private func activeRecords(provider: String, fixtureRoot: URL) throws -> [[String: Any]] {
        let collectorRoot = fixtureRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var result: [[String: Any]] = []
        for status in ["normal", "warning"] {
            let manifestURL = fixtureRoot.appendingPathComponent("manifest_\(status).json")
            let manifest = try Self.object(at: manifestURL)
            let items = manifest["items"] as? [[String: Any]] ?? []
            for item in items where Self.text(item["brand"]) == provider {
                guard let rawPath = Self.text(item["raw_file"]) else { continue }
                let rawURL = rawPath.hasPrefix("/")
                    ? URL(fileURLWithPath: rawPath)
                    : collectorRoot.appendingPathComponent(rawPath)
                result.append(try Self.object(at: rawURL))
            }
        }
        return result.sorted {
            (Self.text($0["product_id"]) ?? "") < (Self.text($1["product_id"]) ?? "")
        }
    }

    private func replay(
        record: [String: Any],
        provider: String
    ) async throws -> ParsedProductInfo {
        let parsed: ParsedProductInfo
        switch provider {
        case "uniqlo": parsed = try replayUniqlo(record)
        case "musinsa": parsed = try replayMusinsa(record)
        case "zara": parsed = try await replayZara(record)
        default: throw ReplayError.invalidField("unsupported provider \(provider)")
        }
        // ProductURLParserService applies this boundary before either link
        // registration or comparison builds its server observation. Fixture
        // replay must do the same so the encoded structure/measurement contract
        // is the one the shipping app actually sends.
        return parsed.normalizedSizes()
    }

    private func replayUniqlo(_ record: [String: Any]) throws -> ParsedProductInfo {
        let sourceURL = try Self.url(record["product_url"], field: "product_url")
        let productID = try Self.firstMatch(
            sourceURL.absoluteString,
            pattern: #"/products/(E\d{6})"#,
            field: "uniqlo product id"
        )
        let details = try capture(record, endpoint: "details")
        let sizeChart = try capture(record, endpoint: "size_chart")
        let detailsObject = try Self.object(from: details.body)
        let product = try Self.dictionary(detailsObject["result"], field: "details.result")
        let returnedID = try Self.string(product["productId"], field: "details.result.productId")
        let colorCode = returnedID.split(separator: "-").last.map(String.init) ?? "000"
        let hydration: [String: Any] = [
            "entity": ["pdpEntity": ["\(productID)-000": ["product": product]]]
        ]
        let hydrationData = try JSONSerialization.data(withJSONObject: hydration)
        let html = "<script>window.__PRELOADED_STATE__ = \(String(decoding: hydrationData, as: UTF8.self));</script>"
        let resolved = ResolvedUniqloURL(
            originalURL: sourceURL,
            resolvedURL: sourceURL,
            productID: productID,
            goodsID: String(productID.dropFirst()),
            apiColorCode: colorCode,
            imageColorCode: colorCode == "000" ? "00" : colorCode,
            productIDWithColorCode: returnedID,
            html: html,
            detailsAPICapture: details
        )
        let sizes = try UniqloSizeAPIParser().parseSizes(from: sizeChart.body)
        let metadata = UniqloProductMetadataParser()
            .parse(resolved: resolved)
            .withPreferredImageURL(
                try UniqloSizeAPIParser().parseResult(from: sizeChart.body).imageURLString,
                selectedColorCode: resolved.imageColorCode,
                goodsID: resolved.goodsID
            )
            .withInferredSleeveDetail(from: sizes)
        let evidence = FitMatchRetailerAPIEvidence(
            contractVersion: FitMatchRetailerAPIEvidence.v1Contract,
            sourceCode: "uniqlo",
            sourceProductKey: productID,
            identityScheme: nil,
            selectedVariantKey: nil,
            details: details,
            measurements: sizeChart
        )
        return metadata.parsedProductInfo(sizes: sizes)
            .withRetailerAPIEvidence(evidence)
    }

    private func replayMusinsa(_ record: [String: Any]) throws -> ParsedProductInfo {
        let sourceURL = try Self.url(record["product_url"], field: "product_url")
        let productID = try Self.string(record["product_id"], field: "product_id")
        let details = try capture(record, endpoint: "detail")
        let actualSize = try capture(record, endpoint: "actual_size")
        var metadata = try MusinsaProductMetadataParser().parseStoredProductDetail(
            data: details.body,
            productID: productID,
            sourceURL: sourceURL
        )
        metadata.retailerDetailsCapture = details
        let result = try MusinsaActualSizeAPIParser().parseActualSize(
            from: actualSize.body,
            isTopCategory: metadata.category.isMusinsaUpperBodyCategory
        )
        metadata.applyActualSizeProfile(
            typeNumber: result.typeNumber,
            typeName: result.typeName
        )
        let evidence = metadata.retailerAPIEvidence(measurements: actualSize)
        return metadata.parsedProductInfo(sizes: result.sizes)
            .withRetailerAPIEvidence(evidence)
    }

    private func replayZara(_ record: [String: Any]) async throws -> ParsedProductInfo {
        let sourceURL = try Self.url(record["product_url"], field: "product_url")
        let page = try capture(record, endpoint: "product_page", requiresObjectBody: false)
        let analyticsObject = try responseBody(record, endpoint: "analytics")
        let analyticsData = try JSONSerialization.data(withJSONObject: analyticsObject)
        let html = "<script>window.zara = window.zara || {}; zara.analyticsData = \(String(decoding: analyticsData, as: UTF8.self));</script>"
        let sizeGuide = try capture(record, endpoint: "size_guide")
        let details = try capture(record, endpoint: "product_details")
        let parser = ZARAParser(
            pageLoader: CollectedZARAPageLoader(page: ZARAProductPage(
                url: sourceURL,
                statusCode: page.httpStatus,
                html: html
            )),
            sizeGuideLoader: CollectedZARASizeLoader(capture: sizeGuide),
            productDetailsLoader: CollectedZARADetailsLoader(capture: details)
        )
        do {
            return try await parser.parse(from: sourceURL)
        } catch let partial as ProductURLParserPartialError {
            return partial.productInfo
        }
    }

    private func capture(
        _ record: [String: Any],
        endpoint: String,
        requiresObjectBody: Bool = true
    ) throws -> FitMatchRetailerAPIResponseCapture {
        let responses = try Self.dictionary(record["responses"], field: "responses")
        let response = try Self.dictionary(responses[endpoint], field: "responses.\(endpoint)")
        let requestURL = try Self.url(
            response["final_url"] ?? response["request_url"],
            field: "responses.\(endpoint).url"
        )
        guard let status = response["status"] as? Int else {
            throw ReplayError.invalidField("responses.\(endpoint).status")
        }
        guard let body = response["body"], !(body is NSNull) else {
            throw ReplayError.invalidField("responses.\(endpoint).body")
        }
        if requiresObjectBody, !(body is [String: Any]) {
            throw ReplayError.invalidField("responses.\(endpoint).body object")
        }
        let bodyData: Data
        if let string = body as? String {
            bodyData = Data(string.utf8)
        } else {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        }
        return FitMatchRetailerAPIResponseCapture(
            requestURL: requestURL,
            httpStatus: status,
            collectedAt: try collectedAt(in: record),
            body: bodyData
        )
    }

    private func responseBody(_ record: [String: Any], endpoint: String) throws -> Any {
        let responses = try Self.dictionary(record["responses"], field: "responses")
        let response = try Self.dictionary(responses[endpoint], field: "responses.\(endpoint)")
        guard let body = response["body"], !(body is NSNull) else {
            throw ReplayError.invalidField("responses.\(endpoint).body")
        }
        return body
    }

    private func collectedAt(in record: [String: Any]) throws -> Date {
        let value = try Self.string(record["collected_at"], field: "collected_at")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw ReplayError.invalidField("collected_at ISO-8601")
        }
        return date
    }

    private func validateEncodedRequest(
        _ data: Data,
        provider: String,
        productID: String
    ) throws {
        let request = try Self.object(from: data)
        let payload = try Self.dictionary(request["payload"], field: "payload")
        let facts = try Self.dictionary(payload["structured_facts"], field: "structured_facts")
        _ = try Self.dictionary(facts["retailer_api"], field: "structured_facts.retailer_api")
        for (key, value) in facts where key != "retailer_api" {
            guard value is String else {
                throw ReplayError.invalidField("\(provider)/\(productID) structured fact \(key) is not String")
            }
        }
        guard !Self.containsKey("catalog_decision", in: request) else {
            throw ReplayError.invalidField("\(provider)/\(productID) contains catalog_decision")
        }
        if provider == "zara" {
            let retailerAPI = try Self.dictionary(
                facts["retailer_api"],
                field: "structured_facts.retailer_api"
            )
            guard Self.text(retailerAPI["contract_version"]) == FitMatchRetailerAPIEvidence.zaraParentVariantContract,
                  Self.text(retailerAPI["source_product_key"]) == Self.text(payload["external_product_id"]),
                  let selected = Self.text(retailerAPI["selected_variant_key"]),
                  !selected.isEmpty,
                  selected != Self.text(payload["external_product_id"]) else {
                throw ReplayError.invalidField("\(provider)/\(productID) parent/variant contract")
            }
        }
    }

    private func makePayloadHandle(reportRoot: URL?, enabled: Bool) throws -> FileHandle? {
        guard enabled, let reportRoot else { return nil }
        let url = reportRoot.appendingPathComponent("swift-payloads.jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try FileHandle(forWritingTo: url)
    }

    private static func object(at url: URL) throws -> [String: Any] {
        try object(from: Data(contentsOf: url))
    }

    private static func object(from data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReplayError.invalidField("JSON object")
        }
        return value
    }

    private static func dictionary(_ value: Any?, field: String) throws -> [String: Any] {
        guard let value = value as? [String: Any] else {
            throw ReplayError.invalidField(field)
        }
        return value
    }

    private static func string(_ value: Any?, field: String) throws -> String {
        guard let value = text(value), !value.isEmpty else {
            throw ReplayError.invalidField(field)
        }
        return value
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func url(_ value: Any?, field: String) throws -> URL {
        let value = try string(value, field: field)
        guard let url = URL(string: value) else { throw ReplayError.invalidField(field) }
        return url
    }

    private static func firstMatch(
        _ value: String,
        pattern: String,
        field: String
    ) throws -> String {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: value) else {
            throw ReplayError.invalidField(field)
        }
        return String(value[swiftRange])
    }

    private static func containsKey(_ key: String, in value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            return dictionary[key] != nil || dictionary.values.contains { containsKey(key, in: $0) }
        }
        if let array = value as? [Any] {
            return array.contains { containsKey(key, in: $0) }
        }
        return false
    }
}

private struct CollectedZARAPageLoader: ZARAProductPageLoading {
    let page: ZARAProductPage
    func load(url: URL) async throws -> ZARAProductPage { page }
}

private struct CollectedZARASizeLoader: ZARASizeGuideLoading {
    let capture: FitMatchRetailerAPIResponseCapture
    func load(productID: String) async throws -> Data { capture.body }
    func loadResponse(productID: String) async throws -> FitMatchRetailerAPIResponseCapture {
        capture
    }
}

private struct CollectedZARADetailsLoader: ZARAProductDetailsLoading {
    let capture: FitMatchRetailerAPIResponseCapture
    func loadResponse(
        sourceURL: URL,
        selectedVariantID: String
    ) async throws -> FitMatchRetailerAPIResponseCapture {
        capture
    }
}

private enum ReplayError: Error, CustomStringConvertible {
    case invalidField(String)

    var description: String {
        switch self {
        case .invalidField(let field): "invalid fixture field: \(field)"
        }
    }
}

private extension String {
    var asFileURL: URL { URL(fileURLWithPath: self, isDirectory: true) }
}
