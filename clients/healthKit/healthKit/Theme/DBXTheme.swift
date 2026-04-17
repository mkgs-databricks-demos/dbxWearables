import SwiftUI

// MARK: - Brand Colors

enum DBXColors {
    static let dbxRed = Color(red: 1.0, green: 0.212, blue: 0.129)           // #FF3621
    static let dbxOrange = Color(red: 1.0, green: 0.416, blue: 0.2)          // #FF6A33
    static let dbxDarkTeal = Color(red: 0.106, green: 0.192, blue: 0.224)    // #1B3139
    static let dbxNavy = Color(red: 0.051, green: 0.133, blue: 0.157)        // #0D2228
    static let dbxGreen = Color(red: 0.0, green: 0.663, blue: 0.447)         // #00A972
    static let dbxYellow = Color(red: 1.0, green: 0.757, blue: 0.027)        // #FFC107

    static let dbxLightGray = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
            : UIColor(red: 0.941, green: 0.949, blue: 0.961, alpha: 1)
    })

    static let dbxCardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
            : UIColor.white
    })
}

// MARK: - Gradients

enum DBXGradients {
    static let primary = LinearGradient(
        colors: [DBXColors.dbxRed, DBXColors.dbxOrange],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let darkBackground = LinearGradient(
        colors: [DBXColors.dbxNavy, DBXColors.dbxDarkTeal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroHeader = LinearGradient(
        colors: [DBXColors.dbxDarkTeal, DBXColors.dbxDarkTeal.opacity(0.85)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Typography

enum DBXTypography {
    static let heroTitle: Font = .system(size: 28, weight: .bold, design: .default)
    static let sectionHeader: Font = .system(size: 20, weight: .semibold)
    static let stat: Font = .system(size: 36, weight: .bold, design: .rounded)
    static let statLabel: Font = .system(size: 12, weight: .medium)
    static let mono: Font = .system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall: Font = .system(size: 10, weight: .regular, design: .monospaced)
}

// MARK: - View Modifiers

struct DBXCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(DBXColors.dbxCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

struct DBXGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DBXColors.dbxRed.opacity(0.2), lineWidth: 1)
            )
    }
}

extension View {
    func dbxCard() -> some View {
        modifier(DBXCardModifier())
    }

    func dbxGlassCard() -> some View {
        modifier(DBXGlassCardModifier())
    }
}

// MARK: - Databricks Wordmark

/// Stylized "databricks" text using brand colors as a placeholder logo.
struct DatabricksWordmark: View {
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 2) {
            Text("data")
                .font(.system(size: size, weight: .light))
                .foregroundStyle(.white)
            Text("bricks")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(DBXColors.dbxRed)
        }
    }
}
