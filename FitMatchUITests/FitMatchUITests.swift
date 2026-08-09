import XCTest

final class FitMatchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-fitmatchUITesting",
            "-FitMatch.hasCompletedOnboarding", "YES"
        ]
        app.launch()
        XCTAssertTrue(
            app.buttons["새 작업"].waitForExistence(timeout: 8),
            "초기 설정을 건너뛴 뒤 홈 화면이 표시되어야 합니다."
        )
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    @MainActor
    func testPrimaryTabsOpenExpectedEmptyStates() throws {
        assertBottomNavigationExists()

        app.buttons["기록"].tap()
        XCTAssertTrue(
            app.staticTexts["상품 비교 기록이 없습니다."].waitForExistence(timeout: 3),
            "기록 탭의 빈 상태가 표시되어야 합니다."
        )

        app.buttons["추천"].tap()
        XCTAssertTrue(
            app.staticTexts["추천 서비스 준비중"].waitForExistence(timeout: 3),
            "추천 탭의 현재 서비스 상태가 표시되어야 합니다."
        )

        app.buttons["내 옷장"].tap()
        XCTAssertTrue(
            app.staticTexts["옷장이 비었습니다."].waitForExistence(timeout: 3),
            "내 옷장 탭의 빈 상태가 표시되어야 합니다."
        )

        app.buttons["홈"].tap()
        XCTAssertTrue(
            app.staticTexts["아직 등록된 옷이 없어요"].waitForExistence(timeout: 3),
            "홈으로 돌아오면 옷장 요약의 빈 상태가 표시되어야 합니다."
        )
    }

    @MainActor
    func testNewTaskOpensComparisonInput() throws {
        app.buttons["새 작업"].tap()

        XCTAssertTrue(
            app.staticTexts["새 작업"].waitForExistence(timeout: 3),
            "새 작업 시트가 표시되어야 합니다."
        )
        XCTAssertTrue(app.buttons["상품 비교"].exists)
        XCTAssertTrue(app.buttons["내 옷장에 추가"].exists)

        app.buttons["상품 비교"].tap()

        XCTAssertTrue(
            app.staticTexts["상품 비교 시작"].waitForExistence(timeout: 5),
            "상품 비교 입력 화면으로 전환되어야 합니다."
        )
        XCTAssertTrue(
            app.textFields["상품 URL을 붙여넣어 주세요"].exists,
            "상품 URL 입력란이 표시되어야 합니다."
        )
    }

    @MainActor
    func testUnsupportedURLIsRejectedBeforeNetworkRequest() throws {
        app.buttons["새 작업"].tap()
        XCTAssertTrue(app.buttons["상품 비교"].waitForExistence(timeout: 3))
        app.buttons["상품 비교"].tap()

        let urlField = app.textFields["상품 URL을 붙여넣어 주세요"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
        urlField.tap()
        urlField.typeText("https://example.com/not-supported")

        let compareButton = app.buttons["비교하기"]
        XCTAssertTrue(compareButton.exists)
        compareButton.tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(
                format: "label CONTAINS %@",
                "무신사"
            )).firstMatch.waitForExistence(timeout: 3),
            "지원 쇼핑몰 안내가 표시되어야 합니다."
        )
    }

    @MainActor
    func testPrivacyPolicyAndSupportAreReachableFromMyPage() throws {
        let myPageButton = app.buttons["내 정보"]
        XCTAssertTrue(myPageButton.waitForExistence(timeout: 3))
        myPageButton.tap()

        let privacyButton = app.buttons["개인정보처리방침"]
        XCTAssertTrue(
            privacyButton.waitForExistence(timeout: 3),
            "MY 화면에서 개인정보처리방침에 접근할 수 있어야 합니다."
        )
        privacyButton.tap()
        XCTAssertTrue(
            app.staticTexts["기기에 저장하는 정보"].waitForExistence(timeout: 3),
            "앱의 실제 데이터 처리 내용이 표시되어야 합니다."
        )

        app.navigationBars.buttons.element(boundBy: 0).tap()

        let supportButton = app.buttons["문의 및 지원"]
        XCTAssertTrue(
            supportButton.waitForExistence(timeout: 3),
            "MY 화면에서 고객지원에 접근할 수 있어야 합니다."
        )
        supportButton.tap()
        XCTAssertTrue(
            app.staticTexts["상품을 불러오지 못할 때"].waitForExistence(timeout: 3),
            "고객지원 문제 해결 안내가 표시되어야 합니다."
        )
        XCTAssertTrue(
            app.staticTexts["고객지원 링크"].exists,
            "공개 고객지원 URL이 없으면 누락 상태를 숨기지 않아야 합니다."
        )
        let diagnosticsShareLink = app.buttons["supportDiagnosticsShareLink"]
        if !diagnosticsShareLink.exists {
            app.swipeUp()
        }
        XCTAssertTrue(
            diagnosticsShareLink.waitForExistence(timeout: 3),
            "개인정보 없는 품질 집계값을 사용자가 직접 내보낼 수 있어야 합니다."
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        app.terminate()
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            app.terminate()
        }
    }

    private func assertBottomNavigationExists(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for title in ["홈", "기록", "추천", "내 옷장", "새 작업"] {
            XCTAssertTrue(
                app.buttons[title].exists,
                "\(title) 하단 탐색 항목이 표시되어야 합니다.",
                file: file,
                line: line
            )
        }
    }
}
