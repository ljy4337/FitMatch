import Foundation

enum MusinsaSizeAvailabilityResolver {
    static func resolve(
        isUseSize: Bool,
        sizeType: String?,
        actualSizes: [ParsedProductSize],
        category: ClothingCategory = .other
    ) -> ProductMeasurementAvailability {
        if !actualSizes.isEmpty { return .actualMeasurements }
        let supportsBodyChestStandard = [.top, .outer, .dress].contains(category.serviceGroup)
        if supportsBodyChestStandard,
           isUseSize,
           (sizeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .standardSizeChart
        }
        return .unavailable
    }
}

struct MusinsaParser: ProductURLParsing {
    static let automaticSizeFailureNotice =
        "일부 상품은 사이즈 제공 방식에 따라 자동 분석이 제한될 수 있습니다.\n판매 페이지에서 사이즈표를 직접 확인해 주세요."

    private let urlResolver = MusinsaURLResolver()
    private let metadataParser = MusinsaProductMetadataParser()
    private let actualSizeParser = MusinsaActualSizeAPIParser()
    private let fallbackSizeParser = MusinsaFallbackSizeParser()

    func canParse(_ url: URL) -> Bool {
        url.absoluteString.lowercased().contains("musinsa")
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        let resolved = try await urlResolver.resolve(url)
        var metadata = await metadataParser.parse(productID: resolved.productID, sourceURL: resolved.resolvedURL)
        let actualSize: MusinsaActualSizeResult?
        do {
            actualSize = try await actualSizeParser.parseActualSize(
                productID: resolved.productID,
                isTopCategory: metadata.category.isMusinsaUpperBodyCategory
            )
        } catch {
            #if DEBUG
            FitMatchDebugLogger.event(screen: "상품 분석", action: "무신사 실측 조회", state: "실패", details: "오류=\(error.localizedDescription)")
            #endif
            actualSize = nil
        }
        var sizes = actualSize?.sizes ?? []
        metadata.applyActualSizeProfile(typeNumber: actualSize?.typeNumber, typeName: actualSize?.typeName)

        if sizes.isEmpty {
            sizes = await fallbackSizeParser.parse(
                goodsContents: metadata.goodsContents,
                category: metadata.category,
                categoryDepth2Name: metadata.categoryDepth2Name
            )
        }
        if sizes.isEmpty {
            metadata.productMetadata.sizeType = StandardBodySizeChart.unavailableMarker
        }

        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "무신사 파싱 완료",
            details: "상품ID=\(resolved.productID), 상품=\(metadata.productName), 브랜드=\(metadata.brandName), 분류=\(metadata.category.rawValue)/\(metadata.detailCategory.rawValue), 실측유형=\(actualSize?.typeName ?? "없음"), 사이즈수=\(sizes.count)"
        )
        #endif

        guard !sizes.isEmpty else {
            throw ProductURLParserPartialError(
                productInfo: metadata.parsedProductInfo(
                    sizes: [],
                    parserNotice: Self.automaticSizeFailureNotice
                )
            )
        }

        return metadata.parsedProductInfo(sizes: sizes)
    }
}
