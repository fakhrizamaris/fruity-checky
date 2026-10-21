import SwiftData
import SwiftUI

/// Fruits picked while shopping, grouped by kind and ripeness. Saving moves them to the stock queue.
struct BasketView: View {
    @Environment(Router.self) private var router
    @Environment(Basket.self) private var basket
    @Environment(\.modelContext) private var context
    @AppStorage(TestClock.offsetKey) private var offsetDays = 0.0
    @State private var confirmingClear = false

    private var stockable: [BasketItem] { basket.items.filter(\.canStock) }
    private var notStockable: [BasketItem] { basket.items.filter { !$0.canStock } }

    var body: some View {
        List {
            if basket.items.isEmpty {
                Section {
                    Text("Keranjang masih kosong. Arahkan kamera ke buah satu per satu, lalu pilih Ambil.")
                        .foregroundStyle(.secondary)
                    Button("Mulai pindai", systemImage: "camera.viewfinder") { router.push(.liveScan) }
                }
            } else {
                Section("Ringkasan") {
                    ForEach(basket.groups) { group in
                        HStack {
                            FruitLabelChip(kind: group.kind, ripeness: group.state?.title ?? "Kematangan belum tersedia",
                                           state: group.state, isPicked: false)
                            Spacer()
                            Text("\(group.count) buah")
                                .font(.headline.monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    ForEach(basket.items) { item in
                        BasketRow(item: item)
                            .swipeActions {
                                Button("Kembalikan", systemImage: "arrow.uturn.backward", role: .destructive) {
                                    basket.remove(item.id)
                                }
                            }
                    }
                } header: {
                    Text("Buah di keranjang")
                } footer: {
                    Text("Geser ke kiri untuk mengembalikan buah. Perkiraan hari adalah rata-rata umum, bukan pengukuran buahmu.")
                }

                Section {
                    Button {
                        saveToStock()
                    } label: {
                        Label("Simpan \(stockable.count) buah ke stok", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(stockable.isEmpty)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if !notStockable.isEmpty {
                        Text(notStockableText)
                    }
                }
            }
        }
        .navigationTitle("Keranjang")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !basket.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kosongkan", role: .destructive) { confirmingClear = true }
                }
            }
        }
        .confirmationDialog("Kosongkan keranjang?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Kosongkan \(basket.count) buah", role: .destructive) { basket.clear() }
        }
    }

    private var notStockableText: String {
        let rotten = notStockable.filter { $0.state == .rotten }.count
        let others = notStockable.count - rotten
        var parts: [String] = []
        if others > 0 { parts.append("\(others) buah belum bisa masuk stok karena kematangannya belum tersedia (alpukat, buah naga, atau buah yang belum dikenali)") }
        if rotten > 0 { parts.append("\(rotten) buah busuk tidak disimpan") }
        return parts.joined(separator: ". ") + ". Buah ini tetap di keranjang."
    }

    /// One stock entry per fruit kind and ripeness, so the queue shows "3 pisang" instead of three rows.
    private func saveToStock() {
        let now = TestClock.now(offsetDays: offsetDays)
        let byGroup = Dictionary(grouping: stockable) { "\($0.stockFruit?.rawValue ?? "")|\($0.state?.rawValue ?? "")" }
        for items in byGroup.values {
            guard let first = items.first, let fruit = first.stockFruit, let result = first.result else { continue }
            let state = result.state == .unsure ? (result.ranked.first?.state ?? .ripe) : result.state
            let estimates = items.compactMap(\.estimatedDays)
            let days = estimates.isEmpty
                ? KnowledgeBase.shared.knowledge(for: fruit)?.shelfLife?.defaultDaysLeft(for: state) ?? 0
                : estimates.reduce(0, +) / Double(estimates.count)
            context.insert(StockItem(fruit: fruit, quantity: items.count, state: state, daysLeft: days,
                                     at: now, source: "scan"))
        }
        try? context.save()
        let saved = Set(stockable.map(\.id))
        basket.removeAll { saved.contains($0.id) }
        router.popToRoot()
        router.push(.stock)
    }
}

private struct BasketRow: View {
    let item: BasketItem

    var body: some View {
        HStack(spacing: Spacing.m) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Color(uiColor: .secondarySystemBackground)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.kind?.emoji ?? "❔") \(item.kind?.displayName ?? "Belum dikenali")")
                    .font(.body.bold())
                Label {
                    Text(item.state?.title ?? "Kematangan belum tersedia")
                } icon: {
                    Image(systemName: item.state?.symbolName ?? "circle.dashed")
                        .foregroundStyle(item.state?.tint ?? .secondary)
                }
                .font(.subheadline)
                if let days = item.estimatedDays {
                    Text("Perkiraan: \(DaysText.remaining(days))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
