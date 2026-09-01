import Foundation

/// Validates user-entered product-link text before a registration or compare
/// flow starts parser/network work. Views use this narrow boundary so a
/// headless caller can exercise the same supported-provider gate without
/// reproducing the view's private button closure.
enum FitMatchProductLinkInput {
    enum Validation: Equatable {
        case empty
        case unsupported
        case supported(URL)

        var canStartLoad: Bool {
            if case .supported = self { return true }
            return false
        }
    }

    /// The product-entry action needs a terminal, user-facing outcome before
    /// it creates a parser or networking task.  Both Home/Compare and
    /// headless callers use this so an empty, malformed, unsupported, or COS
    /// URL cannot disappear as a silent no-op.
    enum EntryOutcome: Equatable {
        case begin(URL)
        case blocked(String)
    }

    static func validate(_ rawValue: String) -> Validation {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .empty }
        guard let url = URL(string: normalized),
              ProductURLSupport.isSupportedProductURL(normalized) else {
            return .unsupported
        }
        return .supported(url)
    }

    static func entryOutcome(for rawValue: String) -> EntryOutcome {
        switch validate(rawValue) {
        case .empty:
            return .blocked("상품 링크를 입력해 주세요.")
        case .unsupported:
            return .blocked(
                ProductURLParserError.unsupportedURL.errorDescription
                    ?? "지원하는 상품 링크인지 확인해 주세요."
            )
        case .supported(let url):
            return .begin(url)
        }
    }
}
