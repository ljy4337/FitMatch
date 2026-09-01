import Foundation

enum AppGroupConfig {
    static let identifier = "group.com.ljy4337.fitmatch"
}

struct SharedURLStore {
    static let pendingProductURLTimeToLive = FitMatchSharedURLHandoff.timeToLive
    typealias PendingProductURLHandoff = FitMatchSharedURLHandoffStore.Handoff
    typealias PendingProductURLReadOutcome = FitMatchSharedURLHandoffStore.PendingHandoffReadOutcome

    /// Missing App Group entitlement must fail closed, not terminate app
    /// startup.  Production app/extension installs supply the shared file;
    /// XCTest hosts and other unsupported containers simply have no pending
    /// handoff to consume.
    private let handoffStore: FitMatchSharedURLHandoffStore?

    init(
        fileURL: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let resolvedFileURL = fileURL ?? FitMatchSharedURLHandoff.appGroupFileURL(
            identifier: AppGroupConfig.identifier
        )
        handoffStore = resolvedFileURL.map {
            FitMatchSharedURLHandoffStore(fileURL: $0, now: now)
        }
    }

    func savePendingProductURL(_ url: URL) {
        _ = handoffStore?.save(url)
    }

    func pendingProductURL() -> String? {
        pendingProductURLHandoff()?.urlString
    }

    func pendingProductURLHandoff() -> PendingProductURLHandoff? {
        handoffStore?.pendingHandoff()
    }

    func pendingProductURLHandoffOutcome() -> PendingProductURLReadOutcome {
        handoffStore?.pendingHandoffOutcome() ?? .none
    }

    @discardableResult
    func clearPendingProductURL(
        ifMatching expectedURLString: String? = nil,
        token expectedToken: String? = nil
    ) -> Bool {
        handoffStore?.acknowledge(
            urlString: expectedURLString,
            generation: expectedToken
        ) ?? false
    }

    func consumePendingProductURL() -> String? {
        handoffStore?.consume()
    }
}

/// This is the app-entry action used by ContentView. A normal launch with no
/// Share intent remains silent; an expired, malformed, or unreadable handoff
/// becomes a concise recovery message rather than a silent no-op.
enum FitMatchPendingShareEntryAction {
    enum Outcome: Equatable {
        case open(SharedURLStore.PendingProductURLHandoff)
        case none
        case blocked(String)
    }

    static func outcome(for store: SharedURLStore) -> Outcome {
        switch store.pendingProductURLHandoffOutcome() {
        case .available(let handoff):
            return .open(handoff)
        case .none:
            return .none
        case .expired:
            return .blocked("공유한 링크가 만료됐어요. 상품 페이지에서 다시 공유해 주세요.")
        case .malformed:
            return .blocked("공유한 링크를 읽지 못했어요. 상품 페이지에서 다시 공유해 주세요.")
        case .storageUnavailable:
            return .blocked("공유한 링크를 열 준비를 하지 못했어요. 잠시 후 다시 시도해 주세요.")
        }
    }
}
