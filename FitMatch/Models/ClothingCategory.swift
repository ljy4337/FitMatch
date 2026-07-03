import Foundation

enum ClothingCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case top = "상의"
    case shirt = "셔츠"
    case knit = "니트"
    case outer = "아우터"
    case pants = "팬츠"
    case dress = "원피스"
    case other = "기타"

    var id: String { rawValue }
}
