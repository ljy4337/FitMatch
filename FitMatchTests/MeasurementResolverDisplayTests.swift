import Foundation
import SwiftData
import Testing
@testable import FitMatch

@MainActor
@Suite(.serialized)
struct MeasurementResolverDisplayTests {
    @Test func providerMeasurementCodesUseKoreanClosetTitles() {
        let fixtures: [(String, MeasurementCode, MeasurementDisplayKind, String)] = [
            ("uniqlo.waist_circumference.garment", .waistWidthEdgeToEdge, .waist, "허리단면"),
            ("uniqlo.hip_circumference.garment", .hipWidthAtWidest, .hip, "엉덩이단면"),
            ("zara.front_rise.front", .riseCrotchToWaistFront, .rise, "앞 밑위"),
            ("musinsa.shoulder_width.seam", .shoulderWidthSeamToSeam, .shoulder, "어깨너비"),
            ("musinsa.sleeve_length", .unknown, .sleeveLength, "소매길이"),
            ("provider.unmapped_metric", .unknown, .unknown, "실측")
        ]
        let records = fixtures.map { rawLabel, code, kind, _ in
            GarmentMeasurementRecord(
                value: 42,
                measurementCode: code,
                displayKind: kind,
                methodSource: "fitmatch_vnext_snapshot",
                inputSource: .importedSizeChart,
                mappingVersion: "test",
                rawLabel: rawLabel,
                rawValueText: "42",
                evidenceLevel: .officialText,
                semanticStatus: code == .unknown ? .unknownDefinition : .mapped
            )
        }

        let rowsByID = Dictionary(
            uniqueKeysWithValues: MeasurementResolver.sourceDisplayRows(records: records)
                .map { ($0.id, $0.title) }
        )
        for (index, fixture) in fixtures.enumerated() {
            #expect(rowsByID[records[index].id] == fixture.3)
        }
        #expect(rowsByID.values.allSatisfy {
            $0.range(of: "[a-z]", options: [.regularExpression, .caseInsensitive]) == nil
        })
    }
}
