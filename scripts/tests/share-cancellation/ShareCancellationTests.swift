import XCTest
import UIKit

@MainActor
final class ShareCancellationTests: XCTestCase {
    private var store: FitMatchSharedURLHandoffStore!
    private var fileURL: URL!
    private let productURL = URL(string: "https://www.uniqlo.com/kr/ko/products/E450259-000/00")!

    override func setUpWithError() throws {
        fileURL = try XCTUnwrap(FitMatchSharedURLHandoff.appGroupFileURL(identifier: ShareViewController.AppGroup.identifier))
        try? FileManager.default.removeItem(at: fileURL)
        store = FitMatchSharedURLHandoffStore(fileURL: fileURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testCloseRemovesItsOwnPendingHandoff() throws {
        let controller = ShareViewController()
        XCTAssertTrue(controller.savePendingURL(productURL))
        XCTAssertNotNil(store.pendingHandoff())
        controller.closeButtonTapped()
        XCTAssertNil(store.pendingHandoff(), "Close must cancel this extension's pending share")
    }

    func testLateExtractionCannotSaveAfterClose() {
        let controller = ShareViewController()
        controller.closeButtonTapped()
        XCTAssertFalse(controller.savePendingURL(productURL), "A late extraction result must not persist after Close")
        XCTAssertNil(store.pendingHandoff())
    }

    func testClosePreservesNewerGenerationOfSameURL() throws {
        let controller = ShareViewController()
        XCTAssertTrue(controller.savePendingURL(productURL))
        let old = try XCTUnwrap(store.pendingHandoff())
        XCTAssertTrue(store.save(productURL))
        let newer = try XCTUnwrap(store.pendingHandoff())
        XCTAssertNotEqual(newer.token, old.token)
        controller.closeButtonTapped()
        XCTAssertEqual(store.pendingHandoff(), newer)
    }

    func testClosePreservesNewerDifferentURL() throws {
        let controller = ShareViewController()
        XCTAssertTrue(controller.savePendingURL(productURL))
        let other = URL(string: "https://www.musinsa.com/products/4096130")!
        XCTAssertTrue(store.save(other, destination: .closetRegistration))
        let newer = try XCTUnwrap(store.pendingHandoff())
        controller.closeButtonTapped()
        XCTAssertEqual(store.pendingHandoff(), newer)
    }

    func testCloseWithoutOwnedHandoffPreservesPendingShare() throws {
        XCTAssertTrue(store.save(productURL))
        let original = try XCTUnwrap(store.pendingHandoff())
        ShareViewController().closeButtonTapped()
        XCTAssertEqual(store.pendingHandoff(), original)
    }

    func testLateOpenFailureDoesNotRestartDismissedShare() async {
        let controller = ShareViewController()
        controller.closeButtonTapped()
        controller.handleOpenResult(false, url: URL(string: "fitmatch://compare")!, canTryExtensionContext: true)
        let callbacksDrained = expectation(description: "Main queue callbacks drained")
        DispatchQueue.main.async { callbacksDrained.fulfill() }
        await fulfillment(of: [callbacksDrained], timeout: 2)
        XCTAssertNil(controller.titleLabel.text, "A dismissed extension must ignore late app-open callbacks")
    }

    func testClosePreservesExpiredReplacement() throws {
        let controller = ShareViewController()
        XCTAssertTrue(controller.savePendingURL(productURL))
        let replacement = FitMatchSharedURLHandoff.Payload(
            urlString: productURL.absoluteString,
            createdAt: Date().addingTimeInterval(-3_600),
            generation: UUID().uuidString
        )
        let data = try FitMatchSharedURLHandoff.makeEncoder().encode(replacement)
        try data.write(to: fileURL, options: .atomic)
        controller.closeButtonTapped()
        XCTAssertEqual(try Data(contentsOf: fileURL), data)
    }

    func testClosePreservesMalformedReplacement() throws {
        let controller = ShareViewController()
        XCTAssertTrue(controller.savePendingURL(productURL))
        let data = Data("malformed newer payload".utf8)
        try data.write(to: fileURL, options: .atomic)
        controller.closeButtonTapped()
        XCTAssertEqual(try Data(contentsOf: fileURL), data)
    }

    func testCancellationRequiresExactURLAsWellAsGeneration() throws {
        let original = try XCTUnwrap(store.saveHandoff(productURL))
        XCTAssertFalse(store.cancel(urlString: "https://www.musinsa.com/products/4096130", generation: original.token))
        XCTAssertEqual(store.pendingHandoff(), original)
        XCTAssertTrue(store.cancel(urlString: original.urlString, generation: original.token))
        XCTAssertNil(store.pendingHandoff())
    }

    func testSaveReceiptKeepsOwnedGenerationWhenSameURLIsReplaced() throws {
        let original = try XCTUnwrap(store.saveHandoff(productURL))
        let replacement = try XCTUnwrap(store.saveHandoff(productURL, destination: .closetRegistration))
        XCTAssertNotEqual(original.token, replacement.token)
        XCTAssertFalse(store.cancel(urlString: original.urlString, generation: original.token))
        XCTAssertEqual(store.pendingHandoff(), replacement)
    }

    func testCompareAndClosetDestinationsRetainExactIdentity() throws {
        for destination in [FitMatchSharedURLHandoff.Destination.compare, .closetRegistration] {
            let controller = ShareViewController()
            XCTAssertTrue(controller.savePendingURL(productURL))
            let original = try XCTUnwrap(store.pendingHandoff())
            // Exercise the real button handler through its opening guard. A nil
            // extensionContext cannot launch the containing app from this host.
            controller.startOpening(destination)
            let chosen = try XCTUnwrap(store.pendingHandoff())
            XCTAssertEqual(chosen.urlString, original.urlString)
            XCTAssertEqual(chosen.token, original.token)
            XCTAssertEqual(chosen.destination, destination)
            XCTAssertEqual(ShareViewController.DeepLink.url(for: destination)?.absoluteString,
                           destination == .compare ? "fitmatch://compare" : "fitmatch://closet-link")
        }
    }
}
