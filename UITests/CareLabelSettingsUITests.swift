import XCTest

// Issue #7 acceptance: Settings screen surfaces data lifecycle actions
// (backup export button, CSV export button, storage usage counters).
//
// Like the other UI tests, launches with -ui-testing to start from a clean state.

final class CareLabelSettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func go(toTab tab: String) {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "tab \(tab) not found")
        button.tap()
    }

    func testSettingsSectionsAndExportTriggers() throws {
        go(toTab: "Settings")
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 10),
            "Settings navigation title missing"
        )

        // Storage usage counter is visible
        XCTAssertTrue(
            app.staticTexts["Photo files"].waitForExistence(timeout: 5),
            "Photo files counter missing"
        )

        // Backup export creation button triggers ShareLink
        let backupButton = app.buttons["settings.backup.create"]
        XCTAssertTrue(backupButton.waitForExistence(timeout: 5), "Backup button missing")
        backupButton.tap()

        let shareBackup = app.buttons["settings.backup.share"]
        XCTAssertTrue(shareBackup.waitForExistence(timeout: 5), "Share backup link missing")

        // CSV export creation button triggers ShareLink
        let csvButton = app.buttons["settings.csv.create"]
        XCTAssertTrue(csvButton.waitForExistence(timeout: 5), "CSV button missing")
        csvButton.tap()

        let shareCSV = app.buttons["settings.csv.share"]
        XCTAssertTrue(shareCSV.waitForExistence(timeout: 5), "Share CSV link missing")
    }
}
