import Foundation
import Combine

final class ShoppingProductViewModel: ObservableObject {
    @Published var brand = ""
    @Published var productName = ""
    @Published var category: ClothingCategory = .top
    @Published var sizeOptions: [ClothingSizeForm] = [
        ClothingSizeForm(sizeName: "S"),
        ClothingSizeForm(sizeName: "M"),
        ClothingSizeForm(sizeName: "L")
    ]
    @Published var recommendation: RecommendationRecord?
    @Published var errorMessage: String?

    private let recommendationService: RecommendationService

    init(recommendationService: RecommendationService = RecommendationService()) {
        self.recommendationService = recommendationService
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

    @discardableResult
    func calculateRecommendation(baselineFits: [BaselineFit]) -> RecommendationRecord? {
        errorMessage = nil

        guard !baselineFits.isEmpty else {
            errorMessage = "먼저 내 옷장에 기준 옷을 추가해 주세요."
            recommendation = nil
            return nil
        }

        guard let product = makeProduct() else {
            errorMessage = "상품명과 최소 1개 사이즈의 실측값을 입력해 주세요."
            recommendation = nil
            return nil
        }

        guard let record = recommendationService.recommend(product: product, baselineFits: baselineFits) else {
            errorMessage = "비교할 수 있는 사이즈 정보가 없습니다."
            recommendation = nil
            return nil
        }

        recommendation = record
        return record
    }

    private func makeProduct() -> ShoppingProduct? {
        let validOptions = sizeOptions.compactMap { $0.makeSizeOption() }
        guard !productName.trimmed.isEmpty, !validOptions.isEmpty else {
            return nil
        }

        return ShoppingProduct(
            brand: brand.trimmed,
            productName: productName.trimmed,
            category: category,
            sizes: validOptions
        )
    }

}

struct ClothingSizeForm: Identifiable, Equatable {
    var id = UUID()
    var sizeName = ""
    var shoulder = ""
    var chest = ""
    var totalLength = ""
    var sleeveLength = ""

    func makeSizeOption() -> ClothingSize? {
        guard
            !sizeName.trimmed.isEmpty,
            let shoulderValue = Double(shoulder),
            let chestValue = Double(chest),
            let totalLengthValue = Double(totalLength),
            let sleeveLengthValue = Double(sleeveLength)
        else {
            return nil
        }

        return ClothingSize(
            name: sizeName.trimmed,
            measurements: GarmentMeasurements(
                shoulder: shoulderValue,
                chest: chestValue,
                totalLength: totalLengthValue,
                sleeveLength: sleeveLengthValue
            )
        )
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
