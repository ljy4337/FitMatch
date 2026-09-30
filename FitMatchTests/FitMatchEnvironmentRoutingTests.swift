import Foundation
import Testing
@testable import FitMatch

struct FitMatchEnvironmentRoutingTests {
    @Test func customLinksCannotCrossEnvironments() throws {
        let own = FitMatchProductEntryRouting.appScheme
        let other = own == "fitmatch" ? "fitmatch-qa" : "fitmatch"
        #expect(FitMatchProductEntryRouting.action(for: try #require(URL(string: "\(own)://compare"))) == .openPendingProductCompare)
        #expect(FitMatchProductEntryRouting.action(for: try #require(URL(string: "\(other)://compare"))) == .ignore)
        #expect(FitMatchProductEntryRouting.action(for: try #require(URL(string: "\(own)://unknown"))) == .ignore)
    }
}
