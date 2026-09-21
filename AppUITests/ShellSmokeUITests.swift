import XCTest

/// Launch-and-navigate smoke tests. They run the app on `-useFixtures`
/// (`InMemoryBackend` + `GTDFixtures.sampleSnapshot`), so **no real vault is ever touched** —
/// the durable rule in `CLAUDE.md` holds for UI tests too.
///
/// These check that the shell composes and routes; the behavioural acceptance runs
/// (process two cards, tick off and undo, run a routine to the end, complete a project action)
/// are written out step by step in `docs/MANUAL_TEST.md`, because they depend on accessibility
/// identifiers in the feature views that were written without a compiler and have to be
/// confirmed on a Mac first. Turn them into tests here as they are confirmed.
final class ShellSmokeUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-useFixtures"]
        app.launch()
        return app
    }

    override func setUp() {
        continueAfterFailure = false
    }

    func testAppLaunchesOnFixtures() {
        let app = launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    }

    #if os(iOS)
    /// N5 / STYLEGUIDE §4.2 — exactly four tabs, in the order Inbox · Next · Lists · Routines,
    /// and the app still opens on Next (E1).
    func testTheFourTabsAreThere() {
        let app = launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let tabs = app.tabBars.buttons
        XCTAssertTrue(tabs["Next"].waitForExistence(timeout: 10))
        XCTAssertTrue(tabs["Inbox"].exists)
        XCTAssertTrue(tabs["Lists"].exists)
        XCTAssertTrue(tabs["Routines"].exists)
        XCTAssertLessThan(tabs["Inbox"].frame.minX, tabs["Next"].frame.minX)
        XCTAssertLessThan(tabs["Next"].frame.minX, tabs["Lists"].frame.minX)
        XCTAssertLessThan(tabs["Lists"].frame.minX, tabs["Routines"].frame.minX)
        XCTAssertTrue(tabs["Next"].isSelected)
    }

    /// L5 — the Lists tab: a list with counts, pushing to a list's items. The row is a
    /// `NavigationLink` over a `Label`, not a plain `Text` row (unlike the Next list's
    /// `ActionRow`), so this asserts on the pushed navigation title rather than the row's own
    /// accessibility element, which is less certain to resolve to a single `staticTexts` match.
    func testListsTabPushesToAListsItems() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Lists"].tap()
        XCTAssertTrue(app.navigationBars["Lists"].waitForExistence(timeout: 10))
        let readRow = app.cells.containing(.staticText, identifier: "Read").firstMatch
        XCTAssertTrue(readRow.waitForExistence(timeout: 10))
        readRow.tap()
        XCTAssertTrue(app.navigationBars["Read"].waitForExistence(timeout: 10))
    }

    /// I1 — the inbox tab's only way into the queue is the primary button.
    func testInboxTabOffersProcessing() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Inbox"].tap()
        let process = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Process inbox")).firstMatch
        XCTAssertTrue(process.waitForExistence(timeout: 10))
    }

    /// P2 / P5 / P8 — the action detail: every text entry gives the keyboard back, the title is
    /// not repeated in the bar, and the action can be ticked off from here.
    func testActionDetailKeyboardCanBeDismissed() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Next"].waitForExistence(timeout: 20))
        let row = app.staticTexts["Reference letter from Prof. Weber"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        // Title · Why? · What? — the last one sits lowest, where the keyboard used to cover it.
        let what = app.textFields.element(boundBy: 2)
        XCTAssertTrue(what.waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars.staticTexts["Reference letter from Prof. Weber"].exists,
                       "P5: the title is repeated in the navigation bar")
        XCTAssertTrue(app.buttons["Done"].exists, "P8: no way to complete from the detail")

        what.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(what.isHittable, "P2: the focused field is under the keyboard")
        XCTAssertLessThanOrEqual(
            what.frame.maxY, app.keyboards.firstMatch.frame.minY + 1,
            "P2: the focused field is under the keyboard")
        let hide = app.toolbars.buttons["Done"].firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "P2: no Done above the keyboard")
        hide.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    /// A1 — a rename moves the note; the pushed detail follows it instead of popping.
    func testRenamingKeepsTheDetailOpen() {
        let app = launch()
        let row = app.staticTexts["Reference letter from Prof. Weber"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let title = app.textFields.element(boundBy: 0)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(" again")
        sleep(3)                                  // past the autosave debounce
        XCTAssertTrue(app.buttons["Open in Obsidian"].exists, "the detail was popped by the rename")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the rename took the keyboard away")
        title.typeText("\n")                      // Return submits, it never breaks the line
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        sleep(2)                                  // the rename lands now; the detail follows it
        XCTAssertTrue(app.buttons["Open in Obsidian"].exists, "the detail was popped by the rename")
    }

    /// P17 — capture from the inbox tab, in a short sheet whose buttons stay reachable.
    func testQuickCaptureFromTheInboxTab() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Inbox"].tap()
        let add = app.buttons["Quick capture"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let capture = app.buttons["Capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(capture.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
    }

    func testRoutinesTabListsTheSampleRoutines() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Routines"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Routines"].tap()
        XCTAssertTrue(app.staticTexts["Morning"].waitForExistence(timeout: 10))
    }
    #endif

    #if os(macOS)
    /// E3 — the sidebar sections of STYLEGUIDE §4.1 are all present.
    func testSidebarSectionsAreThere() {
        let app = launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        for section in ["Inbox", "Next", "Someday", "Waiting", "Projects", "Deferred"] {
            XCTAssertTrue(
                app.descendants(matching: .any)[section].waitForExistence(timeout: 10),
                "sidebar is missing \(section)")
        }
    }
    #endif
}
