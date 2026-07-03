import Foundation

struct GarmentMeasurements: Codable, Equatable, Hashable {
    var shoulder: Double
    var chest: Double
    var totalLength: Double
    var sleeveLength: Double

    var isEmpty: Bool {
        shoulder == 0 && chest == 0 && totalLength == 0 && sleeveLength == 0
    }

    func distance(to other: GarmentMeasurements) -> Double {
        abs(shoulder - other.shoulder)
            + abs(chest - other.chest)
            + abs(totalLength - other.totalLength)
            + abs(sleeveLength - other.sleeveLength)
    }
}
