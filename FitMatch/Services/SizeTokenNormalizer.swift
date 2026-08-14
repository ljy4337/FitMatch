import Foundation

nonisolated enum SizeTokenNormalizer {
    private static let letterSizes = Set([
        "XXS", "XS", "S", "M", "L", "XL", "XXL", "XXXL",
        "2XL", "3XL", "4XL", "5XL", "WM", "FREE", "ONE"
    ])

    static func normalizedKey(for rawValue: String) -> String {
        displayName(for: rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "–", with: "~")
            .replacingOccurrences(of: "—", with: "~")
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    static func displayName(for rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = value.range(
            of: #"^\d+\.\s+"#,
            options: .regularExpression
        ) else { return value }
        let candidate = String(value[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidWithoutDisplayNormalization(candidate) else { return value }
        return candidate
    }

    static func isValid(_ rawValue: String) -> Bool {
        let value = normalizedKey(for: rawValue)
        return isValidNormalizedKey(value)
    }

    private static func isValidWithoutDisplayNormalization(_ rawValue: String) -> Bool {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "–", with: "~")
            .replacingOccurrences(of: "—", with: "~")
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        return isValidNormalizedKey(value)
    }

    private static func isValidNormalizedKey(_ value: String) -> Bool {
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
        if let components = letterSizeWithDescriptorComponents(value) {
            return letterSizes.contains(components.letter)
                && isValidDescriptor(components.descriptor)
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

    private static func letterSizeWithDescriptorComponents(
        _ value: String
    ) -> (letter: String, descriptor: String)? {
        guard let open = value.firstIndex(of: "("),
              value.last == ")" else { return nil }
        let letter = String(value[..<open])
        let descriptor = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
        guard letterSizes.contains(letter) else { return nil }
        return (letter, descriptor)
    }

    private static func isValidDescriptor(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 12 else { return false }
        return value.allSatisfy {
            $0.isLetter || $0.isNumber || ["&", ".", "_", "-"].contains($0)
        }
    }
}
