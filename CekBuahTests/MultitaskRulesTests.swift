import Testing
@testable import CekBuah

struct MultitaskRulesTests {
    private let schema = MultitaskSchema()

    /// species order: avocado, banana, dragon_fruit, mango, papaya, other
    private func output(species: Int, _ p: Double = 0.9, stage: [Double] = [0.1, 0.1, 0.6, 0.1, 0.1],
                        damage: Double = 0.05) -> MultitaskOutput {
        var s = Array(repeating: (1 - p) / 5, count: 6)
        s[species] = p
        return MultitaskOutput(species: s, stage: stage, damage: damage)
    }

    @Test func confidentSpeciesWithStage() {
        let reading = MultitaskRules.read(output(species: 3), schema: schema)
        #expect(reading.kind == .mango)
        #expect(reading.stageIndex == 2)
        #expect(reading.result?.state == .ripe)
        #expect(reading.result?.modelName == "FruitMultitask")
    }

    @Test func lowSpeciesConfidenceGivesNoKind() {
        let reading = MultitaskRules.read(output(species: 3, 0.5), schema: schema)
        #expect(reading.kind == nil)
        #expect(reading.result == nil)
    }

    @Test func otherIsNotAKind() {
        let reading = MultitaskRules.read(output(species: 5), schema: schema)
        #expect(reading.kind == nil && reading.isOther)
    }

    @Test func stagesOutsideTheSpeciesAreMaskedOut() {
        // Papaya has stages 0...2 only; the raw top stage 4 must not win.
        let reading = MultitaskRules.read(output(species: 4, stage: [0.05, 0.25, 0.1, 0.0, 0.6]), schema: schema)
        #expect(reading.stageIndex == 1)
        #expect(reading.result?.state == .unripe)
        #expect(abs(reading.stageConfidence - 0.25 / 0.4) < 1e-9)
    }

    @Test func stateFollowsTheTopStageNotTheSummedState() {
        // Regression (21 Oct 2026): stages 0 + 1 (both "mentah") = 0.55 outvoted stage 2 = 0.45.
        let reading = MultitaskRules.read(output(species: 1, stage: [0.3, 0.25, 0.45, 0.0, 0.0]), schema: schema)
        #expect(reading.stageIndex == 2)
        #expect(reading.result?.state == .unsure) // top stage "matang" holds only 45%: not sure enough
        let clear = MultitaskRules.read(output(species: 1, stage: [0.2, 0.2, 0.6, 0.0, 0.0]), schema: schema)
        #expect(clear.result?.state == .ripe)
    }

    @Test func damageOverridesStageOnlyForTrainedSpecies() {
        let mango = MultitaskRules.read(output(species: 3, damage: 0.8), schema: schema)
        #expect(mango.result?.state == .rotten)
        let banana = MultitaskRules.read(output(species: 1, damage: 0.8), schema: schema)
        #expect(banana.result?.state == .ripe)
        #expect(!banana.damageTrusted)
    }

    @Test func dragonFruitFreshnessComesFromDamage() {
        #expect(MultitaskRules.read(output(species: 2, damage: 0.1), schema: schema).result?.state == .ripe)
        #expect(MultitaskRules.read(output(species: 2, damage: 0.9), schema: schema).result?.state == .rotten)
    }

    @Test func schemaReadsModelMetadata() {
        let custom = MultitaskSchema(metadata: ["species_order": #"["mango","other"]"#,
                                                "valid_stages": #"{"mango":[0,1],"other":[]}"#])
        #expect(custom.speciesOrder == ["mango", "other"])
        #expect(custom.validStages["mango"] == [0, 1])
    }
}
