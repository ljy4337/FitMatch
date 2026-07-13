import Foundation

struct ProductMetadata {
    var styleNo: String? = nil
    var englishName: String? = nil
    var brandCode: String? = nil
    var brandEnglishName: String? = nil
    var brandLogoImageURLString: String? = nil
    var brandNationName: String? = nil
    var baseCategoryFullPath: String? = nil
    var categoryDepth1Code: String? = nil
    var categoryDepth1Name: String? = nil
    var categoryDepth2Code: String? = nil
    var categoryDepth2Name: String? = nil
    var sizeType: String? = nil
    var genderCodes: [String] = []
    var labelNames: [String] = []
    var imageURLStrings: [String] = []
    var normalPrice: Int? = nil
    var salePrice: Int? = nil
    var finalPrice: Int? = nil
    var discountRate: Double? = nil
    var isSale: Bool = false
    var isOutOfStock: Bool = false
    var isRestock: Bool = false
    var isSoonOutOfStock: Bool = false
    var isLimitedQuantity: Bool = false
    var reviewCount: Int? = nil
    var reviewSatisfactionScore: Double? = nil
    var seasonYear: String? = nil
    var season: String? = nil
}
