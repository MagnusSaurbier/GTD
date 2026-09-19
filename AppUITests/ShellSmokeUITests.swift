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
    /// N5 / STYLEGUIDE §4.2 — exactly three tabs, Next first.
    func testTheThreeTabsAreThere() {
        let app = launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let tabs = app.tabBars.buttons
        XCTAssertTrue(tabs["Next"].waitForExistence(timeout: 10))
        XCTAssertTrue(tabs["Inbox"].exists)
        XCTAssertTrue(tabs["Routines"].exists)
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
        for section in ["Inbox", "Next", "Backlog", "Waiting", "Maybe", "Projects", "Deferred"] {
            XCTAssertTrue(
                app.descendants(matching: .any)[section].waitForExistence(timeout: 10),
                "sidebar is missing \(section)")
        }
    }
    #endif
}
