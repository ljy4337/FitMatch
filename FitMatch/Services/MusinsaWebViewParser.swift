import Foundation
import WebKit

@MainActor
final class MusinsaWebViewParser: NSObject, ProductURLParsing {
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var activeWebView: WKWebView?

    func canParse(_ url: URL) -> Bool {
        url.absoluteString.lowercased().contains("musinsa")
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        let urlResolver = MusinsaURLResolver()
        guard urlResolver.extractProductID(from: url) != nil else {
            throw ProductURLParserError.unsupportedURL
        }

        let baseInfo = await loadBaseProductInfo(from: url)
        let webView = makeWebView()
        activeWebView = webView
        defer {
            webView.navigationDelegate = nil
            activeWebView = nil
        }

        try await load(url, in: webView)
        try await waitUntilDocumentReady(in: webView)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let tableText = try await extractActualSizeTableText(from: webView)
        let sizes = parseSizeTableText(tableText)
        guard !sizes.isEmpty else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        return ParsedProductInfo(
            sourceURL: url,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: baseInfo.brandName,
            productName: baseInfo.productName,
            category: baseInfo.category,
            detailCategory: baseInfo.detailCategory,
            sizes: sizes,
            parserNotice: nil
        )
    }

    private func loadBaseProductInfo(from url: URL) async -> ParsedProductInfo {
        do {
            return try await MusinsaParser().parse(from: url)
        } catch let partialError as ProductURLParserPartialError {
            return partialError.productInfo
        } catch {
            return ParsedProductInfo(
                sourceURL: url,
                sourceType: .marketplace,
                sourceName: "무신사",
                brandName: "Musinsa",
                productName: "Musinsa 상품",
                category: .top,
                detailCategory: .other,
                sizes: [],
                parserNotice: nil
            )
        }
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        return webView
    }

    private func load(_ url: URL, in webView: WKWebView) async throws {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            webView.load(request)
        }
    }

    private func waitUntilDocumentReady(in webView: WKWebView) async throws {
        for _ in 0..<10 {
            let readyState = try await evaluateJavaScript("document.readyState", in: webView) as? String
            if readyState == "interactive" || readyState == "complete" {
                return
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func extractActualSizeTableText(from webView: WKWebView) async throws -> String {
        let script = """
        (() => {
            const table =
                document.querySelector('table[class*="ActualSizeTable"]') ||
                document.querySelector('div[class*="ActualSizeTable"] table');
            return table ? table.innerText : '';
        })();
        """

        guard let tableText = try await evaluateJavaScript(script, in: webView) as? String,
              !tableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        print("[MusinsaWebViewParser] ActualSizeTable text: \(tableText.prefix(240))")
        return tableText
    }

    private func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func parseSizeTableText(_ text: String) -> [ParsedProductSize] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return []
        }

        let tabRows = lines.map { splitTableLine($0) }
        if let firstRow = tabRows.first, firstRow.count > 1 {
            return parseRows(headers: firstRow, rows: Array(tabRows.dropFirst()))
        }

        return parseSequentialCells(lines)
    }

    private func splitTableLine(_ line: String) -> [String] {
        line.components(separatedBy: "\t")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseSequentialCells(_ cells: [String]) -> [ParsedProductSize] {
        guard let headerStart = cells.firstIndex(where: { WebViewSizeTableColumn.size.matches($0.normalizedHeader) }) else {
            return []
        }

        let remaining = Array(cells[headerStart...])
        guard let bodyStart = remaining.dropFirst().firstIndex(where: { !isHeaderCell($0) }) else {
            return []
        }

        let headers = Array(remaining[..<bodyStart])
        guard !headers.isEmpty else {
            return []
        }

        let values = Array(remaining[bodyStart...])
        let columnCount = headers.count
        let rows = stride(from: 0, to: values.count, by: columnCount).compactMap { start -> [String]? in
            let end = min(start + columnCount, values.count)
            let row = Array(values[start..<end])
            return row.count == columnCount ? row : nil
        }

        return parseRows(headers: headers, rows: rows)
    }

    private func isHeaderCell(_ text: String) -> Bool {
        let header = text.normalizedHeader
        return WebViewSizeTableColumn.allCases.contains { $0.matches(header) }
    }

    private func parseRows(headers rawHeaders: [String], rows: [[String]]) -> [ParsedProductSize] {
        let headers = rawHeaders.map(\.normalizedHeader)
        return rows.compactMap { row in
            guard row.count >= 2 else {
                return nil
            }

            var valuesByHeader: [String: String] = [:]
            for (index, value) in row.enumerated() where index < headers.count {
                valuesByHeader[headers[index]] = value
            }

            guard let sizeName = value(matching: [.size], in: valuesByHeader),
                  !sizeName.isEmpty else {
                return nil
            }

            let measurements = GarmentMeasurements(
                shoulder: number(matching: [.shoulder], in: valuesByHeader) ?? 0,
                chest: number(matching: [.chest], in: valuesByHeader) ?? 0,
                totalLength: number(matching: [.totalLength, .inseam], in: valuesByHeader) ?? 0,
                sleeveLength: number(matching: [.sleeveLength], in: valuesByHeader) ?? 0,
                waist: number(matching: [.waist], in: valuesByHeader) ?? 0,
                hip: number(matching: [.hip], in: valuesByHeader) ?? 0,
                thigh: number(matching: [.thigh], in: valuesByHeader) ?? 0,
                rise: number(matching: [.rise], in: valuesByHeader) ?? 0,
                hem: number(matching: [.hem], in: valuesByHeader) ?? 0
            )

            return ParsedProductSize(name: sizeName, measurements: measurements)
        }
    }

    private func value(matching columns: [WebViewSizeTableColumn], in valuesByHeader: [String: String]) -> String? {
        for column in columns {
            if let match = valuesByHeader.first(where: { column.matches($0.key) }) {
                return match.value
            }
        }
        return nil
    }

    private func number(matching columns: [WebViewSizeTableColumn], in valuesByHeader: [String: String]) -> Double? {
        guard let text = value(matching: columns, in: valuesByHeader) else {
            return nil
        }

        let pattern = #"(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return Double(text[range])
    }
}

extension MusinsaWebViewParser: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            loadContinuation?.resume()
            loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            loadContinuation?.resume(throwing: error)
            loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            loadContinuation?.resume(throwing: error)
            loadContinuation = nil
        }
    }
}

private enum WebViewSizeTableColumn: CaseIterable {
    case size
    case shoulder
    case chest
    case totalLength
    case sleeveLength
    case waist
    case hip
    case thigh
    case rise
    case inseam
    case hem

    func matches(_ header: String) -> Bool {
        aliases.contains { header.contains($0) }
    }

    private var aliases: [String] {
        switch self {
        case .size:
            return ["사이즈", "size", "옵션"]
        case .shoulder:
            return ["어깨", "어깨너비", "shoulder"]
        case .chest:
            return ["가슴", "가슴단면", "품", "chest", "bust"]
        case .totalLength:
            return ["총장", "기장", "전체길이", "length", "bodylength"]
        case .sleeveLength:
            return ["소매", "소매길이", "화장", "sleeve"]
        case .waist:
            return ["허리", "waist"]
        case .hip:
            return ["엉덩이", "힙", "hip"]
        case .thigh:
            return ["허벅지", "thigh"]
        case .rise:
            return ["밑위", "rise"]
        case .inseam:
            return ["인심", "밑단기장", "inseam"]
        case .hem:
            return ["밑단", "hem"]
        }
    }
}

private extension String {
    var normalizedHeader: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
}
