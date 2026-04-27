import SwiftUI

#if DEBUG

/// Debug-only sheet for pasting in Databricks Service Principal credentials
/// (client ID + client secret) and persisting them to the Keychain.
///
/// In production, these credentials will arrive via a different flow — for example,
/// device-bound short-lived JWTs minted by the gateway after user registration.
/// For now, demos and field testing need a way to bootstrap the M2M SPN
/// credentials without hardcoding them in the bundle, so this paste-in UI is the
/// release-valve. Surface it through the About tab; never include in App Store builds.
struct SPNCredentialsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var clientID: String = ""
    @State private var clientSecret: String = ""
    @State private var savedFlash: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Client ID", text: $clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fontDesign(.monospaced)

                    SecureField("Client Secret", text: $clientSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fontDesign(.monospaced)
                } header: {
                    Text("Service Principal Credentials")
                } footer: {
                    Text("Stored in the iOS Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly). Used to obtain bearer tokens via OAuth client_credentials.")
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Label(savedFlash ? "Saved" : "Save to Keychain",
                              systemImage: savedFlash ? "checkmark.circle.fill" : "key.fill")
                    }
                    .disabled(clientID.isEmpty || clientSecret.isEmpty)

                    Button(role: .destructive) {
                        clear()
                    } label: {
                        Label("Clear Stored Credentials", systemImage: "trash")
                    }
                }

                Section {
                    statusRow(
                        "Client ID",
                        configured: KeychainHelper.exists(for: KeychainHelper.Key.databricksClientID)
                    )
                    statusRow(
                        "Client Secret",
                        configured: KeychainHelper.exists(for: KeychainHelper.Key.databricksClientSecret)
                    )
                } header: {
                    Text("Current Status")
                }
            }
            .navigationTitle("SPN Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func statusRow(_ label: String, configured: Bool) -> some View {
        HStack {
            Image(systemName: configured ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(configured ? DBXColors.dbxGreen : .secondary)
            Text(label)
            Spacer()
            Text(configured ? "Set" : "Not set")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        KeychainHelper.set(clientID, for: KeychainHelper.Key.databricksClientID)
        KeychainHelper.set(clientSecret, for: KeychainHelper.Key.databricksClientSecret)
        // Force the next API call to mint a fresh token using the new credentials.
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessToken)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessTokenExpiry)

        clientID = ""
        clientSecret = ""
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            savedFlash = false
        }
    }

    private func clear() {
        KeychainHelper.delete(for: KeychainHelper.Key.databricksClientID)
        KeychainHelper.delete(for: KeychainHelper.Key.databricksClientSecret)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessToken)
        KeychainHelper.delete(for: KeychainHelper.Key.oauthAccessTokenExpiry)
    }
}

#endif
