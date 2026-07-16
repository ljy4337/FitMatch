import Foundation
import Combine

final class AddClosetItemViewModel: ObservableObject {
    @Published var sourceType: ProductSourceType = .manual
    @Published var sourceName = "직접 입력"
    @Published var brand = ""
    @Published var usesCustomBrand = true
    @Published var gender: UserGender = .men
    @Published var genderCode = "male"
    @Published var productName = ""
    @Published var category: ClothingCategory = .top
    @Published var categoryCode = "tops"
    @Published var detailCategory: ClosetDetailCategory = .shortSleeve
    @Published var detailCategoryCode = "short_sleeve"
    @Published var size = "기준"
    @Published var shoulder = ""
    @Published var chest = ""
    @Published var totalLength = ""
    @Published var sleeveLength = ""
    @Published var waist = ""
    @Published var hip = ""
    @Published var thigh = ""
    @Published var rise = ""
    @Published var hem = ""
    @Published var footLength = ""
    @Published var underBust = ""
    @Published var measurementEntrySource: MeasurementEntrySource?
    @Published var measurementSourceName = ""
    @Published var measurementSourceLabels: [MeasurementKind: String] = [:]
    @Published var musinsaSleeveMeasurementMethod: MusinsaSleeveMeasurementMethod = .unknown
    @Published var fitMemo = ""
    @Published var fitPreference: FitPreference = .regular
    @Published var satisfaction = 4
    @Published var isRepresentative = false

    init(
        item: UserFit? = nil,
        prefillCategory: ClothingCategory? = nil,
        prefillDetailCategory: ClosetDetailCategory? = nil,
        prefillGender: UserGender? = nil,
        prefillBrand: String? = nil,
        prefillProductName: String? = nil
    ) {
        guard let item else {
            if let prefillCategory {
                category = prefillCategory
                categoryCode = prefillCategory.taxonomyCode
            }
            if let prefillDetailCategory {
                detailCategory = prefillDetailCategory
                detailCategoryCode = FitMatchTaxonomyProvider.shared.detailCode(
                    for: prefillDetailCategory.rawValue,
                    categoryCode: categoryCode
                ) ?? detailCategoryCode
            }
            if let prefillGender {
                gender = prefillGender
                genderCode = prefillGender.taxonomyCode
            }
            if let prefillBrand, !prefillBrand.trimmed.isEmpty {
                brand = prefillBrand.trimmed
                usesCustomBrand = true
            }
            if let prefillProductName, !prefillProductName.trimmed.isEmpty {
                productName = prefillProductName.trimmed
            }
            return
        }

        sourceType = item.sourceType
        sourceName = item.sourceName
        brand = item.brandName
        usesCustomBrand = true
        gender = item.gender
        genderCode = item.resolvedGenderCode
        productName = item.productName
        category = item.category
        categoryCode = item.resolvedCategoryCode ?? item.category.taxonomyCode
        detailCategory = item.detailCategory
        detailCategoryCode = item.resolvedDetailCategoryCode ?? ""
        size = item.sizeName
        shoulder = item.measurements.shoulder.formText
        chest = item.measurements.chest.formText
        totalLength = item.measurements.totalLength.formText
        sleeveLength = item.measurements.sleeveLength.formText
        waist = item.measurements.waist.formText
        hip = item.measurements.hip.formText
        thigh = item.measurements.thigh.formText
        rise = item.measurements.rise.formText
        hem = item.measurements.hem.formText
        footLength = item.measurements.footLength.formText
        underBust = item.measurements.underBust.formText
        measurementEntrySource = MeasurementEntrySource.infer(from: item.measurementRecords)
        if let profile = item.measurementRecords.first?.methodProfile,
           profile.hasPrefix("other_size_chart_manual:") {
            measurementSourceName = String(profile.dropFirst("other_size_chart_manual:".count))
            measurementSourceLabels = Dictionary(uniqueKeysWithValues: item.measurementRecords.compactMap { record in
                guard let kind = record.displayKind, let rawLabel = record.rawLabel?.trimmed, !rawLabel.isEmpty else {
                    return nil
                }
                return (kind, rawLabel)
            })
        }
        musinsaSleeveMeasurementMethod = MusinsaSleeveMeasurementMethod.infer(from: item.measurementRecords)
        fitMemo = item.fitMemo
        fitPreference = item.fitPreference
        satisfaction = item.satisfaction
        isRepresentative = item.isRepresentative
    }

    var canSave: Bool {
        !brand.trimmed.isEmpty
            && !productName.trimmed.isEmpty
            && measurements != nil
            && (measurementKinds.isEmpty || measurementEntrySource != nil)
            && (measurementEntrySource != .otherSizeChart || !measurementSourceName.trimmed.isEmpty)
            && (measurementEntrySource != .otherSizeChart || hasAllRequiredSourceLabels)
    }

    var measurements: GarmentMeasurements? {
        var hasAtLeastOneMeasurement = measurementKinds.isEmpty

        for kind in measurementKinds {
            let rawValue = value(for: kind).trimmed
            guard !rawValue.isEmpty else {
                continue
            }

            guard let number = Double(rawValue), number > 0 else {
                return nil
            }

            hasAtLeastOneMeasurement = true
        }

        guard hasAtLeastOneMeasurement else {
            return nil
        }

        return GarmentMeasurements(
            shoulder: Double(shoulder) ?? 0,
            chest: Double(chest) ?? 0,
            totalLength: Double(totalLength) ?? 0,
            sleeveLength: Double(sleeveLength) ?? 0,
            waist: Double(waist) ?? 0,
            hip: Double(hip) ?? 0,
            thigh: Double(thigh) ?? 0,
            rise: Double(rise) ?? 0,
            hem: Double(hem) ?? 0,
            footLength: Double(footLength) ?? 0,
            underBust: Double(underBust) ?? 0
        )
    }

    var measurementKinds: [MeasurementKind] {
        category.measurementKinds(detailCategory: detailCategory, gender: gender)
    }

    func value(for kind: MeasurementKind) -> String {
        switch kind {
        case .shoulder: return shoulder
        case .chest: return chest
        case .totalLength: return totalLength
        case .sleeveLength: return sleeveLength
        case .waist: return waist
        case .hip: return hip
        case .thigh: return thigh
        case .rise: return rise
        case .hem: return hem
        case .footLength: return footLength
        case .underBust: return underBust
        }
    }

    func makeUserFit() -> UserFit? {
        guard let measurements else {
            return nil
        }

        let item = UserFit(
            sourceType: sourceType,
            sourceName: resolvedSourceName,
            brandName: brand.trimmed,
            gender: gender,
            productName: productName.trimmed,
            category: category,
            detailCategory: detailCategory,
            sizeName: resolvedSizeName,
            measurements: measurements,
            fitMemo: fitMemo.trimmed,
            fitPreference: fitPreference,
            satisfaction: satisfaction,
            isRepresentative: isRepresentative
        )
        item.genderCode = genderCode
        item.categoryCode = categoryCode
        item.detailCategoryCode = detailCategoryCode
        item.normalizedProductTypeCode = FitMatchTaxonomyProvider.shared.normalizedProductTypeCode(
            sourceCategoryPath: item.sourceCategoryPath,
            categoryCode: categoryCode
        )
        if let measurementEntrySource {
            let records = ManualMeasurementRecordFactory.records(
                source: measurementEntrySource,
                musinsaSleeveMethod: musinsaSleeveMeasurementMethod,
                measurements: measurements,
                rawValues: Dictionary(uniqueKeysWithValues: measurementKinds.map { ($0, value(for: $0).trimmed) }),
                rawLabels: measurementSourceLabels,
                kinds: measurementKinds,
                otherSourceName: measurementSourceName.trimmed,
                userFit: item
            )
            item.measurementRecords = records
            if !records.isEmpty {
                item.measurementSchemaVersion = 1
                item.measurementInputSourceRawValue = measurementEntrySource.inputSource.rawValue
                item.measurementMigrationVersion = MeasurementLegacyBackfillService.migrationVersion
                item.measurementMigrationStatus = .completed
                item.measurementMigrationErrorCode = nil
            }
        }
        return item
    }

    func measurementGuide(for kind: MeasurementKind) -> String {
        guard let measurementEntrySource else { return "먼저 실측 정보 출처를 선택해 주세요" }
        return ManualMeasurementRecordFactory.guide(for: kind, source: measurementEntrySource)
    }

    private var hasAllRequiredSourceLabels: Bool {
        measurementKinds.allSatisfy { kind in
            value(for: kind).trimmed.isEmpty || !(measurementSourceLabels[kind]?.trimmed.isEmpty ?? true)
        }
    }

    var resolvedSourceName: String {
        switch sourceType {
        case .officialStore:
            return sourceName.trimmed.isEmpty ? "\(brand.trimmed) 공식몰" : sourceName.trimmed
        case .marketplace:
            return sourceName.trimmed
        case .manual:
            return sourceName.trimmed.isEmpty ? "직접 입력" : sourceName.trimmed
        }
    }

    private var resolvedSizeName: String {
        let trimmedSize = size.trimmed
        return trimmedSize.isEmpty ? "기준" : trimmedSize
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Double {
    var formText: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(self)
    }
}
