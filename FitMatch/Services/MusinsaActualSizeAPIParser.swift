import Foundation

struct MusinsaActualSizeAPIParser: ProductURLParsing {
    private let urlResolver = MusinsaURLResolver()
    private let metadataParser = MusinsaProductMetadataParser()

    func canParse(_ url: URL) -> Bool {
        url.absoluteString.lowercased().contains("musinsa")
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        let resolvedProduct = try await urlResolver.resolve(url)
        var metadata = await metadataParser.parse(productID: resolvedProduct.productID, sourceURL: resolvedProduct.resolvedURL)
        let actualSize = try await parseActualSize(productID: resolvedProduct.productID)
        let sizes = actualSize.sizes
        metadata.applyActualSizeProfile(typeNumber: actualSize.typeNumber, typeName: actualSize.typeName)

        guard !sizes.isEmpty else {
            throw ProductURLParserPartialError(productInfo: metadata.parsedProductInfo(sizes: []))
        }

        return metadata.parsedProductInfo(sizes: sizes)
    }

    func parseSizes(productID: String) async throws -> [ParsedProductSize] {
        try await parseActualSize(productID: productID).sizes
    }

    func parseActualSize(productID: String) async throws -> MusinsaActualSizeResult {
        guard let apiURL = URL(string: "https://goods-detail.musinsa.com/api2/goods/\(productID)/actual-size") else {
            throw ProductURLParserError.automaticParsingUnavailable
        }

        let data = try await fetchData(from: apiURL)
        return try parseActualSize(from: data)
    }

    func parseActualSize(from data: Data) throws -> MusinsaActualSizeResult {
        do {
            let response = try JSONDecoder().decode(MusinsaActualSizeResponse.self, from: data)
            return MusinsaActualSizeResult(
                typeName: response.data.typeName,
                typeNumber: response.data.typeNumber,
                webImage: response.data.webImage,
                mobileImage: response.data.mobileImage,
                sizes: response.data.sizes.compactMap {
                    makeParsedSize(from: $0, typeNumber: response.data.typeNumber, typeName: response.data.typeName)
                }
            )
        } catch {
            print("[MusinsaActualSizeAPIParser] Actual size JSON decode failed: \(error)")
            throw ProductURLParserError.automaticParsingUnavailable
        }
    }

    private func fetchData(from apiURL: URL) async throws -> Data {
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

        return data
    }

    private func makeParsedSize(
        from size: MusinsaActualSizeResponse.Size,
        typeNumber: Int?,
        typeName: String?
    ) -> ParsedProductSize? {
        guard !size.name.trimmed.isEmpty else {
            return nil
        }

        var valuesByName: [String: String] = [:]

        let measurementRecords = size.items.compactMap { item -> ParsedMeasurement? in
            let rawValue = item.value.stringValue
            guard let value = firstNumber(in: rawValue), value.isFinite, value > 0 else { return nil }
            let column = MusinsaActualSizeColumn.column(for: item.name.normalizedMeasurementName)
            let mapping = MeasurementSourceMappingPolicy.musinsa(
                typeNumber: typeNumber,
                displayKind: column?.displayKind,
                rawLabel: item.name
            )
            let normalizedValue = value * (mapping?.valueMultiplier ?? 1)
            valuesByName[item.name.normalizedMeasurementName] = String(normalizedValue)
            return ParsedMeasurement(
                value: normalizedValue,
                measurementCode: mapping?.code ?? .unknown,
                displayKind: column?.displayKind ?? .unknown,
                methodSource: "musinsa",
                methodProfile: typeNumber.map { "musinsa_type_\($0)" }
                    ?? typeName.flatMap { $0.trimmed.nonEmpty }.map { "musinsa_type_name_\($0)" },
                inputSource: .importedSizeChart,
                mappingVersion: MeasurementSourceMappingPolicy.musinsaVersion,
                rawLabel: item.name,
                rawValueText: rawValue,
                evidenceLevel: mapping?.evidence ?? .unknown,
                semanticStatus: mapping == nil ? .unknownDefinition : .mapped
            )
        }

        let measurements = GarmentMeasurements(
            shoulder: number(matching: [.shoulder], in: valuesByName) ?? 0,
            chest: number(matching: [.chest], in: valuesByName) ?? 0,
            totalLength: number(matching: [.totalLength, .inseam], in: valuesByName) ?? 0,
            sleeveLength: number(matching: [.sleeveLength], in: valuesByName) ?? 0,
            waist: number(matching: [.waist], in: valuesByName) ?? 0,
            hip: number(matching: [.hip], in: valuesByName) ?? 0,
            thigh: number(matching: [.thigh], in: valuesByName) ?? 0,
            rise: number(matching: [.rise], in: valuesByName) ?? 0,
            hem: number(matching: [.hem], in: valuesByName) ?? 0
        )

        guard !measurementRecords.isEmpty ||
                measurements.shoulder > 0 ||
                measurements.chest > 0 ||
                measurements.totalLength > 0 ||
                measurements.sleeveLength > 0 ||
                measurements.waist > 0 ||
                measurements.hip > 0 ||
                measurements.thigh > 0 ||
                measurements.rise > 0 ||
                measurements.hem > 0 else {
            return nil
        }

        return ParsedProductSize(
            name: size.name.normalizedMusinsaSizeName,
            measurements: measurements,
            measurementRecords: measurementRecords
        )
    }

    private func number(matching columns: [MusinsaActualSizeColumn], in valuesByName: [String: String]) -> Double? {
        for column in columns {
            if let match = valuesByName.first(where: { column.matches($0.key) }),
               let number = firstNumber(in: match.value) {
                return number
            }
        }
        return nil
    }

    private func firstNumber(in text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }

}

struct MusinsaActualSizeResult {
    let typeName: String?
    let typeNumber: Int?
    let webImage: String?
    let mobileImage: String?
    let sizes: [ParsedProductSize]
}

private struct MusinsaActualSizeResponse: Decodable {
    let data: DataBody

    struct DataBody: Decodable {
        let typeName: String?
        let typeNumber: Int?
        let webImage: String?
        let mobileImage: String?
        let sizes: [Size]
    }

    struct Size: Decodable {
        let name: String
        let items: [Item]
    }

    struct Item: Decodable {
        let name: String
        let value: FlexibleString
    }
}

private enum FlexibleString: Decodable {
    case string(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if container.decodeNil() {
            self = .string("")
        } else {
            throw DecodingError.typeMismatch(
                FlexibleString.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported actual-size value")
            )
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        }
    }
}

private enum MusinsaActualSizeColumn {
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

    static func column(for name: String) -> MusinsaActualSizeColumn? {
        let searchOrder: [MusinsaActualSizeColumn] = [
            .shoulder, .chest, .sleeveLength, .waist, .hip, .thigh, .rise, .inseam, .hem, .totalLength
        ]
        return searchOrder.first { $0.matches(name) }
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

private extension ParsedProductInfo {
    func withoutSizes() -> ParsedProductInfo {
        ParsedProductInfo(
            sourceURL: sourceURL,
            sourceType: sourceType,
            sourceName: sourceName,
            brandName: brandName,
            productName: productName,
            category: category,
            detailCategory: detailCategory,
            sizes: [],
            parserNotice: nil
        )
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedMeasurementName: String {
        trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    var normalizedMusinsaSizeName: String {
        let value = trimmed
        guard value.contains("/") else {
            return value
        }

        return value
            .split(separator: "/")
            .last
            .map { String($0).trimmed }
            ?? value
    }
}
