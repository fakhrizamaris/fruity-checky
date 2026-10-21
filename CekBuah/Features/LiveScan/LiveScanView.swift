import SwiftUI

/// Shopping scan, one fruit at a time: hold a fruit close and turn it slowly. When several frames agree,
/// a pop-up shows the fruit with its kind and ripeness: "Ambil" puts it in the basket, "Pilih yang lain" skips it.
struct LiveScanView: View {
    @Environment(Router.self) private var router
    @Environment(Basket.self) private var basket
    @Environment(\.classifier) private var classifier
    @AppStorage(SettingsKey.testerMode) private var testerMode = false
    @State private var model = LiveScanModel()

    var body: some View {
        // Square camera card, as wide as the screen: it shows exactly the centre square the model analyses
        // (a full-screen preview made that square wider than the screen and the boxes looked too big).
        VStack(spacing: Spacing.m) {
            preview
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(alignment: .top) {
                    if model.current == nil, model.status == .running {
                        floatingLabel(guideText, systemImage: model.tooCloseHint ? "arrow.down.left.and.arrow.up.right" : "viewfinder")
                            .padding(Spacing.s)
                    }
                }
                .overlay(alignment: .bottom) { bottomOverlay.padding(Spacing.s) }

            Label("Arahkan ke satu buah sampai seluruhnya terlihat di kotak kamera, lalu putar perlahan.",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if testerMode { testerPanel }
            if let message = model.detectorError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
            }

            Spacer(minLength: 0)

            Button {
                router.push(.basket)
            } label: {
                Label("Keranjang (\(basket.count))", systemImage: "cart")
            }
            .buttonStyle(PrimaryButtonStyle(prominent: basket.count > 0))
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.m)
        .navigationTitle("Pindai belanja")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.start(classifier: classifier) }
        .onDisappear { model.stop() }
        .sheet(item: $model.offer, onDismiss: {
            // Swiping the sheet away counts as "Pilih yang lain".
            if model.offer == nil { model.skipIfPending() }
        }) { offer in
            OfferSheet(offer: offer,
                       onTake: { manual in model.take(offer, into: basket, manualResult: manual) },
                       onSkip: { model.skip() })
                // The hand-check list needs the full height.
                .presentationDetents(ManualRipenessGuide.required(for: offer.verdict.kind) == nil ? [.medium, .large] : [.large])
        }
    }

    /// Text on a material capsule, readable over any camera image.
    private func floatingLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.bold())
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
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
            placeholder(icon: "camera.badge.ellipsis", text: "Akses kamera belum diizinkan. Aktifkan kamera di Pengaturan.")
        case .unavailable(let message):
            placeholder(icon: "camera.badge.ellipsis", text: message)
        }
    }

    /// Tester mode: which model found the box, named the fruit, and judged ripeness on the latest frame.
    private var testerPanel: some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.xs) {
            GridRow {
                Text("Kotak").foregroundStyle(.secondary)
                Text(model.usesDetector ? CoreMLShelfDetector.modelName : "kotak tengah (tanpa detektor)")
            }
            GridRow {
                Text("Jenis").foregroundStyle(.secondary)
                Text(model.lastKindInfo)
            }
            GridRow {
                Text("Kematangan").foregroundStyle(.secondary)
                Text(ripenessInfo)
            }
            if model.usesMultitask {
                GridRow {
                    Text("Tahap").foregroundStyle(.secondary)
                    Text(model.lastStageInfo)
                }
                GridRow {
                    Text("Kerusakan").foregroundStyle(.secondary)
                    Text(model.lastDamageInfo)
                }
            }
            GridRow {
                Text("Frame").foregroundStyle(.secondary)
                Text("\(Int((model.progress * 100).rounded()))% dari \(LiveScanAccumulator.framesNeeded) frame setuju")
            }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var ripenessInfo: String {
        guard let fruit = model.current else { return "–" }
        guard let result = fruit.result else {
            return fruit.kind.ripenessFruit == nil ? "belum ada model untuk \(fruit.kind.displayName.lowercased())" : "menilai…"
        }
        let name = result.modelName.isEmpty ? (result.isDemo ? "demo" : "?") : result.modelName
        return "\(name) · \(result.state.title) \(result.confidencePercent)%"
    }

    private var guideText: String {
        if model.waitingForNextFruit { return "Ganti dengan buah berikutnya" }
        if model.tooCloseHint { return "Terlalu dekat, jauhkan HP sampai seluruh buah terlihat" }
        if model.unsupportedHint { return "Buah ini belum didukung" }
        return "Arahkan satu buah ke tengah"
    }

    /// Progress while turning the fruit, or the confirmation toast after taking one.
    @ViewBuilder
    private var bottomOverlay: some View {
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
        } else if model.current != nil, !model.waitingForNextFruit {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Putar buah perlahan…")
                    .font(.subheadline.bold())
                ProgressView(value: model.progress)
                    .accessibilityLabel("Kemajuan pemindaian")
                    .accessibilityValue("\(Int(model.progress * 100)) persen")
            }
            .padding(Spacing.m)
            .frame(maxWidth: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
        }
    }

    private var accessibilityText: String {
        guard let fruit = model.current else { return "Pratinjau kamera. \(guideText)." }
        return "Terlihat \(fruit.kind.displayName), \(LiveFruitOverlay.ripenessText(fruit)). Putar buah perlahan."
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
}

/// Pop-up once the app is sure: the fruit, its kind and ripeness, and the two choices.
/// For avocado and mango the photo cannot read ripeness well, so a hand check is required before "Ambil";
/// the chosen answer becomes the ripeness stored in the basket.
private struct OfferSheet: View {
    let offer: LiveScanModel.Offer
    let onTake: (ClassificationResult?) -> Void
    let onSkip: () -> Void
    @State private var manualChoice: ManualCheckOption?

    private var guide: ManualRipenessGuide? { ManualRipenessGuide.required(for: offer.verdict.kind) }
    private var shownResult: ClassificationResult? {
        manualChoice.map(ManualRipenessGuide.result(for:)) ?? offer.verdict.result
    }

    /// Basket item as it would be stored, so the days estimate follows the hand check.
    private var item: BasketItem {
        var item = offer.basketItem
        item.result = shownResult
        return item
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                HStack(spacing: Spacing.l) {
                    Image(uiImage: UIImage(cgImage: offer.crop))
                        .resizable()
                        .scaledToFill()
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("\(offer.verdict.kind.emoji) \(offer.verdict.kind.displayName)")
                            .font(.title2.bold())
                        Label {
                            Text(ripenessTitle)
                        } icon: {
                            Image(systemName: shownResult?.state.symbolName ?? "circle.dashed")
                                .foregroundStyle(shownResult?.state.tint ?? .secondary)
                        }
                        .font(.headline)
                        if let days = item.estimatedDays {
                            Text("Perkiraan: \(DaysText.remaining(days))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("Jenis sama di \(offer.verdict.agreeing) dari \(offer.verdict.looked) sisi yang dilihat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if let guide { manualCheck(guide) }

                if shownResult?.state == .rotten {
                    Label("Buah ini terlihat busuk atau rusak. Sebaiknya pilih yang lain.", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                }

                Button {
                    onTake(manualChoice.map(ManualRipenessGuide.result(for:)))
                } label: {
                    Label("Ambil", systemImage: "cart.badge.plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(guide != nil && manualChoice == nil)
                .accessibilityHint(guide != nil && manualChoice == nil ? "Pilih hasil cek tangan dulu" : "Memasukkan buah ini ke keranjang")

                Button(action: onSkip) {
                    Label("Pilih yang lain", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(PrimaryButtonStyle(prominent: false))
                .accessibilityHint("Melewati buah ini dan memindai buah berikutnya")

                Text("Perkiraan dari foto dan cek tangan, bukan pemeriksaan keamanan pangan.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.xl)
        }
    }

    private var ripenessTitle: String {
        if let manualChoice { return "\(manualChoice.stageName) (cek tangan)" }
        if guide != nil { return "Cek tangan dulu" }
        return offer.verdict.result?.state.title ?? "Kematangan belum tersedia"
    }

    /// Required hand check: how to press (and smell, for mango), then one answer per stage.
    private func manualCheck(_ guide: ManualRipenessGuide) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("Cek tangan (wajib untuk \(guide.kind.displayName.lowercased()))", systemImage: "hand.point.up.left")
                .font(.headline)
            Text(guide.howTo)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let photo = offer.verdict.result {
                Text("Tebakan dari foto: \(photo.state.title.lowercased()). Hanya petunjuk, hasil cek tanganmu yang dipakai.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(guide.options) { option in
                Button {
                    manualChoice = option
                } label: {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        Image(systemName: manualChoice == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(manualChoice == option ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title).font(.body.bold())
                            Text("\(option.stageName) · \(option.detail)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(manualChoice == option ? .isSelected : [])
            }
            Label(guide.note, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

/// Box and labels for the fruit in the live view. The camera image is portrait 3:4 and fills the view
/// (aspect fill). Live frames are the centre square of that image; in the square camera card that square is
/// exactly the card, so a normalized box maps straight onto it.
private struct LiveFruitOverlay: View {
    let fruit: LiveScanModel.LiveFruit?

    /// Centre square of the camera image, in view points (may extend past the screen's sides).
    static func analysisSquare(in size: CGSize) -> CGRect {
        let k = max(size.width / 3, size.height / 4)
        let image = CGSize(width: 3 * k, height: 4 * k)
        let side = image.width
        return CGRect(x: (size.width - image.width) / 2, y: (size.height - image.height) / 2 + (image.height - side) / 2,
                      width: side, height: side)
    }

    var body: some View {
        GeometryReader { proxy in
            let square = Self.analysisSquare(in: proxy.size)
            ZStack(alignment: .topLeading) {
                if let fruit {
                    let rect = CGRect(x: square.minX + fruit.box.minX * square.width, y: square.minY + fruit.box.minY * square.height,
                                      width: fruit.box.width * square.width, height: fruit.box.height * square.height)
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.yellow, lineWidth: 3)
                        .frame(width: rect.width, height: rect.height)
                        .overlay(alignment: .top) {
                            FruitLabelChip(kind: fruit.kind, ripeness: Self.ripenessText(fruit),
                                           state: fruit.result?.state, isPicked: false)
                                .fixedSize()
                                .offset(y: rect.minY > 120 ? -40 : 6)
                        }
                        .position(x: rect.midX, y: rect.midY)
                        .animation(.easeOut(duration: 0.2), value: rect)
                }
            }
        }
    }

    static func ripenessText(_ fruit: LiveScanModel.LiveFruit) -> String {
        if let result = fruit.result { return result.state.title }
        return fruit.kind.ripenessFruit == nil ? "Kematangan belum tersedia" : "Menilai…"
    }
}
