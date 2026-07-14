import Foundation
import SwiftData

@Model
final class UserFit {
    @Attribute(.unique)
    var id: UUID
    var sourceTypeRawValue: String = ProductSourceType.manual.rawValue
    var sourceName: String = "직접 입력"
    var sourceCategoryPath: String?
    var sourceCategoryDepth1: String?
    var sourceCategoryDepth2: String?
    var sourceCategoryDepth3: String?
    var sourceCategoryDepth4: String?
    var brandName: String
    var genderRawValue: String = UserGender.unisex.rawValue
    var productName: String
    var categoryRawValue: String
    var detailCategoryRawValue: String = ClosetDetailCategory.other.rawValue
    var sizeName: String
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
    var fitMemo: String
    var fitPreferenceRawValue: String = FitPreference.regular.rawValue
    var satisfaction: Int
    var isRepresentative: Bool = false
    var createdAt: Date
    var updatedAt: Date

    var sourceProduct: Product?
    var sourceProductSize: ProductSize?

    init(
        id: UUID = UUID(),
        sourceType: ProductSourceType = .manual,
        sourceName: String = "직접 입력",
        sourceCategoryPath: String? = nil,
        sourceCategoryDepth1: String? = nil,
        sourceCategoryDepth2: String? = nil,
        sourceCategoryDepth3: String? = nil,
        sourceCategoryDepth4: String? = nil,
        brandName: String,
        gender: UserGender = .unisex,
        productName: String,
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory = .other,
        sizeName: String,
        measurements: GarmentMeasurements,
        fitMemo: String,
        fitPreference: FitPreference = .regular,
        satisfaction: Int,
        isRepresentative: Bool = false,
        sourceProduct: Product? = nil,
        sourceProductSize: ProductSize? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceTypeRawValue = sourceType.rawValue
        self.sourceName = sourceName
        self.sourceCategoryPath = sourceCategoryPath ?? sourceProduct?.sourceCategoryPath
        self.sourceCategoryDepth1 = sourceCategoryDepth1 ?? sourceProduct?.sourceCategoryDepth1
        self.sourceCategoryDepth2 = sourceCategoryDepth2 ?? sourceProduct?.sourceCategoryDepth2
        self.sourceCategoryDepth3 = sourceCategoryDepth3 ?? sourceProduct?.sourceCategoryDepth3
        self.sourceCategoryDepth4 = sourceCategoryDepth4 ?? sourceProduct?.sourceCategoryDepth4
        self.brandName = brandName
        self.genderRawValue = gender.rawValue
        self.productName = productName
        self.categoryRawValue = category.rawValue
        self.detailCategoryRawValue = detailCategory.rawValue
        self.sizeName = sizeName
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
        self.fitMemo = fitMemo
        self.fitPreferenceRawValue = fitPreference.rawValue
        self.satisfaction = satisfaction
        self.isRepresentative = isRepresentative
        self.sourceProduct = sourceProduct
        self.sourceProductSize = sourceProductSize
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var category: ClothingCategory {
        get { ClothingCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var sourceType: ProductSourceType {
        get { ProductSourceType(rawValue: sourceTypeRawValue) ?? .manual }
        set { sourceTypeRawValue = newValue.rawValue }
    }

    var gender: UserGender {
        get { UserGender(rawValue: genderRawValue) ?? .unisex }
        set { genderRawValue = newValue.rawValue }
    }

    var detailCategory: ClosetDetailCategory {
        get { ClosetDetailCategory(rawValue: detailCategoryRawValue) ?? .other }
        set { detailCategoryRawValue = newValue.rawValue }
    }

    var fitPreference: FitPreference {
        get { FitPreference(rawValue: fitPreferenceRawValue) ?? .regular }
        set { fitPreferenceRawValue = newValue.rawValue }
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

    var displayName: String {
        "\(brandName) \(productName)"
    }

    var sourceCategoryNameForMatching: String {
        let value = (sourceCategoryDepth1 ?? sourceProduct?.sourceCategoryDepth1 ?? sourceProduct?.categoryDepth1Name)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? category.rawValue : value
    }

    var sourceDetailCategoryNameForDisplay: String {
        let value = (sourceCategoryDepth2 ?? sourceProduct?.sourceCategoryDepth2 ?? sourceProduct?.categoryDepth2Name)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? detailCategory.rawValue : value
    }

    var sourceCategoryDisplayText: String {
        if let sourceCategoryPath,
           !sourceCategoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sourceCategoryPath
        }
        return sourceProduct?.sourceCategoryDisplayText ?? "\(sourceCategoryNameForMatching) / \(sourceDetailCategoryNameForDisplay)"
    }
}
