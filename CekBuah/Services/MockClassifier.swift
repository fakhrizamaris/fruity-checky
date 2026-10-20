import CoreGraphics

/// Random but plausible results, so the UI works before any model exists.
struct MockClassifier: FruitClassifying {
    var delay: Duration = .milliseconds(300)
    var rules: DecisionRules = .standard

    func classify(image: CGImage, fruit: Fruit) async throws -> ClassificationResult {
        try await Task.sleep(for: delay)

        let states = RipenessState.modelStates
        let top = states.randomElement() ?? .ripe
        let topProbability = Double.random(in: 0.45...0.95)
        let others = states.filter { $0 != top }
        let weights = others.map { _ in Double.random(in: 0.1...1) }
        let total = weights.reduce(0, +)

        var predictions = [ClassPrediction(state: top, probability: topProbability)]
        for (state, weight) in zip(others, weights) {
            predictions.append(ClassPrediction(state: state, probability: (1 - topProbability) * weight / total))
        }
        return rules.evaluate(predictions, isDemo: true)
    }
}
