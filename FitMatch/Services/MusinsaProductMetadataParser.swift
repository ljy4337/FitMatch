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
    var productMetadata: ProductMetadata = ProductMetadata()

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
            canonicalURLString: canonicalURLString,
            productMetadata: productMetadata
        )
    }

    mutating func applyActualSizeTypeName(_ typeName: String?) {
        guard let typeName = typeName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !typeName.isEmpty else {
            return
        }

        let mappedCategory = MusinsaProductMetadataParser.mapCategory(from: typeName)
        let mappedDetailCategory = MusinsaProductMetadataParser.mapDetailCategory(from: typeName)

        if mappedCategory != .other {
            category = mappedCategory
        }

        if mappedDetailCategory != .other {
            detailCategory = mappedDetailCategory
        }
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
            let metadata = Self.makeProductMetadata(from: response.data)

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
                price: metadata.finalPrice ?? metadata.salePrice ?? metadata.normalPrice,
                canonicalURLString: "https://www.musinsa.com/products/\(productID)",
                productMetadata: metadata
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
            canonicalURLString: canonical ?? "https://www.musinsa.com/products/\(productID)",
            productMetadata: ProductMetadata()
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
        if text.contains("팬츠") ||
            text.contains("바지") ||
            text.contains("데님") ||
            text.contains("하의") ||
            text.contains("쇼츠") ||
            text.localizedCaseInsensitiveContains("shorts") {
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
        if text.contains("반바지") ||
            text.contains("쇼츠") ||
            text.contains("숏팬츠") ||
            text.contains("하프팬츠") ||
            text.contains("버뮤다") ||
            text.localizedCaseInsensitiveContains("shorts") ||
            text.localizedCaseInsensitiveContains("short pants") ||
            text.localizedCaseInsensitiveContains("bermuda") {
            return .shorts
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

    private static func makeProductMetadata(from data: MusinsaProductDetailResponse.DataBody) -> ProductMetadata {
        ProductMetadata(
            styleNo: data.styleNo,
            englishName: data.goodsNmEng,
            brandCode: data.brand,
            brandEnglishName: data.brandInfo?.brandEnglishName,
            brandLogoImageURLString: normalizeImageURL(data.brandInfo?.brandLogoImage),
            brandNationName: data.brandInfo?.brandNationName,
            baseCategoryFullPath: data.baseCategoryFullPath,
            categoryDepth1Code: data.category?.categoryDepth1Code,
            categoryDepth1Name: data.category?.categoryDepth1Name,
            categoryDepth2Code: data.category?.categoryDepth2Code,
            categoryDepth2Name: data.category?.categoryDepth2Name,
            sizeType: data.sizeType,
            genderCodes: data.genders ?? data.sex ?? [],
            labelNames: data.labels?.map(\.name) ?? [],
            imageURLStrings: data.goodsImages?.compactMap { normalizeImageURL($0.imageUrl) } ?? [],
            normalPrice: data.goodsPrice?.normalPrice ?? data.normalPrice,
            salePrice: data.goodsPrice?.salePrice ?? data.salePrice,
            finalPrice: data.goodsPrice?.finalPrice ?? data.finalPrice,
            discountRate: data.goodsPrice?.discountRate ?? data.discountRate,
            isSale: data.goodsPrice?.isSale ?? data.isSale ?? false,
            isOutOfStock: data.isOutOfStock ?? false,
            isRestock: data.isRestock ?? false,
            isSoonOutOfStock: data.isSoonOutOfStock ?? false,
            isLimitedQuantity: data.isLimitedQuantity ?? false,
            reviewCount: data.goodsReview?.totalCount,
            reviewSatisfactionScore: data.goodsReview?.satisfactionScore,
            seasonYear: data.seasonYear,
            season: data.season
        )
    }
}

private struct MusinsaProductDetailResponse: Decodable {
    let data: DataBody

    struct DataBody: Decodable {
        let goodsNo: Int?
        let goodsNm: String
        let goodsNmEng: String?
        let styleNo: String?
        let sex: [String]?
        let brand: String?
        let brandInfo: BrandInfo?
        let seasonYear: String?
        let season: String?
        let isSale: Bool?
        let isRestock: Bool?
        let isSoonOutOfStock: Bool?
        let isLimitedQuantity: Bool?
        let baseCategoryFullPath: String?
        let category: Category?
        let thumbnailImageUrl: String?
        let goodsImages: [GoodsImage]?
        let goodsPrice: GoodsPrice?
        let salePrice: Int?
        let normalPrice: Int?
        let finalPrice: Int?
        let discountRate: Double?
        let goodsReview: GoodsReview?
        let sizeType: String?
        let isUseSize: Bool?
        let labels: [Label]?
        let genders: [String]?
        let isOutOfStock: Bool?
    }

    struct BrandInfo: Decodable {
        let brandName: String?
        let brandEnglishName: String?
        let brandNationName: String?
        let brandLogoImage: String?
    }

    struct Category: Decodable {
        let categoryDepth1Code: String?
        let categoryDepth1Name: String?
        let categoryDepth2Code: String?
        let categoryDepth2Name: String?
        let categoryDepth3Code: String?
        let categoryDepth3Name: String?
        let categoryDepth4Code: String?
        let categoryDepth4Name: String?
    }

    struct GoodsImage: Decodable {
        let imageUrl: String?
    }

    struct GoodsPrice: Decodable {
        let salePrice: Int?
        let normalPrice: Int?
        let finalPrice: Int?
        let discountRate: Double?
        let couponPrice: Int?
        let totalDiscount: Int?
        let finalDiscount: Int?
        let isSale: Bool?
        let isLowestPrice: Bool?
    }

    struct GoodsReview: Decodable {
        let totalCount: Int?
        let satisfactionScore: Double?
        let hasSummary: Bool?
    }

    struct Label: Decodable {
        let code: String?
        let name: String
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
