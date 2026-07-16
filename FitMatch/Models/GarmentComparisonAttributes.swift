import Foundation

enum ComparisonLengthType: String, Codable, Equatable {
    case sleeveless
    case short = "short_sleeve"
    case long = "long_sleeve"
    case unknown

    var displayName: String {
        switch self {
        case .sleeveless: return "민소매"
        case .short: return "반팔"
        case .long: return "긴팔"
        case .unknown: return ""
        }
    }
}

enum ComparisonGarmentFamily: String, Codable, Equatable {
    case knitCardigan = "knit_cardigan"
    case tshirt
    case shirt
    case sweatshirt
    case hoodie
    case pants
    case denim
    case skirt
    case outerwear
    case underwear
    case dress
    case shoes
    case accessory
    case unknown

    var displayName: String {
        switch self {
        case .knitCardigan: return "니트/가디건"
        case .tshirt: return "티셔츠"
        case .shirt: return "셔츠/블라우스"
        case .sweatshirt: return "스웨트"
        case .hoodie: return "후드"
        case .pants: return "팬츠"
        case .denim: return "데님"
        case .skirt: return "스커트"
        case .outerwear: return "아우터"
        case .underwear: return "속옷"
        case .dress: return "원피스"
        case .shoes: return "신발"
        case .accessory: return "액세서리"
        case .unknown: return "옷"
        }
    }
}

enum ComparisonConstructionType: String, Codable, Equatable {
    case setIn = "set_in"
    case raglan
    case unknown
}
