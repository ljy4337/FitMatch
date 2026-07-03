import Foundation
import SwiftData

@Model
final class ShoppingProduct {
    @Attribute(.unique)
    var id: UUID
    var brand: String
    var productName: String
    var categoryRawValue: String
    @Relationship(deleteRule: .cascade)
    var sizes: [ClothingSize]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        brand: String,
        productName: String,
        category: ClothingCategory,
        sizes: [ClothingSize],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.brand = brand
        self.productName = productName
        self.categoryRawValue = category.rawValue
        self.sizes = sizes
        self.createdAt = createdAt
    }

    var category: ClothingCategory {
        get { ClothingCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }
}
