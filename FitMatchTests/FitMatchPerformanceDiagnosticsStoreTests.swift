import Foundation
import Testing
@testable import FitMatch

struct FitMatchPerformanceDiagnosticsStoreTests {
    @Test func recordsOnlyTypedNavigationAndScrollSummaries() {
        let suite = "FitMatchTests.Performance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FitMatchPerformanceDiagnosticsStore(defaults: defaults)

        store.begin(.historyToResult)
        store.mark(.historyToResult, event: "result_appeared")
        store.mark(.historyToResult, event: "first_main_runloop", finished: true)
        store.scrollSummary(screen: "history_list", frames: 20, delayed: 3, severe: 1, worstMS: 42)

        let report = store.report()
        #expect(report.contains("route=history_to_result event=tapped"))
        #expect(report.contains("route=history_to_result event=result_appeared elapsed_ms="))
        #expect(report.contains("step_ms="))
        #expect(report.contains("screen=history_list event=scroll_summary display_intervals=20 delayed_24ms=3 severe_40ms=1"))
        #expect(!report.contains("product="))
        #expect(!report.contains("https://"))
    }

    @Test func ignoresUnstartedRoutesAndBoundsStoredEvents() {
        let suite = "FitMatchTests.Performance.Bounded.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FitMatchPerformanceDiagnosticsStore(defaults: defaults)

        store.mark(.resultToCandidates, event: "candidates_appeared", finished: true)
        for _ in 0..<50 {
            store.scrollSummary(screen: "comparison_candidates", frames: 10, delayed: 0, severe: 0, worstMS: 17)
        }

        let report = store.report()
        #expect(defaults.stringArray(forKey: FitMatchPerformanceDiagnosticsStore.recentKey)?.count == 40)
        #expect(!report.contains("route=result_to_candidates"))
    }

    @Test func comparisonMilestonesStayOrderedAndStopAfterCompletion() {
        let suite = "FitMatchTests.Performance.Comparison.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FitMatchPerformanceDiagnosticsStore(defaults: defaults)

        store.begin(.comparisonCardToResult)
        store.mark(.comparisonCardToResult, event: "reference_authorized")
        store.mark(.comparisonCardToResult, event: "begin_completed")
        store.mark(.comparisonCardToResult, event: "first_main_runloop", finished: true)
        store.mark(.comparisonCardToResult, event: "unexpected_after_finish")

        let report = store.report()
        let authorized = report.range(of: "event=reference_authorized")
        let begin = report.range(of: "event=begin_completed")
        let visible = report.range(of: "event=first_main_runloop")
        #expect(authorized != nil && begin != nil && visible != nil)
        if let authorized, let begin, let visible {
            #expect(authorized.lowerBound < begin.lowerBound)
            #expect(begin.lowerBound < visible.lowerBound)
        }
        #expect(!report.contains("unexpected_after_finish"))
        #expect(report.contains("step_ms="))
    }

    @Test func frameCadenceAndSlowWorkAreBoundedAndContainNoProductData() {
        let suite = "FitMatchTests.Performance.Cadence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FitMatchPerformanceDiagnosticsStore(defaults: defaults)
        var cadence = FitMatchFrameCadenceBuckets()
        for interval in [8.3, 16.7, 24.9, 33.4, 59.3] {
            cadence.record(intervalMS: interval)
        }
        store.frameCadenceSummary(
            route: .historyToResult,
            phase: "after_appear",
            requestedFPS: 120,
            cadence: cadence
        )
        store.scrollSummary(
            screen: "recommendation_result", frames: 5, delayed: 3,
            severe: 1, worstMS: 59.3, requestedFPS: 120, cadence: cadence
        )
        for _ in 0..<10 {
            store.recordSlowWork(.resultMeasurements, elapsedMS: 9)
        }
        store.recordSlowWork(.resultSnapshotInit, elapsedMS: 7.9)

        let report = store.report()
        #expect(report.contains("phase=after_appear event=frame_cadence requested_fps=120"))
        #expect(report.contains("intervals=5 under_12ms=1 from_12_to_20ms=1 from_20_to_28ms=1 from_28_to_40ms=1 over_40ms=1"))
        #expect(report.contains("screen=recommendation_result event=scroll_summary"))
        #expect(report.contains("requested_fps=120"))
        #expect(report.components(separatedBy: "event=slow_work operation=result_measurements").count == 6)
        #expect(!report.contains("operation=result_snapshot_init"))
        #expect(!report.contains("product="))
    }
}
