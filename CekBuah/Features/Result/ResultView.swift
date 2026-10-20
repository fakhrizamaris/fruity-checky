import SwiftData
import SwiftUI

struct ResultView: View {
    @Environment(Router.self) private var router
    @Environment(\.classifier) private var classifier
    @Environment(\.identifier) private var identifier
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.savePhotos) private var savePhotos = false
    @AppStorage(TestClock.offsetKey) private var offsetDays = 0.0
    @AppStorage(NotificationSettings.enabledKey) private var notificationsEnabled = false
    @AppStorage(SettingsKey.testerMode) private var testerMode = false
    @AppStorage(SettingsKey.identityThreshold) private var identityThreshold = FruitIdentity.defaultThreshold
    @State private var model: ResultViewModel

    init(photo: CapturedPhoto) {
        _model = State(initialValue: ResultViewModel(photo: photo))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                switch model.phase {
                case .loading:
                    ProgressView("Menganalisis buah…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .card()
                case .done(let items):
                    DetectionOverlay(image: model.photo.image, items: items)
                    if model.isDemo { DemoBanner() }
                    if items.count > 1 {
                        Text("\(items.count) buah terdeteksi")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if model.offersPhysicalCheck && model.allUnsure { physicalCheckButton }
                    ForEach(items) { item in
                        itemSection(item, numbered: items.count > 1)
                    }
                    if model.offersPhysicalCheck && !model.allUnsure { physicalCheckButton }
                    Button("Foto ulang", systemImage: "camera") {
                        router.path.removeLast()
                    }
                    .buttonStyle(PrimaryButtonStyle(prominent: false))
                    ClaimBanner()
                    if testerMode { testerDetails(items) }
                }
            }
            .padding(Spacing.l)
            .animation(reduceMotion ? nil : .default, value: model.items.count)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(model.uniformFruit.map { "Hasil \($0.displayName)" } ?? "Hasil")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: model.items.count)
        .task {
            await model.analyze(using: classifier, identifier: identifier,
                                identityThreshold: testerMode ? identityThreshold : FruitIdentity.defaultThreshold,
                                context: context, savePhoto: savePhotos)
        }
    }

    private func itemSection(_ item: DetectedFruit, numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if item.needsIdentityNotice && !model.savedToStock.contains(item.number) {
                IdentityNotice(pickedFruit: item.pickedFruit, identity: item.identity,
                               isWorking: model.switching.contains(item.number),
                               onSwitch: { fruit in Task { await model.switchFruit(item, to: fruit, context: context) } },
                               onKeep: { model.keepPicked(item, context: context) })
            }
            fruitHeader(for: item)
            ResultCard(result: item.result, reason: model.reason(for: item), number: numbered ? item.number : nil,
                       estimatedDays: model.estimatedDays(for: item), daysUntilReady: model.daysUntilReady(for: item))
            if model.canAddToStock(item) { stockButton(for: item, numbered: numbered) }
            if testerMode { feedbackRow(for: item, numbered: numbered) }
        }
    }

    /// Which fruit the result is about, with a way to correct it (the model only knows six fruits).
    @ViewBuilder
    private func fruitHeader(for item: DetectedFruit) -> some View {
        HStack {
            Text("\(item.fruit.emoji) \(item.fruit.displayName)")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !item.needsIdentityNotice && !model.savedToStock.contains(item.number) {
                Menu {
                    ForEach(Fruit.enabled.filter { $0 != item.fruit }) { fruit in
                        Button("\(fruit.emoji) \(fruit.displayName)") {
                            Task { await model.switchFruit(item, to: fruit, context: context) }
                        }
                    }
                } label: {
                    Label("Ganti buah", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .frame(minHeight: TouchTarget.minimum)
                }
                .disabled(model.switching.contains(item.number))
                .accessibilityHint("Pilih jenis buah lain jika hasil pengenalan salah")
            }
        }
    }

    @ViewBuilder
    private func stockButton(for item: DetectedFruit, numbered: Bool) -> some View {
        if model.savedToStock.contains(item.number) {
            Button {
                router.push(.stock)
            } label: {
                Label("Tersimpan · Lihat stok", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle(prominent: false))
        } else {
            Button {
                model.addToStock(item, context: context, now: TestClock.now(offsetDays: offsetDays))
                Task {
                    await StockNotifier.reschedule(context: context, offsetDays: offsetDays, enabled: notificationsEnabled)
                }
            } label: {
                Label(numbered ? "Simpan buah \(item.number) ke stok" : "Simpan ke stok", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle(prominent: false))
            .accessibilityHint("Menambahkan buah ini ke daftar stok")
        }
    }

    /// Unsure: the physical check is the main next step, not a model guess.
    private var physicalCheckButton: some View {
        Button {
            router.push(.physicalCheck(model.physicalCheckFruit))
        } label: {
            Label(model.allUnsure ? "Lanjutkan cek fisik" : "Cek fisik", systemImage: "hand.point.up.left")
        }
        .buttonStyle(PrimaryButtonStyle(prominent: model.allUnsure))
        .accessibilityHint("Membuka langkah memeriksa buah dengan tangan dan penciuman")
    }

    private func feedbackRow(for item: DetectedFruit, numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(numbered ? "Penguji: apakah hasil buah \(item.number) sesuai?" : "Penguji: apakah hasil sesuai?")
                .font(.subheadline.bold())
            HStack(spacing: Spacing.m) {
                feedbackButton(title: "Ya", matches: true, item: item)
                feedbackButton(title: "Tidak", matches: false, item: item)
            }
        }
        .card()
    }

    private func feedbackButton(title: String, matches: Bool, item: DetectedFruit) -> some View {
        let selected = model.feedback[item.number] == matches
        return Button {
            model.setFeedback(matches, for: item.number, context: context)
        } label: {
            Label(title, systemImage: selected ? "checkmark.circle.fill" : "circle")
        }
        .buttonStyle(PrimaryButtonStyle(prominent: selected))
        .accessibilityLabel("Hasil buah \(item.number) sesuai: \(title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func testerDetails(_ items: [DetectedFruit]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Detail model")
                .font(.caption.bold())
            ForEach(items) { item in
                let scores = item.result.topTwo
                    .map { "\($0.state.title) \($0.percentText)" }
                    .joined(separator: ", ")
                Text(items.count > 1 ? "Buah \(item.number): \(scores)" : scores)
                if item.result.isTie {
                    Text("Peluang seri, dipilih tahap yang lebih lanjut.")
                }
                if let extras = item.result.extras {
                    Text("RipeNet\(items.count > 1 ? " buah \(item.number)" : ""): jenis \(extras.fruitLabel) "
                         + "\(Int((extras.fruitProbability * 100).rounded()))%, regresi hari "
                         + "\(extras.days.formatted(.number.precision(.fractionLength(1)))) (label sintetis)")
                }
                if item.identity.verdict != .unavailable {
                    Text("Cek jenis\(items.count > 1 ? " buah \(item.number)" : ""): \(identityText(item))")
                }
            }
            if let name = items.first?.result.modelName, !name.isEmpty {
                Text("Model: \(name)")
            }
            if let latency = model.latencyMs {
                Text("Waktu proses (deteksi + klasifikasi): \(latency) ms")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private func identityText(_ item: DetectedFruit) -> String {
    let scores = Fruit.enabled
        .sorted { (item.identity.scores[$0] ?? 0) > (item.identity.scores[$1] ?? 0) }
        .prefix(2)
        .map { "\($0.displayName) \(Int(((item.identity.scores[$0] ?? 0) * 100).rounded()))%" }
        .joined(separator: ", ")
    let action = item.identityAction.map { $0 == .switched ? " · diganti penguji/pengguna" : " · tetap" } ?? ""
    return "\(item.identity.verdict.rawValue) (\(scores))\(action)"
}

#Preview {
    NavigationStack {
        ResultView(photo: CapturedPhoto(image: UIImage(systemName: "photo") ?? UIImage()))
    }
    .environment(Router())
    .environment(\.classifier, MockClassifier())
    .modelContainer(for: LogEntry.self, inMemory: true)
}
