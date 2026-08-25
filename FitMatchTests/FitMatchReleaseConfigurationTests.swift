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

    @Test func shareExtensionAcceptsAllReleasedRetailerHosts() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("FitMatchShareExtension/ShareViewController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains(#"host == "musinsa.com""#))
        #expect(source.contains(#"host == "uniqlo.com""#))
        #expect(source.contains(#"host == "zara.com""#))
        #expect(source.contains(#"return "zara""#))
    }
}
