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
    var isUseSize: Bool = false
    var goodsContents: String = ""
    var productMetadata: ProductMetadata = ProductMetadata()

    func parsedProductInfo(sizes: [ParsedProductSize], parserNotice: String? = nil) -> ParsedProductInfo {
        let canonical = ParsedClosetClassification.resolve(
            category: category,
            detailCategory: detailCategory,
            sourceDepths: [productMetadata.sourceCategoryDepth1, productMetadata.sourceCategoryDepth2,
                           productMetadata.sourceCategoryDepth3, productMetadata.sourceCategoryDepth4],
            sourcePath: productMetadata.sourceCategoryPath,
            productName: productName
        )
        return ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: .marketplace,
            sourceName: "무신사",
            brandName: brandName,
            productName: productName,
            category: canonical?.category ?? category,
            detailCategory: canonical?.detailCategory ?? detailCategory,
            sizes: sizes,
            parserNotice: parserNotice,
            productID: productID,
            imageURLString: imageURLString,
            price: price,
            canonicalURLString: canonicalURLString,
            sourceCategoryPath: productMetadata.sourceCategoryPath,
            sourceCategoryDepth1: productMetadata.sourceCategoryDepth1,
            sourceCategoryDepth2: productMetadata.sourceCategoryDepth2,
            sourceCategoryDepth3: productMetadata.sourceCategoryDepth3,
            sourceCategoryDepth4: productMetadata.sourceCategoryDepth4,
            productTargetGender: UserGender.productTarget(from: productMetadata.genderCodes),
            productMetadata: productMetadata,
            measurementAvailability: {
                switch productMetadata.sizeType {
                case StandardBodySizeChart.metadataMarker: return .standardSizeChart
                case StandardBodySizeChart.unavailableMarker: return .unavailable
                default: return sizes.isEmpty ? .unavailable : .actualMeasurements
                }
            }()
        )
    }

    mutating func applyActualSizeTypeName(_ typeName: String?) {
        guard let typeName = typeName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !typeName.isEmpty else {
            return
        }

        let mappedCategory = MusinsaProductMetadataParser.mapCategory(from: typeName)
        let mappedDetailCategory = MusinsaProductMetadataParser.mapDetailCategory(from: typeName)
        let hasSourceCategory =
            categoryDepth1Name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            categoryDepth2Name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        if !hasSourceCategory, mappedCategory != .other {
            category = mappedCategory
        }

        if mappedDetailCategory.isSpecificLengthCategory ||
            (!hasSourceCategory && mappedDetailCategory != .other) {
            detailCategory = mappedDetailCategory
        }
    }

    mutating func applyActualSizeProfile(typeNumber: Int?, typeName: String?) {
        if let typeNumber {
            productMetadata.sizeType = String(typeNumber)
        }
        applyActualSizeTypeName(typeName)
    }
}

private extension ClosetDetailCategory {
    var isSpecificLengthCategory: Bool {
        self == .sleeveless || self == .shortSleeve || self == .longSleeve || self == .shorts
    }
}

struct MusinsaProductMetadataParser {
    func parse(productID: String, sourceURL: URL) async -> MusinsaProductMetadata {
        do {
            let response = try await fetchProductDetail(productID: productID)
            let sourcePath = Self.categoryPath(from: response.data)
            let depth1 = sourcePath.depth1
            let depth2 = sourcePath.depth2
            let categoryText = sourcePath.depths.joined(separator: " ")
            let productName = response.data.goodsNm
            let brandName = response.data.brandInfo?.brandName
                ?? response.data.brandInfo?.brandEnglishName
                ?? response.data.brand
                ?? "Musinsa"
            let metadata = Self.makeProductMetadata(from: response.data)
            Self.logSourceCategory(
                rawSourceCategory: [
                    response.data.category?.categoryDepth1Title,
                    response.data.category?.categoryDepth2Title,
                    response.data.category?.categoryDepth3Title,
                    response.data.category?.categoryDepth4Title
                ]
                    .compactMap { Self.normalizedCategoryValue($0) }
                    .joined(separator: " / "),
                gender: UserGender.productTarget(from: metadata.genderCodes),
                sourcePath: sourcePath
            )

            return MusinsaProductMetadata(
                sourceURL: sourceURL,
                productID: productID,
                brandName: brandName,
                productName: productName,
                category: Self.mapCategory(from: categoryText),
                detailCategory: Self.mapDetailCategory(from: depth2 ?? categoryText),
                categoryDepth1Name: depth1,
                categoryDepth2Name: depth2,
                imageURLString: Self.normalizeImageURL(response.data.thumbnailImageUrl),
                price: metadata.finalPrice ?? metadata.salePrice ?? metadata.normalPrice,
                canonicalURLString: "https://www.musinsa.com/products/\(productID)",
                isUseSize: response.data.isUseSize ?? false,
                goodsContents: response.data.goodsContents ?? "",
                productMetadata: metadata
            )
        } catch {
            #if DEBUG
            FitMatchDebugLogger.event(screen: "상품 분석", action: "무신사 상품 정보 조회", state: "실패", details: "오류=\(error.localizedDescription), HTML대체파싱=시작")
            #endif
            return await parseHTMLFallback(productID: productID, sourceURL: sourceURL)
        }
    }

    private func fetchProductDetail(productID: String) async throws -> MusinsaProductDetailResponse {
        guard let apiURL = URL(string: "https://goods-detail.musinsa.com/api2/goods/\(productID)") else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.timeoutInterval = MusinsaNetworkPolicy.requestTimeout
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
            category: .other,
            detailCategory: .other,
            categoryDepth1Name: nil,
            categoryDepth2Name: nil,
            imageURLString: Self.normalizeImageURL(ogImage),
            price: nil,
            canonicalURLString: canonical ?? "https://www.musinsa.com/products/\(productID)",
            isUseSize: false,
            goodsContents: html,
            productMetadata: ProductMetadata()
        )
    }

    private func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = MusinsaNetworkPolicy.requestTimeout
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
        let depths = text
            .components(separatedBy: ">")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let umbrellaCategories = ["원피스/스커트", "경량 패딩/패딩 베스트"]
        for depth in depths.reversed() where !umbrellaCategories.contains(depth) {
            if let category = atomicCategory(from: depth) {
                return category
            }
        }
        return atomicCategory(from: text) ?? .other
    }

    private static func atomicCategory(from text: String) -> ClothingCategory? {
        if text.contains("여성 속옷 하의") || text.contains("속옷") { return .underwear }
        if text.contains("원피스") { return .dress }
        if text.contains("스커트") { return .bottom }
        if text.contains("홈웨어") { return .other }
        if text.contains("신발") || text.contains("슈즈") { return .shoes }
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
        if text.contains("셔츠") {
            return .shirt
        }
        if text.contains("니트") {
            return .knit
        }
        if text.contains("티셔츠") || text.contains("상의") || text.contains("반소매") || text.contains("긴소매") || text.contains("민소매") {
            return .top
        }
        return nil
    }

    static func mapDetailCategory(from text: String) -> ClosetDetailCategory {
        if text.contains("여성 속옷 하의") || text.contains("팬티") { return .womenPanty }
        if text.contains("홈웨어") { return .loungewear }
        if text.contains("스커트") { return .skirt }
        if text.contains("원피스") { return .onePiece }
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
        let sourcePath = categoryPath(from: data)
        let brandLogoImageURLString = normalizeImageURL(data.brandInfo?.brandLogoImage)
        let imageURLStrings = data.goodsImages?.compactMap { normalizeImageURL($0.imageUrl) } ?? []
        let normalPrice = data.goodsPrice?.normalPrice ?? data.normalPrice
        let salePrice = data.goodsPrice?.salePrice ?? data.salePrice
        let finalPrice = data.goodsPrice?.finalPrice ?? data.finalPrice
        let hasPrice = normalPrice != nil || salePrice != nil || finalPrice != nil
        let stockStatusRawValue = data.isOutOfStock == true
            ? ProductStockStatus.outOfStock.rawValue
            : ProductStockStatus.unknown.rawValue

        return ProductMetadata(
            styleNo: data.styleNo,
            englishName: data.goodsNmEng,
            brandCode: data.brand,
            brandEnglishName: data.brandInfo?.brandEnglishName,
            brandLogoImageURLString: brandLogoImageURLString,
            brandNationName: data.brandInfo?.brandNationName,
            sourceCategoryPath: sourcePath.fullPath,
            sourceCategoryDepth1: sourcePath.depth1,
            sourceCategoryDepth2: sourcePath.depth2,
            sourceCategoryDepth3: sourcePath.depth3,
            sourceCategoryDepth4: sourcePath.depth4,
            baseCategoryFullPath: sourcePath.fullPath,
            categoryDepth1Code: data.category?.categoryDepth1Code,
            categoryDepth1Name: sourcePath.depth1,
            categoryDepth2Code: data.category?.categoryDepth2Code,
            categoryDepth2Name: sourcePath.depth2,
            categoryDepth3Code: data.category?.categoryDepth3Code,
            categoryDepth3Name: sourcePath.depth3,
            categoryDepth4Code: data.category?.categoryDepth4Code,
            categoryDepth4Name: sourcePath.depth4,
            sizeType: data.sizeType,
            genderCodes: data.genders ?? data.sex ?? [],
            labelNames: data.labels?.map(\.name) ?? [],
            imageURLStrings: imageURLStrings,
            normalPrice: normalPrice,
            salePrice: salePrice,
            finalPrice: finalPrice,
            currencyCode: hasPrice ? "KRW" : nil,
            discountRate: data.goodsPrice?.discountRate ?? data.discountRate,
            isSale: data.goodsPrice?.isSale ?? data.isSale ?? false,
            isOutOfStock: data.isOutOfStock ?? false,
            stockStatusRawValue: stockStatusRawValue,
            isRestock: data.isRestock ?? false,
            isSoonOutOfStock: data.isSoonOutOfStock ?? false,
            isLimitedQuantity: data.isLimitedQuantity ?? false,
            reviewCount: data.goodsReview?.totalCount,
            reviewSatisfactionScore: data.goodsReview?.satisfactionScore,
            seasonYear: data.seasonYear,
            season: data.season
        )
    }

    private static func categoryPath(from data: MusinsaProductDetailResponse.DataBody) -> SourceCategoryPath {
        let titleDepths = [
            normalizedCategoryValue(data.category?.categoryDepth1Title),
            normalizedCategoryValue(data.category?.categoryDepth2Title),
            normalizedCategoryValue(data.category?.categoryDepth3Title),
            normalizedCategoryValue(data.category?.categoryDepth4Title)
        ]

        if titleDepths.contains(where: { $0 != nil }) {
            return SourceCategoryPath(depths: titleDepths.compactMap { $0 })
        }

        let pathParts = splitCategoryPath(data.baseCategoryFullPath)
        if !pathParts.isEmpty {
            return SourceCategoryPath(depths: pathParts)
        }

        let fallbackParts = [
            data.category?.categoryDepth1Name,
            data.category?.categoryDepth2Name,
            data.category?.categoryDepth3Name,
            data.category?.categoryDepth4Name
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return SourceCategoryPath(depths: fallbackParts)
    }

    private static func normalizedCategoryValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func splitCategoryPath(_ path: String?) -> [String] {
        guard let path else { return [] }
        return path
            .components(separatedBy: CharacterSet(charactersIn: ">/"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func logSourceCategory(rawSourceCategory: String, gender: UserGender, sourcePath: SourceCategoryPath) {
        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "무신사 원본 분류 해석",
            details: "원본=\(rawSourceCategory.isEmpty ? "없음" : rawSourceCategory), 성별=\(gender.rawValue), depth1=\(sourcePath.depth1 ?? "없음"), depth2=\(sourcePath.depth2 ?? "없음"), depth3=\(sourcePath.depth3 ?? "없음"), depth4=\(sourcePath.depth4 ?? "없음"), 경로=\(sourcePath.fullPath ?? "없음")"
        )
        #endif
    }
}

private struct SourceCategoryPath {
    let depths: [String]

    var fullPath: String? {
        depths.isEmpty ? nil : depths.joined(separator: " > ")
    }

    var depth1: String? { depth(at: 0) }
    var depth2: String? { depth(at: 1) }
    var depth3: String? { depth(at: 2) }
    var depth4: String? { depth(at: 3) }

    private func depth(at index: Int) -> String? {
        guard depths.indices.contains(index) else { return nil }
        return depths[index]
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
        let goodsContents: String?
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
        let categoryDepth1Title: String?
        let categoryDepth2Code: String?
        let categoryDepth2Name: String?
        let categoryDepth2Title: String?
        let categoryDepth3Code: String?
        let categoryDepth3Name: String?
        let categoryDepth3Title: String?
        let categoryDepth4Code: String?
        let categoryDepth4Name: String?
        let categoryDepth4Title: String?
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
