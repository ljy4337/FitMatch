import Foundation

struct ResolvedMusinsaURL {
    let originalURL: URL
    let resolvedURL: URL
    let productID: String
}

private struct MusinsaRedirectResponse {
    let url: URL
    let body: String
}

enum MusinsaNetworkPolicy {
    static let requestTimeout: TimeInterval = 12
}

struct MusinsaURLResolver {
    func resolve(_ url: URL) async throws -> ResolvedMusinsaURL {
        if let productID = extractProductID(from: url),
           let productURL = URL(string: "https://www.musinsa.com/products/\(productID)") {
            #if DEBUG
            FitMatchDebugLogger.detail(screen: "상품 분석", action: "무신사 URL 해석", details: "방식=직접, 상품ID=\(productID)")
            #endif
            return ResolvedMusinsaURL(originalURL: url, resolvedURL: productURL, productID: productID)
        }

        let redirectResponse = try await followRedirects(from: url)
        let finalURL = redirectResponse.url
        let htmlProductID = extractProductID(from: redirectResponse.body)
        let productID = extractProductID(from: finalURL) ?? extractProductID(from: url) ?? htmlProductID
        guard let productID else {
            #if DEBUG
            FitMatchDebugLogger.event(screen: "상품 분석", action: "무신사 URL 해석", state: "실패", details: "상품ID=없음")
            #endif
            throw ProductURLParserError.unsupportedURL
        }

        let resolvedProductURL = productURL(from: finalURL, fallbackProductID: productID, html: redirectResponse.body)
        #if DEBUG
        FitMatchDebugLogger.detail(screen: "상품 분석", action: "무신사 URL 해석", details: "방식=리다이렉트, 상품ID=\(productID), 최종URL=\(resolvedProductURL.absoluteString)")
        #endif
        return ResolvedMusinsaURL(originalURL: url, resolvedURL: resolvedProductURL, productID: productID)
    }

    func extractProductID(from url: URL) -> String? {
        if let productID = firstProductID(in: decodedVariants(of: url.absoluteString).joined(separator: " ")) {
            return productID
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        for item in components.queryItems ?? [] {
            guard let value = item.value else {
                continue
            }

            let candidates = decodedVariants(of: value)
            if let productID = firstProductID(in: candidates.joined(separator: " ")) {
                return productID
            }

            for candidate in candidates {
                if let nestedComponents = URLComponents(string: candidate) {
                    for nestedItem in nestedComponents.queryItems ?? [] {
                        guard let nestedValue = nestedItem.value else {
                            continue
                        }
                        if let productID = firstProductID(in: decodedVariants(of: nestedValue).joined(separator: " ")) {
                            return productID
                        }
                    }
                }
            }
        }

        return nil
    }

    func extractProductID(from text: String) -> String? {
        firstProductID(in: decodedVariants(of: text).joined(separator: " "))
    }

    private func followRedirects(from url: URL) async throws -> MusinsaRedirectResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = MusinsaNetworkPolicy.requestTimeout
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let body = String(data: data, encoding: .utf8) ?? ""
        return MusinsaRedirectResponse(url: response.url ?? url, body: body)
    }

    private func productURL(from finalURL: URL, fallbackProductID: String, html: String) -> URL {
        if finalURL.absoluteString.contains("/products/\(fallbackProductID)") {
            return finalURL
        }

        for candidate in decodedVariants(of: html) {
            if let urlString = firstProductURLString(in: candidate),
               let url = URL(string: urlString) {
                return url
            }
        }

        return URL(string: "https://www.musinsa.com/products/\(fallbackProductID)") ?? finalURL
    }

    private func firstProductURLString(in text: String) -> String? {
        let pattern = #"https://www\.musinsa\.com/products/\d+[^\s'"<>)]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }

        return String(text[range])
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstProductID(in text: String) -> String? {
        let patterns = [
            #"products/(\d+)"#,
            #"products%2[fF](\d+)"#,
            #"/goods/(\d+)"#,
            #"goods%2[fF](\d+)"#,
            #"goodsNo[=:](\d+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  let range = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[range])
        }

        return nil
    }

    private func decodedVariants(of text: String) -> [String] {
        var variants = [text]
        var current = text

        for _ in 0..<4 {
            guard let decoded = current.removingPercentEncoding,
                  decoded != current else {
                break
            }
            variants.append(decoded)
            current = decoded
        }

        return variants
    }
}
