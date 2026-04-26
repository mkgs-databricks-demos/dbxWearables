import SwiftUI

/// Reusable Databricks-branded header with wordmark, app name, and tagline.
/// Matches the Dashboard hero header style with left alignment and gradient.
struct DBXHeaderView: View {
    var showVersion: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatabricksWordmark(size: 16)

            Text("dbxWearables")
                .font(DBXTypography.heroTitle)
                .foregroundStyle(.white)

            Text("HealthKit \u{2192} ZeroBus")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            if showVersion {
                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(DBXGradients.heroHeader)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
