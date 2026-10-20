import SwiftUI

/// One physical-check step with selectable answers.
struct CheckStepCard: View {
    let number: Int
    let step: CheckStep
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Langkah \(number)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(step.instruction)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(step.options) { option in
                let isSelected = selection == option.id
                Button {
                    selection = option.id
                } label: {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        Text(option.label)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: TouchTarget.minimum)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .card()
    }
}

#Preview {
    @Previewable @State var selection: String?
    CheckStepCard(
        number: 1,
        step: CheckStep(id: "press", instruction: "Tekan lembut kulitnya.", options: [
            CheckOption(id: "hard", label: "Keras", suggests: "mentah"),
            CheckOption(id: "soft", label: "Sedikit lunak", suggests: "matang"),
        ]),
        selection: $selection
    )
    .padding()
}
