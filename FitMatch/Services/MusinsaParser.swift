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
        var metadata = await metadataParser.parse(productID: resolved.productID, sourceURL: resolved.resolvedURL)
        let actualSize: MusinsaActualSizeResult
        do {
            actualSize = try await actualSizeParser.parseActualSize(productID: resolved.productID)
        } catch {
            #if DEBUG
            FitMatchDebugLogger.event(screen: "상품 분석", action: "무신사 실측 조회", state: "실패", details: "오류=\(error.localizedDescription)")
            #endif
            throw ProductURLParserPartialError(
                productInfo: metadata.parsedProductInfo(
                    sizes: [],
                    parserNotice: "상품 정보는 불러왔지만 실측 사이즈표를 찾지 못했습니다. 다른 무신사 상품 URL로 다시 시도해 주세요."
                )
            )
        }
        let sizes = actualSize.sizes
        metadata.applyActualSizeProfile(typeNumber: actualSize.typeNumber, typeName: actualSize.typeName)

        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "무신사 파싱 완료",
            details: "상품ID=\(resolved.productID), 상품=\(metadata.productName), 브랜드=\(metadata.brandName), 분류=\(metadata.category.rawValue)/\(metadata.detailCategory.rawValue), 실측유형=\(actualSize.typeName ?? "없음"), 사이즈수=\(sizes.count)"
        )
        #endif

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
