import SwiftUI

/// Guided physical check. Its summary adds information and never replaces the model result.
struct PhysicalCheckView: View {
    let fruit: Fruit
    @State private var answers: [String: String] = [:]

    private var knowledge: FruitKnowledge? { KnowledgeBase.shared.knowledge(for: fruit) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let knowledge {
                    Text("Ikuti langkah berikut dan pilih jawaban yang paling sesuai.")
                        .foregroundStyle(.secondary)

                    ForEach(Array(knowledge.checkSteps.enumerated()), id: \.element.id) { index, step in
                        CheckStepCard(number: index + 1, step: step, selection: binding(for: step.id))
                    }

                    ForEach(knowledge.notes, id: \.self) { note in
                        Label(note, systemImage: "lightbulb")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !answers.isEmpty {
                        summary(knowledge)
                    }
                } else {
                    Label("Panduan cek fisik untuk buah ini belum tersedia.", systemImage: "exclamationmark.triangle")
                        .card()
                }
            }
            .padding(Spacing.l)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Cek fisik \(fruit.displayName)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for stepID: String) -> Binding<String?> {
        Binding(
            get: { answers[stepID] },
            set: { answers[stepID] = $0 }
        )
    }

    private func summary(_ knowledge: FruitKnowledge) -> some View {
        let suggestion = PhysicalCheckSummary.suggestion(steps: knowledge.checkSteps, answers: answers)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Ringkasan")
                .font(.headline)
            if let suggestion {
                Label("Cek fisik menunjukkan: \(suggestion.title.lowercased()).", systemImage: suggestion.symbolName)
                    .foregroundStyle(.primary)
            } else {
                Text("Hasil cek fisik belum mengarah ke satu kondisi.")
            }
            Text("Ringkasan ini melengkapi hasil foto, bukan menggantikannya.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .card(border: suggestion?.tint ?? Color(uiColor: .separator))
        .accessibilityElement(children: .combine)
    }
}

enum PhysicalCheckSummary {
    /// The state most answers point to, or nil when there is no clear majority.
    static func suggestion(steps: [CheckStep], answers: [String: String]) -> RipenessState? {
        var votes: [RipenessState: Int] = [:]
        for step in steps {
            guard let optionID = answers[step.id],
                  let state = step.options.first(where: { $0.id == optionID })?.suggestedState else { continue }
            votes[state, default: 0] += 1
        }
        let ranked = votes.sorted { $0.value > $1.value }
        guard let top = ranked.first else { return nil }
        if ranked.count > 1, ranked[1].value == top.value { return nil }
        return top.key
    }
}

#Preview {
    NavigationStack { PhysicalCheckView(fruit: .banana) }
}
