import Foundation

enum FitMatchPerformanceRoute: String {
    case historyToResult = "history_to_result"
    case comparisonCardToResult = "comparison_card_to_result"
    case resultToCandidates = "result_to_candidates"
    case resultToOtherClothesSheet = "result_to_other_clothes_sheet"
    case resultToSizesSheet = "result_to_sizes_sheet"
    case sizeApplyToResult = "size_apply_to_result"
}

struct FitMatchFrameCadenceBuckets {
    private(set) var intervals = 0
    private(set) var under12 = 0
    private(set) var from12To20 = 0
    private(set) var from20To28 = 0
    private(set) var from28To40 = 0
    private(set) var over40 = 0
    private(set) var worstMS: Double = 0

    mutating func record(intervalMS: Double) {
        guard intervalMS.isFinite, intervalMS > 0 else { return }
        intervals += 1
        worstMS = max(worstMS, intervalMS)
        switch intervalMS {
        case ..<12: under12 += 1
        case ..<20: from12To20 += 1
        case ..<28: from20To28 += 1
        case ..<40: from28To40 += 1
        default: over40 += 1
        }
    }

    var summary: String {
        String(
            format: "intervals=%d under_12ms=%d from_12_to_20ms=%d from_20_to_28ms=%d from_28_to_40ms=%d over_40ms=%d worst_interval_ms=%.1f",
            intervals, under12, from12To20, from20To28, from28To40, over40, worstMS
        )
    }
}

enum FitMatchPerformanceWork: String {
    case resultSnapshotInit = "result_snapshot_init"
    case resultMeasurements = "result_measurements"
    case supplementalComparison = "supplemental_comparison"
}

final class FitMatchPerformanceDiagnosticsStore {
    static let shared = FitMatchPerformanceDiagnosticsStore(
        defaults: UserDefaults(suiteName: AppGroupConfig.identifier) ?? .standard
    )
    static let recentKey = "FitMatch.performance.recent.v1"
    private static let recentLimit = 40

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "FitMatch.performance.diagnostics", qos: .utility)
    private struct RouteTiming {
        let startedAt: TimeInterval
        var lastMarkedAt: TimeInterval
    }
    private var starts: [FitMatchPerformanceRoute: RouteTiming] = [:]
    private var slowWorkCounts: [FitMatchPerformanceWork: Int] = [:]

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func begin(_ route: FitMatchPerformanceRoute) {
        let now = ProcessInfo.processInfo.systemUptime
        queue.async {
            self.starts[route] = RouteTiming(startedAt: now, lastMarkedAt: now)
            self.append("route=\(route.rawValue) event=tapped")
        }
    }

    func mark(_ route: FitMatchPerformanceRoute, event: String, finished: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        queue.async {
            guard var timing = self.starts[route] else { return }
            let elapsed = max(0, (now - timing.startedAt) * 1_000)
            let step = max(0, (now - timing.lastMarkedAt) * 1_000)
            self.append(String(format: "route=%@ event=%@ elapsed_ms=%.1f step_ms=%.1f", route.rawValue, event, elapsed, step))
            if finished {
                self.starts.removeValue(forKey: route)
            } else {
                timing.lastMarkedAt = now
                self.starts[route] = timing
            }
        }
    }

    func frameCadenceSummary(
        route: FitMatchPerformanceRoute,
        phase: String,
        requestedFPS: Int,
        cadence: FitMatchFrameCadenceBuckets
    ) {
        guard cadence.intervals > 0 else { return }
        queue.async {
            self.append("route=\(route.rawValue) phase=\(phase) event=frame_cadence requested_fps=\(requestedFPS) \(cadence.summary)")
        }
    }

    func scrollSummary(
        screen: String,
        frames: Int,
        delayed: Int,
        severe: Int,
        worstMS: Double,
        requestedFPS: Int? = nil,
        cadence: FitMatchFrameCadenceBuckets? = nil
    ) {
        guard frames > 0 else { return }
        queue.async {
            var value = String(
                format: "screen=%@ event=scroll_summary display_intervals=%d delayed_24ms=%d severe_40ms=%d worst_interval_ms=%.1f",
                screen, frames, delayed, severe, worstMS
            )
            if let requestedFPS, let cadence {
                value += " requested_fps=\(requestedFPS) \(cadence.summary)"
            }
            self.append(value)
        }
    }

    func recordSlowWork(_ operation: FitMatchPerformanceWork, elapsedMS: Double) {
        guard elapsedMS.isFinite, elapsedMS >= 8 else { return }
        queue.async {
            let count = self.slowWorkCounts[operation, default: 0]
            guard count < 5 else { return }
            self.slowWorkCounts[operation] = count + 1
            self.append(String(format: "event=slow_work operation=%@ elapsed_ms=%.1f", operation.rawValue, elapsedMS))
        }
    }

    func report() -> String {
        queue.sync {
            let recent = defaults.stringArray(forKey: Self.recentKey) ?? []
            return (["performance_events_limit=\(Self.recentLimit)"] + recent).joined(separator: "\n")
        }
    }

    private func append(_ value: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var recent = defaults.stringArray(forKey: Self.recentKey) ?? []
        recent.append("\(timestamp) \(value)")
        defaults.set(Array(recent.suffix(Self.recentLimit)), forKey: Self.recentKey)
    }
}

enum DetailPerformanceDiagnostics {
    private static var historyResultNavigationStartedAt: TimeInterval?

    static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    static func log(
        screen: String,
        event: String,
        startedAt: TimeInterval,
        metadata: String = ""
    ) {
        #if DEBUG
        let elapsedMilliseconds = (now() - startedAt) * 1_000
        let thread = Thread.isMainThread ? "main" : "background"
        let suffix = metadata.isEmpty ? "" : " \(metadata)"
        print(
            String(
                format: "[DetailPerformance] screen=%@ event=%@ elapsed_ms=%.1f thread=%@%@",
                screen,
                event,
                elapsedMilliseconds,
                thread,
                suffix
            )
        )
        #endif
    }

    static func beginHistoryResultNavigation(productName: String) {
        #if DEBUG
        historyResultNavigationStartedAt = now()
        print("[NavigationPerformance] route=history_to_result event=card_tapped elapsed_ms=0.0 product=\(productName)")
        #endif
    }

    static func logHistoryResultNavigation(event: String) {
        #if DEBUG
        guard let startedAt = historyResultNavigationStartedAt else { return }
        let elapsedMilliseconds = (now() - startedAt) * 1_000
        print(
            String(
                format: "[NavigationPerformance] route=history_to_result event=%@ elapsed_ms=%.1f",
                event,
                elapsedMilliseconds
            )
        )
        if event == "first_main_runloop" {
            historyResultNavigationStartedAt = nil
        }
        #endif
    }
}
