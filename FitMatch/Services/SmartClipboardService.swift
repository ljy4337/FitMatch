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
              let urlString = ProductURLSupport.extractedURLString(from: text),
              urlString != defaults.string(forKey: lastHandledURLKey),
              let providerName = ProductURLSupport.supportedProviderName(for: urlString) else {
            return nil
        }

        return SmartClipboardCandidate(urlString: urlString, providerName: providerName)
    }

    func currentSupportedProductCandidate() -> SmartClipboardCandidate? {
        guard let text = pasteboard.string,
              let urlString = ProductURLSupport.extractedURLString(from: text),
              let providerName = ProductURLSupport.supportedProviderName(for: urlString) else {
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

}
