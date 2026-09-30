import Foundation
import Testing
@testable import FitMatch

@MainActor
struct FitMatchShareClosetEntryTests {
    @Test func sharedURLCanChooseClosetWithoutChangingItsIdentity() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchShareClosetEntry-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let url = try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/E450259-000/00"))
        let store = FitMatchSharedURLHandoffStore(fileURL: fileURL)

        #expect(store.save(url))
        let initial = try #require(store.pendingHandoff())
        #expect(initial.destination == .compare)
        #expect(store.setDestination(.closetRegistration, for: url, generation: initial.token))

        let chosen = try #require(store.pendingHandoff())
        #expect(chosen.urlString == initial.urlString)
        #expect(chosen.token == initial.token)
        #expect(chosen.destination == .closetRegistration)
        #expect(!store.setDestination(.compare, for: url, generation: UUID().uuidString))
        let otherURL = try #require(URL(string: "https://www.musinsa.com/products/4096130"))
        #expect(!store.setDestination(.compare, for: otherURL, generation: chosen.token))
        #expect(store.pendingHandoff()?.destination == .closetRegistration)
        #expect(store.acknowledge(urlString: chosen.urlString, generation: chosen.token))
        #expect(store.pendingHandoff() == nil)
    }

    @Test func olderSharePayloadStillOpensComparison() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FitMatchShareLegacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let now = Date()
        let legacy: [String: Any] = [
            "schemaVersion": 1,
            "urlString": "https://www.musinsa.com/products/4096130",
            "createdAt": now.timeIntervalSince1970 * 1_000,
            "generation": UUID().uuidString
        ]
        try JSONSerialization.data(withJSONObject: legacy).write(to: fileURL)

        let handoff = try #require(FitMatchSharedURLHandoffStore(fileURL: fileURL).pendingHandoff())
        #expect(handoff.destination == .compare)

        var malformed = legacy
        malformed["destination"] = NSNull()
        try JSONSerialization.data(withJSONObject: malformed).write(to: fileURL)
        #expect(FitMatchSharedURLHandoffStore(fileURL: fileURL).pendingHandoffOutcome() == .malformed)
    }

    @Test func appRouteAcceptsOnlyOwnShareDestinations() throws {
        let scheme = FitMatchProductEntryRouting.appScheme
        let compare = try #require(URL(string: "\(scheme)://compare"))
        let closet = try #require(URL(string: "\(scheme)://closet-link"))
        let unknown = try #require(URL(string: "\(scheme)://unknown"))

        #expect(FitMatchProductEntryRouting.action(for: compare) == .openPendingProductCompare)
        #expect(FitMatchProductEntryRouting.action(for: closet) == .openPendingClosetRegistration)
        #expect(FitMatchProductEntryRouting.action(for: unknown) == .ignore)
    }
}
