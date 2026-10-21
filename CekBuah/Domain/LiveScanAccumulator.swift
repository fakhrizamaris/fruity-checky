import CoreGraphics
import Foundation

/// What one live frame said about the fruit in front of the camera.
struct LiveObservation: Sendable {
    /// Frame counter, used by the scan model to find the crop of this frame.
    let frame: Int
    let kind: ShelfFruit
    /// 0...1, from the detector label or the fruit-recognition head.
    let kindConfidence: Double
    /// Normalized box inside the live frame.
    let box: CGRect
    /// Nil when the app has no ripeness model for this kind, or judging failed.
    let result: ClassificationResult?
}

/// The settled answer after the user turned the fruit in front of the camera.
struct LiveVerdict: Sendable {
    let kind: ShelfFruit
    /// Ripeness of the frame that best represents the agreed state; nil when this kind has no ripeness model.
    let result: ClassificationResult?
    /// Frames that agreed on the kind / frames looked at.
    let agreeing: Int
    let looked: Int
    let meanKindConfidence: Double
    /// Frame whose crop becomes the basket thumbnail (the most confident agreeing frame).
    let bestFrame: Int
}

/// Collects frames of one fruit while the user turns it, and decides when the app is sure enough to ask
/// "Ambil?". One frame can be fooled by glare or by the side facing the camera; several sides agreeing are not.
struct LiveScanAccumulator: Sendable {
    /// About 2 seconds at the camera's 3 scans per second.
    static let framesNeeded = 6
    /// Only the most recent frames count, so an early wrong guess is forgotten.
    static let window = 10
    static let minAgreement = 0.7
    static let minKindConfidence = ShelfPostProcessing.defaultMinConfidence
    /// A box this far from the previous one (IoU) means another fruit was put in front of the camera.
    static let newFruitIoU = 0.05

    private(set) var observations: [LiveObservation] = []

    var isEmpty: Bool { observations.isEmpty }

    /// 0...1 for the progress bar: agreeing frames of the leading kind over the frames needed.
    var progress: Double {
        guard let kind = leadingKind else { return 0 }
        return min(1, Double(observations.filter { $0.kind == kind }.count) / Double(Self.framesNeeded))
    }

    /// Kind most frames agree on so far (shown while collecting).
    var leadingKind: ShelfFruit? {
        Dictionary(grouping: observations, by: \.kind).max { $0.value.count < $1.value.count }?.key
    }

    mutating func add(_ observation: LiveObservation) {
        if let last = observations.last,
           ShelfPostProcessing.intersectionOverUnion(last.box, observation.box) < Self.newFruitIoU {
            observations.removeAll()
        }
        observations.append(observation)
        if observations.count > Self.window { observations.removeFirst(observations.count - Self.window) }
    }

    mutating func reset() { observations.removeAll() }

    /// Nil until enough frames agree with enough confidence (and, for kinds with a ripeness model,
    /// until ripeness has been judged on those frames).
    func verdict() -> LiveVerdict? {
        guard let kind = leadingKind else { return nil }
        let agreeing = observations.filter { $0.kind == kind }
        guard agreeing.count >= Self.framesNeeded,
              Double(agreeing.count) / Double(observations.count) >= Self.minAgreement else { return nil }
        let meanConfidence = agreeing.map(\.kindConfidence).reduce(0, +) / Double(agreeing.count)
        guard meanConfidence >= Self.minKindConfidence else { return nil }

        var result: ClassificationResult?
        if kind.ripenessFruit != nil {
            let judged = agreeing.compactMap(\.result)
            guard judged.count * 2 >= agreeing.count else { return nil }
            // Most frequent state over the sides seen; ties go to the later (riskier) stage.
            let byState = Dictionary(grouping: judged, by: \.state)
            let state = byState.max { lhs, rhs in
                lhs.value.count != rhs.value.count ? lhs.value.count < rhs.value.count
                    : lhs.key.ripeningStage < rhs.key.ripeningStage
            }?.key
            result = judged.filter { $0.state == state }.max { $0.confidence < $1.confidence }
        }
        let best = agreeing.max { $0.kindConfidence < $1.kindConfidence } ?? agreeing[0]
        return LiveVerdict(kind: kind, result: result, agreeing: agreeing.count, looked: observations.count,
                           meanKindConfidence: meanConfidence, bestFrame: best.frame)
    }
}
