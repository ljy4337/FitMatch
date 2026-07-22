import Foundation

#if DEBUG
enum FitMatchDebugLogger {
    static func event(
        screen: String,
        action: String,
        state: String,
        details: @autoclosure () -> String = ""
    ) {
        let value = details()
        let suffix = value.isEmpty ? "" : " \(value)"
        print("[화면: \(screen)][동작: \(action)][상태: \(state)]\(suffix)")
    }

    static func detail(
        screen: String,
        action: String,
        details: @autoclosure () -> String
    ) {
        print("[DEBUG][화면: \(screen)][동작: \(action)] \(details())")
    }
}
#endif
