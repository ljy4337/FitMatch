import Foundation
import SwiftData

enum SampleDataService {
    static func removeLegacySamples(
        modelContext: ModelContext,
        products: [Product],
        userFits: [UserFit],
        histories: [RecommendationHistory]
    ) {
        let sampleProductCodes = Set(["SAMPLE-MUSINSA-SWT", "SAMPLE-UNIQLO-OXF"])
        let sampleUserFitKeys = Set([
            "MUSINSA STANDARD|Favorite Hoodie",
            "UNIQLO|Daily Oxford Shirt"
        ])

        let sampleUserFitIDs = Set(
            userFits
                .filter { sampleUserFitKeys.contains("\($0.brandName)|\($0.productName)") }
                .map(\.id)
        )

        histories
            .filter { sampleUserFitIDs.contains($0.userFit.id) }
            .forEach { modelContext.delete($0) }

        products
            .filter { product in
                guard let productCode = product.productCode else {
                    return false
                }
                return sampleProductCodes.contains(productCode)
            }
            .forEach { modelContext.delete($0) }

        userFits
            .filter { sampleUserFitKeys.contains("\($0.brandName)|\($0.productName)") }
            .forEach { modelContext.delete($0) }

        do {
            try modelContext.save()
        } catch {
            print("[SampleDataService] legacy sample cleanup failed: \(error.localizedDescription)")
        }
    }
}
