import Foundation

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
