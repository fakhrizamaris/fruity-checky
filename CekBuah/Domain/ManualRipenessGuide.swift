import Foundation

/// Hand check that DECIDES the ripeness stage for fruits whose skin colour is unreliable in a photo:
/// avocado (local green varieties barely change colour; Hass darkens but firmness is the ripeness index)
/// and mango (Arumanis stays green when ripe). Rubrics from the "Engine Sisa Hari" note, sections 7.2-7.3.
/// The photo's guess is shown as a hint only.
struct ManualCheckOption: Identifiable, Hashable, Sendable {
    /// Shared stage 0...4; nil = "Tidak yakin".
    let stage: Int?
    let title: String
    let detail: String

    var id: String { "\(stage.map(String.init) ?? "unsure")-\(title)" }

    var state: RipenessState {
        stage.map(MultitaskRules.state(forStage:)) ?? .unsure
    }

    /// Stage name on the shared scale, e.g. "Mulai matang" (the app state would show stage 1 as "Mentah").
    var stageName: String {
        guard let stage else { return "Tidak yakin" }
        return MultitaskRules.stageNames[stage].prefix(1).uppercased() + MultitaskRules.stageNames[stage].dropFirst()
    }
}

struct ManualRipenessGuide: Sendable {
    let kind: ShelfFruit
    /// How to check, shown above the options.
    let howTo: String
    /// Extra caution shown under the options.
    let note: String
    let options: [ManualCheckOption]

    static func required(for kind: ShelfFruit) -> ManualRipenessGuide? {
        switch kind {
        case .avocado: avocado
        case .mango: mango
        default: nil
        }
    }

    /// Result stored in the basket: the hand check, labelled as such.
    static func result(for option: ManualCheckOption) -> ClassificationResult {
        var result = ClassificationResult(state: option.state, confidence: option.stage == nil ? 0 : 1,
                                          ranked: [ClassPrediction(state: option.state, probability: 1)], isDemo: false)
        result.modelName = "cek manual"
        return result
    }

    static let unsure = ManualCheckOption(stage: nil, title: "Tidak yakin",
                                          detail: "Simpan tanpa tahap. Cek lagi di rumah.")

    static let avocado = ManualRipenessGuide(
        kind: .avocado,
        howTo: "Genggam alpukat, lalu tekan perlahan dengan seluruh telapak tangan, bukan ujung jari, supaya tidak memar. Untuk Hass, lihat juga warna kulitnya.",
        note: "Warna tutup tangkai belum terbukti sebagai patokan, jadi tidak dipakai.",
        options: [
            ManualCheckOption(stage: 0, title: "Keras seperti apel", detail: "Tidak memberi sama sekali. Kulit Hass masih hijau."),
            ManualCheckOption(stage: 1, title: "Sedikit memberi", detail: "Sedikit lentur saat ditekan, lalu kembali. Kulit Hass mulai gelap."),
            ManualCheckOption(stage: 2, title: "Empuk merata", detail: "Memberi merata tanpa meninggalkan bekas. Kulit Hass ungu kehitaman."),
            ManualCheckOption(stage: 3, title: "Sangat lembek", detail: "Mudah penyok, kulit terasa kendur. Habiskan hari ini."),
            ManualCheckOption(stage: 4, title: "Berair, berbau, atau berjamur", detail: "Jangan dimakan."),
            unsure,
        ])

    static let mango = ManualRipenessGuide(
        kind: .mango,
        howTo: "Tekan lembut dengan ibu jari di dekat pangkal (tangkai), lalu cium aroma di pangkal.",
        note: "Warna kulit tidak bisa diandalkan: Arumanis tetap hijau walau sudah matang. Aroma hanya pendukung, utamakan rasa tekan.",
        options: [
            ManualCheckOption(stage: 0, title: "Keras, tidak berbau", detail: "Tidak memberi saat ditekan."),
            ManualCheckOption(stage: 1, title: "Sedikit memberi, harum lemah", detail: "Mulai lentur di dekat pangkal."),
            ManualCheckOption(stage: 2, title: "Empuk, harum kuat", detail: "Memberi saat ditekan, aroma manis jelas di pangkal."),
            ManualCheckOption(stage: 3, title: "Lembek, kulit mulai berkerut", detail: "Aroma sangat kuat atau mulai asam. Habiskan hari ini."),
            ManualCheckOption(stage: 4, title: "Berair, bercak hitam meluas", detail: "Bau fermentasi. Jangan dimakan."),
            unsure,
        ])
}
