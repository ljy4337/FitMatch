import Foundation
import Combine

final class AddClosetItemViewModel: ObservableObject {
    @Published var sourceType: ProductSourceType = .manual
    @Published var sourceName = "직접 입력"
    @Published var brand = ""
    @Published var usesCustomBrand = true
    @Published var gender: UserGender = .men
    @Published var productName = ""
    @Published var category: ClothingCategory = .top
    @Published var detailCategory: ClosetDetailCategory = .shortSleeve
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
            }
            if let prefillDetailCategory {
                detailCategory = prefillDetailCategory
            }
            if let prefillGender {
                gender = prefillGender == .unisex ? .men : prefillGender
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
        gender = item.gender == .unisex ? .men : item.gender
        productName = item.productName
        category = item.category
        detailCategory = item.detailCategory
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
        fitMemo = item.fitMemo
        fitPreference = item.fitPreference
        satisfaction = item.satisfaction
        isRepresentative = item.isRepresentative
    }

    var canSave: Bool {
        !brand.trimmed.isEmpty
            && !productName.trimmed.isEmpty
            && measurements != nil
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

    private func value(for kind: MeasurementKind) -> String {
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

        return UserFit(
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
