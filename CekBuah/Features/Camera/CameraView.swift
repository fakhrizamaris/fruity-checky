import PhotosUI
import SwiftUI

struct CameraView: View {
    @Environment(Router.self) private var router
    @AppStorage(SettingsKey.testerMode) private var testerMode = false
    @AppStorage(SettingsKey.identityThreshold) private var confirmThreshold = FruitIdentity.defaultThreshold
    @State private var camera = CameraModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: Spacing.l) {
            preview
                .frame(maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))

            Label("Satu buah per foto, di dalam bingkai, dengan cahaya terang dan merata.",
                  systemImage: "sun.max")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)

            Button {
                Task { await takePhoto() }
            } label: {
                Label(camera.status == .capturing ? "Memproses…" : "Ambil foto", systemImage: "camera.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(camera.status != .running)
            .accessibilityLabel("Ambil foto buah")

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Pilih dari galeri", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(PrimaryButtonStyle(prominent: false))
            .accessibilityLabel("Pilih foto buah dari galeri")
        }
        .padding(Spacing.l)
        .navigationTitle("Pindai buah")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            camera.confirmThreshold = testerMode ? confirmThreshold : FruitIdentity.defaultThreshold
            await camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicked(item) }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch camera.status {
        case .running, .capturing:
            ZStack(alignment: .top) {
                CameraPreview(session: camera.service.session)
                    .accessibilityElement()
                    .accessibilityLabel("Pratinjau kamera. Arahkan buah ke tengah bingkai.")
                GuideFrame()
                LiveScanLabel(scan: camera.liveScan)
                    .padding(Spacing.m)
            }
        case .idle:
            placeholder(icon: "camera", text: "Menyiapkan kamera…")
        case .denied:
            placeholder(icon: "camera.badge.ellipsis",
                        text: "Akses kamera belum diizinkan. Pilih foto dari galeri, atau aktifkan kamera di Pengaturan.")
        case .unavailable(let message):
            placeholder(icon: "camera.badge.ellipsis", text: "\(message) Pilih foto dari galeri.")
        }
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

    private func takePhoto() async {
        do {
            let image = try await camera.capture()
            router.push(.result(CapturedPhoto(image: image)))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Foto tidak dapat dibuka. Silakan pilih foto lain."
                return
            }
            router.push(.result(CapturedPhoto(image: image.normalized())))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Live preview of what the model sees in the guide frame. The final result comes from the photo.
private struct LiveScanLabel: View {
    let scan: CameraModel.LiveScan?

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.bold())
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var text: String {
        guard let scan, let fruit = scan.fruit else { return "Arahkan satu buah ke dalam bingkai" }
        let state = scan.state == .unsure ? "belum yakin" : scan.state.title.lowercased()
        return "\(fruit.emoji) \(fruit.displayName) · \(state)"
    }

    private var symbol: String {
        guard let scan, scan.fruit != nil else { return "viewfinder" }
        return scan.state.symbolName
    }
}

/// Decorative square guide in the centre; matches the centre crop the model sees.
private struct GuideFrame: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) - Spacing.l
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}
