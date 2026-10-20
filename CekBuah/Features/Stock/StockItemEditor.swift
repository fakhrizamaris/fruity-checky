import SwiftData
import SwiftUI

/// Add a fruit by hand, or correct an existing one (state, days left, quantity).
struct StockItemEditor: View {
    enum Mode {
        case add
        case edit(StockItem)
    }

    let mode: Mode
    /// Test-clock "now", so a manual estimate starts counting from the simulated day.
    let now: Date
    /// Consume/discard from the editor; handled by the stock screen so the undo banner appears.
    var onOutcome: ((OutcomeKind) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var fruit: Fruit = .banana
    @State private var state: RipenessState = .unripe
    @State private var daysLeft: Double = 6
    @State private var quantity = 1
    @State private var hasPlan = false
    @State private var planDate = Date.now

    private static let states: [RipenessState] = [.unripe, .ripe, .overripe, .rotten]

    private var shelfLife: ShelfLife? { KnowledgeBase.shared.knowledge(for: fruit)?.shelfLife }

    var body: some View {
        NavigationStack {
            Form {
                Section("Buah") {
                    Picker("Jenis buah", selection: userChange($fruit)) {
                        ForEach(Fruit.enabled) { Text("\($0.emoji) \($0.displayName)").tag($0) }
                    }
                    .disabled(isEditing)
                    Stepper("Jumlah: \(quantity)", value: $quantity, in: 1...50)
                }

                Section {
                    Picker("Kondisi", selection: userChange($state)) {
                        ForEach(Self.states) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                    }
                    Stepper("Sisa hari: \(DaysText.remaining(daysLeft))", value: $daysLeft, in: -5...30, step: 1)
                } header: {
                    Text("Perkiraan")
                } footer: {
                    Text("Sisa hari terisi otomatis sesuai kondisi dan dapat disesuaikan.")
                }

                Section {
                    Toggle("Atur rencana konsumsi", isOn: $hasPlan)
                        .frame(minHeight: TouchTarget.minimum)
                    if hasPlan {
                        DatePicker("Tanggal", selection: $planDate, in: now..., displayedComponents: .date)
                        if let advice = previewEntry.planAdvice() {
                            Label(advice.text, systemImage: advice.symbolName)
                                .font(.footnote)
                        }
                    }
                } header: {
                    Text("Rencana konsumsi")
                } footer: {
                    Text("Rencana dibandingkan dengan perkiraan kematangan buah.")
                }

                if case .edit(let item) = mode {
                    if let onOutcome {
                        Section {
                            ForEach([OutcomeKind.consumed, .discarded], id: \.self) { kind in
                                Button("Tandai 1 \(kind.actionTitle.lowercased())", systemImage: kind.symbolName) {
                                    onOutcome(kind)
                                    dismiss()
                                }
                                .frame(minHeight: TouchTarget.minimum)
                            }
                        } footer: {
                            Text("Dicatat dalam ringkasan stok. Dapat diurungkan dari layar Stok.")
                        }
                    }
                    Section {
                        Button("Hapus (salah input)", role: .destructive) {
                            context.delete(item)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Ubah buah" : "Tambah buah")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Simpan") { save() } }
            }
            .onAppear(perform: load)
        }
    }

    /// The entry as it would be saved, used to check the eating plan live.
    private var previewEntry: QueueEntry {
        QueueEntry(id: UUID(), fruit: fruit, daysLeftAtEstimate: daysLeft, estimatedAt: now,
                   readyWithinDays: shelfLife?.readyWithinDays ?? 0, plannedEatDate: hasPlan ? planDate : nil)
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    /// Picker binding that refills days left from the table only when the user changes the value.
    private func userChange<Value: Equatable>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                guard newValue != binding.wrappedValue else { return }
                binding.wrappedValue = newValue
                daysLeft = (shelfLife?.defaultDaysLeft(for: state) ?? daysLeft).rounded()
            }
        )
    }

    private func load() {
        planDate = now.addingTimeInterval(2 * 86_400)
        guard case .edit(let item) = mode, let itemFruit = item.fruit else {
            fruit = Fruit.enabled.first ?? .banana
            daysLeft = shelfLife?.defaultDaysLeft(for: state) ?? daysLeft
            return
        }
        fruit = itemFruit
        state = item.state ?? .unripe
        quantity = item.quantity
        if let planned = item.plannedEatDate {
            hasPlan = true
            planDate = max(planned, now)
        }
        daysLeft = (item.entry()?.daysLeft(at: now) ?? item.daysLeftAtEstimate).rounded()
    }

    private func save() {
        switch mode {
        case .add:
            let item = StockItem(fruit: fruit, quantity: quantity, state: state,
                                 daysLeft: daysLeft, at: now, source: "manual")
            item.plannedEatDate = hasPlan ? planDate : nil
            context.insert(item)
        case .edit(let item):
            item.quantity = quantity
            item.plannedEatDate = hasPlan ? planDate : nil
            item.reestimate(daysLeft: daysLeft, state: state, at: now)
        }
        try? context.save()
        dismiss()
    }
}
