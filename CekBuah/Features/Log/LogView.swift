import SwiftData
import SwiftUI

struct LogView: View {
    @Query(sort: \LogEntry.date, order: .reverse) private var entries: [LogEntry]
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.savePhotos) private var savePhotos = false
    @State private var askingPhotoConsent = false

    var body: some View {
        List {
            Section {
                Toggle("Simpan foto di log", isOn: photoToggle)
                    .frame(minHeight: TouchTarget.minimum)
            } footer: {
                Text("Foto hanya disimpan di iPhone ini dan hanya jika opsi ini menyala.")
            }

            Section {
                if entries.isEmpty {
                    Text("Belum ada hasil. Foto buah dulu dari halaman utama.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    LogRowView(entry: entry)
                }
                .onDelete(perform: delete)
            } header: {
                Text("\(entries.count) hasil")
            }
        }
        .navigationTitle("Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: CSVDocument(rows: entries.map(LogRow.init)),
                          preview: SharePreview("cekbuah-log.csv")) {
                    Label("Ekspor CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(entries.isEmpty)
                .accessibilityLabel("Ekspor log sebagai CSV")
            }
        }
        .alert("Simpan foto di log?", isPresented: $askingPhotoConsent) {
            Button("Setuju") { savePhotos = true }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Foto buah akan disimpan di iPhone ini untuk evaluasi PoC. Foto tidak dikirim ke mana pun dan bisa dihapus dengan menghapus baris log.")
        }
    }

    /// Turning on requires explicit consent; turning off is immediate.
    private var photoToggle: Binding<Bool> {
        Binding(
            get: { savePhotos },
            set: { newValue in
                if newValue { askingPhotoConsent = true } else { savePhotos = false }
            }
        )
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(entries[index]) }
        try? context.save()
    }
}

private struct LogRowView: View {
    let entry: LogEntry

    var body: some View {
        let state = entry.state ?? .unsure
        HStack(spacing: Spacing.m) {
            Image(systemName: state.symbolName)
                .foregroundStyle(state.tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(entry.fruit?.displayName ?? entry.fruitRaw): \(state.title)")
                    .font(.headline)
                Text("\(Int((entry.confidence * 100).rounded())) persen · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verdictText + (entry.isDemo ? " · demo" : "") + (entry.photoData != nil ? " · ada foto" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var verdictText: String {
        switch entry.matchesExpectation {
        case .some(true): "Sesuai"
        case .some(false): "Tidak sesuai"
        case .none: "Belum dinilai"
        }
    }
}

#Preview {
    NavigationStack { LogView() }
        .modelContainer(for: LogEntry.self, inMemory: true)
}
