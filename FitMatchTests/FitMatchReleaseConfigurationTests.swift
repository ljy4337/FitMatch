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
        // The Share Extension and containing app now use this shared routing
        // contract, rather than maintaining fragile duplicated host literals
        // in a ViewController source file.
        let musinsa = try #require(URL(string: "https://www.musinsa.com/products/6781113"))
        let uniqlo = try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/E450259-000/00"))
        let zara = try #require(URL(string: "https://www.zara.com/kr/ko/example-p06224446.html"))
        let cos = try #require(URL(string: "https://www.cos.com/ko-kr/product.example.1229297007.html"))

        #expect(FitMatchProductURLRouting.provider(for: musinsa) == .musinsa)
        #expect(FitMatchProductURLRouting.provider(for: uniqlo) == .uniqlo)
        #expect(FitMatchProductURLRouting.provider(for: zara) == .zara)
        #expect(FitMatchProductURLRouting.provider(for: cos) == nil)
    }
}
