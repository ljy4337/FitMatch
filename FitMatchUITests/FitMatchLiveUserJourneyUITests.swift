import XCTest

final class FitMatchLiveUserJourneyUITests: XCTestCase {
    private struct ClosetRegistrationCase {
        let provider: String
        let group: String
        let productID: String
        let productName: String
        let url: String
    }

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
    func testLiveClosetRegistrationAndDirectURLComparison() throws {
        try addClosetReference(
            url: uniqloReferenceURL,
            expectedProductText: "DRY-EX폴로셔츠"
        )
        try addClosetReference(
            url: musinsaReferenceURL,
            expectedProductText: "아이스펄스"
        )

        try compareFromDirectURL(
            url: uniqloComparisonURL,
            expectedProductText: "드라이컬러크루넥",
            expectedReferenceText: "DRY-EX폴로셔츠",
            caseNumber: 1
        )
        try compareFromDirectURL(
            url: musinsaComparisonURL,
            expectedProductText: "스탠넥 아노락",
            expectedReferenceText: "아이스펄스",
            caseNumber: 2
        )
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

    /// Live retailer regression for the actual Closet link-registration UI.
    /// The list is deliberately balanced at five upper and five lower garments
    /// per provider, and every item has an official retailer size table.
    /// `FITMATCH_CLOSET30_START_INDEX` lets a diagnosed live failure resume at
    /// the interrupted item without weakening or relabelling earlier results.
    @MainActor
    func testLiveThirtyRetailerClosetRegistrations() throws {
        continueAfterFailure = false
        executionTimeAllowance = 3_600
        let cases = thirtyClosetRegistrationCases
        XCTAssertEqual(cases.count, 30)
        XCTAssertEqual(Set(cases.map { "\($0.provider):\($0.productID)" }).count, 30)
        for provider in ["MUSINSA", "UNIQLO", "ZARA"] {
            let providerCases = cases.filter { $0.provider == provider }
            XCTAssertEqual(providerCases.count, 10)
            XCTAssertEqual(providerCases.filter { $0.group == "상의" }.count, 5)
            XCTAssertEqual(providerCases.filter { $0.group == "하의" }.count, 5)
        }

        let requestedStart = Int(
            ProcessInfo.processInfo.environment["FITMATCH_CLOSET30_START_INDEX"] ?? "1"
        ) ?? 1
        let startIndex = min(max(requestedStart, 1), cases.count)
        let requestedEnd = Int(
            ProcessInfo.processInfo.environment["FITMATCH_CLOSET30_END_INDEX"]
                ?? String(cases.count)
        ) ?? cases.count
        let endIndex = min(max(requestedEnd, startIndex), cases.count)

        for (offset, testCase) in cases.enumerated()
            .dropFirst(startIndex - 1)
            .prefix(endIndex - startIndex + 1) {
            let index = offset + 1
            let uiMessage = try addClosetReference(
                url: testCase.url,
                expectedProductText: productTextProbe(testCase.productName)
            )
            print(
                "FITMATCH_CLOSET30_PASS index=\(index) provider=\(testCase.provider) "
                    + "group=\(testCase.group) product=\(testCase.productID) "
                    + "ui_message=\(uiMessage)"
            )
        }
    }

    @MainActor
    func testLiveTenUserJourneysThroughAppUI() throws {
        let cases = Array(try loadThirtyPairCases().prefix(10))
        XCTAssertEqual(cases.count, 10)

        let referenceCases = Dictionary(grouping: cases) {
            "\($0.brand):\($0.referenceProductID)"
        }.values.compactMap(\.first).sorted {
            ($0.brand, $0.categoryCode) < ($1.brand, $1.categoryCode)
        }

        for reference in referenceCases {
            try addClosetReference(
                url: reference.referenceURL,
                expectedProductText: productTextProbe(reference.referenceProductName)
            )
        }

        for (index, testCase) in cases.enumerated() {
            try compareFromDirectURL(
                url: testCase.comparisonURL,
                expectedProductText: productTextProbe(testCase.comparisonProductName),
                expectedReferenceText: productTextProbe(testCase.referenceProductName),
                caseNumber: index + 1
            )
            print(
                "FITMATCH_PHYSICAL_A_PASS index=\(index + 1) brand=\(testCase.brand) "
                    + "category=\(testCase.categoryCode) reference=\(testCase.referenceProductID) "
                    + "comparison=\(testCase.comparisonProductID)"
            )
        }
    }

    @MainActor
    func testLiveTwoHundredUserJourneysThroughAppUI() throws {
        continueAfterFailure = false
        executionTimeAllowance = 3_600
        let sourceCases = try loadThirtyPairCases()
        let musinsaCases = sourceCases.filter { $0.brand == "musinsa" }
        let uniqloCases = sourceCases.filter { $0.brand == "uniqlo" }
        XCTAssertEqual(musinsaCases.count, 15)
        XCTAssertEqual(uniqloCases.count, 15)

        let referenceCases = Dictionary(grouping: sourceCases) {
            "\($0.brand):\($0.referenceProductID)"
        }.values.compactMap(\.first).sorted {
            ($0.brand, $0.categoryCode) < ($1.brand, $1.categoryCode)
        }
        for reference in referenceCases {
            try addClosetReference(
                url: reference.referenceURL,
                expectedProductText: productTextProbe(reference.referenceProductName)
            )
        }

        let startedAt = Date()
        var completed = 0
        for index in 0..<200 {
            if Date().timeIntervalSince(startedAt) >= 3_540 {
                XCTFail("1시간 종료선에 도달했습니다. completed=\(completed)")
                break
            }
            let sourceIndex = (index / 2) % 15
            let testCase = index.isMultiple(of: 2)
                ? musinsaCases[sourceIndex]
                : uniqloCases[sourceIndex]
            try compareFromDirectURL(
                url: testCase.comparisonURL,
                expectedProductText: productTextProbe(testCase.comparisonProductName),
                expectedReferenceText: productTextProbe(testCase.referenceProductName),
                caseNumber: index + 1
            )
            completed += 1
            print(
                "FITMATCH_PHYSICAL_A200_CASE index=\(completed) brand=\(testCase.brand) "
                    + "category=\(testCase.categoryCode) reference=\(testCase.referenceProductID) "
                    + "comparison=\(testCase.comparisonProductID) result=PASS"
            )
            if completed.isMultiple(of: 10) {
                print(
                    "FITMATCH_PHYSICAL_A200_CHECKPOINT completed=\(completed) "
                        + "elapsed=\(Int(Date().timeIntervalSince(startedAt)))"
                )
            }
        }
        XCTAssertEqual(completed, 200)
    }

    @MainActor
    func testLiveDeleteMissingReferenceAndReregisterRecovery() throws {
        try addClosetReference(
            url: uniqloReferenceURL,
            expectedProductText: "DRY-EX폴로셔츠"
        )
        try compareFromDirectURL(
            url: uniqloComparisonURL,
            expectedProductText: "드라이컬러크루넥",
            expectedReferenceText: "DRY-EX폴로셔츠",
            caseNumber: 1
        )

        try deleteClosetItem(containing: "DRY-EX폴로셔츠")

        app.buttons["새 작업"].tap()
        tapHittableButton(named: "상품 비교", timeout: 8)
        let urlField = app.textFields["상품 URL을 붙여넣어 주세요"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 8))
        urlField.tap()
        urlField.typeText(uniqloComparisonURL)
        tapHittableButton(named: "비교하기", timeout: 8)

        let registrationButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "등록하기")
        ).firstMatch
        XCTAssertTrue(registrationButton.waitForExistence(timeout: 240))
        registrationButton.tap()

        XCTAssertTrue(
            app.staticTexts["내 옷 추가"].waitForExistence(timeout: 8),
            "비교할 옷이 없을 때 등록 방법을 먼저 선택할 수 있어야 합니다."
        )
        tapHittableButton(containing: "상품 링크로 불러오기", timeout: 8)

        let registrationURLField = app.textFields["상품 URL을 붙여넣어 주세요"]
        XCTAssertTrue(registrationURLField.waitForExistence(timeout: 8))
        registrationURLField.tap()
        registrationURLField.typeText(uniqloReferenceURL)
        tapHittableButton(named: "상품 정보 불러오기", timeout: 8)

        let product = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "DRY-EX폴로셔츠")
        ).firstMatch
        XCTAssertTrue(product.waitForExistence(timeout: 240))
        tapHittableButton(named: "다음", timeout: 10)
        tapHittableButton(named: "보유한 옷으로 등록", timeout: 10)

        XCTAssertTrue(
            waitForAny([
                app.staticTexts["비교할 옷 선택"],
                app.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "DRY-EX폴로셔츠")
                ).firstMatch
            ], timeout: 20),
            "재등록한 옷이 진행 중인 비교 후보에 다시 반영되어야 합니다."
        )
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
        let closetSelection = app.staticTexts["비교할 옷 선택"]
        let chooseClosetReference = app.buttons["내 옷장에서 기준 옷 선택"]
        let categoryConfirmation = app.staticTexts["상품 종류 확인"]
        let loadError = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "불러오지 못")
        ).firstMatch

        XCTAssertTrue(
            waitForAny(
                [categoryConfirmation, referenceSelection, closetSelection,
                 chooseClosetReference, resultTitle, insufficient, missingReference, loadError],
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
                    [referenceSelection, closetSelection, chooseClosetReference,
                     resultTitle, insufficient, missingReference],
                    timeout: 30
                )
            )
        }

        if chooseClosetReference.exists {
            chooseClosetReference.tap()
        }

        if referenceSelection.exists || closetSelection.exists {
            tapPreferredReferenceOrFirstCandidate(
                preferredText: expectedReferenceText,
                caseNumber: caseNumber
            )
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
        XCTAssertTrue(
            resultTitle.exists || insufficient.exists,
            comparisonFailureMessage()
        )
        dismissComparisonSheetIfNeeded()
    }

    @discardableResult
    private func addClosetReference(url: String, expectedProductText: String) throws -> String {
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

        let loadedProductName = app.staticTexts["closet.loadedProductName"]
        let loadError = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "불러오지 못")
        ).firstMatch
        XCTAssertTrue(
            waitForEither(loadedProductName, loadError, timeout: 240),
            "상품 분석이 제한 시간 안에 완료되어야 합니다."
        )
        if loadError.exists {
            capture(name: "closet-load-error-\(expectedProductText)")
            XCTFail("상품 링크 내 옷장 추가가 실패했습니다: \(loadError.label)")
        }
        XCTAssertTrue(
            loadedProductName.label.localizedCaseInsensitiveContains(expectedProductText),
            "요청한 상품과 다른 상품이 열렸습니다: \(loadedProductName.label)"
        )

        tapHittableButton(named: "다음", timeout: 10)
        tapHittableButton(named: "보유한 옷으로 등록", timeout: 10)
        let successToast = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "내 옷장에 추가했어요.")
        ).firstMatch
        XCTAssertTrue(
            successToast.waitForExistence(timeout: 8),
            "등록 완료 시 사용자에게 실제 성공 문구를 보여줘야 합니다."
        )
        let uiMessage = successToast.label
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 10))
        capture(name: "closet-saved-\(expectedProductText)")
        return uiMessage
    }

    private var thirtyClosetRegistrationCases: [ClosetRegistrationCase] {
        [
            .init(provider: "MUSINSA", group: "하의", productID: "3346165", productName: "윈드브레이커 와이드 밴딩 팬츠", url: "https://www.musinsa.com/products/3346165"),
            .init(provider: "MUSINSA", group: "하의", productID: "4818151", productName: "seersucker stripe pants", url: "https://www.musinsa.com/products/4818151"),
            .init(provider: "MUSINSA", group: "하의", productID: "3774997", productName: "우먼즈 레귤러 핏 데님 팬츠", url: "https://www.musinsa.com/products/3774997"),
            .init(provider: "MUSINSA", group: "하의", productID: "6908818", productName: "트레일 기어 팬츠", url: "https://www.musinsa.com/products/6908818"),
            .init(provider: "MUSINSA", group: "하의", productID: "6908820", productName: "트레일 기어 팬츠", url: "https://www.musinsa.com/products/6908820"),
            .init(provider: "MUSINSA", group: "상의", productID: "4341120", productName: "클래식 반소매 티셔츠", url: "https://www.musinsa.com/products/4341120"),
            .init(provider: "MUSINSA", group: "상의", productID: "4971043", productName: "메이크 아트 반소매 티셔츠", url: "https://www.musinsa.com/products/4971043"),
            .init(provider: "MUSINSA", group: "상의", productID: "5922490", productName: "Cotton Short Sleeve Henley Tee", url: "https://www.musinsa.com/products/5922490"),
            .init(provider: "MUSINSA", group: "상의", productID: "6590793", productName: "헨리넥 오버핏 반팔 티셔츠", url: "https://www.musinsa.com/products/6590793"),
            .init(provider: "MUSINSA", group: "상의", productID: "6595807", productName: "스트라이프 릴렉스드 긴소매 티셔츠", url: "https://www.musinsa.com/products/6595807"),

            .init(provider: "UNIQLO", group: "하의", productID: "E488397", productName: "EZY배럴진", url: "https://www.uniqlo.com/kr/ko/products/E488397-000"),
            .init(provider: "UNIQLO", group: "하의", productID: "E488630", productName: "EZY배럴진", url: "https://www.uniqlo.com/kr/ko/products/E488630-000"),
            .init(provider: "UNIQLO", group: "하의", productID: "E488684", productName: "스트레이트진", url: "https://www.uniqlo.com/kr/ko/products/E488684-000"),
            .init(provider: "UNIQLO", group: "하의", productID: "E489563", productName: "기어쇼트팬츠", url: "https://www.uniqlo.com/kr/ko/products/E489563-000"),
            .init(provider: "UNIQLO", group: "하의", productID: "E483512", productName: "데님쇼트팬츠", url: "https://www.uniqlo.com/kr/ko/products/E483512-000"),
            .init(provider: "UNIQLO", group: "상의", productID: "E491086", productName: "메리노블렌드헨리넥스웨터", url: "https://www.uniqlo.com/kr/ko/products/E491086-000"),
            .init(provider: "UNIQLO", group: "상의", productID: "E491294", productName: "코튼셔츠", url: "https://www.uniqlo.com/kr/ko/products/E491294-000"),
            .init(provider: "UNIQLO", group: "상의", productID: "E491297", productName: "코튼셔츠", url: "https://www.uniqlo.com/kr/ko/products/E491297-000"),
            .init(provider: "UNIQLO", group: "상의", productID: "E491380", productName: "옥스포드박시셔츠", url: "https://www.uniqlo.com/kr/ko/products/E491380-000"),
            .init(provider: "UNIQLO", group: "상의", productID: "E492123", productName: "데님릴렉스셔츠재킷", url: "https://www.uniqlo.com/kr/ko/products/E492123-000"),

            .init(provider: "ZARA", group: "하의", productID: "p08372248", productName: "배럴 팬츠", url: "https://www.zara.com/kr/ko/item-p08372248.html"),
            .init(provider: "ZARA", group: "하의", productID: "p04026158", productName: "레귤러핏 치노 팬츠", url: "https://www.zara.com/kr/ko/item-p04026158.html"),
            .init(provider: "ZARA", group: "하의", productID: "p01568383", productName: "울 - 리넨 수트 팬츠 AARON LEVINE X ZARA", url: "https://www.zara.com/kr/ko/item-p01568383.html"),
            .init(provider: "ZARA", group: "하의", productID: "p01608240", productName: "포플린 배럴 팬츠", url: "https://www.zara.com/kr/ko/item-p01608240.html"),
            .init(provider: "ZARA", group: "하의", productID: "p06861011", productName: "플리츠 치노 팬츠", url: "https://www.zara.com/kr/ko/item-p06861011.html"),
            .init(provider: "ZARA", group: "상의", productID: "p03431633", productName: "리오셀 반소매 티셔츠", url: "https://www.zara.com/kr/ko/item-p03431633.html"),
            .init(provider: "ZARA", group: "상의", productID: "p08054344", productName: "코튼 린넨 헨리넥 티셔츠", url: "https://www.zara.com/kr/ko/item-p08054344.html"),
            .init(provider: "ZARA", group: "상의", productID: "p01887320", productName: "롱 슬리브 티셔츠", url: "https://www.zara.com/kr/ko/item-p01887320.html"),
            .init(provider: "ZARA", group: "상의", productID: "p01887423", productName: "스트라이프 자카드 티셔츠", url: "https://www.zara.com/kr/ko/item-p01887423.html"),
            .init(provider: "ZARA", group: "상의", productID: "p00264141", productName: "플루이드 레터링 티셔츠", url: "https://www.zara.com/kr/ko/item-p00264141.html")
        ]
    }

    private func deleteClosetItem(containing productText: String) throws {
        app.activate()
        tapHittableButton(named: "내 옷장", timeout: 8)
        tapHittableButton(containing: productText, timeout: 10)
        tapHittableButton(named: "편집", timeout: 8)

        let deleteButton = app.buttons["삭제"]
        for _ in 0..<6 where !deleteButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 8))
        deleteButton.tap()

        let destructiveConfirmation = app.alerts.buttons["삭제"]
        if destructiveConfirmation.waitForExistence(timeout: 3) {
            destructiveConfirmation.tap()
        }
        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 10))
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

        let tabOverviewDone = safari.buttons["DoneButton"]
        if tabOverviewDone.waitForExistence(timeout: 3), tabOverviewDone.isHittable {
            tabOverviewDone.tap()
        }

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
        addressField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
        let newTask = app.buttons["새 작업"]
        if !newTask.exists || !newTask.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            start.press(forDuration: 0.05, thenDragTo: end)
            if !newTask.waitForExistence(timeout: 2) || !newTask.isHittable {
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        let predicate = NSPredicate { _, _ in newTask.exists && newTask.isHittable }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
    }

    private func tapPreferredReferenceOrFirstCandidate(
        preferredText: String,
        caseNumber: Int
    ) {
        let preferred = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", preferredText)
        ).allElementsBoundByIndex.first(where: { $0.isHittable })
        if let preferred {
            preferred.tap()
            return
        }

        let comparisonCandidate = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                "실측",
                "비교 가능"
            )
        ).allElementsBoundByIndex.first(where: { $0.isHittable })
        guard let comparisonCandidate else {
            XCTFail("\(caseNumber)번에서 선택 가능한 비교 후보를 찾지 못했습니다.\n\(app.debugDescription)")
            return
        }
        print(
            "FITMATCH_PHYSICAL_A200_FALLBACK index=\(caseNumber) "
                + "preferred=\(preferredText) selected=\(comparisonCandidate.label)"
        )
        comparisonCandidate.tap()
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
