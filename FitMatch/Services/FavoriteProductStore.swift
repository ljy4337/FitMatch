import Foundation

struct FavoriteProductStore {
    private let defaults: UserDefaults
    private let key = "FitMatch.favoriteProductURLs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func favoriteURLs() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func isFavorite(_ urlString: String?) -> Bool {
        guard let normalizedURL = normalizedURLString(urlString) else {
            return false
        }

        return favoriteURLs().contains(normalizedURL)
    }

    func toggle(_ urlString: String?) -> Bool {
        guard let normalizedURL = normalizedURLString(urlString) else {
            return false
        }

        var favorites = favoriteURLs()
        if favorites.contains(normalizedURL) {
            favorites.remove(normalizedURL)
            defaults.set(Array(favorites), forKey: key)
            return false
        } else {
            favorites.insert(normalizedURL)
            defaults.set(Array(favorites), forKey: key)
            return true
        }
    }

    private func normalizedURLString(_ urlString: String?) -> String? {
        guard let value = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}
