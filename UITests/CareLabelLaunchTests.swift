import XCTest

// Issue #1 bootstrap smoke test: the app launches and the registry root
// (issue #5, which replaced the bootstrap home screen) comes up.

final class CareLabelLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesIntoRegistry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.navigationBars["My Garments"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["registry.empty"].exists)
    }
}
