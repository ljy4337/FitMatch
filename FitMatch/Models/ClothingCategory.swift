import Foundation

/// A user-owned Closet item belongs to exactly one comparison group.
/// Retailer category mapping is server-owned; these values are the stable
/// presentation codes shared by the registration and edit surfaces.
enum FitMatchComparisonGroup: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case tops = "A"
    case outerwear = "B"
    case pants = "C"
    case skirts = "D"
    case onePiece = "E"
    case innerwear = "F"
    case homewear = "G"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tops: return "상의"
        case .outerwear: return "아우터"
        case .pants: return "바지"
        case .skirts: return "스커트"
        case .onePiece: return "원피스·한벌옷"
        case .innerwear: return "이너웨어"
        case .homewear: return "홈웨어·파자마"
        }
    }

    static func legacyFallback(
        category: ClothingCategory,
        detailCategory: ClosetDetailCategory
    ) -> FitMatchComparisonGroup? {
        let detail = detailCategory.rawValue.lowercased()
        if detail.contains("스커트") || detail.contains("치마") { return .skirts }
        if detail.contains("파자마") || detail.contains("홈웨어") { return .homewear }
        switch category.serviceGroup {
        case .top: return .tops
        case .outer: return .outerwear
        case .bottom: return .pants
        case .dress: return .onePiece
        case .underwear: return .innerwear
        default: return nil
        }
    }
}

enum ClothingCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case top = "상의"
    case bottom = "하의"
    case outer = "아우터"
    case pants = "팬츠"
    case dress = "원피스"
    case underwear = "속옷"
    case shirt = "셔츠"
    case knit = "니트"
    case shoes = "신발"
    case accessory = "액세서리"
    case other = "기타"

    var id: String { rawValue }

    var taxonomyCode: String {
        switch serviceGroup {
        case .top: return "tops"
        case .bottom: return "bottoms"
        case .outer: return "outerwear"
        case .dress: return "dresses"
        case .underwear: return "underwear"
        case .shoes: return "shoes"
        case .accessory: return "accessories"
        case .other: return "other"
        case .pants, .shirt, .knit: return serviceGroup.taxonomyCode
        }
    }

    static func fromTaxonomyCode(_ code: String) -> ClothingCategory {
        switch code {
        case "tops": return .top
        case "bottoms", "leggings", "skirts": return .bottom
        case "outerwear": return .outer
        case "dresses": return .dress
        case "underwear": return .underwear
        case "shoes": return .shoes
        case "accessories": return .accessory
        default: return .other
        }
    }

    nonisolated var serviceGroup: ClothingCategory {
        switch self {
        case .pants:
            return .bottom
        case .shirt, .knit:
            return .top
        default:
            return self
        }
    }

    static func closetCategories(for gender: UserGender) -> [ClothingCategory] {
        switch gender {
        case .men:
            return [.top, .bottom, .outer, .underwear, .shoes, .accessory, .other]
        case .women:
            return [.top, .bottom, .outer, .dress, .underwear, .shoes, .accessory, .other]
        case .kids, .baby, .unisex, .unknown:
            return [.top, .bottom, .outer, .dress, .underwear, .shoes, .accessory, .other]
        }
    }
}
