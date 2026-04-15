import SwiftUI

/// Visual representation of the data pipeline for the About screen.
/// Rendered as a sequence of branded nodes with arrow connectors.
struct DataFlowDiagramView: View {

    private let steps: [(icon: String, label: String)] = [
        ("applewatch", "Apple Watch"),
        ("heart.text.square", "HealthKit"),
        ("doc.text", "NDJSON"),
        ("server.rack", "AppKit API"),
        ("bolt.horizontal", "ZeroBus"),
        ("cylinder", "Unity Catalog"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        arrow
                    }
                    node(icon: step.icon, label: step.label, highlight: index >= 3)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    private func node(icon: String, label: String, highlight: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(highlight ? DBXColors.dbxRed : .white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(highlight ? DBXColors.dbxRed.opacity(0.15) : Color.white.opacity(0.1))
                )

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(width: 60)
        }
    }

    private var arrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(DBXColors.dbxRed.opacity(0.6))
    }
}
