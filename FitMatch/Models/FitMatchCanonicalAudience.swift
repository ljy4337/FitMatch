import Foundation

/// Canonical retailer audience carried to the server authority.
///
/// `UNKNOWN` is an exact lack-of-evidence value. It is never a wildcard.
/// `GENERIC` is deliberately absent because it is a verified DB mapping scope,
/// not a product audience that an adapter is allowed to assert.
nonisolated enum FitMatchCanonicalAudience: String, Sendable {
    case men = "MEN"
    case women = "WOMEN"
    case unisex = "UNISEX"
    case kids = "KIDS"
    case baby = "BABY"
    case unknown = "UNKNOWN"

    static func code(from rawValue: String?) -> String {
        guard let rawValue else { return Self.unknown.rawValue }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        switch normalized {
        case "M", "MEN", "MAN", "MALE", "남성":
            return Self.men.rawValue
        case "W", "WOMEN", "WOMAN", "FEMALE", "여성":
            return Self.women.rawValue
        case "M,W", "UNISEX", "COMMON", "U", "공용", "젠더리스":
            return Self.unisex.rawValue
        case "KID", "KIDS":
            return Self.kids.rawValue
        case "BABY":
            return Self.baby.rawValue
        default:
            return Self.unknown.rawValue
        }
    }

    static func code(from rawValues: [String]) -> String {
        guard !rawValues.isEmpty else { return Self.unknown.rawValue }
        let codes = Set(rawValues.map { code(from: $0) })
        if codes.contains(Self.unknown.rawValue) {
            return Self.unknown.rawValue
        }
        if codes.contains(Self.unisex.rawValue)
            || (codes.contains(Self.men.rawValue) && codes.contains(Self.women.rawValue)) {
            return Self.unisex.rawValue
        }
        return codes.count == 1 ? codes.first! : Self.unknown.rawValue
    }
}
