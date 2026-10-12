import Foundation

/// Resolves only retailer-owned identities. Scanned options never select a size.
nonisolated struct TagProductResolver {
    enum ScanError: LocalizedError {
        case unsupported, invalidBarcode, notFound, invalidResponse
        var errorDescription: String? {
            switch self {
            case .unsupported: "유니클로 바코드 또는 무신사·자라 상품 QR을 스캔해 주세요."
            case .invalidBarcode: "바코드를 확인하지 못했어요. 다시 스캔해 주세요."
            case .notFound: "이 태그의 상품을 찾지 못했어요. 상품 링크로 다시 시도해 주세요."
            case .invalidResponse: "상품 정보를 확인하지 못했어요. 잠시 후 다시 시도해 주세요."
            }
        }
    }

    func resolve(_ payload: String) async throws -> URL {
        try Task.checkCancellation()
        if payload.allSatisfy({ $0.isASCII && $0.isNumber }) {
            let endpoint = try Self.uniqloEndpoint(payload)
            let (data, _) = try await fetch(endpoint)
            try Task.checkCancellation()
            return try Self.uniqloProductURL(data)
        }
        if let url = URL(string: payload), Self.isZaraProductURL(url) {
            // Preserve the exact selected v1/catalog entry for the existing ZARA parser.
            return url
        }
        guard var url = URL(string: payload), Self.isMusinsaURL(url) else {
            throw ScanError.unsupported
        }
        var visited = Set<URL>()
        for _ in 0..<8 {
            try Task.checkCancellation()
            guard Self.isMusinsaURL(url), visited.insert(url).inserted else { throw ScanError.notFound }
            if let product = Self.musinsaProductURL(url) { return product }
            // Printed mss.kr tags use HTTP. Upgrade before making any request.
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.scheme = "https"
            let (_, response) = try await fetch(components.url!, allowRedirect: true)
            guard (300..<400).contains(response.statusCode),
                  let location = response.value(forHTTPHeaderField: "Location"),
                  let next = URL(string: location, relativeTo: components.url)?.absoluteURL else {
                throw ScanError.notFound
            }
            url = next
        }
        throw ScanError.notFound
    }

    static func isZaraProductURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              ["www.zara.com", "zara.com"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              matches(url.path, "/kr/ko/[^/]+-p[0-9]{8}\\.html") else { return false }
        let variants = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .filter { $0.name == "v1" }
        guard variants.count <= 1 else { return false }
        if let variant = variants.first {
            guard let value = variant.value, matches(value, "[0-9]+") else { return false }
        }
        return true
    }

    static func uniqloEndpoint(_ barcode: String) throws -> URL {
        guard matches(barcode, "[0-9]{13}") else { throw ScanError.invalidBarcode }
        let digits = barcode.utf8.map { Int($0 - 48) }
        let sum = digits.prefix(12).enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 1 : 3) }
        guard (10 - sum % 10) % 10 == digits[12] else { throw ScanError.invalidBarcode }
        return URL(string: "https://www.uniqlo.com/kr/api/commerce/v5/ko/l3s/\(barcode)")!
    }

    static func uniqloProductURL(_ data: Data) throws -> URL {
        struct Code: Decodable { let displayCode: String }
        struct Product: Decodable {
            let productId: String
            let priceGroup: String
            let color: Code
            let size: Code
            let pld: Code
        }
        struct Response: Decodable { let status: String; let result: Product? }
        guard let receipt = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ScanError.invalidResponse
        }
        guard receipt.status == "ok", let product = receipt.result else { throw ScanError.notFound }
        guard matches(product.productId, "E[0-9]{6}-[0-9]{3}"),
              matches(product.priceGroup, "[0-9]{2}"), matches(product.color.displayCode, "[0-9]{2}"),
              matches(product.size.displayCode, "[0-9]{3}"), matches(product.pld.displayCode, "[0-9]{3}") else {
            throw ScanError.invalidResponse
        }
        var url = URLComponents(string: "https://www.uniqlo.com/kr/ko/products/\(product.productId)/\(product.priceGroup)")!
        url.queryItems = [URLQueryItem(name: "colorDisplayCode", value: product.color.displayCode),
                          URLQueryItem(name: "pldDisplayCode", value: product.pld.displayCode)]
        return url.url!
    }

    static func isMusinsaURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.user == nil && url.password == nil
        && (url.port == nil || url.port == 443 || url.port == 80)
        && ["mss.kr", "musinsa.onelink.me", "www.musinsa.com", "musinsa.com", "m.musinsa.com", "pdp-web.musinsa.com"].contains(url.host?.lowercased() ?? "")
    }

    static func musinsaProductURL(_ url: URL, depth: Int = 0) -> URL? {
        guard depth < 5, isMusinsaURL(url) else { return nil }
        let host = url.host?.lowercased()
        let parts = url.pathComponents.filter { $0 != "/" }
        if ["www.musinsa.com", "musinsa.com", "m.musinsa.com"].contains(host ?? ""),
           parts.count == 2, ["products", "goods"].contains(parts[0]), matches(parts[1], "[0-9]+") {
            return URL(string: "https://www.musinsa.com/products/\(parts[1])")
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if host == "pdp-web.musinsa.com", url.path == "/pdp/goods" {
            let ids = items.filter { $0.name == "goodsNo" }.compactMap(\.value)
            guard ids.count == 1, let id = ids.first, matches(id, "[0-9]+") else { return nil }
            return URL(string: "https://www.musinsa.com/products/\(id)")
        }
        if host == "musinsa.onelink.me" {
            let products = Set(items.filter { ["af_dp", "af_android_url", "af_ios_url", "af_web_dp"].contains($0.name) }
                .compactMap(\.value).compactMap(URL.init(string:))
                .compactMap { musinsaProductURL($0, depth: depth + 1) })
            return products.count == 1 ? products.first : nil
        }
        return nil
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        guard let range = value.range(of: "^(?:\(pattern))$", options: .regularExpression) else { return false }
        return range.lowerBound == value.startIndex && range.upperBound == value.endIndex
    }

    private func fetch(_ url: URL, allowRedirect: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: .ephemeral, delegate: TagRedirectStopper(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScanError.invalidResponse }
        guard (200..<300).contains(http.statusCode) || (allowRedirect && (300..<400).contains(http.statusCode)) else {
            throw ScanError.invalidResponse
        }
        return (data, http)
    }
}

private final class TagRedirectStopper: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
