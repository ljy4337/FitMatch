import Foundation

enum ParsedSizeValidator {
    static func validSizes(
        _ sizes: [ParsedProductSize],
        category: ClothingCategory
    ) -> [ParsedProductSize] {
        let valid = sizes.filter { size in
            guard SizeTokenNormalizer.isValid(size.name) else { return false }
            return size.measurementRecords.contains { measurement in
                measurement.semanticStatus == .mapped
                    && measurement.measurementCode != .unknown
                    && measurement.measurementCode != .legacyUnknown
                    && measurement.value.isFinite
                    && measurement.value > 0
                    && measurement.value <= maximumValue(for: category)
            }
        }

        guard category.serviceGroup != .shoes || valid.count >= 2 else { return [] }
        return valid
    }

    static func hasUsableMeasurements(
        _ sizes: [ParsedProductSize],
        category: ClothingCategory
    ) -> Bool {
        sizes.contains { size in
            SizeTokenNormalizer.isValid(size.name)
                && size.measurementRecords.contains {
                    $0.semanticStatus == .mapped
                        && $0.measurementCode != .unknown
                        && $0.measurementCode != .legacyUnknown
                        && $0.value.isFinite
                        && $0.value > 0
                        && $0.value <= maximumValue(for: category)
                }
        }
    }

    private static func maximumValue(for category: ClothingCategory) -> Double {
        category.serviceGroup == .shoes ? 400 : 300
    }
}
