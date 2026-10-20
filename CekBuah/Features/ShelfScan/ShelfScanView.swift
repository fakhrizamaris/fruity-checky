import SwiftUI

/// Scans one shelf or crate photo: a box per fruit with two labels (kind and ripeness).
/// Tapping a box puts that fruit in the basket; tapping it again puts it back on the shelf.
struct ShelfScanView: View {
    @Environment(Router.self) private var router
    @Environment(Basket.self) private var basket
    @Environment(\.classifier) private var classifier
    @AppStorage(SettingsKey.testerMode) private var testerMode = false
    @State private var model: ShelfScanModel

    init(photo: CapturedPhoto) {
        _model = State(initialValue: ShelfScanModel(photo: photo))
    }

    /// Box numbers of this photo that are in the basket.
    private var picked: Set<Int> {
        Set(model.detections.filter { basket.contains(model.source(of: $0)) }.map(\.number))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                ShelfDetectionOverlay(image: model.photo.image, detections: model.detections,
                                      ripeness: model.ripeness, picked: picked,
                                      onTap: model.phase == .done ? { toggle($0) } : nil)

                switch model.phase {
                case .detecting:
                    ProgressView("Mencari buah di rak…")
                        .frame(maxWidth: .infinity)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                case .done:
                    summary
                    if model.usesFallback { fallbackNotice }
                    if testerMode { testerControls }
                    list
                }
            }
            .padding(Spacing.l)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { basketBar }
        .navigationTitle("Pilih buah")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.onRipeness = { [basket, model] number, result in
                basket.update(.shelf(photoID: model.photo.id, number: number), result: result)
            }
            await model.run(detector: ShelfDetectorFactory.current(), classifier: classifier)
        }
        // A new threshold renumbers the boxes, so picks from this photo no longer match.
        .onChange(of: model.minConfidence) { forgetPicksFromThisPhoto() }
    }

    private func toggle(_ item: ShelfDetection) {
        basket.toggle(model.basketItem(for: item))
    }

    private func forgetPicksFromThisPhoto() {
        let photoID = model.photo.id
        basket.removeAll { item in
            if case .shelf(let id, _) = item.source { return id == photoID }
            return false
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(model.detections.isEmpty ? "Belum ada buah terdeteksi" : "\(model.detections.count) buah terdeteksi")
                .font(.title3.bold())
            if model.detections.isEmpty {
                Text("Coba foto lebih dekat, dengan cahaya yang cukup, dan seluruh rak terlihat.")
                    .foregroundStyle(.secondary)
            } else {
                Text(model.counts.map { "\($0.fruit?.emoji ?? "❔") \($0.count) \($0.fruit?.displayName.lowercased() ?? "objek")" }
                    .joined(separator: " · "))
                    .foregroundStyle(.secondary)
                Label("Ketuk kotak untuk memilih buah. Ketuk lagi untuk mengembalikan.", systemImage: "hand.tap")
                    .font(.subheadline)
            }
        }
        .card()
    }

    private var fallbackNotice: some View {
        Label("Model deteksi rak belum terpasang. Kotak berasal dari Vision tanpa jenis buah, dan buah yang bersentuhan bisa terbaca sebagai satu.",
              systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var testerControls: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Model: \(model.detectorName)")
            Text("Ambang keyakinan: \(Int((model.minConfidence * 100).rounded()))%")
            Slider(value: $model.minConfidence, in: 0.1...0.9, step: 0.05)
                .accessibilityLabel("Ambang keyakinan deteksi")
            Text("Mengubah ambang mengosongkan pilihan dari foto ini.")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .card()
    }

    private var list: some View {
        LazyVStack(spacing: Spacing.s) {
            ForEach(model.detections) { item in
                let isPicked = picked.contains(item.number)
                Button {
                    toggle(item)
                } label: {
                    ShelfItemRow(item: item, result: model.ripeness[item.number], showsConfidence: testerMode,
                                 isPicked: isPicked)
                }
                .buttonStyle(.plain)
                .accessibilityValue(isPicked ? "Dipilih" : "")
                .accessibilityHint(isPicked ? "Mengembalikan buah ini ke rak" : "Memasukkan buah ini ke keranjang")
            }
        }
    }

    private var basketBar: some View {
        Button {
            router.push(.basket)
        } label: {
            Label(picked.isEmpty ? "Keranjang (\(basket.count))" : "Lanjut ke keranjang (\(basket.count))",
                  systemImage: "cart")
        }
        .buttonStyle(PrimaryButtonStyle(prominent: !picked.isEmpty))
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .background(.bar)
    }
}

private struct ShelfItemRow: View {
    let item: ShelfDetection
    let result: ClassificationResult?
    let showsConfidence: Bool
    let isPicked: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text("\(item.number)")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.fruit?.emoji ?? "❔") \(item.fruit?.displayName ?? "Objek belum dikenali")")
                    .font(.body.bold())
                Label {
                    Text(ShelfDetectionOverlay.ripenessText(item, result))
                } icon: {
                    Image(systemName: result?.state.symbolName ?? "circle.dashed")
                        .foregroundStyle(result?.state.tint ?? .secondary)
                }
                .font(.subheadline)
                .foregroundStyle(result == nil ? .secondary : .primary)
                if showsConfidence {
                    Text("Deteksi \(Int((item.confidence * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: isPicked ? "checkmark.circle.fill" : "plus.circle")
                .font(.title2)
                .foregroundStyle(isPicked ? .green : .secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum, alignment: .leading)
        .card(border: isPicked ? .yellow : Color(uiColor: .separator))
    }
}
