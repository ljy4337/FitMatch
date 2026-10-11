import XCTest
@testable import FitMatch

final class TagProductResolverTests: XCTestCase {
    func testSuppliedUniqloBarcodeChecksumAndEndpoint() throws {
        XCTAssertEqual(try TagProductResolver.uniqloEndpoint("2000222273037").absoluteString,
                       "https://www.uniqlo.com/kr/api/commerce/v5/ko/l3s/2000222273037")
        for invalid in ["2000222273038", "487689", "２０００２２２２７３０３７", "2000222273037\n", ""] {
            XCTAssertThrowsError(try TagProductResolver.uniqloEndpoint(invalid))
        }
    }

    func testUniqloReceiptPreservesProductColorLengthButDoesNotSelectSize() throws {
        let json = #"{"status":"ok","result":{"productId":"E487689-000","priceGroup":"00","color":{"displayCode":"09"},"size":{"displayCode":"003"},"pld":{"displayCode":"000"}}}"#
        let url = try TagProductResolver.uniqloProductURL(Data(json.utf8))
        XCTAssertEqual(url.path, "/kr/ko/products/E487689-000/00")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first { $0.name == "colorDisplayCode" }?.value, "09")
        XCTAssertEqual(items?.first { $0.name == "pldDisplayCode" }?.value, "000")
        XCTAssertFalse(items?.contains { $0.name == "sizeDisplayCode" } ?? true)
        XCTAssertThrowsError(try TagProductResolver.uniqloProductURL(Data(#"{"status":"nok"}"#.utf8)))
        XCTAssertThrowsError(try TagProductResolver.uniqloProductURL(Data(json.replacingOccurrences(of: "E487689-000", with: "wrong").utf8)))
        XCTAssertThrowsError(try TagProductResolver.uniqloProductURL(Data(json.dropLast().utf8)))
    }

    func testMusinsaIntermediateOneLinkResolvesBothSuppliedProducts() throws {
        for id in ["6853555", "6341385"] {
            var link = URLComponents(string: "https://musinsa.onelink.me/bXEP")!
            link.queryItems = [URLQueryItem(name: "af_android_url", value: "https://pdp-web.musinsa.com/pdp/goods?barcode=MMFDJ9A82LG00S&goodsNo=\(id)")]
            XCTAssertEqual(TagProductResolver.musinsaProductURL(link.url!)?.absoluteString,
                           "https://www.musinsa.com/products/\(id)")
        }
    }

    func testUntrustedAndAmbiguousLinksAreRejected() {
        for text in ["https://evil.test/products/6853555", "https://musinsa.com.evil.test/products/6853555",
                     "https://pdp-web.musinsa.com/pdp/goods?goodsNo=abc6853555",
                     "https://pdp-web.musinsa.com/pdp/goods?goodsNo=6853555&goodsNo=6341385",
                     "https://user@www.musinsa.com/products/6853555"] {
            XCTAssertNil(TagProductResolver.musinsaProductURL(URL(string: text)!))
        }
        var link = URLComponents(string: "https://musinsa.onelink.me/bXEP")!
        link.queryItems = [URLQueryItem(name: "af_android_url", value: "https://www.musinsa.com/products/6853555"),
                           URLQueryItem(name: "af_web_dp", value: "https://www.musinsa.com/products/6341385")]
        XCTAssertNil(TagProductResolver.musinsaProductURL(link.url!))
    }

    @MainActor
    func testResolvedLinksEnterExistingProductInputGate() throws {
        for link in ["https://www.uniqlo.com/kr/ko/products/E487689-000/00?colorDisplayCode=09&pldDisplayCode=000",
                     "https://www.musinsa.com/products/6853555"] {
            XCTAssertTrue(FitMatchProductLinkInput.validate(link).canStartLoad)
            guard case .begin(let url) = FitMatchProductLinkInput.entryOutcome(for: link) else {
                return XCTFail("Resolved scan did not enter the existing product flow")
            }
            XCTAssertEqual(url.absoluteString, link)
        }
    }

    func testInternalRFIDQRDoesNotBecomeProduct() async {
        do {
            _ = try await TagProductResolver().resolve("553ACB6A6006655EEB5BD09200002FD9")
            XCTFail("Internal QR must not resolve")
        } catch {
            XCTAssertTrue(error is TagProductResolver.ScanError)
        }
    }
}
