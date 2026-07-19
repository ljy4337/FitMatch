import Testing
import Foundation
@testable import FitMatch

@MainActor
struct LiveMusinsaValidationTests {
    @Test func rejectedImageSamples() async {
        let parser = MusinsaParser()
        for id in ["3838933", "4898098", "5058151"] {
            do {
                let result = try await parser.parse(
                    from: URL(string: "https://www.musinsa.com/products/\(id)")!
                )
                print("LIVE_RESULT \(id) success sizes=\(result.sizes.map { $0.name }) counts=\(result.sizes.map { $0.measurementRecords.count })")
            } catch let error as ProductURLParserPartialError {
                print("LIVE_RESULT \(id) rejected sizes=\(error.productInfo.sizes.count)")
            } catch {
                print("LIVE_RESULT \(id) error=\(error)")
            }
        }
    }
}
