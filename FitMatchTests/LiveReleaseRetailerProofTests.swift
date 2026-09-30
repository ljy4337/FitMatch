import Foundation
import Testing
@testable import FitMatch

/// Explicit opt-in; real HTTP and production parser, no Supabase mutations.
@MainActor
@Suite(.enabled(if: FileManager.default.fileExists(atPath: "/tmp/fitmatch-live-release-proof.enabled")))
struct LiveReleaseRetailerProofTests {
    @Test(arguments: [
        "https://musinsa.onelink.me/PvkC/ct27zw6f",
        "https://www.uniqlo.com/kr/ko/products/E484080-000/00?colorDisplayCode=07&sizeDisplayCode=004&pldDisplayCode=000",
        "https://www.zara.com/kr/ko/fruit-of-the-loom--%E1%84%8B%E1%85%AF%E1%84%89%E1%85%B5%E1%86%BC-%E1%84%90%E1%85%A6%E1%86%A8%E1%84%89%E1%85%B3%E1%84%90%E1%85%B3-%E1%84%89%E1%85%B3%E1%84%8B%E1%85%B0%E1%84%90%E1%85%B3%E1%84%89%E1%85%A7%E1%84%8E%E1%85%B3-p03443415.html?v1=564228855&utm_campaign=productShare&utm_medium=mobile_sharing_iOS&utm_source=red_social_movil"
    ])
    func actualProductToObservation(url: String) async throws {
        let product = try await ProductURLParserService().parse(urlString: url)
        #expect(!product.sizes.isEmpty)
        let request = try #require(product.fitMatchProductObservationRequest())
        let rawCount = product.sizes.reduce(0) { $0 + $1.measurementRecords.count }
        let transportedCount = request.payload.variants.reduce(0) { sum, variant in
            sum + variant.sizes.reduce(0) { $0 + $1.measurements.count }
        }
        #expect(rawCount > 0)
        #expect(transportedCount == rawCount)
        print("LIVE_RELEASE_PROOF source=\(request.payload.source) sizes=\(product.sizes.count) raw=\(rawCount) transported=\(transportedCount)")
    }
}
