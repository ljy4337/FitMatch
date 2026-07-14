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
    var imageURLString: String?
    var styleNo: String?
    var englishName: String?
    var brandCode: String?
    var brandEnglishName: String?
    var brandLogoImageURLString: String?
    var brandNationName: String?
    var sourceCategoryPath: String?
    var sourceCategoryDepth1: String?
    var sourceCategoryDepth2: String?
    var sourceCategoryDepth3: String?
    var sourceCategoryDepth4: String?
    var baseCategoryFullPath: String?
    var categoryDepth1Code: String?
    var categoryDepth1Name: String?
    var categoryDepth2Code: String?
    var categoryDepth2Name: String?
    var categoryDepth3Code: String?
    var categoryDepth3Name: String?
    var categoryDepth4Code: String?
    var categoryDepth4Name: String?
    var sizeType: String?
    var genderCodes: String = ""
    var labelNames: String = ""
    var imageURLStrings: String = ""
    var normalPrice: Int?
    var salePrice: Int?
    var finalPrice: Int?
    var currencyCode: String?
    var discountRate: Double?
    var isSale: Bool = false
    var isOutOfStock: Bool = false
    var stockStatusRawValue: String?
    var isRestock: Bool = false
    var isSoonOutOfStock: Bool = false
    var isLimitedQuantity: Bool = false
    var reviewCount: Int?
    var reviewSatisfactionScore: Double?
    var seasonYear: String?
    var season: String?
    var checkedColorName: String?
    var checkedSizeName: String?
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
        imageURLString: String? = nil,
        metadata: ProductMetadata = ProductMetadata(),
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
        self.imageURLString = imageURLString
        self.styleNo = metadata.styleNo
        self.englishName = metadata.englishName
        self.brandCode = metadata.brandCode
        self.brandEnglishName = metadata.brandEnglishName
        self.brandLogoImageURLString = metadata.brandLogoImageURLString
        self.brandNationName = metadata.brandNationName
        self.sourceCategoryPath = metadata.sourceCategoryPath ?? metadata.baseCategoryFullPath
        self.sourceCategoryDepth1 = metadata.sourceCategoryDepth1 ?? metadata.categoryDepth1Name
        self.sourceCategoryDepth2 = metadata.sourceCategoryDepth2 ?? metadata.categoryDepth2Name
        self.sourceCategoryDepth3 = metadata.sourceCategoryDepth3 ?? metadata.categoryDepth3Name
        self.sourceCategoryDepth4 = metadata.sourceCategoryDepth4 ?? metadata.categoryDepth4Name
        self.baseCategoryFullPath = metadata.baseCategoryFullPath
        self.categoryDepth1Code = metadata.categoryDepth1Code
        self.categoryDepth1Name = metadata.categoryDepth1Name
        self.categoryDepth2Code = metadata.categoryDepth2Code
        self.categoryDepth2Name = metadata.categoryDepth2Name
        self.categoryDepth3Code = metadata.categoryDepth3Code
        self.categoryDepth3Name = metadata.categoryDepth3Name
        self.categoryDepth4Code = metadata.categoryDepth4Code
        self.categoryDepth4Name = metadata.categoryDepth4Name
        self.sizeType = metadata.sizeType
        self.genderCodes = metadata.genderCodes.joined(separator: ",")
        self.labelNames = metadata.labelNames.joined(separator: ",")
        self.imageURLStrings = metadata.imageURLStrings.joined(separator: "\n")
        self.normalPrice = metadata.normalPrice
        self.salePrice = metadata.salePrice
        self.finalPrice = metadata.finalPrice
        self.currencyCode = metadata.currencyCode
        self.discountRate = metadata.discountRate
        self.isSale = metadata.isSale
        self.isOutOfStock = metadata.isOutOfStock
        self.stockStatusRawValue = metadata.stockStatusRawValue
        self.isRestock = metadata.isRestock
        self.isSoonOutOfStock = metadata.isSoonOutOfStock
        self.isLimitedQuantity = metadata.isLimitedQuantity
        self.reviewCount = metadata.reviewCount
        self.reviewSatisfactionScore = metadata.reviewSatisfactionScore
        self.seasonYear = metadata.seasonYear
        self.season = metadata.season
        self.checkedColorName = metadata.checkedColorName
        self.checkedSizeName = metadata.checkedSizeName
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

    var sourceCategoryNameForMatching: String {
        let value = (sourceCategoryDepth1 ?? categoryDepth1Name)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? category.rawValue : value
    }

    var sourceDetailCategoryNameForDisplay: String {
        let value = (sourceCategoryDepth2 ?? categoryDepth2Name)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "" : value
    }

    var sourceCategoryDisplayText: String {
        if let sourceCategoryPath,
           !sourceCategoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sourceCategoryPath
        }

        if let baseCategoryFullPath,
           !baseCategoryFullPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return baseCategoryFullPath
        }

        let categoryName = sourceCategoryNameForMatching
        let detailName = sourceDetailCategoryNameForDisplay
        return detailName.isEmpty ? categoryName : "\(categoryName) / \(detailName)"
    }

    var productTargetGender: UserGender {
        UserGender.productTarget(from: genderCodes
            .split(separator: ",")
            .map(String.init))
    }

    var stockStatus: ProductStockStatus {
        ProductStockStatus(rawValue: stockStatusRawValue ?? "") ?? (isOutOfStock ? .outOfStock : .unknown)
    }

    var displayName: String {
        if let brandName = brand?.name, !brandName.isEmpty {
            return "\(brandName) \(name)"
        }

        return name
    }
}

enum ProductStockStatus: String, Codable, CaseIterable {
    case inStock = "재고 있음"
    case outOfStock = "품절"
    case unknown = "재고 확인 필요"
}
