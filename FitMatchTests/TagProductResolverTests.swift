import XCTest
import CoreImage
import Vision
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

    @MainActor
    func testGeneratedZaraQRDecodesAndPreservesSelectedCatalogEntry() async throws {
        // Synthetic product URL QR; not a photograph of a retail tag or a live product lookup.
        let payload = "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346&v2=2436873"
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let output = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        // A QR needs a quiet zone; the generator emits only the symbol itself.
        let bounds = output.extent.insetBy(dx: -40, dy: -40)
        let background = CIImage(color: CIColor.white).cropped(to: bounds)
        let padded = output.composited(over: background)
        let image = try XCTUnwrap(CIContext().createCGImage(padded, from: bounds))
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        #if targetEnvironment(simulator)
        request.revision = VNDetectBarcodesRequestRevision1
        request.usesCPUOnly = true
        #endif
        try VNImageRequestHandler(cgImage: image).perform([request])
        let decoded = try XCTUnwrap(request.results?.first?.payloadStringValue)
        XCTAssertEqual(decoded, payload)
        let url = try await TagProductResolver().resolve(decoded)
        XCTAssertEqual(url.absoluteString, payload)
        XCTAssertEqual(ZARAProductPageParser.variantID(from: url), "545490346")
        XCTAssertTrue(FitMatchProductLinkInput.validate(url.absoluteString).canStartLoad)
    }

    func testZaraScanRejectsUnknownRoutesAndInvalidVariants() async throws {
        for payload in [
            "https://www.zara.com/kr/ko/",
            "https://www.zara.com.evil.test/kr/ko/item-p04166166.html?v1=545490346",
            "https://user@www.zara.com/kr/ko/item-p04166166.html",
            "https://www.zara.com/kr/ko/item-p04166166.html?v1=abc",
            "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346&v1=1",
            "https://www.zara.com/kr/ko/item-p04166166.html?v1=545490346%0A",
            "https://www.zara.com/kr/ko/qr/unknown"
        ] {
            do {
                _ = try await TagProductResolver().resolve(payload)
                XCTFail("Unverified Zara input accepted: \(payload)")
            } catch {
                XCTAssertTrue(error is TagProductResolver.ScanError)
            }
        }
        let payload = "https://www.zara.com/kr/ko/item-p04166166.html"
        let url = try await TagProductResolver().resolve(payload)
        XCTAssertEqual(url.absoluteString, payload, "Do not invent v1; existing parser resolves it from the page")
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
