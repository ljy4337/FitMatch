//
//  FitMatchUITestsLaunchTests.swift
//  FitMatchUITests
//
//  Created by 이진영 on 7/3/26.
//

import XCTest

final class FitMatchUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in t#imageLiteral(resourceName: "simulator_screenshot_1831E49B-B11C-45A8-83F1-4C76749A1A79.png")he app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
