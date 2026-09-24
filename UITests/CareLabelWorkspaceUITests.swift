import XCTest

// Issue #6 acceptance: the core pre-wash journey on iPhone simulator —
// build basket -> see conflict -> log wash — plus symbol-reference
// browse/search and wash-log surfacing.
//
// Same harness as the registry tests: launch with -ui-testing wipes the
// container, so each run starts from an empty registry.

final class CareLabelWorkspaceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    // MARK: - Helpers (same hierarchy caveats as CareLabelRegistryUITests:
    // lazy Forms need scroll-aware waits; menu pickers surface by visible
    // text, not identifier)

    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    private func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        if element.waitForExistence(timeout: 2) { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            app.swipeUp()
            if element.waitForExistence(timeout: 2) { return true }
        }
        return false
    }

    private func openAddEditor() {
        let addButton = app.buttons["registry.add.toolbar"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "add button not found")
        addButton.tap()
        XCTAssertTrue(
            anyElement("editor.root").waitForExistence(timeout: 10),
            "editor did not appear"
        )
    }

    private func typeGarmentName(_ name: String) {
        let nameField = app.textFields["editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        nameField.typeText("\n")
    }

    /// Opens the wash-axis picker (first "Not recorded" value in the form —
    /// identical fallback to the registry tests' proven helper).
    private func openWashAxisPicker() {
        let picker = anyElement("axis.wash.mode")
        if waitForElement(picker, timeout: 4) {
            if !picker.isHittable { app.swipeUp() }
            picker.firstMatch.tap()
            return
        }
        app.swipeDown()
        app.swipeDown()
        let valueText = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@ OR value ==[c] %@", "Not recorded", "Not recorded")
        ).firstMatch
        XCTAssertTrue(waitForElement(valueText), "wash picker not visible")
        valueText.tap()
    }

    private func selectPickerOption(_ option: String) {
        let candidates = [
            app.tables.cells.staticTexts[option],
            app.collectionViews.cells.staticTexts[option],
            app.tables.cells.buttons[option],
            app.buttons[option],
            app.staticTexts[option],
        ]
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 3) {
                candidate.firstMatch.tap()
                if app.navigationBars["Wash"].exists {
                    let back = app.navigationBars.buttons.matching(
                        NSPredicate(format: "label == %@ OR label CONTAINS %@", "Back", "Add Garment")
                    ).firstMatch
                    if back.waitForExistence(timeout: 3) { back.tap() }
                }
                return
            }
        }
        XCTFail("Picker option \"\(option)\" not found")
    }

    private func saveEditor() {
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
    }

    /// Adds one garment through the editor. `washOption` is nil for
    /// leave-as-unrecorded, otherwise the wash mode picker option text.
    private func addGarment(named name: String, washOption: String?) {
        openAddEditor()
        typeGarmentName(name)
        if let washOption {
            openWashAxisPicker()
            selectPickerOption(washOption)
        }
        saveEditor()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
    }

    private func go(toTab tab: String) {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "tab \(tab) not found")
        button.tap()
    }

    /// Replaces a field's text deterministically (same as the registry tests).
    private func replaceText(of field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        for _ in current {
            field.typeText("\u{8}")
        }
        field.typeText(text)
    }

    // MARK: - Journey: build basket -> see conflict -> log wash

    func testBuildBasketSeeConflictLogWash() throws {
        // Two garments: a machine-washable tee and a hand-wash-only sweater.
        addGarment(named: "Cotton tee", washOption: "Machine wash")
        addGarment(named: "Wool sweater", washOption: "Hand wash only")

        // Wash log starts empty.
        go(toTab: "Wash Log")
        XCTAssertTrue(
            app.staticTexts["No washes logged yet"].waitForExistence(timeout: 10),
            "wash log should start empty"
        )

        // Basket: select both, keep the default plan (machine 40 °C normal),
        // evaluate.
        go(toTab: "Basket")

        // Tap both rows by their visible names (rows are Buttons whose a11y
        // label is "name, category" — CI evidence says List container
        // identifiers do not bridge reliably, so query globally).
        let tee = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Cotton tee")
        ).firstMatch
        XCTAssertTrue(waitForElement(tee), "Cotton tee not in basket picker")
        tee.tap()

        let sweater = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Wool sweater")
        ).firstMatch
        XCTAssertTrue(waitForElement(sweater), "Wool sweater not in basket picker")
        sweater.tap()

        let evaluate = app.buttons["basket.evaluate"]
        XCTAssertTrue(evaluate.waitForExistence(timeout: 5), "evaluate button missing")
        evaluate.tap()

        // Report arrives: the tee is safe, the sweater conflicts by name.
        // (Match the safe header text — Section identifiers cascade over
        // children in the XCUITest tree, per issue #5 CI evidence.)
        XCTAssertTrue(
            app.staticTexts["Compatibility report"].waitForExistence(timeout: 10),
            "report did not open"
        )
        let safeHeader = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Safe for this plan")
        ).firstMatch
        XCTAssertTrue(waitForElement(safeHeader), "safe section header not visible")

        let conflictRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "hand wash only")
        ).firstMatch
        XCTAssertTrue(
            waitForElement(conflictRow),
            "named conflict reason for the hand-wash sweater not visible"
        )
        XCTAssertTrue(conflictRow.label.contains("Wool sweater"))

        // One tap logs the wash for the safe group only (1 garment).
        let logButton = app.buttons["basket.report.log"]
        XCTAssertTrue(waitForElement(logButton), "log button not visible")
        XCTAssertTrue(logButton.label.contains("1"))
        logButton.tap()

        // The log button reports disabled once the group is logged (SwiftUI
        // .disabled maps to AXEnabled=false; the frame stays hittable).
        XCTAssertFalse(logButton.isEnabled)

        // Done pops back to the basket.
        let done = app.buttons["basket.report.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        // Registry row surfaces "Last washed" for the tee.
        go(toTab: "Garments")
        let lastWashed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Last washed")
        ).firstMatch
        XCTAssertTrue(waitForElement(lastWashed), "last-washed surfacing missing")
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Never washed")
            ).firstMatch.exists,
            "the unwashed sweater should say Never washed"
        )

        // Wash log now lists the logged machine wash for the tee. Rows are
        // combined accessibility elements (label CONTAINS, not exact
        // staticTexts — same hierarchy caveat as the symbol sheet).
        go(toTab: "Wash Log")
        let logHeader = app.staticTexts["Cotton tee"]
        XCTAssertTrue(
            waitForElement(logHeader),
            "logged garment not grouped in wash log"
        )
        let logRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Machine wash")
        ).firstMatch
        XCTAssertTrue(
            waitForElement(logRow),
            "logged method not visible in wash log"
        )
    }

    // MARK: - Symbol reference: browse by family + search by meaning

    func testSymbolReferenceSearchAndFamilyFilter() throws {
        go(toTab: "Symbols")
        XCTAssertTrue(
            app.navigationBars["Care Symbols"].waitForExistence(timeout: 10),
            "symbol screen not reached"
        )

        // Search narrows by meaning text; unrelated families disappear.
        // SymbolRows are merged accessibility elements (children: .ignore +
        // combined label), so match via `.any` label predicates, exactly as
        // the issue #5 sheet test does.
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        replaceText(of: searchField, with: "tumble")
        let tumbleRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Tumble dry")
        ).firstMatch
        XCTAssertTrue(
            waitForElement(tumbleRow),
            "tumble-dry symbols not found in search"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "soleplate cap")
            ).firstMatch.exists,
            "iron symbols should not match a tumble search"
        )

        // Family filter: a List-row Button (toolbar items on this searchable
        // screen never bridged into the XCUITest tree — CI runs
        // 35965330787 / 35967213600 / 35969146987) that opens a
        // confirmationDialog. On iPhone the dialog presents as an action
        // SHEET, not an alert (run 35971701876: alerts.buttons found
        // nothing); query the option globally — no other button in the
        // tree carries the "Ironing" label (section headers are StaticText).
        replaceText(of: searchField, with: "")
        let filter = app.buttons["symbols.family.filter"]
        XCTAssertTrue(waitForElement(filter, timeout: 5), "family filter row missing")
        filter.tap()
        let ironOption = app.buttons["Ironing"].firstMatch
        XCTAssertTrue(ironOption.waitForExistence(timeout: 5), "family dialog did not open")
        ironOption.tap()

        let ironRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "soleplate cap")
        ).firstMatch
        XCTAssertTrue(
            waitForElement(ironRow),
            "iron family rows not visible after filter"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "Machine wash at up to")
            ).firstMatch.exists,
            "wash rows should be filtered out"
        )
    }
}
