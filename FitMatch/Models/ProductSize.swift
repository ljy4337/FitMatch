import Foundation
import SwiftData

@Model
final class ProductSize {
    @Attribute(.unique)
    var id: UUID
    var name: String
    var shoulder: Double
    var chest: Double
    var totalLength: Double
    var sleeveLength: Double
    var waist: Double = 0
    var hip: Double = 0
    var thigh: Double = 0
    var rise: Double = 0
    var hem: Double = 0
    var footLength: Double = 0
    var underBust: Double = 0
    var displayOrder: Int
    var createdAt: Date
    var updatedAt: Date

    var product: Product?

    init(
        id: UUID = UUID(),
        name: String,
        measurements: GarmentMeasurements,
        displayOrder: Int = 0,
        product: Product? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.shoulder = measurements.shoulder
        self.chest = measurements.chest
        self.totalLength = measurements.totalLength
        self.sleeveLength = measurements.sleeveLength
        self.waist = measurements.waist
        self.hip = measurements.hip
        self.thigh = measurements.thigh
        self.rise = measurements.rise
        self.hem = measurements.hem
        self.footLength = measurements.footLength
        self.underBust = measurements.underBust
        self.displayOrder = displayOrder
        self.product = product
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var measurements: GarmentMeasurements {
        get {
            GarmentMeasurements(
                shoulder: shoulder,
                chest: chest,
                totalLength: totalLength,
                sleeveLength: sleeveLength,
                waist: waist,
                hip: hip,
                thigh: thigh,
                rise: rise,
                hem: hem,
                footLength: footLength,
                underBust: underBust
            )
        }
        set {
            shoulder = newValue.shoulder
            chest = newValue.chest
            totalLength = newValue.totalLength
            sleeveLength = newValue.sleeveLength
            waist = newValue.waist
            hip = newValue.hip
            thigh = newValue.thigh
            rise = newValue.rise
            hem = newValue.hem
            footLength = newValue.footLength
            underBust = newValue.underBust
            updatedAt = Date()
        }
    }
}
