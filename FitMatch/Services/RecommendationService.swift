import Foundation

struct RecommendationService {
    func recommend(product: ShoppingProduct, baselineFits: [BaselineFit]) -> RecommendationRecord? {
        var bestRecord: RecommendationRecord?

        for size in product.sizes where !size.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for baselineFit in baselineFits {
                let differences = GarmentMeasurements(
                    shoulder: abs(size.measurements.shoulder - baselineFit.measurements.shoulder),
                    chest: abs(size.measurements.chest - baselineFit.measurements.chest),
                    totalLength: abs(size.measurements.totalLength - baselineFit.measurements.totalLength),
                    sleeveLength: abs(size.measurements.sleeveLength - baselineFit.measurements.sleeveLength)
                )
                let score = differences.shoulder + differences.chest + differences.totalLength + differences.sleeveLength

                let record = RecommendationRecord(
                    shoppingProduct: product,
                    recommendedSize: size,
                    baselineFit: baselineFit,
                    totalDifference: score,
                    measurementDifferences: differences
                )

                if bestRecord == nil || score < bestRecord!.totalDifference {
                    bestRecord = record
                }
            }
        }

        return bestRecord
    }
}
