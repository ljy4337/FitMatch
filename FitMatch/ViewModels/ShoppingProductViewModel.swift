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
    @Published var hasLoadedProductInfo = false

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
        isLoadingProductInfo = true
        defer { isLoadingProductInfo = false }

        do {
            let parsedProduct = try await parserService.parse(urlString: productURL)
            apply(parsedProduct)
            return true
        } catch let partialError as ProductURLParserPartialError {
            apply(partialError.productInfo)
            errorMessage = partialError.errorDescription
            return false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "상품 정보를 불러오지 못했습니다."
            return false
        }
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
            errorMessage = "비교할 수 있는 사이즈 정보가 없습니다."
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
            errorMessage = "비교할 수 있는 사이즈 정보가 없습니다."
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
            sourceURLString: productCanonicalURLString ?? (productURL.trimmed.isEmpty ? nil : productURL.trimmed),
            imageURLString: productImageURLString,
            sourceType: sourceType,
            sourceName: resolvedSourceName,
            sizes: validOptions
        )
        validOptions.forEach { $0.product = product }
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
        parserNotice = parsedProduct.parserNotice
        hasLoadedProductInfo = true
        print("[ShoppingProductViewModel] productName: \(productName)")
        print("[ShoppingProductViewModel] brandName: \(brand)")
        print("[ShoppingProductViewModel] sourceType: \(sourceType.displayName)")
        print("[ShoppingProductViewModel] sourceName: \(sourceName)")
        print("[ShoppingProductViewModel] category: \(category.rawValue)")
        print("[ShoppingProductViewModel] detailCategory: \(detailCategory.rawValue)")
        print("[ShoppingProductViewModel] imageURL: \(productImageURLString ?? "nil")")
        print("[ShoppingProductViewModel] sizeCount: \(parsedProduct.sizes.count)")
        guard !parsedProduct.sizes.isEmpty else {
            sizeOptions = [ClothingSizeForm()]
            return
        }

        sizeOptions = parsedProduct.sizes.enumerated().map { index, size in
            ClothingSizeForm(
                sizeName: size.name,
                shoulder: size.measurements.shoulder.extractedFormText,
                chest: size.measurements.chest.extractedFormText,
                totalLength: size.measurements.totalLength.extractedFormText,
                sleeveLength: size.measurements.sleeveLength.extractedFormText,
                waist: size.measurements.waist.extractedFormText,
                hip: size.measurements.hip.extractedFormText,
                thigh: size.measurements.thigh.extractedFormText,
                rise: size.measurements.rise.extractedFormText,
                hem: size.measurements.hem.extractedFormText,
                footLength: size.measurements.footLength.extractedFormText,
                underBust: size.measurements.underBust.extractedFormText,
                displayOrder: index
            )
        }
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
    var displayOrder = 0

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
        guard validMeasurementCount >= min(2, measurementKinds.count) else {
            return nil
        }

        return ProductSize(
            name: sizeName.trimmed,
            measurements: GarmentMeasurements(
                shoulder: numericValue(for: .shoulder),
                chest: numericValue(for: .chest),
                totalLength: numericValue(for: .totalLength),
                sleeveLength: numericValue(for: .sleeveLength),
                waist: numericValue(for: .waist),
                hip: numericValue(for: .hip),
                thigh: numericValue(for: .thigh),
                rise: numericValue(for: .rise),
                hem: numericValue(for: .hem),
                footLength: numericValue(for: .footLength),
                underBust: numericValue(for: .underBust)
            ),
            displayOrder: displayOrder
        )
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
