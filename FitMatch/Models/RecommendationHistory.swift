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
    var stockStatusRawValue: String?
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
        self.stockStatusRawValue = product.stockStatus.rawValue
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
}
