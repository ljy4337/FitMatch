import Foundation
import Combine

final class AddClosetItemViewModel: ObservableObject {
    @Published var brand = ""
    @Published var productName = ""
    @Published var category: ClothingCategory = .top
    @Published var size = ""
    @Published var shoulder = ""
    @Published var chest = ""
    @Published var totalLength = ""
    @Published var sleeveLength = ""
    @Published var fitMemo = ""
    @Published var satisfaction = 4

    init(item: ClosetItem? = nil) {
        guard let item else {
            return
        }

        brand = item.brand
        productName = item.productName
        category = item.category
        size = item.size
        shoulder = item.measurements.shoulder.formText
        chest = item.measurements.chest.formText
        totalLength = item.measurements.totalLength.formText
        sleeveLength = item.measurements.sleeveLength.formText
        fitMemo = item.fitMemo
        satisfaction = item.satisfaction
    }

    var canSave: Bool {
        !brand.trimmed.isEmpty
            && !productName.trimmed.isEmpty
            && !size.trimmed.isEmpty
            && measurements != nil
    }

    var measurements: GarmentMeasurements? {
        guard
            let shoulderValue = Double(shoulder),
            let chestValue = Double(chest),
            let totalLengthValue = Double(totalLength),
            let sleeveLengthValue = Double(sleeveLength)
        else {
            return nil
        }

        return GarmentMeasurements(
            shoulder: shoulderValue,
            chest: chestValue,
            totalLength: totalLengthValue,
            sleeveLength: sleeveLengthValue
        )
    }

    func makeClosetItem() -> ClosetItem? {
        guard let measurements else {
            return nil
        }

        return ClosetItem(
            brand: brand.trimmed,
            productName: productName.trimmed,
            category: category,
            size: size.trimmed,
            measurements: measurements,
            fitMemo: fitMemo.trimmed,
            satisfaction: satisfaction
        )
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
