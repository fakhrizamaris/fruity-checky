import SwiftUI

/// Photo with one numbered box per detected fruit. Box colour follows the status,
/// and every box carries a number + icon, so status is never colour alone.
struct DetectionOverlay: View {
    let image: UIImage
    let items: [DetectedFruit]

    @ScaledMetric(relativeTo: .caption) private var tagPadding: CGFloat = 4

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 360)
            .overlay {
                GeometryReader { proxy in
                    ForEach(items.filter { !$0.coversWholePhoto }) { item in
                        let rect = CGRect(x: item.box.minX * proxy.size.width,
                                          y: item.box.minY * proxy.size.height,
                                          width: item.box.width * proxy.size.width,
                                          height: item.box.height * proxy.size.height)
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(item.result.state.tint, lineWidth: 3)
                            .frame(width: rect.width, height: rect.height)
                            .overlay(alignment: .topLeading) { tag(for: item) }
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
    }

    private func tag(for item: DetectedFruit) -> some View {
        Label("\(item.number)", systemImage: item.result.state.symbolName)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(tagPadding)
            .background(item.result.state.tint, in: RoundedRectangle(cornerRadius: 4))
            .padding(4)
    }

    private var accessibilitySummary: String {
        guard items.count > 1 else { return "Foto buah yang dinilai" }
        let parts = items.map { "buah \($0.number) \($0.result.state.title.lowercased())" }
        return "Foto dengan \(items.count) buah: " + parts.joined(separator: ", ")
    }
}
