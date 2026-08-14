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
            app.staticTexts["아직 비교한 상품이 없어요."].waitForExistence(timeout: 3),
            "기록 탭의 빈 상태가 표시되어야 합니다."
        )

        app.buttons["추천"].tap()
        XCTAssertTrue(
            app.staticTexts["추천 서비스 준비 중"].waitForExistence(timeout: 3),
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
    func testAmbiguousCategoryChoiceIsReusedForTheExactProduct() throws {
        app.terminate()
        app.launchArguments = [
            "-fitmatchUITesting",
            "-FitMatch.hasCompletedOnboarding", "YES",
            "-fitmatchUITestSeedExistingData",
            "-fitmatchAmbiguousCategoryFixture",
            "-fitmatchResetCategoryMappings"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))

        openAmbiguousCategoryFixture()
        XCTAssertTrue(
            app.staticTexts["상품 종류 확인"].waitForExistence(timeout: 8),
            "첫 분석에서는 모호한 세부 카테고리를 사용자에게 물어야 합니다."
        )
        app.buttons["대분류 선택"].tap()
        app.buttons["상의"].tap()
        app.buttons["세부 카테고리 선택"].tap()
        app.buttons["반팔"].tap()
        app.buttons["비교하기"].tap()
        let referenceSelection = app.staticTexts["기준 옷 직접 선택"]
        if referenceSelection.waitForExistence(timeout: 3) {
            app.buttons.matching(NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "기존 기준옷",
                "직접 비교"
            )).firstMatch.tap()
        }
        XCTAssertTrue(
            waitForAny([
                app.navigationBars["비교 결과"],
                app.staticTexts["추천하기에 실측 정보가 부족해요"]
            ], timeout: 10),
            "사용자 분류로 추천 결과 또는 명시적인 실측 부족 단계까지 진행되어야 합니다."
        )

        // Relaunch with a fresh in-memory closet but the same local defaults.
        // The exact-product answer must survive and bypass category selection.
        app.terminate()
        app.launchArguments = [
            "-fitmatchUITesting",
            "-FitMatch.hasCompletedOnboarding", "YES",
            "-fitmatchUITestSeedExistingData",
            "-fitmatchAmbiguousCategoryFixture"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))

        openAmbiguousCategoryFixture()
        XCTAssertTrue(
            waitForAny([
                app.navigationBars["비교 결과"],
                app.staticTexts["기준 옷 직접 선택"],
                app.staticTexts["추천하기에 실측 정보가 부족해요"]
            ], timeout: 10),
            "동일 상품 재분석은 분류 선택 없이 비교 단계로 진행되어야 합니다."
        )
        XCTAssertFalse(
            app.staticTexts["상품 종류 확인"].exists,
            "동일 상품에는 분류 선택을 다시 요구하면 안 됩니다."
        )

        // A sibling product from the exact same provider path must not inherit
        // the answer stored for the first product.
        app.terminate()
        app.launchArguments = [
            "-fitmatchUITesting",
            "-FitMatch.hasCompletedOnboarding", "YES",
            "-fitmatchUITestSeedExistingData",
            "-fitmatchAmbiguousCategoryFixture"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))

        openAmbiguousCategoryFixture(productSuffix: "sibling")
        XCTAssertTrue(
            app.staticTexts["상품 종류 확인"].waitForExistence(timeout: 8),
            "같은 공급사 경로라도 다른 상품에는 첫 상품의 선택을 전파하면 안 됩니다."
        )

        // Clearing the local mapping store must make the original product ask
        // again, proving that the prior bypass came from persisted state.
        app.terminate()
        app.launchArguments = [
            "-fitmatchUITesting",
            "-FitMatch.hasCompletedOnboarding", "YES",
            "-fitmatchUITestSeedExistingData",
            "-fitmatchAmbiguousCategoryFixture",
            "-fitmatchResetCategoryMappings"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))

        openAmbiguousCategoryFixture()
        XCTAssertTrue(
            app.staticTexts["상품 종류 확인"].waitForExistence(timeout: 8),
            "분류 매핑을 초기화하면 원래 상품도 다시 사용자에게 물어야 합니다."
        )
    }

    private func openAmbiguousCategoryFixture(productSuffix: String? = nil) {
        app.buttons["새 작업"].tap()
        XCTAssertTrue(app.buttons["상품 비교"].waitForExistence(timeout: 3))
        app.buttons["상품 비교"].tap()
        let urlField = app.textFields["상품 URL을 붙여넣어 주세요"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
        urlField.tap()
        let suffix = productSuffix.map { "-\($0)" } ?? ""
        urlField.typeText("https://www.musinsa.com/products/fitmatch-ambiguous-category-ui\(suffix)")
        app.buttons["비교하기"].tap()
    }

    private func waitForAny(
        _ elements: [XCUIElement],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: \.exists) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return elements.contains(where: \.exists)
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
