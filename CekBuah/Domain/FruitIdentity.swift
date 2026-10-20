import Foundation

/// Result of the fruit-identity check for one detected fruit.
/// It only warns: the user can always keep their own choice.
enum IdentityVerdict: String, Sendable {
    /// The photo looks like the fruit the user picked.
    case match
    /// The photo looks like another supported fruit (see `FruitIdentity.suggested`).
    case looksLike
    /// No supported fruit was recognised.
    case unrecognized
    /// The check could not run (e.g. Vision unsupported on Simulator); nothing is shown.
    case unavailable
}

/// What the user did with a warning, kept for the tester log.
enum IdentityAction: String, Sendable {
    case switched
    case kept
}

/// Best Vision score (0...1) per supported fruit, plus the verdict against the picked fruit.
struct FruitIdentity: Sendable, Equatable {
    /// Minimum RipeNetV2 fruit-head probability to accept the recognised fruit without asking.
    /// A starting value, not tuned on field photos yet: testers can change it in the menu.
    static let defaultThreshold = 0.60
    static let thresholdChoices: [Double] = [0.40, 0.50, 0.60, 0.70, 0.80]
    /// Cut-off for Apple Vision scores (VisionFruitIdentifier), tuned on 200 RipeNet photos (see README).
    static let visionThreshold = 0.10

    let scores: [Fruit: Double]
    let verdict: IdentityVerdict
    /// Set only when `verdict == .looksLike`.
    let suggested: Fruit?

    static let unavailable = FruitIdentity(scores: [:], verdict: .unavailable, suggested: nil)

    /// Judges `scores` against the fruit the user picked.
    /// Match: the picked fruit reaches `threshold` and no other fruit scores higher.
    /// Otherwise the best other fruit at/above `threshold` is suggested, else the photo is unrecognised.
    static func assess(scores: [Fruit: Double], picked: Fruit, threshold: Double = defaultThreshold) -> FruitIdentity {
        let own = scores[picked] ?? 0
        let best = scores.filter { $0.key != picked }
            .max { ($0.value, $1.key.rawValue) < ($1.value, $0.key.rawValue) }

        if own >= threshold, own >= (best?.value ?? 0) {
            return FruitIdentity(scores: scores, verdict: .match, suggested: nil)
        }
        if let best, best.value >= threshold {
            return FruitIdentity(scores: scores, verdict: .looksLike, suggested: best.key)
        }
        return FruitIdentity(scores: scores, verdict: .unrecognized, suggested: nil)
    }

    /// Recognises the fruit with no user pick: the best-scoring fruit, confirmed when it reaches `threshold`.
    /// Below the threshold the verdict is `.unrecognized`, so the app asks the user to confirm.
    static func recognize(scores: [Fruit: Double], threshold: Double = defaultThreshold) -> (fruit: Fruit?, identity: FruitIdentity) {
        guard let best = scores.max(by: { ($0.value, $1.key.rawValue) < ($1.value, $0.key.rawValue) }) else {
            return (nil, .unavailable)
        }
        let verdict: IdentityVerdict = best.value >= threshold ? .match : .unrecognized
        return (best.key, FruitIdentity(scores: scores, verdict: verdict, suggested: nil))
    }

    /// Re-judges the same scores after the user switched fruit.
    func reassessed(for picked: Fruit, threshold: Double = defaultThreshold) -> FruitIdentity {
        guard verdict != .unavailable else { return self }
        return Self.assess(scores: scores, picked: picked, threshold: threshold)
    }

    /// Best score per supported fruit from Vision's (label, confidence) pairs.
    static func scores(from observations: [(label: String, confidence: Double)]) -> [Fruit: Double] {
        var result: [Fruit: Double] = [:]
        for fruit in Fruit.enabled {
            result[fruit] = observations.filter { fruit.visionLabels.contains($0.label) }.map(\.confidence).max() ?? 0
        }
        return result
    }
}

extension Fruit {
    /// Apple Vision taxonomy labels that mean this fruit (checked on RipeNet photos with VNClassifyImageRequest).
    var visionLabels: Set<String> {
        switch self {
        case .apple: ["apple"]
        case .banana: ["banana"]
        case .mango: ["mango"]
        case .orange: ["citrus_fruit", "oranges", "orange", "mandarine"]
        case .papaya: ["papaya"]
        case .pineapple: ["pineapple"]
        }
    }
}
