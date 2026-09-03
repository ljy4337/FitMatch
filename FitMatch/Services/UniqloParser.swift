import Foundation

struct UniqloParser: ProductURLParsing {
    private let urlResolver = UniqloURLResolver()
    private let metadataParser = UniqloProductMetadataParser()
    private let sizeParser = UniqloSizeAPIParser()

    func canParse(_ url: URL) -> Bool {
        ProductURLSupport.isUniqloURL(url)
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        try await parse(from: url, onProgress: { _ in })
    }

    func parse(
        from url: URL,
        onProgress: @escaping (ProductAnalysisPhase) -> Void
    ) async throws -> ParsedProductInfo {
        let resolved = try await urlResolver.resolve(url)
        let metadata = metadataParser.parse(resolved: resolved)
        onProgress(.loadingSizeChart)

        let sizeAPIResult: UniqloSizeAPIResult
        do {
            sizeAPIResult = try await sizeParser.parseWithGenericColorFallback(
                productID: resolved.productID,
                preferredProductIDWithColorCode: resolved.productIDWithColorCode,
                selectedColorDisplayCode: resolved.imageColorCode,
                selectedPLDDisplayCode: resolved.pldDisplayCode,
                priceGroupCode: resolved.priceGroupCode
            )
        } catch {
            if Task.isCancelled { throw CancellationError() }
            #if DEBUG
            FitMatchDebugLogger.event(screen: "상품 분석", action: "유니클로 실측 조회", state: "실패", details: "오류=\(error.localizedDescription)")
            #endif
            throw ProductURLParserPartialError(
                productInfo: metadata.parsedProductInfo(
                    sizes: [],
                    parserNotice: "상품 정보는 불러왔지만 유니클로 사이즈표를 찾지 못했어요. 상품 URL을 다시 확인해 주세요."
                )
            )
        }
        let sizes = sizeAPIResult.sizes
        let resolvedMetadata = metadata
            .withPreferredImageURL(
                sizeAPIResult.imageURLString,
                selectedColorCode: resolved.imageColorCode,
                goodsID: resolved.goodsID
            )
            .withInferredSleeveDetail(from: sizes)

        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "유니클로 파싱 완료",
            details: "상품ID=\(resolved.productID), 색상=\(resolved.imageColorCode), 상품=\(resolvedMetadata.productName), 분류=\(resolvedMetadata.category.rawValue)/\(resolvedMetadata.detailCategory.rawValue), 사이즈수=\(sizes.count)"
        )
        #endif

        guard !sizes.isEmpty else {
            throw ProductURLParserPartialError(
                productInfo: resolvedMetadata.parsedProductInfo(
                    sizes: [],
                    parserNotice: "상품 정보는 불러왔지만 유니클로 사이즈표를 찾지 못했어요. 상품 URL을 다시 확인해 주세요."
                )
            )
        }

        return resolvedMetadata.parsedProductInfo(sizes: sizes)
    }
}

struct ResolvedUniqloURL {
    let originalURL: URL
    let resolvedURL: URL
    let productID: String
    let goodsID: String
    let apiColorCode: String
    let imageColorCode: String
    let productIDWithColorCode: String
    let html: String
    var pldDisplayCode: String? = nil
    var priceGroupCode: String = "00"
}

struct UniqloURLResolver {
    func resolve(_ url: URL) async throws -> ResolvedUniqloURL {
        let response = try await fetchHTML(from: url)
        let finalURL = response.url
        let haystack = "\(url.absoluteString) \(finalURL.absoluteString) \(response.body)"

        guard let productID = extractProductID(from: haystack) else {
            #if DEBUG
            FitMatchDebugLogger.event(screen: "상품 분석", action: "유니클로 URL 해석", state: "실패", details: "상품ID=없음")
            #endif
            throw ProductURLParserError.unsupportedURL
        }

        let goodsID = productID.dropFirstE
        let rawColorCode = resolveColorCode(
            originalURL: url,
            resolvedURL: finalURL,
            fallbackText: haystack,
            productID: productID,
            goodsID: goodsID
        ) ?? "00"
        let apiColorCode = normalizeAPIColorCode(rawColorCode)
        let imageColorCode = normalizeImageColorCode(rawColorCode)
        let productIDWithColorCode = "\(productID)-\(apiColorCode)"
        let pldDisplayCode = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == "pldDisplayCode" })?.value
        let productPathIndex = finalURL.pathComponents.firstIndex(where: {
            $0.localizedCaseInsensitiveCompare(productID) == .orderedSame
                || $0.uppercased().hasPrefix("\(productID.uppercased())-")
        })
        let priceGroupCode = productPathIndex.flatMap { index -> String? in
            let nextIndex = finalURL.pathComponents.index(after: index)
            guard finalURL.pathComponents.indices.contains(nextIndex) else { return nil }
            let value = finalURL.pathComponents[nextIndex]
            return value.isEmpty ? nil : value
        } ?? "00"
        let resolvedURL = canonicalURL(productID: productID, colorCode: imageColorCode, fallback: finalURL)
        let metadataHTML: String
        if let detailsHydration = try? await fetchProductDetailsHydration(productID: productID) {
            // The KR PDP is sometimes an Akamai Access Denied document while
            // the official Commerce API remains available. Append only the
            // selected provider product as hydration data so the existing
            // metadata parser can still consume retailer-owned name,
            // audience, and complete ordered breadcrumbs.
            metadataHTML = response.body + detailsHydration
        } else {
            metadataHTML = response.body
        }

        #if DEBUG
        FitMatchDebugLogger.detail(screen: "상품 분석", action: "유니클로 URL 해석", details: "상품ID=\(productID), goodsID=\(goodsID), API색상=\(apiColorCode), 이미지색상=\(imageColorCode)")
        #endif

        return ResolvedUniqloURL(
            originalURL: url,
            resolvedURL: resolvedURL,
            productID: productID,
            goodsID: goodsID,
            apiColorCode: apiColorCode,
            imageColorCode: imageColorCode,
            productIDWithColorCode: productIDWithColorCode,
            html: metadataHTML,
            pldDisplayCode: pldDisplayCode,
            priceGroupCode: priceGroupCode
        )
    }

    func extractProductID(from text: String) -> String? {
        let patterns = [
            #"products/(E\d{6})"#,
            #"\b(E\d{6})[-_/]?\d{2,3}\b"#,
            #"productId["'=:\s]+(E\d{6})"#,
            #"goodsId["'=:\s]+(\d{6})"#,
            #"imagesgoods/(\d{6})"#
        ]

        for pattern in patterns {
            if let value = firstMatch(in: decodedVariants(of: text).joined(separator: " "), pattern: pattern) {
                return value.hasPrefix("E") ? value : "E\(value)"
            }
        }

        return nil
    }

    func extractColorCode(from text: String, productID: String, goodsID: String) -> String? {
        let decodedText = decodedVariants(of: text).joined(separator: " ")
        let escapedProductID = NSRegularExpression.escapedPattern(for: productID)
        let escapedGoodsID = NSRegularExpression.escapedPattern(for: goodsID)
        let patterns = [
            #"\#(escapedProductID)-(\d{2,3})"#,
            #"colorDisplayCode[=:"'\s]+(\d{2,3})"#,
            #"colorCode[=:"'\s]+(\d{2,3})"#,
            #"colCode[=:"'\s]+(\d{2,3})"#,
            #"krgoods_(\d{2,3})_\#(escapedGoodsID)"#,
            #"goods_\#(escapedGoodsID).*?color.*?(\d{2,3})"#
        ]

        for pattern in patterns {
            if let value = firstMatch(in: decodedText, pattern: pattern) {
                return value
            }
        }

        return nil
    }

    func resolveColorCode(
        originalURL: URL,
        resolvedURL: URL,
        fallbackText: String,
        productID: String,
        goodsID: String
    ) -> String? {
        queryColorCode(in: originalURL)
            ?? queryColorCode(in: resolvedURL)
            ?? extractColorCode(from: fallbackText, productID: productID, goodsID: goodsID)
    }

    func normalizeAPIColorCode(_ colorCode: String) -> String {
        let digits = colorCode.filter(\.isNumber)
        if digits.count >= 3 {
            return String(digits.suffix(3))
        }
        return digits.leftPadded(toLength: 3, with: "0")
    }

    func normalizeImageColorCode(_ colorCode: String) -> String {
        let digits = colorCode.filter(\.isNumber)
        if digits.count >= 2 {
            return String(digits.suffix(2))
        }
        return digits.leftPadded(toLength: 2, with: "0")
    }

    private func fetchHTML(from url: URL) async throws -> UniqloHTMLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("https://www.uniqlo.com/kr/ko/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""
        return UniqloHTMLResponse(url: response.url ?? url, body: html)
    }

    private func fetchProductDetailsHydration(productID: String) async throws -> String {
        let coreID = productID.uppercased().hasSuffix("-000")
            ? productID.uppercased()
            : "\(productID.uppercased())-000"
        guard var components = URLComponents(
            string: "https://www.uniqlo.com/kr/api/commerce/v5/ko/products/\(coreID)/price-groups/00/details"
        ) else {
            throw ProductURLParserError.unsupportedURL
        }
        components.queryItems = [
            URLQueryItem(name: "includeModelSize", value: "true"),
            URLQueryItem(name: "imageRatio", value: "3x4"),
            URLQueryItem(name: "httpFailure", value: "true")
        ]
        guard let url = components.url else {
            throw ProductURLParserError.unsupportedURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.uniqlo.com/kr/ko/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["status"] as? String)?.lowercased() == "ok",
              let product = root["result"] as? [String: Any],
              let returnedID = product["productId"] as? String,
              returnedID.uppercased().hasPrefix(productID.uppercased()) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        let hydration: [String: Any] = [
            "entity": [
                "pdpEntity": [
                    coreID: ["product": product]
                ]
            ]
        ]
        let hydrationData = try JSONSerialization.data(withJSONObject: hydration)
        guard let json = String(data: hydrationData, encoding: .utf8) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return "<script>window.__PRELOADED_STATE__ = \(json);</script>"
    }

    private func canonicalURL(productID: String, colorCode: String, fallback: URL) -> URL {
        URL(string: "https://www.uniqlo.com/kr/ko/products/\(productID)?colorDisplayCode=\(colorCode)") ?? fallback
    }

    private func queryColorCode(in url: URL) -> String? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.compare("colorDisplayCode", options: .caseInsensitive) == .orderedSame })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[range])
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

private struct UniqloHTMLResponse {
    let url: URL
    let body: String
}

struct UniqloSizeAPIResult {
    var sizes: [ParsedProductSize]
    var imageURLString: String?
}

enum UniqloImageURLPolicy {
    static func defaultImageURLString(productCode: String?) -> String? {
        guard let goodsID = goodsID(productCode: productCode) else { return nil }
        return "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/\(goodsID)/item/krgoods_00_\(goodsID)_3x4.jpg?width=400"
    }

    static func candidateURLs(primaryURL: URL?) -> [URL] {
        var candidates: [URL] = []
        if let primaryURL {
            candidates.append(primaryURL)
        }
        if let primaryURL,
           let fallback = defaultImageURL(from: primaryURL),
           fallback != primaryURL {
            candidates.append(fallback)
        }
        return candidates
    }

    static func containsGoodsID(_ imageURLString: String, goodsID: String) -> Bool {
        imageURLString.localizedCaseInsensitiveContains("_\(goodsID)_")
            || imageURLString.localizedCaseInsensitiveContains("/imagesgoods/\(goodsID)/")
    }

    private static func defaultImageURL(from primaryURL: URL) -> URL? {
        guard primaryURL.host?.localizedCaseInsensitiveContains("uniqlo.com") == true,
              let goodsID = firstMatch(
                in: primaryURL.path,
                pattern: #"/imagesgoods/(\d{6})/"#
              ) else {
            return nil
        }
        return defaultImageURLString(productCode: "E\(goodsID)").flatMap(URL.init(string:))
    }

    private static func goodsID(productCode: String?) -> String? {
        guard let normalized = productCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
              let goodsID = firstMatch(in: normalized, pattern: #"^E?(\d{6})$"#) else {
            return nil
        }
        return goodsID
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}

struct UniqloSizeAPIParser {
    static func genericProductIDWithColorCode(for productID: String) -> String {
        "\(productID)-000"
    }

    static func shouldRetryWithGenericColor(
        preferredProductIDWithColorCode: String,
        genericProductIDWithColorCode: String,
        result: UniqloSizeAPIResult
    ) -> Bool {
        result.sizes.isEmpty
            && preferredProductIDWithColorCode != genericProductIDWithColorCode
    }

    func parseWithGenericColorFallback(
        productID: String,
        preferredProductIDWithColorCode: String,
        selectedColorDisplayCode: String? = nil,
        selectedPLDDisplayCode: String? = nil,
        priceGroupCode: String = "00"
    ) async throws -> UniqloSizeAPIResult {
        let genericProductIDWithColorCode = Self.genericProductIDWithColorCode(for: productID)
        let baseResult: UniqloSizeAPIResult
        do {
            let preferredResult = try await parse(
                productIDWithColorCode: preferredProductIDWithColorCode
            )
            guard Self.shouldRetryWithGenericColor(
                preferredProductIDWithColorCode: preferredProductIDWithColorCode,
                genericProductIDWithColorCode: genericProductIDWithColorCode,
                result: preferredResult
            ) else {
                baseResult = preferredResult
                return await applyingLiveAvailabilityIfAvailable(
                    to: baseResult,
                    productID: productID,
                    colorDisplayCode: selectedColorDisplayCode,
                    pldDisplayCode: selectedPLDDisplayCode,
                    priceGroupCode: priceGroupCode
                )
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            guard preferredProductIDWithColorCode != genericProductIDWithColorCode else {
                throw error
            }
        }

        baseResult = try await parse(productIDWithColorCode: genericProductIDWithColorCode)
        return await applyingLiveAvailabilityIfAvailable(
            to: baseResult,
            productID: productID,
            colorDisplayCode: selectedColorDisplayCode,
            pldDisplayCode: selectedPLDDisplayCode,
            priceGroupCode: priceGroupCode
        )
    }

    /// Joins the official size-chart records with UNIQLO's official L2 SKU
    /// inventory facts. A failed product lookup intentionally leaves stock
    /// UNKNOWN rather than guessing from the existence of a size chart.
    private func applyingLiveAvailabilityIfAvailable(
        to result: UniqloSizeAPIResult,
        productID: String,
        colorDisplayCode: String?,
        pldDisplayCode: String?,
        priceGroupCode: String
    ) async -> UniqloSizeAPIResult {
        guard let colorDisplayCode else { return result }
        do {
            async let productData = fetchProductData(
                productID: productID,
                priceGroupCode: priceGroupCode
            )
            async let stockData = fetchStockData(
                productID: productID,
                priceGroupCode: priceGroupCode
            )
            let (productPayload, stockPayload) = try await (productData, stockData)
            return UniqloSizeAPIResult(
                sizes: try applyingAvailability(
                    productData: productPayload,
                    stockData: stockPayload,
                    to: result.sizes,
                    colorDisplayCode: colorDisplayCode,
                    pldDisplayCode: pldDisplayCode
                ),
                imageURLString: result.imageURLString
            )
        } catch {
            return result
        }
    }

    func applyingAvailability(
        productData: Data,
        stockData: Data,
        to sizes: [ParsedProductSize],
        colorDisplayCode: String,
        pldDisplayCode: String? = nil,
        observedAt: Date = Date()
    ) throws -> [ParsedProductSize] {
        let productResponse = try JSONDecoder().decode(
            UniqloProductAvailabilityResponse.self,
            from: productData
        )
        let stockResponse = try JSONDecoder().decode(
            UniqloProductStockResponse.self,
            from: stockData
        )
        let normalizedColor = Self.normalizedDisplayCode(colorDisplayCode)
        let normalizedPLD = pldDisplayCode.map(Self.normalizedDisplayCode)
        let matching = productResponse.result.l2s.filter { item in
            Self.normalizedDisplayCode(item.color.displayCode) == normalizedColor
                && (normalizedPLD == nil
                    || Self.normalizedDisplayCode(item.pld.displayCode) == normalizedPLD)
        }
        let bySize = Dictionary(grouping: matching) {
            ParsedProductSizeNormalizer.normalizedSizeKey(for: $0.size.name)
        }

        return sizes.map { size in
            var copy = size
            let sizeKey = ParsedProductSizeNormalizer.normalizedSizeKey(for: size.name)
            guard let items = bySize[sizeKey], !items.isEmpty else { return copy }

            // Multiple provider rows can exist for one displayed size when a
            // length/PLD was not selected. Mark AVAILABLE only when every
            // matched row agrees; otherwise retain a fail-closed UNKNOWN.
            let stockFacts = items.compactMap { item in
                stockResponse.result[item.l2Id].map { (item, $0) }
            }
            guard stockFacts.count == items.count else { return copy }
            let statuses = Set(stockFacts.map { Self.normalizedStockStatus($0.1.statusCode) })
            guard statuses.count == 1,
                  let status = statuses.first,
                  status != "UNKNOWN" else { return copy }
            copy.availabilityStatus = status
            copy.availabilityObservedAt = observedAt
            copy.availabilityValidUntil = observedAt.addingTimeInterval(15 * 60)
            copy.availabilityEvidence = [
                "provider": "uniqlo_kr",
                "provider_entity": "l2_stock",
                "stock_status_code": stockFacts[0].1.statusCode,
                "stock_quantity": stockFacts[0].1.quantity.map(String.init) ?? "",
                "color_display_code": items[0].color.displayCode,
                "size_display_code": items[0].size.displayCode,
                "pld_display_code": items[0].pld.displayCode,
                "l2_id": items[0].l2Id
            ]
            return copy
        }
    }

    private func fetchProductData(
        productID: String,
        priceGroupCode: String
    ) async throws -> Data {
        guard let url = URL(string:
            "https://www.uniqlo.com/kr/api/commerce/v5/ko/products/\(productID)-000/price-groups/\(priceGroupCode)?httpFailure=true"
        ) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return try await fetchData(from: url)
    }

    private func fetchStockData(
        productID: String,
        priceGroupCode: String
    ) async throws -> Data {
        guard let url = URL(string:
            "https://www.uniqlo.com/kr/api/commerce/v5/ko/products/\(productID)-000/price-groups/\(priceGroupCode)/stock?httpFailure=true"
        ) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return try await fetchData(from: url)
    }

    private static func normalizedStockStatus(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "IN_STOCK", "LOW_STOCK": return "AVAILABLE"
        case "STOCK_OUT", "OUT_OF_STOCK", "SOLD_OUT": return "SOLD_OUT"
        default: return "UNKNOWN"
        }
    }

    private static func normalizedDisplayCode(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 3, trimmed.hasPrefix("0") else { return trimmed }
        return String(trimmed.dropFirst())
    }

    func parse(productIDWithColorCode: String) async throws -> UniqloSizeAPIResult {
        guard var components = URLComponents(string: "https://www.uniqlo.com/kr/api/commerce/v5/ko/products/size-charts") else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        components.queryItems = [
            URLQueryItem(name: "productIdsWithColorCode", value: productIDWithColorCode),
            URLQueryItem(name: "includeBodyMeasurements", value: "true"),
            URLQueryItem(name: "simpleSizeChart", value: "true"),
            URLQueryItem(name: "httpFailure", value: "true")
        ]

        guard let apiURL = components.url else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        let data = try await fetchData(from: apiURL)
        return try parseResult(from: data)
    }

    func parseSizes(productIDWithColorCode: String) async throws -> [ParsedProductSize] {
        try await parse(productIDWithColorCode: productIDWithColorCode).sizes
    }

    func parseSizes(from data: Data) throws -> [ParsedProductSize] {
        try parseResult(from: data).sizes
    }

    func parseResult(from data: Data) throws -> UniqloSizeAPIResult {
        let response = try JSONDecoder().decode(UniqloSizeChartResponse.self, from: data)
        let sizes = response.result.flatMap { resultItem in
            (resultItem.sizeChart ?? []).compactMap { sizeChart in
                makeParsedSize(from: sizeChart, productIDWithColorCode: resultItem.productId)
            }
        }
        let imageURLString = response.result
            .compactMap { normalizeImageURL($0.imageUrl) }
            .first

        return UniqloSizeAPIResult(
            sizes: ParsedProductSizeNormalizer.uniqueSizes(sizes),
            imageURLString: imageURLString
        )
    }

    private func fetchData(from apiURL: URL) async throws -> Data {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.uniqlo.com/kr/ko/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        return data
    }

    private func makeParsedSize(
        from size: UniqloSizeChartResponse.SizeChart,
        productIDWithColorCode: String
    ) -> ParsedProductSize? {
        let sizeName = size.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sizeName.isEmpty else {
            return nil
        }

        var valuesByCode: [String: Double] = [:]
        var valuesByName: [String: Double] = [:]
        let methodProfile = uniqloMethodProfile(for: size.sizeParts ?? [])
        var measurementRecords: [ParsedMeasurement] = []

        for part in size.sizeParts ?? [] {
            guard let measurement = part.centimeterMeasurement else {
                continue
            }
            let normalizedCode = part.code.normalizedUniqloMeasurementKey
            let mapping = MeasurementSourceMappingPolicy.uniqlo(rawCode: part.code)
            let normalizedValue = measurement.value * (mapping?.valueMultiplier ?? 1)
            valuesByCode[normalizedCode] = normalizedValue
            valuesByName[part.name.normalizedUniqloMeasurementKey] = normalizedValue
            let displayKind = UniqloMeasurementColumn
                .column(for: normalizedCode, fallbackName: part.name.normalizedUniqloMeasurementKey)?
                .displayKind ?? .unknown
            measurementRecords.append(
                ParsedMeasurement(
                    value: normalizedValue,
                    measurementCode: mapping?.code ?? .unknown,
                    displayKind: displayKind,
                    methodSource: "uniqlo_kr",
                    methodProfile: methodProfile,
                    inputSource: .importedSizeChart,
                    mappingVersion: MeasurementSourceMappingPolicy.uniqloVersion,
                    rawCode: part.code,
                    rawLabel: part.name,
                    rawInfo: part.info,
                    rawValueText: measurement.rawValue,
                    evidenceLevel: mapping?.evidence ?? .unknown,
                    semanticStatus: mapping == nil ? .unknownDefinition : .mapped
                )
            )
        }

        let measurements = GarmentMeasurements(
            shoulder: number(matching: [.shoulder], valuesByCode: valuesByCode, valuesByName: valuesByName) ?? 0,
            chest: number(matching: [.chest], valuesByCode: valuesByCode, valuesByName: valuesByName) ?? 0,
            totalLength: number(matching: [.totalLength, .inseam], valuesByCode: valuesByCode, valuesByName: valuesByName) ?? 0,
            sleeveLength: number(matching: [.sleeveLength], valuesByCode: valuesByCode, valuesByName: valuesByName) ?? 0,
            waist: number(matching: [.waist], valuesByCode: valuesByCode, valuesByName: valuesByName) ?? 0,
            hip: number(matching: [.hip], valuesByCode: valuesByCode, valuesByName: valuesByName) ?? 0,
            thigh: number(matching: [.thigh], valuesByCode: valuesByCode, valuesByName: valuesByName) ?? 0,
            rise: number(matching: [.rise], valuesByCode: valuesByCode, valuesByName: valuesByName) ?? 0,
            hem: number(matching: [.hem], valuesByCode: valuesByCode, valuesByName: valuesByName) ?? 0
        )

        guard !measurementRecords.isEmpty || !measurements.isEmpty else {
            return nil
        }

        return ParsedProductSize(
            id: ParsedProductSize.stableID(for: "\(productIDWithColorCode)|\(sizeName)"),
            name: sizeName,
            measurements: measurements,
            measurementRecords: measurementRecords
        )
    }

    private func uniqloMethodProfile(for parts: [UniqloSizeChartResponse.SizePart]) -> String {
        let codes = Set(parts.map { $0.code.normalizedUniqloMeasurementKey })
        if codes.contains("knitbodylengthfront") { return "uniqlo_top_knit" }
        if codes.contains("bodylengthback") { return "uniqlo_top_back" }
        if codes.contains("bodylength") { return "uniqlo_top_shirt" }
        return "uniqlo_size_chart"
    }

    private func number(
        matching columns: [UniqloMeasurementColumn],
        valuesByCode: [String: Double],
        valuesByName: [String: Double]
    ) -> Double? {
        for column in columns {
            if let match = column.firstValue(in: valuesByCode) { return match }
            if let match = column.firstValue(in: valuesByName) { return match }
        }
        return nil
    }

    private func normalizeImageURL(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            return nil
        }
        if rawValue.hasPrefix("//") { return "https:" + rawValue }
        if rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") { return rawValue }
        if rawValue.hasPrefix("/") { return "https://www.uniqlo.com" + rawValue }
        return rawValue
    }
}

struct UniqloProductMetadata {
    var sourceURL: URL
    var productID: String
    var goodsID: String
    var colorCode: String
    var brandName: String
    var productName: String
    var category: ClothingCategory
    var detailCategory: ClosetDetailCategory
    var imageURLString: String?
    var price: Int?
    var canonicalURLString: String?
    var productMetadata: ProductMetadata = ProductMetadata()

    func parsedProductInfo(sizes: [ParsedProductSize], parserNotice: String? = nil) -> ParsedProductInfo {
        ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: .officialStore,
            sourceName: "유니클로 공식몰",
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
            sourceCategoryPath: productMetadata.sourceCategoryPath,
            sourceCategoryDepth1: productMetadata.sourceCategoryDepth1,
            sourceCategoryDepth2: productMetadata.sourceCategoryDepth2,
            sourceCategoryDepth3: productMetadata.sourceCategoryDepth3,
            sourceCategoryDepth4: productMetadata.sourceCategoryDepth4,
            productTargetGender: UserGender.productTarget(from: productMetadata.genderCodes),
            productMetadata: productMetadata
        )
    }

    func withPreferredImageURL(
        _ preferredImageURLString: String?,
        selectedColorCode: String,
        goodsID: String
    ) -> UniqloProductMetadata {
        guard let preferredImageURLString, !preferredImageURLString.isEmpty else {
            return self
        }

        // The size-chart API can fall back to the generic `000` color. Do not
        // let that response replace the thumbnail selected from the shared URL.
        let expectedToken = "_\(selectedColorCode)_\(goodsID)_"
        let isSelectedColorImage = preferredImageURLString
            .localizedCaseInsensitiveContains(expectedToken)
        let mayUseOfficialDefault = selectedColorCode == "00"
            && UniqloImageURLPolicy.containsGoodsID(
                preferredImageURLString,
                goodsID: goodsID
            )
        guard isSelectedColorImage || mayUseOfficialDefault else {
            return self
        }

        var copy = self
        copy.imageURLString = preferredImageURLString
        var metadata = copy.productMetadata
        metadata.imageURLStrings = [preferredImageURLString]
        copy.productMetadata = metadata
        return copy
    }

    func withInferredSleeveDetail(
        from sizes: [ParsedProductSize]
    ) -> UniqloProductMetadata {
        guard category.serviceGroup == .top,
              detailCategory == .other else {
            return self
        }

        let gender = UserGender.productTarget(from: productMetadata.genderCodes)
        let length = GarmentLengthInferencePolicy.infer(
            category: category,
            gender: gender,
            samples: GarmentLengthInferencePolicy.samples(from: sizes),
            fallbackMeasurements: sizes.map(\.measurements)
        )
        let inferred: ClosetDetailCategory
        switch length {
        case .short: inferred = .shortSleeve
        case .long: inferred = .longSleeve
        default: return self
        }
        var copy = self
        copy.detailCategory = inferred
        return copy
    }
}

struct UniqloProductMetadataParser {
    func parse(resolved: ResolvedUniqloURL) -> UniqloProductMetadata {
        let jsonLDObjects = parseJSONLDObjects(from: resolved.html)
        let productGroupObject = jsonLDObjects.first(where: { isType("ProductGroup", in: $0) })
        let productObject = jsonLDObjects.first(where: { isType("Product", in: $0) })
        let breadcrumbObject = jsonLDObjects.first(where: { isType("BreadcrumbList", in: $0) })
        let hydrationProduct = selectedHydrationProduct(
            from: resolved.html,
            productID: resolved.productID,
            productIDWithColorCode: resolved.productIDWithColorCode
        )

        let rawProductName = stringValue(productGroupObject?["name"])
            ?? stringValue(productObject?["name"])
            ?? stringValue(hydrationProduct?["name"])
            ?? titleFallback(from: resolved.html)
            ?? "유니클로 상품 \(resolved.goodsID)"
        let productName = sanitizedProductName(rawProductName, fallback: "유니클로 상품 \(resolved.goodsID)")
        let brandName = brandName(from: productGroupObject) ?? brandName(from: productObject) ?? "유니클로"
        let structuredImageURL = normalizeImageURL(firstImage(from: productGroupObject) ?? firstImage(from: productObject))
        let expectedImageToken = "_\(resolved.imageColorCode)_\(resolved.goodsID)_"
        let imageURLString = structuredImageURL?.localizedCaseInsensitiveContains(expectedImageToken) == true
            ? structuredImageURL
            : fallbackImageURL(goodsID: resolved.goodsID, colorCode: resolved.imageColorCode)
        let priceInfo = priceInfo(productGroupObject: productGroupObject, productObject: productObject, resolved: resolved)
        let breadcrumb = breadcrumbItems(from: breadcrumbObject, productName: productName)
        let htmlBreadcrumb = htmlBreadcrumbItems(from: resolved.html, productName: productName)
        let embeddedBreadcrumb = embeddedProductBreadcrumb(
            from: resolved.html,
            productID: resolved.productID
        )
        let productTypeKr = embeddedProductTypeKr(
            from: resolved.html,
            productID: resolved.productID,
            productIDWithColorCode: resolved.productIDWithColorCode
        )
        let productStructureFact = embeddedProductStructureFact(
            from: resolved.html,
            productID: resolved.productID,
            productIDWithColorCode: resolved.productIDWithColorCode,
            productName: productName
        )
        let sourcePath = categoryPath(
            productGroupObject: productGroupObject,
            breadcrumb: breadcrumb,
            htmlBreadcrumb: htmlBreadcrumb,
            embeddedBreadcrumb: embeddedBreadcrumb
        )
        let rawSourceCategory = !breadcrumb.isEmpty
            ? breadcrumb.joined(separator: " / ")
            : (!htmlBreadcrumb.isEmpty
                ? htmlBreadcrumb.joined(separator: " / ")
                : (stringValue(productGroupObject?["category"]) ?? "nil"))
        let categoryText = sourcePath.fullPath ?? sourcePath.depths.joined(separator: " ")
        // Official category evidence determines the major category. Product
        // names may refine an ambiguous detail later, but must not silently
        // flip a clear provider major category.
        let mixedKnitCardiganBucket = sourcePath.depths.contains {
            $0.contains("니트") && ($0.contains("가디건") || $0.contains("카디건"))
        }
        let explicitCardiganProduct = productName.contains("가디건")
            || productName.contains("카디건")
            || productName.localizedCaseInsensitiveContains("cardigan")
        let initiallyMappedCategory: ClothingCategory = mixedKnitCardiganBucket
            && explicitCardiganProduct
            ? .outer
            : mapCategory(from: categoryText)
        let initiallyMappedDetail: ClosetDetailCategory = mixedKnitCardiganBucket
            && explicitCardiganProduct
            ? .cardigan
            : mapDetailCategory(from: "\(categoryText) \(productName)")
        let canonical = ParsedClosetClassification.resolve(
            category: initiallyMappedCategory,
            detailCategory: initiallyMappedDetail,
            sourceDepths: [sourcePath.depth1, sourcePath.depth2, sourcePath.depth3, sourcePath.depth4],
            sourcePath: sourcePath.fullPath,
            productName: productName
        )
        let category = canonical?.category ?? initiallyMappedCategory
        let detailCategory = canonical?.detailCategory == .other
            ? initiallyMappedDetail
            : (canonical?.detailCategory ?? initiallyMappedDetail)
        let canonicalURL = canonicalURL(from: resolved.html) ?? resolved.resolvedURL.absoluteString
        let productAudience = productAudience(from: resolved.html)
        let genderCodes = productAudience.codes
            ?? sourcePath.gender.map { [$0] }
            ?? genderCodes(from: breadcrumb + htmlBreadcrumb)

        var structuredFacts = productTypeKr.map { ["product_type_kr": $0] } ?? [:]
        if let productStructureFact {
            structuredFacts.merge(productStructureFact.structuredFacts) { current, _ in current }
        }
        // This marker is retailer-observation provenance, not a path-length
        // guess. It is emitted only when the selected PDP exposes each
        // ordered UNIQLO breadcrumb node with an ID.
        if sourcePath.isCompleteObservedProviderHierarchy {
            structuredFacts["source_category_path_completeness"] = "complete"
            structuredFacts["source_category_path_source"] = "uniqlo_pdp_breadcrumbs"
        }

        let metadata = ProductMetadata(
            brandEnglishName: "UNIQLO",
            sourceCategoryPath: sourcePath.fullPath,
            sourceCategoryDepth1: sourcePath.depth1,
            sourceCategoryDepth2: sourcePath.depth2,
            sourceCategoryDepth3: sourcePath.depth3,
            sourceCategoryDepth4: sourcePath.depth4,
            baseCategoryFullPath: sourcePath.fullPath,
            categoryDepth1Code: sourcePath.code1,
            categoryDepth1Name: sourcePath.depth1,
            categoryDepth2Code: sourcePath.code2,
            categoryDepth2Name: sourcePath.depth2,
            categoryDepth3Code: sourcePath.code3,
            categoryDepth3Name: sourcePath.depth3,
            categoryDepth4Code: sourcePath.code4,
            categoryDepth4Name: sourcePath.depth4,
            structuredFacts: structuredFacts,
            genderCodes: genderCodes,
            imageURLStrings: [imageURLString].compactMap { $0 },
            normalPrice: priceInfo.normalPrice,
            salePrice: priceInfo.salePrice,
            finalPrice: priceInfo.finalPrice,
            currencyCode: (priceInfo.finalPrice ?? priceInfo.salePrice ?? priceInfo.normalPrice) == nil ? nil : "KRW",
            isSale: priceInfo.normalPrice.map { normal in
                guard let current = priceInfo.finalPrice ?? priceInfo.salePrice else { return false }
                return normal > current
            } ?? false,
            isOutOfStock: priceInfo.stockStatus == .outOfStock,
            stockStatusRawValue: priceInfo.stockStatus.rawValue,
            checkedColorName: resolved.imageColorCode,
            checkedSizeName: queryValue("sizeDisplayCode", in: resolved.originalURL) ?? queryValue("sizeDisplayCode", in: resolved.resolvedURL)
        )

        logSourceCategory(
            rawSourceCategory: rawSourceCategory,
            gender: UserGender.productTarget(from: metadata.genderCodes),
            sourcePath: sourcePath,
            audienceEvidence: productAudience.evidence,
            prefix: "[UniqloProductMetadataParser]"
        )

        return UniqloProductMetadata(
            sourceURL: resolved.resolvedURL,
            productID: resolved.productID,
            goodsID: resolved.goodsID,
            colorCode: resolved.imageColorCode,
            brandName: brandName,
            productName: productName,
            category: category,
            detailCategory: detailCategory,
            imageURLString: imageURLString,
            price: priceInfo.finalPrice ?? priceInfo.salePrice ?? priceInfo.normalPrice,
            canonicalURLString: canonicalURL,
            productMetadata: metadata
        )
    }

    func parseJSONLDObjects(from html: String) -> [[String: Any]] {
        let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
        return matches.flatMap { match -> [[String: Any]] in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else {
                return []
            }

            let jsonString = String(html[range]).htmlDecoded
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                return []
            }

            if let object = json as? [String: Any] {
                return flattenJSONLD(object)
            }
            if let array = json as? [Any] {
                return array.flatMap { element -> [[String: Any]] in
                    guard let object = element as? [String: Any] else { return [] }
                    return flattenJSONLD(object)
                }
            }
            return []
        }
    }

    private func flattenJSONLD(_ object: [String: Any]) -> [[String: Any]] {
        var objects = [object]
        if let graph = object["@graph"] as? [[String: Any]] {
            objects.append(contentsOf: graph)
        }
        return objects
    }

    private func isType(_ expectedType: String, in object: [String: Any]) -> Bool {
        if let type = object["@type"] as? String {
            return type.caseInsensitiveCompare(expectedType) == .orderedSame
        }
        if let types = object["@type"] as? [String] {
            return types.contains { $0.caseInsensitiveCompare(expectedType) == .orderedSame }
        }
        return false
    }

    private func brandName(from productObject: [String: Any]?) -> String? {
        if let brand = productObject?["brand"] as? [String: Any] {
            return stringValue(brand["name"])
        }
        return stringValue(productObject?["brand"])
    }

    private func firstImage(from productObject: [String: Any]?) -> String? {
        if let image = stringValue(productObject?["image"]) {
            return image
        }
        if let images = productObject?["image"] as? [Any] {
            return images.compactMap(stringValue).first
        }
        return nil
    }

    private func priceInfo(
        productGroupObject: [String: Any]?,
        productObject: [String: Any]?,
        resolved: ResolvedUniqloURL
    ) -> UniqloPriceInfo {
        let variants = variantObjects(from: productGroupObject?["hasVariant"])
        let selectedSizeCode = queryValue("sizeDisplayCode", in: resolved.originalURL) ?? queryValue("sizeDisplayCode", in: resolved.resolvedURL)
        let selectedColorCode = queryValue("colorDisplayCode", in: resolved.originalURL)
            ?? queryValue("colorDisplayCode", in: resolved.resolvedURL)
            ?? resolved.imageColorCode

        let selectedVariant = variants.first {
            variant($0, matchesColorCode: selectedColorCode, sizeCode: selectedSizeCode)
        } ?? variants.first {
            variant($0, matchesColorCode: selectedColorCode, sizeCode: nil)
        } ?? variants.first

        if let selectedVariant, let info = priceInfo(from: selectedVariant["offers"]) {
            return info
        }
        if let info = priceInfo(from: productGroupObject?["offers"]) {
            return info
        }
        if let info = priceInfo(from: productObject?["offers"]) {
            return info
        }
        return UniqloPriceInfo(normalPrice: nil, salePrice: nil, finalPrice: nil, stockStatus: .unknown)
    }

    private func variantObjects(from value: Any?) -> [[String: Any]] {
        if let object = value as? [String: Any] { return [object] }
        if let array = value as? [[String: Any]] { return array }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private func variant(_ object: [String: Any], matchesColorCode colorCode: String?, sizeCode: String?) -> Bool {
        let haystack = object.map { "\($0.key)=\($0.value)" }.joined(separator: " ").lowercased()
        let colorMatches = colorCode.map { haystack.contains($0.lowercased()) } ?? true
        let sizeMatches = sizeCode.map { haystack.contains($0.lowercased()) } ?? true
        return colorMatches && sizeMatches
    }

    private func priceInfo(from offers: Any?) -> UniqloPriceInfo? {
        let offerObjects: [[String: Any]]
        if let object = offers as? [String: Any] {
            offerObjects = [object]
        } else if let array = offers as? [[String: Any]] {
            offerObjects = array
        } else if let array = offers as? [Any] {
            offerObjects = array.compactMap { $0 as? [String: Any] }
        } else {
            return nil
        }

        guard let offer = offerObjects.first else { return nil }
        let finalPrice = intValue(offer["price"] ?? offer["lowPrice"])
        let salePrice = intValue(offer["salePrice"] ?? offer["priceSpecification"])
        let normalPrice = intValue(offer["normalPrice"] ?? offer["listPrice"] ?? offer["highPrice"])
        let availability = stringValue(offer["availability"]) ?? stringValue(offer["itemAvailability"])

        return UniqloPriceInfo(
            normalPrice: normalPrice,
            salePrice: salePrice,
            finalPrice: finalPrice ?? salePrice ?? normalPrice,
            stockStatus: stockStatus(from: availability)
        )
    }

    private func breadcrumbItems(from breadcrumbObject: [String: Any]?, productName: String) -> [String] {
        guard let elements = breadcrumbObject?["itemListElement"] as? [[String: Any]] else {
            return []
        }

        let names = elements.compactMap { element -> String? in
            if let name = stringValue(element["name"]) {
                return name
            }
            if let item = element["item"] as? [String: Any] {
                return stringValue(item["name"])
            }
            return nil
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        return cleanedCategoryParts(names, productName: productName)
    }

    private func categoryPath(
        productGroupObject: [String: Any]?,
        breadcrumb: [String],
        htmlBreadcrumb: [String],
        embeddedBreadcrumb: SourceCategoryPath?
    ) -> SourceCategoryPath {
        let productGroupCategory = stringValue(productGroupObject?["category"])
        let productGroupPath = sourceCategoryPath(from: splitCategoryPath(productGroupCategory))
        let candidates = [
            embeddedBreadcrumb,
            sourceCategoryPath(from: breadcrumb),
            sourceCategoryPath(from: htmlBreadcrumb),
            productGroupPath
        ].compactMap { $0 }.filter { !$0.depths.isEmpty }

        // UNIQLO's visible/JSON-LD breadcrumb can stop at a collaboration page,
        // while __PRELOADED_STATE__ still contains the official leaf and IDs.
        // Keep source order for ties, but never discard the deeper evidence.
        return candidates.max { lhs, rhs in
            lhs.depths.count < rhs.depths.count
        } ?? sourceCategoryPath(from: [])
    }

    private func embeddedProductBreadcrumb(
        from html: String,
        productID: String
    ) -> SourceCategoryPath? {
        guard let json = firstMatch(
            in: html,
            pattern: #"window\.__PRELOADED_STATE__\s*=\s*(\{.*?\})\s*;?\s*</script>"#
        ),
        let data = json.data(using: .utf8),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let entity = root["entity"] as? [String: Any],
        let pdpEntity = entity["pdpEntity"] as? [String: Any] else {
            return nil
        }

        let normalizedProductID = productID.uppercased()
        guard let entry = pdpEntity.first(where: { key, _ in
            key.uppercased().hasPrefix(normalizedProductID + "-")
        })?.value as? [String: Any],
        let product = entry["product"] as? [String: Any],
        let breadcrumbs = product["breadcrumbs"] as? [String: Any] else {
            return nil
        }

        let orderedKeys = ["gender", "class", "category", "subcategory"]
        let nodes: [(name: String, code: String?)] = orderedKeys.compactMap { key in
            guard let node = breadcrumbs[key] as? [String: Any],
                  let name = stringValue(node["locale"] ?? node["name"])?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ),
                  !name.isEmpty else {
                return nil
            }
            return (name, stringValue(node["id"]))
        }
        guard !nodes.isEmpty else { return nil }

        let gender = audienceCode(from: nodes[0].name)
        let categoryNodes = gender == nil ? nodes : Array(nodes.dropFirst())
        let isCompleteObservedProviderHierarchy = nodes.count == orderedKeys.count
            && gender != nil
            && nodes.allSatisfy { node in
                guard let code = node.code?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return false
                }
                return !code.isEmpty
            }
        return SourceCategoryPath(
            gender: gender,
            depths: categoryNodes.map(\.name),
            codes: categoryNodes.map(\.code),
            isCompleteObservedProviderHierarchy: isCompleteObservedProviderHierarchy
        )
    }

    /// Returns UNIQLO's retailer-owned Korean product type verbatim from the
    /// selected hydration product. A unique exact variant match wins; when no
    /// exact variant is present, there must be exactly one matching core
    /// product. Ambiguous or missing evidence is deliberately omitted.
    private func embeddedProductTypeKr(
        from html: String,
        productID: String,
        productIDWithColorCode: String
    ) -> String? {
        guard let selectedProduct = selectedHydrationProduct(
            from: html,
            productID: productID,
            productIDWithColorCode: productIDWithColorCode
        ), let rawValue = selectedProduct["productTypeKr"] as? String,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return rawValue
    }

    /// Captures only a provider-declared structure or explicit composite text
    /// in the selected retailer PDP. PDP identity selects the record, but it
    /// is not cardinality evidence.
    private func embeddedProductStructureFact(
        from html: String,
        productID: String,
        productIDWithColorCode: String,
        productName: String
    ) -> RetailerProductStructureFact? {
        let product = selectedHydrationProduct(
            from: html,
            productID: productID,
            productIDWithColorCode: productIDWithColorCode
        )

        if let product,
           let declared = declaredProductStructure(from: product) {
            return declared
        }

        let textFields: [(String, String?)] = [
            ("pdp_entity_name", product.flatMap { stringValue($0["name"]) }),
            ("pdp_composition", product.flatMap { stringValue($0["composition"]) }),
            ("pdp_product_composition", product.flatMap { stringValue($0["productComposition"]) }),
            ("pdp_component_description", product.flatMap { stringValue($0["componentDescription"]) }),
            ("pdp_long_description", product.flatMap { stringValue($0["longDescription"]) }),
            ("pdp_description", product.flatMap { stringValue($0["description"]) }),
            ("pdp_short_description", product.flatMap { stringValue($0["shortDescription"]) }),
            ("pdp_product_name", productName)
        ]
        for (field, value) in textFields {
            guard let value,
                  let fact = RetailerProductStructureFact.explicitCompositeRetailerText(
                    value,
                    source: "uniqlo_pdp_entity",
                    evidenceField: field
                  ) else {
                continue
            }
            return fact
        }
        return nil
    }

    private func declaredProductStructure(
        from product: [String: Any]
    ) -> RetailerProductStructureFact? {
        let textFields = [
            "productStructure", "product_structure", "bundleType", "bundle_type"
        ]
        for field in textFields {
            guard let raw = stringValue(product[field])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(), !raw.isEmpty else {
                continue
            }
            let structure: RetailerProductStructure?
            switch raw {
            case "single", "single_item", "single-item", "one":
                structure = .single
            case "set", "bundle", "kit":
                structure = .set
            case "multipack", "multi_pack", "multi-pack", "pack":
                structure = .multipack
            case "unknown":
                structure = .unknown
            default:
                structure = nil
            }
            if let structure {
                return RetailerProductStructureFact(
                    structure: structure,
                    source: "uniqlo_pdp_entity",
                    evidence: "\(field):provider_declared"
                )
            }
        }

        if let isSet = product["isSet"] as? Bool, isSet {
            return RetailerProductStructureFact(
                structure: .set,
                source: "uniqlo_pdp_entity",
                evidence: "isSet:true"
            )
        }
        if let packCount = intValue(product["packCount"]), packCount > 1 {
            return RetailerProductStructureFact(
                structure: .multipack,
                source: "uniqlo_pdp_entity",
                evidence: "packCount:provider_gt_1"
            )
        }
        return nil
    }

    private func selectedHydrationProduct(
        from html: String,
        productID: String,
        productIDWithColorCode: String
    ) -> [String: Any]? {
        guard let json = firstMatch(
            in: html,
            pattern: #"window\.__PRELOADED_STATE__\s*=\s*(\{.*?\})\s*;?\s*</script>"#
        ),
        let data = json.data(using: .utf8),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let entity = root["entity"] as? [String: Any],
        let pdpEntity = entity["pdpEntity"] as? [String: Any] else {
            return nil
        }

        let normalizedProductID = productID.uppercased()
        let normalizedVariantID = productIDWithColorCode.uppercased()
        let candidates: [(key: String, productID: String?, product: [String: Any])] =
            pdpEntity.compactMap { key, rawEntry in
                guard let entry = rawEntry as? [String: Any],
                      let product = entry["product"] as? [String: Any] else {
                    return nil
                }
                let normalizedKey = key.uppercased()
                let embeddedProductID = stringValue(product["productId"])?.uppercased()
                let matchesCore = normalizedKey == normalizedProductID
                    || normalizedKey.hasPrefix(normalizedProductID + "-")
                    || embeddedProductID == normalizedProductID
                    || embeddedProductID?.hasPrefix(normalizedProductID + "-") == true
                guard matchesCore else { return nil }
                return (normalizedKey, embeddedProductID, product)
            }

        let exactMatches = candidates.filter { candidate in
            candidate.key == normalizedVariantID
                || candidate.key.hasPrefix(normalizedVariantID + "-")
                || candidate.productID == normalizedVariantID
        }
        if exactMatches.count == 1 {
            return exactMatches[0].product
        } else if exactMatches.isEmpty, candidates.count == 1 {
            return candidates[0].product
        } else {
            return nil
        }
    }

    private func htmlBreadcrumbItems(from html: String, productName: String) -> [String] {
        let patterns = [
            #"<nav[^>]*(?:breadcrumb|Breadcrumb)[^>]*>(.*?)</nav>"#,
            #"<ol[^>]*(?:breadcrumb|Breadcrumb)[^>]*>(.*?)</ol>"#,
            #"<ul[^>]*(?:breadcrumb|Breadcrumb)[^>]*>(.*?)</ul>"#,
            #"<[^>]*(?:class|data-testid)=["'][^"']*(?:breadcrumb|Breadcrumb)[^"']*["'][^>]*>(.*?)</[^>]+>"#
        ]

        for pattern in patterns {
            guard let htmlChunk = firstMatch(in: html, pattern: pattern) else {
                continue
            }

            let linkedTexts = allMatches(in: htmlChunk, pattern: #"<a[^>]*>(.*?)</a>"#)
            let itemTexts = linkedTexts.isEmpty
                ? allMatches(in: htmlChunk, pattern: #"<li[^>]*>(.*?)</li>"#)
                : linkedTexts
            let parts = itemTexts
                .map { $0.strippingHTMLTags.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let cleaned = cleanedCategoryParts(parts, productName: productName)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return []
    }

    private func cleanedCategoryParts(_ parts: [String], productName: String) -> [String] {
        var seen = Set<String>()
        return parts.compactMap { rawPart in
            let part = rawPart
                .htmlDecoded
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            guard !part.isEmpty,
                  !isBreadcrumbRoot(part),
                  !part.caseInsensitiveEquals(productName) else {
                return nil
            }
            let key = part.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return part
        }
    }

    private func isBreadcrumbRoot(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["홈", "home", "유니클로", "uniqlo"].contains(normalized)
    }

    private func logSourceCategory(rawSourceCategory: String, gender: UserGender, sourcePath: SourceCategoryPath, audienceEvidence: String?, prefix: String) {
        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "유니클로 원본 분류 해석",
            details: "파서=\(prefix), 원본=\(rawSourceCategory), 카테고리대상=\(sourcePath.gender ?? "없음"), 상품성별=\(gender.rawValue), 성별근거=\(audienceEvidence ?? "카테고리 경로"), depth1=\(sourcePath.depth1 ?? "없음"), depth2=\(sourcePath.depth2 ?? "없음"), depth3=\(sourcePath.depth3 ?? "없음"), depth4=\(sourcePath.depth4 ?? "없음"), 경로=\(sourcePath.fullPath ?? "없음")"
        )
        #endif
    }

    private func productAudience(from html: String) -> (codes: [String]?, evidence: String?) {
        for field in ["genderCategory", "genderName"] {
            let pattern = #"\""# + field + #"\"\s*:\s*\"([^\"]+)\""#
            if let value = firstMatch(in: html, pattern: pattern),
               let codes = normalizedAudienceCodes(from: value) {
                return (codes, "\(field):\(value)")
            }
        }

        if firstMatch(in: html, pattern: #"\"code\"\s*:\s*\"(unisex)\""#) != nil {
            return (["UNISEX"], "productFlag:unisex")
        }

        if let contents = firstMatch(in: html, pattern: #"\"topCategories\"\s*:\s*\[([^\]]*)\]"#) {
            let values = allMatches(in: contents, pattern: #"\"([^\"]+)\""#).map { $0.uppercased() }
            if values.contains("MEN"), values.contains("WOMEN") {
                return (["UNISEX"], "topCategories:MEN+WOMEN")
            }
        }
        return (nil, nil)
    }

    private func normalizedAudienceCodes(from value: String) -> [String]? {
        let canonical = FitMatchCanonicalAudience.code(from: value)
        return canonical == FitMatchCanonicalAudience.unknown.rawValue
            ? nil
            : [canonical]
    }

    private func splitCategoryPath(_ path: String?) -> [String] {
        guard let path else { return [] }
        return path
            .components(separatedBy: CharacterSet(charactersIn: "/>"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func sourceCategoryPath(from rawParts: [String]) -> SourceCategoryPath {
        var parts = rawParts
        let gender = parts.first.flatMap { audienceCode(from: $0) }
        if gender != nil {
            parts.removeFirst()
        }
        return SourceCategoryPath(gender: gender, depths: parts, codes: [])
    }

    private func audienceCode(from value: String) -> String? {
        let canonical = FitMatchCanonicalAudience.code(from: value)
        return canonical == FitMatchCanonicalAudience.unknown.rawValue
            ? nil
            : canonical
    }

    private func titleFallback(from html: String) -> String? {
        firstMatch(in: html, pattern: #"<title[^>]*>(.*?)</title>"#)?
            .htmlDecoded
            .components(separatedBy: "|")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizedProductName(_ rawName: String, fallback: String) -> String {
        let decodedName = rawName
            .htmlDecoded
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let removableAudienceTokens = [
            "젠더리스",
            "MEN",
            "WOMEN",
            "UNISEX",
            "KIDS",
            "BABY",
            "남성",
            "여성",
            "공용",
            "키즈",
            "베이비"
        ]

        var sanitized = decodedName
        for token in removableAudienceTokens {
            let escapedToken = NSRegularExpression.escapedPattern(for: token)
            let patterns = [
                #"(?i)^\s*\#(escapedToken)\s*[-_/|:·ㆍ]?\s*"#,
                #"(?i)\s+\#(escapedToken)\s*$"#,
                #"(?i)\s*[-_/|:·ㆍ]\s*\#(escapedToken)\s*$"#,
                #"(?i)^\s*\[\#(escapedToken)\]\s*"#,
                #"(?i)\s*\[\#(escapedToken)\]\s*$"#,
                #"(?i)^\s*\(\#(escapedToken)\)\s*"#,
                #"(?i)\s*\(\#(escapedToken)\)\s*$"#
            ]

            for pattern in patterns {
                sanitized = sanitized.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: .regularExpression
                )
            }
        }

        sanitized = sanitized
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_/|:·ㆍ")))

        return sanitized.isEmpty ? fallback : sanitized
    }

    private func canonicalURL(from html: String) -> String? {
        firstMatch(in: html, pattern: #"<link[^>]*rel=["']canonical["'][^>]*href=["']([^"']*)["'][^>]*>"#)
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func mapCategory(from text: String) -> ClothingCategory {
        let value = text.lowercased()
        let pathSegments = text.components(separatedBy: ">").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        // 상위 경로에 "티셔츠"가 포함되어도 최하위 공식 카테고리와
        // 상품명이 스웨트팬츠처럼 더 구체적이면 그 대분류를 우선한다.
        let terminal = text.components(separatedBy: ">").last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
        let terminalValue = terminal.lowercased()
        if terminal.contains("스커트") || terminalValue.contains("skirt") { return .bottom }
        if terminalValue.contains("women") && terminalValue.contains("dress")
            || terminal.contains("원피스") { return .dress }
        if terminalValue.contains("bottoms") || terminal.contains("팬츠")
            || terminal.contains("바지") || terminal.contains("쇼츠")
            || terminalValue.contains("pants") || terminalValue.contains("jeans")
            || terminalValue.contains("shorts") { return .bottom }
        if terminal.contains("아우터") || terminal.contains("재킷")
            || terminal.contains("자켓") || terminal.contains("코트")
            || terminal.contains("파카") || terminal.contains("점퍼")
            || terminalValue.contains("outer") || terminalValue.contains("jacket")
            || terminalValue.contains("coat") { return .outer }
        if terminal.contains("가디건") || terminal.contains("카디건")
            || terminalValue.contains("cardigan") { return .outer }
        if terminal.contains("니트") || terminal.contains("스웨터")
            || terminalValue.contains("knit") || terminalValue.contains("sweater") {
            return .knit
        }
        // V넥·터틀넥·램스울·GU처럼 말단이 소재/넥/기획명인 경우에도
        // 바로 위 공식 구조가 "니트"이면 니트 상의로 확정할 수 있다.
        // "니트 & 가디건" 혼합 상위 버킷만으로는 추정하지 않는다.
        let structuralSegments = pathSegments.dropFirst().map { $0.lowercased() }
        if structuralSegments.contains(where: { segment in
            (segment.contains("니트") || segment.contains("스웨터")
                || segment.contains("knit") || segment.contains("sweater"))
                && !segment.contains("가디건")
                && !segment.contains("cardigan")
        }) {
            return .knit
        }
        if terminalValue.contains("cut & sewn") || terminalValue.contains("cut and sewn") {
            return .top
        }
        if text.contains("홈웨어") || text.contains("라운지") || text.contains("파자마")
            || value.contains("homewear") || value.contains("loungewear") { return .other }
        // Reversible previous order treated any denim token as bottoms, including denim overshirts.
        if value.contains("overshirt") || text.contains("오버셔츠") || value.contains("shirt") || text.contains("셔츠") {
            return .top
        }
        if text.contains("스커트") || value.contains("skirt") { return .bottom }
        if value.contains("women") && value.contains("dress") || text.contains("원피스") {
            return .dress
        }
        if value.contains("bottoms") || text.contains("팬츠") || text.contains("바지") || text.contains("데님") || text.contains("쇼츠") || value.contains("pants") || value.contains("jeans") || value.contains("shorts") {
            return .bottom
        }
        if text.contains("아우터") || text.contains("재킷") || text.contains("자켓") || text.contains("코트") || text.contains("파카") || text.contains("점퍼") || value.contains("outer") || value.contains("jacket") || value.contains("coat") {
            return .outer
        }
        // Official Tops paths take precedence over AIRism/inner wording in a product name.
        if value.contains("tops") || text.contains("상의") { return .top }
        if text.contains("속옷") || text.contains("이너") || value.contains("inner") || value.contains("underwear") {
            return .underwear
        }
        if text.contains("신발") || text.contains("슈즈") || value.contains("shoes") {
            return .shoes
        }
        if text.contains("가방") || text.contains("모자") || text.contains("벨트") || text.contains("액세서리") || value.contains("accessories") {
            return .accessory
        }
        // 공식 분류 근거가 없으면 상의로 추정하지 않는다. 호출부가 제한된
        // 상품명 보완을 시도한 뒤에도 모호하면 사용자 선택으로 넘긴다.
        return .other
    }

    func mapDetailCategory(from text: String) -> ClosetDetailCategory {
        let value = text.lowercased()
        let terminal = text.components(separatedBy: ">").last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
        let terminalValue = terminal.lowercased()
        if terminal.contains("가디건") || terminal.contains("카디건")
            || terminalValue.contains("cardigan") { return .cardigan }
        if terminal.contains("니트") || terminal.contains("스웨터")
            || terminalValue.contains("knit") || terminalValue.contains("sweater") {
            return .knitTop
        }
        if text.contains("캐미솔") || value.contains("camisole") { return .womenCamisole }
        if text.contains("슬립") || value.contains("slip") { return .womenSlip }
        if text.contains("브라") || value.contains("bra") { return .womenBra }
        if text.contains("팬티") || value.contains("panty") { return .womenPanty }
        if text.contains("트렁크") || value.contains("trunks") || value.contains("boxer") { return .menTrunks }
        if text.contains("브리프") || value.contains("brief") { return .menBriefs }
        if text.contains("런닝") || value.contains("undershirt") { return .menUndershirt }
        if text.contains("스커트") || value.contains("skirt") { return .skirt }
        if text.contains("슬리브리스") || value.contains("sleeveless") { return .sleeveless }
        if text.contains("쇼트 팬츠") || text.contains("쇼트팬츠") || value.contains("short pants") { return .shorts }
        if value.contains("overshirt") || text.contains("오버셔츠") { return .shirt }
        if text.contains("가디건") || value.contains("cardigan") { return .cardigan }
        if text.contains("민소매") || text.contains("나시") || value.contains("sleeveless") || value.contains("tank") { return .sleeveless }
        if text.contains("반팔") || text.contains("반소매") || value.contains("short sleeve") { return .shortSleeve }
        if text.contains("긴팔") || text.contains("긴소매") || value.contains("long sleeve") { return .longSleeve }
        if value.contains("cut & sewn") || value.contains("cut and sewn") { return .shortSleeve }
        // 티셔츠는 "셔츠"를 문자열로 포함하지만 서로 다른 의류 계열이다.
        // 소매 길이는 이 단계에서 추정하지 않고, 공식 실측 사이즈표를 받은 후
        // withInferredSleeveDetail/normalizedSizes에서 반팔·긴팔로 확정한다.
        if text.contains("티셔츠")
            || text.contains("그래픽T")
            || text.contains("그래픽t")
            || value.contains("t-shirt")
            || value.contains("tshirt") {
            return .other
        }
        if text.contains("후드") || value.contains("hoodie") { return .hoodie }
        if text.contains("스웨트") || text.contains("맨투맨") || value.contains("sweat") { return .sweatshirt }
        if text.contains("셔츠") || value.contains("shirt") { return .shirt }
        if text.contains("니트") || value.contains("knit") || value.contains("sweater") { return .knitTop }
        if text.contains("슬랙스") || value.contains("slacks") { return .slacks }
        if text.contains("반바지") || text.contains("쇼츠") || value.contains("shorts") { return .shorts }
        if text.contains("데님") || text.contains("진") || value.contains("jeans") || value.contains("denim") { return .denim }
        if text.contains("스커트") || value.contains("skirt") { return .skirt }
        if text.contains("레깅스") || value.contains("leggings") { return .leggings }
        if text.contains("재킷") || text.contains("자켓") || value.contains("jacket") { return .jacket }
        if text.contains("코트") || value.contains("coat") { return .coat }
        if text.contains("패딩") || text.contains("파카") || value.contains("parka") { return .padding }
        if text.contains("원피스") || value.contains("dress") { return .onePiece }
        return .other
    }

    private func genderCodes(from breadcrumb: [String]) -> [String] {
        let text = breadcrumb.joined(separator: " ").lowercased()
        if text.contains("women") || text.contains("여성") { return ["WOMEN"] }
        if text.contains("men") || text.contains("남성") { return ["MEN"] }
        if text.contains("kids") || text.contains("키즈") { return ["KIDS"] }
        return []
    }

    private func fallbackImageURL(goodsID: String, colorCode: String) -> String {
        "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/\(goodsID)/item/krgoods_\(colorCode)_\(goodsID)_3x4.jpg?width=400"
    }

    private func normalizeImageURL(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            return nil
        }
        if rawValue.hasPrefix("//") { return "https:" + rawValue }
        if rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") { return rawValue }
        return rawValue
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String {
            return Int(Double(value) ?? 0)
        }
        return nil
    }

    private func stockStatus(from availability: String?) -> ProductStockStatus {
        guard let availability = availability?.lowercased() else {
            return .unknown
        }
        if availability.contains("instock") {
            return .inStock
        }
        if availability.contains("outofstock") || availability.contains("soldout") {
            return .outOfStock
        }
        return .unknown
    }
}

private struct SourceCategoryPath {
    let gender: String?
    let depths: [String]
    let codes: [String?]
    let isCompleteObservedProviderHierarchy: Bool

    init(
        gender: String?,
        depths: [String],
        codes: [String?],
        isCompleteObservedProviderHierarchy: Bool = false
    ) {
        self.gender = gender
        self.depths = depths
        self.codes = codes
        self.isCompleteObservedProviderHierarchy = isCompleteObservedProviderHierarchy
    }

    var fullPath: String? {
        depths.isEmpty ? nil : depths.joined(separator: " > ")
    }

    var depth1: String? { depth(at: 0) }
    var depth2: String? { depth(at: 1) }
    var depth3: String? { depth(at: 2) }
    var depth4: String? { depth(at: 3) }
    var code1: String? { code(at: 0) }
    var code2: String? { code(at: 1) }
    var code3: String? { code(at: 2) }
    var code4: String? { code(at: 3) }

    private func depth(at index: Int) -> String? {
        guard depths.indices.contains(index) else { return nil }
        return depths[index]
    }

    private func code(at index: Int) -> String? {
        guard codes.indices.contains(index) else { return nil }
        return codes[index]
    }
}

private struct UniqloPriceInfo {
    let normalPrice: Int?
    let salePrice: Int?
    let finalPrice: Int?
    let stockStatus: ProductStockStatus
}

private struct UniqloProductAvailabilityResponse: Decodable {
    let status: String?
    let result: Result

    struct Result: Decodable {
        let l2s: [L2]
    }

    struct L2: Decodable {
        let l2Id: String
        let color: DisplayValue
        let size: DisplayValue
        let pld: DisplayValue
        let sales: Bool
    }

    struct DisplayValue: Decodable {
        let displayCode: String
        let name: String?
    }
}

private struct UniqloProductStockResponse: Decodable {
    let status: String?
    let result: [String: Stock]

    struct Stock: Decodable {
        let statusCode: String
        let quantity: Int?
    }
}

private struct UniqloSizeChartResponse: Decodable {
    let status: String?
    let result: [ResultItem]

    private enum CodingKeys: String, CodingKey {
        case status
        case result
    }

    private struct ResultContainer: Decodable {
        let items: [ResultItem]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        if let items = try? container.decode([ResultItem].self, forKey: .result) {
            result = items
        } else {
            result = try container.decode(ResultContainer.self, forKey: .result).items
        }
    }

    struct ResultItem: Decodable {
        let productId: String
        let sizeChart: [SizeChart]?
        let bodyMeasurements: [SizeChart]?
        let imageUrl: String?
        let colorCode: String?
    }

    struct SizeChart: Decodable {
        let sizeCode: String?
        let displayCode: String?
        let name: String
        let sizeParts: [SizePart]?
    }

    struct SizePart: Decodable {
        let code: String
        let name: String
        let info: String?
        let measurements: [Measurement]?

        var centimeterValue: Double? {
            centimeterMeasurement?.value
        }

        var centimeterMeasurement: (value: Double, rawValue: String)? {
            guard let measurement = measurements?.first(where: { $0.unit.lowercased() == "cm" }),
                  let value = Self.firstNumber(in: measurement.value),
                  value.isFinite,
                  value > 0 else { return nil }
            return (value, measurement.value)
        }

        private static func firstNumber(in text: String) -> Double? {
            let pattern = #"(\d+(?:\.\d+)?)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return Double(text[range])
        }
    }

    struct Measurement: Decodable {
        let value: String
        let unit: String
    }
}

private enum UniqloMeasurementColumn {
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

    static func column(for code: String, fallbackName: String) -> UniqloMeasurementColumn? {
        let searchOrder: [UniqloMeasurementColumn] = [
            .shoulder, .chest, .sleeveLength, .waist, .hip, .thigh, .rise, .inseam, .hem, .totalLength
        ]
        return searchOrder.first { $0.matches(code) }
            ?? searchOrder.first { $0.matches(fallbackName) }
    }

    var displayKind: MeasurementDisplayKind {
        switch self {
        case .shoulder: return .shoulder
        case .chest: return .chest
        case .totalLength, .inseam: return .totalLength
        case .sleeveLength: return .sleeveLength
        case .waist: return .waist
        case .hip: return .hip
        case .thigh: return .thigh
        case .rise: return .rise
        case .hem: return .hem
        }
    }

    func matches(_ name: String) -> Bool {
        aliases.contains { name.contains($0) }
    }

    func firstValue(in values: [String: Double]) -> Double? {
        for alias in aliases {
            if let exact = values[alias] { return exact }
        }
        for alias in aliases where alias != "length" {
            if let key = values.keys.sorted().first(where: { $0.contains(alias) }) {
                return values[key]
            }
        }
        return nil
    }

    private var aliases: [String] {
        switch self {
        case .shoulder:
            return ["shoulder", "shoulderwidth", "어깨", "어깨너비"]
        case .chest:
            return ["bodywidth", "chest", "bust", "가슴", "가슴너비", "가슴단면"]
        case .totalLength:
            return ["bodylength", "bodylengthback", "length", "총장", "전체길이", "기장"]
        case .sleeveLength:
            return ["sleeve", "sleevelength", "sleevelengthcb", "소매", "소매길이"]
        case .waist:
            return ["waist", "허리"]
        case .hip:
            return ["hip", "엉덩이", "힙"]
        case .thigh:
            return ["thigh", "허벅지"]
        case .rise:
            return ["risinglength", "rise", "front-rise", "밑위"]
        case .inseam:
            return ["inseam", "인심"]
        case .hem:
            return ["hem", "bottomwidth", "bottomopening", "legopening", "밑단"]
        }
    }
}

private extension String {
    var dropFirstE: String {
        hasPrefix("E") ? String(dropFirst()) : self
    }

    var normalizedUniqloMeasurementKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    func leftPadded(toLength length: Int, with pad: Character) -> String {
        guard count < length else { return self }
        return String(repeating: String(pad), count: length - count) + self
    }

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

    var strippingHTMLTags: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func caseInsensitiveEquals(_ other: String) -> Bool {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(other.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}
