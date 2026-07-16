import Foundation
import SwiftData

@Model
final class GarmentMeasurementRecord {
    @Attribute(.unique)
    var id: UUID
    var value: Double
    var unitRawValue: String
    var measurementCodeRawValue: String
    var displayKindRawValue: String
    var methodSource: String
    var methodProfile: String?
    var inputSourceRawValue: String
    var standardVersion: String?
    var mappingVersion: String
    var rawCode: String?
    var rawLabel: String
    var rawInfo: String?
    var rawValueText: String?
    var evidenceLevelRawValue: String
    var semanticStatusRawValue: String
    var createdAt: Date
    var updatedAt: Date

    var productSize: ProductSize?
    var userFit: UserFit?

    init(
        id: UUID = UUID(),
        value: Double,
        unit: MeasurementUnit = .centimeter,
        measurementCode: MeasurementCode,
        displayKind: MeasurementDisplayKind,
        methodSource: String,
        methodProfile: String? = nil,
        inputSource: MeasurementInputSource,
        standardVersion: String? = nil,
        mappingVersion: String,
        rawCode: String? = nil,
        rawLabel: String,
        rawInfo: String? = nil,
        rawValueText: String? = nil,
        evidenceLevel: MeasurementEvidenceLevel,
        semanticStatus: MeasurementSemanticStatus,
        productSize: ProductSize? = nil,
        userFit: UserFit? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.value = value
        self.unitRawValue = unit.rawValue
        self.measurementCodeRawValue = measurementCode.rawValue
        self.displayKindRawValue = displayKind.rawValue
        self.methodSource = methodSource
        self.methodProfile = methodProfile
        self.inputSourceRawValue = inputSource.rawValue
        self.standardVersion = standardVersion
        self.mappingVersion = mappingVersion
        self.rawCode = rawCode
        self.rawLabel = rawLabel
        self.rawInfo = rawInfo
        self.rawValueText = rawValueText
        self.evidenceLevelRawValue = evidenceLevel.rawValue
        self.semanticStatusRawValue = semanticStatus.rawValue
        self.productSize = productSize
        self.userFit = userFit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var measurementCode: MeasurementCode {
        MeasurementCode(rawValue: measurementCodeRawValue) ?? .unknown
    }

    var displayKind: MeasurementDisplayKind? {
        MeasurementDisplayKind(rawValue: displayKindRawValue)
    }

    var semanticStatus: MeasurementSemanticStatus {
        MeasurementSemanticStatus(rawValue: semanticStatusRawValue) ?? .unknownDefinition
    }

    var isComparable: Bool {
        value.isFinite && value > 0
            && measurementCode != .unknown
            && measurementCode != .legacyUnknown
            && semanticStatus == .mapped
    }
}
