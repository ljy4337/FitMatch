import Foundation
import SwiftData

/// Retailer-garment measurement presence is intentionally narrower than
/// comparison readiness.  It answers only whether a parsed size table proved
/// at least one positive garment measurement; the server still owns
/// classification, canonicalization, and comparison policy.
enum FitMatchProductMeasurementPresence: Equatable, Sendable {
    /// The parser did not establish a complete actual-size-table result, so
    /// the client must keep the existing recovery/error flow instead of
    /// claiming the retailer has no measurements.
    case unknown
    /// The parser confirmed size rows but every row lacked a positive garment
    /// measurement.
    case none
    /// At least one retailer size contains a positive garment measurement.
    case available
}

/// One shared presence rule for product-wide early gates and exact-size Closet
/// picker eligibility.  This is deliberately a fact-presence helper, not a
/// local canonicalization or comparison policy.
enum FitMatchGarmentMeasurementPresence {
    static func presence(for parsedProduct: ParsedProductInfo) -> FitMatchProductMeasurementPresence {
        // Standard-size fallbacks and parser recovery states do not prove that
        // an actual retailer garment table is empty.  Treat them as unknown.
        guard parsedProduct.measurementAvailability == .actualMeasurements,
              !parsedProduct.sizes.isEmpty else {
            return .unknown
        }

        return parsedProduct.sizes.contains(where: hasAnyMeasurement(in:))
            ? .available
            : .none
    }

    static func hasAnyMeasurement(in size: ParsedProductSize) -> Bool {
        if !size.measurementRecords.isEmpty {
            return hasAnyGarmentRecord(in: size.measurementRecords)
        }
        // Some legacy retailer parsers filled the scalar garment fields before
        // measurement-record provenance existed.  Their scalar values remain
        // valid only as this bounded fallback; records always take priority.
        return hasAnyScalarMeasurement(in: size.measurements)
    }

    static func hasAnyMeasurement(in size: ProductSize) -> Bool {
        if !size.measurementRecords.isEmpty {
            return hasAnyGarmentRecord(in: size.measurementRecords)
        }
        return hasAnyScalarMeasurement(in: size.measurements)
    }

    static func hasAnyMeasurement(in records: [ParsedMeasurement]) -> Bool {
        hasAnyGarmentRecord(in: records)
    }

    private static func hasAnyGarmentRecord(in records: [ParsedMeasurement]) -> Bool {
        records.contains {
            $0.value.isFinite
                && $0.value > 0
                // A body-size chart is not a garment measurement table.
                && $0.measurementCode != .standardBodyChestCircumference
        }
    }

    private static func hasAnyGarmentRecord(in records: [GarmentMeasurementRecord]) -> Bool {
        records.contains {
            $0.value.isFinite
                && $0.value > 0
                && $0.measurementCode != .standardBodyChestCircumference
        }
    }

    private static func hasAnyScalarMeasurement(in measurements: GarmentMeasurements) -> Bool {
        [
            measurements.shoulder,
            measurements.chest,
            measurements.totalLength,
            measurements.sleeveLength,
            measurements.upperAbdomen,
            measurements.upperWaist,
            measurements.waist,
            measurements.hip,
            measurements.thigh,
            measurements.rise,
            measurements.hem,
            measurements.footLength,
            measurements.underBust
        ].contains { $0.isFinite && $0 > 0 }
    }
}

@Model
final class ProductSize {
    @Attribute(.unique)
    var id: UUID
    var name: String
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
    var displayOrder: Int
    var createdAt: Date
    var updatedAt: Date

    var measurementSchemaVersion: Int = 0
    var measurementMigrationVersion: Int = 0
    var measurementMigrationStatusRawValue: String = MeasurementMigrationStatus.notStarted.rawValue
    var measurementMigrationErrorCode: String?

    var product: Product?

    @Relationship(deleteRule: .cascade, inverse: \GarmentMeasurementRecord.productSize)
    var measurementRecords: [GarmentMeasurementRecord] = []

    init(
        id: UUID = UUID(),
        name: String,
        measurements: GarmentMeasurements,
        displayOrder: Int = 0,
        product: Product? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
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
        self.displayOrder = displayOrder
        self.product = product
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var measurementMigrationStatus: MeasurementMigrationStatus {
        get { MeasurementMigrationStatus(rawValue: measurementMigrationStatusRawValue) ?? .notStarted }
        set { measurementMigrationStatusRawValue = newValue.rawValue }
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
}
