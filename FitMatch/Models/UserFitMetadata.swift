import Foundation

enum UserGender: String, CaseIterable, Identifiable, Codable, Hashable {
    case men = "남성"
    case women = "여성"
    case unisex = "공용"

    var id: String { rawValue }
}

enum FitPreference: String, CaseIterable, Identifiable, Codable, Hashable {
    case slim = "슬림"
    case regular = "정핏"
    case semiOver = "세미오버"
    case over = "오버"
    case boxy = "박시"

    var id: String { rawValue }
}

enum ProductSourceType: String, CaseIterable, Identifiable, Codable, Hashable {
    case officialStore
    case marketplace
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .officialStore: return "공식몰"
        case .marketplace: return "쇼핑 플랫폼"
        case .manual: return "직접 입력"
        }
    }

    static let officialStoreNames = ["유니클로", "자라", "COS", "H&M", "나이키", "아디다스"]
    static let marketplaceNames = ["무신사", "29CM", "W컨셉", "쿠팡", "지그재그"]
}

enum ClosetDetailCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case sleeveless = "민소매"
    case shortSleeve = "반팔"
    case longSleeve = "긴팔"
    case shirt = "셔츠"
    case blouse = "블라우스"
    case knitTop = "니트"
    case cardigan = "가디건"
    case vest = "베스트"
    case sweatshirt = "스웨트"
    case hoodie = "후드"
    case denim = "데님"
    case slacks = "슬랙스"
    case shorts = "반바지"
    case trainingPants = "트레이닝 팬츠"
    case skirt = "스커트"
    case leggings = "레깅스"
    case jumper = "점퍼"
    case jacket = "재킷"
    case coat = "코트"
    case padding = "패딩"
    case underwear = "속옷"
    case menBriefs = "남성 브리프"
    case menTrunks = "남성 트렁크"
    case menUndershirt = "남성 런닝"
    case womenBra = "브라"
    case womenPanty = "팬티"
    case womenCamisole = "캐미솔"
    case womenSlip = "슬립"
    case onePiece = "원피스"
    case sneakers = "스니커즈"
    case runningShoes = "러닝화"
    case loafers = "로퍼"
    case boots = "부츠"
    case sandals = "샌들"
    case heels = "힐"
    case watch = "시계"
    case ring = "반지"
    case bracelet = "팔찌"
    case necklace = "목걸이"
    case bag = "가방"
    case hat = "모자"
    case belt = "벨트"
    case scarf = "스카프"
    case socks = "양말"
    case sportswear = "스포츠웨어"
    case swimwear = "수영복"
    case loungewear = "라운지웨어"
    case uniform = "유니폼"
    case costume = "코스튬"
    case other = "기타"

    var id: String { rawValue }

    static func options(for category: ClothingCategory, gender: UserGender) -> [ClosetDetailCategory] {
        switch category.serviceGroup {
        case .top:
            var options: [ClosetDetailCategory] = [.sleeveless, .shortSleeve, .longSleeve, .shirt, .knitTop, .sweatshirt, .hoodie]
            if gender == .women || gender == .unisex {
                options.insert(.blouse, at: 4)
            }
            return options + [.other]
        case .bottom:
            var options: [ClosetDetailCategory] = [.denim, .slacks, .shorts, .trainingPants]
            if gender == .women || gender == .unisex {
                options += [.skirt, .leggings]
            }
            return options + [.other]
        case .outer:
            return [.jumper, .jacket, .coat, .padding, .cardigan, .vest, .other]
        case .dress:
            return [.onePiece, .other]
        case .underwear:
            switch gender {
            case .men:
                return [.menBriefs, .menTrunks, .menUndershirt, .socks, .other]
            case .women:
                return [.womenBra, .womenPanty, .womenCamisole, .womenSlip, .socks, .other]
            case .unisex:
                return [.underwear, .menBriefs, .menTrunks, .womenBra, .womenPanty, .socks, .other]
            }
        case .shoes:
            var options: [ClosetDetailCategory] = [.sneakers, .runningShoes, .loafers, .boots, .sandals]
            if gender == .women || gender == .unisex {
                options.append(.heels)
            }
            return options + [.other]
        case .accessory:
            return [.watch, .ring, .bracelet, .necklace, .bag, .hat, .belt, .scarf, .socks, .other]
        case .other:
            return [.sportswear, .swimwear, .loungewear, .uniform, .costume, .other]
        case .pants, .shirt, .knit:
            return options(for: category.serviceGroup, gender: gender)
        }
    }
}
