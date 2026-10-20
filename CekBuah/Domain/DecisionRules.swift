import Foundation

/// Turns model probabilities into one of the five states.
/// - Top class ≥ 50% → that label. Probabilities sum to 100%, so at most one class can pass.
/// - Exact tie → the later ripening stage wins (busuk > terlalu matang > matang > mentah).
/// - No class ≥ 50% → `tidak_yakin`, and the app sends the user to the physical check.
/// Tune from validation data (see the threshold section in ml/train_ripeness.ipynb).
struct DecisionRules: Sendable {
    var minTopConfidence: Double = 0.50
    var minMargin: Double = 0.0

    static let standard = DecisionRules()

    func evaluate(_ predictions: [ClassPrediction], isDemo: Bool = false) -> ClassificationResult {
        let ranked = Self.rank(predictions)
        guard let top = ranked.first else {
            return ClassificationResult(state: .unsure, confidence: 0, ranked: [], isDemo: isDemo)
        }
        let second = ranked.dropFirst().first?.probability ?? 0
        let margin = top.probability - second
        let confident = top.probability >= minTopConfidence && margin >= minMargin

        return ClassificationResult(
            state: confident ? top.state : .unsure,
            confidence: top.probability,
            ranked: ranked,
            isDemo: isDemo
        )
    }

    /// Highest probability first; exact ties ordered by later ripening stage, so the result is deterministic.
    static func rank(_ predictions: [ClassPrediction]) -> [ClassPrediction] {
        predictions.sorted { lhs, rhs in
            if lhs.probability != rhs.probability { return lhs.probability > rhs.probability }
            return lhs.state.ripeningStage > rhs.state.ripeningStage
        }
    }

    /// Physical check is offered when the model is unsure, when the top two classes tie,
    /// or for fruits whose skin colour is unreliable (mango).
    static func offersPhysicalCheck(for result: ClassificationResult, fruit: Fruit) -> Bool {
        result.state == .unsure || result.isTie || fruit.alwaysOffersPhysicalCheck
    }
}
