import Foundation

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
}

struct ParsedProductSize: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var measurements: GarmentMeasurements
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
            return "아직 지원하지 않는 상품 링크입니다. 현재는 무신사 상품 URL을 우선 지원합니다."
        case .automaticParsingUnavailable:
            return "상품 정보를 불러오지 못했습니다. 잠시 후 다시 시도하거나 무신사 상품 URL인지 확인해 주세요."
        }
    }
}

struct ProductURLParserPartialError: LocalizedError {
    let productInfo: ParsedProductInfo

    var errorDescription: String? {
        "상품 정보 일부만 불러왔습니다. 사이즈 정보를 찾지 못했어요."
    }
}

@MainActor
struct ProductURLParserService {
    private let musinsaParser: ProductURLParsing
    private let genericParser: ProductURLParsing

    init(
        musinsaParser: ProductURLParsing? = nil,
        genericParser: ProductURLParsing? = nil
    ) {
        self.musinsaParser = musinsaParser ?? MusinsaParser()
        self.genericParser = genericParser ?? GenericProductParser()
    }

    func parse(urlString: String) async throws -> ParsedProductInfo {
        guard let url = normalizedURL(from: urlString) else {
            throw ProductURLParserError.invalidURL
        }

        let isMusinsaURL = url.absoluteString.lowercased().contains("musinsa")
        print("[ProductURLParserService] detectedProvider: \(isMusinsaURL ? "musinsa" : "generic")")

        if isMusinsaURL {
            do {
                return try await musinsaParser.parse(from: url)
            } catch let partialError as ProductURLParserPartialError {
                print("[ProductURLParserService] Musinsa parser partially loaded product info: \(partialError.localizedDescription)")
                throw partialError
            } catch {
                print("[ProductURLParserService] Musinsa parser failed, falling back to GenericProductParser: \(error.localizedDescription)")
                do {
                    return try await genericParser.parse(from: url)
                } catch {
                    print("[ProductURLParserService] Generic fallback also failed for Musinsa URL: \(error.localizedDescription)")
                    throw ProductURLParserError.automaticParsingUnavailable
                }
            }
        }

        return try await genericParser.parse(from: url)
    }

    private func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let candidate = extractedURLString(from: trimmed) ?? trimmed
        let normalizedCandidate = candidate.hasPrefix("http://") || candidate.hasPrefix("https://")
            ? candidate
            : "https://\(candidate)"

        guard let url = URL(string: normalizedCandidate),
              url.scheme != nil,
              url.host != nil else {
            return nil
        }

        return url
    }

    private func extractedURLString(from text: String) -> String? {
        let pattern = #"(https?://)?[^\s]*musinsa[^\s]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }

        return String(text[range])
    }
}
