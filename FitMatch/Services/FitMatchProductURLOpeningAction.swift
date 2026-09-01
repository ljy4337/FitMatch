import Foundation

/// The non-visual decision behind opening a product page from a completed
/// Result. The View owns `openURL`; this action owns only the existing
/// provider-specific destination/fallback choice so it is shared by the
/// production caller and headless release tests.
enum FitMatchProductURLOpeningAction {
    enum Destination: Equatable {
        case web(URL)
        case musinsaApp(appURL: URL, fallbackWebURL: URL)
    }

    static func destination(for product: Product) -> Destination? {
        guard let urlString = product.sourceURLString,
              let webURL = URL(string: urlString) else {
            return nil
        }

        guard isMusinsa(product), let appURL = musinsaAppURL(for: webURL) else {
            return .web(webURL)
        }
        return .musinsaApp(appURL: appURL, fallbackWebURL: webURL)
    }

    private static func isMusinsa(_ product: Product) -> Bool {
        product.sourceDisplayName.localizedCaseInsensitiveContains("무신사")
            || product.sourceDisplayName.localizedCaseInsensitiveContains("musinsa")
            || product.sourceURLString?.localizedCaseInsensitiveContains("musinsa") == true
    }

    private static func musinsaAppURL(for webURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "musinsaad"
        components.host = "web"
        components.queryItems = [
            URLQueryItem(name: "link", value: webURL.absoluteString)
        ]
        return components.url
    }
}
