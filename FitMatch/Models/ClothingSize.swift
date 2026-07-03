import Foundation
import SwiftData

@Model
final class ClothingSize {
    @Attribute(.unique)
    var id: UUID
    var name: String
    var shoulder: Double
    var chest: Double
    var totalLength: Double
    var sleeveLength: Double

    init(id: UUID = UUID(), name: String, measurements: GarmentMeasurements) {
        self.id = id
        self.name = name
        self.shoulder = measurements.shoulder
        self.chest = measurements.chest
        self.totalLength = measurements.totalLength
        self.sleeveLength = measurements.sleeveLength
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
}
