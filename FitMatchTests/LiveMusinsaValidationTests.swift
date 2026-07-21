import Testing
import Foundation
@testable import FitMatch

@MainActor
struct LiveMusinsaValidationTests {
    @Test func circumferencePipelineSamples() async {
        let parser = MusinsaParser()
        for id in ["6391245", "6219777", "6045676"] {
            do {
                let result = try await parser.parse(
                    from: URL(string: "https://www.musinsa.com/products/\(id)")!
                )
                let rows = result.sizes.map { size in
                    let chest = size.measurementRecords.first {
                        $0.measurementCode == .chestCircumferenceGarment
                    }
                    let form = ShoppingProductViewModel.makeSizeForm(
                        from: size,
                        displayOrder: 0,
                        allowsStandardSizeFallback: false
                    )
                    let productSize = form.makeSizeOption(
                        category: result.category,
                        detailCategory: result.detailCategory
                    )
                    let storedChest = productSize?.measurementRecords.first {
                        $0.measurementCode == .chestCircumferenceGarment
                    }
                    return "\(size.name):record=\(chest?.value.description ?? "nil"),form=\(form.chest),circ=\(form.chestUsesCircumference),stored=\(storedChest?.value.description ?? "nil")"
                }
                print("LIVE_CIRCUMFERENCE \(id) sizes=\(result.sizes.count) rows=\(rows)")
            } catch let error as ProductURLParserPartialError {
                print("LIVE_CIRCUMFERENCE \(id) partial sizes=\(error.productInfo.sizes.count)")
            } catch {
                print("LIVE_CIRCUMFERENCE \(id) error=\(error)")
            }
        }
    }

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
