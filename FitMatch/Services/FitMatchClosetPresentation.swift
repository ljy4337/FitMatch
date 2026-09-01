import Foundation

/// Non-visual Closet presentation policy shared by `MyClosetView` and
/// headless tests.  It does not decide comparison eligibility; it only keeps
/// inactive/history-only rows out of the user-managed Closet list and applies
/// the View's existing filter/sort choices deterministically.
enum FitMatchClosetSortOption: String, CaseIterable {
    case recent
    case oldest
    case brand
    case category
    case basisFirst

    var title: String {
        switch self {
        case .recent: return "최근 등록"
        case .oldest: return "오래된순"
        case .brand: return "브랜드순"
        case .category: return "카테고리순"
        case .basisFirst: return "기준 옷 우선"
        }
    }
}

enum FitMatchClosetPresentation {
    static func activeItems(from cachedItems: [UserFit]) -> [UserFit] {
        cachedItems.filter(\.isActiveClosetItem)
    }

    static func displayedItems(
        from cachedItems: [UserFit],
        category: ClothingCategory?,
        brand: String?,
        sort: FitMatchClosetSortOption
    ) -> [UserFit] {
        let filtered = activeItems(from: cachedItems).filter { item in
            let matchesCategory = category == nil || item.category == category
            let matchesBrand = brand == nil || item.brandName == brand
            return matchesCategory && matchesBrand
        }

        switch sort {
        case .recent:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .brand:
            return filtered.sorted { $0.brandName < $1.brandName }
        case .category:
            return filtered.sorted { $0.category.rawValue < $1.category.rawValue }
        case .basisFirst:
            return filtered.sorted {
                if $0.isRepresentative != $1.isRepresentative {
                    return $0.isRepresentative && !$1.isRepresentative
                }
                return $0.createdAt > $1.createdAt
            }
        }
    }
}
