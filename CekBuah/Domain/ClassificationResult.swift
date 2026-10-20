import Foundation

/// One class with its probability (0...1).
struct ClassPrediction: Hashable, Sendable {
    let state: RipenessState
    let probability: Double

    /// "50,4 persen": one decimal so near-ties are visible to testers.
    var percentText: String {
        let value = (probability * 100).formatted(
            .number.precision(.fractionLength(1)).locale(Locale(identifier: "id_ID"))
        )
        return "\(value) persen"
    }
}

/// Extra heads of the RipeNet V2 model. Not used for decisions.
struct ModelExtras: Sendable {
    /// Fruit head's top label (apple, banana, mango, orange, papaya, pineapple) and its probability.
    let fruitLabel: String
    let fruitProbability: Double
    /// Days-remaining regression; RipeNet's labels are synthetic, so this is never shown to regular users.
    let days: Double
}

/// Final result shown to the user, after DecisionRules.
struct ClassificationResult: Sendable {
    /// Shown state. `.unsure` when no class reaches the majority threshold.
    let state: RipenessState
    /// Probability of the model's top class (0...1).
    let confidence: Double
    /// All model classes, highest first (ties ordered by ripening stage).
    let ranked: [ClassPrediction]
    /// True when produced by MockClassifier (no real model bundled).
    let isDemo: Bool
    /// Model that produced this result (tester log), e.g. "BananaRipeness" or "RipeNetV2".
    var modelName = ""
    /// Extra outputs of a multi-task model; shown only in tester mode.
    var extras: ModelExtras?

    /// Model's two best classes, highest first.
    var topTwo: [ClassPrediction] { Array(ranked.prefix(2)) }

    var confidencePercent: Int { Int((confidence * 100).rounded()) }

    /// Top two classes have exactly the same probability; the label came from the tie rule.
    var isTie: Bool {
        topTwo.count == 2 && topTwo[0].probability == topTwo[1].probability
    }

    /// "Keyakinan 82%". When unsure, points to the physical check instead of guessing.
    var confidenceText: String {
        state == .unsure
            ? "Hasil foto belum meyakinkan. Lanjutkan dengan cek fisik."
            : "Keyakinan \(confidencePercent)%"
    }
}
