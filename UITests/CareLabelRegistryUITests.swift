import XCTest

// Issue #5 acceptance: UI tests on iPhone simulator covering the core
// registry loop — add garment -> edit care caps -> symbol sheet ->
// photo attach happy path — plus search and the confirmed-delete rule.
//
// The app launches with -ui-testing, which wipes the app container at launch
// so each run starts from an empty registry, and exposes a deterministic
// test-photo source (the simulator has no camera and no seeded library).

final class CareLabelRegistryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    // MARK: - Helpers

    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Waits for an element, scrolling the screen upward while it is absent.
    /// A SwiftUI `Form` renders lazily: controls below the fold may not exist
    /// in the accessibility hierarchy at all until scrolled into view, so a
    /// plain waitForExistence on them can never succeed.
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

    /// Opens the editor via the toolbar + button and returns once the form is up.
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
        // Return on a single-line field dismisses the keyboard deterministically.
        nameField.typeText("\n")
    }

    private func saveEditor() {
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
    }

    /// Opens one care-axis mode picker (menu style) by its identifier.
    private func openAxisPicker(_ identifier: String) {
        let picker = anyElement(identifier)
        XCTAssertTrue(waitForElement(picker), "picker \(identifier) not visible")
        if !picker.isHittable { app.swipeUp() }
        picker.firstMatch.tap()
    }

    private func selectPickerOption(_ option: String) {
        // A SwiftUI menu-style Picker presents a system menu; items surface
        // as buttons or static text depending on presentation.
        let candidates = [
            app.collectionViews.buttons[option],
            app.tables.cells.buttons[option],
            app.tables.buttons[option],
            app.buttons[option],
            app.staticTexts[option],
        ]
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 2) {
                candidate.firstMatch.tap()
                return
            }
        }
        XCTFail("Picker option \"\(option)\" not found")
    }

    // MARK: - Tests

    /// Empty state shows; add-garment happy path lands a row on the list.
    func testAddGarmentFromEmptyState() throws {
        XCTAssertTrue(waitForElement(anyElement("registry.empty")))

        openAddEditor()
        typeGarmentName("Blue sweater")
        saveEditor()

        let row = app.staticTexts["Blue sweater"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        // Fully-unknown profile surfaces the "care not recorded" summary.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Care not recorded")
            ).firstMatch.exists
        )
    }

    /// Edit care caps -> plain-language preview updates -> symbol sheet opens
    /// with accessible glyph+meaning rows -> save persists the cap.
    func testEditCareCapsAndSymbolSheet() throws {
        openAddEditor()
        typeGarmentName("Wool cardigan")

        openAxisPicker("axis.wash.mode")
        selectPickerOption("Hand wash only")

        // The preview + axis summary now render the hand-wash rule.
        XCTAssertTrue(
            app.staticTexts["Hand wash only"].waitForExistence(timeout: 5),
            "preview did not update"
        )

        // Symbol reference sheet for the wash family.
        let sheetLink = anyElement("axis.sheet.wash")
        XCTAssertTrue(waitForElement(sheetLink), "wash symbol link not visible")
        if !sheetLink.isHittable { app.swipeUp() }
        sheetLink.tap()

        XCTAssertTrue(anyElement("sheet.wash").waitForExistence(timeout: 5))
        let symbolRow = anyElement("symbol.row.hand-wash")
        XCTAssertTrue(symbolRow.waitForExistence(timeout: 5))
        XCTAssertTrue(symbolRow.label.contains("wash tub with a hand dipping into it"))
        XCTAssertTrue(symbolRow.label.contains("Hand wash only"))

        // Back to the editor. The sheet's nav bar also hosts Cancel/Save, so
        // match ONLY the back button (labeled "Back" or the parent title).
        let backButton = app.navigationBars.buttons.matching(
            NSPredicate(format: "label == %@ OR label CONTAINS %@", "Back", "Add Garment")
        ).firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "symbol sheet back button not found")
        backButton.tap()
        saveEditor()

        XCTAssertTrue(app.staticTexts["Wool cardigan"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "1 of 5 care axes recorded")
            ).firstMatch.waitForExistence(timeout: 5)
        )
    }

    /// Photo attach happy path through the import seam: visible in the
    /// editor, persists on the registry row, and appears in the detail view.
    func testPhotoAttachPersists() throws {
        openAddEditor()
        typeGarmentName("Photo shirt")

        let attach = anyElement("editor.photo.test")
        XCTAssertTrue(attach.waitForExistence(timeout: 5))
        attach.tap()

        // Editor switches from picker to "Remove photo" once attached.
        XCTAssertTrue(
            app.buttons["editor.photo.remove"].waitForExistence(timeout: 10)
        )
        saveEditor()

        XCTAssertTrue(app.staticTexts["Photo shirt"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.images.matching(
                NSPredicate(format: "label CONTAINS %@", "Label photo of Photo shirt")
            ).firstMatch.waitForExistence(timeout: 5)
        )

        // Detail view shows the persisted photo and the unknown-axis rules.
        app.staticTexts["Photo shirt"].tap()
        XCTAssertTrue(
            app.images.matching(
                NSPredicate(format: "label CONTAINS %@", "Label photo of Photo shirt")
            ).firstMatch.waitForExistence(timeout: 5)
        )
        XCTAssertTrue(anyElement("detail.rules").exists)
    }

    /// Delete requires confirmation; confirming removes the row (and with it
    /// the cascaded wash log + photo per the documented rule).
    func testDeleteRequiresConfirmation() throws {
        openAddEditor()
        typeGarmentName("Delete me")
        saveEditor()
        XCTAssertTrue(app.staticTexts["Delete me"].waitForExistence(timeout: 10))

        app.staticTexts["Delete me"].swipeLeft()
        let deleteAction = app.buttons["Delete"]
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 5))
        deleteAction.tap()

        // Confirmation alert appears before anything is removed.
        let confirm = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(waitForElement(anyElement("registry.empty"), timeout: 10))
    }

    /// Search filters by name and by category display name.
    func testSearchByNameAndCategory() throws {
        for name in ["Red jacket", "Grey pants"] {
            openAddEditor()
            typeGarmentName(name)
            saveEditor()
        }
        XCTAssertTrue(app.staticTexts["Red jacket"].exists)
        XCTAssertTrue(app.staticTexts["Grey pants"].exists)

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        replaceText(of: searchField, with: "jacket")
        XCTAssertTrue(app.staticTexts["Red jacket"].exists)
        XCTAssertFalse(app.staticTexts["Grey pants"].exists)

        replaceText(of: searchField, with: "Top") // both default to the Top category
        XCTAssertTrue(app.staticTexts["Red jacket"].exists)
        XCTAssertTrue(app.staticTexts["Grey pants"].exists)
    }

    /// Replaces a field's text deterministically (backspaces the current
    /// value, then types the new one). XCUIElement has no public clearText.
    private func replaceText(of field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        for _ in current {
            field.typeText("\u{8}") // delete backwards
        }
        field.typeText(text)
    }
}
