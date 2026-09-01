import Foundation
import UniformTypeIdentifiers

/// The narrow system-side boundary for a Share attachment. The extension
/// adapts `NSItemProvider` to this protocol; the user-facing traversal and
/// provider-support policy below are shared production logic.
@MainActor
protocol FitMatchShareAttachmentLoading {
    var hasURLItem: Bool { get }
    var hasPlainTextItem: Bool { get }

    func loadURLItem() async -> Any?
    func loadPlainTextItem() async -> Any?
}

/// Shared Share-extension attachment traversal. Both the extension UI and
/// headless tests call this production action, so attachment order, plain-text
/// fallback, and official-provider filtering cannot drift apart. The action
/// deliberately owns no Share Sheet UI and no App Group persistence.
@MainActor
enum FitMatchShareAttachmentExtractionAction {
    static func firstSupportedURL(
        from attachments: [any FitMatchShareAttachmentLoading]
    ) async -> URL? {
        for attachment in attachments {
            if attachment.hasURLItem,
               let url = directURL(from: await attachment.loadURLItem()),
               FitMatchProductURLRouting.provider(for: url) != nil {
                return url
            }

            if attachment.hasPlainTextItem,
               let text = text(from: await attachment.loadPlainTextItem()),
               let url = FitMatchProductURLRouting.firstSupportedURL(in: urls(in: text)) {
                return url
            }
        }
        return nil
    }

    private static func urls(in text: String) -> [URL] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return []
        }
        return detector.matches(in: text, range: range).compactMap(\.url)
    }

    private static func text(from item: Any?) -> String? {
        if let text = item as? String { return text }
        if let text = item as? NSString { return text as String }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    private static func directURL(from item: Any?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let text = text(from: item) { return URL(string: text) }
        return nil
    }
}

/// UIKit adapter used only at the actual extension boundary. It lets the
/// shared production action remain testable without imitating the app's
/// provider/URL policy in XCTest.
@MainActor
private struct FitMatchNSItemProviderAttachment: FitMatchShareAttachmentLoading {
    let provider: NSItemProvider

    var hasURLItem: Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
    }

    var hasPlainTextItem: Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
    }

    func loadURLItem() async -> Any? {
        await loadItem(for: UTType.url.identifier)
    }

    func loadPlainTextItem() async -> Any? {
        await loadItem(for: UTType.plainText.identifier)
    }

    private func loadItem(for typeIdentifier: String) async -> Any? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }
}

enum FitMatchShareAttachmentExtractor {
    static func loadFirstSupportedURL(
        from attachments: [NSItemProvider],
        completion: @escaping (URL?) -> Void
    ) {
        let loaders: [any FitMatchShareAttachmentLoading] = attachments.map {
            FitMatchNSItemProviderAttachment(provider: $0)
        }
        Task { @MainActor in
            completion(await FitMatchShareAttachmentExtractionAction.firstSupportedURL(from: loaders))
        }
    }
}
