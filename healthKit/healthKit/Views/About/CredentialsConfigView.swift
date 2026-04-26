import SwiftUI

/// Production-ready credentials configuration view for entering Databricks service principal
/// credentials (client ID + client secret) with secure Keychain storage.
///
/// Available in both DEBUG and RELEASE builds, accessible from About tab.
struct CredentialsConfigView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var clientID: String = ""
    @State private var clientSecret: String = ""
    @State private var showClientSecret = false
    @State private var saveStatus: SaveStatus = .idle
    @State private var showDeleteConfirmation = false
    @State private var showQRScanner = false
    
    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                instructionsSection
                credentialsInputSection
                actionsSection
                currentStatusSection
                securityInfoSection
            }
            .navigationTitle("API Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .alert("Delete Credentials", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { deleteCredentials() }
            } message: {
                Text("Are you sure you want to delete the stored credentials? You'll need to re-enter them to sync data.")
            }
            .fullScreenCover(isPresented: $showQRScanner) {
                QRCodeScannerView { clientID, clientSecret in
                    handleQRScan(clientID: clientID, clientSecret: clientSecret)
                }
            }
        }
    }
    
    // MARK: - Instructions
    
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
                
                // QR Code Scan Button
                Button {
                    showQRScanner = true
                } label: {
                    HStack {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan QR Code")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Quick setup for Databricks employees")
                                .font(.caption2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding(12)
                    .background(DBXColors.dbxRed.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                
                Divider()
                    .padding(.vertical, 4)
                
                Text("Or enter manually:")
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
    
    // MARK: - Credentials Input
    
    private var credentialsInputSection: some View {
        Section {
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
        } header: {
            Text("Credentials")
        } footer: {
            Text("Paste your service principal OAuth credentials. These will be stored securely in the iOS Keychain.")
        }
    }
    
    // MARK: - Actions
    
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
    
    // MARK: - Current Status
    
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
                "OAuth Token",
                isSet: KeychainHelper.exists(for: KeychainHelper.Key.oauthAccessToken),
                icon: "ticket.fill"
            )
        } header: {
            Text("Current Status")
        }
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
    
    // MARK: - Security Info
    
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
    
    // MARK: - Actions
    
    private var canSave: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        saveStatus != .saving
    }
    
    private var isConfigured: Bool {
        KeychainHelper.exists(for: KeychainHelper.Key.databricksClientID) &&
        KeychainHelper.exists(for: KeychainHelper.Key.databricksClientSecret)
    }
    
    private func save() {
        saveStatus = .saving
        
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate inputs
        guard !trimmedID.isEmpty else {
            saveStatus = .error("Client ID cannot be empty")
            return
        }
        
        guard !trimmedSecret.isEmpty else {
            saveStatus = .error("Client Secret cannot be empty")
            return
        }
        
        // Save to Keychain
        let idSaved = KeychainHelper.set(trimmedID, for: KeychainHelper.Key.databricksClientID)
        let secretSaved = KeychainHelper.set(trimmedSecret, for: KeychainHelper.Key.databricksClientSecret)
        
        guard idSaved && secretSaved else {
            saveStatus = .error("Failed to save credentials to Keychain")
            return
        }
        
        // Invalidate any cached OAuth tokens to force refresh with new credentials
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessToken)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessTokenExpiry)
        
        // Clear input fields
        clientID = ""
        clientSecret = ""
        
        // Show success
        saveStatus = .saved
        
        // Auto-dismiss after 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
    
    private func deleteCredentials() {
        KeychainHelper.delete(for: KeychainHelper.Key.databricksClientID)
        KeychainHelper.delete(for: KeychainHelper.Key.databricksClientSecret)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessToken)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessTokenExpiry)
        
        clientID = ""
        clientSecret = ""
        saveStatus = .idle
    }
    
    private func handleQRScan(clientID: String, clientSecret: String) {
        // Populate the fields with scanned credentials
        self.clientID = clientID
        self.clientSecret = clientSecret
        
        // Auto-save after successful scan
        save()
    }
}

#Preview {
    CredentialsConfigView()
}
