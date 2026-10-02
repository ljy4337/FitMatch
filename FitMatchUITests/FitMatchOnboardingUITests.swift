import XCTest

final class FitMatchOnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFourGuidePagesHaveOnlyNextAndFinish() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-fitmatchUITesting", "-fitmatchResetOnboarding"]
        app.launch()
        for page in 0..<4 {
            XCTAssertTrue(app.staticTexts["onboarding.title.\(page)"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["onboarding.skip"].exists)
            XCTAssertFalse(app.buttons["onboarding.shoppingLink"].exists)
            XCTAssertFalse(app.buttons["onboarding.manual"].exists)
            XCTAssertFalse(app.buttons["onboarding.later"].exists)
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Onboarding \(page + 1)"
            capture.lifetime = .keepAlways
            add(capture)
            app.buttons["onboarding.next"].tap()
        }
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))
        app.terminate()
        app.launchArguments = ["-fitmatchUITesting"]
        app.launch()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["onboarding.next"].exists)
    }

    @MainActor
    func test02MusinsaFactsStayVisibleWithoutServerRegistrationAuthority() throws {
        let app = launchFreshOnboardingApp()

        registerLinkedProduct(
            in: app,
            url: "https://www.musinsa.com/products/onboarding-ui-test",
            expectedProductName: "온보딩 무신사 상의"
        )
    }

    @MainActor
    func test03UniqloFactsStayVisibleWithoutServerRegistrationAuthority() throws {
        let app = launchFreshOnboardingApp()

        registerLinkedProduct(
            in: app,
            url: "https://www.uniqlo.com/kr/ko/products/E000001-000/00",
            expectedProductName: "온보딩 유니클로 상의"
        )
    }

    @MainActor
    func test04ManualRegistrationRemainsAvailableAfterGuide() throws {
        let app = launchFreshOnboardingApp()
        openRegistrationFromMain(in: app, method: "직접 입력하기")
        XCTAssertTrue(app.textFields["closet.measurement.총장"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["onboarding.next"].exists)
    }

    @MainActor
    func test05NextPersistsOnboardingCompletionAcrossRelaunch() throws {
        var app = launchFreshOnboardingApp()
        advanceToRegistrationGuide(in: app)

        XCTAssertFalse(app.buttons["onboarding.later.top"].exists)
        let nextButton = app.buttons["onboarding.next"]
        nextButton.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["아직 등록된 옷이 없어요"].exists)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-fitmatchUITesting"]
        app.launch()

        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["onboarding.title.0"].exists)
        XCTAssertTrue(app.staticTexts["아직 등록된 옷이 없어요"].exists)
    }

    @MainActor
    func test06UnownedSeedDataDoesNotLeakIntoTheTestAccount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-fitmatchUITesting", "-fitmatchUITestSeedExistingData"]
        app.launch()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["아직 등록된 옷이 없어요"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["기존 기준옷"].exists)
        XCTAssertFalse(app.staticTexts["기존 비교상품"].exists)
        XCTAssertFalse(app.buttons["기준 옷 해제"].exists)
    }

    @MainActor
    func test07RepeatedLoadCannotReportSaveWithoutServerAuthority() throws {
        let app = launchFreshOnboardingApp()
        registerLinkedProduct(in: app,
                              url: "https://www.musinsa.com/products/onboarding-ui-test",
                              expectedProductName: "온보딩 무신사 상의")
        let reload = app.buttons["closet.linkLoad"]
        if reload.exists && reload.isHittable { reload.tap() }
        XCTAssertFalse(app.buttons["closet.confirmAction"].exists)
        XCTAssertFalse(app.staticTexts["내 옷장에 추가했어요."].exists)
    }

    /// Signed-out users are stopped by the root before any device-scoped
    /// onboarding surface can expose a registration or comparison action.
    @MainActor
    func test08SignedOutRootShowsLoginBeforeOnboarding() throws {
        let storeName = "FitMatchCR019-\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchArguments = [
            "-fitmatchResetOnboarding",
            "-fitmatchOnboardingFixtures",
            "-fitmatchUITestingPersistentStore", storeName
        ]
        app.launch()

        // `FIT MATCH` is unique to LoginView. Its appearance proves the
        // authenticated root wins before the device-level onboarding gate.
        XCTAssertTrue(app.staticTexts["FIT MATCH"].waitForExistence(timeout: 8))
        let appleButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Apple")
        ).firstMatch
        XCTAssertTrue(appleButton.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["onboarding.next"].exists)
        XCTAssertFalse(app.buttons["onboarding.shoppingLink"].exists)
        XCTAssertFalse(app.buttons["새 작업"].exists)
    }

    @MainActor
    private func launchFreshOnboardingApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-fitmatchUITesting",
            "-fitmatchResetOnboarding",
            "-fitmatchOnboardingFixtures"
        ]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["onboarding.title.0"].waitForExistence(timeout: 8)
        )
        return app
    }

    @MainActor
    private func advanceToRegistrationGuide(in app: XCUIApplication) {
        for page in 1..<4 {
            app.buttons["onboarding.next"].tap()
            XCTAssertTrue(app.staticTexts["onboarding.title.\(page)"].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    private func openRegistrationFromMain(in app: XCUIApplication, method: String) {
        advanceToRegistrationGuide(in: app)
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 5))
        app.buttons["새 작업"].tap()
        app.buttons["내 옷장에 추가"].tap()
        let methodButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", method)
        ).firstMatch
        XCTAssertTrue(methodButton.waitForExistence(timeout: 3))
        methodButton.tap()
    }

    @MainActor
    private func registerLinkedProduct(
        in app: XCUIApplication,
        url: String,
        expectedProductName: String
    ) {
        openRegistrationFromMain(in: app, method: "상품 링크로 불러오기")

        let urlField = app.textFields["closet.linkURL"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 3))
        urlField.tap()
        urlField.typeText(url)
        app.buttons["closet.linkLoad"].tap()

        XCTAssertTrue(app.staticTexts[expectedProductName].waitForExistence(timeout: 5))
        // DEBUG parser fixtures have no authenticated Supabase connection.
        // Parsed facts must remain visible, but cannot grant a save identity.
        let next = app.buttons["closet.linkNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        XCTAssertFalse(next.isEnabled)
        XCTAssertFalse(app.buttons["closet.confirmAction"].exists)
        XCTAssertFalse(app.staticTexts["내 옷장에 추가했어요."].exists)
    }

    @MainActor
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.exists || !element.isHittable {
            app.swipeUp()
        }
    }
}
