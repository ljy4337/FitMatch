import Foundation

enum AppGroupConfig {
    static let identifier = "group.io.github.ljy4337.FitMatch"
}

struct SharedURLStore {
    private enum Key {
        static let pendingProductURL = "pendingProductURL"
        static let pendingProductURLCreatedAt = "pendingProductURLCreatedAt"
    }

    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: AppGroupConfig.identifier) ?? .standard
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

    func consumePendingProductURL() -> String? {
        guard let urlString = pendingProductURL() else {
            return nil
        }

        defaults.removeObject(forKey: Key.pendingProductURL)
        defaults.removeObject(forKey: Key.pendingProductURLCreatedAt)
        return urlString
    }
}
