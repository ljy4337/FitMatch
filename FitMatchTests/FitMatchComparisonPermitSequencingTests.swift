import Foundation
import Testing
@testable import FitMatch

struct FitMatchComparisonPermitSequencingTests {
    @Test func profileMatcherCannotRunMeasurementScorer() throws {
        let source = try sourceFile("FitMatch/Services/ComparisonProfileMatcher.swift")

        #expect(!source.contains("MeasurementComparisonEngine"))
        #expect(!source.contains("hasConfirmedMeasurementComparison"))
    }

    @Test func releaseComparisonCallSitesRequirePermitBeforeScoring() throws {
        let viewModel = try sourceFile("FitMatch/ViewModels/ShoppingProductViewModel.swift")
        let viewModelBegin = try #require(
            viewModel.range(of: "return try await coordinator.beginAuthorizedComparison")
        )
        let viewModelScore = try #require(
            viewModel.range(of: "recommendationService.recommendAfterServerAuthorization")
        )
        #expect(viewModelBegin.lowerBound < viewModelScore.lowerBound)

        let resultView = try sourceFile("FitMatch/Views/RecommendationResultView.swift")
        let releaseResultView = strippingDebugOnlyCode(from: resultView)
        let resultBegin = try #require(
            releaseResultView.range(of: "permit = try await coordinator.beginAuthorizedComparison")
        )
        let resultScore = try #require(
            releaseResultView.range(of: "ResultReferenceComparisonPersistence.resolveAndSave")
        )
        #expect(resultBegin.lowerBound < resultScore.lowerBound)
        #expect(!releaseResultView.contains(".recommend("))
        #expect(!releaseResultView.contains(".insufficientEvidence("))

        let compareFlow = try sourceFile("FitMatch/Views/CompareFlowSheet.swift")
        #expect(!compareFlow.contains(".automaticMatchResult("))
        #expect(!compareFlow.contains(".referenceSelectionPlan("))
        #expect(!compareFlow.contains("MeasurementComparisonEngine"))
    }

    @Test func persistedServerApprovalGuardsAlternativeSizeScoring() throws {
        let resultView = strippingDebugOnlyCode(
            from: try sourceFile("FitMatch/Views/RecommendationResultView.swift")
        )
        let serverApprovalGuard = try #require(
            resultView.range(
                of: "currentResult.comparisonMethod.hasPrefix(\"서버 승인\")"
            )
        )
        let alternativeScore = try #require(
            resultView.range(of: "service.analyzeSizeWithoutSaving")
        )

        #expect(serverApprovalGuard.lowerBound < alternativeScore.lowerBound)
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func strippingDebugOnlyCode(from source: String) -> String {
        var debugDepth = 0
        var retained: [Substring] = []

        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let directive = line.trimmingCharacters(in: .whitespaces)
            if directive == "#if DEBUG" {
                debugDepth += 1
                continue
            }
            if debugDepth > 0, directive.hasPrefix("#if ") {
                debugDepth += 1
                continue
            }
            if debugDepth > 0, directive == "#endif" {
                debugDepth -= 1
                continue
            }
            if debugDepth == 0 {
                retained.append(line)
            }
        }

        return retained.joined(separator: "\n")
    }
}
