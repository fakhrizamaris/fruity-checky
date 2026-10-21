import CoreGraphics
import CoreML
import Foundation
import Vision

/// Names the fruit on one crop: `FruitSpecies.mlmodel`, a Create ML image classifier trained on
/// ripeness-multitask/data/createml_species (labels avocado, banana, dragon_fruit, mango, papaya, other).
/// Stand-in for the species head of the planned multi-task model.
actor FruitSpeciesClassifier {
    static let modelName = "FruitSpecies"
    static let shared = FruitSpeciesClassifier()

    struct Prediction: Sendable {
        /// Nil for "other" (a fruit the app does not support, or not a fruit).
        let kind: ShelfFruit?
        let label: String
        let confidence: Double
    }

    private var container: CoreMLModelContainer?

    static var isAvailable: Bool { Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") != nil }

    func classify(_ image: CGImage) async throws -> Prediction? {
        var request = CoreMLRequest(model: try loadedContainer())
        // Crops are already square; Create ML trained on the whole image.
        request.cropAndScaleAction = .scaleToFill
        let observations = try await request.perform(on: image).compactMap { $0 as? ClassificationObservation }
        guard let best = observations.max(by: { $0.confidence < $1.confidence }) else { return nil }
        return Prediction(kind: ShelfFruit(detectorLabel: best.identifier), label: best.identifier,
                          confidence: Double(best.confidence))
    }

    private func loadedContainer() throws -> CoreMLModelContainer {
        if let container { return container }
        guard let url = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc") else {
            throw ShelfDetectorError.modelMissing
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loaded = try CoreMLModelContainer(model: MLModel(contentsOf: url, configuration: configuration))
        container = loaded
        return loaded
    }
}
