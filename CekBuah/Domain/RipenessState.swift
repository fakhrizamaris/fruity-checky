import Foundation

/// The only five outputs the app may show.
enum RipenessState: String, CaseIterable, Identifiable, Codable, Sendable {
    case unripe = "mentah"
    case ripe = "matang"
    case overripe = "terlalu_matang"
    case rotten = "busuk"
    case unsure = "tidak_yakin"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unripe: "Mentah"
        case .ripe: "Matang"
        case .overripe: "Terlalu matang"
        case .rotten: "Busuk"
        case .unsure: "Tidak yakin"
        }
    }

    /// States a model is allowed to predict (`unsure` comes from DecisionRules only).
    static let modelStates: [RipenessState] = [.unripe, .ripe, .overripe, .rotten]

    /// Ripening order, used to break exact ties: the later (riskier) stage wins,
    /// because calling a rotten fruit ripe is the most harmful mistake.
    var ripeningStage: Int {
        switch self {
        case .unsure: -1
        case .unripe: 0
        case .ripe: 1
        case .overripe: 2
        case .rotten: 3
        }
    }

    /// Maps a model class label to a state.
    /// Accepts the PoC labels (mentah, matang, ...) and common English dataset labels,
    /// so a model trained straight from English folders still works.
    init?(modelLabel: String) {
        let key = modelLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        switch key {
        case "mentah", "unripe", "green", "raw": self = .unripe
        case "matang", "ripe", "fresh": self = .ripe
        case "terlalu_matang", "overripe", "overipe", "over_ripe": self = .overripe
        case "busuk", "rotten", "perished": self = .rotten
        default: return nil
        }
    }
}
