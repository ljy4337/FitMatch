import Foundation

enum UserGender: String, CaseIterable, Identifiable, Codable, Hashable {
    case men = "남성"
    case women = "여성"
    case kids = "키즈"
    case baby = "베이비"
    case unisex = "공용"
    case unknown = "미분류"

    var id: String { rawValue }

    var taxonomyCode: String {
        switch self {
        case .men: return "male"
        case .women: return "female"
        case .unisex: return "unisex"
        case .kids, .baby: return "kids_unisex"
        case .unknown: return "unknown"
        }
    }

    static func fromTaxonomyCode(_ code: String) -> UserGender {
        switch code {
        case "male", "boys": return .men
        case "female", "girls": return .women
        case "unisex": return .unisex
        case "kids_unisex": return .kids
        default: return .unknown
        }
    }

    static func productTarget(from codes: [String]) -> UserGender {
        let normalizedCodes = codes
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
            }
            .filter { !$0.isEmpty }

        guard !normalizedCodes.isEmpty else {
            return .unknown
        }

        if normalizedCodes.contains(where: { ["UNISEX", "COMMON", "U", "공용"].contains($0) }) {
            return .unisex
        }
        if normalizedCodes.contains(where: { ["BABY", "베이비"].contains($0) }) {
            return .baby
        }
        if normalizedCodes.contains(where: { ["KIDS", "KID", "키즈"].contains($0) }) {
            return .kids
        }
        if normalizedCodes.contains(where: { ["WOMEN", "WOMAN", "FEMALE", "F", "여성"].contains($0) }) {
            return .women
        }
        if normalizedCodes.contains(where: { ["MEN", "MAN", "MALE", "M", "남성"].contains($0) }) {
            return .men
        }

        return .unknown
    }
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
    case threeQuarterSleeve = "7부"
    case shortPants = "숏팬츠"
    case croppedPants = "크롭"
    case threeQuarterPants = "7부 팬츠"
    case nineTenthsPants = "9부"
    case longPants = "긴바지"
    case shortLeggings = "숏 레깅스"
    case threeQuarterLeggings = "7부 레깅스"
    case nineTenthsLeggings = "9부 레깅스"
    case longLeggings = "롱 레깅스"
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
    case windbreaker = "바람막이"
    case anorak = "아노락"
    case blazer = "블레이저"
    case blouson = "블루종"
    case fleece = "플리스"
    case lightPadding = "경량패딩"
    case shortPadding = "숏패딩"
    case longPadding = "롱패딩"
    case trenchCoat = "트렌치코트"
    case mouton = "무스탕"
    case paddedVest = "패딩조끼"
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

    static func fromTaxonomyCode(_ code: String) -> ClosetDetailCategory {
        switch code {
        case "sleeveless": return .sleeveless
        case "short_sleeve": return .shortSleeve
        case "three_quarter_sleeve": return .threeQuarterSleeve
        case "long_sleeve": return .longSleeve
        case "short_pants": return .shortPants
        case "shorts": return .shorts
        case "cropped_pants": return .croppedPants
        case "three_quarter_pants": return .threeQuarterPants
        case "nine_tenths_pants": return .nineTenthsPants
        case "long_pants": return .longPants
        case "short_leggings": return .shortLeggings
        case "three_quarter_leggings": return .threeQuarterLeggings
        case "nine_tenths_leggings": return .nineTenthsLeggings
        case "long_leggings": return .longLeggings
        case "cardigan": return .cardigan
        case "windbreaker": return .windbreaker
        case "anorak": return .anorak
        case "jacket": return .jacket
        case "blazer": return .blazer
        case "jumper": return .jumper
        case "blouson": return .blouson
        case "fleece": return .fleece
        case "light_padding": return .lightPadding
        case "short_padding": return .shortPadding
        case "padding": return .padding
        case "long_padding": return .longPadding
        case "coat": return .coat
        case "trench_coat": return .trenchCoat
        case "mouton": return .mouton
        case "vest": return .vest
        case "padded_vest": return .paddedVest
        case "skirt": return .skirt
        case "one_piece": return .onePiece
        case "underwear": return .underwear
        case "men_briefs": return .menBriefs
        case "men_trunks": return .menTrunks
        case "men_undershirt": return .menUndershirt
        case "women_bra": return .womenBra
        case "women_panty": return .womenPanty
        case "women_camisole": return .womenCamisole
        case "women_slip": return .womenSlip
        case "sneakers": return .sneakers
        case "running_shoes": return .runningShoes
        case "loafers": return .loafers
        case "boots": return .boots
        case "sandals": return .sandals
        case "heels": return .heels
        case "watch": return .watch
        case "ring": return .ring
        case "bracelet": return .bracelet
        case "necklace": return .necklace
        case "bag": return .bag
        case "hat": return .hat
        case "belt": return .belt
        case "scarf": return .scarf
        case "socks": return .socks
        case "loungewear": return .loungewear
        case "sportswear": return .sportswear
        case "swimwear": return .swimwear
        case "uniform": return .uniform
        case "costume": return .costume
        default: return .other
        }
    }

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
            case .kids, .baby, .unisex, .unknown:
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
