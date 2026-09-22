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
        // The empty state is an accessibility group — query it as .any, not
        // .otherElements (SwiftUI groups surface as .group, not .other).
        XCTAssertTrue(
            app.descendants(matching: .any)["registry.empty"]
                .firstMatch.waitForExistence(timeout: 5)
        )
    }
}
