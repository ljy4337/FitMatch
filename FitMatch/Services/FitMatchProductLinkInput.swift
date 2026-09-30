import Foundation

/// Validates user-entered product-link text before a registration or compare
/// flow starts parser/network work. Views use this narrow boundary so a
/// headless caller can exercise the same supported-provider gate without
/// reproducing the view's private button closure.
enum FitMatchProductLinkInput {
    enum Validation: Equatable {
        case empty
        case malformed
        case unsupported
        case supported(URL)

        var canStartLoad: Bool {
            if case .supported = self { return true }
            return false
        }

        var userMessage: String? {
            switch self {
            case .empty, .supported:
                return nil
            case .malformed:
                return "올바른 상품 URL을 입력해 주세요."
            case .unsupported:
                return "현재는 무신사, 유니클로, ZARA 상품 링크를 지원합니다."
            }
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
        guard let url = ProductURLSupport.normalizedURL(from: normalized) else {
            return .malformed
        }
        guard ProductURLSupport.isSupportedProductURL(normalized) else {
            return .unsupported
        }
        return .supported(url)
    }

    static func entryOutcome(for rawValue: String) -> EntryOutcome {
        switch validate(rawValue) {
        case .empty:
            return .blocked("상품 링크를 입력해 주세요.")
        case .malformed:
            return .blocked(Validation.malformed.userMessage!)
        case .unsupported:
            return .blocked(Validation.unsupported.userMessage!)
        case .supported(let url):
            return .begin(url)
        }
    }
}
