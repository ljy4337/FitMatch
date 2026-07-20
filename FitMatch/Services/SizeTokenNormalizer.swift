import Foundation

enum SizeTokenNormalizer {
    private static let letterSizes = Set([
        "XXS", "XS", "S", "M", "L", "XL", "XXL", "XXXL",
        "2XL", "3XL", "4XL", "5XL", "WM", "FREE", "ONE"
    ])

    static func normalizedKey(for rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "–", with: "~")
            .replacingOccurrences(of: "—", with: "~")
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    static func isValid(_ rawValue: String) -> Bool {
        let value = normalizedKey(for: rawValue)
        guard !value.isEmpty, value.count <= 20 else { return false }
        if letterSizes.contains(value) { return true }
        if isNumericSize(value) { return true }
        if value.range(of: #"^\d{2,3}-\d{2,3}$"#, options: .regularExpression) != nil {
            return true
        }
        if let components = parenthesizedComponents(value) {
            return isNumericSize(components.number) && letterSizes.contains(components.letter)
                || letterSizes.contains(components.letter) && isNumericSize(components.number)
        }

        let slashParts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if slashParts.count == 2 {
            return isNumericSize(slashParts[0]) && letterSizes.contains(slashParts[1])
                || isNumericSize(slashParts[0]) && isNumericSize(slashParts[1])
        }
        if slashParts.count == 3 {
            return isNumericSize(slashParts[0])
                && letterSizes.contains(slashParts[1])
                && isNumericRange(slashParts[2])
        }
        return false
    }

    private static func isNumericSize(_ value: String) -> Bool {
        guard value.range(of: #"^\d{2,3}$"#, options: .regularExpression) != nil else {
            return false
        }
        return true
    }

    private static func isNumericRange(_ value: String) -> Bool {
        value.range(of: #"^\d{2,3}~\d{2,3}$"#, options: .regularExpression) != nil
    }

    private static func parenthesizedComponents(
        _ value: String
    ) -> (number: String, letter: String)? {
        guard let open = value.firstIndex(of: "("),
              value.last == ")",
              value[value.index(after: open)..<value.index(before: value.endIndex)].contains(where: { !$0.isWhitespace })
        else { return nil }
        let outside = String(value[..<open])
        let inside = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
        if isNumericSize(outside), letterSizes.contains(inside) {
            return (outside, inside)
        }
        if letterSizes.contains(outside), isNumericSize(inside) {
            return (inside, outside)
        }
        return nil
    }
}
