import Foundation
import SwiftData

@Model
final class BaselineFit {
    @Attribute(.unique)
    var id: UUID
    var sourceClosetItemID: UUID?
    var brand: String
    var productName: String
    var categoryRawValue: String
    var size: String
    var shoulder: Double
    var chest: Double
    var totalLength: Double
    var sleeveLength: Double
    var fitMemo: String
    var satisfaction: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sourceClosetItemID: UUID? = nil,
        brand: String,
        productName: String,
        category: ClothingCategory,
        size: String,
        measurements: GarmentMeasurements,
        fitMemo: String,
        satisfaction: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceClosetItemID = sourceClosetItemID
        self.brand = brand
        self.productName = productName
        self.categoryRawValue = category.rawValue
        self.size = size
        self.shoulder = measurements.shoulder
        self.chest = measurements.chest
        self.totalLength = measurements.totalLength
        self.sleeveLength = measurements.sleeveLength
        self.fitMemo = fitMemo
        self.satisfaction = satisfaction
        self.createdAt = createdAt
    }

    var category: ClothingCategory {
        get { ClothingCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var measurements: GarmentMeasurements {
        get {
            GarmentMeasurements(
                shoulder: shoulder,
                chest: chest,
                totalLength: totalLength,
                sleeveLength: sleeveLength
            )
        }
        set {
            shoulder = newValue.shoulder
            chest = newValue.chest
            totalLength = newValue.totalLength
            sleeveLength = newValue.sleeveLength
        }
    }

    var displayName: String {
        "\(brand) \(productName)"
    }
}
