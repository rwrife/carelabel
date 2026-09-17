import XCTest

final class CareLabelLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBootstrapHomeLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.otherElements["bootstrap.home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Care Label"].exists)
        XCTAssertTrue(app.staticTexts["Garment registry, care decoding, and basket tools arrive in the next milestones."].exists)
    }
}
