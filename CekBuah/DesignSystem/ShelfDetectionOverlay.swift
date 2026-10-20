import SwiftUI

/// Shelf photo with one box per detected fruit, like a market-crate detector.
/// Each box carries two labels (kind and ripeness) while the shelf is not crowded.
/// Tapping a box picks that fruit; tapping it again puts it back. Picked fruits get a thick box and a check.
struct ShelfDetectionOverlay: View {
    let image: UIImage
    let detections: [ShelfDetection]
    var ripeness: [Int: ClassificationResult] = [:]
    var picked: Set<Int> = []
    var onTap: ((ShelfDetection) -> Void)?

    /// Above this many fruits the label chips would cover the photo, so only number tags are drawn
    /// (picked fruits still show their chip).
    private let maxChips = 12
    /// Above this many fruits even number tags would cover the photo.
    private let maxTags = 30

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { proxy in
                    ForEach(detections) { item in
                        box(for: item, in: proxy.size)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .accessibilityElement(children: onTap == nil ? .ignore : .contain)
            .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private func box(for item: ShelfDetection, in size: CGSize) -> some View {
        let rect = CGRect(x: item.box.minX * size.width, y: item.box.minY * size.height,
                          width: item.box.width * size.width, height: item.box.height * size.height)
        let isPicked = picked.contains(item.number)
        Rectangle()
            .strokeBorder(isPicked ? Color.yellow : Color.green, lineWidth: isPicked ? 4 : 2)
            .background(isPicked ? Color.yellow.opacity(0.15) : Color.clear)
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                if detections.count <= maxChips || isPicked {
                    FruitLabelChip(kind: item.fruit, ripeness: Self.ripenessText(item, ripeness[item.number]),
                                   state: ripeness[item.number]?.state, isPicked: isPicked, compact: true)
                        .fixedSize()
                        .padding(2)
                } else if detections.count <= maxTags {
                    tag(item.number)
                }
            }
            .position(x: rect.midX, y: rect.midY)
            .onTapGesture { onTap?(item) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Buah \(item.number), \(item.fruit?.displayName ?? "belum dikenali"), "
                                + Self.ripenessText(item, ripeness[item.number]))
            .accessibilityValue(isPicked ? "Dipilih" : "")
            .accessibilityHint(onTap == nil ? "" : isPicked ? "Ketuk untuk mengembalikan" : "Ketuk untuk memilih")
            .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    private func tag(_ number: Int) -> some View {
        Text("\(number)")
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(.black)
            .padding(.horizontal, 3)
            .background(Color.green)
    }

    static func ripenessText(_ item: ShelfDetection, _ result: ClassificationResult?) -> String {
        if let result { return result.state.title }
        if item.fruit == nil { return "Kematangan tidak diketahui" }
        return item.fruit?.ripenessFruit == nil ? "Kematangan belum tersedia" : "Menilai…"
    }

    private var accessibilitySummary: String {
        guard !detections.isEmpty else { return "Foto rak, belum ada buah terdeteksi" }
        let parts = ShelfPostProcessing.counts(detections).map { entry in
            "\(entry.count) \(entry.fruit?.displayName.lowercased() ?? "objek")"
        }
        return "Foto rak dengan \(detections.count) buah: " + parts.joined(separator: ", ")
    }
}
