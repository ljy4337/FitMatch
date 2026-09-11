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

    /// 기존 저장값과 테스트를 디코딩하기 위한 호환 case는 유지하되,
    /// 제거된 기준 옷 정렬을 사용자 선택지에는 노출하지 않는다.
    static let allCases: [FitMatchClosetSortOption] = [
        .recent, .oldest, .brand, .category
    ]

    var title: String {
        switch self {
        case .recent: return "최근 등록"
        case .oldest: return "오래된순"
        case .brand: return "브랜드순"
        case .category: return "그룹순"
        case .basisFirst: return "이전 기준 옷 우선"
        }
    }
}

enum FitMatchClosetPresentation {
    static func activeItems(from cachedItems: [UserFit]) -> [UserFit] {
        cachedItems.filter(\.isActiveClosetItem)
    }

    static func displayedItems(
        from cachedItems: [UserFit],
        comparisonGroup: FitMatchComparisonGroup?,
        brand: String?,
        sort: FitMatchClosetSortOption
    ) -> [UserFit] {
        let filtered = activeItems(from: cachedItems).filter { item in
            let matchesGroup = comparisonGroup == nil
                || item.comparisonGroup == comparisonGroup
            let matchesBrand = brand == nil || item.brandName == brand
            return matchesGroup && matchesBrand
        }
        return sorted(filtered, by: sort, usesComparisonGroupOrder: true)
    }

    /// Retained for manual-registration and existing headless contracts.
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

        return sorted(filtered, by: sort, usesComparisonGroupOrder: false)
    }

    private static func sorted(
        _ items: [UserFit],
        by sort: FitMatchClosetSortOption,
        usesComparisonGroupOrder: Bool
    ) -> [UserFit] {
        switch sort {
        case .recent:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return items.sorted { $0.createdAt < $1.createdAt }
        case .brand:
            return items.sorted { $0.brandName < $1.brandName }
        case .category:
            guard usesComparisonGroupOrder else {
                return items.sorted { $0.category.rawValue < $1.category.rawValue }
            }
            return items.sorted {
                let left = $0.comparisonGroup?.rawValue ?? "ZZ"
                let right = $1.comparisonGroup?.rawValue ?? "ZZ"
                if left != right { return left < right }
                return $0.createdAt > $1.createdAt
            }
        case .basisFirst:
            return items.sorted {
                if $0.isRepresentative != $1.isRepresentative {
                    return $0.isRepresentative && !$1.isRepresentative
                }
                return $0.createdAt > $1.createdAt
            }
        }
    }
}
