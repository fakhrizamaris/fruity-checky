import SwiftUI

/// Shopping scan, one fruit at a time: point the camera at a fruit, check the box and its two labels,
/// then tap "Tambah ke keranjang" and move to the next fruit. A whole shelf can be photographed instead.
struct LiveScanView: View {
    @Environment(Router.self) private var router
    @Environment(Basket.self) private var basket
    @Environment(\.classifier) private var classifier
    @AppStorage(SettingsKey.testerMode) private var testerMode = false
    @State private var model = LiveScanModel()
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: Spacing.l) {
            preview
                .frame(maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(alignment: .bottom) { toast }

            if testerMode {
                Text("Model live: \(model.detectorName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
            }

            Spacer(minLength: 0)

            Button {
                model.addCurrent(to: basket)
            } label: {
                Label("Tambah ke keranjang", systemImage: "cart.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.current == nil)
            .accessibilityHint("Menyimpan buah yang sedang terlihat, lalu lanjut ke buah berikutnya")

            HStack(spacing: Spacing.m) {
                Button {
                    Task { await photographShelf() }
                } label: {
                    Label("Foto rak", systemImage: "square.grid.3x3.square")
                }
                .buttonStyle(PrimaryButtonStyle(prominent: false))
                .disabled(model.status != .running)
                .accessibilityHint("Memotret seluruh rak, lalu pilih buah dengan mengetuk kotaknya")

                Button {
                    router.push(.basket)
                } label: {
                    Label("Keranjang (\(basket.count))", systemImage: "cart")
                }
                .buttonStyle(PrimaryButtonStyle(prominent: false))
            }
        }
        .padding(Spacing.l)
        .navigationTitle("Pindai belanja")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.start(classifier: classifier) }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var preview: some View {
        switch model.status {
        case .running, .capturing:
            CameraPreview(session: model.service.session)
                .overlay { LiveFruitOverlay(fruit: model.current) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityAddTraits(.updatesFrequently)
        case .idle:
            placeholder(icon: "camera", text: "Menyiapkan kamera…")
        case .denied:
            placeholder(icon: "camera.badge.ellipsis",
                        text: "Akses kamera belum diizinkan. Aktifkan kamera di Pengaturan, atau pilih foto rak dari Beranda.")
        case .unavailable(let message):
            placeholder(icon: "camera.badge.ellipsis", text: message)
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let text = model.toast {
            HStack(spacing: Spacing.m) {
                Label(text, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold())
                Button("Batalkan") { model.undoLast(in: basket) }
                    .font(.subheadline)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .background(.regularMaterial, in: Capsule())
            .padding(Spacing.m)
            .transition(.opacity)
        }
    }

    private var accessibilityText: String {
        guard let fruit = model.current else { return "Pratinjau kamera. Arahkan satu buah ke tengah." }
        return "Terlihat \(fruit.kind.displayName), \(LiveFruitOverlay.ripenessText(fruit))"
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: icon).font(.largeTitle).accessibilityHidden(true)
            Text(text).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .accessibilityElement(children: .combine)
    }

    private func photographShelf() async {
        do {
            let image = try await model.captureShelfPhoto()
            errorMessage = nil
            router.push(.shelfScan(CapturedPhoto(image: image)))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Box and labels for the fruit in the live view. Live frames are the centre square of the
/// camera image, which fills the preview's width, so the box is placed inside that square.
private struct LiveFruitOverlay: View {
    let fruit: LiveScanModel.LiveFruit?

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let origin = CGPoint(x: (proxy.size.width - side) / 2, y: (proxy.size.height - side) / 2)
            if let fruit {
                let rect = CGRect(x: origin.x + fruit.box.minX * side, y: origin.y + fruit.box.minY * side,
                                  width: fruit.box.width * side, height: fruit.box.height * side)
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.yellow, lineWidth: 3)
                    .frame(width: rect.width, height: rect.height)
                    .overlay(alignment: .top) {
                        FruitLabelChip(kind: fruit.kind, ripeness: Self.ripenessText(fruit),
                                       state: fruit.result?.state, isPicked: false)
                            .fixedSize()
                            .offset(y: -34)
                    }
                    .position(x: rect.midX, y: rect.midY)
                    .animation(.easeOut(duration: 0.2), value: rect)
            } else {
                Text("Arahkan satu buah ke tengah")
                    .font(.subheadline.bold())
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.s)
                    .background(.ultraThinMaterial, in: Capsule())
                    .position(x: proxy.size.width / 2, y: Spacing.xl + Spacing.s)
            }
        }
    }

    static func ripenessText(_ fruit: LiveScanModel.LiveFruit) -> String {
        if let result = fruit.result { return result.state.title }
        return fruit.kind.ripenessFruit == nil ? "Kematangan belum tersedia" : "Menilai…"
    }
}
