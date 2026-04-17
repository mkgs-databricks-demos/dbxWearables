import SwiftUI

/// Swipeable first-launch onboarding explaining ZeroBus, data flow, and HealthKit permissions.
/// Can be re-shown from the About tab.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @StateObject private var permissionsViewModel = PermissionsViewModel()
    @State private var currentPage = 0

    private let totalPages = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                zeroBusPage.tag(1)
                dataTypesPage.tag(2)
                getStartedPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Page indicator + navigation
            VStack(spacing: 16) {
                pageIndicator

                if currentPage < totalPages - 1 {
                    Button("Next") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(DBXPrimaryButtonStyle(isFullWidth: true))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .background(DBXColors.dbxLightGray)
        .interactiveDismissDisabled(currentPage == 3 && !permissionsViewModel.isAuthorized)
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? DBXColors.dbxRed : DBXColors.dbxRed.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
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

    // MARK: - Page 4: Get Started

    private var getStartedPage: some View {
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

            if permissionsViewModel.isAuthorized {
                Button("Get Started") {
                    isPresented = false
                }
                .buttonStyle(DBXPrimaryButtonStyle(isFullWidth: true))
                .padding(.horizontal, 24)
            } else {
                Button("Grant Access") {
                    Task { await permissionsViewModel.requestAuthorization() }
                }
                .buttonStyle(DBXPrimaryButtonStyle(isFullWidth: true))
                .padding(.horizontal, 24)
            }

            if let error = permissionsViewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }

            if !permissionsViewModel.isAuthorized {
                Button("Skip for Now") {
                    isPresented = false
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
