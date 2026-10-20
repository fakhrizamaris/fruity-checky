import Foundation

/// Fruits supported by the PoC.
/// To add a fruit: add a case here, an entry in knowledge-base.json,
/// and train `<modelName>.mlpackage` with ml/train_ripeness.ipynb (copied into Resources/Models).
/// A fruit without a bundled model runs in demo mode.
enum Fruit: String, CaseIterable, Identifiable, Codable, Sendable {
    case apple
    case banana
    case mango
    case orange
    case papaya
    case pineapple

    var id: String { rawValue }

    /// Fruits shown on the home screen, in this order.
    static let enabled: [Fruit] = [.banana, .mango, .orange, .papaya, .pineapple, .apple]

    var displayName: String {
        switch self {
        case .apple: "Apel"
        case .banana: "Pisang"
        case .mango: "Mangga"
        case .orange: "Jeruk"
        case .papaya: "Pepaya"
        case .pineapple: "Nanas"
        }
    }

    /// Core ML model file name (without extension) bundled in the app.
    var modelName: String {
        switch self {
        case .apple: "AppleRipeness" // not trained yet; RipeNetV2 covers apple
        case .banana: "BananaRipeness"
        case .mango: "MangoRipeness"
        case .orange: "OrangeRipeness"
        case .papaya: "PapayaRipeness"
        case .pineapple: "PineappleRipeness"
        }
    }

    var emoji: String {
        switch self {
        case .apple: "🍎"
        case .banana: "🍌"
        case .mango: "🥭"
        case .orange: "🍊"
        case .papaya: "🍈"
        case .pineapple: "🍍"
        }
    }

    /// Skin colour is an unreliable ripeness sign for these fruits (varies per variety,
    /// or stays green when ripe), so the physical check is always offered.
    var alwaysOffersPhysicalCheck: Bool {
        switch self {
        case .apple, .mango, .orange, .pineapple: true
        case .banana, .papaya: false
        }
    }
}
