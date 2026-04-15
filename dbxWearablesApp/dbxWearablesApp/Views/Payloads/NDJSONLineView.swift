import SwiftUI

/// An expandable NDJSON line shown in the Payload Inspector.
/// Collapsed: truncated single-line preview. Expanded: pretty-printed JSON.
struct NDJSONLineView: View {
    let line: PayloadLine
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Text("\(line.id + 1)")
                        .font(DBXTypography.monoSmall)
                        .foregroundStyle(DBXColors.dbxRed.opacity(0.6))
                        .frame(width: 24, alignment: .trailing)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 12)

                    if isExpanded {
                        Text(line.fullJSON)
                            .font(DBXTypography.mono)
                            .foregroundStyle(DBXColors.dbxGreen)
                            .textSelection(.enabled)
                    } else {
                        Text(line.preview)
                            .font(DBXTypography.mono)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
