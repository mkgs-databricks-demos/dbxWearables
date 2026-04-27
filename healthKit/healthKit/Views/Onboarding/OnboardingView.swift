import SwiftUI

/// First-launch onboarding flow. Six gated pages, programmatic navigation
/// (no swipe), full-screen cover from the parent. Forward progress is locked
/// behind per-page predicates; the final "Get Started" tap is the only path
/// that flips `hasCompletedOnboarding`.
///
/// Pages:
/// 1. Welcome
/// 2. ZeroBus explainer
/// 3. Data types
/// 4. API Credentials (QR-first)
/// 5. Sign in with Apple
/// 6. HealthKit permission → Get Started
///
/// Replay (from About tab): all gates read live state, so users with
/// credentials + auth + HealthKit access blow through to the end.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @StateObject private var permissionsViewModel: PermissionsViewModel
    @StateObject private var signInManager = AppleSignInManager()

    @State private var currentPage = 0
    @State private var canSaveCredentials: Bool = false
    @State private var triggerSaveCredentials: Int = 0
    @State private var credentialsRevision: Int = 0
    @State private var showSwitchWorkspaceAlert = false

    private let totalPages = 6

    init(
        isPresented: Binding<Bool>,
        hasCompletedOnboarding: Binding<Bool>,
        healthKitManager: HealthKitManager
    ) {
        self._isPresented = isPresented
        self._hasCompletedOnboarding = hasCompletedOnboarding
        self._permissionsViewModel = StateObject(
            wrappedValue: PermissionsViewModel(healthKitManager: healthKitManager)
        )
    }

    // MARK: - Lifecycle

    /// Mark onboarding complete and dismiss. Only callable from a successful
    /// terminal step — never from a swipe/drag/incidental dismissal.
    private func finishOnboarding() {
        hasCompletedOnboarding = true
        isPresented = false
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Programmatic page swap — no TabView, no swipe-to-skip-the-gate.
            ZStack {
                pageView(for: currentPage)
                    .id(currentPage)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: currentPage)

            // Page indicator + advance / back row
            VStack(spacing: 12) {
                pageIndicator

                primaryActionButton

                #if DEBUG
                debugSkipButton
                #endif

                if currentPage > 0 && currentPage < totalPages - 1 {
                    Button("Back") {
                        withAnimation { currentPage -= 1 }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .background(DBXColors.dbxLightGray)
        .interactiveDismissDisabled(true)
        .onAppear {
            advanceIfAlreadySatisfied()
        }
        .onChange(of: currentPage) { _, _ in
            // When manual nav (or blow-through) lands on a gated page whose
            // gate is already satisfied, keep advancing.
            advanceIfAlreadySatisfied()
        }
        .onChange(of: signInManager.authState.isAuthenticated) { _, _ in
            // If the user just completed sign-in on page 5, surface the
            // change immediately by recomputing the gate.
            advanceIfAlreadySatisfied()
        }
        .alert("Switch Workspace?", isPresented: $showSwitchWorkspaceAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Switch", role: .destructive) {
                clearWorkspaceAndCredentials()
            }
        } message: {
            Text("This clears your saved Databricks credentials and signs you out so you can configure a different workspace.")
        }
    }

    // MARK: - Page dispatch

    @ViewBuilder
    private func pageView(for page: Int) -> some View {
        switch page {
        case 0: welcomePage
        case 1: zeroBusPage
        case 2: dataTypesPage
        case 3: credentialsPage
        case 4: signInPage
        case 5: healthKitPage
        default: welcomePage
        }
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? DBXColors.dbxRed : DBXColors.dbxRed.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Primary action button (per-page)

    @ViewBuilder
    private var primaryActionButton: some View {
        switch currentPage {
        case 0, 1, 2:
            Button("Next") {
                withAnimation { currentPage += 1 }
            }
            .buttonStyle(DBXPrimaryButtonStyle(isFullWidth: true))

        case 3:
            // Credentials gate
            Button("Next") {
                withAnimation { currentPage += 1 }
            }
            .buttonStyle(DBXPrimaryButtonStyle(isFullWidth: true))
            .disabled(!credentialsConfigured)

        case 4:
            // Sign-in gate
            Button("Next") {
                withAnimation { currentPage += 1 }
            }
            .buttonStyle(DBXPrimaryButtonStyle(isFullWidth: true))
            .disabled(!signInManager.authState.isAuthenticated)

        case 5:
            // HealthKit gate / final
            if permissionsViewModel.isAuthorized {
                Button("Get Started") {
                    finishOnboarding()
                }
                .buttonStyle(DBXPrimaryButtonStyle(isFullWidth: true))
            } else {
                Button("Grant Access") {
                    Task { await permissionsViewModel.requestAuthorization() }
                }
                .buttonStyle(DBXPrimaryButtonStyle(isFullWidth: true))
            }

        default:
            EmptyView()
        }
    }

    #if DEBUG
    /// Debug-only escape hatch on the gated pages. Lets us iterate on the
    /// flow without a fully-working server-side auth pipeline.
    @ViewBuilder
    private var debugSkipButton: some View {
        switch currentPage {
        case 3:
            if !credentialsConfigured {
                Button("Skip for Now (DEBUG)") {
                    withAnimation { currentPage += 1 }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        case 4:
            if !signInManager.authState.isAuthenticated {
                Button("Skip for Now (DEBUG)") {
                    withAnimation { currentPage += 1 }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        case 5:
            if !permissionsViewModel.isAuthorized {
                Button("Skip for Now (DEBUG)") {
                    finishOnboarding()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }
    #endif

    // MARK: - Gate predicates

    private var credentialsConfigured: Bool {
        // `credentialsRevision` participates only as a SwiftUI dep — the
        // actual values come from Keychain/WorkspaceConfig directly.
        _ = credentialsRevision
        return KeychainHelper.exists(for: KeychainHelper.Key.databricksClientID)
            && KeychainHelper.exists(for: KeychainHelper.Key.databricksClientSecret)
            && WorkspaceConfig.isFullyConfigured
    }

    /// On entering the flow (or any page transition), auto-advance through
    /// pages whose gates are already satisfied. This is the "blow through"
    /// behavior for replay from About tab when everything's configured.
    private func advanceIfAlreadySatisfied() {
        // Only blow through forward, never auto-skip past the user's
        // current spot if they've manually backed up.
        if currentPage == 3 && credentialsConfigured {
            withAnimation { currentPage = 4 }
        }
        if currentPage == 4 && signInManager.authState.isAuthenticated {
            withAnimation { currentPage = 5 }
        }
        // Page 5 (HealthKit) requires an explicit Get Started tap — don't
        // auto-finish even if authorized, so the user always sees the
        // wrap-up screen.
    }

    private func clearWorkspaceAndCredentials() {
        KeychainHelper.delete(for: KeychainHelper.Key.databricksClientID)
        KeychainHelper.delete(for: KeychainHelper.Key.databricksClientSecret)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessToken)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessTokenExpiry)
        KeychainHelper.delete(for: KeychainHelper.Key.userJWT)
        KeychainHelper.delete(for: KeychainHelper.Key.userJWTExpiry)
        WorkspaceConfig.clear()
        signInManager.signOut()
        credentialsRevision += 1
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            DBXHeaderView()
                .padding(.horizontal)

            Text("Stream your Apple Health data to Databricks using ZeroBus for real-time analytics.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Page 2: What is ZeroBus?

    private var zeroBusPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 48))
                .foregroundStyle(DBXColors.dbxRed)

            Text("What is ZeroBus?")
                .font(.title2)
                .fontWeight(.bold)

            Text("ZeroBus is Databricks' built-in event streaming SDK. It decouples REST API intake from table writes, providing streaming semantics without managing Kafka or similar infrastructure.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            DataFlowDiagramView()
                .padding()
                .background(DBXColors.dbxNavy)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Page 3: Data Types

    private var dataTypesPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 48))
                .foregroundStyle(DBXColors.dbxRed)

            Text("What Data Is Sent")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 10) {
                Label("Steps, Distance, Energy", systemImage: "figure.walk")
                Label("Heart Rate, HRV, SpO2", systemImage: "heart.fill")
                Label("Workouts (70+ types)", systemImage: "figure.run")
                Label("Sleep Stages", systemImage: "bed.double.fill")
                Label("Activity Ring Summaries", systemImage: "circle.circle")
            }
            .font(.subheadline)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DBXColors.dbxCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)

            Text("Data is read-only and sent as NDJSON.\nThis app never writes to your Health data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Page 4: API Credentials

    private var credentialsPage: some View {
        VStack(spacing: 0) {
            if credentialsConfigured {
                // Replay path: already-configured user. Offer Continue (gate
                // is already satisfied) or Switch Workspace (clear + reconfig).
                replayCredentialsCard
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
            }

            CredentialsConfigForm(
                layout: .onboarding,
                canSave: $canSaveCredentials,
                triggerSave: $triggerSaveCredentials,
                onSaveCompleted: {
                    credentialsRevision += 1
                }
            )
            .id(credentialsRevision) // Force re-init when user picks "Switch"
        }
    }

    private var replayCredentialsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(DBXColors.dbxGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Already Configured")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(currentWorkspaceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Continue with this workspace, or switch to a different one. Switching clears your credentials and signs you out.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                showSwitchWorkspaceAlert = true
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Switch Workspace")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(12)
                .foregroundStyle(DBXColors.dbxRed)
                .background(DBXColors.dbxRed.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var currentWorkspaceLabel: String {
        if let label = WorkspaceConfig.label, !label.isEmpty {
            return label
        }
        return "Configured Workspace"
    }

    // MARK: - Page 5: Sign in with Apple

    private var signInPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(DBXColors.dbxRed)

                Text("Sign In with Apple")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Sign in with your Apple ID to create a secure session for syncing data to Databricks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                SignInWithAppleContent(signInManager: signInManager)
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Page 6: HealthKit permission / Get Started

    private var healthKitPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: permissionsViewModel.isAuthorized ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(permissionsViewModel.isAuthorized ? DBXColors.dbxGreen : DBXColors.dbxRed)

            Text(permissionsViewModel.isAuthorized ? "You're All Set!" : "Grant HealthKit Access")
                .font(.title2)
                .fontWeight(.bold)

            Text(permissionsViewModel.isAuthorized
                 ? "HealthKit access is granted. You can start syncing data to Databricks."
                 : "To send your health data to Databricks, this app needs read access to HealthKit.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            if let error = permissionsViewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }
}
