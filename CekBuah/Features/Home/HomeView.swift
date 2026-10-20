import PhotosUI
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(Router.self) private var router
    @AppStorage(SettingsKey.testerMode) private var testerMode = false
    @AppStorage(SettingsKey.identityThreshold) private var identityThreshold = FruitIdentity.defaultThreshold
    @AppStorage(RipenessModelChoice.key) private var ripenessModel = RipenessModelChoice.standard.rawValue
    @AppStorage(TestClock.offsetKey) private var offsetDays = 0.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Pindai buah untuk mengetahui jenis, tingkat kematangan, dan perkiraan waktu konsumsi. Semua proses berlangsung di perangkat.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ShoppingCard()

                ScanCard()

                ShelfScanCard()

                StockSummaryCard()
            }
            .padding(Spacing.l)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Orang BAIK")
        // Leaving tester mode returns the simulated clock to today.
        .onChange(of: testerMode) { _, isOn in
            if !isOn { offsetDays = 0 }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Tentang & sumber data", systemImage: "info.circle") { router.push(.credits) }
                    Toggle("Mode penguji", systemImage: "wrench.and.screwdriver", isOn: $testerMode)
                    if testerMode {
                        Button("Log pengujian", systemImage: "list.bullet.rectangle") { router.push(.log) }
                        Picker("Model kematangan", selection: $ripenessModel) {
                            ForEach(RipenessModelChoice.allCases) { choice in
                                Text(choice.title).tag(choice.rawValue)
                            }
                        }
                        Picker("Ambang pengenalan buah", selection: $identityThreshold) {
                            ForEach(FruitIdentity.thresholdChoices, id: \.self) { value in
                                Text("\(Int((value * 100).rounded()))%").tag(value)
                            }
                        }
                    }
                } label: {
                    Label("Menu", systemImage: "ellipsis.circle")
                }
                .accessibilityLabel("Menu lainnya")
            }
        }
    }
}

/// Shopping flow: scan fruits one by one (or tap them on a shelf photo) into a basket, then save to stock.
private struct ShoppingCard: View {
    @Environment(Router.self) private var router
    @Environment(Basket.self) private var basket

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("Belanja buah", systemImage: "cart")
                .font(.headline)
            Text("Arahkan kamera ke buah satu per satu, atau foto seluruh rak lalu ketuk buah yang ingin diambil.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                router.push(.liveScan)
            } label: {
                Label("Pindai belanja", systemImage: "camera.viewfinder")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint("Membuka kamera untuk memilih buah dan memasukkannya ke keranjang")

            if basket.count > 0 {
                Button {
                    router.push(.basket)
                } label: {
                    Label("Keranjang (\(basket.count))", systemImage: "cart.fill")
                }
                .buttonStyle(PrimaryButtonStyle(prominent: false))
            }
        }
        .card()
    }
}

/// Short queue summary, like the storyboard's "Smart Queue": what to eat first.
private struct StockSummaryCard: View {
    @Environment(Router.self) private var router
    @Query private var items: [StockItem]
    @AppStorage(TestClock.offsetKey) private var offsetDays = 0.0

    var body: some View {
        let now = TestClock.now(offsetDays: offsetDays)
        let ordered = StockQueue.ordered(items.compactMap { $0.entry() }, at: now)
        let count = { (status: StockStatus) in ordered.filter { $0.status(at: now) == status }.count }
        let front = ordered.first { $0.status(at: now) == .ready }

        Button {
            router.push(.stock)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("Stok buah", systemImage: "list.number")
                    .font(.headline)
                if ordered.isEmpty {
                    Text("Belum ada buah tersimpan.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(count(.ready)) siap dikonsumsi · \(count(.waiting)) menunggu" +
                         (count(.overdue) > 0 ? " · \(count(.overdue)) perlu diperiksa" : ""))
                        .foregroundStyle(.secondary)
                    if let front {
                        Text("Prioritas: \(front.fruit.emoji) \(front.fruit.displayName), \(DaysText.remaining(front.daysLeft(at: now)))")
                            .font(.subheadline.bold())
                    }
                }
            }
            .font(.subheadline)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Membuka daftar stok buah")
    }
}

/// One entry point: the app recognises the fruit itself.
private struct ScanCard: View {
    @Environment(Router.self) private var router
    @State private var pickerItem: PhotosPickerItem?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Buah yang dikenali: " + Fruit.enabled.map { "\($0.emoji) \($0.displayName)" }.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                router.push(.camera)
            } label: {
                Label("Pindai buah", systemImage: "camera.viewfinder")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint("Membuka kamera untuk mengenali buah dan menilai kematangannya")

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Pilih dari galeri", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(PrimaryButtonStyle(prominent: false))
            .accessibilityLabel("Pilih foto buah dari galeri")

            Menu {
                ForEach(Fruit.enabled) { fruit in
                    Button("\(fruit.emoji) \(fruit.displayName)") { router.push(.physicalCheck(fruit)) }
                }
            } label: {
                Label("Periksa manual tanpa foto", systemImage: "hand.point.up.left")
            }
            .buttonStyle(PrimaryButtonStyle(prominent: false))

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
            }
        }
        .card()
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicked(item) }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                errorMessage = "Foto tidak dapat dibuka. Silakan pilih foto lain."
                return
            }
            errorMessage = nil
            router.push(.result(CapturedPhoto(image: image.normalized())))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Many fruits in one photo (a shelf, crate or fruit bowl): one box per fruit and a count per kind.
private struct ShelfScanCard: View {
    @Environment(Router.self) private var router
    @State private var pickerItem: PhotosPickerItem?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("Pindai rak", systemImage: "square.grid.3x3.square")
                .font(.headline)
            Text("Satu foto untuk banyak buah: " + ShelfFruit.allCases.map { "\($0.emoji) \($0.displayName)" }.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Pilih foto rak", systemImage: "photo.stack")
            }
            .buttonStyle(PrimaryButtonStyle(prominent: false))
            .accessibilityHint("Memilih foto rak atau keranjang buah dari galeri")

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
            }
        }
        .card()
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicked(item) }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                errorMessage = "Foto tidak dapat dibuka. Silakan pilih foto lain."
                return
            }
            errorMessage = nil
            // Larger than the single-fruit flow: small fruits at the back of a crate need the pixels.
            router.push(.shelfScan(CapturedPhoto(image: image.normalized(maxDimension: 2048))))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(Router())
        .environment(Basket())
        .modelContainer(for: StockItem.self, inMemory: true)
}
