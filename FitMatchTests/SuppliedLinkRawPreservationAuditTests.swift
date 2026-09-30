import Foundation
import Testing
@testable import FitMatch

/// Offline replay of existing retailer receipts intersecting the supplied URL list.
/// This verifies parser/display/observation transport, not server persistence.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FITMATCH_RELEASE_URLS"] != nil))
struct SuppliedLinkRawPreservationAuditTests {
    @Test func existingSuppliedUniqloReceiptsPreserveRawFacts() throws {
        let input = try #require(ProcessInfo.processInfo.environment["FITMATCH_RELEASE_URLS"])
        let urls = try String(contentsOfFile: input, encoding: .utf8)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("CurrentUniqloCatalogInputs.json"))
        let products = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        var checkedProducts = 0
        var checkedRows = 0
        for product in products {
            let id = try #require(product["product_id"] as? String)
            guard urls.contains("/products/\(id)-") else { continue }
            let payload = try #require(product["size_chart_payload"] as? [String: Any])
            let parsed = try UniqloSizeAPIParser().parseSizes(from: JSONSerialization.data(withJSONObject: payload))
            let result = try #require(payload["result"] as? [[String: Any]])
            var expected = Set<String>()
            for chart in result {
                for size in chart["sizeChart"] as? [[String: Any]] ?? [] {
                    let name = try #require(size["name"] as? String)
                    for part in size["sizeParts"] as? [[String: Any]] ?? [] {
                        let code = try #require(part["code"] as? String)
                        let label = try #require(part["name"] as? String)
                        let measures = part["measurements"] as? [[String: Any]] ?? []
                        guard let cm = measures.first(where: { ($0["unit"] as? String)?.lowercased() == "cm" }),
                              let raw = cm["value"] as? String,
                              let value = Double(raw), value.isFinite, value > 0 else { continue }
                        expected.insert("\(name)|\(code)|\(label)|\(value)")
                    }
                }
            }
            var actual = Set<String>()
            for size in parsed {
                let rows = MeasurementResolver.sourceDisplayRows(records: size.measurementRecords)
                #expect(rows.count == size.measurementRecords.count, "\(id) / \(size.name)")
                for record in size.measurementRecords {
                    actual.insert("\(size.name)|\(record.rawCode ?? "")|\(record.rawLabel)|\(record.value)")
                }
            }
            // Range/text measurements remain separate from the exact numeric subset.
            #expect(expected.isSubset(of: actual), "Raw receipt values lost or changed: \(id), \(expected.subtracting(actual))")
            let info = ParsedProductInfo(
                sourceURL: try #require(URL(string: "https://www.uniqlo.com/kr/ko/products/\(id)-000/00")),
                sourceType: .officialStore, sourceName: "유니클로 공식몰",
                brandName: "유니클로", productName: product["product_name"] as? String ?? id,
                category: .top, detailCategory: .shortSleeve, sizes: parsed, productID: id
            )
            let observation = try #require(info.fitMatchProductObservationRequest(observedAt: Date(timeIntervalSince1970: 0)))
            let transported = observation.payload.variants.flatMap(\.sizes)
            #expect(transported.count == parsed.count, "\(id)")
            #expect(transported.reduce(0) { $0 + $1.measurements.count } == parsed.reduce(0) { $0 + $1.measurementRecords.count }, "\(id)")
            for (source, target) in zip(parsed, transported) {
                for (raw, sent) in zip(source.measurementRecords, target.measurements) {
                    #expect(raw.rawCode == sent.rawCode)
                    #expect(raw.rawLabel == sent.rawLabel)
                    #expect(raw.value == sent.rawValue)
                    #expect(raw.rawValueText == sent.rawValueText)
                }
            }
            checkedRows += expected.count
            checkedProducts += 1
        }
        #expect(checkedProducts > 0)
        print("SUPPLIED_RAW_REPLAY products=\(checkedProducts) exact_numeric_rows=\(checkedRows)")
    }
}
