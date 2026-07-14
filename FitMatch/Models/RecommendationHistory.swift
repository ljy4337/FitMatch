import Foundation
import SwiftData

@Model
final class RecommendationHistory {
    @Attribute(.unique)
    var id: UUID
    var totalDifference: Double
    var shoulderDifference: Double
    var chestDifference: Double
    var totalLengthDifference: Double
    var sleeveLengthDifference: Double
    var waistDifference: Double = 0
    var hipDifference: Double = 0
    var thighDifference: Double = 0
    var riseDifference: Double = 0
    var hemDifference: Double = 0
    var footLengthDifference: Double = 0
    var underBustDifference: Double = 0
    var recommendationScore: Int = 0
    var trueToSizeRecommendation: String = ""
    var oversizedRecommendation: String = ""
    var comparisonMethod: String = "같은 종류 기준 비교"
    var fallbackReason: String = ""
    var productDetailCategoryRawValue: String = ClosetDetailCategory.other.rawValue
    var normalPriceSnapshot: Int?
    var salePriceSnapshot: Int?
    var finalPriceSnapshot: Int?
    var currencyCodeSnapshot: String?
    var isSaleSnapshot: Bool = false
    var discountRateSnapshot: Double?
    var priceCheckedAt: Date?
    var stockStatusRawValue: String?
    var stockCheckedAt: Date?
    var selectedColorNameSnapshot: String?
    var selectedSizeNameSnapshot: String?
    var productSourceNameSnapshot: String?
    var productBrandNameSnapshot: String?
    var productNameSnapshot: String?
    var productImageURLStringSnapshot: String?
    var productURLStringSnapshot: String?
    var productCodeSnapshot: String?
    var productTargetGenderRawValueSnapshot: String?
    var sourceCategoryPathSnapshot: String?
    var reason: String
    var createdAt: Date

    var product: Product
    var recommendedSize: ProductSize
    var userFit: UserFit

    init(
        id: UUID = UUID(),
        product: Product,
        recommendedSize: ProductSize,
        userFit: UserFit,
        totalDifference: Double,
        measurementDifferences: GarmentMeasurements,
        recommendationScore: Int = 0,
        trueToSizeRecommendation: String = "",
        oversizedRecommendation: String = "",
        comparisonMethod: String = "같은 종류 기준 비교",
        fallbackReason: String = "",
        productDetailCategory: ClosetDetailCategory = .other,
        reason: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.product = product
        self.recommendedSize = recommendedSize
        self.userFit = userFit
        self.totalDifference = totalDifference
        self.shoulderDifference = measurementDifferences.shoulder
        self.chestDifference = measurementDifferences.chest
        self.totalLengthDifference = measurementDifferences.totalLength
        self.sleeveLengthDifference = measurementDifferences.sleeveLength
        self.waistDifference = measurementDifferences.waist
        self.hipDifference = measurementDifferences.hip
        self.thighDifference = measurementDifferences.thigh
        self.riseDifference = measurementDifferences.rise
        self.hemDifference = measurementDifferences.hem
        self.footLengthDifference = measurementDifferences.footLength
        self.underBustDifference = measurementDifferences.underBust
        self.recommendationScore = recommendationScore
        self.trueToSizeRecommendation = trueToSizeRecommendation
        self.oversizedRecommendation = oversizedRecommendation
        self.comparisonMethod = comparisonMethod
        self.fallbackReason = fallbackReason
        self.productDetailCategoryRawValue = productDetailCategory.rawValue
        self.normalPriceSnapshot = product.normalPrice
        self.salePriceSnapshot = product.salePrice
        self.finalPriceSnapshot = product.finalPrice
        self.currencyCodeSnapshot = product.currencyCode
        self.isSaleSnapshot = product.isSale
        self.discountRateSnapshot = product.discountRate
        self.priceCheckedAt = createdAt
        self.stockStatusRawValue = nil
        self.stockCheckedAt = nil
        self.selectedColorNameSnapshot = product.checkedColorName
        self.selectedSizeNameSnapshot = product.checkedSizeName ?? recommendedSize.name
        self.productSourceNameSnapshot = product.sourceDisplayName
        self.productBrandNameSnapshot = product.brand?.name
        self.productNameSnapshot = product.name
        self.productImageURLStringSnapshot = product.imageURLString
        self.productURLStringSnapshot = product.sourceURLString
        self.productCodeSnapshot = product.productCode
        self.productTargetGenderRawValueSnapshot = product.productTargetGender.rawValue
        self.sourceCategoryPathSnapshot = product.sourceCategoryDisplayText
        self.reason = reason ?? "내 옷장에 있는 \(userFit.displayName)와 가장 비슷한 핏입니다."
        self.createdAt = createdAt
    }

    var measurementDifferences: GarmentMeasurements {
        GarmentMeasurements(
            shoulder: shoulderDifference,
            chest: chestDifference,
            totalLength: totalLengthDifference,
            sleeveLength: sleeveLengthDifference,
            waist: waistDifference,
            hip: hipDifference,
            thigh: thighDifference,
            rise: riseDifference,
            hem: hemDifference,
            footLength: footLengthDifference,
            underBust: underBustDifference
        )
    }

    var productDetailCategory: ClosetDetailCategory {
        get { ClosetDetailCategory(rawValue: productDetailCategoryRawValue) ?? .other }
        set { productDetailCategoryRawValue = newValue.rawValue }
    }

    var displayComparisonMethod: String {
        switch comparisonMethod {
        case "전체 fallback 비교":
            return "유사한 옷 기준 비교"
        default:
            return comparisonMethod.replacingOccurrences(of: "fallback", with: "유사한 옷")
        }
    }

    var stockStatus: ProductStockStatus {
        ProductStockStatus(rawValue: stockStatusRawValue ?? "") ?? .unknown
    }

    var productSourceNameForDisplay: String {
        productSourceNameSnapshot ?? product.sourceDisplayName
    }

    var productBrandNameForDisplay: String {
        productBrandNameSnapshot ?? product.brand?.name ?? product.sourceDisplayName
    }

    var productNameForDisplay: String {
        productNameSnapshot ?? product.name
    }

    var productImageURLStringForDisplay: String? {
        productImageURLStringSnapshot ?? product.imageURLString
    }

    var sourceCategoryPathForDisplay: String {
        sourceCategoryPathSnapshot ?? product.sourceCategoryDisplayText
    }

    var optionSnapshotText: String? {
        let values = [
            selectedColorNameSnapshot.map { "색상 \($0)" },
            selectedSizeNameSnapshot.map { "옵션 \($0)" }
        ]
            .compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}
