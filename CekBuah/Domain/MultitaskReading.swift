import Foundation

/// Raw outputs of `FruitMultitask.mlpackage` (ripeness-multitask/mtk/export.py): probabilities after temperature
/// scaling. `stage` is NOT masked yet: valid stages differ per species and come from the model's metadata.
struct MultitaskOutput: Sendable {
    let species: [Double]
    let stage: [Double]
    let damage: Double
}

/// Label order and valid stages, read from the model's metadata (stage_schema.json at export time).
struct MultitaskSchema: Sendable, Equatable {
    var speciesOrder = ["avocado", "banana", "dragon_fruit", "mango", "papaya", "other"]
    var validStages: [String: [Int]] = ["avocado": [0, 1, 2, 3, 4], "banana": [0, 1, 2, 3], "dragon_fruit": [],
                                        "mango": [0, 1, 2, 3], "papaya": [0, 1, 2], "other": []]

    /// Metadata values are JSON strings (coremltools user_defined_metadata).
    init(metadata: [String: String] = [:]) {
        if let order = Self.decode([String].self, metadata["species_order"]) { speciesOrder = order }
        if let valid = Self.decode([String: [Int]].self, metadata["valid_stages"]) { validStages = valid }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ text: String?) -> T? {
        text.flatMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }
}

/// What the app takes from one crop.
struct MultitaskReading: Sendable {
    /// Nil for "other" or when the species is below the threshold.
    let kind: ShelfFruit?
    let label: String
    let speciesConfidence: Double
    /// Shared stage index 0...4 after the species mask, nil when this species has no stage.
    let stageIndex: Int?
    let stageConfidence: Double
    let damage: Double
    /// Damage was only trained for dragon fruit, mango and papaya.
    let damageTrusted: Bool
    /// Ripeness for the app's states; nil when there is no kind.
    let result: ClassificationResult?

    var isOther: Bool { label == "other" }
}

/// Pure rules from model output to what the app shows. Thresholds are first guesses: the validation data
/// is easier than a market, so the species threshold is stricter than the notebook's suggestion (0.3).
enum MultitaskRules {
    static let speciesThreshold = 0.7
    static let damageThreshold = 0.5
    static let damageTrusted: Set<ShelfFruit> = [.dragonFruit, .mango, .papaya]
    static let modelName = "FruitMultitask"
    /// Shared scale names (stage_schema.json "scale"), shown in tester mode.
    static let stageNames = ["mentah", "mulai matang", "siap makan", "habiskan segera", "lewat"]

    /// Shared stage -> app state. The app has no "mulai matang" state yet, so stage 1 shows as mentah;
    /// stage 4 ("lewat": avocado senescence with mould spots) shows as busuk.
    static func state(forStage stage: Int) -> RipenessState {
        switch stage {
        case 0, 1: .unripe
        case 2: .ripe
        case 3: .overripe
        default: .rotten
        }
    }

    static func read(_ output: MultitaskOutput, schema: MultitaskSchema) -> MultitaskReading {
        let best = output.species.indices.max { output.species[$0] < output.species[$1] } ?? 0
        let label = best < schema.speciesOrder.count ? schema.speciesOrder[best] : "?"
        let confidence = output.species.indices.contains(best) ? output.species[best] : 0
        let kind = confidence >= speciesThreshold ? ShelfFruit(detectorLabel: label) : nil
        let trusted = kind.map(damageTrusted.contains) ?? false

        guard let kind else {
            return MultitaskReading(kind: nil, label: label, speciesConfidence: confidence, stageIndex: nil,
                                    stageConfidence: 0, damage: output.damage, damageTrusted: false, result: nil)
        }

        // Stage probabilities renormalised over this species' valid stages.
        let valid = schema.validStages[label] ?? []
        let total = valid.reduce(0.0) { $0 + (output.stage.indices.contains($1) ? output.stage[$1] : 0) }
        var stageIndex: Int?
        var stageConfidence = 0.0
        var result: ClassificationResult?
        if !valid.isEmpty, total > 0 {
            var byState: [RipenessState: Double] = [:]
            for s in valid where output.stage.indices.contains(s) {
                byState[state(forStage: s), default: 0] += output.stage[s] / total
            }
            let top = valid.max { output.stage[$0] < output.stage[$1] }
            stageIndex = top
            stageConfidence = top.map { output.stage[$0] / total } ?? 0
            // The state follows the top STAGE (summing stages 0 and 1 into "mentah" must not outvote stage 2).
            // Its confidence is the share of all stages mapped to that state; below 50% the app says unsure.
            if let top {
                let state = state(forStage: top)
                let confidence = byState[state] ?? 0
                result = ClassificationResult(
                    state: confidence >= DecisionRules.standard.minTopConfidence ? state : .unsure,
                    confidence: confidence,
                    ranked: DecisionRules.rank(byState.map { ClassPrediction(state: $0.key, probability: $0.value) }),
                    isDemo: false)
            }
        } else if trusted {
            // No ripening track (dragon fruit): fresh unless the damage head says otherwise.
            result = DecisionRules.standard.evaluate([ClassPrediction(state: .ripe, probability: 1 - output.damage),
                                                      ClassPrediction(state: .rotten, probability: output.damage)])
        }
        // Visible damage overrides the stage, for species whose damage head was trained.
        if trusted, output.damage >= damageThreshold {
            result = ClassificationResult(state: .rotten, confidence: output.damage,
                                          ranked: [ClassPrediction(state: .rotten, probability: output.damage)], isDemo: false)
        }
        result?.modelName = modelName
        return MultitaskReading(kind: kind, label: label, speciesConfidence: confidence, stageIndex: stageIndex,
                                stageConfidence: stageConfidence, damage: output.damage, damageTrusted: trusted,
                                result: result)
    }
}
