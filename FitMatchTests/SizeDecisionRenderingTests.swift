import XCTest
import SwiftUI
import SwiftData
@testable import FitMatch

@MainActor
final class SizeDecisionRenderingTests: XCTestCase {
    func testPartialAndCompleteResultCardsRender() async throws {
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        for full in [false, true] {
            let evidence = [VNextAuthorizedMeasurementDTO(
                measurementCode: "chest_width", referenceValue: 43, targetValue: 42.5,
                difference: -0.5, absoluteDifference: 0.5, unitCode: "cm", basisCode: "chest_pit_to_pit",
                weight: 2, requirementMode: "OPTIONAL", priority: 0)] + (full ? [VNextAuthorizedMeasurementDTO(
                measurementCode: "back_length", referenceValue: 60, targetValue: 59,
                difference: -1, absoluteDifference: 1, unitCode: "cm", basisCode: "back_neck_to_hem",
                weight: 1, requirementMode: "OPTIONAL", priority: 1)] : [])
            let cache = VNextAuthorizedScoreCache()
            let calculated = VNextRankingEvidence.compare(evidence, cache: cache)
            let comparison = try XCTUnwrap(calculated)
            let size = ProductSize(name: "L", measurements: .init(shoulder: 0, chest: 42.5, totalLength: full ? 59 : 0, sleeveLength: 0))
            let product = Product(name: "립미니T", category: .top, sizes: [size])
            let reference = UserFit(brandName: "ZARA", productName: "내 티셔츠", category: .top,
                sizeName: "L", measurements: .init(shoulder: 0, chest: 43, totalLength: full ? 60 : 0, sleeveLength: 0),
                fitMemo: "", satisfaction: 3)
            let history = RecommendationHistory(product: product, recommendedSize: size, userFit: reference,
                totalDifference: comparison.averageDifference, measurementDifferences: comparison.signedDifferences,
                recommendationScore: comparison.score, comparisonResult: comparison)
            container.mainContext.insert(history)
            XCTAssertEqual(history.sizeComparisonDecision.overallScore, full ? 97 : nil)
            let view = RecommendationResultView(result: history).releaseSizeDecisionCard
                .padding(16).frame(width: 393).background(Color(.systemBackground))
                .environment(\.colorScheme, .light).modelContainer(container)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let rendered = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(rendered.size.height, 180)
            let attachment = XCTAttachment(image: rendered)
            attachment.name = full ? "core-dimensions-97-points" : "chest-only-partial-no-percentage"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
