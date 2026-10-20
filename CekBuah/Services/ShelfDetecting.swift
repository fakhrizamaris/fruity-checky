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

/// Create ML object detector (`ShelfFruitDetector.mlmodel`) run through Vision's `CoreMLRequest`.
/// The model is loaded once and cached.
actor CoreMLShelfDetector: ShelfDetecting {
    static let modelName = "ShelfFruitDetector"
    static let shared = CoreMLShelfDetector()

    nonisolated var name: String { Self.modelName }
    private var container: CoreMLModelContainer?

    /// Xcode compiles `<name>.mlmodel` / `.mlpackage` into `<name>.mlmodelc` inside the app bundle.
    static var isAvailable: Bool { Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") != nil }

    func candidates(in image: CGImage) async throws -> [ShelfCandidate] {
        var request = CoreMLRequest(model: try await loadedContainer())
        // Create ML trains the detector on the whole photo stretched to its input size.
        request.cropAndScaleAction = .scaleToFill
        let observations = try await request.perform(on: image)
        return observations.compactMap { $0 as? RecognizedObjectObservation }.map { observation in
            let best = observation.labels.first
            return ShelfCandidate(
                box: observation.boundingBox.toImageCoordinates(CGSize(width: 1, height: 1), origin: .upperLeft),
                label: best?.identifier ?? "",
                confidence: Double(best?.confidence ?? observation.confidence)
            )
        }
    }

    private func loadedContainer() async throws -> CoreMLModelContainer {
        if let container { return container }
        guard let url = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc") else {
            throw ShelfDetectorError.modelMissing
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loaded = try CoreMLModelContainer(model: try await MLModel.load(contentsOf: url, configuration: configuration))
        container = loaded
        return loaded
    }
}

/// Fallback while no detector is bundled: Vision's class-agnostic foreground instances.
/// Finds separate objects but not their kind, and merges fruits that touch.
struct ForegroundShelfDetector: ShelfDetecting {
    var detector = ForegroundFruitDetector(minAreaFraction: 0.005, maxObjects: 40)
    var name: String { "Vision foreground (tanpa model)" }

    func candidates(in image: CGImage) async throws -> [ShelfCandidate] {
        try await detector.regions(in: image).map { ShelfCandidate(box: $0, label: "", confidence: 1) }
    }
}

enum ShelfDetectorError: LocalizedError {
    case modelMissing

    var errorDescription: String? {
        switch self {
        case .modelMissing: "Model deteksi rak belum ada di app."
        }
    }
}

enum ShelfDetectorFactory {
    /// The trained detector when it is bundled, otherwise the Vision fallback.
    static func current() -> any ShelfDetecting {
        CoreMLShelfDetector.isAvailable ? CoreMLShelfDetector.shared : ForegroundShelfDetector()
    }
}
