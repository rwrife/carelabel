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

    /// Registry empty state, by its visible text. CI evidence (runs
    /// 35647411314 / 35777234043): the `registry.empty` identifier never
    /// surfaces (ContentUnavailableView does not bridge identifiers), while
    /// its label text always does.
    private func assertRegistryEmpty(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            waitForElement(app.staticTexts["No garments yet"], timeout: timeout),
            "empty state not visible"
        )
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

    /// Opens one care-axis mode picker by its identifier, falling back to the
    /// picker's visible value text. CI evidence (run 35777234043): SwiftUI
    /// menu-style Pickers and container-type views do not reliably surface
    /// their `accessibilityIdentifier` in the XCUITest hierarchy, but their
    /// visible text always does. All five axes default to the value
    /// "Not recorded", and the wash axis is the FIRST one in the form, so
    /// firstMatch disambiguates for the only picker the tests exercise.
    private func openAxisPicker(_ identifier: String) {
        let picker = anyElement(identifier)
        if waitForElement(picker, timeout: 4) {
            if !picker.isHittable { app.swipeUp() }
            picker.firstMatch.tap()
            return
        }
        // Return toward the top so the FIRST visible "Not recorded" value is
        // unambiguously the wash axis (the first axis in the form).
        app.swipeDown()
        app.swipeDown()
        // Match the picker's value cell EXACTLY. A CONTAINS predicate would
        // also match each axis header, whose unknown-state rule text is
        // "Care not recorded — check the label and add it" and precedes the
        // picker in the hierarchy. Menu pickers expose the current value in
        // `value` or as a standalone `label` depending on presentation.
        let valueText = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@ OR value ==[c] %@", "Not recorded", "Not recorded")
        ).firstMatch
        XCTAssertTrue(waitForElement(valueText), "picker \(identifier) not visible")
        valueText.tap()
    }

    private func selectPickerOption(_ option: String) {
        // The axis pickers use .navigationLink style: options open as a
        // pushed list whose rows are reliably queryable (menu popups were
        // not, CI run 35780364211). Selecting usually auto-pops; if the list
        // is still up after the tap, go back explicitly.
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
                // Selecting auto-pops the pushed list. If it did NOT (we are
                // still on the picker list — its nav title is the picker
                // label, e.g. "Wash"), pop via the back item ("Back" or the
                // editor title "Add Garment").
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

    // MARK: - Tests

    /// Empty state shows; add-garment happy path lands a row on the list.
    func testAddGarmentFromEmptyState() throws {
        assertRegistryEmpty()

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

        // Symbol reference sheet for the wash family. Prefer the identifier,
        // fall back to the link's visible label text (same hierarchy caveat).
        let sheetLink = anyElement("axis.sheet.wash")
        var link = sheetLink
        if !waitForElement(sheetLink, timeout: 4) {
            let linkText = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "Symbol reference — Wash")
            ).firstMatch
            XCTAssertTrue(waitForElement(linkText), "wash symbol link not visible")
            link = linkText
        }
        if !link.isHittable { app.swipeUp() }
        link.tap()

        // Sheet arrived: assert by nav title (identifier bridging on a List
        // is not proven in CI). The hand-wash row is asserted by its
        // VoiceOver label text — notation + meaning — not its identifier.
        // Generous scroll budget (CI run 35782956055 attempt 2): the sheet is
        // a page sheet — the FIRST swipeUp expands the detent instead of
        // scrolling — and the row is #19 of 21 in a virtualized List, so it
        // needs the expansion swipe plus a couple of real scrolls to mount.
        XCTAssertTrue(
            app.navigationBars["Wash symbols"].waitForExistence(timeout: 10),
            "wash symbol sheet did not open"
        )
        let symbolRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "wash tub with a hand dipping into it")
        ).firstMatch
        XCTAssertTrue(waitForElement(symbolRow, timeout: 24), "hand-wash symbol row not visible")
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

        XCTAssertTrue(waitForElement(app.staticTexts["No garments yet"], timeout: 10))
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
