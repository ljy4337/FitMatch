import Foundation
import SwiftData

@Model
final class UserFit {
    @Attribute(.unique)
    var id: UUID
    var sourceTypeRawValue: String = ProductSourceType.manual.rawValue
    var sourceName: String = "직접 입력"
    var sourcePlatformCode: String?
    var sourceCategoryPath: String?
    var sourceCategoryDepth1: String?
    var sourceCategoryDepth2: String?
    var sourceCategoryDepth3: String?
    var sourceCategoryDepth4: String?
    var brandName: String
    var genderRawValue: String = UserGender.unisex.rawValue
    var genderCode: String?
    var productName: String
    var categoryRawValue: String
    var detailCategoryRawValue: String = ClosetDetailCategory.other.rawValue
    var categoryCode: String?
    var detailCategoryCode: String?
    var normalizedProductTypeCode: String?
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

    var measurementSchemaVersion: Int = 0
    var measurementInputSourceRawValue: String = MeasurementInputSource.migratedLegacy.rawValue
    var measurementMigrationVersion: Int = 0
    var measurementMigrationStatusRawValue: String = MeasurementMigrationStatus.notStarted.rawValue
    var measurementMigrationErrorCode: String?

    var sourceProduct: Product?
    var sourceProductSize: ProductSize?

    @Relationship(deleteRule: .cascade, inverse: \GarmentMeasurementRecord.userFit)
    var measurementRecords: [GarmentMeasurementRecord] = []

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
        self.sourcePlatformCode = FitMatchTaxonomyProvider.shared.sourcePlatformCode(
            sourceName: sourceName,
            sourceURLString: sourceProduct?.sourceURLString
        )
        self.sourceCategoryPath = sourceCategoryPath ?? sourceProduct?.sourceCategoryPath
        self.sourceCategoryDepth1 = sourceCategoryDepth1 ?? sourceProduct?.sourceCategoryDepth1
        self.sourceCategoryDepth2 = sourceCategoryDepth2 ?? sourceProduct?.sourceCategoryDepth2
        self.sourceCategoryDepth3 = sourceCategoryDepth3 ?? sourceProduct?.sourceCategoryDepth3
        self.sourceCategoryDepth4 = sourceCategoryDepth4 ?? sourceProduct?.sourceCategoryDepth4
        self.brandName = brandName
        self.genderRawValue = gender.rawValue
        self.genderCode = gender.taxonomyCode
        self.productName = productName
        self.categoryRawValue = category.rawValue
        self.detailCategoryRawValue = detailCategory.rawValue
        self.categoryCode = category.taxonomyCode
        self.detailCategoryCode = FitMatchTaxonomyProvider.shared.detailCode(
            for: detailCategory.rawValue,
            categoryCode: category.taxonomyCode
        )
        self.normalizedProductTypeCode = FitMatchTaxonomyProvider.shared.normalizedProductTypeCode(
            sourceCategoryPath: sourceCategoryPath ?? sourceProduct?.sourceCategoryPath,
            categoryCode: category.taxonomyCode
        )
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
        set {
            categoryRawValue = newValue.rawValue
            categoryCode = newValue.taxonomyCode
        }
    }

    var sourceType: ProductSourceType {
        get { ProductSourceType(rawValue: sourceTypeRawValue) ?? .manual }
        set { sourceTypeRawValue = newValue.rawValue }
    }

    var measurementMigrationStatus: MeasurementMigrationStatus {
        get { MeasurementMigrationStatus(rawValue: measurementMigrationStatusRawValue) ?? .notStarted }
        set { measurementMigrationStatusRawValue = newValue.rawValue }
    }

    var gender: UserGender {
        get { UserGender(rawValue: genderRawValue) ?? .unisex }
        set {
            genderRawValue = newValue.rawValue
            genderCode = newValue.taxonomyCode
        }
    }

    var detailCategory: ClosetDetailCategory {
        get { ClosetDetailCategory(rawValue: detailCategoryRawValue) ?? .other }
        set {
            detailCategoryRawValue = newValue.rawValue
            if let resolvedCategoryCode {
                detailCategoryCode = FitMatchTaxonomyProvider.shared.detailCode(
                    for: newValue.rawValue,
                    categoryCode: resolvedCategoryCode
                )
            }
        }
    }

    var resolvedGenderCode: String {
        genderCode ?? FitMatchTaxonomyProvider.shared.genderCode(for: genderRawValue) ?? "unknown"
    }

    var resolvedCategoryCode: String? {
        categoryCode ?? FitMatchTaxonomyProvider.shared.categoryCode(for: categoryRawValue)
    }

    var resolvedDetailCategoryCode: String? {
        if let detailCategoryCode { return detailCategoryCode }
        guard let resolvedCategoryCode else { return nil }
        return FitMatchTaxonomyProvider.shared.detailCode(for: detailCategoryRawValue, categoryCode: resolvedCategoryCode)
    }

    var resolvedNormalizedProductTypeCode: String? {
        normalizedProductTypeCode ?? FitMatchTaxonomyProvider.shared.normalizedProductTypeCode(
            sourceCategoryPath: sourceCategoryPath ?? sourceProduct?.sourceCategoryPath,
            categoryCode: resolvedCategoryCode
        )
    }

    var taxonomyDisplayMetadata: String {
        let provider = FitMatchTaxonomyProvider.shared
        let genderName = provider.displayName(forGender: resolvedGenderCode) ?? gender.rawValue
        let categoryName = resolvedCategoryCode.flatMap(provider.displayName(forCategory:)) ?? category.rawValue
        let detailName = resolvedCategoryCode.flatMap { categoryCode in
            resolvedDetailCategoryCode.flatMap { provider.displayName(forDetail: $0, categoryCode: categoryCode) }
        } ?? detailCategory.rawValue
        return "\(genderName) / \(categoryName) / \(detailName) / \(sizeName)"
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

    func replaceMeasurementRecords(with sourceRecords: [GarmentMeasurementRecord]) {
        measurementRecords = sourceRecords.map { source in
            GarmentMeasurementRecord(
                value: source.value,
                unit: MeasurementUnit(rawValue: source.unitRawValue) ?? .centimeter,
                measurementCode: source.measurementCode,
                displayKind: source.displayKind ?? .unknown,
                methodSource: source.methodSource,
                methodProfile: source.methodProfile,
                inputSource: MeasurementInputSource(rawValue: source.inputSourceRawValue) ?? .importedSizeChart,
                standardVersion: source.standardVersion,
                mappingVersion: source.mappingVersion,
                rawCode: source.rawCode,
                rawLabel: source.rawLabel,
                rawInfo: source.rawInfo,
                rawValueText: source.rawValueText,
                evidenceLevel: MeasurementEvidenceLevel(rawValue: source.evidenceLevelRawValue) ?? .unknown,
                semanticStatus: source.semanticStatus,
                userFit: self
            )
        }
        guard !measurementRecords.isEmpty else {
            measurementSchemaVersion = 0
            measurementInputSourceRawValue = MeasurementInputSource.importedSizeChart.rawValue
            measurementMigrationVersion = 0
            measurementMigrationStatus = .notStarted
            measurementMigrationErrorCode = nil
            return
        }
        measurementSchemaVersion = 1
        measurementInputSourceRawValue = measurementRecords.first?.inputSourceRawValue
            ?? MeasurementInputSource.importedSizeChart.rawValue
        measurementMigrationVersion = MeasurementLegacyBackfillService.migrationVersion
        measurementMigrationStatus = .completed
        measurementMigrationErrorCode = nil
    }

    var sourceCategoryNameForMatching: String {
        let value = (sourceCategoryDepth1 ?? sourceProduct?.sourceCategoryDepth1 ?? sourceProduct?.categoryDepth1Name)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? category.rawValue : value
    }

    var sourceFamily: String? { sourceCategoryDepth1 ?? sourceProduct?.sourceFamily }
    var sourceDetail: String? { sourceCategoryDepth2 ?? sourceProduct?.sourceDetail }

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

    var isImportedFromURL: Bool {
        sourceProduct != nil
            || sourceProductSize != nil
            || !(sourceProduct?.sourceURLString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
