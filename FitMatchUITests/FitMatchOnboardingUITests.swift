import XCTest

final class FitMatchOnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test01NewUserReachesGarmentRegistrationGuideWithoutBodySetup() throws {
        let app = launchFreshOnboardingApp()

        advanceToRegistrationGuide(in: app)

        XCTAssertTrue(app.staticTexts["잘 맞는 옷 하나를 등록해보세요"].exists)
        XCTAssertTrue(app.buttons["onboarding.shoppingLink"].exists)
        XCTAssertTrue(app.buttons["onboarding.manual"].exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "체형")
        ).firstMatch.exists)
    }

    @MainActor
    func test02MusinsaLinkRegistrationCreatesClosetItemAndFinishesOnboarding() throws {
        let app = launchFreshOnboardingApp()

        registerLinkedProduct(
            in: app,
            url: "https://www.musinsa.com/products/onboarding-ui-test",
            expectedProductName: "온보딩 무신사 기준옷"
        )
    }

    @MainActor
    func test03UniqloLinkRegistrationCreatesClosetItemAndFinishesOnboarding() throws {
        let app = launchFreshOnboardingApp()

        registerLinkedProduct(
            in: app,
            url: "https://www.uniqlo.com/kr/ko/products/E000001-000/00",
            expectedProductName: "온보딩 유니클로 기준옷"
        )
    }

    @MainActor
    func test04ManualGarmentMeasurementRegistrationCreatesClosetItem() throws {
        let app = launchFreshOnboardingApp()
        advanceToRegistrationGuide(in: app)

        app.buttons["onboarding.manual"].tap()
        XCTAssertTrue(app.staticTexts["내 옷 추가"].waitForExistence(timeout: 3))

        let totalLengthField = app.textFields["closet.measurement.총장"]
        scrollToElement(totalLengthField, in: app)
        XCTAssertTrue(totalLengthField.exists)
        totalLengthField.tap()
        totalLengthField.typeText("70")

        let saveButton = app.buttons["closet.manualSave"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["온보딩 직접등록 기준옷"].waitForExistence(timeout: 3))
    }

    @MainActor
    func test05LaterPersistsOnboardingCompletionAcrossRelaunch() throws {
        var app = launchFreshOnboardingApp()
        advanceToRegistrationGuide(in: app)

        app.buttons["onboarding.later"].tap()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["아직 등록된 옷이 없어요"].exists)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-fitmatchUITesting"]
        app.launch()

        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["내 옷이 비교 기준이 돼요"].exists)
        XCTAssertTrue(app.staticTexts["아직 등록된 옷이 없어요"].exists)
    }

    @MainActor
    func test06ExistingUserKeepsClosetReferenceAndHistoryAcrossRelaunch() throws {
        let storeName = "FitMatchExistingUser-\(UUID().uuidString)"
        var app = XCUIApplication()
        app.launchArguments = [
            "-fitmatchUITesting",
            "-fitmatchUITestingPersistentStore", storeName,
            "-fitmatchUITestSeedExistingData"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["기존 기준옷"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["기존 비교상품"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["기준 옷 해제"].exists)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-fitmatchUITesting",
            "-fitmatchUITestingPersistentStore", storeName
        ]
        app.launch()

        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["내 옷이 비교 기준이 돼요"].exists)
        XCTAssertTrue(app.staticTexts["기존 기준옷"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["기존 비교상품"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["기준 옷 해제"].exists)
    }

    @MainActor
    func test07RapidSaveTapCreatesOneClosetItemAndShowsToast() throws {
        let app = launchFreshOnboardingApp()
        advanceToRegistrationGuide(in: app)
        app.buttons["onboarding.shoppingLink"].tap()

        let urlField = app.textFields["closet.linkURL"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 3))
        urlField.tap()
        urlField.typeText("https://www.musinsa.com/products/onboarding-ui-test")
        app.buttons["closet.linkLoad"].tap()
        XCTAssertTrue(app.staticTexts["온보딩 무신사 기준옷"].waitForExistence(timeout: 5))
        app.buttons["closet.linkNext"].tap()

        let actionButton = app.buttons["closet.confirmAction"]
        XCTAssertTrue(actionButton.waitForExistence(timeout: 3))
        actionButton.doubleTap()

        XCTAssertTrue(app.staticTexts["내 옷장에 추가했어요."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 5))
        app.buttons["내 옷장"].tap()
        XCTAssertTrue(app.staticTexts["온보딩 무신사 기준옷"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts.matching(
            NSPredicate(format: "label == %@", "온보딩 무신사 기준옷")
        ).count, 1)
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
            app.staticTexts["내 옷이 비교 기준이 돼요"].waitForExistence(timeout: 8)
        )
        return app
    }

    @MainActor
    private func advanceToRegistrationGuide(in app: XCUIApplication) {
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["상품 실측을 불러와요"].waitForExistence(timeout: 3))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["가장 비슷한 사이즈를 찾아요"].waitForExistence(timeout: 3))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["잘 맞는 옷 하나를 등록해보세요"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func registerLinkedProduct(
        in app: XCUIApplication,
        url: String,
        expectedProductName: String
    ) {
        advanceToRegistrationGuide(in: app)
        app.buttons["onboarding.shoppingLink"].tap()

        let urlField = app.textFields["closet.linkURL"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 3))
        urlField.tap()
        urlField.typeText(url)
        app.buttons["closet.linkLoad"].tap()

        XCTAssertTrue(app.staticTexts[expectedProductName].waitForExistence(timeout: 5))
        app.buttons["closet.linkNext"].tap()

        let actionButton = app.buttons["closet.confirmAction"]
        XCTAssertTrue(actionButton.waitForExistence(timeout: 3))
        let addPredicate = NSPredicate(format: "label CONTAINS %@", "내 옷장에 추가")
        expectation(for: addPredicate, evaluatedWith: actionButton)
        waitForExpectations(timeout: 3)
        actionButton.tap()

        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[expectedProductName].waitForExistence(timeout: 3))
    }

    @MainActor
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.exists || !element.isHittable {
            app.swipeUp()
        }
    }
}
