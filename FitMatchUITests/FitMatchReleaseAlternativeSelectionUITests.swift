import XCTest

/// P03 read-only subset: alternative selection on an existing exact History.
/// Full other-Closet switching requires separately tracked mutation coverage.
final class FitMatchReleaseAlternativeSelectionUITests: XCTestCase {
    @MainActor
    func testExistingHistoryAlternativeSelection() throws {
        continueAfterFailure = false
        let configuration = try Configuration(ProcessInfo.processInfo.environment)
        let app = XCUIApplication(bundleIdentifier: "com.ljy4337.fitmatch.qa")
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        defer {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "P03-final-state"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }

        XCTAssertTrue(app.buttons["새 작업"].waitForExistence(timeout: 20),
                      "BLOCKED: log the dedicated QA account in through the normal app first.")
        tap(app.buttons["기록"])
        let histories = app.staticTexts.matching(NSPredicate(format: "label == %@", configuration.historyProductName))
        let exactHistory = NSPredicate { _, _ in
            histories.count == 1 && histories.element(boundBy: 0).isHittable
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: exactHistory, object: nil)],
                                     timeout: 30), .completed,
                       "BLOCKED: the verified exact History product name must match once; no fallback.")
        tap(histories.element(boundBy: 0))
        XCTAssertTrue(app.navigationBars["비교 결과"].waitForExistence(timeout: 15))
        try applyAlternative(configuration.alternativeSize, in: app)
        let changeCloset = app.buttons["비교할 내 옷 변경"]
        XCTAssertTrue(changeCloset.waitForExistence(timeout: 15))
        XCTAssertTrue(changeCloset.isEnabled)
        // Do not tap: History callers open a new historical-product flow that
        // can ingest/promote product observations before a candidate is chosen.
    }

    @MainActor
    private func applyAlternative(_ size: String, in app: XCUIApplication) throws {
        tap(app.buttons["다른 사이즈 비교"])
        XCTAssertTrue(app.navigationBars["다른 사이즈 비교"].waitForExistence(timeout: 15))
        let emptySelection = app.buttons["비교할 사이즈를 선택해 주세요"]
        XCTAssertTrue(emptySelection.waitForExistence(timeout: 15),
                      "A newly mounted result must have no selectedAlternativeSizeID.")
        XCTAssertFalse(emptySelection.isEnabled)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", 선택됨")).count, 0)

        let cards = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(size) 사이즈, "))
        let available = NSPredicate { _, _ in
            cards.count == 1 && cards.element(boundBy: 0).isHittable
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: available, object: nil)],
                                     timeout: 30), .completed,
                       "BLOCKED: the exact approved alternative must exist once and be visible.")
        let card = cards.element(boundBy: 0)
        XCTAssertFalse(card.label.contains("핏매치 추천 사이즈"),
                       "Fixture must name an approved nonrecommended alternative.")
        tap(card)
        XCTAssertTrue(card.isSelected)
        XCTAssertTrue(card.label.contains(", 선택됨"))
        tap(app.buttons["\(size) 사이즈로 분석하기"])
        XCTAssertTrue(app.staticTexts["비교 사이즈"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.navigationBars["다른 사이즈 비교"].exists)
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        let enabled = NSPredicate(format: "enabled == true AND hittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: element)],
                                     timeout: 30), .completed)
        element.tap()
    }

    private struct Configuration {
        let historyProductName: String
        let alternativeSize: String

        init(_ environment: [String: String]) throws {
            guard environment["FITMATCH_P03_READ_ONLY"] == "1",
                  environment["FITMATCH_P03_DEDICATED_ACCOUNT"] == "1",
                  environment["FITMATCH_P03_PROJECT_REF"] == "hnkplvyegonlhumlejst" else {
                throw NSError(domain: "FitMatchP03Blocked", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "BLOCKED: read-only development inspection and dedicated account required."])
            }
            func required(_ key: String) throws -> String {
                guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty else {
                    throw NSError(domain: "FitMatchP03Blocked", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "BLOCKED: missing \(key)"])
                }
                return value
            }
            historyProductName = try required("FITMATCH_P03_HISTORY_PRODUCT_NAME")
            alternativeSize = try required("FITMATCH_P03_ALTERNATIVE_SIZE")
        }
    }
}
