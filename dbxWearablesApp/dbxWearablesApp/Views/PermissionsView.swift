import SwiftUI

/// Guides the user through HealthKit authorization with an explanation of why each data type is needed.
struct PermissionsView: View {
    @StateObject private var viewModel = PermissionsViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Text("Health Data Access")
                .font(.title)
                .bold()

            Text("dbxWearables needs access to your health data to sync activity, heart rate, sleep, and workout information to your Databricks dashboard.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            GroupBox("Data we read") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Steps & Distance", systemImage: "figure.walk")
                    Label("Heart Rate & HRV", systemImage: "heart.fill")
                    Label("Active & Resting Energy", systemImage: "flame.fill")
                    Label("Workouts", systemImage: "figure.run")
                    Label("Sleep Analysis", systemImage: "bed.double.fill")
                    Label("Activity Rings", systemImage: "circle.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("We never write to your Health data.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Grant Access") {
                Task { await viewModel.requestAuthorization() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
