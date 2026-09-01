import Foundation

/// Non-authoritative presentation rules shared by Home, History, and the
/// headless release checks. This never decides comparison eligibility or
/// alters immutable comparison evidence.
enum FitMatchHistoryScope: String, CaseIterable {
    case all
    case favorite

    var title: String {
        switch self {
        case .all: return "전체 기록"
        case .favorite: return "관심상품"
        }
    }
}

enum FitMatchHistorySortOption: String, CaseIterable {
    case latest
    case oldest
    case brand
    case fitConfidence

    var title: String {
        switch self {
        case .latest: return "최신순"
        case .oldest: return "오래된순"
        case .brand: return "브랜드순"
        case .fitConfidence: return "사이즈 유사도 높은순"
        }
    }
}

enum FitMatchHistoryPresentation {
    /// Home is a recent-comparison surface, not a unique-product surface.
    /// A completed comparison has its own immutable history ID, so repeated
    /// comparisons of the same retailer product must remain independently
    /// visible.
    static func recentHistories(
        from histories: [RecommendationHistory],
        limit: Int = 5
    ) -> [RecommendationHistory] {
        Array(
            histories
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(limit)
        )
    }

    static func displayedHistories(
        from histories: [RecommendationHistory],
        searchText: String,
        scope: FitMatchHistoryScope,
        category: ClothingCategory?,
        favoriteURLs: Set<String>,
        sort: FitMatchHistorySortOption
    ) -> [RecommendationHistory] {
        let normalizedQuery = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let filtered = histories.filter { history in
            let matchesCategory = category == nil || history.product.category == category
            guard matchesCategory else { return false }

            let isFavorite = history.product.sourceURLString.map(favoriteURLs.contains) ?? false
            guard scope == .all || isFavorite else { return false }

            guard !normalizedQuery.isEmpty else { return true }
            let searchableValues = [
                history.productBrandNameForDisplay,
                history.productNameForDisplay,
                history.product.sourceDisplayName,
                history.product.productCode ?? ""
            ]
            return searchableValues.contains { value in
                value.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ).contains(normalizedQuery)
            }
        }

        switch sort {
        case .latest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .brand:
            return filtered.sorted {
                $0.productBrandNameForDisplay.localizedCaseInsensitiveCompare(
                    $1.productBrandNameForDisplay
                ) == .orderedAscending
            }
        case .fitConfidence:
            return filtered.sorted { $0.recommendationScore > $1.recommendationScore }
        }
    }
}

/// Data-level search projection shared by GlobalSearchView and headless
/// acceptance. It filters already-owned local presentation models only; it
/// does not resolve authority, mutate storage, or make comparison decisions.
enum FitMatchGlobalSearchPresentation {
    static func closetResults(
        from cachedUserFits: [UserFit],
        searchText: String,
        limit: Int = 8
    ) -> [UserFit] {
        let normalized = normalizedQuery(searchText)
        let active = cachedUserFits.filter(\.isActiveClosetItem)
        guard !normalized.isEmpty else {
            return Array(active.prefix(limit))
        }

        return active.filter { item in
            item.brandName.lowercased().contains(normalized)
                || item.productName.lowercased().contains(normalized)
                || item.category.rawValue.lowercased().contains(normalized)
                || item.detailCategory.rawValue.lowercased().contains(normalized)
                || item.sizeName.lowercased().contains(normalized)
        }
    }

    static func historyResults(
        from histories: [RecommendationHistory],
        searchText: String,
        favoriteURLs: Set<String>,
        limit: Int = 8
    ) -> [RecommendationHistory] {
        let normalized = normalizedQuery(searchText)
        guard !normalized.isEmpty else {
            return Array(histories.prefix(limit))
        }

        return histories.filter { history in
            let product = history.product
            let isFavorite = product.sourceURLString.map(favoriteURLs.contains) ?? false
            return product.displayName.lowercased().contains(normalized)
                || (product.brand?.name.lowercased().contains(normalized) ?? false)
                || product.category.rawValue.lowercased().contains(normalized)
                || history.productDetailCategory.rawValue.lowercased().contains(normalized)
                || product.sourceDisplayName.lowercased().contains(normalized)
                || (isFavorite && "관심상품".contains(normalized))
        }
    }

    private static func normalizedQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
