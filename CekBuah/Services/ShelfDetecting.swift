import CoreGraphics
import CoreML
import Foundation
import Vision

/// Anything that finds fruits on a shelf photo. The scan screen only talks to this protocol,
/// so the trained Core ML detector and the training-free Vision fallback are interchangeable.
protocol ShelfDetecting: Sendable {
    /// Shown in tester mode and written to logs.
    var name: String { get }
    /// Unfiltered boxes; `ShelfPostProcessing.finalize` turns them into numbered detections.
    func candidates(in image: CGImage) async throws -> [ShelfCandidate]
}

/// Create ML object detector (`ShelfFruitDetector.mlmodel`) run through Vision's `VNCoreMLRequest`.
/// The model is loaded once and cached.
///
/// Uses the older Vision API on purpose: the Swift `CoreMLRequest` rejects Create ML detectors
/// ("inputImageFeatureName does not point to a MLFeatureTypeImage input") because they also take
/// iouThreshold and confidenceThreshold inputs, even with the image input named explicitly.
/// Reproduced on macOS 27 with this model on 20 Oct 2026; `VNCoreMLRequest` works.
actor CoreMLShelfDetector: ShelfDetecting {
    static let modelName = "ShelfFruitDetector"
    static let shared = CoreMLShelfDetector()

    nonisolated var name: String { Self.modelName }
    private var visionModel: VNCoreMLModel?

    /// Xcode compiles `<name>.mlmodel` / `.mlpackage` into `<name>.mlmodelc` inside the app bundle.
    static var isAvailable: Bool { Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") != nil }

    func candidates(in image: CGImage) async throws -> [ShelfCandidate] {
        let request = VNCoreMLRequest(model: try await loadedModel())
        // Create ML trains the detector on the whole photo stretched to its input size.
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = request.results as? [VNRecognizedObjectObservation] ?? []
        return observations.map { observation in
            let best = observation.labels.first
            let box = observation.boundingBox // normalized, origin bottom-left
            return ShelfCandidate(
                box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
                label: best?.identifier ?? "",
                confidence: Double(best?.confidence ?? observation.confidence)
            )
        }
    }

    private func loadedModel() async throws -> VNCoreMLModel {
        if let visionModel { return visionModel }
        guard let url = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc") else {
            throw ShelfDetectorError.modelMissing
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loaded = try VNCoreMLModel(for: try await MLModel.load(contentsOf: url, configuration: configuration))
        visionModel = loaded
        return loaded
    }
}

enum ShelfDetectorError: LocalizedError {
    case modelMissing

    var errorDescription: String? {
        switch self {
        case .modelMissing: "Model belum ada di app."
        }
    }
}

