import SwiftUI

/// The two labels on a fruit box: kind and ripeness. Ripeness always has an icon and text
/// (never colour alone); a picked fruit also shows a check mark.
struct FruitLabelChip: View {
    let kind: ShelfFruit?
    let ripeness: String
    let state: RipenessState?
    let isPicked: Bool
    var compact = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if isPicked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("\(kind?.emoji ?? "❔") \(kind?.displayName ?? "Belum dikenali")")
                    .font((compact ? Font.caption2 : .caption).bold())
                Label {
                    Text(ripeness)
                } icon: {
                    Image(systemName: state?.symbolName ?? "circle.dashed")
                        .foregroundStyle(state?.tint ?? .secondary)
                }
                .font(compact ? .caption2 : .caption)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, compact ? 4 : Spacing.s)
        .padding(.vertical, compact ? 2 : Spacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
