import Foundation

/// The official user-facing provider boundary shared by the containing app
/// and Share Extension.  Parsers may retain experimental/internal support,
/// but a URL only reaches a normal user entry flow when this contract accepts
/// it.
enum FitMatchProductURLRouting {
    enum Provider: String, CaseIterable, Sendable {
        case musinsa
        case uniqlo
        case zara
    }

    static func provider(
        for url: URL,
        zaraEnabled: Bool = true
    ) -> Provider? {
        guard let host = url.host?.lowercased() else {
            return nil
        }

        if matches(host: host, domain: "musinsa.com") || host == "musinsa.onelink.me" {
            return .musinsa
        }
        if matches(host: host, domain: "uniqlo.com") {
            return .uniqlo
        }
        if zaraEnabled, matches(host: host, domain: "zara.com") {
            return .zara
        }
        return nil
    }

    static func firstSupportedURL(
        in candidates: [URL],
        zaraEnabled: Bool = true
    ) -> URL? {
        candidates.first { provider(for: $0, zaraEnabled: zaraEnabled) != nil }
    }

    private static func matches(host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }
}
