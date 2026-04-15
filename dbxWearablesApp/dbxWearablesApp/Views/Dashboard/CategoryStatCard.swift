import SwiftUI

/// A compact stat card for the category summary grid on the Dashboard.
struct CategoryStatCard: View {
    let icon: String
    let label: String
    let count: Int

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(DBXColors.dbxRed)

            Text("\(count)")
                .font(DBXTypography.stat)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(label)
                .font(DBXTypography.statLabel)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .dbxCard()
    }
}
