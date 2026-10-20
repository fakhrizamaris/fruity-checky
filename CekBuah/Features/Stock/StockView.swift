import SwiftData
import SwiftUI

/// The stock queue: fruits to eat first at the front, fruits that need more time behind.
struct StockView: View {
    @Query(sort: \StockItem.addedAt) private var items: [StockItem]
    @Query(sort: \StockOutcome.date, order: .reverse) private var outcomes: [StockOutcome]
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TestClock.offsetKey) private var offsetDays = 0.0
    @AppStorage(NotificationSettings.enabledKey) private var notificationsEnabled = false
    @AppStorage(SettingsKey.testerMode) private var testerMode = false
    @State private var notificationDenied = false
    @State private var editing: StockItem?
    @State private var adding = false
    /// Last consume/discard action, shown with an Undo button for a few seconds.
    @State private var lastAction: StockOutcome?

    private var now: Date { TestClock.now(offsetDays: offsetDays) }

    /// Items in queue order, paired with their queue entry (fruits with quantity 0 are left out).
    private var queue: [(item: StockItem, entry: QueueEntry)] {
        let pairs = items.compactMap { item in item.entry().map { (item: item, entry: $0) } }
        let order = StockQueue.ordered(pairs.map(\.entry), at: now).map(\.id)
        return order.compactMap { id in pairs.first { $0.entry.id == id } }
    }

    private var summary: OutcomeSummary {
        OutcomeSummary.make(outcomes.compactMap { o in o.kind.map { (kind: $0, date: o.date, wasOverdue: o.wasOverdue) } },
                            since: now.addingTimeInterval(-30 * 86_400), until: now)
    }

    var body: some View {
        List {
            if summary.total > 0 { summarySection }

            if queue.isEmpty {
                Section {
                    Text("Belum ada buah tersimpan. Simpan dari hasil foto, atau ketuk + untuk menambah.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(StockStatus.allCases, id: \.self) { status in
                let rows = queue.filter { $0.entry.status(at: now) == status }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows, id: \.entry.id) { row in
                            StockRow(item: row.item, entry: row.entry, now: now,
                                     isFront: row.entry.id == queue.first?.entry.id,
                                     onOpen: { editing = row.item },
                                     onOutcome: { record($0, for: row.item) })
                                .swipeActions(edge: .leading) {
                                    Button(OutcomeKind.consumed.actionTitle, systemImage: OutcomeKind.consumed.symbolName) {
                                        record(.consumed, for: row.item)
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Hapus", systemImage: "minus.circle", role: .destructive) { delete(row.item) }
                                    Button(OutcomeKind.discarded.actionTitle, systemImage: OutcomeKind.discarded.symbolName) {
                                        record(.discarded, for: row.item)
                                    }
                                    .tint(.orange)
                                }
                                .contextMenu {
                                    Button(OutcomeKind.consumed.actionTitle, systemImage: OutcomeKind.consumed.symbolName) {
                                        record(.consumed, for: row.item)
                                    }
                                    Button(OutcomeKind.discarded.actionTitle, systemImage: OutcomeKind.discarded.symbolName) {
                                        record(.discarded, for: row.item)
                                    }
                                    Button("Ubah", systemImage: "pencil") { editing = row.item }
                                    Divider()
                                    Button("Hapus (salah input)", systemImage: "minus.circle", role: .destructive) {
                                        delete(row.item)
                                    }
                                }
                        }
                    } header: {
                        Label(status.title, systemImage: status.symbolName)
                    } footer: {
                        if status == StockStatus.allCases.last(where: { s in queue.contains { $0.entry.status(at: now) == s } }) {
                            Text("Urutan berdasarkan perkiraan umum pada suhu ruang. Ketuk buah untuk menyesuaikan.")
                        }
                    }
                }
            }

            reminderSection
            if testerMode { testClockSection }
        }
        .navigationTitle("Stok Buah")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Tambah buah", systemImage: "plus") { adding = true }
                    .accessibilityLabel("Tambah buah ke stok")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let lastAction { undoBanner(for: lastAction) }
        }
        .animation(reduceMotion ? nil : .default, value: lastAction?.persistentModelID)
        .sheet(item: $editing) { item in
            StockItemEditor(mode: .edit(item), now: now, onOutcome: { record($0, for: item) })
        }
        .sheet(isPresented: $adding) {
            StockItemEditor(mode: .add, now: now)
        }
        // Keep reminders in sync whenever the queue, the test clock or the setting changes.
        .task(id: scheduleKey) {
            await StockNotifier.reschedule(context: context, offsetDays: offsetDays, enabled: notificationsEnabled)
        }
        // Hide the undo banner after a few seconds.
        .task(id: lastAction?.persistentModelID) {
            guard lastAction != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            lastAction = nil
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: Spacing.m) {
                summaryTile(value: summary.consumed, title: "Dikonsumsi", symbol: "fork.knife", state: .ripe)
                summaryTile(value: summary.discarded, title: "Dibuang", symbol: "trash", state: .rotten)
            }
            if let ratio = summary.savedRatio {
                Text("\(Int((ratio * 100).rounded()))% buah dikonsumsi sebelum terbuang" +
                     (summary.consumedOnTime < summary.consumed
                        ? " · \(summary.consumed - summary.consumedOnTime) dikonsumsi setelah melewati perkiraan" : ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("30 hari terakhir", systemImage: "chart.bar")
        }
    }

    private func summaryTile(value: Int, title: String, symbol: String, state: RipenessState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func undoBanner(for outcome: StockOutcome) -> some View {
        let fruit = Fruit(rawValue: outcome.fruitRaw)
        let name = fruit.map { "\($0.emoji) \($0.displayName)" } ?? "Buah"
        return HStack(spacing: Spacing.m) {
            Text("1 \(name) \(outcome.kind?.pastTense ?? "diperbarui")")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Urungkan") { undo(outcome) }
                .font(.subheadline.bold())
                .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                .accessibilityLabel("Urungkan, kembalikan \(fruit?.displayName ?? "buah") ke stok")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.s)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }

    /// One fruit leaves the stock. The item stays (at quantity 0) so undo can bring it back.
    private func record(_ kind: OutcomeKind, for item: StockItem) {
        guard item.quantity > 0, let fruit = item.fruit else { return }
        let wasOverdue = item.entry()?.status(at: now) == .overdue
        item.quantity -= 1
        let outcome = StockOutcome(fruit: fruit, kind: kind, date: now, wasOverdue: wasOverdue, itemQueueID: item.queueID)
        context.insert(outcome)
        try? context.save()
        lastAction = outcome
    }

    private func undo(_ outcome: StockOutcome) {
        if let item = items.first(where: { $0.queueID == outcome.itemQueueID }) {
            item.quantity += 1
        }
        context.delete(outcome)
        try? context.save()
        lastAction = nil
    }

    private var scheduleKey: String {
        let parts = items.map { "\($0.queueID)\($0.daysLeftAtEstimate)\($0.estimatedAt.timeIntervalSince1970)\($0.quantity)" }
        return parts.joined() + "\(offsetDays)\(notificationsEnabled)"
    }

    private var reminderSection: some View {
        Section {
            Toggle("Pengingat buah siap dikonsumsi", isOn: Binding(
                get: { notificationsEnabled },
                set: { newValue in
                    guard newValue else { notificationsEnabled = false; return }
                    Task {
                        let granted = await StockNotifier.requestAuthorization()
                        notificationsEnabled = granted
                        notificationDenied = !granted
                    }
                }
            ))
            .frame(minHeight: TouchTarget.minimum)
            if notificationDenied {
                Text("Notifikasi belum diizinkan. Aktifkan melalui Pengaturan > Notifikasi > Orang BAIK.")
                    .font(.footnote)
            }
            if notificationsEnabled && testerMode {
                Button("Kirim notifikasi uji (5 detik)", systemImage: "bell.badge") {
                    Task { await StockNotifier.sendTest() }
                }
                .frame(minHeight: TouchTarget.minimum)
            }
        } header: {
            Label("Pengingat", systemImage: "bell")
        } footer: {
            Text("Anda akan diberi tahu saat buah siap dikonsumsi dan saat perlu diperiksa.")
        }
    }

    /// Lets testers jump days ahead instead of waiting for fruit to ripen.
    private var testClockSection: some View {
        Section {
            Text("Tanggal simulasi: \(now.formatted(date: .abbreviated, time: .omitted))" +
                 (offsetDays == 0 ? " (hari ini)" : " (\(offsetDays > 0 ? "+" : "")\(Int(offsetDays)) hari)"))
            HStack(spacing: Spacing.m) {
                Button("−1 hari") { offsetDays -= 1 }
                    .buttonStyle(PrimaryButtonStyle(prominent: false))
                    .accessibilityLabel("Mundurkan waktu simulasi satu hari")
                Button("+1 hari") { offsetDays += 1 }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityLabel("Majukan waktu simulasi satu hari")
            }
            if offsetDays != 0 {
                Button("Kembali ke hari ini") { offsetDays = 0 }
                    .frame(minHeight: TouchTarget.minimum)
            }
        } header: {
            Label("Penguji: simulasi waktu", systemImage: "clock.arrow.circlepath")
        } footer: {
            Text("Majukan hari untuk melihat perubahan urutan tanpa menunggu.")
        }
    }

    private func delete(_ item: StockItem) {
        context.delete(item)
        try? context.save()
    }
}

private struct StockRow: View {
    let item: StockItem
    let entry: QueueEntry
    let now: Date
    let isFront: Bool
    let onOpen: () -> Void
    let onOutcome: (OutcomeKind) -> Void

    var body: some View {
        let status = entry.status(at: now)
        HStack(spacing: Spacing.s) {
            Button(action: onOpen) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: status.symbolName)
                        .foregroundStyle(status.state.tint)
                        .font(.title3)
                        .frame(minWidth: 28)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("\(entry.fruit.emoji) \(entry.fruit.displayName)" + (item.quantity > 1 ? " ×\(item.quantity)" : ""))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(detail(status))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let advice = entry.planAdvice(), let planned = entry.plannedEatDate {
                            Label("Rencana \(planned.formatted(date: .abbreviated, time: .omitted)): \(advice.text.lowercased())",
                                  systemImage: advice.symbolName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if isFront && status == .ready {
                            Label("Prioritas berikutnya", systemImage: "arrow.up.to.line")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Ketuk untuk mengubah detail buah.")

            // Visible actions; swipe and the context menu are shortcuts to the same actions (HIG).
            if status == .overdue {
                outcomeButton(.discarded)
            }
            outcomeButton(.consumed)
        }
        .frame(minHeight: TouchTarget.minimum)
    }

    private func outcomeButton(_ kind: OutcomeKind) -> some View {
        Button { onOutcome(kind) } label: {
            Image(systemName: kind.symbolName)
                .font(.body.weight(.semibold))
                .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Tandai satu \(entry.fruit.displayName.lowercased()) \(kind.actionTitle.lowercased())")
    }

    private func detail(_ status: StockStatus) -> String {
        let left = entry.daysLeft(at: now)
        switch status {
        case .overdue: return "Melewati perkiraan (\(DaysText.remaining(left))). Periksa sebelum dikonsumsi."
        case .ready: return "Konsumsi dalam \(DaysText.remaining(left))"
        case .waiting:
            return "Siap dalam \(DaysText.remaining(entry.daysUntilReady(at: now))) · tahan hingga \(DaysText.remaining(left))"
        }
    }
}

#Preview {
    NavigationStack { StockView() }
        .modelContainer(for: [StockItem.self, StockOutcome.self], inMemory: true)
}
