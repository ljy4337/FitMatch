import Foundation
import SwiftData

enum ProductSource: String, CaseIterable, Codable, Hashable {
    case userInput = "사용자 입력"
    case sample = "샘플"
    case catalog = "카탈로그"
}

@Model
final class Product {
    @Attribute(.unique)
    var id: UUID
    var name: String
    var categoryRawValue: String
    var productCode: String?
    var sourceURLString: String?
    var sourceTypeRawValue: String = ProductSourceType.manual.rawValue
    var sourceName: String = "직접 입력"
    var sourceRawValue: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    var brand: Brand?

    @Relationship(deleteRule: .cascade, inverse: \ProductSize.product)
    var sizes: [ProductSize]

    init(
        id: UUID = UUID(),
        name: String,
        brand: Brand? = nil,
        category: ClothingCategory,
        productCode: String? = nil,
        sourceURLString: String? = nil,
        sourceType: ProductSourceType = .manual,
        sourceName: String = "직접 입력",
        source: ProductSource = .userInput,
        notes: String = "",
        sizes: [ProductSize] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.categoryRawValue = category.rawValue
        self.productCode = productCode
        self.sourceURLString = sourceURLString
        self.sourceTypeRawValue = sourceType.rawValue
        self.sourceName = sourceName
        self.sourceRawValue = source.rawValue
        self.notes = notes
        self.sizes = sizes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var category: ClothingCategory {
        get { ClothingCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var source: ProductSource {
        get { ProductSource(rawValue: sourceRawValue) ?? .userInput }
        set { sourceRawValue = newValue.rawValue }
    }

    var sourceType: ProductSourceType {
        get { ProductSourceType(rawValue: sourceTypeRawValue) ?? .manual }
        set { sourceTypeRawValue = newValue.rawValue }
    }

    var sourceDisplayName: String {
        sourceName.isEmpty ? sourceType.displayName : sourceName
    }

    var displayName: String {
        if let brandName = brand?.name, !brandName.isEmpty {
            return "\(brandName) \(name)"
        }

        return name
    }
}
