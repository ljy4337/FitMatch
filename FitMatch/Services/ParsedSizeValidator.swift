import Foundation

enum ParsedSizeValidator {
    static func validSizes(
        _ sizes: [ParsedProductSize],
        category: ClothingCategory
    ) -> [ParsedProductSize] {
        let valid = sizes.filter { size in
            guard SizeTokenNormalizer.isValid(size.name)
                    || hasTrustedProviderMeasurements(size) else { return false }
            return size.measurementRecords.contains { measurement in
                isUsable(measurement, category: category)
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
            (SizeTokenNormalizer.isValid(size.name) || hasTrustedProviderMeasurements(size))
                && size.measurementRecords.contains {
                    isUsable($0, category: category)
                }
        }
    }

    private static func hasTrustedProviderMeasurements(_ size: ParsedProductSize) -> Bool {
        size.measurementRecords.contains { measurement in
            let methodSource = measurement.methodSource.lowercased()
            return measurement.inputSource == .importedSizeChart
                && (methodSource == "musinsa" || methodSource.hasPrefix("uniqlo"))
                && measurement.semanticStatus == .mapped
                && measurement.measurementCode != .unknown
                && measurement.measurementCode != .legacyUnknown
        }
    }

    private static func isUsable(
        _ measurement: ParsedMeasurement,
        category: ClothingCategory
    ) -> Bool {
        measurement.semanticStatus == .mapped
            && measurement.measurementCode != .unknown
            && measurement.measurementCode != .legacyUnknown
            && measurement.value.isFinite
            && measurement.value > 0
            && measurement.value <= maximumValue(for: category)
    }

    private static func maximumValue(for category: ClothingCategory) -> Double {
        category.serviceGroup == .shoes ? 400 : 300
    }
}
