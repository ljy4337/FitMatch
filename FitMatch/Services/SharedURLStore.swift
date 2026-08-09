import Foundation

enum AppGroupConfig {
    static let identifier = "group.com.ljy4337.fitmatch"
}

struct SharedURLStore {
    private enum Key {
        static let pendingProductURL = "pendingProductURL"
        static let pendingProductURLCreatedAt = "pendingProductURLCreatedAt"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppGroupConfig.identifier) ?? .standard
    }

    func savePendingProductURL(_ url: URL) {
        defaults.set(url.absoluteString, forKey: Key.pendingProductURL)
        defaults.set(Date(), forKey: Key.pendingProductURLCreatedAt)
    }

    func pendingProductURL() -> String? {
        guard let urlString = defaults.string(forKey: Key.pendingProductURL), !urlString.isEmpty else {
            return nil
        }

        return urlString
    }

    @discardableResult
    func clearPendingProductURL(ifMatching expectedURLString: String? = nil) -> Bool {
        guard let currentURLString = pendingProductURL() else {
            return false
        }

        if let expectedURLString,
           currentURLString != expectedURLString {
            return false
        }

        defaults.removeObject(forKey: Key.pendingProductURL)
        defaults.removeObject(forKey: Key.pendingProductURLCreatedAt)
        return true
    }

    func consumePendingProductURL() -> String? {
        guard let urlString = pendingProductURL() else {
            return nil
        }

        clearPendingProductURL(ifMatching: urlString)
        return urlString
    }
}
