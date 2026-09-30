import Foundation
import Testing
@testable import FitMatch

@MainActor
struct ClosetRegistrationDuplicateRawTests {
    @Test func referenceSnapshotRetainsServerCodesWithoutPromotingRetailerFacts() throws {
        let item = UserFit(
            sourceType: .manual, brandName: "test", productName: "test",
            category: .top, detailCategory: .shortSleeve, sizeName: "M",
            measurements: GarmentMeasurements(shoulder: 0, chest: 0, totalLength: 0, sleeveLength: 0),
            fitMemo: "", satisfaction: 3
        )
        item.categoryCode = "tops"
        item.detailCategoryCode = "short_sleeve"
        item.garmentTypeRawValue = "tshirt"
        item.markClassificationAuthority(.serverConfirmed)
        let expected = ["back_width": 50.0, "front_length_shoulder_to_hem": 67.5,
                        "upper_arm_width": 21.5, "chest_width": 56.0, "sleeve_length": 62.5]
        item.measurementRecords = expected.map { code, value in
            GarmentMeasurementRecord(
                value: value, measurementCode: .unknown, measurementCodeRawValue: code,
                displayKind: .unknown, methodSource: "fitmatch_vnext_snapshot",
                inputSource: .importedSizeChart, mappingVersion: "fixture",
                rawCode: code, rawLabel: code, evidenceLevel: .officialText,
                semanticStatus: .unknownDefinition, userFit: item
            )
        }
        item.measurementRecords.append(GarmentMeasurementRecord(
            value: 99, measurementCode: .unknown, displayKind: .unknown,
            methodSource: "zara", inputSource: .importedSizeChart, mappingVersion: "fixture",
            rawCode: "future_raw", rawLabel: "future_raw", evidenceLevel: .officialText,
            semanticStatus: .unknownDefinition, userFit: item
        ))
        #expect(try #require(item.fitMatchServerReferenceSnapshot()).measurements == expected)
        #expect(item.measurementRecords.count == 6)
    }

    @Test(arguments: ["unknown", "chest_width"])
    func preservesDistinctRawRowsWithDuplicateLocalCodes(localCode: String) throws {
        let product = Product(
            id: UUID(), name: "Raw regression", category: .top,
            productCode: "564222870", sourceURLString: "https://www.zara.com/kr/ko/test-p03443415.html?v1=564228855",
            metadata: ProductMetadata(genderCodes: ["MEN"]),
            sourceType: .marketplace, sourceName: "ZARA", source: .catalog
        )
        product.garmentTypeRawValue = "tshirt"
        product.sleeveTypeRawValue = "long_sleeve"
        product.markClassificationAuthority(.serverConfirmed)
        let size = ProductSize(
            id: UUID(), name: "M", measurements: GarmentMeasurements(
                shoulder: 0, chest: 56, totalLength: 0, sleeveLength: 0
            ), product: product
        )
        size.measurementRecords = [
            ("zone-name-front-length", 67.5),
            ("zone-name-back-width", 50.0),
            ("zone-name-arm-width", 21.5)
        ].map { code, value in
            GarmentMeasurementRecord(
                value: value, measurementCode: .unknown,
                measurementCodeRawValue: localCode, displayKind: .unknown,
                methodSource: "zara", inputSource: .importedSizeChart,
                mappingVersion: "raw_v1", rawCode: code, rawLabel: code,
                rawValueText: String(value), evidenceLevel: .officialText,
                semanticStatus: .unknownDefinition, productSize: size
            )
        }
        product.sizes = [size]
        let request = FitMatchComparedProductClosetRegistration.SaveRequest(
            product: product, selectedSize: size,
            serverIdentity: FitMatchClosetRegistrationServerIdentity(
                productID: UUID(), productVariantID: UUID(), productSizeID: UUID()
            ),
            hasMeasurementEligibilityProof: true,
            activeClosetItems: [], brandName: "ZARA", gender: .men, genderCode: "male",
            productName: product.name, category: .top, categoryCode: "tops",
            detailCategory: .shortSleeve, detailCategoryCode: "short_sleeve",
            isRepresentative: false, didExplicitlyChangeClassification: false,
            didExplicitlySelectClosetClassification: false
        )
        let payload = try FitMatchComparedProductClosetRegistration
            .prepareServerFirstSubmission(request).remoteRequest.item
        #expect(payload.measurements.isEmpty)
        #expect(payload.measurementRecords.count == 3)
        #expect(payload.measurementRecords.map(\.rawCode) == size.measurementRecords.map(\.rawCode))
        #expect(payload.measurementRecords.map(\.value) == [67.5, 50, 21.5])
    }
}
