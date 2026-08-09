import XCTest

final class FitMatchUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFreshInstallShowsOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-fitmatchUITesting",
            "-FitMatch.hasCompletedOnboarding", "NO"
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["내 옷이 비교 기준이 돼요"].waitForExistence(timeout: 8),
            "신규 사용자는 첫 온보딩 화면을 봐야 합니다."
        )
        XCTAssertTrue(app.buttons["건너뛰기"].exists)
        XCTAssertTrue(app.buttons["다음"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Fresh Install Onboarding"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
