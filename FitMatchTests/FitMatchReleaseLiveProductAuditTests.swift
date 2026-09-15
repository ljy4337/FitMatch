import Foundation
import Testing
@testable import FitMatch

/// Opt-in live retailer reads only. Does not sign in, ingest or write database rows.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FITMATCH_RELEASE_URLS"] != nil,
                "Requires an explicit release URL corpus"))
struct FitMatchReleaseLiveProductAuditTests {
    @Test func suppliedURLsLoadThroughTheFullProductionParser() async throws {
        let env = ProcessInfo.processInfo.environment
        let input = try #require(env["FITMATCH_RELEASE_URLS"])
        let output = try #require(env["FITMATCH_RELEASE_OUTPUT"])
        let urls = try String(contentsOfFile: input, encoding: .utf8)
            .split(whereSeparator: \.isNewline).map(String.init)
        #expect(!urls.isEmpty)
        #expect(Set(urls).count == urls.count)
        var records: [[String: Any]] = []
        for (index, url) in urls.enumerated() {
            let started = Date()
            var record: [String: Any] = ["url": url]
            do {
                let parsed = try await ProductURLParserService().parse(urlString: url)
                record.merge(evidence(parsed)) { _, new in new }
                if env["FITMATCH_RELEASE_VERIFY_REPAIRS"] == "1", parsed.productID == "6372903" {
                    #expect(parsed.sizes.map { $0.name.uppercased() } == ["S(090)", "M(095)", "L(100)"])
                    #expect(parsed.sizes.flatMap(\.measurementRecords).filter { $0.rawLabel == "팔둘레" }.map(\.value)
                            == [28, 29.5, 30.5])
                    #expect(parsed.sizes.flatMap(\.measurementRecords).filter { $0.rawLabel == "가슴둘레" }.map(\.value)
                            == [84, 88, 94])
                    for (label, expected) in ["어깨너비": [36.0, 37, 39], "소매길이": [13.0, 14, 15], "총장": [55.0, 56, 57]] {
                        #expect(parsed.sizes.compactMap { size in
                            size.measurementRecords.first { $0.rawLabel == label }?.value
                        } == expected)
                    }
                }
                record["status"] = parsed.measurementAvailability == .actualMeasurements
                    && parsed.sizes.contains(where: { !$0.measurementRecords.isEmpty })
                    ? "PARSED_WITH_MEASUREMENTS" : "MEASUREMENT_RECOVERY_REQUIRED"
            } catch let partial as ProductURLParserPartialError {
                record.merge(evidence(partial.productInfo)) { _, new in new }
                record["status"] = "PARTIAL_RECOVERY_REQUIRED"
                record["error"] = partial.localizedDescription
            } catch {
                record["status"] = "FAILED"
                record["error"] = error.localizedDescription
            }
            record["elapsedSeconds"] = Date().timeIntervalSince(started)
            records.append(record)
            let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
            print("RELEASE_PRODUCT_AUDIT \(index + 1)/\(urls.count) \(record["status"] ?? "UNKNOWN") \(url)")
        }
        #expect(records.count == urls.count)
        // A completed audit is not a product pass; preserve every failed/partial row.
        #expect(records.filter { $0["status"] as? String == "FAILED" }.isEmpty)
    }

    private func evidence(_ product: ParsedProductInfo) -> [String: Any] {
        let observation = product.fitMatchProductObservationRequest()
        return [
            "productID": product.productID as Any? ?? NSNull(),
            "name": product.productName,
            "source": observation?.payload.source as Any? ?? NSNull(),
            "sourceCategoryPath": observation?.payload.sourceCategoryPath as Any? ?? NSNull(),
            "measurementAvailability": product.measurementAvailability.rawValue,
            "observationAvailable": observation != nil,
            "imageAvailable": product.imageURLString?.isEmpty == false,
            "notice": product.parserNotice as Any? ?? NSNull(),
            "sizes": product.sizes.map { size in
                ["name": size.name,
                 "availability": size.availabilityStatus ?? "UNKNOWN",
                 "measurements": size.measurementRecords.map { measurement in
                     ["label": measurement.rawLabel, "value": measurement.value,
                      "code": measurement.measurementCode.rawValue,
                      "unit": measurement.unit.rawValue] as [String: Any]
                 }] as [String: Any]
            }
        ]
    }
}
