import CoreML
import Foundation
import Vision

/// RipeNet V2 (github.com/alexcj10/ripenet): one EfficientNet-B0 with three heads (ripeness, fruit, days),
/// converted by ml/convert_ripenet.py. One inference gives both the fruit type and its ripeness:
/// the ripeness head goes through the same DecisionRules as the per-fruit models, the fruit head
/// recognises the fruit (FruitIdentifying), and the days head is a tester detail only.
actor RipeNetClassifier: FruitClassifying, FruitIdentifying {
    static let shared = RipeNetClassifier()
    static let modelName = "RipeNetV2"
    /// Output order of the ripeness head (RipeNet: Unripe, Fresh, Rotten).
    static let ripenessStates: [RipenessState] = [.unripe, .ripe, .rotten]
    /// Output order of the fruit head; raw values of `Fruit`.
    static let fruitLabels = ["apple", "banana", "mango", "orange", "papaya", "pineapple"]

    /// Everything one inference returns.
    struct Scan: Sendable {
        let fruitScores: [Fruit: Double]
        let result: ClassificationResult
    }

    private var model: MLModel?
    private let rules: DecisionRules

    init(rules: DecisionRules = .standard) {
        self.rules = rules
    }

    static var isAvailable: Bool {
        Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") != nil
    }

    func scan(image: CGImage) throws -> Scan {
        let model = try loadedModel()
        guard let constraint = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else {
            throw ClassifierError.unknownLabels
        }
        // RipeNet resizes to 224 x 224 without cropping; the app passes a square crop.
        let input = try MLFeatureValue(cgImage: image, constraint: constraint,
                                       options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
        let output = try Self.predict(model, MLDictionaryFeatureProvider(dictionary: ["image": input]))

        let ripeness = Self.values(of: "ripeness", in: output)
        guard ripeness.count == Self.ripenessStates.count else { throw ClassifierError.unknownLabels }
        var result = rules.evaluate(zip(Self.ripenessStates, ripeness).map {
            ClassPrediction(state: $0, probability: $1)
        })
        result.modelName = Self.modelName

        let fruits = Self.values(of: "fruit", in: output)
        var scores: [Fruit: Double] = [:]
        for (label, probability) in zip(Self.fruitLabels, fruits) {
            if let fruit = Fruit(rawValue: label) { scores[fruit] = probability }
        }
        if let best = fruits.indices.max(by: { fruits[$0] < fruits[$1] }), best < Self.fruitLabels.count {
            result.extras = ModelExtras(fruitLabel: Self.fruitLabels[best], fruitProbability: fruits[best],
                                        days: Self.values(of: "days", in: output).first ?? 0)
        }
        return Scan(fruitScores: scores, result: result)
    }

    func classify(image: CGImage, fruit: Fruit) async throws -> ClassificationResult {
        try scan(image: image).result
    }

    func scores(for image: CGImage) async throws -> [Fruit: Double] {
        try scan(image: image).fruitScores
    }

    private func loadedModel() throws -> MLModel {
        if let model { return model }
        guard let url = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc") else {
            throw ClassifierError.modelMissing(.banana)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loaded = try MLModel(contentsOf: url, configuration: configuration)
        model = loaded
        return loaded
    }

    /// Synchronous prediction (outside an async context the sync overload is picked), so the
    /// non-Sendable model never leaves this actor.
    private static func predict(_ model: MLModel, _ input: MLFeatureProvider) throws -> MLFeatureProvider {
        try model.prediction(from: input)
    }

    private static func values(of name: String, in output: MLFeatureProvider) -> [Double] {
        guard let array = output.featureValue(for: name)?.multiArrayValue else { return [] }
        return (0..<array.count).map { array[$0].doubleValue }
    }
}
