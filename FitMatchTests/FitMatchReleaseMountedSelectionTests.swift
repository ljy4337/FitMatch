import SwiftUI
import SwiftData
import Testing
import UIKit
@testable import FitMatch

/// Real mounted view state and button owners; remote receipts are synthetic.
/// This does not claim physical taps, live authentication, or database E2E.
@MainActor
struct FitMatchReleaseMountedSelectionTests {
    @Test func alternateSizeThenAnotherClosetThenAlternateSizeRemountsActualResult() async throws {
        let fixture = HeadlessJourneyFixture(provider: .musinsa)
        let helpers = FitMatchReleaseContinuationTests()
        let sizeIDs = [fixture.productSizeID, UUID()]
        let first = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        let second = fixture.localReference(garment: "tshirt", sleeve: "short_sleeve")
        first.isRepresentative = false
        second.isRepresentative = false
        second.productName = "Mounted second Closet"
        second.chest = 56
        let records = [fixture.closetRecord(for: first), fixture.closetRecord(for: second)]
        let firstCandidates = helpers.candidates(sizeIDs: sizeIDs, referenceChest: 50)
        let secondCandidates = helpers.candidates(sizeIDs: sizeIDs, referenceChest: 56)
        let secondComparisonID = UUID()
        let runtime = try fixture.runtime(globalStatus: .confirmed, runtimeCandidates: firstCandidates)
        let remote = JourneyRecordingRemote(
            resolutions: Array(repeating: fixture.resolution(globalStatus: .confirmed), count: 3),
            runtimes: Array(repeating: runtime, count: 3),
            closetResponses: [.init(state: "ready", items: records)],
            candidateResponses: [
                try fixture.referenceResponse(candidates: [
                    (first, records[0].closetItemID, "MANUAL_EXTENDED"),
                    (second, records[1].closetItemID, "MANUAL_EXTENDED")]),
                try fixture.referenceResponse(reference: first, closetItemID: records[0].closetItemID,
                    decision: "MANUAL_EXTENDED", eligibleProductSizeIDs: sizeIDs),
                try fixture.referenceResponse(reference: second, closetItemID: records[1].closetItemID,
                    decision: "MANUAL_EXTENDED", eligibleProductSizeIDs: sizeIDs)
            ],
            eligibleResponses: [
                try fixture.eligible(referenceClosetItemID: records[0].closetItemID,
                    candidates: firstCandidates, allowed: true, decision: "MANUAL_EXTENDED"),
                try fixture.eligible(referenceClosetItemID: records[1].closetItemID,
                    candidates: secondCandidates, allowed: true, decision: "MANUAL_EXTENDED")],
            beginResponses: [
                try helpers.begin(fixture: fixture, comparisonID: fixture.comparisonID,
                    referenceID: records[0].closetItemID, candidates: firstCandidates),
                try helpers.begin(fixture: fixture, comparisonID: secondComparisonID,
                    referenceID: records[1].closetItemID, candidates: secondCandidates)],
            completionResponses: [
                helpers.completion(id: fixture.comparisonID, sizeID: sizeIDs[0], label: "M"),
                helpers.completion(id: secondComparisonID, sizeID: sizeIDs[1], label: "L")])
        let viewModel = ShoppingProductViewModel(initialURL: fixture.url.absoluteString,
            parserService: ProductURLParserService(musinsaParser: HeadlessJourneyParser(product: fixture.parsedProduct())),
            metricsRecorder: HeadlessNoopMetricsRecorder(),
            serverAuthorityCoordinator: FitMatchServerAuthorityCoordinator(remote: remote))
        let schema = Schema(FitMatchSchemaV1.models)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()
        let probe = FitMatchReleaseSelectionProbe()
        let root = NavigationStack {
            CompareFlowSheet(testingViewModel: viewModel, initialURL: fixture.url.absoluteString)
        }
        .modelContainer(container)
        .environmentObject(FitMatchAuthSessionStore(client: nil))
        .environmentObject(TabBarVisibilityController())
        .environment(\.fitMatchReleaseSelectionProbe, probe)
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            for id in probe.resultAppearances { VNextComparisonSessionStore.shared.remove(historyID: id) }
            window.isHidden = true
            window.rootViewController = nil
            probe.flow = nil
            probe.result = nil
        }
        try await waitUntil("candidate screen: \(viewModel.errorMessage ?? "pending")") {
            probe.flow?.releaseSelectionStep == "comparisonSummary"
        }
        let flow = try #require(probe.flow)
        #expect(Set(flow.releaseCandidateIDs) == Set([first.id, second.id]))
        #expect(flow.releaseSelectedClosetID == nil)
        #expect(flow.releaseChooseCloset(first.id))
        try await waitUntil("first mounted result") {
            probe.result?.result.referencesClosetItem(clientItemID: first.id) == true
        }
        let firstResult = try #require(probe.result)
        let firstHistoryID = firstResult.result.id
        let firstAlternativeID = VNextHistoryProjectionIdentity.productSizeID(
            comparisonID: firstHistoryID, productSizeID: sizeIDs[1])
        #expect(firstResult.result.product.sizes.contains { $0.id == firstAlternativeID })
        #expect(firstResult.releaseDisplayedServerSizeID == sizeIDs[0])
        let firstCalls = await remote.calls()
        firstResult.releaseOpenAlternativeSizes()
        try await waitUntil("first size analyses") { firstResult.releaseAnalysisCount == 2 }
        firstResult.releaseChooseAlternativeSize(firstAlternativeID)
        firstResult.releaseApplyAlternativeSize()
        try await waitUntil("first alternate applied") {
            firstResult.releaseDisplayedServerSizeID == sizeIDs[1] && !firstResult.releaseSizeSheetPresented
        }
        #expect(firstResult.releaseSelectedSizeID == firstAlternativeID)
        #expect(firstResult.releaseTemporaryReferenceChest == 50)
        #expect(await remote.calls() == firstCalls)

        firstResult.releaseShowOtherCloset()
        try await waitUntil("actual result subtree removed") {
            flow.releaseSelectionStep == "comparisonSummary"
                && probe.resultDisappearances.contains(firstHistoryID)
        }
        #expect(flow.releaseSelectedClosetID == nil)
        #expect(flow.releaseChooseCloset(second.id))
        try await waitUntil("second mounted result") {
            probe.result?.result.referencesClosetItem(clientItemID: second.id) == true
        }
        let secondResult = try #require(probe.result)
        #expect(firstHistoryID != secondResult.result.id)
        let secondAlternativeID = VNextHistoryProjectionIdentity.productSizeID(
            comparisonID: secondResult.result.id, productSizeID: sizeIDs[0])
        #expect(secondResult.result.product.sizes.contains { $0.id == secondAlternativeID })
        #expect(probe.resultAppearances.contains(secondResult.result.id))
        // These fail if the old Result's actual selected ID/cache are reused.
        #expect(secondResult.releaseSelectedSizeID == nil)
        #expect(secondResult.releaseAnalysisCount == 0)
        #expect(secondResult.releaseTemporaryReferenceChest == nil)
        #expect(secondResult.releaseDisplayedServerSizeID == sizeIDs[1])
        #expect(flow.releaseSelectedClosetID == second.id)
        let secondCalls = await remote.calls()
        secondResult.releaseOpenAlternativeSizes()
        try await waitUntil("second size analyses") { secondResult.releaseAnalysisCount == 2 }
        secondResult.releaseChooseAlternativeSize(secondAlternativeID)
        secondResult.releaseApplyAlternativeSize()
        try await waitUntil("second alternate applied") {
            secondResult.releaseDisplayedServerSizeID == sizeIDs[0] && !secondResult.releaseSizeSheetPresented
        }
        #expect(secondResult.releaseSelectedSizeID == secondAlternativeID)
        #expect(secondResult.releaseTemporaryReferenceChest == 56)
        #expect(await remote.calls() == secondCalls)
        #expect(secondCalls.filter { $0 == "begin_comparison" }.count == 2)
        #expect(secondCalls.filter { $0 == "complete_comparison" }.count == 2)
        let batch = try #require(VNextComparisonSessionStore.shared.analysis(for: secondResult.result.id))
        #expect(batch.comparisonID == secondComparisonID)
    }

    private func waitUntil(_ phase: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), Comment(rawValue: phase))
    }
}
