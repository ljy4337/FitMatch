import Foundation
import Combine

@MainActor
final class ShoppingProductViewModel: ObservableObject {
    @Published var productURL = ""
    @Published var sourceType: ProductSourceType = .manual
    @Published var sourceName = "직접 입력"
    @Published var brand = ""
    @Published var productName = ""
    @Published var category: ClothingCategory = .top
    @Published var detailCategory: ClosetDetailCategory = .other
    @Published var sizeOptions: [ClothingSizeForm] = [
        ClothingSizeForm()
    ]
    @Published var recommendation: RecommendationHistory?
    @Published var errorMessage: String?
    @Published var parserNotice: String?
    @Published var isLoadingProductInfo = false
    @Published var productImageURLString: String?
    @Published var productPrice: Int?
    @Published var productCanonicalURLString: String?
    @Published var productCode: String?
    @Published var productMetadata = ProductMetadata()
    @Published var hasLoadedProductInfo = false
    @Published var measurementAvailability: ProductMeasurementAvailability = .actualMeasurements
    @Published var sizeTableRecoveryContext: SizeTableRecoveryContext?
    @Published var isAnalyzingRecoveryImage = false
    @Published var recoveryErrorMessage: String?
    @Published var isNetworkFailure = false

    private let recommendationService: RecommendationService
    private let parserService: ProductURLParserService

    init(
        initialURL: String? = nil,
        recommendationService: RecommendationService? = nil,
        parserService: ProductURLParserService? = nil
    ) {
        productURL = initialURL ?? ""
        self.recommendationService = recommendationService ?? RecommendationService()
        self.parserService = parserService ?? ProductURLParserService()
    }

    func addSizeOption() {
        sizeOptions.append(ClothingSizeForm())
    }

    func removeSizeOption(_ option: ClothingSizeForm) {
        guard sizeOptions.count > 1 else {
            return
        }

        sizeOptions.removeAll { $0.id == option.id }
    }

    func loadProductInfoFromURL() async -> Bool {
        errorMessage = nil
        parserNotice = nil
        hasLoadedProductInfo = false
        productCode = nil
        productMetadata = ProductMetadata()
        sizeTableRecoveryContext = nil
        isNetworkFailure = false
        isLoadingProductInfo = true
        defer { isLoadingProductInfo = false }

        do {
            let parsedProduct = try await parserService.parse(urlString: productURL)
            apply(parsedProduct)
            return true
        } catch let partialError as ProductURLParserPartialError {
            apply(partialError.productInfo)
            if partialError.productInfo.sourceName == "무신사",
               partialError.productInfo.sizes.isEmpty {
                errorMessage = MusinsaParser.automaticSizeFailureNotice
            } else {
                errorMessage = partialError.productInfo.parserNotice ?? partialError.errorDescription
            }
            return false
        } catch {
            let nsError = error as NSError
            isNetworkFailure = nsError.domain == NSURLErrorDomain
                || (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.domain == NSURLErrorDomain
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "상품 정보를 불러오지 못했습니다."
            return false
        }
    }

    func analyzeRecoveryImage(url: URL) async -> Bool {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                recoveryErrorMessage = "이미지를 불러오지 못했어요."
                return false
            }
            return analyzeRecoveryImage(data: data)
        } catch {
            recoveryErrorMessage = "이미지를 불러오지 못했어요."
            return false
        }
    }

    func analyzeRecoveryImage(data: Data) -> Bool {
        recoveryErrorMessage = nil
        isAnalyzingRecoveryImage = true
        defer { isAnalyzingRecoveryImage = false }
        let parsed = MusinsaFallbackSizeParser().parseRecoveryImage(
            data: data,
            category: category,
            categoryDepth2Name: productMetadata.categoryDepth2Name
        )
        guard !parsed.isEmpty else {
            recoveryErrorMessage = "표를 확정하지 못했어요. 값을 직접 입력해 주세요."
            return false
        }
        sizeOptions = parsed.enumerated().map {
            Self.makeSizeForm(from: $0.element, displayOrder: $0.offset, allowsStandardSizeFallback: false)
        }
        sizeTableRecoveryContext = SizeTableRecoveryContext(
            failure: .incompleteOCR,
            imageURLStrings: sizeTableRecoveryContext?.imageURLStrings ?? []
        )
        return true
    }

    @discardableResult
    func calculateRecommendation(
        userFits: [UserFit],
        brand: Brand? = nil,
        allowsGlobalFallback: Bool = false
    ) -> RecommendationHistory? {
        errorMessage = nil

        guard !userFits.isEmpty else {
            errorMessage = "먼저 내 옷장에 기준 옷을 추가해 주세요."
            recommendation = nil
            return nil
        }

        guard let product = makeProduct(brand: brand) else {
            errorMessage = "상품명과 최소 1개 사이즈의 실측값을 입력해 주세요."
            recommendation = nil
            return nil
        }

        guard let history = recommendationService.recommend(
            product: product,
            userFits: userFits,
            productDetailCategory: detailCategory,
            allowsGlobalFallback: allowsGlobalFallback
        ) else {
            errorMessage = "측정 방식이 호환되는 실측 항목이 부족해 추천할 수 없습니다."
            recommendation = nil
            return nil
        }

        recommendation = history
        return history
    }

    @discardableResult
    func calculateTemporaryRecommendation(
        selectedReferenceItem: UserFit,
        brand: Brand? = nil
    ) -> RecommendationHistory? {
        errorMessage = nil

        guard let product = makeProduct(brand: brand) else {
            errorMessage = "상품명과 최소 1개 사이즈의 실측값을 입력해 주세요."
            recommendation = nil
            return nil
        }

        guard let history = recommendationService.recommend(
            product: product,
            selectedReferenceItem: selectedReferenceItem,
            productDetailCategory: detailCategory
        ) else {
            errorMessage = "측정 방식이 호환되는 실측 항목이 부족해 추천할 수 없습니다."
            recommendation = nil
            return nil
        }

        recommendation = history
        return history
    }

    func needsDetailCategoryBasis(userFits: [UserFit]) -> Bool {
        guard hasLoadedProductInfo else {
            return false
        }

        guard !userFits.isEmpty else {
            return true
        }

        guard let product = makeProduct(brand: makeBrand()) else {
            return false
        }

        return !recommendationService.hasRelevantClosetItem(
            product: product,
            productDetailCategory: detailCategory,
            userFits: userFits
        )
    }

    func temporaryComparisonCandidates(userFits: [UserFit], brand: Brand? = nil) -> [UserFit] {
        guard let product = makeProduct(brand: brand) else {
            return []
        }

        return recommendationService.temporaryComparisonCandidates(
            product: product,
            productDetailCategory: detailCategory,
            userFits: userFits
        )
    }

    func needsFallbackDecision(userFits: [UserFit], brand: Brand? = nil) -> Bool {
        guard let product = makeProduct(brand: brand), !userFits.isEmpty else {
            return false
        }

        return !recommendationService.hasRelevantClosetItem(
            product: product,
            productDetailCategory: detailCategory,
            userFits: userFits
        )
    }

    func makeBrand() -> Brand? {
        let trimmedBrand = brand.trimmed
        guard !trimmedBrand.isEmpty else {
            return nil
        }

        return Brand(name: trimmedBrand)
    }

    func makeProductForClosetRegistration(brand: Brand?) -> Product? {
        makeProduct(brand: brand)
    }

    private func makeProduct(brand: Brand?) -> Product? {
        let validOptions = sizeOptions.compactMap {
            $0.makeSizeOption(category: category, detailCategory: detailCategory)
        }
        guard !productName.trimmed.isEmpty, !validOptions.isEmpty else {
            return nil
        }

        let product = Product(
            name: productName.trimmed,
            brand: brand,
            category: category,
            productCode: productCode,
            sourceURLString: productCanonicalURLString ?? (productURL.trimmed.isEmpty ? nil : productURL.trimmed),
            imageURLString: productImageURLString,
            metadata: productMetadata,
            sourceType: sourceType,
            sourceName: resolvedSourceName,
            sizes: validOptions
        )
        if let canonical = ParsedClosetClassification.resolve(
            category: category,
            detailCategory: detailCategory,
            sourceDepths: [productMetadata.sourceCategoryDepth1, productMetadata.sourceCategoryDepth2,
                           productMetadata.sourceCategoryDepth3, productMetadata.sourceCategoryDepth4],
            sourcePath: productMetadata.sourceCategoryPath,
            productName: productName
        ) {
            product.categoryCode = canonical.categoryCode
            product.normalizedProductTypeCode = canonical.normalizedProductTypeCode
            product.garmentType = canonical.garmentFamily
            product.sleeveType = canonical.lengthType
            product.constructionType = canonical.constructionType
        }
        _ = ComparisonProfileMatcher().profile(for: product, detailCategory: detailCategory)
        return product
    }

    private func apply(_ parsedProduct: ParsedProductInfo) {
        productURL = parsedProduct.sourceURL.absoluteString
        sourceType = parsedProduct.sourceType
        sourceName = parsedProduct.sourceName
        brand = parsedProduct.brandName
        productName = parsedProduct.productName
        category = parsedProduct.category
        detailCategory = parsedProduct.detailCategory
        productImageURLString = parsedProduct.imageURLString
        productPrice = parsedProduct.price
        productCanonicalURLString = parsedProduct.canonicalURLString
        productCode = parsedProduct.productID
        productMetadata = metadataWithSourceCategory(from: parsedProduct)
        measurementAvailability = parsedProduct.measurementAvailability
        sizeTableRecoveryContext = parsedProduct.sizeTableRecoveryContext
        parserNotice = parsedProduct.parserNotice
        hasLoadedProductInfo = true
        #if DEBUG
        FitMatchDebugLogger.event(
            screen: "상품 비교",
            action: "파싱 데이터 적용",
            state: "완료",
            details: "상품=\(productName), 브랜드=\(brand), 출처=\(sourceName), 성별=\(UserGender.productTarget(from: productMetadata.genderCodes).rawValue), 원본분류=\(productMetadata.sourceCategoryPath ?? "없음"), FitMatch분류=\(category.rawValue)/\(detailCategory.rawValue), 사이즈수=\(parsedProduct.sizes.count)"
        )
        #endif
        guard !parsedProduct.sizes.isEmpty else {
            sizeOptions = [ClothingSizeForm()]
            return
        }

        sizeOptions = parsedProduct.sizes.enumerated().map { index, size in
            Self.makeSizeForm(
                from: size,
                displayOrder: index,
                allowsStandardSizeFallback: parsedProduct.measurementAvailability != .actualMeasurements
            )
        }
    }

    static func makeSizeForm(
        from size: ParsedProductSize,
        displayOrder: Int,
        allowsStandardSizeFallback: Bool
    ) -> ClothingSizeForm {
        let chestCircumference = size.measurementRecords.first {
            $0.measurementCode == .chestCircumferenceGarment
                && $0.semanticStatus == .mapped
                && $0.value.isFinite
                && $0.value > 0
        }
        return ClothingSizeForm(
            sizeName: size.name,
            shoulder: MeasurementResolver.value(for: .shoulder, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            chest: MeasurementResolver.value(for: .chest, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            totalLength: MeasurementResolver.value(for: .totalLength, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            sleeveLength: MeasurementResolver.value(for: .sleeveLength, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            waist: MeasurementResolver.value(for: .waist, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            hip: MeasurementResolver.value(for: .hip, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            thigh: MeasurementResolver.value(for: .thigh, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            rise: MeasurementResolver.value(for: .rise, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            hem: MeasurementResolver.value(for: .hem, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            footLength: MeasurementResolver.value(for: .footLength, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            underBust: MeasurementResolver.value(for: .underBust, measurements: size.measurements, records: size.measurementRecords)?.extractedFormText ?? "",
            chestUsesCircumference: size.measurements.chest <= 0 && chestCircumference != nil,
            displayOrder: displayOrder,
            parsedMeasurementRecords: size.measurementRecords,
            standardBodyChestCircumferenceCm: size.standardBodyChestCircumferenceCm,
            allowsStandardSizeFallback: allowsStandardSizeFallback
        )
    }

    private func metadataWithSourceCategory(from parsedProduct: ParsedProductInfo) -> ProductMetadata {
        var metadata = parsedProduct.productMetadata
        metadata.sourceCategoryPath = parsedProduct.sourceCategoryPath ?? metadata.sourceCategoryPath ?? metadata.baseCategoryFullPath
        metadata.sourceCategoryDepth1 = parsedProduct.sourceCategoryDepth1 ?? metadata.sourceCategoryDepth1 ?? metadata.categoryDepth1Name
        metadata.sourceCategoryDepth2 = parsedProduct.sourceCategoryDepth2 ?? metadata.sourceCategoryDepth2 ?? metadata.categoryDepth2Name
        metadata.sourceCategoryDepth3 = parsedProduct.sourceCategoryDepth3 ?? metadata.sourceCategoryDepth3 ?? metadata.categoryDepth3Name
        metadata.sourceCategoryDepth4 = parsedProduct.sourceCategoryDepth4 ?? metadata.sourceCategoryDepth4 ?? metadata.categoryDepth4Name
        if metadata.baseCategoryFullPath == nil {
            metadata.baseCategoryFullPath = metadata.sourceCategoryPath
        }
        return metadata
    }

    var resolvedSourceName: String {
        switch sourceType {
        case .officialStore:
            return sourceName.trimmed.isEmpty ? "\(brand.trimmed) 공식몰" : sourceName.trimmed
        case .marketplace:
            return sourceName.trimmed
        case .manual:
            return sourceName.trimmed.isEmpty ? "직접 입력" : sourceName.trimmed
        }
    }

}

struct ClothingSizeForm: Identifiable, Equatable {
    var id = UUID()
    var sizeName = ""
    var shoulder = ""
    var chest = ""
    var totalLength = ""
    var sleeveLength = ""
    var waist = ""
    var hip = ""
    var thigh = ""
    var rise = ""
    var hem = ""
    var footLength = ""
    var underBust = ""
    var chestUsesCircumference = false
    var waistUsesCircumference = false
    var displayOrder = 0
    var parsedMeasurementRecords: [ParsedMeasurement] = []
    var standardBodyChestCircumferenceCm: Double? = nil
    var allowsStandardSizeFallback = false

    func makeSizeOption(category: ClothingCategory, detailCategory: ClosetDetailCategory = .other, gender: UserGender = .unisex) -> ProductSize? {
        guard !sizeName.trimmed.isEmpty else {
            return nil
        }

        let measurementKinds = category.measurementKinds(detailCategory: detailCategory, gender: gender)
        guard !measurementKinds.isEmpty else {
            return nil
        }

        let validMeasurementCount = measurementKinds.filter {
            numericValue(for: $0) > 0
        }.count
        let isStandardSizeOption = allowsStandardSizeFallback
        guard validMeasurementCount >= min(2, measurementKinds.count) || isStandardSizeOption else {
            return nil
        }

        let productSize = ProductSize(
            id: id,
            name: sizeName.trimmed,
            measurements: GarmentMeasurements(
                shoulder: numericValue(for: .shoulder),
                chest: chestUsesCircumference ? 0 : numericValue(for: .chest),
                totalLength: numericValue(for: .totalLength),
                sleeveLength: numericValue(for: .sleeveLength),
                waist: waistUsesCircumference ? 0 : numericValue(for: .waist),
                hip: numericValue(for: .hip),
                thigh: numericValue(for: .thigh),
                rise: numericValue(for: .rise),
                hem: numericValue(for: .hem),
                footLength: numericValue(for: .footLength),
                underBust: numericValue(for: .underBust)
            ),
            displayOrder: displayOrder
        )
        let sourceRecords = parsedMeasurementRecords.isEmpty
            ? manualMeasurementRecords(
                category: category,
                detailCategory: detailCategory,
                productSize: productSize
            )
            : parsedMeasurementRecords.map { $0.makeRecord(productSize: productSize) }
        let records = sourceRecords
        productSize.measurementRecords = records
        if !records.isEmpty {
            productSize.measurementSchemaVersion = 1
            productSize.measurementMigrationVersion = MeasurementLegacyBackfillService.migrationVersion
            productSize.measurementMigrationStatus = .completed
        }
        return productSize
    }

    private func manualMeasurementRecords(
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory,
        productSize: ProductSize
    ) -> [GarmentMeasurementRecord] {
        category.measurementKinds(detailCategory: detailCategory, gender: .unisex).compactMap { kind in
            let value = numericValue(for: kind)
            guard value > 0, let code = manualMeasurementCode(for: kind, category: category) else {
                return nil
            }
            let label: String
            switch kind {
            case .chest: label = chestUsesCircumference ? "가슴둘레" : "가슴단면"
            case .waist: label = waistUsesCircumference ? "허리둘레" : "허리단면"
            default: label = kind.title
            }
            return ParsedMeasurement(
                value: value,
                measurementCode: code,
                displayKind: kind.displayKind,
                methodSource: "manual_product_size_entry",
                methodProfile: "transcribed_size_chart",
                inputSource: .transcribedSizeChart,
                mappingVersion: "manual_product_size_entry_v1",
                rawLabel: label,
                rawValueText: value.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(value))
                    : String(value),
                evidenceLevel: .officialText,
                semanticStatus: .mapped
            ).makeRecord(productSize: productSize)
        }
    }

    private func manualMeasurementCode(
        for kind: MeasurementKind,
        category: ClothingCategory
    ) -> MeasurementCode? {
        switch kind {
        case .shoulder: return .shoulderWidthSeamToSeam
        case .chest: return chestUsesCircumference ? .chestCircumferenceGarment : .chestWidthPitToPit
        case .totalLength:
            return category.serviceGroup == .bottom ? .pantsOutseamWaistToHem : .bodyLengthBackNeckToHem
        case .sleeveLength: return .sleeveShoulderSeamToCuff
        case .waist: return waistUsesCircumference ? .waistCircumferenceGarment : .waistWidthEdgeToEdge
        case .hip: return .hipWidthAtWidest
        case .thigh: return .thighWidthCrotchToOuter
        case .rise: return .riseCrotchToWaistFront
        case .hem: return .hemWidthEdgeToEdge
        case .footLength: return .footLengthHeelToToe
        case .underBust: return .underBustWidthEdgeToEdge
        }
    }

    func value(for kind: MeasurementKind) -> String {
        switch kind {
        case .shoulder: return shoulder
        case .chest: return chest
        case .totalLength: return totalLength
        case .sleeveLength: return sleeveLength
        case .waist: return waist
        case .hip: return hip
        case .thigh: return thigh
        case .rise: return rise
        case .hem: return hem
        case .footLength: return footLength
        case .underBust: return underBust
        }
    }

    private func numericValue(for kind: MeasurementKind) -> Double {
        Double(value(for: kind).trimmed) ?? 0
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Double {
    var formText: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(self)
    }

    var extractedFormText: String {
        self > 0 ? formText : ""
    }
}
