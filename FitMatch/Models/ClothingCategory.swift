import Foundation

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

    var serviceGroup: ClothingCategory {
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
