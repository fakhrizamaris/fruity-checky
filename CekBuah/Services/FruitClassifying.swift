import CoreGraphics
import SwiftUI

/// Anything that can judge ripeness from a photo. Screens only talk to this protocol,
/// so MockClassifier and CoreMLClassifier are interchangeable.
protocol FruitClassifying: Sendable {
    func classify(image: CGImage, fruit: Fruit) async throws -> ClassificationResult
}

/// Which ripeness model the app uses. Testers can switch in the menu; everyone else gets `standard`.
enum RipenessModelChoice: String, CaseIterable, Identifiable, Sendable {
    /// RipeNet V2 multi-task model (one model for all fruits).
    case ripeNet = "ripenetV2"
    /// One Cek Buah model per fruit (ml/train_ripeness.ipynb).
    case perFruit

    static let key = "ripenessModel"
    static let standard: RipenessModelChoice = .ripeNet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ripeNet: "RipeNet V2 (satu model)"
        case .perFruit: "Cek Buah (model per buah)"
        }
    }

    /// The tester's choice applies only while tester mode is on.
    static func current(in defaults: UserDefaults = .standard) -> RipenessModelChoice {
        guard defaults.bool(forKey: SettingsKey.testerMode),
              let raw = defaults.string(forKey: key), let choice = RipenessModelChoice(rawValue: raw) else { return standard }
        return choice
    }
}

/// Uses the chosen Core ML model when it is bundled, otherwise the mock.
/// Adding `MangoRipeness.mlpackage` to Resources/Models switches mango to the real per-fruit model.
struct ClassifierRouter: FruitClassifying {
    static let shared = ClassifierRouter()

    private let coreML = CoreMLClassifier()
    private let ripeNet = RipeNetClassifier.shared
    private let mock = MockClassifier()

    static func hasModel(for fruit: Fruit, choice: RipenessModelChoice = .current()) -> Bool {
        choice == .ripeNet ? RipeNetClassifier.isAvailable : CoreMLClassifier.hasModel(for: fruit)
    }

    func classify(image: CGImage, fruit: Fruit) async throws -> ClassificationResult {
        let choice = RipenessModelChoice.current()
        if choice == .ripeNet, RipeNetClassifier.isAvailable {
            return try await ripeNet.classify(image: image, fruit: fruit)
        }
        if CoreMLClassifier.hasModel(for: fruit) {
            return try await coreML.classify(image: image, fruit: fruit)
        }
        return try await mock.classify(image: image, fruit: fruit)
    }
}

extension EnvironmentValues {
    @Entry var classifier: any FruitClassifying = ClassifierRouter.shared
}
