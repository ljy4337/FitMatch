import Foundation

/// COS exposes product-specific garment measurements behind its official
/// size-guide endpoint. The endpoint is not a published integration contract,
/// so this parser extracts both request identifiers from the official product
/// page and fails closed if either source changes.
struct COSParser: ProductURLParsing {
    private let pageLoader: COSProductPageLoading
    private let sizeGuideLoader: COSSizeGuideLoading

    init(
        pageLoader: COSProductPageLoading = COSProductPageLoader(),
        sizeGuideLoader: COSSizeGuideLoading = COSSizeGuideLoader()
    ) {
        self.pageLoader = pageLoader
        self.sizeGuideLoader = sizeGuideLoader
    }

    func canParse(_ url: URL) -> Bool {
        ProductURLSupport.isCOSURL(url)
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        try await parse(from: url, onProgress: { _ in })
    }

    func parse(
        from url: URL,
        onProgress: @escaping (ProductAnalysisPhase) -> Void
    ) async throws -> ParsedProductInfo {
        guard let productID = COSProductPageParser.productID(from: url) else {
            throw ProductURLParserError.unsupportedURL
        }

        let page = try await pageLoader.load(url: url)
        guard page.statusCode == 200,
              !COSProductPageParser.isAccessDenied(page.html) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        onProgress(.loadingSizeChart)
        let info = COSProductPageParser.parse(
            html: page.html,
            sourceURL: page.url,
            productID: productID
        )
        guard !info.productName.isEmpty else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        guard let request = COSProductPageParser.sizeGuideRequest(
            from: page.html,
            fallbackSlitmCode: info.productID
        ) else {
            throw ProductURLParserPartialError(
                productInfo: info.withNotice(
                    "COS 상품 정보는 불러왔지만 공식 사이즈표 식별자를 찾지 못했어요."
                )
            )
        }

        do {
            let data = try await sizeGuideLoader.load(
                request: request,
                referringProductURL: page.url
            )
            let sizes = try COSSizeGuideParser.parse(data: data)
            guard !sizes.isEmpty else { throw ProductURLParserError.automaticParsingUnavailable }
            var resolved = info
            resolved.productID = request.slitmCode
            resolved.productMetadata.styleNo = COSProductPageParser.articleNumber(from: page.url)
            resolved.sizes = sizes
            resolved.measurementAvailability = .actualMeasurements
            return resolved
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProductURLParserPartialError(
                productInfo: info.withNotice(
                    "상품 정보는 불러왔지만 COS 공식 실측 사이즈표를 확인하지 못했어요. 자동 비교는 진행하지 않아요."
                )
            )
        }
    }
}

protocol COSProductPageLoading: Sendable {
    func load(url: URL) async throws -> COSProductPage
}

struct COSProductPage: Sendable {
    let url: URL
    let statusCode: Int
    let html: String
}

struct COSProductPageLoader: COSProductPageLoading {
    func load(url: URL) async throws -> COSProductPage {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("ko-KR,ko;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        return COSProductPage(
            url: response.url ?? url,
            statusCode: httpResponse?.statusCode ?? -1,
            html: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

struct COSSizeGuideRequest: Equatable, Sendable {
    let slitmCode: String
    let sectionID: String
}

protocol COSSizeGuideLoading: Sendable {
    func load(request: COSSizeGuideRequest, referringProductURL: URL) async throws -> Data
}

struct COSSizeGuideLoader: COSSizeGuideLoading {
    func load(request: COSSizeGuideRequest, referringProductURL: URL) async throws -> Data {
        var components = URLComponents(
            string: "https://www.cos.com/ko-kr/pub/ncp/gb/v1/pd/gbProduct/getSizeGuide"
        )
        components?.queryItems = [
            URLQueryItem(name: "slitmCd", value: request.slitmCode),
            URLQueryItem(name: "sectId", value: request.sectionID)
        ]
        guard let url = components?.url else { throw ProductURLParserError.automaticParsingUnavailable }

        var requestURL = URLRequest(url: url)
        requestURL.httpMethod = "GET"
        requestURL.timeoutInterval = 15
        requestURL.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        requestURL.setValue("ko-KR,ko;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        requestURL.setValue(referringProductURL.absoluteString, forHTTPHeaderField: "Referer")
        requestURL.setValue("https://www.cos.com", forHTTPHeaderField: "Origin")
        requestURL.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: requestURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return data
    }
}

enum COSProductPageParser {
    static func productID(from url: URL) -> String? {
        articleNumber(from: url)
    }

    static func articleNumber(from url: URL) -> String? {
        firstMatch(in: url.path, pattern: #"\.([0-9]{10})\.html$"#)
    }

    static func sizeGuideRequest(from html: String, fallbackSlitmCode: String?) -> COSSizeGuideRequest? {
        let normalized = decodedVariants(of: html)
        let pairPattern = #"productInfo\s*\"?\s*:\s*\{\s*\"?slitmCd\"?\s*:\s*\"([A-Za-z0-9]+)\"\s*,\s*\"?sectId\"?\s*:\s*\"?(\d+)\"?"#
        for text in normalized {
            if let pair = captureGroups(in: text, pattern: pairPattern), pair.count == 2 {
                return COSSizeGuideRequest(slitmCode: pair[0], sectionID: pair[1])
            }
        }

        guard let fallbackSlitmCode,
              let sectionID = normalized.lazy.compactMap({
                  firstMatch(in: $0, pattern: #"sectInf\s*\"?\s*:\s*\{.*?\"?sectId\"?\s*:\s*\"?(\d+)\"?"#, options: [.dotMatchesLineSeparators])
              }).first else {
            return nil
        }
        return COSSizeGuideRequest(slitmCode: fallbackSlitmCode, sectionID: sectionID)
    }

    static func isAccessDenied(_ html: String) -> Bool {
        html.localizedCaseInsensitiveContains("<title>access denied</title>")
            || html.localizedCaseInsensitiveContains("errors.edgesuite.net")
    }

    static func parse(html: String, sourceURL: URL, productID: String) -> ParsedProductInfo {
        let pathMetadata = categoryMetadata(from: sourceURL)
        let jsonLD = productJSONLD(from: html)
        let productName = nonBlank(
            jsonLD?["name"] as? String,
            metaContent(in: html, property: "og:title"),
            title(in: html)
        ) ?? ""
        let imageURL = nonBlank(
            imageURL(in: jsonLD?["image"]),
            metaContent(in: html, property: "og:image")
        )
        let price = price(in: jsonLD?["offers"])
        let canonicalURL = nonBlank(
            metaContent(in: html, property: "og:url"),
            sourceURL.absoluteString
        )

        let metadata = ProductMetadata(
            styleNo: productID,
            englishName: productName,
            brandCode: "cos",
            brandEnglishName: "COS",
            sourceCategoryPath: pathMetadata.path,
            sourceCategoryDepth1: pathMetadata.depth1,
            sourceCategoryDepth2: pathMetadata.depth2,
            baseCategoryFullPath: pathMetadata.path,
            categoryDepth1Code: pathMetadata.depth1Code,
            categoryDepth2Code: pathMetadata.depth2Code,
            genderCodes: [pathMetadata.genderCode],
            imageURLStrings: imageURL.map { [$0] } ?? [],
            normalPrice: price,
            finalPrice: price,
            currencyCode: "KRW"
        )
        return ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: .officialStore,
            sourceName: "COS 공식몰",
            brandName: "COS",
            productName: productName,
            category: pathMetadata.category,
            detailCategory: pathMetadata.detailCategory,
            sizes: [],
            productID: productID,
            imageURLString: imageURL,
            price: price,
            canonicalURLString: canonicalURL,
            sourceCategoryPath: pathMetadata.path,
            sourceCategoryDepth1: pathMetadata.depth1,
            sourceCategoryDepth2: pathMetadata.depth2,
            productTargetGender: pathMetadata.gender,
            productMetadata: metadata,
            measurementAvailability: .unavailable
        )
    }

    private static func categoryMetadata(from url: URL) -> COSCategoryMetadata {
        let components = url.pathComponents
            .filter { $0 != "/" }
        let productIndex = components.firstIndex { $0.hasPrefix("product.") } ?? components.count
        let categoryComponents = Array(components.prefix(productIndex))
        let localeIndex = categoryComponents.firstIndex { $0.lowercased() == "ko-kr" }
        let route = Array(categoryComponents.dropFirst((localeIndex ?? -1) + 1))
        let genderToken = route.first?.lowercased() ?? ""
        let categoryToken = route.dropFirst().joined(separator: "/").lowercased()
        let gender: UserGender = genderToken == "men" ? .men : (genderToken == "women" ? .women : .unknown)
        let category: ClothingCategory
        let detail: ClosetDetailCategory
        if categoryToken.contains("dress") {
            category = .dress; detail = .onePiece
        } else if categoryToken.contains("trouser") || categoryToken.contains("jean") || categoryToken.contains("short") {
            category = .bottom
            detail = categoryToken.contains("jean") ? .denim : (categoryToken.contains("short") ? .shorts : .longPants)
        } else if categoryToken.contains("coat") || categoryToken.contains("jacket") || categoryToken.contains("outerwear") {
            category = .outer
            detail = categoryToken.contains("coat") ? .coat : .jacket
        } else if categoryToken.contains("t-shirt") || categoryToken.contains("top") {
            category = .top; detail = .other
        } else if categoryToken.contains("shirt") {
            category = .top; detail = .shirt
        } else if categoryToken.contains("knit") || categoryToken.contains("cardigan") {
            category = .top; detail = categoryToken.contains("cardigan") ? .cardigan : .knitTop
        } else if categoryToken.contains("underwear") || categoryToken.contains("lingerie") {
            category = .underwear; detail = .underwear
        } else if categoryToken.contains("shoe") {
            category = .shoes; detail = .other
        } else if categoryToken.contains("bag") || categoryToken.contains("accessor") {
            category = .accessory; detail = .other
        } else {
            category = .other; detail = .other
        }
        let routeLabels = route.map { $0.replacingOccurrences(of: "-", with: " ").capitalized }
        return COSCategoryMetadata(
            path: routeLabels.joined(separator: " > "),
            depth1: routeLabels.first,
            depth2: routeLabels.dropFirst().first,
            depth1Code: route.first,
            depth2Code: route.dropFirst().first,
            gender: gender,
            genderCode: genderToken.uppercased(),
            category: category,
            detailCategory: detail
        )
    }

    private static func productJSONLD(from html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let bodyRange = Range(match.range(at: 1), in: html),
                  let data = String(html[bodyRange]).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            let candidates: [[String: Any]]
            if let dictionary = object as? [String: Any] {
                candidates = [dictionary] + (dictionary["@graph"] as? [[String: Any]] ?? [])
            } else {
                candidates = object as? [[String: Any]] ?? []
            }
            if let product = candidates.first(where: { type(of: $0) == "product" }) {
                return product
            }
        }
        return nil
    }

    private static func type(of object: [String: Any]) -> String {
        if let type = object["@type"] as? String { return type.lowercased() }
        return (object["@type"] as? [String])?.joined(separator: " ").lowercased() ?? ""
    }

    private static func imageURL(in value: Any?) -> String? {
        if let value = value as? String { return value }
        if let values = value as? [String] { return values.first }
        if let value = value as? [String: Any] { return value["url"] as? String }
        return nil
    }

    private static func price(in offers: Any?) -> Int? {
        let dictionary = offers as? [String: Any]
        let raw = dictionary?["price"] as? String ?? (dictionary?["price"] as? NSNumber)?.stringValue
        return raw.flatMap { Int(Double($0) ?? -1) }.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func metaContent(in html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            #"<meta[^>]+(?:property|name)=[\"']\#(escaped)[\"'][^>]+content=[\"'](.*?)[\"'][^>]*>"#,
            #"<meta[^>]+content=[\"'](.*?)[\"'][^>]+(?:property|name)=[\"']\#(escaped)[\"'][^>]*>"#
        ]
        for pattern in patterns {
            if let value = firstMatch(
                in: html,
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) {
                return value
            }
        }
        return nil
    }

    private static func title(in html: String) -> String? {
        firstMatch(in: html, pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func captureGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func decodedVariants(of html: String) -> [String] {
        let quoted = html
            .replacingOccurrences(of: #"\\\""#, with: #"\""#)
            .replacingOccurrences(of: #"\\u0022"#, with: #"\""#)
            .replacingOccurrences(of: #"\\u003c"#, with: "<")
            .replacingOccurrences(of: #"\\u003e"#, with: ">")
        return [html, quoted]
    }

    private static func nonBlank(_ values: String?...) -> String? {
        for candidate in values {
            guard let candidate else { continue }
            let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }
}

private enum COSSizeGuideParser {
    private static let mappingVersion = "cos_kr_size_guide_mapping_v1"

    static func parse(data: Data) throws -> [ParsedProductSize] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        if text.localizedCaseInsensitiveContains("<table"),
           let table = htmlTable(from: text) {
            return makeSizes(headers: table.headers, rows: table.rows)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let table = jsonTable(from: object) else {
            throw ProductURLParserError.automaticParsingUnavailable
        }
        return makeSizes(headers: table.headers, rows: table.rows)
    }

    private static func jsonTable(from object: Any) -> (headers: [String], rows: [(String, [String])])? {
        var stringArrays: [[String]] = []
        var objectArrays: [[[String: Any]]] = []
        collect(object, stringArrays: &stringArrays, objectArrays: &objectArrays)
        let headers = stringArrays
            .filter { $0.count >= 2 && $0.filter(isSizeLabel).count >= 2 }
            .max { $0.filter(isSizeLabel).count < $1.filter(isSizeLabel).count }
        guard let headers else { return nil }

        let candidates = objectArrays.compactMap { objects -> [(String, [String])]? in
            let rows = objects.compactMap(row(from:))
            return rows.isEmpty ? nil : rows
        }
        guard let rows = candidates
            .filter({ $0.contains { $0.1.count >= headers.count } })
            .max(by: { $0.count < $1.count }) else {
            return nil
        }
        return (headers, rows)
    }

    private static func collect(
        _ object: Any,
        stringArrays: inout [[String]],
        objectArrays: inout [[[String: Any]]]
    ) {
        if let dictionary = object as? [String: Any] {
            dictionary.values.forEach { collect($0, stringArrays: &stringArrays, objectArrays: &objectArrays) }
            return
        }
        guard let array = object as? [Any] else { return }
        let strings = array.compactMap(stringValue)
        if strings.count == array.count { stringArrays.append(strings) }
        let dictionaries = array.compactMap { $0 as? [String: Any] }
        if dictionaries.count == array.count, !dictionaries.isEmpty {
            objectArrays.append(dictionaries)
        }
        array.forEach { collect($0, stringArrays: &stringArrays, objectArrays: &objectArrays) }
    }

    nonisolated private static func row(from dictionary: [String: Any]) -> (String, [String])? {
        let label = dictionary
            .sorted { scoreLabelKey($0.key) > scoreLabelKey($1.key) }
            .compactMap { scoreLabelKey($0.key) > 0 ? stringValue($0.value) : nil }
            .first
        guard let label, !label.isEmpty else { return nil }

        let values = dictionary
            .sorted { scoreValueKey($0.key) > scoreValueKey($1.key) }
            .compactMap { key, value -> [String]? in
                guard scoreValueKey(key) > 0 else { return nil }
                if let list = value as? [Any] {
                    let strings = list.compactMap(stringValue)
                    return strings.count == list.count ? strings : nil
                }
                return nil
            }
            .first
        return values.map { (label, $0) }
    }

    private static func htmlTable(from html: String) -> (headers: [String], rows: [(String, [String])])? {
        let rowPattern = #"<tr[^>]*>(.*?)</tr>"#
        let cellPattern = #"<t[hd][^>]*>(.*?)</t[hd]>"#
        let rows = matches(in: html, pattern: rowPattern).map { row in
            matches(in: row, pattern: cellPattern).map(stripHTML)
        }.filter { !$0.isEmpty }
        guard let header = rows.first(where: { $0.filter(isSizeLabel).count >= 2 }) else { return nil }
        let valueRows = rows.compactMap { row -> (String, [String])? in
            guard row.count > 1, row[0] != header[0] else { return nil }
            return (row[0], Array(row.dropFirst()))
        }
        return valueRows.isEmpty ? nil : (header, valueRows)
    }

    private static func makeSizes(headers: [String], rows: [(String, [String])]) -> [ParsedProductSize] {
        headers.enumerated().compactMap { index, name in
            let sizeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSizeLabel(sizeName) else { return nil }
            let records = rows.compactMap { label, values -> ParsedMeasurement? in
                guard index < values.count,
                      let value = Double(values[index].trimmingCharacters(in: .whitespacesAndNewlines)),
                      value.isFinite, value > 0 else { return nil }
                let mapping = measurementMapping(for: label)
                return ParsedMeasurement(
                    value: value,
                    measurementCode: mapping?.code ?? .unknown,
                    displayKind: mapping?.displayKind ?? .unknown,
                    methodSource: "cos",
                    methodProfile: "cos_kr_product_size_guide",
                    inputSource: .importedSizeChart,
                    mappingVersion: mappingVersion,
                    rawLabel: label,
                    rawValueText: values[index],
                    evidenceLevel: mapping == nil ? .unknown : .officialText,
                    semanticStatus: mapping == nil ? .unknownDefinition : .mapped
                )
            }
            guard !records.isEmpty else { return nil }
            return ParsedProductSize(
                id: ParsedProductSize.stableID(for: sizeName),
                name: sizeName,
                measurements: GarmentMeasurements(
                    shoulder: firstValue(.shoulder, in: records),
                    chest: firstValue(.chest, in: records),
                    totalLength: firstValue(.totalLength, in: records),
                    sleeveLength: firstValue(.sleeveLength, in: records),
                    waist: firstValue(.waist, in: records),
                    hip: firstValue(.hip, in: records),
                    thigh: firstValue(.thigh, in: records),
                    rise: firstValue(.rise, in: records),
                    hem: firstValue(.hem, in: records)
                ),
                measurementRecords: records
            )
        }
    }

    private static func measurementMapping(for rawLabel: String) -> (code: MeasurementCode, displayKind: MeasurementDisplayKind)? {
        let label = rawLabel.lowercased().replacingOccurrences(of: "½", with: "half")
        if label.contains("shoulder to shoulder") { return (.shoulderWidthSeamToSeam, .shoulder) }
        if label.contains("chest") || label.contains("bust") { return (.chestWidthPitToPit, .chest) }
        if label.contains("back length") { return (.bodyLengthBackNeckToHem, .totalLength) }
        if label.contains("sleeve length") { return (.sleeveShoulderSeamToCuff, .sleeveLength) }
        if label.contains("inside leg") || label.contains("inseam") { return (.pantsInseamCrotchToHem, .totalLength) }
        if label.contains("front rise") { return (.riseCrotchToWaistFront, .rise) }
        if label.contains("back rise") { return (.riseCrotchToWaistBack, .rise) }
        if label.contains("waist") { return (.waistWidthEdgeToEdge, .waist) }
        if label.contains("hip") { return (.hipWidthAtWidest, .hip) }
        if label.contains("thigh") { return (.thighWidthCrotchToOuter, .thigh) }
        if label.contains("bottom opening") || label.contains("hem") { return (.hemWidthEdgeToEdge, .hem) }
        return nil
    }

    private static func firstValue(_ kind: MeasurementDisplayKind, in records: [ParsedMeasurement]) -> Double {
        records.first(where: { $0.displayKind == kind })?.value ?? 0
    }

    nonisolated private static func scoreLabelKey(_ key: String) -> Int {
        let key = key.lowercased()
        if key.contains("name") || key.contains("label") || key.contains("title") { return 2 }
        if key.contains("part") || key.contains("item") { return 1 }
        return 0
    }

    nonisolated private static func scoreValueKey(_ key: String) -> Int {
        let key = key.lowercased()
        if key.contains("value") || key.contains("measurement") { return 2 }
        if key.contains("size") || key.contains("data") { return 1 }
        return 0
    }

    nonisolated private static func stringValue(_ value: Any) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    nonisolated private static func isSizeLabel(_ value: String) -> Bool {
        let normalized = value.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["XXS", "XS", "S", "M", "L", "XL", "XXL", "XXXL"].contains(normalized)
            || normalized.range(of: #"^\d{2,3}$"#, options: .regularExpression) != nil
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap {
            guard $0.numberOfRanges > 1, let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    nonisolated private static func stripHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct COSCategoryMetadata {
    let path: String
    let depth1: String?
    let depth2: String?
    let depth1Code: String?
    let depth2Code: String?
    let gender: UserGender
    let genderCode: String
    let category: ClothingCategory
    let detailCategory: ClosetDetailCategory
}

private extension ParsedProductInfo {
    func withNotice(_ notice: String) -> ParsedProductInfo {
        var copy = self
        copy.parserNotice = notice
        return copy
    }
}
