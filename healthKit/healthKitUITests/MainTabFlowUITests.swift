import XCTest

/// Smoke tests for the main tab bar flow. These run against a real launched
/// app and verify the surfaces an engineer demos on stage actually render —
/// the unit test layer can't reach SwiftUI rendering, navigation, or button
/// state transitions.
///
/// Onboarding is bypassed by passing `-hasCompletedOnboarding YES` as a
/// launch argument: UserDefaults reads the argument domain before the
/// standard domain, so the `@AppStorage` flag in `dbxWearablesApp` returns
/// `true` regardless of any prior persisted state.
final class MainTabFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // `-resetForUITests YES` wipes UserDefaults + Documents/sync_ledger so
        // each test gets a deterministic empty state. `-hasCompletedOnboarding
        // YES` then bypasses the onboarding sheet via the argument domain.
        app.launchArguments = [
            "-resetForUITests", "YES",
            "-hasCompletedOnboarding", "YES"
        ]
        // The launched app process does NOT inherit env vars from the test
        // runner — APIConfiguration.swift fatalErrors on launch without
        // these, so we hand them through `launchEnvironment`.
        app.launchEnvironment = [
            "DBX_API_BASE_URL": "https://test.databricks.com/apps/wearables",
            "DBX_WORKSPACE_HOST": "https://test.cloud.databricks.com"
        ]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Launch / Onboarding bypass

    func testLaunchSkippingOnboardingShowsDashboard() {
        // The tab bar is the most reliable indicator that onboarding was
        // bypassed — the onboarding sheet covers it entirely on first launch.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5),
                      "Tab bar should be visible after onboarding bypass")
    }

    // MARK: - Tab navigation

    func testAllFourTabsAreReachable() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        let dashboardTab = tabBar.buttons["Dashboard"]
        let dataTab = tabBar.buttons["Data"]
        let payloadsTab = tabBar.buttons["Payloads"]
        let aboutTab = tabBar.buttons["About"]

        XCTAssertTrue(dashboardTab.exists)
        XCTAssertTrue(dataTab.exists)
        XCTAssertTrue(payloadsTab.exists)
        XCTAssertTrue(aboutTab.exists)

        // Visit each tab and confirm its navigation title (or a known element)
        // has rendered. Use staticTexts because navigationTitle is rendered
        // as a static text in the navigation bar.
        dataTab.tap()
        XCTAssertTrue(app.navigationBars["Data Explorer"].waitForExistence(timeout: 3),
                      "Data tab should show 'Data Explorer' navigation bar")

        payloadsTab.tap()
        XCTAssertTrue(app.navigationBars["Payloads"].waitForExistence(timeout: 3),
                      "Payloads tab should show 'Payloads' navigation bar")

        aboutTab.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 3),
                      "About tab should show 'About' navigation bar")

        dashboardTab.tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 3),
                      "Dashboard tab should be reachable again after navigating away")
    }

    // MARK: - Dashboard

    func testDashboardShowsSyncButtonAndStatusCard() {
        // On simulator, the app fires an auto-sync at launch via the observer
        // query (background delivery registration). HealthKit returns zero
        // records and the sync resolves to .success in under a second, so the
        // SyncStatusCard label transitions from "Sync Now" → "Sync Again".
        // We accept either — the contract we want to pin down is "the sync
        // button is reachable on the Dashboard".
        let syncNow = app.buttons["Sync Now"]
        let syncAgain = app.buttons["Sync Again"]
        let predicate = NSPredicate(format: "exists == 1")
        let either = expectation(for: predicate, evaluatedWith: syncNow, handler: nil)
        let either2 = expectation(for: predicate, evaluatedWith: syncAgain, handler: nil)
        let result = XCTWaiter().wait(for: [either, either2], timeout: 5, enforceOrder: false)
        XCTAssertTrue(
            result == .completed || syncNow.exists || syncAgain.exists,
            "Either 'Sync Now' or 'Sync Again' should be visible on the Dashboard"
        )

        // The "Recent Activity" section header is always present on the
        // Dashboard regardless of sync state.
        XCTAssertTrue(app.staticTexts["Recent Activity"].exists,
                      "Recent Activity section should anchor the bottom of the Dashboard")
    }

    func testDashboardCategoryGridLabelsAreVisible() {
        // The Dashboard's "Data Sent" grid lists every record type. These
        // labels are user-visible and worth pinning down — if a label is
        // accidentally renamed the demo loses its anchors.
        XCTAssertTrue(app.staticTexts["Data Sent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Health Samples"].exists)
        XCTAssertTrue(app.staticTexts["Workouts"].exists)
        XCTAssertTrue(app.staticTexts["Sleep Sessions"].exists)
        XCTAssertTrue(app.staticTexts["Activity Days"].exists)
        XCTAssertTrue(app.staticTexts["Deletions"].exists)
    }

    // MARK: - Payloads tab empty state

    func testPayloadsTabShowsEmptyStateOnFirstLaunch() {
        app.tabBars.firstMatch.buttons["Payloads"].tap()
        XCTAssertTrue(app.staticTexts["No data sent yet"].waitForExistence(timeout: 5),
                      "Payloads tab should display empty-state copy when nothing's been synced")
    }

    // MARK: - Sync Now interaction

    func testTappingSyncDoesNotCrashAndKeepsTabBar() {
        // The button label is "Sync Now" before any sync and "Sync Again"
        // after one — see testDashboardShowsSyncButtonAndStatusCard for why.
        let syncNow = app.buttons["Sync Now"]
        let syncAgain = app.buttons["Sync Again"]
        let target: XCUIElement
        if syncNow.waitForExistence(timeout: 3) {
            target = syncNow
        } else {
            XCTAssertTrue(syncAgain.waitForExistence(timeout: 3),
                          "Either 'Sync Now' or 'Sync Again' must be present")
            target = syncAgain
        }
        target.tap()

        // What matters is that the Dashboard remains responsive and the tab
        // bar stays mounted after the sync resolves.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5),
                      "Tab bar must remain after sync completes")
        XCTAssertTrue(tabBar.buttons["Dashboard"].isSelected,
                      "Dashboard tab should remain selected through a sync")
    }
}
