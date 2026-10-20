import CoreGraphics
import Foundation

/// Rules for the live scan, which shows one fruit at a time: the fruit nearest the centre wins,
/// and the label only changes after the same fruit is seen in consecutive frames.
enum LiveFruitPick {
    /// Boxes below this detector confidence are ignored in the live view.
    static let minConfidence = 0.5
    /// Boxes in consecutive frames overlapping more than this are the same fruit.
    static let sameFruitIoU = 0.3

    /// The fruit to show: confidence weighted by closeness to the centre of the frame,
    /// so the fruit the user points at wins over a more confident one at the edge.
    static func best(_ candidates: [ShelfCandidate], minConfidence: Double = minConfidence) -> ShelfCandidate? {
        candidates
            .filter { $0.confidence >= minConfidence }
            .max { score($0) < score($1) }
    }

    static func score(_ candidate: ShelfCandidate) -> Double {
        let dx = candidate.box.midX - 0.5
        let dy = candidate.box.midY - 0.5
        // 0 at the centre, about 0.7 in a corner.
        let distance = Double((dx * dx + dy * dy).squareRoot())
        return candidate.confidence * (1 - distance)
    }

    /// Same kind and overlapping boxes: treated as the same fruit, so the label can settle.
    static func isSameFruit(_ a: ShelfCandidate, _ b: ShelfCandidate) -> Bool {
        a.label == b.label && ShelfPostProcessing.intersectionOverUnion(a.box, b.box) > sameFruitIoU
    }
}
