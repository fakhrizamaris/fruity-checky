import CoreGraphics
import SwiftUI
import Vision

/// Tells which supported fruit a photo looks like. Screens never talk to Vision directly,
/// so tests can plug in a fake.
protocol FruitIdentifying: Sendable {
    /// Best score (0...1) per supported fruit.
    func scores(for image: CGImage) async throws -> [Fruit: Double]
}

/// Apple's built-in image classifier (on-device, no training). Its taxonomy has
/// banana, mango, papaya, pineapple, apple and citrus labels. Not used in the current flow
/// (RipeNetV2's fruit head recognises the fruit); kept as a fallback, use `FruitIdentity.visionThreshold`.
struct VisionFruitIdentifier: FruitIdentifying {
    func scores(for image: CGImage) async throws -> [Fruit: Double] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            try VNImageRequestHandler(cgImage: image).perform([request])
            let observations = (request.results ?? []).map { (label: $0.identifier, confidence: Double($0.confidence)) }
            return FruitIdentity.scores(from: observations)
        }.value
    }
}

extension EnvironmentValues {
    @Entry var identifier: any FruitIdentifying = RipeNetClassifier.shared
}
