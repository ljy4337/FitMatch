import XCTest

/// Opt-in writes through the normal app session. No mock-auth launch flag,
/// preloaded catalog, direct database write or automatic candidate fallback.
final class FitMatchAuthenticatedRegistrationUITests: XCTestCase {
    @MainActor
    func testSlacksRegistrationThenExplicitClosetComparison() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FITMATCH_RUN_AUTHENTICATED_JOURNEY"] == "1")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        defer {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "authenticated-journey-final"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        func tap(_ element: XCUIElement, timeout: TimeInterval = 15) {
            XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing UI: \(element)")
            let enabled = NSPredicate(format: "enabled == true")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: element)], timeout: timeout), .completed,
                           "UI stayed disabled; loading is not registration success: \(element)")
            element.tap()
        }
        func containing(_ text: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }

        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 30),
                      "BLOCKED: normal authenticated Home is required; this test never fabricates a session.")
        if ProcessInfo.processInfo.environment["FITMATCH_COMPARISON_ONLY"] != "1" {
            tap(app.buttons["새 작업"])
            tap(app.buttons["내 옷장에 추가"])
            tap(containing("상품 링크로 불러오기"))
            let link = app.textFields["closet.linkURL"]
            tap(link)
            link.typeText(ProcessInfo.processInfo.environment["FITMATCH_REGISTRATION_URL"] ?? "https://musinsa.onelink.me/PvkC/ct27zw6f")
            tap(app.buttons["closet.linkLoad"])
            tap(app.buttons["closet.linkNext"], timeout: 120)
            tap(app.buttons["closet.sizeSelector"])
            let medium = app.buttons["M"]
            XCTAssertTrue(medium.waitForExistence(timeout: 15))
            // SwiftUI Menu exposes a valid frame but sometimes no AX activation point.
            medium.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let action = app.buttons["closet.confirmAction"]
            XCTAssertTrue(action.waitForExistence(timeout: 10))
            if action.label.contains("다음") { tap(action) }
            XCTAssertTrue(action.label.contains("보유한 옷으로 등록"))
            tap(action)
            XCTAssertTrue(app.staticTexts["내 옷장에 추가했어요."].waitForExistence(timeout: 30),
                          "The actual registration must succeed before comparison begins.")
        }

        if ProcessInfo.processInfo.environment["FITMATCH_REGISTRATION_ONLY"] == "1" { return }

        tap(app.buttons["새 작업"])
        tap(app.buttons["상품 비교"])
        let target = app.textFields["상품 URL을 붙여넣어 주세요"]
        tap(target)
        target.typeText("https://www.uniqlo.com/kr/ko/products/E487214-000/00")
        tap(app.buttons["비교하기"])
        // A specific saved item is selected; another item is never substituted.
        let matches = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "원턱 와이드 슬랙스", "1. M"))
        let visible = NSPredicate { _, _ in matches.allElementsBoundByIndex.filter { $0.isHittable }.count == 1 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: nil)], timeout: 120), .completed,
                       "The exact saved M must appear as a visible server-approved candidate.")
        let candidate = try XCTUnwrap(matches.allElementsBoundByIndex.first { $0.isHittable })
        tap(candidate)
        XCTAssertTrue(app.navigationBars["개별 비교 결과"].waitForExistence(timeout: 90),
                      "An error or insufficient-measurement screen is not a successful comparison.")
        app.terminate()
        app.launch()
        tap(app.buttons["기록"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "배럴치노팬츠")).firstMatch.waitForExistence(timeout: 30),
                      "The completed product must remain in History after relaunch.")
        // Server Closet and completed comparison read-back must be checked separately
        // using this run's persisted IDs before labeling the full journey PASS.
    }
}
