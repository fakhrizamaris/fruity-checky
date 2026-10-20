import Foundation

/// Fruit kinds the shelf detector (`ShelfFruitDetector.mlmodel`) can find.
/// Raw values are the detector's labels, written by shelf-detection/pipeline/common.py (FRUITS).
enum ShelfFruit: String, CaseIterable, Identifiable, Codable, Sendable {
    case avocado
    case banana
    case dragonFruit = "dragon_fruit"
    case mango
    case papaya

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .avocado: "Alpukat"
        case .banana: "Pisang"
        case .dragonFruit: "Buah naga"
        case .mango: "Mangga"
        case .papaya: "Pepaya"
        }
    }

    var emoji: String {
        switch self {
        case .avocado: "🥑"
        case .banana: "🍌"
        case .dragonFruit: "🐉"
        case .mango: "🥭"
        case .papaya: "🍈"
        }
    }

    /// The fruit whose ripeness model judges this kind, or nil when the app has no ripeness model for it yet
    /// (avocado and dragon fruit: their per-fruit models are trained separately, see shelf-detection/README.md).
    var ripenessFruit: Fruit? {
        switch self {
        case .banana: .banana
        case .mango: .mango
        case .papaya: .papaya
        case .avocado, .dragonFruit: nil
        }
    }

    /// Accepts the detector label and a few spellings a hand-made Create ML project might use.
    init?(detectorLabel: String) {
        let key = detectorLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        switch key {
        case "avocado", "alpukat": self = .avocado
        case "banana", "pisang": self = .banana
        case "dragon_fruit", "dragonfruit", "buah_naga", "pitaya": self = .dragonFruit
        case "mango", "mangga": self = .mango
        case "papaya", "pepaya": self = .papaya
        default: return nil
        }
    }
}
