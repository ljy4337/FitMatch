import Foundation

enum MusinsaSizeAvailabilityResolver {
    static func resolve(
        isUseSize: Bool,
        sizeType: String?,
        actualSizes: [ParsedProductSize],
        category: ClothingCategory = .other
    ) -> ProductMeasurementAvailability {
        let hasLegacyActualMeasurements = actualSizes.contains {
            $0.measurementRecords.isEmpty && !$0.measurements.isEmpty
        }
        if ParsedSizeValidator.hasUsableMeasurements(actualSizes, category: category)
            || hasLegacyActualMeasurements {
            return .actualMeasurements
        }
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
        "판매 페이지에 사이즈표가 있지만 제공 형식이나 이미지 구성 때문에 자동으로 읽지 못했어요. 사이즈표를 추가하면 바로 비교할 수 있어요."
    static let unsupportedTopBottomSetNotice =
        "상·하의가 함께 구성된 세트 상품은 아직 사이즈 비교를 지원하지 않아요."

    private let urlResolver = MusinsaURLResolver()
    private let metadataParser = MusinsaProductMetadataParser()
    private let actualSizeParser = MusinsaActualSizeAPIParser()
    private let fallbackSizeParser = MusinsaFallbackSizeParser()

    func canParse(_ url: URL) -> Bool {
        ProductURLSupport.isMusinsaURL(url)
    }

    func parse(from url: URL) async throws -> ParsedProductInfo {
        try await parse(from: url, onProgress: { _ in })
    }

    func parse(
        from url: URL,
        onProgress: @escaping (ProductAnalysisPhase) -> Void
    ) async throws -> ParsedProductInfo {
        let resolved = try await urlResolver.resolve(url)
        var metadata = await metadataParser.parse(productID: resolved.productID, sourceURL: resolved.resolvedURL)
        if MusinsaUnsupportedProductPolicy.isTopBottomSet(
            categoryDepth2Name: metadata.categoryDepth2Name
        ) {
            throw ProductURLParserPartialError(
                productInfo: metadata.parsedProductInfo(
                    sizes: [],
                    parserNotice: Self.unsupportedTopBottomSetNotice
                )
            )
        }
        onProgress(.loadingSizeChart)
        let actualSize: MusinsaActualSizeResult?
        do {
            actualSize = try await actualSizeParser.parseActualSize(
                productID: resolved.productID,
                isTopCategory: metadata.category.isMusinsaUpperBodyCategory
            )
        } catch {
            if Task.isCancelled { throw CancellationError() }
            #if DEBUG
            FitMatchDebugLogger.event(screen: "상품 분석", action: "무신사 실측 조회", state: "실패", details: "오류=\(error.localizedDescription)")
            #endif
            actualSize = nil
        }
        let actualParsedSizes = actualSize?.sizes ?? []
        var sizes = ParsedSizeValidator.validSizes(
            actualParsedSizes,
            category: metadata.category
        )
        metadata.applyActualSizeProfile(typeNumber: actualSize?.typeNumber, typeName: actualSize?.typeName)

        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "무신사 실측 검증",
            details: "API파싱수=\(actualParsedSizes.count), 유효수=\(sizes.count), 제외사이즈=\(actualParsedSizes.filter { candidate in !sizes.contains { $0.name == candidate.name } }.map(\.name).joined(separator: ","))"
        )
        #endif

        if sizes.isEmpty {
            let fallbackSizes = await fallbackSizeParser.parse(
                goodsContents: metadata.goodsContents,
                category: metadata.category,
                categoryDepth2Name: metadata.categoryDepth2Name
            )
            try Task.checkCancellation()
            sizes = ParsedSizeValidator.validSizes(
                fallbackSizes,
                category: metadata.category
            )
        }

        #if DEBUG
        FitMatchDebugLogger.detail(
            screen: "상품 분석",
            action: "무신사 파싱 완료",
            details: "상품ID=\(resolved.productID), 상품=\(metadata.productName), 브랜드=\(metadata.brandName), 분류=\(metadata.category.rawValue)/\(metadata.detailCategory.rawValue), 실측유형=\(actualSize?.typeName ?? "없음"), 사이즈수=\(sizes.count)"
        )
        #endif

        guard !sizes.isEmpty else {
            let recoveryImages = MusinsaFallbackImageExtractor.images(in: metadata.goodsContents)
                .sorted { $0.candidateScore > $1.candidateScore }
                .prefix(12)
                .map(\.url.absoluteString)
            var productInfo = metadata.parsedProductInfo(
                sizes: [],
                parserNotice: Self.automaticSizeFailureNotice
            )
            productInfo.sizeTableRecoveryContext = SizeTableRecoveryContext(
                failure: recoveryImages.isEmpty ? .noImageCandidates : .imageCandidatesAvailable,
                imageURLStrings: recoveryImages
            )
            throw ProductURLParserPartialError(
                productInfo: productInfo
            )
        }

        return metadata.parsedProductInfo(sizes: sizes)
    }
}

enum MusinsaUnsupportedProductPolicy {
    static func isTopBottomSet(categoryDepth2Name: String?) -> Bool {
        categoryDepth2Name?
            .components(separatedBy: .whitespacesAndNewlines)
            .joined() == "상하의세트"
    }
}
