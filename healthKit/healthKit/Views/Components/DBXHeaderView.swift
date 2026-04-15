import SwiftUI

/// Reusable Databricks-branded header with wordmark, app name, and tagline.
struct DBXHeaderView: View {
    var showVersion: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            DatabricksWordmark(size: 18)

            Text("dbxWearables")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Apple HealthKit \u{2192} Databricks ZeroBus")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            if showVersion {
                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(DBXGradients.darkBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
