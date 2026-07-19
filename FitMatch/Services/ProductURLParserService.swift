import Foundation

enum ProductMeasurementAvailability: String, Equatable {
    case actualMeasurements
    case standardSizeChart
    case unavailable
}

enum ProductComparisonMode: String, Equatable {
    case actualMeasurements
    case standardSizeFallback
    case unavailable
}

enum StandardBodySizeChart {
    static let metadataMarker = "fitmatch_standard_size_chart"
    static let unavailableMarker = "fitmatch_size_unavailable"

    static func normalizedSize(from optionName: String) -> String? {
        let uppercased = optionName.uppercased()
        let pattern = #"(?<![A-Z0-9])(XXL|XL|XS|L|M|S)(?![A-Z])"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(
                in: uppercased,
                range: NSRange(uppercased.startIndex..<uppercased.endIndex, in: uppercased)
            )
            guard matches.count <= 1 else {
                // A set option such as "브라_S 팬티_L" must not be interpreted
                // as one garment's body-chest standard size.
                return nil
            }
            if let match = matches.first,
           let range = Range(match.range(at: 1), in: uppercased) {
                return String(uppercased[range])
            }
        }

        let circumferencePattern = #"(?:44|55|66|77|88|110)\s*\((85|90|95|100|105|110)\)"#
        guard let regex = try? NSRegularExpression(pattern: circumferencePattern),
              let match = regex.firstMatch(
                in: uppercased,
                range: NSRange(uppercased.startIndex..<uppercased.endIndex, in: uppercased)
              ),
              let range = Range(match.range(at: 1), in: uppercased),
              let circumference = Double(uppercased[range]) else {
            return nil
        }
        return sizeName(for: circumference)
    }

    static func chestCircumferenceCm(for optionName: String) -> Double? {
        guard let size = normalizedSize(from: optionName) else { return nil }
        return ["XS": 85, "S": 90, "M": 95, "L": 100, "XL": 105, "XXL": 110][size]
    }

    private static func sizeName(for circumference: Double) -> String? {
        [85: "XS", 90: "S", 95: "M", 100: "L", 105: "XL", 110: "XXL"][circumference]
    }
}

struct ParsedProductInfo {
    var sourceURL: URL
    var sourceType: ProductSourceType = .manual
    var sourceName: String = "직접 입력"
    var brandName: String
    var productName: String
    var category: ClothingCategory
    var detailCategory: ClosetDetailCategory
    var sizes: [ParsedProductSize]
    var parserNotice: String? = nil
    var productID: String? = nil
    var imageURLString: String? = nil
    var price: Int? = nil
    var canonicalURLString: String? = nil
    var sourceCategoryPath: String? = nil
    var sourceCategoryDepth1: String? = nil
    var sourceCategoryDepth2: String? = nil
    var sourceCategoryDepth3: String? = nil
    var sourceCategoryDepth4: String? = nil
    var productTargetGender: UserGender = .unknown
    var productMetadata: ProductMetadata = ProductMetadata()
    var measurementAvailability: ProductMeasurementAvailability = .actualMeasurements
    var sizeTableRecoveryContext: SizeTableRecoveryContext? = nil
}

struct ParsedProductSize: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var measurements: GarmentMeasurements
    var measurementRecords: [ParsedMeasurement] = []
    var standardBodyChestCircumferenceCm: Double? = nil
}

struct ParsedMeasurement: Equatable {
    var value: Double
    var unit: MeasurementUnit = .centimeter
    var measurementCode: MeasurementCode
    var displayKind: MeasurementDisplayKind
    var methodSource: String
    var methodProfile: String? = nil
    var inputSource: MeasurementInputSource
    var standardVersion: String? = nil
    var mappingVersion: String = "measurement_mapping_v1"
    var rawCode: String? = nil
    var rawLabel: String
    var rawInfo: String? = nil
    var rawValueText: String? = nil
    var evidenceLevel: MeasurementEvidenceLevel
    var semanticStatus: MeasurementSemanticStatus

    func makeRecord(productSize: ProductSize? = nil, userFit: UserFit? = nil) -> GarmentMeasurementRecord {
        GarmentMeasurementRecord(
            value: value,
            unit: unit,
            measurementCode: measurementCode,
            displayKind: displayKind,
            methodSource: methodSource,
            methodProfile: methodProfile,
            inputSource: inputSource,
            standardVersion: standardVersion,
            mappingVersion: mappingVersion,
            rawCode: rawCode,
            rawLabel: rawLabel,
            rawInfo: rawInfo,
            rawValueText: rawValueText,
            evidenceLevel: evidenceLevel,
            semanticStatus: semanticStatus,
            productSize: productSize,
            userFit: userFit
        )
    }
}

extension ParsedProductSize {
    static func stableID(for sizeName: String) -> UUID {
        let normalizedName = sizeName
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { ParsedProductSizeNormalizer.normalizedSizeKey(for: String($0)) }
            .joined(separator: "|")
        let seed = normalizedName.isEmpty ? sizeName : normalizedName
        let bytes = Array(seed.utf8)
        var firstHash: UInt64 = 14_695_981_039_346_656_037
        var secondHash: UInt64 = 10_995_116_282_11

        for byte in bytes {
            firstHash ^= UInt64(byte)
            firstHash &*= 1_099_511_628_211
        }

        for byte in bytes.reversed() {
            secondHash ^= UInt64(byte)
            secondHash &*= 1_099_511_628_211
        }

        var uuidBytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            uuidBytes[index] = UInt8((firstHash >> UInt64(index * 8)) & 0xff)
            uuidBytes[index + 8] = UInt8((secondHash >> UInt64(index * 8)) & 0xff)
        }
        uuidBytes[6] = (uuidBytes[6] & 0x0f) | 0x50
        uuidBytes[8] = (uuidBytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }
}

enum ParsedProductSizeNormalizer {
    static func normalizedSizeKey(for name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    static func uniqueSizes(_ sizes: [ParsedProductSize]) -> [ParsedProductSize] {
        var seenKeys = Set<String>()
        var uniqueSizes: [ParsedProductSize] = []

        for size in sizes {
            let key = normalizedSizeKey(for: size.name)
            guard !key.isEmpty, !seenKeys.contains(key) else {
                continue
            }

            seenKeys.insert(key)
            uniqueSizes.append(size)
        }

        return uniqueSizes
    }

    static func uniqueProductSizes(_ sizes: [ProductSize]) -> [ProductSize] {
        var seenKeys = Set<String>()
        var uniqueSizes: [ProductSize] = []

        for size in sizes {
            let key = normalizedSizeKey(for: size.name)
            guard !key.isEmpty, !seenKeys.contains(key) else {
                continue
            }

            seenKeys.insert(key)
            uniqueSizes.append(size)
        }

        return uniqueSizes
    }

    static func makeProductSizes(from sizes: [ParsedProductSize]) -> [ProductSize] {
        uniqueSizes(sizes).enumerated().map { index, size in
            let productSize = ProductSize(
                id: size.id,
                name: size.name.trimmingCharacters(in: .whitespacesAndNewlines),
                measurements: size.measurements,
                displayOrder: index
            )
            let records = size.measurementRecords.map { $0.makeRecord(productSize: productSize) }
            productSize.measurementRecords = records
            if !records.isEmpty {
                productSize.measurementSchemaVersion = 1
                productSize.measurementMigrationVersion = MeasurementLegacyBackfillService.migrationVersion
                productSize.measurementMigrationStatus = .completed
                productSize.measurementMigrationErrorCode = nil
            }
            return productSize
        }
    }
}

@MainActor
protocol ProductURLParsing {
    func canParse(_ url: URL) -> Bool
    func parse(from url: URL) async throws -> ParsedProductInfo
}

enum ProductURLParserError: LocalizedError {
    case invalidURL
    case unsupportedURL
    case automaticParsingUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "올바른 상품 URL을 입력해 주세요."
        case .unsupportedURL:
            return "아직 지원하지 않는 상품 링크입니다. 현재는 무신사와 유니클로 상품 URL을 우선 지원합니다."
        case .automaticParsingUnavailable:
            return "상품 정보를 불러오지 못했습니다. 잠시 후 다시 시도하거나 지원 쇼핑몰 상품 URL인지 확인해 주세요."
        }
    }
}

struct ProductURLParserPartialError: LocalizedError {
    let productInfo: ParsedProductInfo

    var errorDescription: String? {
        "상품 정보 일부만 불러왔습니다. 사이즈 정보를 찾지 못했어요."
    }
}

enum ProductURLSupport {
    static func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let candidate = extractedURLString(from: trimmed) ?? trimmed
        let normalizedCandidate = candidate.hasPrefix("http://") || candidate.hasPrefix("https://")
            ? candidate
            : "https://\(candidate)"

        guard let url = URL(string: normalizedCandidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }

        return url
    }

    static func supportedProviderName(for urlString: String) -> String? {
        guard let url = normalizedURL(from: urlString) else {
            return nil
        }

        let value = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""

        if value.contains("musinsa") { return "무신사" }
        if host.contains("uniqlo") { return "유니클로" }

        return nil
    }

    static func isSupportedProductURL(_ urlString: String) -> Bool {
        supportedProviderName(for: urlString) != nil
    }

    static func extractedURLString(from text: String) -> String? {
        let pattern = #"(https?://)?[^\s]*(musinsa|uniqlo)[^\s]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }

        return String(text[range])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\"'<>"))
    }
}

@MainActor
struct ProductURLParserService {
    private let musinsaParser: ProductURLParsing
    private let uniqloParser: ProductURLParsing
    private let genericParser: ProductURLParsing

    init(
        musinsaParser: ProductURLParsing? = nil,
        uniqloParser: ProductURLParsing? = nil,
        genericParser: ProductURLParsing? = nil
    ) {
        self.musinsaParser = musinsaParser ?? MusinsaParser()
        self.uniqloParser = uniqloParser ?? UniqloParser()
        self.genericParser = genericParser ?? GenericProductParser()
    }

    func parse(urlString: String) async throws -> ParsedProductInfo {
        guard let url = ProductURLSupport.normalizedURL(from: urlString) else {
            throw ProductURLParserError.invalidURL
        }

        let isMusinsaURL = url.absoluteString.lowercased().contains("musinsa")
        let isUniqloURL = uniqloParser.canParse(url)
        let detectedProvider = isMusinsaURL ? "musinsa" : (isUniqloURL ? "uniqlo" : "generic")
        #if DEBUG
        FitMatchDebugLogger.detail(screen: "상품 분석", action: "파서 선택", details: "파서=\(detectedProvider)")
        #endif

        if isMusinsaURL {
            do {
                return logParsedProductInfo((try await musinsaParser.parse(from: url)).normalizedSizes())
            } catch let partialError as ProductURLParserPartialError {
                #if DEBUG
                FitMatchDebugLogger.event(screen: "상품 분석", action: "무신사 파싱", state: "일부 성공", details: "오류=\(partialError.localizedDescription)")
                #endif
                throw ProductURLParserPartialError(productInfo: partialError.productInfo.normalizedSizes())
            } catch {
                #if DEBUG
                FitMatchDebugLogger.event(screen: "상품 분석", action: "무신사 파싱", state: "대체 파싱", details: "오류=\(error.localizedDescription)")
                #endif
                do {
                    return (try await genericParser.parse(from: url)).normalizedSizes()
                } catch {
                    #if DEBUG
                    FitMatchDebugLogger.event(screen: "상품 분석", action: "무신사 대체 파싱", state: "실패", details: "오류=\(error.localizedDescription)")
                    #endif
                    throw ProductURLParserError.automaticParsingUnavailable
                }
            }
        }

        if isUniqloURL {
            do {
                return logParsedProductInfo((try await uniqloParser.parse(from: url)).normalizedSizes())
            } catch let partialError as ProductURLParserPartialError {
                #if DEBUG
                FitMatchDebugLogger.event(screen: "상품 분석", action: "유니클로 파싱", state: "일부 성공", details: "오류=\(partialError.localizedDescription)")
                #endif
                throw ProductURLParserPartialError(productInfo: partialError.productInfo.normalizedSizes())
            } catch {
                #if DEBUG
                FitMatchDebugLogger.event(screen: "상품 분석", action: "유니클로 파싱", state: "대체 파싱", details: "오류=\(error.localizedDescription)")
                #endif
                do {
                    return (try await genericParser.parse(from: url)).normalizedSizes()
                } catch {
                    #if DEBUG
                    FitMatchDebugLogger.event(screen: "상품 분석", action: "유니클로 대체 파싱", state: "실패", details: "오류=\(error.localizedDescription)")
                    #endif
                    throw ProductURLParserError.automaticParsingUnavailable
                }
            }
        }

        return logParsedProductInfo((try await genericParser.parse(from: url)).normalizedSizes())
    }

    private func logParsedProductInfo(_ productInfo: ParsedProductInfo) -> ParsedProductInfo {
        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "파싱 결과",
            details: "성별=\(productInfo.productTargetGender.rawValue), depth1=\(productInfo.sourceCategoryDepth1 ?? "없음"), depth2=\(productInfo.sourceCategoryDepth2 ?? "없음"), depth3=\(productInfo.sourceCategoryDepth3 ?? "없음"), depth4=\(productInfo.sourceCategoryDepth4 ?? "없음"), 경로=\(productInfo.sourceCategoryPath ?? "없음")"
        )
        #endif
        return productInfo
    }

    private func normalizedURL(from rawValue: String) -> URL? {
        ProductURLSupport.normalizedURL(from: rawValue)
    }

    private func extractedURLString(from text: String) -> String? {
        ProductURLSupport.extractedURLString(from: text)
    }
}

extension ParsedProductInfo {
    func normalizedSizes() -> ParsedProductInfo {
        var copy = self
        copy.sizes = ParsedProductSizeNormalizer.uniqueSizes(sizes)
        return copy
    }
}
