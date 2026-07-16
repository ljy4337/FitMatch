import Foundation

struct UniqloParser: ProductURLParsing {
    private let urlResolver = UniqloURLResolver()
    private let metadataParser = UniqloProductMetadataParser()
    private let sizeParser = UniqloSizeAPIParser()

    func canParse(_ url: URL) -> Bool {
        url.host?.lowercased().contains("uniqlo.com") == true
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        let resolved = try await urlResolver.resolve(url)
        let metadata = metadataParser.parse(resolved: resolved)

        let sizeAPIResult: UniqloSizeAPIResult
        do {
            sizeAPIResult = try await sizeParser.parse(productIDWithColorCode: resolved.productIDWithColorCode)
        } catch {
            print("[UniqloParser] size API failed: \(error.localizedDescription)")
            throw ProductURLParserPartialError(
                productInfo: metadata.parsedProductInfo(
                    sizes: [],
                    parserNotice: "상품 정보는 불러왔지만 유니클로 사이즈표를 찾지 못했습니다. 상품 URL을 다시 확인해 주세요."
                )
            )
        }
        let sizes = sizeAPIResult.sizes
        let resolvedMetadata = metadata.withPreferredImageURL(sizeAPIResult.imageURLString)

        print("[UniqloParser] detectedProvider: uniqlo")
        print("[UniqloParser] originalURL: \(resolved.originalURL.absoluteString)")
        print("[UniqloParser] resolvedURL: \(resolved.resolvedURL.absoluteString)")
        print("[UniqloParser] productID: \(resolved.productID)")
        print("[UniqloParser] colorCode: \(resolved.imageColorCode)")
        print("[UniqloParser] apiProductIDWithColorCode: \(resolved.productIDWithColorCode)")
        print("[UniqloParser] productName: \(resolvedMetadata.productName)")
        print("[UniqloParser] category: \(resolvedMetadata.category.rawValue)")
        print("[UniqloParser] detailCategory: \(resolvedMetadata.detailCategory.rawValue)")
        print("[UniqloParser] sizeAPIImageURL: \(sizeAPIResult.imageURLString ?? "nil")")
        print("[UniqloParser] imageURL: \(resolvedMetadata.imageURLString ?? "nil")")
        print("[UniqloParser] sizeCount: \(sizes.count)")

        guard !sizes.isEmpty else {
            throw ProductURLParserPartialError(
                productInfo: resolvedMetadata.parsedProductInfo(
                    sizes: [],
                    parserNotice: "상품 정보는 불러왔지만 유니클로 사이즈표를 찾지 못했습니다. 상품 URL을 다시 확인해 주세요."
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
}

struct UniqloURLResolver {
    func resolve(_ url: URL) async throws -> ResolvedUniqloURL {
        print("[UniqloURLResolver] originalURL: \(url.absoluteString)")

        let response = try await fetchHTML(from: url)
        let finalURL = response.url
        let haystack = "\(url.absoluteString) \(finalURL.absoluteString) \(response.body)"

        guard let productID = extractProductID(from: haystack) else {
            print("[UniqloURLResolver] productID: nil")
            throw ProductURLParserError.unsupportedURL
        }

        let goodsID = productID.dropFirstE
        let rawColorCode = extractColorCode(from: haystack, productID: productID, goodsID: goodsID) ?? "00"
        let apiColorCode = normalizeAPIColorCode(rawColorCode)
        let imageColorCode = normalizeImageColorCode(rawColorCode)
        let productIDWithColorCode = "\(productID)-\(apiColorCode)"
        let resolvedURL = canonicalURL(productID: productID, colorCode: imageColorCode, fallback: finalURL)

        print("[UniqloURLResolver] resolvedURL: \(resolvedURL.absoluteString)")
        print("[UniqloURLResolver] productID: \(productID)")
        print("[UniqloURLResolver] goodsID: \(goodsID)")
        print("[UniqloURLResolver] apiColorCode: \(apiColorCode)")
        print("[UniqloURLResolver] imageColorCode: \(imageColorCode)")

        return ResolvedUniqloURL(
            originalURL: url,
            resolvedURL: resolvedURL,
            productID: productID,
            goodsID: goodsID,
            apiColorCode: apiColorCode,
            imageColorCode: imageColorCode,
            productIDWithColorCode: productIDWithColorCode,
            html: response.body
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

    private func canonicalURL(productID: String, colorCode: String, fallback: URL) -> URL {
        URL(string: "https://www.uniqlo.com/kr/ko/products/\(productID)?colorDisplayCode=\(colorCode)") ?? fallback
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

struct UniqloSizeAPIParser {
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
            let value = measurement.value
            valuesByCode[part.code.normalizedUniqloMeasurementKey] = value
            valuesByName[part.name.normalizedUniqloMeasurementKey] = value

            let normalizedCode = part.code.normalizedUniqloMeasurementKey
            let mapping: (MeasurementCode, MeasurementEvidenceLevel)?
            switch normalizedCode {
            case "shoulderwidth":
                mapping = (.shoulderWidthSeamToSeam, .officialText)
            case "sleevelengthcb":
                mapping = (.sleeveCenterBackToCuff, .officialText)
            default:
                mapping = nil
            }
            let displayKind = UniqloMeasurementColumn
                .column(for: normalizedCode, fallbackName: part.name.normalizedUniqloMeasurementKey)?
                .displayKind ?? .unknown
            measurementRecords.append(
                ParsedMeasurement(
                    value: value,
                    measurementCode: mapping?.0 ?? .unknown,
                    displayKind: displayKind,
                    methodSource: "uniqlo_kr",
                    methodProfile: methodProfile,
                    inputSource: .importedSizeChart,
                    rawCode: part.code,
                    rawLabel: part.name,
                    rawInfo: part.info,
                    rawValueText: measurement.rawValue,
                    evidenceLevel: mapping?.1 ?? .unknown,
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
            if let match = valuesByCode.first(where: { column.matches($0.key) })?.value {
                return match
            }
            if let match = valuesByName.first(where: { column.matches($0.key) })?.value {
                return match
            }
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

    func withPreferredImageURL(_ preferredImageURLString: String?) -> UniqloProductMetadata {
        guard let preferredImageURLString, !preferredImageURLString.isEmpty else {
            return self
        }

        var copy = self
        copy.imageURLString = preferredImageURLString
        var metadata = copy.productMetadata
        metadata.imageURLStrings = [preferredImageURLString]
        copy.productMetadata = metadata
        return copy
    }
}

struct UniqloProductMetadataParser {
    func parse(resolved: ResolvedUniqloURL) -> UniqloProductMetadata {
        let jsonLDObjects = parseJSONLDObjects(from: resolved.html)
        let productGroupObject = jsonLDObjects.first(where: { isType("ProductGroup", in: $0) })
        let productObject = jsonLDObjects.first(where: { isType("Product", in: $0) })
        let breadcrumbObject = jsonLDObjects.first(where: { isType("BreadcrumbList", in: $0) })

        let rawProductName = stringValue(productGroupObject?["name"])
            ?? stringValue(productObject?["name"])
            ?? titleFallback(from: resolved.html)
            ?? "유니클로 상품 \(resolved.goodsID)"
        let productName = sanitizedProductName(rawProductName, fallback: "유니클로 상품 \(resolved.goodsID)")
        let brandName = brandName(from: productGroupObject) ?? brandName(from: productObject) ?? "유니클로"
        let imageURLString = normalizeImageURL(firstImage(from: productGroupObject) ?? firstImage(from: productObject))
            ?? fallbackImageURL(goodsID: resolved.goodsID, colorCode: resolved.imageColorCode)
        let priceInfo = priceInfo(productGroupObject: productGroupObject, productObject: productObject, resolved: resolved)
        let breadcrumb = breadcrumbItems(from: breadcrumbObject, productName: productName)
        let htmlBreadcrumb = htmlBreadcrumbItems(from: resolved.html, productName: productName)
        let sourcePath = categoryPath(productGroupObject: productGroupObject, breadcrumb: breadcrumb, htmlBreadcrumb: htmlBreadcrumb)
        let rawSourceCategory = !breadcrumb.isEmpty
            ? breadcrumb.joined(separator: " / ")
            : (!htmlBreadcrumb.isEmpty
                ? htmlBreadcrumb.joined(separator: " / ")
                : (stringValue(productGroupObject?["category"]) ?? "nil"))
        let categoryText = sourcePath.depths.joined(separator: " ")
        let category = mapCategory(from: categoryText)
        let detailCategory = mapDetailCategory(from: sourcePath.depths.last ?? categoryText)
        let canonicalURL = canonicalURL(from: resolved.html) ?? resolved.resolvedURL.absoluteString

        let metadata = ProductMetadata(
            brandEnglishName: "UNIQLO",
            sourceCategoryPath: sourcePath.fullPath,
            sourceCategoryDepth1: sourcePath.depth1,
            sourceCategoryDepth2: sourcePath.depth2,
            sourceCategoryDepth3: sourcePath.depth3,
            sourceCategoryDepth4: sourcePath.depth4,
            baseCategoryFullPath: sourcePath.fullPath,
            categoryDepth1Name: sourcePath.depth1,
            categoryDepth2Name: sourcePath.depth2,
            categoryDepth3Name: sourcePath.depth3,
            categoryDepth4Name: sourcePath.depth4,
            genderCodes: sourcePath.gender.map { [$0] } ?? genderCodes(from: breadcrumb + htmlBreadcrumb),
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
        htmlBreadcrumb: [String]
    ) -> SourceCategoryPath {
        let breadcrumbPath = sourceCategoryPath(from: breadcrumb)
        if !breadcrumbPath.depths.isEmpty {
            return breadcrumbPath
        }

        let htmlBreadcrumbPath = sourceCategoryPath(from: htmlBreadcrumb)
        if !htmlBreadcrumbPath.depths.isEmpty {
            return htmlBreadcrumbPath
        }

        let productGroupCategory = stringValue(productGroupObject?["category"])
        let productGroupPath = sourceCategoryPath(from: splitCategoryPath(productGroupCategory))
        if !productGroupPath.depths.isEmpty {
            return productGroupPath
        }

        return sourceCategoryPath(from: [])
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

    private func logSourceCategory(rawSourceCategory: String, gender: UserGender, sourcePath: SourceCategoryPath, prefix: String) {
        print("\(prefix) raw source category: \(rawSourceCategory)")
        print("\(prefix) parsed gender: \(gender.rawValue)")
        print("\(prefix) sourceCategoryDepth1: \(sourcePath.depth1 ?? "nil")")
        print("\(prefix) sourceCategoryDepth2: \(sourcePath.depth2 ?? "nil")")
        print("\(prefix) sourceCategoryDepth3: \(sourcePath.depth3 ?? "nil")")
        print("\(prefix) sourceCategoryDepth4: \(sourcePath.depth4 ?? "nil")")
        print("\(prefix) sourceCategoryPath: \(sourcePath.fullPath ?? "nil")")
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
        return SourceCategoryPath(gender: gender, depths: parts)
    }

    private func audienceCode(from value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return ["MEN", "WOMEN", "KIDS", "BABY"].contains(normalized) ? normalized : nil
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

    private func mapCategory(from text: String) -> ClothingCategory {
        let value = text.lowercased()
        if value.contains("women") && value.contains("dress") || text.contains("원피스") {
            return .dress
        }
        if text.contains("팬츠") || text.contains("바지") || text.contains("데님") || text.contains("쇼츠") || value.contains("pants") || value.contains("jeans") || value.contains("shorts") {
            return .bottom
        }
        if text.contains("아우터") || text.contains("재킷") || text.contains("자켓") || text.contains("코트") || text.contains("파카") || text.contains("점퍼") || value.contains("outer") || value.contains("jacket") || value.contains("coat") {
            return .outer
        }
        if text.contains("속옷") || text.contains("이너") || value.contains("inner") || value.contains("underwear") {
            return .underwear
        }
        if text.contains("신발") || text.contains("슈즈") || value.contains("shoes") {
            return .shoes
        }
        if text.contains("가방") || text.contains("모자") || text.contains("벨트") || text.contains("액세서리") || value.contains("accessories") {
            return .accessory
        }
        return .top
    }

    private func mapDetailCategory(from text: String) -> ClosetDetailCategory {
        let value = text.lowercased()
        if text.contains("가디건") || value.contains("cardigan") { return .cardigan }
        if text.contains("민소매") || text.contains("나시") || value.contains("sleeveless") || value.contains("tank") { return .sleeveless }
        if text.contains("반팔") || text.contains("반소매") || value.contains("short sleeve") { return .shortSleeve }
        if text.contains("긴팔") || text.contains("긴소매") || value.contains("long sleeve") { return .longSleeve }
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

private struct UniqloPriceInfo {
    let normalPrice: Int?
    let salePrice: Int?
    let finalPrice: Int?
    let stockStatus: ProductStockStatus
}

private struct UniqloSizeChartResponse: Decodable {
    let status: String?
    let result: [ResultItem]

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
            return ["rise", "front-rise", "밑위"]
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
