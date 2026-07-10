import Foundation
import UIKit

struct SmartClipboardCandidate: Identifiable, Equatable {
    let urlString: String
    let providerName: String

    var id: String { urlString }
}

struct SmartClipboardService {
    private let pasteboard: UIPasteboard
    private let defaults: UserDefaults

    private let lastHandledURLKey = "FitMatch.SmartClipboard.lastHandledURL"
    private let mutedDateKey = "FitMatch.SmartClipboard.mutedDate"

    init(
        pasteboard: UIPasteboard = .general,
        defaults: UserDefaults = .standard
    ) {
        self.pasteboard = pasteboard
        self.defaults = defaults
    }

    func detectCandidate() -> SmartClipboardCandidate? {
        guard !isMutedToday(),
              let text = pasteboard.string,
              let urlString = extractURLString(from: text),
              urlString != defaults.string(forKey: lastHandledURLKey),
              let providerName = supportedProviderName(for: urlString) else {
            return nil
        }

        return SmartClipboardCandidate(urlString: urlString, providerName: providerName)
    }

    func markHandled(_ candidate: SmartClipboardCandidate) {
        defaults.set(candidate.urlString, forKey: lastHandledURLKey)
    }

    func muteToday() {
        defaults.set(Date().timeIntervalSince1970, forKey: mutedDateKey)
    }

    private func isMutedToday() -> Bool {
        let timestamp = defaults.double(forKey: mutedDateKey)
        guard timestamp > 0 else {
            return false
        }

        return Calendar.current.isDateInToday(Date(timeIntervalSince1970: timestamp))
    }

    private func extractURLString(from text: String) -> String? {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }

        return String(text[range])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\"'<>"))
    }

    private func supportedProviderName(for urlString: String) -> String? {
        let value = urlString.lowercased()

        if value.contains("musinsa") { return "무신사" }
        if value.contains("29cm") { return "29CM" }
        if value.contains("uniqlo") { return "유니클로" }
        if value.contains("coupang") { return "쿠팡" }
        if value.contains("naver") { return "네이버쇼핑" }

        return nil
    }
}
