import SwiftUI
import AuthenticationServices

/// Sign in with Apple view for user authentication.
///
/// Shows:
/// - Sign in with Apple button
/// - Current auth status
/// - User info when authenticated
/// - Sign out option
struct SignInWithAppleView: View {
    @StateObject private var signInManager = AppleSignInManager()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    switch signInManager.authState {
                    case .unauthenticated:
                        unauthenticatedView
                    case .signingIn:
                        signingInView
                    case .authenticated:
                        authenticatedView
                    case .error(let message):
                        errorView(message)
                    }
                    
                    explanationSection
                }
                .padding()
            }
            .background(DBXColors.dbxLightGray)
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if signInManager.authState.isAuthenticated {
                        Button("Done") {
                            dismiss()
                        }
                    } else {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: signInManager.authState.isAuthenticated ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(signInManager.authState.isAuthenticated ? DBXColors.dbxGreen : DBXColors.dbxRed)
            
            Text(signInManager.authState.isAuthenticated ? "Authenticated" : "Sign In Required")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(signInManager.authState.isAuthenticated ?
                 "Your session is active and secure." :
                 "Sign in with your Apple ID to sync health data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }
    
    // MARK: - Unauthenticated
    
    private var unauthenticatedView: some View {
        VStack(spacing: 20) {
            SignInWithAppleButton(.signIn) { request in
                signInManager.prepareRequest(request)
            } onCompletion: { result in
                Task {
                    await signInManager.completeSignIn(result: result)
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 12) {
                benefitRow(icon: "lock.shield", title: "Secure", description: "Your data is protected with end-to-end encryption")
                benefitRow(icon: "person.badge.shield.checkmark", title: "Private", description: "Apple doesn't track your activity")
                benefitRow(icon: "bolt.fill", title: "Fast", description: "Quick authentication with Face ID or Touch ID")
            }
            .padding()
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func benefitRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(DBXColors.dbxRed)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Signing In
    
    private var signingInView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Signing in...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
    }
    
    // MARK: - Authenticated
    
    private var authenticatedView: some View {
        VStack(spacing: 20) {
            if let user = signInManager.currentUser {
                VStack(spacing: 12) {
                    if let fullName = user.fullName {
                        Text(formatName(fullName))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    if let email = user.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    HStack {
                        Label("Session expires", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(user.jwtExpiresAt, style: .relative)
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Button(role: .destructive) {
                signInManager.signOut()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DBXSecondaryButtonStyle())
        }
    }
    
    // MARK: - Error
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            Text("Sign In Failed")
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                signInManager.resetForRetry()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DBXPrimaryButtonStyle())
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Explanation
    
    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why Sign In?")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("Your Apple ID is used to create a secure session with Databricks. This ensures that only you can upload your health data.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("Technical Details")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.top, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                technicalDetail("1", "Apple authenticates your identity")
                technicalDetail("2", "App exchanges Apple token for Databricks JWT")
                technicalDetail("3", "JWT used for all health data uploads")
                technicalDetail("4", "Session expires after 1 hour")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func technicalDetail(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number + ".")
                .fontWeight(.semibold)
                .foregroundStyle(DBXColors.dbxRed)
                .frame(width: 20, alignment: .leading)
            Text(text)
        }
    }
    
    // MARK: - Helpers
    
    private func formatName(_ components: PersonNameComponents) -> String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        return formatter.string(from: components)
    }
}

#Preview {
    SignInWithAppleView()
}
