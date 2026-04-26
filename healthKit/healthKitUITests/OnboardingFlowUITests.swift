import XCTest

/// Verifies the first-launch onboarding actually shows up and walks through
/// its 4 pages. We launch with `-hasCompletedOnboarding NO` so the argument
/// domain forces UserDefaults to report the flag as false regardless of any
/// prior simulator state.
final class OnboardingFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "NO"]
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

    func testOnboardingShowsWelcomeCopyOnFirstLaunch() {
        // Page 1 (welcome) shows the dbxWearables wordmark + a tagline that
        // mentions ZeroBus. We assert on the tagline because it's regular
        // text and easy to find by partial match.
        let welcomeText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "ZeroBus")
        ).firstMatch
        XCTAssertTrue(welcomeText.waitForExistence(timeout: 5),
                      "Onboarding welcome page should mention ZeroBus")
    }

    func testNextButtonAdvancesToZeroBusPage() {
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()

        // Page 2 has a heading "What is ZeroBus?"
        XCTAssertTrue(app.staticTexts["What is ZeroBus?"].waitForExistence(timeout: 3),
                      "After tapping Next, the ZeroBus page should be visible")
    }

    func testFinalPageShowsDismissControl() {
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        // Tap Next 3 times to reach page 4 (the grant-access page).
        nextButton.tap()
        XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
        nextButton.tap()
        XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
        nextButton.tap()

        // Page 4 shows different controls depending on HealthKit auth status:
        //   - Authorized (typical on simulator):   "Get Started"
        //   - Not yet authorized (real device):     "Grant Access" + "Skip for Now"
        // We accept either path — the contract is that page 4 always exposes
        // *some* dismissal control.
        let getStarted = app.buttons["Get Started"]
        let grantAccess = app.buttons["Grant Access"]
        XCTAssertTrue(
            getStarted.waitForExistence(timeout: 3) || grantAccess.exists,
            "Final onboarding page must show either 'Get Started' or 'Grant Access'"
        )
    }

    func testDismissingOnboardingRevealsTabBar() {
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap(); nextButton.tap(); nextButton.tap()

        // Dismiss via whichever final-page control is shown — see
        // testFinalPageShowsDismissControl for the auth-state branching.
        let getStarted = app.buttons["Get Started"]
        let skip = app.buttons["Skip for Now"]
        if getStarted.waitForExistence(timeout: 3) {
            getStarted.tap()
        } else if skip.waitForExistence(timeout: 3) {
            skip.tap()
        } else {
            XCTFail("Final onboarding page exposed no dismissal button")
        }

        // The tab bar lives below the onboarding sheet, so it always exists
        // in the hierarchy. After dismiss, it should be hittable — that's the
        // signal we use to confirm the sheet went away.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        let dashboard = tabBar.buttons["Dashboard"]
        XCTAssertTrue(dashboard.isHittable,
                      "Dashboard tab must be hittable once the onboarding sheet dismisses")
    }
}
