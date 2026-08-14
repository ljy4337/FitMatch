import Foundation
import Testing
@testable import FitMatch

struct FitMatchReleaseConfigurationTests {
    @Test func releaseLinksAcceptOnlyPublicHTTPSURLs() {
        #expect(
            FitMatchReleaseConfiguration.httpsURL(from: " https://fitmatch.example/privacy ")?.absoluteString
                == "https://fitmatch.example/privacy"
        )
        #expect(FitMatchReleaseConfiguration.httpsURL(from: "http://fitmatch.example/privacy") == nil)
        #expect(FitMatchReleaseConfiguration.httpsURL(from: "https://") == nil)
        #expect(FitMatchReleaseConfiguration.httpsURL(from: "https://user:secret@fitmatch.example") == nil)
        #expect(FitMatchReleaseConfiguration.httpsURL(from: "javascript:alert(1)") == nil)
        #expect(FitMatchReleaseConfiguration.httpsURL(from: "") == nil)
        #expect(FitMatchReleaseConfiguration.httpsURL(from: nil) == nil)
    }
}
