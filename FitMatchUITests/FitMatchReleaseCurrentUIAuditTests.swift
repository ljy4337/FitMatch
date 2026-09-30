import XCTest

/// Current visible UI, using the existing DEBUG test session and empty local store.
/// These tests do not authenticate with Apple or prove remote persistence.
final class FitMatchReleaseCurrentUIAuditTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(onboarding: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fitmatchUITesting"]
        app.launchArguments += onboarding
            ? ["-fitmatchResetOnboarding"]
            : ["-FitMatch.hasCompletedOnboarding", "YES"]
        app.launch()
        return app
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCurrentOnboardingNextAndLaterReachHome() {
        let app = launch(onboarding: true)
        XCTAssertTrue(app.staticTexts["내 옷으로 비교해요"].waitForExistence(timeout: 8))
        capture(app, "Onboarding first page")
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["상품 실측을 불러와요"].waitForExistence(timeout: 3))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["비슷한 옷을 한눈에 봐요"].waitForExistence(timeout: 3))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.shoppingLink"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboarding.manual"].exists)
        capture(app, "Registration choices")
        app.buttons["onboarding.later"].tap()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 5))
        capture(app, "Home after Later")
        app.terminate()
        app.launchArguments = ["-fitmatchUITesting"]
        app.launch()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))
        app.terminate()
    }

    @MainActor
    func testCurrentTabsAndPrivacySupportNavigation() {
        let app = launch()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))
        app.buttons["기록"].tap()
        XCTAssertTrue(app.staticTexts["아직 비교한 상품이 없어요."].waitForExistence(timeout: 3))
        app.buttons["추천"].tap()
        XCTAssertTrue(app.staticTexts["추천 서비스 준비 중"].waitForExistence(timeout: 3))
        app.buttons["내 옷장"].tap()
        XCTAssertTrue(app.staticTexts["아직 등록된 옷이 없어요."].waitForExistence(timeout: 3))
        capture(app, "Empty Closet")
        app.buttons["홈"].tap()
        app.buttons["내 정보"].tap()
        app.buttons["개인정보처리방침"].tap()
        XCTAssertTrue(app.staticTexts["기기와 서버에 저장하는 정보"].waitForExistence(timeout: 3))
        capture(app, "Current privacy policy")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["문의 및 지원"].tap()
        XCTAssertTrue(app.staticTexts["상품을 불러오지 못할 때"].waitForExistence(timeout: 3))
        capture(app, "Support")
        app.terminate()
    }

    @MainActor
    func testMalformedComparisonLinkShowsActionableMessage() {
        let app = launch()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))
        app.buttons["새 작업"].tap()
        app.buttons["상품 비교"].tap()
        let field = app.textFields["상품 URL을 붙여넣어 주세요"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("http://")
        app.buttons["비교하기"].tap()
        XCTAssertTrue(app.staticTexts["올바른 상품 URL을 입력해 주세요."].waitForExistence(timeout: 3))
        capture(app, "Malformed link recovery")
        app.terminate()
    }

    @MainActor
    func testLinkedClosetEmptyInputCannotLoadOrAdvance() {
        let app = launch(onboarding: true)
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 8))
        for _ in 0..<3 { app.buttons["onboarding.next"].tap() }
        app.buttons["onboarding.shoppingLink"].tap()
        XCTAssertTrue(app.textFields["closet.linkURL"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["closet.linkLoad"].isEnabled)
        XCTAssertFalse(app.buttons["closet.linkNext"].exists)
        capture(app, "Linked Closet empty input")
        app.terminate()
    }
}
