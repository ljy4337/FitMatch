import Foundation

struct GarmentMeasurements: Codable, Equatable, Hashable {
    var shoulder: Double
    var chest: Double
    var totalLength: Double
    var sleeveLength: Double
    var waist: Double = 0
    var hip: Double = 0
    var thigh: Double = 0
    var rise: Double = 0
    var hem: Double = 0
    var footLength: Double = 0
    var underBust: Double = 0

    var isEmpty: Bool {
        shoulder == 0 && chest == 0 && totalLength == 0 && sleeveLength == 0
            && waist == 0 && hip == 0 && thigh == 0 && rise == 0 && hem == 0 && footLength == 0 && underBust == 0
    }

    func distance(to other: GarmentMeasurements) -> Double {
        abs(shoulder - other.shoulder)
            + abs(chest - other.chest)
            + abs(totalLength - other.totalLength)
            + abs(sleeveLength - other.sleeveLength)
            + abs(waist - other.waist)
            + abs(hip - other.hip)
            + abs(thigh - other.thigh)
            + abs(rise - other.rise)
            + abs(hem - other.hem)
            + abs(footLength - other.footLength)
            + abs(underBust - other.underBust)
    }

    func value(for kind: MeasurementKind) -> Double {
        switch kind {
        case .shoulder: return shoulder
        case .chest: return chest
        case .totalLength: return totalLength
        case .sleeveLength: return sleeveLength
        case .waist: return waist
        case .hip: return hip
        case .thigh: return thigh
        case .rise: return rise
        case .hem: return hem
        case .footLength: return footLength
        case .underBust: return underBust
        }
    }
}

enum MeasurementKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case shoulder
    case chest
    case totalLength
    case sleeveLength
    case waist
    case hip
    case thigh
    case rise
    case hem
    case footLength
    case underBust

    var id: String { title }

    var title: String {
        switch self {
        case .shoulder: return "어깨너비"
        case .chest: return "가슴단면"
        case .totalLength: return "총장"
        case .sleeveLength: return "소매길이"
        case .waist: return "허리단면"
        case .hip: return "엉덩이단면"
        case .thigh: return "허벅지단면"
        case .rise: return "밑위"
        case .hem: return "밑단단면"
        case .footLength: return "발길이"
        case .underBust: return "밑가슴둘레"
        }
    }

    var placeholder: String {
        switch self {
        case .shoulder: return "48"
        case .chest: return "56"
        case .totalLength: return "70"
        case .sleeveLength: return "62"
        case .waist: return "39"
        case .hip: return "52"
        case .thigh: return "31"
        case .rise: return "29"
        case .hem: return "22"
        case .footLength: return "27"
        case .underBust: return "75"
        }
    }
}

extension ClothingCategory {
    var measurementKinds: [MeasurementKind] {
        switch serviceGroup {
        case .top, .outer:
            return [.totalLength, .shoulder, .chest, .sleeveLength]
        case .bottom:
            return [.totalLength, .waist, .hip, .thigh, .rise, .hem]
        case .dress:
            return [.shoulder, .chest, .totalLength, .sleeveLength, .waist, .hip]
        case .underwear:
            return [.chest, .totalLength, .waist, .hip]
        case .shoes:
            return [.footLength]
        case .accessory:
            return []
        case .other:
            return [.totalLength, .chest, .waist]
        case .pants, .shirt, .knit:
            return serviceGroup.measurementKinds
        }
    }

    func measurementKinds(detailCategory: ClosetDetailCategory, gender: UserGender) -> [MeasurementKind] {
        guard serviceGroup == .underwear else {
            return measurementKinds
        }

        switch detailCategory {
        case .menBriefs, .menTrunks:
            return [.waist, .hip]
        case .menUndershirt:
            return [.chest, .totalLength]
        case .womenBra:
            return [.underBust, .chest]
        case .womenPanty:
            return [.waist, .hip]
        case .womenCamisole:
            return [.underBust, .chest, .totalLength]
        case .womenSlip:
            return [.underBust, .chest, .waist, .hip, .totalLength]
        case .socks:
            return [.footLength]
        default:
            switch gender {
            case .men:
                return [.waist, .hip]
            case .women:
                return [.underBust, .chest, .waist, .hip]
            case .kids, .baby, .unisex, .unknown:
                return [.waist, .hip]
            }
        }
    }
}
