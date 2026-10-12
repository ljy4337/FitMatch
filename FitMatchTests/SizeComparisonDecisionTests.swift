import Foundation
import Testing
@testable import FitMatch

@MainActor
struct SizeComparisonDecisionTests {
    @Test func singleChestNearMatchNeverBecomesAnOverallSimilarity() throws {
        let evidence = VNextAuthorizedMeasurementDTO(
            measurementCode: "chest_width", referenceValue: 43, targetValue: 42.5,
            difference: -0.5, absoluteDifference: 0.5, unitCode: "cm",
            basisCode: "chest_pit_to_pit", weight: 2,
            requirementMode: "REQUIRED_ANY", priority: 1)
        let result = try #require(MeasurementComparisonEngine().compareAuthorizedEvidence(
            [evidence], minimumComparableCount: 1))
        #expect(result.score == 98)
        let summary = FitMatchClosetComparisonSummary(
            closetItemID: UUID(), comparisonGroup: .tops,
            recommendedProductSizeID: UUID(), recommendedSizeLabel: "L",
            comparisonResult: result)
        #expect(summary.similarityPercent == nil)
        #expect(summary.evidenceState == .comparable)
    }
    @Test(arguments: [
        (FitMatchComparisonGroup.tops, ["chest_width"], false),
        (.tops, ["chest_width", "shoulder_width"], false),
        (.tops, ["chest_width", "back_length"], true),
        (.tops, ["chest_width", "front_length_shoulder_to_hem"], true),
        (.tops, ["back_length", "sleeve_length"], false),
        (.outerwear, ["chest_width", "back_length"], true),
        (.pants, ["waist_width", "hip_width", "outseam"], true),
        (.pants, ["waist_width", "thigh_width", "outseam"], false),
        (.skirts, ["waist_width", "hip_width", "total_length"], true),
        (.onePiece, ["chest_width", "back_length"], false),
        (.onePiece, ["chest_width", "waist_width", "back_length"], true),
        (.onePiece, ["chest_width", "hip_width", "back_length"], true),
        (.innerwear, ["chest_width", "back_length"], false),
        (.homewear, ["chest_width", "back_length"], false)
    ])
    func coreDimensionsControlWholeGarmentScore(
        group: FitMatchComparisonGroup, codes: [String], shouldShowScore: Bool
    ) throws {
        let evidence = codes.enumerated().map { index, code in
            VNextAuthorizedMeasurementDTO(
                measurementCode: code, referenceValue: 50, targetValue: 51,
                difference: 1, absoluteDifference: 1, unitCode: "cm", basisCode: "verified",
                weight: 1, requirementMode: "OPTIONAL", priority: index + 1)
        }
        let result = try #require(MeasurementComparisonEngine().compareAuthorizedEvidence(evidence, minimumComparableCount: 1))
        let decision = SizeComparisonDecision.make(group: group, result: result)
        #expect((decision.overallScore != nil) == shouldShowScore)
        #expect(decision.overallScore == (shouldShowScore ? 95 : nil))
        #expect(!decision.scoreText.contains("%"))
        #expect(!decision.badge.contains("핏"))
    }

    @Test func unknownGroupOrHistoricalScoreWithoutEvidenceCannotClaimOverallFit() {
        let decision = SizeComparisonDecision.make(group: nil, score: 100, status: .legacy, measurements: [])
        #expect(decision.overallScore == nil)
        #expect(decision.comparedCount == 0)
        #expect(decision.sizeTitle == "참고 사이즈")
    }

    @Test func zaraFrontLengthRetainsItsOwnExactSemanticCode() throws {
        let projection = try #require(FitMatchCanonicalMeasurementCode.projection(for: "front_length_shoulder_to_hem"))
        #expect(projection.localCode == .bodyLengthFrontShoulderSeamToHem)
        #expect(projection.localCode != .bodyLengthBackNeckToHem)
        #expect(projection.localCode != .bodyLengthHPSToHemFront)
        #expect(FitMatchCanonicalMeasurementCode.canonicalCode(for: projection.localCode) == "front_length_shoulder_to_hem")
    }
}
