import SwiftUI

/// Result for one fruit: optional number, status badge and short reason.
/// The photo (with boxes) is shown once above all cards by DetectionOverlay.
struct ResultCard: View {
    let result: ClassificationResult
    let reason: String
    /// Shown when the photo contains more than one fruit.
    var number: Int?
    /// Rough days-left estimate, nil when the fruit has no shelf-life table.
    var estimatedDays: Double?
    /// Rough days until "matang"; nil when the fruit is already ripe.
    var daysUntilReady: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let number {
                Text("Buah \(number)")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            StatusBadge(state: result.state, confidenceText: result.confidenceText)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Alasan")
                    .font(.subheadline.bold())
                Text(reason)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if let estimatedDays {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let daysUntilReady {
                        Label("Perkiraan matang \(DaysText.remaining(daysUntilReady))", systemImage: "hourglass")
                            .font(.subheadline.bold())
                    }
                    Label("Dapat dikonsumsi hingga \(DaysText.remaining(estimatedDays))",
                          systemImage: "calendar")
                        .font(daysUntilReady == nil ? .subheadline.bold() : .subheadline)
                    Text("Perkiraan umum pada suhu ruang, bukan hasil pengukuran.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Shown when no model is bundled for the fruit.
struct DemoBanner: View {
    var body: some View {
        Label("Model untuk buah ini belum tersedia. Hasil di bawah hanya contoh.", systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .card()
    }
}

/// Fixed banner: what the app does not claim.
struct ClaimBanner: View {
    static let limits = [
        "Rasa dan tingkat manis tidak dinilai.",
        "Kondisi bagian dalam buah tidak dapat dipastikan dari foto.",
        "Status yang ditampilkan: mentah, matang, terlalu matang, busuk, atau tidak yakin.",
        "Perkiraan waktu konsumsi bersifat umum dan dapat berbeda tergantung cara penyimpanan.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label("Perlu diketahui", systemImage: "info.circle")
                .font(.headline)
            ForEach(Self.limits, id: \.self) { limit in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text("•").accessibilityHidden(true)
                    Text(limit)
                }
            }
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .card()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScrollView {
        ResultCard(
            result: DecisionRules.standard.evaluate([
                ClassPrediction(state: .ripe, probability: 0.82),
                ClassPrediction(state: .overripe, probability: 0.1),
            ]),
            reason: "Kulit kuning merata dan bintik cokelat masih sedikit.",
            number: 1
        )
        .padding()
    }
}
