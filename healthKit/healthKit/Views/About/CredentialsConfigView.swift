import SwiftUI

/// Sheet wrapper around `CredentialsConfigForm` for the About tab. Owns the
/// `NavigationStack`, Cancel/Save toolbar, and auto-dismiss-on-save behavior.
struct CredentialsConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var canSave: Bool = false
    @State private var triggerSave: Int = 0

    var body: some View {
        NavigationStack {
            CredentialsConfigForm(
                layout: .sheet,
                canSave: $canSave,
                triggerSave: $triggerSave,
                onSaveCompleted: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            )
            .navigationTitle("API Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { triggerSave += 1 }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }
}

/// Reusable credentials/workspace configuration form. Used by the About tab's
/// sheet wrapper and embedded in onboarding.
///
/// The two layouts:
/// - `.sheet` — full Form with current-workspace card, instructions, manual
///   inputs, status, and security info. Save is driven by the parent toolbar.
/// - `.onboarding` — QR-first hero CTA, scan-result confirmation, manual entry
///   collapsed inside a DisclosureGroup. Save runs implicitly on QR scan; the
///   onboarding "Next" gate observes Keychain/WorkspaceConfig directly.
struct CredentialsConfigForm: View {
    enum Layout {
        case sheet
        case onboarding
    }

    let layout: Layout

    /// Lets the parent toolbar (sheet layout) reflect input validity.
    @Binding var canSave: Bool

    /// Increment from the parent to request a save (sheet layout). The form
    /// observes the value and runs `save()` whenever it changes. Onboarding
    /// layout doesn't need this — it auto-saves after a successful scan.
    @Binding var triggerSave: Int

    /// Called after a successful save. Sheet layout uses this to schedule the
    /// auto-dismiss; onboarding ignores it (the gate flips and the user
    /// advances when they're ready).
    var onSaveCompleted: () -> Void = {}

    @State private var clientID: String = ""
    @State private var clientSecret: String = ""
    @State private var apiBaseURLInput: String = ""
    @State private var workspaceHostInput: String = ""
    @State private var workspaceLabelInput: String = ""
    @State private var showClientSecret = false
    @State private var showAdvancedURLs = false
    @State private var showManualEntry = false
    @State private var saveStatus: SaveStatus = .idle
    @State private var showDeleteConfirmation = false
    @State private var showQRScanner = false

    /// Forces re-evaluation of derived values after a save.
    @State private var configRevision: Int = 0

    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    var body: some View {
        Group {
            switch layout {
            case .sheet:
                sheetForm
            case .onboarding:
                onboardingForm
            }
        }
        .alert("Delete Credentials", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteCredentials() }
        } message: {
            Text("Delete the stored credentials and workspace URLs? You'll need to re-scan or re-enter them to sync data.")
        }
        .fullScreenCover(isPresented: $showQRScanner) {
            QRCodeScannerView { scan in
                handleQRScan(scan)
            }
        }
        .onChange(of: triggerSave) { _, _ in
            save()
        }
        .onChange(of: clientID) { _, _ in updateCanSave() }
        .onChange(of: clientSecret) { _, _ in updateCanSave() }
        .onChange(of: saveStatus) { _, _ in updateCanSave() }
        .onAppear { updateCanSave() }
    }

    // MARK: - Sheet form (today's full Form layout)

    private var sheetForm: some View {
        Form {
            currentWorkspaceSection
            instructionsSection
            credentialsInputSection
            workspaceURLsSection
            actionsSection
            currentStatusSection
            securityInfoSection
        }
    }

    // MARK: - Onboarding form (QR-first)

    private var onboardingForm: some View {
        ScrollView {
            VStack(spacing: 20) {
                onboardingHeader
                onboardingScanCTA
                if isConfigured {
                    onboardingScanResultCard
                }
                onboardingManualEntryDisclosure
            }
            .padding(.horizontal, 20)
        }
    }

    private var onboardingHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "qrcode")
                .font(.system(size: 48))
                .foregroundStyle(DBXColors.dbxRed)

            Text("Connect to Databricks")
                .font(.title2)
                .fontWeight(.bold)

            Text("Scan your workspace QR code to configure credentials in one step. Or enter them manually below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    private var onboardingScanCTA: some View {
        Button {
            showQRScanner = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title2)
                Text(isConfigured ? "Scan a Different Workspace" : "Scan Workspace QR Code")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(DBXColors.dbxRed)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var onboardingScanResultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(DBXColors.dbxGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workspace Configured")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(currentLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("API Base URL")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(currentBaseURLDisplay)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("Tap **Next** to continue.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .id(configRevision)
    }

    private var onboardingManualEntryDisclosure: some View {
        DisclosureGroup(isExpanded: $showManualEntry) {
            VStack(alignment: .leading, spacing: 16) {
                clientIDField
                clientSecretField
                onboardingURLFields
                Button {
                    save()
                } label: {
                    Text("Save Credentials")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DBXPrimaryButtonStyle(isFullWidth: true))
                .disabled(!canSave)

                saveStatusMessage
            }
            .padding(.top, 12)
        } label: {
            HStack {
                Image(systemName: "keyboard")
                    .foregroundStyle(DBXColors.dbxRed)
                Text("Or enter manually")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Current Workspace (sheet only)

    private var currentWorkspaceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: workspaceConfigured ? "building.2.crop.circle.fill" : "building.2.crop.circle")
                        .font(.title2)
                        .foregroundStyle(workspaceConfigured ? DBXColors.dbxGreen : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentLabel)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(currentBaseURLDisplay)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }

                Button {
                    showQRScanner = true
                } label: {
                    HStack {
                        Image(systemName: "qrcode.viewfinder")
                        Text(workspaceConfigured ? "Switch Workspace" : "Scan Workspace QR")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding(12)
                    .background(DBXColors.dbxRed.opacity(0.1))
                    .foregroundStyle(DBXColors.dbxRed)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .id(configRevision)
        } header: {
            Text("Current Workspace")
        } footer: {
            Text("Scan a workspace QR code to switch the entire context (base URL, workspace host, and SPN credentials) atomically.")
        }
    }

    // MARK: - Instructions (sheet only)

    private var instructionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundStyle(DBXColors.dbxRed)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Service Principal Required")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Enter your Databricks service principal credentials to enable secure data synchronization.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Manual entry:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    instructionStep(1, "Create a service principal in your Databricks workspace")
                    instructionStep(2, "Generate OAuth credentials (Client ID & Secret)")
                    instructionStep(3, "Enter the credentials below or scan QR code")
                    instructionStep(4, "Credentials are stored securely in iOS Keychain")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func instructionStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(DBXColors.dbxRed)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Credentials Input (sheet)

    private var credentialsInputSection: some View {
        Section {
            clientIDField
            clientSecretField

            saveStatusMessage
        } header: {
            Text("Credentials")
        } footer: {
            Text("Paste your service principal OAuth credentials. These will be stored securely in the iOS Keychain.")
        }
    }

    // MARK: - Field building blocks (shared)

    private var clientIDField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Client ID")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("abc123-def456-ghi789", text: $clientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.username)
                .fontDesign(.monospaced)
                .onChange(of: clientID) { _, _ in
                    saveStatus = .idle
                }
        }
        .padding(.vertical, 4)
    }

    private var clientSecretField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Client Secret")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showClientSecret.toggle()
                } label: {
                    Image(systemName: showClientSecret ? "eye.slash.fill" : "eye.fill")
                        .font(.caption)
                        .foregroundStyle(DBXColors.dbxRed)
                }
            }

            if showClientSecret {
                TextField("dapi••••••••••••", text: $clientSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.password)
                    .fontDesign(.monospaced)
                    .onChange(of: clientSecret) { _, _ in
                        saveStatus = .idle
                    }
            } else {
                SecureField("dapi••••••••••••", text: $clientSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.password)
                    .fontDesign(.monospaced)
                    .onChange(of: clientSecret) { _, _ in
                        saveStatus = .idle
                    }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var saveStatusMessage: some View {
        if case .saved = saveStatus {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DBXColors.dbxGreen)
                Text("Credentials saved successfully")
                    .font(.caption)
                    .foregroundStyle(DBXColors.dbxGreen)
            }
        }

        if case .error(let message) = saveStatus {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Workspace URLs (sheet)

    private var workspaceURLsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAdvancedURLs) {
                workspaceURLFieldsBody
            } label: {
                HStack {
                    Image(systemName: "link")
                        .foregroundStyle(DBXColors.dbxRed)
                    Text("Workspace URLs (manual)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
        } footer: {
            Text("Optional. Both URLs must be valid http(s) URLs. Leave blank to keep the currently-configured workspace (or fall back to the build-time DBX_API_BASE_URL / DBX_WORKSPACE_HOST environment variables).")
        }
    }

    private var workspaceURLFieldsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API Base URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://<ws>.databricksapps.com/<app>", text: $apiBaseURLInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .fontDesign(.monospaced)
                    .onChange(of: apiBaseURLInput) { _, _ in saveStatus = .idle }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace Host")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://<ws>.cloud.databricks.com", text: $workspaceHostInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .fontDesign(.monospaced)
                    .onChange(of: workspaceHostInput) { _, _ in saveStatus = .idle }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Label (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Field Eng Demo", text: $workspaceLabelInput)
                    .autocorrectionDisabled()
                    .onChange(of: workspaceLabelInput) { _, _ in saveStatus = .idle }
            }
            .padding(.vertical, 4)
        }
    }

    /// Onboarding-flavored URL fields (no DisclosureGroup wrapper).
    private var onboardingURLFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            workspaceURLFieldsBody
        }
    }

    // MARK: - Actions (sheet)

    private var actionsSection: some View {
        Section {
            if isConfigured {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Stored Credentials")
                    }
                }
            }
        }
    }

    // MARK: - Current Status (sheet)

    private var currentStatusSection: some View {
        Section {
            statusRow(
                "Client ID",
                isSet: KeychainHelper.exists(for: KeychainHelper.Key.databricksClientID),
                icon: "person.text.rectangle"
            )
            statusRow(
                "Client Secret",
                isSet: KeychainHelper.exists(for: KeychainHelper.Key.databricksClientSecret),
                icon: "key.fill"
            )
            statusRow(
                "Workspace URLs",
                isSet: WorkspaceConfig.isFullyConfigured,
                icon: "link"
            )
            statusRow(
                "OAuth Token",
                isSet: KeychainHelper.exists(for: KeychainHelper.Key.oauthAccessToken),
                icon: "ticket.fill"
            )
        } header: {
            Text("Current Status")
        }
        .id(configRevision)
    }

    private func statusRow(_ label: String, isSet: Bool, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(DBXColors.dbxRed)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: isSet ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSet ? DBXColors.dbxGreen : .secondary)
                Text(isSet ? "Set" : "Not set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Security Info (sheet)

    private var securityInfoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                securityPoint("lock.shield.fill", "Credentials are encrypted using iOS Keychain")
                securityPoint("iphone.slash", "Never synced to iCloud or other devices")
                securityPoint("hand.raised.fill", "Only accessible after device unlock")
                securityPoint("arrow.left.arrow.right.circle", "Used only for OAuth token exchange")
            }
            .padding(.vertical, 4)
        } header: {
            Text("Security & Privacy")
        } footer: {
            Text("Your credentials are stored with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, providing maximum security while allowing background sync.")
        }
    }

    private func securityPoint(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(DBXColors.dbxGreen)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Derived

    private var canSaveLocal: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        saveStatus != .saving
    }

    private func updateCanSave() {
        canSave = canSaveLocal
    }

    private var isConfigured: Bool {
        KeychainHelper.exists(for: KeychainHelper.Key.databricksClientID) &&
        KeychainHelper.exists(for: KeychainHelper.Key.databricksClientSecret)
    }

    private var workspaceConfigured: Bool {
        WorkspaceConfig.isFullyConfigured
    }

    private var currentLabel: String {
        if let label = WorkspaceConfig.label, !label.isEmpty {
            return label
        }
        return workspaceConfigured ? "Configured Workspace" : "No Workspace Configured"
    }

    private var currentBaseURLDisplay: String {
        APIConfiguration.configuredBaseURL?.absoluteString ?? "(scan QR or set DBX_API_BASE_URL)"
    }

    // MARK: - Save / Delete

    private func save() {
        saveStatus = .saving

        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedID.isEmpty else {
            saveStatus = .error("Client ID cannot be empty")
            return
        }

        guard !trimmedSecret.isEmpty else {
            saveStatus = .error("Client Secret cannot be empty")
            return
        }

        // Workspace URLs: optional, but if either is provided, both must
        // parse. We surface invalid URLs through saveStatus rather than
        // silently dropping them.
        let trimmedAPI = apiBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = workspaceHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let userProvidedURLs = !trimmedAPI.isEmpty || !trimmedHost.isEmpty

        var newAPIBase: URL?
        var newHost: URL?
        if userProvidedURLs {
            guard let api = WorkspaceConfig.validatedURL(from: trimmedAPI) else {
                saveStatus = .error("API Base URL must be a valid http(s) URL")
                return
            }
            guard let host = WorkspaceConfig.validatedURL(from: trimmedHost) else {
                saveStatus = .error("Workspace Host must be a valid http(s) URL")
                return
            }
            newAPIBase = api
            newHost = host
        }

        // Persist credentials.
        let idSaved = KeychainHelper.set(trimmedID, for: KeychainHelper.Key.databricksClientID)
        let secretSaved = KeychainHelper.set(trimmedSecret, for: KeychainHelper.Key.databricksClientSecret)

        guard idSaved && secretSaved else {
            saveStatus = .error("Failed to save credentials to Keychain")
            return
        }

        // Persist workspace URLs (only if user provided them in this save).
        if let api = newAPIBase, let host = newHost {
            let label = workspaceLabelInput.trimmingCharacters(in: .whitespacesAndNewlines)
            WorkspaceConfig.set(apiBaseURL: api, host: host, label: label.isEmpty ? nil : label)
        }

        // Invalidate any cached tokens — both the SPN OAuth and the user JWT
        // must be re-minted against the new credentials/workspace.
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessToken)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessTokenExpiry)
        KeychainHelper.delete(for: KeychainHelper.Key.userJWT)
        KeychainHelper.delete(for: KeychainHelper.Key.userJWTExpiry)

        // Clear input fields
        clientID = ""
        clientSecret = ""
        apiBaseURLInput = ""
        workspaceHostInput = ""
        workspaceLabelInput = ""

        saveStatus = .saved
        configRevision += 1

        onSaveCompleted()
    }

    private func deleteCredentials() {
        KeychainHelper.delete(for: KeychainHelper.Key.databricksClientID)
        KeychainHelper.delete(for: KeychainHelper.Key.databricksClientSecret)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessToken)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessTokenExpiry)
        KeychainHelper.delete(for: KeychainHelper.Key.userJWT)
        KeychainHelper.delete(for: KeychainHelper.Key.userJWTExpiry)
        WorkspaceConfig.clear()

        clientID = ""
        clientSecret = ""
        apiBaseURLInput = ""
        workspaceHostInput = ""
        workspaceLabelInput = ""
        saveStatus = .idle
        configRevision += 1
    }

    private func handleQRScan(_ scan: ScanResult) {
        clientID = scan.clientID
        clientSecret = scan.clientSecret
        if let api = scan.apiBaseURL {
            apiBaseURLInput = api.absoluteString
        }
        if let host = scan.workspaceHost {
            workspaceHostInput = host.absoluteString
        }
        if let label = scan.workspaceLabel {
            workspaceLabelInput = label
        }
        save()
    }
}

#Preview {
    CredentialsConfigView()
}
