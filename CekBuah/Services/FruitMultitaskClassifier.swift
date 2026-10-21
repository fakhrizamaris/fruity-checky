import CoreGraphics
import CoreML
import Foundation
import Vision

/// `FruitMultitask.mlpackage`: one MobileNetV3 backbone with three heads (species, ripeness stage, damage),
/// trained in ripeness-multitask/train_multitask.ipynb. Replaces FruitSpecies + RipeNetV2 in the live scan.
/// The model has one image input, so it is called directly through Core ML (no Vision request needed).
actor FruitMultitaskClassifier {
    static let modelName = MultitaskRules.modelName
    static let shared = FruitMultitaskClassifier()

    private var model: MLModel?
    private(set) var schema = MultitaskSchema()

    static var isAvailable: Bool { Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") != nil }

    func read(_ image: CGImage) throws -> MultitaskReading {
        let model = try loadedModel()
        guard let constraint = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else {
            throw ClassifierError.unknownLabels
        }
        // Crops are already square; the model was trained on square crops resized to 224.
        let input = try MLFeatureValue(cgImage: image, constraint: constraint,
                                       options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": input]))
        let values = MultitaskOutput(species: Self.values("species", output), stage: Self.values("stage", output),
                                     damage: Self.values("damage", output).first ?? 0)
        return MultitaskRules.read(values, schema: schema)
    }

    private func loadedModel() throws -> MLModel {
        if let model { return model }
        guard let url = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc") else {
            throw ShelfDetectorError.modelMissing
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loaded = try MLModel(contentsOf: url, configuration: configuration)
        let metadata = loaded.modelDescription.metadata[.creatorDefinedKey] as? [String: String] ?? [:]
        schema = MultitaskSchema(metadata: metadata)
        model = loaded
        return loaded
    }

    private static func values(_ name: String, _ output: MLFeatureProvider) -> [Double] {
        guard let array = output.featureValue(for: name)?.multiArrayValue else { return [] }
        return (0..<array.count).map { array[$0].doubleValue }
    }
}
