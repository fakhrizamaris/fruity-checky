import SwiftUI

/// Icon + status text (+ optional confidence). Colour only on the icon and border.
struct StatusBadge: View {
    let state: RipenessState
    var confidenceText: String?

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 28

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Image(systemName: state.symbolName)
                .font(.system(size: iconSize))
                .foregroundStyle(state.tint)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(state.title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                if let confidenceText {
                    Text(confidenceText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .card(border: state.tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(state.title)" + (confidenceText.map { ", \($0)" } ?? ""))
    }
}

#Preview {
    VStack(spacing: Spacing.m) {
        ForEach(RipenessState.allCases) { state in
            StatusBadge(state: state, confidenceText: "Keyakinan 82%")
        }
    }
    .padding()
}
