import Foundation
import SwiftData

@Model
final class RecommendationRecord {
    @Attribute(.unique)
    var id: UUID
    var shoppingProduct: ShoppingProduct
    var recommendedSize: ClothingSize
    var baselineFit: BaselineFit
    var totalDifference: Double
    var shoulderDifference: Double
    var chestDifference: Double
    var totalLengthDifference: Double
    var sleeveLengthDifference: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        shoppingProduct: ShoppingProduct,
        recommendedSize: ClothingSize,
        baselineFit: BaselineFit,
        totalDifference: Double,
        measurementDifferences: GarmentMeasurements,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.shoppingProduct = shoppingProduct
        self.recommendedSize = recommendedSize
        self.baselineFit = baselineFit
        self.totalDifference = totalDifference
        self.shoulderDifference = measurementDifferences.shoulder
        self.chestDifference = measurementDifferences.chest
        self.totalLengthDifference = measurementDifferences.totalLength
        self.sleeveLengthDifference = measurementDifferences.sleeveLength
        self.createdAt = createdAt
    }

    var measurementDifferences: GarmentMeasurements {
        get {
            GarmentMeasurements(
                shoulder: shoulderDifference,
                chest: chestDifference,
                totalLength: totalLengthDifference,
                sleeveLength: sleeveLengthDifference
            )
        }
        set {
            shoulderDifference = newValue.shoulder
            chestDifference = newValue.chest
            totalLengthDifference = newValue.totalLength
            sleeveLengthDifference = newValue.sleeveLength
        }
    }

    var reasonText: String {
        "내 옷장에 있는 \(baselineFit.displayName)와 가장 비슷한 핏입니다."
    }
}
