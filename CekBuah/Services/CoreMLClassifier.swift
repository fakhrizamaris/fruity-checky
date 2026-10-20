import CoreML
import Foundation
import Vision

enum ClassifierError: LocalizedError {
    case modelMissing(Fruit)
    case unknownLabels

    var errorDescription: String? {
        switch self {
        case .modelMissing(let fruit): "Model untuk \(fruit.displayName.lowercased()) belum ada di app."
        case .unknownLabels: "Label model tidak dikenali. Gunakan: mentah, matang, terlalu_matang, busuk."
        }
    }
}

/// Runs one Core ML model per fruit through Vision (`CoreMLRequest`, iOS 18+).
/// Models are loaded once and cached.
actor CoreMLClassifier: FruitClassifying {
    private var containers: [Fruit: CoreMLModelContainer] = [:]
    private let rules: DecisionRules

    init(rules: DecisionRules = .standard) {
        self.rules = rules
    }

    /// Xcode compiles `<name>.mlpackage` / `.mlmodel` into `<name>.mlmodelc` inside the app bundle.
    static func modelURL(for fruit: Fruit, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: fruit.modelName, withExtension: "mlmodelc")
    }

    static func hasModel(for fruit: Fruit) -> Bool {
        modelURL(for: fruit) != nil
    }

    func classify(image: CGImage, fruit: Fruit) async throws -> ClassificationResult {
        var request = CoreMLRequest(model: try container(for: fruit))
        // Same preprocessing as training evaluation: center square, scaled to the model input.
        request.cropAndScaleAction = .centerCrop

        let observations = try await request.perform(on: image)
        let raw = observations
            .compactMap { $0 as? ClassificationObservation }
            .map { (label: $0.identifier, value: Double($0.confidence)) }

        let predictions = Self.normalize(raw)
        guard !predictions.isEmpty else { throw ClassifierError.unknownLabels }
        var result = rules.evaluate(predictions)
        result.modelName = fruit.modelName
        return result
    }

    private func container(for fruit: Fruit) throws -> CoreMLModelContainer {
        if let cached = containers[fruit] { return cached }
        guard let url = Self.modelURL(for: fruit) else { throw ClassifierError.modelMissing(fruit) }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let container = try CoreMLModelContainer(model: MLModel(contentsOf: url, configuration: configuration))
        containers[fruit] = container
        return container
    }

    /// Vision passes the model's values through unchanged. If they are not already
    /// probabilities (0...1, summing to 1), treat them as logits and apply softmax.
    /// Labels the app does not know are dropped.
    static func normalize(_ raw: [(label: String, value: Double)]) -> [ClassPrediction] {
        let values = raw.map(\.value)
        let looksLikeProbabilities = values.allSatisfy { (0...1).contains($0) }
            && abs(values.reduce(0, +) - 1) < 0.05
        let probabilities = looksLikeProbabilities ? values : softmax(values)

        return zip(raw, probabilities).compactMap { item, probability in
            RipenessState(modelLabel: item.label).map { ClassPrediction(state: $0, probability: probability) }
        }
    }

    private static func softmax(_ values: [Double]) -> [Double] {
        guard let maxValue = values.max() else { return [] }
        let exps = values.map { exp($0 - maxValue) }
        let sum = exps.reduce(0, +)
        return exps.map { $0 / sum }
    }
}
