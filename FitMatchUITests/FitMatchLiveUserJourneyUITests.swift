import XCTest

final class FitMatchLiveUserJourneyUITests: XCTestCase {
    private struct ThirtyPairCase: Decodable {
        let brand: String
        let referenceProductID: String
        let referenceProductName: String
        let referenceSizeName: String
        let referenceURL: String
        let comparisonProductID: String
        let comparisonProductName: String
        let comparisonSizeName: String
        let comparisonURL: String
        let categoryCode: String
        let score: Int
        let reliability: String

        enum CodingKeys: String, CodingKey {
            case brand
            case referenceProductID = "reference_product_id"
            case referenceProductName = "reference_product_name"
            case referenceSizeName = "reference_size_name"
            case referenceURL = "reference_url"
            case comparisonProductID = "comparison_product_id"
            case comparisonProductName = "comparison_product_name"
            case comparisonSizeName = "comparison_size_name"
            case comparisonURL = "comparison_url"
            case categoryCode = "category_code"
            case score
            case reliability
        }
    }
    private let app = XCUIApplication()
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let systemUI = XCUIApplication(bundleIdentifier: "com.apple.UIKitSystemApp")

    private let uniqloReferenceURL = "https://www.uniqlo.com/kr/ko/products/E482305-000/00"
    private let uniqloComparisonURL = "https://www.uniqlo.com/kr/ko/products/E465187-000/00?colorDisplayCode=64&sizeDisplayCode=004"
    private let musinsaReferenceURL = "https://www.musinsa.com/products/6219777"
    private let musinsaComparisonURL = "https://www.musinsa.com/products/6045676"

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FITMATCH_RUN_LIVE_UI_TESTS"] == "1",
            "실사용자 실서버 UI 검증은 FitMatchLiveUserJourney scheme으로 실행합니다."
        )

        app.launchArguments = [
            "-fitmatchUITesting",
            "-FitMatch.hasCompletedOnboarding", "YES"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 12))
    }

    override func tearDownWithError() throws {
        capture(name: "final-state")
        app.terminate()
    }

    @MainActor
    func testLiveClosetRegistrationAndSafariShareComparison() throws {
        try XCTContext.runActivity(named: "유니클로 링크로 내 옷장 추가") { _ in
            try addClosetReference(
                url: uniqloReferenceURL,
                expectedProductText: "DRY-EX폴로셔츠"
            )
        }

        try XCTContext.runActivity(named: "무신사 링크로 내 옷장 추가") { _ in
            try addClosetReference(
                url: musinsaReferenceURL,
                expectedProductText: "아이스펄스"
            )
        }

        try XCTContext.runActivity(named: "Safari에서 유니클로 상품 공유 후 비교") { _ in
            try shareFromSafariAndVerifyComparison(
                url: uniqloComparisonURL,
                expectedProductText: "드라이컬러크루넥",
                expectedReferenceText: "DRY-EX폴로셔츠"
            )
            dismissComparisonSheetIfNeeded()
        }

        try XCTContext.runActivity(named: "Safari에서 무신사 상품 공유 후 비교") { _ in
            try shareFromSafariAndVerifyComparison(
                url: musinsaComparisonURL,
                expectedProductText: "스탠넥 아노락",
                expectedReferenceText: "아이스펄스"
            )
        }
    }

    @MainActor
    func testLiveThirtyBalancedPairsThroughAppUI() throws {
        let cases = try loadThirtyPairCases()
        XCTAssertEqual(cases.count, 30)
        XCTAssertEqual(Set(cases.map(\.comparisonProductID)).count, 30)

        let referenceCases = Dictionary(grouping: cases) {
            "\($0.brand):\($0.referenceProductID)"
        }.values.compactMap(\.first).sorted {
            ($0.brand, $0.categoryCode) < ($1.brand, $1.categoryCode)
        }

        XCTAssertEqual(referenceCases.count, 6)
        for reference in referenceCases {
            try XCTContext.runActivity(
                named: "기준옷 등록 \(reference.brand) \(reference.referenceProductID)"
            ) { _ in
                try addClosetReference(
                    url: reference.referenceURL,
                    expectedProductText: productTextProbe(reference.referenceProductName)
                )
            }
        }

        var completed = 0
        for testCase in cases {
            try XCTContext.runActivity(
                named: "UI쌍 \(completed + 1)/30 \(testCase.brand) \(testCase.comparisonProductID)"
            ) { _ in
                try compareFromDirectURL(
                    url: testCase.comparisonURL,
                    expectedProductText: productTextProbe(testCase.comparisonProductName),
                    expectedReferenceText: productTextProbe(testCase.referenceProductName),
                    caseNumber: completed + 1
                )
            }
            completed += 1
            print(
                "FITMATCH_UI30_FLOW_PASS index=\(completed) brand=\(testCase.brand) "
                    + "category=\(testCase.categoryCode) reference=\(testCase.referenceProductID) "
                    + "comparison=\(testCase.comparisonProductID) engine_size=\(testCase.comparisonSizeName) "
                    + "engine_score=\(testCase.score) reliability=\(testCase.reliability)"
            )
        }
        XCTAssertEqual(completed, 30)
    }

    private func loadThirtyPairCases() throws -> [ThirtyPairCase] {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "FitMatchUI30Pairs", withExtension: "json")
        )
        return try JSONDecoder().decode([ThirtyPairCase].self, from: Data(contentsOf: url))
    }

    private func productTextProbe(_ name: String) -> String {
        let tokens = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return tokens.first(where: { $0.count >= 3 }) ?? String(name.prefix(8))
    }

    private func compareFromDirectURL(
        url: String,
        expectedProductText: String,
        expectedReferenceText: String,
        caseNumber: Int
    ) throws {
        app.activate()
        tapHittableButton(named: "새 작업", timeout: 20)
        tapHittableButton(named: "상품 비교", timeout: 8)

        let urlField = app.textFields["상품 URL을 붙여넣어 주세요"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 8))
        urlField.tap()
        urlField.typeText(url)
        tapHittableButton(named: "비교하기", timeout: 8)

        let resultTitle = app.navigationBars["비교 결과"]
        let insufficient = app.staticTexts["추천하기에 실측 정보가 부족해요"]
        let missingReference = app.staticTexts["기준 옷을 직접 선택해 주세요"]
        let referenceSelection = app.staticTexts["기준 옷 직접 선택"]
        let categoryConfirmation = app.staticTexts["상품 종류 확인"]
        let loadError = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "불러오지 못")
        ).firstMatch

        XCTAssertTrue(
            waitForAny(
                [categoryConfirmation, referenceSelection,
                 resultTitle, insufficient, missingReference, loadError],
                timeout: 240
            ),
            "\(caseNumber)번 상품 분석이 제한 시간 안에 끝나야 합니다."
        )

        if loadError.exists {
            capture(name: "ui30-\(caseNumber)-load-error-\(expectedProductText)")
            XCTFail("\(caseNumber)번 상품을 불러오지 못했습니다: \(loadError.label)")
            dismissComparisonSheetIfNeeded()
            return
        }

        if categoryConfirmation.exists {
            tapHittableButton(named: "비교하기", timeout: 10)
            XCTAssertTrue(
                waitForAny(
                    [referenceSelection, resultTitle, insufficient, missingReference],
                    timeout: 30
                )
            )
        }

        if referenceSelection.exists {
            tapHittableButton(containing: expectedReferenceText, timeout: 10)
            XCTAssertTrue(
                waitForAny([resultTitle, insufficient], timeout: 15)
            )
        }

        if missingReference.exists {
            XCTAssertFalse(app.buttons["이 상품을 내 옷장에 추가"].exists)
            tapHittableButton(named: "내 옷장에서 기준 옷 선택", timeout: 10)
            tapHittableButton(containing: expectedReferenceText, timeout: 10)
        }

        XCTAssertTrue(
            waitForAny([resultTitle, insufficient], timeout: 240),
            "\(caseNumber)번은 비교 결과 또는 명시적인 근거 부족으로 끝나야 합니다."
        )
        if caseNumber % 5 == 0 || !resultTitle.exists {
            capture(name: "ui30-\(caseNumber)-result-\(expectedProductText)")
        }
        XCTAssertTrue(resultTitle.exists, comparisonFailureMessage())
        dismissComparisonSheetIfNeeded()
    }

    private func addClosetReference(url: String, expectedProductText: String) throws {
        app.activate()
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 8))
        app.buttons["새 작업"].tap()
        XCTAssertTrue(app.buttons["내 옷장에 추가"].waitForExistence(timeout: 5))
        app.buttons["내 옷장에 추가"].tap()
        tapHittableButton(containing: "상품 링크로 불러오기", timeout: 8)

        let urlField = app.textFields["상품 URL을 붙여넣어 주세요"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 8))
        urlField.tap()
        urlField.typeText(url)
        app.buttons["상품 정보 불러오기"].tap()

        let expectedProduct = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", expectedProductText)
        ).firstMatch
        let loadError = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "불러오지 못")
        ).firstMatch
        XCTAssertTrue(
            waitForEither(expectedProduct, loadError, timeout: 240),
            "상품 분석이 제한 시간 안에 완료되어야 합니다."
        )
        if loadError.exists {
            capture(name: "closet-load-error-\(expectedProductText)")
            XCTFail("상품 링크 내 옷장 추가가 실패했습니다: \(loadError.label)")
        }

        tapHittableButton(named: "다음", timeout: 10)
        tapHittableButton(named: "내 옷장에 추가", timeout: 10)
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 10))
        capture(name: "closet-saved-\(expectedProductText)")
    }

    private func shareFromSafariAndVerifyComparison(
        url: String,
        expectedProductText: String,
        expectedReferenceText: String
    ) throws {
        openURLInSafari(url)
        capture(application: safari, name: "safari-product-\(expectedProductText)")
        openSafariShareSheet()
        capture(application: springboard, name: "share-sheet-\(expectedProductText)")

        XCTAssertTrue(
            tapShareExtension(timeout: 20),
            "시스템 공유 시트에서 FitMatch 공유 확장을 찾을 수 있어야 합니다."
        )

        XCTAssertTrue(
            waitForStaticTextAcrossApplications(
                labels: ["FitMatch에 상품을 추가하고 있어요", "상품 링크를 FitMatch에 저장했어요"],
                timeout: 20
            )
        )
        XCTAssertTrue(tapButtonAcrossApplications(labels: ["보러가기"], timeout: 20))
        _ = tapButtonAcrossApplications(labels: ["열기", "Open"], timeout: 8)

        if !app.wait(for: .runningForeground, timeout: 30) {
            app.activate()
        }
        let resultTitle = app.navigationBars["비교 결과"]
        let insufficient = app.staticTexts["추천하기에 실측 정보가 부족해요"]
        let missingReference = app.staticTexts["기준 옷을 직접 선택해 주세요"]
        let referenceSelection = app.staticTexts["기준 옷 직접 선택"]
        let categoryConfirmation = app.staticTexts["상품 종류 확인"]

        let comparisonStarted = waitForAny(
            [categoryConfirmation, referenceSelection,
             resultTitle, insufficient, missingReference],
            timeout: 45
        )
        XCTAssertTrue(
            comparisonStarted,
            "공유 상품 분석이 제한 시간 안에 다음 단계로 진행되어야 합니다."
        )
        guard comparisonStarted else {
            capture(name: "comparison-not-started-\(expectedProductText)")
            return
        }

        if categoryConfirmation.exists {
            tapHittableButton(named: "비교하기", timeout: 10)
            XCTAssertTrue(
                waitForAny(
                    [referenceSelection, resultTitle, insufficient, missingReference],
                    timeout: 240
                ),
                "분류 확인 후 비교 대상 선택 또는 결과 화면으로 진행되어야 합니다."
            )
        }

        if referenceSelection.exists {
            tapHittableButton(containing: expectedReferenceText, timeout: 10)
            XCTAssertTrue(
                waitForAny([resultTitle, insufficient], timeout: 15),
                "추천 기준 옷을 선택하면 결과 화면으로 진행되어야 합니다."
            )
        }

        if missingReference.exists {
            XCTAssertFalse(app.buttons["이 상품을 내 옷장에 추가"].exists)
            tapHittableButton(named: "내 옷장에서 기준 옷 선택", timeout: 10)
            tapHittableButton(containing: expectedReferenceText, timeout: 10)
        }

        XCTAssertTrue(
            waitForAny([resultTitle, insufficient, missingReference], timeout: 240),
            "공유된 상품이 비교 결과 또는 명시적인 비교 불가 상태로 종료되어야 합니다."
        )
        capture(name: "comparison-result-\(expectedProductText)")
        XCTAssertTrue(resultTitle.exists, comparisonFailureMessage())
    }

    private func openURLInSafari(_ url: String) {
        safari.launch()

        let addressButton = safari.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "주소", "Address")
        ).firstMatch
        if addressButton.waitForExistence(timeout: 8) {
            addressButton.tap()
        } else {
            safari.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        }

        let addressField = safari.textFields.firstMatch
        XCTAssertTrue(addressField.waitForExistence(timeout: 8), safari.debugDescription)
        addressField.tap()
        let clearButton = safari.buttons["ClearTextButton"]
        if clearButton.waitForExistence(timeout: 3) {
            clearButton.tap()
        } else {
            addressField.typeKey("a", modifierFlags: .command)
            addressField.typeKey(.delete, modifierFlags: [])
        }
        addressField.typeText(url)
        let goButton = firstHittableElement(in: safari.buttons, labels: ["이동", "Go"])
        if goButton.waitForExistence(timeout: 3) {
            goButton.tap()
        } else {
            addressField.typeKey(.return, modifierFlags: [])
        }

        let moreButton = firstHittableElement(in: safari.buttons, labels: ["더 보기", "More"])
        XCTAssertTrue(moreButton.waitForExistence(timeout: 45), "Safari가 상품 페이지를 열어야 합니다.")

        let rejectCookies = firstHittableElement(
            in: safari.buttons,
            labels: ["모두 거부", "Reject all", "Reject All"]
        )
        if rejectCookies.waitForExistence(timeout: 5) {
            rejectCookies.tap()
        }
    }

    private func openSafariShareSheet() {
        let directShare = firstHittableElement(
            in: safari.buttons,
            labels: ["페이지 공유하기", "Share Page"]
        )
        if directShare.exists && directShare.isHittable {
            directShare.tap()
            return
        }

        let moreButton = firstHittableElement(in: safari.buttons, labels: ["더 보기", "More"])
        XCTAssertTrue(moreButton.waitForExistence(timeout: 10), "Safari 페이지 메뉴 버튼이 필요합니다.")
        moreButton.tap()

        let menuShare = firstHittableElement(in: safari.buttons, labels: ["공유", "Share"])
        XCTAssertTrue(menuShare.waitForExistence(timeout: 10), "Safari 페이지 메뉴에 공유 항목이 필요합니다.")
        menuShare.tap()
    }

    private func tapShareExtension(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for application in runningSystemApplications {
                let candidates = application.descendants(matching: .any).matching(
                    NSPredicate(
                        format: "label ==[c] %@ OR label CONTAINS[c] %@",
                        "FitMatch",
                        "FitMatch로 비교"
                    )
                ).allElementsBoundByIndex
                let direct = candidates.first(where: {
                    $0.isHittable
                        && $0.identifier != "breadcrumb"
                        && !$0.label.localizedCaseInsensitiveContains("돌아가기")
                        && !$0.label.localizedCaseInsensitiveContains("back to")
                })
                if let direct {
                    direct.tap()
                    return true
                }
            }

            let more = firstExistingButton(labels: ["더 보기", "More"])
            if more.exists && more.isHittable {
                more.tap()
                continue
            }

            for application in runningSystemApplications {
                if let collection = application.collectionViews.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                    collection.swipeLeft()
                }
            }
        }
        capture(application: springboard, name: "share-extension-not-found")
        return false
    }

    private func dismissComparisonSheetIfNeeded() {
        app.activate()
        if app.navigationBars["비교 결과"].exists {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            start.press(forDuration: 0.05, thenDragTo: end)
            if app.navigationBars["비교 결과"].waitForExistence(timeout: 2) {
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        let newTask = app.buttons["새 작업"]
        let predicate = NSPredicate { _, _ in newTask.exists && newTask.isHittable }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
    }

    private func tapHittableButton(named name: String, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let button = app.buttons.matching(identifier: name).allElementsBoundByIndex.first(where: { $0.isHittable }) {
                button.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        XCTFail("누를 수 있는 ‘\(name)’ 버튼이 필요합니다.\n\(app.debugDescription)")
    }

    private func tapHittableButton(containing text: String, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        repeat {
            if let button = app.buttons.matching(predicate).allElementsBoundByIndex.first(where: { $0.isHittable }) {
                button.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        XCTFail("누를 수 있는 ‘\(text)’ 포함 버튼이 필요합니다.\n\(app.debugDescription)")
    }

    private func tapButtonAcrossApplications(labels: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for application in runningApplications {
                let element = firstHittableElement(in: application.buttons, labels: labels)
                if element.exists && element.isHittable {
                    element.tap()
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return false
    }

    private func firstExistingButton(labels: [String]) -> XCUIElement {
        for application in runningApplications {
            let element = firstHittableElement(in: application.buttons, labels: labels)
            if element.exists {
                return element
            }
        }
        return app.buttons[labels[0]]
    }

    private func waitForStaticTextAcrossApplications(labels: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for application in runningApplications {
                for label in labels where application.staticTexts[label].exists {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return false
    }

    private var runningSystemApplications: [XCUIApplication] {
        [systemUI, springboard, safari].filter { $0.state != .notRunning }
    }

    private var runningApplications: [XCUIApplication] {
        [app] + runningSystemApplications
    }

    private func firstHittableElement(in query: XCUIElementQuery, labels: [String]) -> XCUIElement {
        for label in labels {
            let exact = query[label]
            if exact.exists && exact.isHittable {
                return exact
            }
            let containing = query.matching(
                NSPredicate(format: "label CONTAINS[c] %@", label)
            ).firstMatch
            if containing.exists && containing.isHittable {
                return containing
            }
        }
        return query[labels[0]]
    }

    private func waitForEither(_ first: XCUIElement, _ second: XCUIElement, timeout: TimeInterval) -> Bool {
        waitForAny([first, second], timeout: timeout)
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { _, _ in elements.contains { $0.exists } }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func comparisonFailureMessage() -> String {
        if app.staticTexts["기준 옷을 직접 선택해 주세요"].exists {
            return "자동 비교 후보는 없었고 저장한 기준 옷을 직접 선택하는 경로도 완료하지 못했습니다."
        }
        if app.staticTexts["추천하기에 실측 정보가 부족해요"].exists {
            return "기준 옷과 상품을 불러왔지만 추천에 필요한 호환 실측이 부족했습니다."
        }
        return "비교 결과 화면에 도달하지 못했습니다."
    }

    private func capture(application: XCUIApplication? = nil, name: String) {
        let attachment = XCTAttachment(screenshot: (application ?? app).screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
