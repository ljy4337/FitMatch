import Foundation

/// The app's data-level entry policy for custom links and Share handoffs.
///
/// This deliberately decides only whether a deep link is allowed to request a
/// pending product handoff. `ContentView` still owns presentation and the
/// shared-store owns generation-safe consumption. Keeping that boundary here
/// prevents an unknown app route from accidentally consuming an unrelated
/// pending Share payload.
enum FitMatchProductEntryRouting {
    enum DeepLinkAction: Equatable {
        case openPendingProductCompare
        case ignore
    }

    static func action(for url: URL) -> DeepLinkAction {
        guard isSupportedAppLink(url) else { return .ignore }
        return route(from: url) == "compare" ? .openPendingProductCompare : .ignore
    }

    static func isSupportedAppLink(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "fitmatch":
            return true
        case "https":
            return url.host?.lowercased() == "fitmatch.app"
        default:
            return false
        }
    }

    static func route(from url: URL) -> String {
        if url.scheme?.lowercased() == "fitmatch",
           let host = url.host,
           !host.isEmpty {
            return host.lowercased()
        }

        let pathComponents = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .map(String.init)

        return pathComponents.first?.lowercased() ?? ""
    }
}
