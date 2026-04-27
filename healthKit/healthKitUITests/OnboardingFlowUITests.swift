import XCTest

/// Verifies the gated 6-page onboarding flow.
///
/// Pages: Welcome → ZeroBus → Data Types → API Credentials → Sign in with
/// Apple → HealthKit Permission → Get Started.
///
/// Launch arguments:
/// - `-hasCompletedOnboarding NO` — argument-domain override forces UserDefaults
///   to report the flag false, so onboarding shows on every launch.
/// - `-resetForUITests YES` — wipes UserDefaults + Documents/sync_ledger so each
///   case has a clean baseline.
/// - `-onboardingPrefillCredentials YES` — AppDelegate seeds Keychain +
///   WorkspaceConfig so the credentials gate reports satisfied at launch.
/// - `-onboardingSimulateSignedIn YES` — AppDelegate seeds a non-expired JWT
///   so AppleSignInManager.restoreSession() lands in `.authenticated`,
///   satisfying the sign-in gate without invoking real SIWA.
final class OnboardingFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Default: clean baseline, no prefill. Individual tests append more
        // launch args before calling launch().
        app.launchArguments = [
            "-resetForUITests", "YES",
            "-hasCompletedOnboarding", "NO"
        ]
        app.launchEnvironment = [
            "DBX_API_BASE_URL": "https://test.databricks.com/apps/wearables",
            "DBX_WORKSPACE_HOST": "https://test.cloud.databricks.com"
        ]
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Page presence

    func testOnboardingShowsWelcomeCopyOnFirstLaunch() {
        app.launch()
        let welcomeText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "ZeroBus")
        ).firstMatch
        XCTAssertTrue(welcomeText.waitForExistence(timeout: 5),
                      "Onboarding welcome page should mention ZeroBus")
    }

    func testNextButtonAdvancesToZeroBusPage() {
        app.launch()
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()
        XCTAssertTrue(app.staticTexts["What is ZeroBus?"].waitForExistence(timeout: 3),
                      "After tapping Next, the ZeroBus page should be visible")
    }

    func testCredentialsPageAppearsAfterDataTypes() {
        app.launch()
        // Welcome → ZeroBus → Data Types → Credentials. Tap Next 3x.
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap(); nextButton.tap(); nextButton.tap()

        // The credentials page surfaces a "Connect to Databricks" header and
        // a QR-scan CTA. Either is a sufficient signal.
        let header = app.staticTexts["Connect to Databricks"]
        XCTAssertTrue(header.waitForExistence(timeout: 3),
                      "Page 4 should show the credentials configuration header")
    }

    // MARK: - Gating

    func testCredentialsNextDisabledWhenNothingConfigured() {
        app.launch()
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap(); nextButton.tap(); nextButton.tap()

        // We should now be on the credentials page. There are multiple "Next"
        // buttons in the app over time, but the visible primary CTA on the
        // credentials page is gated until creds + WorkspaceConfig are set.
        // Without prefill, that means the bottom Next button is disabled.
        XCTAssertTrue(app.staticTexts["Connect to Databricks"].waitForExistence(timeout: 3))

        // Find the primary Next at the bottom action bar. It exists but is
        // not enabled.
        let bottomNext = app.buttons["Next"]
        XCTAssertTrue(bottomNext.exists)
        XCTAssertFalse(bottomNext.isEnabled,
                       "Credentials gate must keep the Next button disabled until configured")
    }

    func testCredentialsNextEnabledWhenPrefilled() {
        app.launchArguments.append(contentsOf: ["-onboardingPrefillCredentials", "YES"])
        app.launch()

        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap(); nextButton.tap(); nextButton.tap()

        // With creds prefilled at launch, the gate should land us *past*
        // page 4 via blow-through (advanceIfAlreadySatisfied). We may end up
        // on the sign-in page instead of the credentials page.
        let signInHeader = app.staticTexts["Sign In with Apple"]
        XCTAssertTrue(signInHeader.waitForExistence(timeout: 3),
                      "With prefilled credentials, blow-through should land on the sign-in page")
    }

    func testReplayBlowsThroughWhenAllConfigured() {
        // Both gates pre-satisfied via launch fixtures.
        app.launchArguments.append(contentsOf: [
            "-onboardingPrefillCredentials", "YES",
            "-onboardingSimulateSignedIn", "YES"
        ])
        app.launch()

        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap(); nextButton.tap(); nextButton.tap()

        // Should blow through pages 4 and 5 and land on the HealthKit /
        // Get Started page (page 6).
        let getStarted = app.buttons["Get Started"]
        let grantAccess = app.buttons["Grant Access"]
        XCTAssertTrue(
            getStarted.waitForExistence(timeout: 5) || grantAccess.waitForExistence(timeout: 1),
            "Replay onboarding with credentials + sign-in should land on the final HealthKit page"
        )
    }

    // MARK: - Final page contract

    func testFinalPageShowsDismissControlWhenConfigured() {
        app.launchArguments.append(contentsOf: [
            "-onboardingPrefillCredentials", "YES",
            "-onboardingSimulateSignedIn", "YES"
        ])
        app.launch()

        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap(); nextButton.tap(); nextButton.tap()

        // Final page exposes "Get Started" (HealthKit authorized) or
        // "Grant Access" (not yet authorized). Either is acceptable.
        let getStarted = app.buttons["Get Started"]
        let grantAccess = app.buttons["Grant Access"]
        XCTAssertTrue(
            getStarted.waitForExistence(timeout: 5) || grantAccess.exists,
            "Final onboarding page must show either 'Get Started' or 'Grant Access'"
        )
    }
}
