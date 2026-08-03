import Foundation

enum CanonicalTaxonomyDecision: String, Codable, Equatable {
    case confirmed
    case reviewRequired = "review_required"
    case rejected
    case unsupported
    case notFound = "not_found"
}

struct CanonicalLengthAxes: Codable, Equatable {
    let sleeve: String
    let pants: String
    let leggings: String
    let skirt: String
    let body: String
}

struct CanonicalComparisonProfile: Codable, Equatable {
    let decision: CanonicalTaxonomyDecision
    let semanticCategoryCode: String?
    let semanticGarmentType: String?
    let comparisonFamily: String?
    let appComparisonFamily: String?
    let lengthAxes: CanonicalLengthAxes
    let constructionType: String
    let eligibility: Bool
    let requiredMeasurements: [String]
    let optionalMeasurements: [String]
    let excludedMeasurements: [String]
    let policyVersion: String
    let resolutionMethod: String
    let sourceIdentity: String?

    var appGarmentFamily: ComparisonGarmentFamily? {
        guard let comparisonFamily = appComparisonFamily ?? comparisonFamily else { return nil }
        let transformed: String
        switch comparisonFamily {
        case "knit", "cardigan", "knit_cardigan": transformed = "knit_cardigan"
        case "anorak", "blazer", "blouson", "coat", "fleece", "jacket", "mouton",
             "outerwear", "padded_vest", "padding", "trench_coat", "windbreaker": transformed = "outerwear"
        case "short_pants", "cropped_pants", "three_quarter_pants", "nine_tenths_pants", "long_pants", "slacks", "training_pants": transformed = "pants"
        case "standard_pants": transformed = "pants"
        case "knit_sweater": transformed = "knit_cardigan"
        case "shirt_blouse", "polo_shirt": transformed = "shirt"
        case "base_layer_top": transformed = "underwear"
        case "short_leggings", "three_quarter_leggings", "nine_tenths_leggings", "long_leggings": transformed = "leggings"
        default: transformed = comparisonFamily
        }
        return ComparisonGarmentFamily(rawValue: transformed)
    }

    var appLengthType: ComparisonLengthType? {
        let candidates = [lengthAxes.sleeve, lengthAxes.pants, lengthAxes.leggings, lengthAxes.skirt, lengthAxes.body]
        guard let value = candidates.first(where: { $0 != "unknown" && $0 != "not_applicable" }) else { return nil }
        switch value {
        case "sleeveless": return .sleeveless
        case "short_sleeve", "short_pants", "short_leggings", "short": return .short
        case "three_quarter_sleeve", "three_quarter_pants", "three_quarter_leggings", "three_quarter": return .threeQuarter
        case "cropped", "cropped_pants": return .cropped
        case "nine_tenths", "nine_tenths_pants", "nine_tenths_leggings": return .nineTenths
        case "long_sleeve", "long_pants", "long_leggings", "long": return .long
        default: return nil
        }
    }

    var appConstructionType: ComparisonConstructionType? {
        ComparisonConstructionType(rawValue: constructionType)
    }
}

enum CanonicalProfileSnapshotCoder {
    static func encode(_ profile: CanonicalComparisonProfile?) -> String? {
        guard let profile, let data = try? JSONEncoder().encode(profile) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ value: String?) -> CanonicalComparisonProfile? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CanonicalComparisonProfile.self, from: data)
    }
}
