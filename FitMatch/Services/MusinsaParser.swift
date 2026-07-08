import Foundation

struct MusinsaParser: ProductURLParsing {
    private let urlResolver = MusinsaURLResolver()
    private let metadataParser = MusinsaProductMetadataParser()
    private let actualSizeParser = MusinsaActualSizeAPIParser()

    func canParse(_ url: URL) -> Bool {
        url.absoluteString.lowercased().contains("musinsa")
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        let resolved = try await urlResolver.resolve(url)
        let metadata = await metadataParser.parse(productID: resolved.productID, sourceURL: resolved.resolvedURL)
        let sizes: [ParsedProductSize]
        do {
            sizes = try await actualSizeParser.parseSizes(productID: resolved.productID)
        } catch {
            print("[MusinsaParser] actual-size API failed: \(error.localizedDescription)")
            throw ProductURLParserPartialError(
                productInfo: metadata.parsedProductInfo(
                    sizes: [],
                    parserNotice: "상품 정보는 불러왔지만 실측 사이즈표를 찾지 못했습니다. 다른 무신사 상품 URL로 다시 시도해 주세요."
                )
            )
        }

        print("[MusinsaParser] detectedProvider: musinsa")
        print("[MusinsaParser] originalURL: \(resolved.originalURL.absoluteString)")
        print("[MusinsaParser] resolvedURL: \(resolved.resolvedURL.absoluteString)")
        print("[MusinsaParser] extractedProductId: \(resolved.productID)")
        print("[MusinsaParser] productName: \(metadata.productName)")
        print("[MusinsaParser] brandName: \(metadata.brandName)")
        print("[MusinsaParser] category: \(metadata.category.rawValue)")
        print("[MusinsaParser] detailCategory: \(metadata.detailCategory.rawValue)")
        print("[MusinsaParser] imageURL: \(metadata.imageURLString ?? "nil")")
        print("[MusinsaParser] sizeCount: \(sizes.count)")

        guard !sizes.isEmpty else {
            throw ProductURLParserPartialError(
                productInfo: metadata.parsedProductInfo(
                    sizes: [],
                    parserNotice: "상품 정보는 불러왔지만 실측 사이즈표를 찾지 못했습니다. 다른 무신사 상품 URL로 다시 시도해 주세요."
                )
            )
        }

        return metadata.parsedProductInfo(sizes: sizes)
    }
}
