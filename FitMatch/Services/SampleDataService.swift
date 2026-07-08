import Foundation
import SwiftData

enum SampleDataService {
    static func seedIfNeeded(modelContext: ModelContext, brands: [Brand], userFits: [UserFit]) {
        guard brands.isEmpty, userFits.isEmpty else {
            return
        }

        let musinsa = Brand(name: "MUSINSA STANDARD", countryCode: "KR", websiteURL: "https://www.musinsa.com")
        let uniqlo = Brand(name: "UNIQLO", countryCode: "JP", websiteURL: "https://www.uniqlo.com")

        let relaxedSweatshirt = Product(
            name: "Relaxed Sweatshirt",
            brand: musinsa,
            category: .top,
            productCode: "SAMPLE-MUSINSA-SWT",
            source: .sample,
            notes: "샘플 데이터"
        )
        relaxedSweatshirt.sizes = [
            ProductSize(name: "M", measurements: GarmentMeasurements(shoulder: 52, chest: 58, totalLength: 68, sleeveLength: 60), displayOrder: 0, product: relaxedSweatshirt),
            ProductSize(name: "L", measurements: GarmentMeasurements(shoulder: 54, chest: 61, totalLength: 70, sleeveLength: 61), displayOrder: 1, product: relaxedSweatshirt),
            ProductSize(name: "XL", measurements: GarmentMeasurements(shoulder: 56, chest: 64, totalLength: 72, sleeveLength: 62), displayOrder: 2, product: relaxedSweatshirt)
        ]

        let oxfordShirt = Product(
            name: "Oxford Regular Shirt",
            brand: uniqlo,
            category: .shirt,
            productCode: "SAMPLE-UNIQLO-OXF",
            source: .sample,
            notes: "샘플 데이터"
        )
        oxfordShirt.sizes = [
            ProductSize(name: "M", measurements: GarmentMeasurements(shoulder: 46, chest: 55, totalLength: 73, sleeveLength: 61), displayOrder: 0, product: oxfordShirt),
            ProductSize(name: "L", measurements: GarmentMeasurements(shoulder: 48, chest: 58, totalLength: 75, sleeveLength: 62), displayOrder: 1, product: oxfordShirt),
            ProductSize(name: "XL", measurements: GarmentMeasurements(shoulder: 50, chest: 61, totalLength: 77, sleeveLength: 63), displayOrder: 2, product: oxfordShirt)
        ]

        musinsa.products = [relaxedSweatshirt]
        uniqlo.products = [oxfordShirt]

        let favoriteHoodie = UserFit(
            brandName: "MUSINSA STANDARD",
            productName: "Favorite Hoodie",
            category: .top,
            sizeName: "L",
            measurements: GarmentMeasurements(shoulder: 54, chest: 60, totalLength: 70, sleeveLength: 61),
            fitMemo: "어깨와 가슴이 여유 있고 총장이 적당함",
            satisfaction: 5
        )

        let dailyShirt = UserFit(
            brandName: "UNIQLO",
            productName: "Daily Oxford Shirt",
            category: .shirt,
            sizeName: "L",
            measurements: GarmentMeasurements(shoulder: 48, chest: 57, totalLength: 75, sleeveLength: 62),
            fitMemo: "정핏에 가까운 셔츠 기준",
            satisfaction: 4
        )

        modelContext.insert(musinsa)
        modelContext.insert(uniqlo)
        modelContext.insert(favoriteHoodie)
        modelContext.insert(dailyShirt)
    }
}
