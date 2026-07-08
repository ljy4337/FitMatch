import Foundation

struct MusinsaProductMetadata {
    var sourceURL: URL
    var productID: String
    var brandName: String
    var productName: String
    var category: ClothingCategory
    var detailCategory: ClosetDetailCategory
    var categoryDepth1Name: String?
    var categoryDepth2Name: String?
    var imageURLString: String?
    var price: Int?
    var canonicalURLString: String?

    func parsedProductInfo(sizes: [ParsedProductSize], parserNotice: String? = nil) -> ParsedProductInfo {
        ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: brandName,
            productName: productName,
            category: category,
            detailCategory: detailCategory,
            sizes: sizes,
            parserNotice: parserNotice,
            productID: productID,
            imageURLString: imageURLString,
            price: price,
            canonicalURLString: canonicalURLString
        )
    }
}

struct MusinsaProductMetadataParser {
    func parse(productID: String, sourceURL: URL) async -> MusinsaProductMetadata {
        do {
            let response = try await fetchProductDetail(productID: productID)
            let depth1 = response.data.category?.categoryDepth1Name
            let depth2 = response.data.category?.categoryDepth2Name
            let categoryText = depth2 ?? depth1 ?? response.data.baseCategoryFullPath
            let productName = response.data.goodsNm
            let brandName = response.data.brandInfo?.brandName
                ?? response.data.brandInfo?.brandEnglishName
                ?? response.data.brand
                ?? "Musinsa"

            return MusinsaProductMetadata(
                sourceURL: sourceURL,
                productID: productID,
                brandName: brandName,
                productName: productName,
                category: Self.mapCategory(from: categoryText),
                detailCategory: Self.mapDetailCategory(from: "\(categoryText ?? "") \(productName)"),
                categoryDepth1Name: depth1,
                categoryDepth2Name: depth2,
                imageURLString: Self.normalizeImageURL(response.data.thumbnailImageUrl),
                price: response.data.salePrice ?? response.data.finalPrice,
                canonicalURLString: "https://www.musinsa.com/products/\(productID)"
            )
        } catch {
            print("[MusinsaProductMetadataParser] API metadata failed: \(error.localizedDescription)")
            return await parseHTMLFallback(productID: productID, sourceURL: sourceURL)
        }
    }

    private func fetchProductDetail(productID: String) async throws -> MusinsaProductDetailResponse {
        guard let apiURL = URL(string: "https://goods-detail.musinsa.com/api2/goods/\(productID)") else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.musinsa.com", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        return try JSONDecoder().decode(MusinsaProductDetailResponse.self, from: data)
    }

    private func parseHTMLFallback(productID: String, sourceURL: URL) async -> MusinsaProductMetadata {
        let html = (try? await fetchHTML(from: sourceURL)) ?? ""
        let title = firstMatch(in: html, pattern: #"<title[^>]*>(.*?)</title>"#, options: [.dotMatchesLineSeparators])?.htmlDecoded
        let ogImage = metaContent(in: html, key: "property", value: "og:image")
        let canonical = firstMatch(in: html, pattern: #"<link[^>]*rel="canonical"[^>]*href="([^"]*)"[^>]*>"#)
        let productName = title?.components(separatedBy: " - ").first?.trimmingCharacters(in: .whitespacesAndNewlines)

        return MusinsaProductMetadata(
            sourceURL: sourceURL,
            productID: productID,
            brandName: "Musinsa",
            productName: productName?.isEmpty == false ? productName! : "Musinsa 상품 \(productID)",
            category: .top,
            detailCategory: .other,
            categoryDepth1Name: nil,
            categoryDepth2Name: nil,
            imageURLString: Self.normalizeImageURL(ogImage),
            price: nil,
            canonicalURLString: canonical ?? "https://www.musinsa.com/products/\(productID)"
        )
    }

    private func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return html
    }

    private func metaContent(in html: String, key: String, value: String) -> String? {
        let pattern = #"<meta[^>]*\#(key)="\#(NSRegularExpression.escapedPattern(for: value))"[^>]*content="([^"]*)"[^>]*>"#
        return firstMatch(in: html, pattern: pattern)?.htmlDecoded
    }

    private func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func mapCategory(from categoryText: String?) -> ClothingCategory {
        let text = categoryText ?? ""
        if text.contains("팬츠") || text.contains("바지") || text.contains("데님") || text.contains("하의") {
            return .bottom
        }
        if text.contains("아우터") || text.contains("재킷") || text.contains("자켓") || text.contains("코트") || text.contains("점퍼") {
            return .outer
        }
        if text.contains("원피스") {
            return .dress
        }
        if text.contains("속옷") {
            return .underwear
        }
        if text.contains("셔츠") {
            return .shirt
        }
        if text.contains("니트") {
            return .knit
        }
        if text.contains("티셔츠") || text.contains("상의") || text.contains("반소매") || text.contains("긴소매") {
            return .top
        }
        return .other
    }

    static func mapDetailCategory(from text: String) -> ClosetDetailCategory {
        if text.contains("민소매") || text.localizedCaseInsensitiveContains("sleeveless") || text.localizedCaseInsensitiveContains("tank") {
            return .sleeveless
        }
        if text.contains("반소매") || text.contains("반팔") || text.localizedCaseInsensitiveContains("short sleeve") {
            return .shortSleeve
        }
        if text.contains("긴소매") || text.contains("긴팔") || text.localizedCaseInsensitiveContains("long sleeve") {
            return .longSleeve
        }
        if text.contains("후드") || text.localizedCaseInsensitiveContains("hoodie") {
            return .hoodie
        }
        if text.contains("스웨트") || text.contains("맨투맨") || text.localizedCaseInsensitiveContains("sweat") {
            return .sweatshirt
        }
        if text.contains("셔츠") || text.localizedCaseInsensitiveContains("shirt") {
            return .shirt
        }
        if text.contains("슬랙스") || text.localizedCaseInsensitiveContains("slacks") {
            return .slacks
        }
        if text.contains("데님") || text.contains("청바지") || text.localizedCaseInsensitiveContains("denim") {
            return .denim
        }
        if text.contains("점퍼") || text.contains("블루종") || text.localizedCaseInsensitiveContains("jumper") {
            return .jumper
        }
        if text.contains("재킷") || text.contains("자켓") || text.localizedCaseInsensitiveContains("jacket") {
            return .jacket
        }
        if text.contains("코트") || text.localizedCaseInsensitiveContains("coat") {
            return .coat
        }
        if text.contains("속옷") || text.localizedCaseInsensitiveContains("underwear") {
            return .underwear
        }
        if text.contains("원피스") || text.localizedCaseInsensitiveContains("dress") {
            return .onePiece
        }
        return .other
    }

    private static func normalizeImageURL(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        if rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") {
            return rawValue
        }

        if rawValue.hasPrefix("//image.msscdn.net/") {
            return "https:" + rawValue
        }

        if rawValue.hasPrefix("/images/") {
            return "https://image.msscdn.net" + rawValue
        }

        if rawValue.hasPrefix("images/") {
            return "https://image.msscdn.net/" + rawValue
        }

        return rawValue
    }
}

private struct MusinsaProductDetailResponse: Decodable {
    let data: DataBody

    struct DataBody: Decodable {
        let goodsNm: String
        let brand: String?
        let brandInfo: BrandInfo?
        let baseCategoryFullPath: String?
        let category: Category?
        let thumbnailImageUrl: String?
        let salePrice: Int?
        let finalPrice: Int?
    }

    struct BrandInfo: Decodable {
        let brandName: String?
        let brandEnglishName: String?
    }

    struct Category: Decodable {
        let categoryDepth1Name: String?
        let categoryDepth2Name: String?
    }
}

private extension String {
    var htmlDecoded: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\u003C", with: "<")
            .replacingOccurrences(of: "\\u003E", with: ">")
            .replacingOccurrences(of: "\\u0026", with: "&")
    }
}
