import Testing
@testable import CekBuah

struct DecisionRulesTests {
    private let rules = DecisionRules.standard

    private func predictions(_ values: [(RipenessState, Double)]) -> [ClassPrediction] {
        values.map { ClassPrediction(state: $0.0, probability: $0.1) }
    }

    @Test func confidentResultKeepsTopClass() {
        let result = rules.evaluate(predictions([(.ripe, 0.85), (.overripe, 0.10), (.unripe, 0.05)]))
        #expect(result.state == .ripe)
        #expect(result.confidence == 0.85)
        #expect(result.topTwo.map(\.state) == [.ripe, .overripe])
    }

    @Test func majorityAboveFiftyPercentIsShown() {
        // 65% is below the old 70% threshold but is a clear majority now.
        let result = rules.evaluate(predictions([(.ripe, 0.65), (.overripe, 0.20), (.unripe, 0.15)]))
        #expect(result.state == .ripe)
    }

    @Test func exactlyFiftyPercentIsShown() {
        let result = rules.evaluate(predictions([(.rotten, 0.50), (.overripe, 0.30), (.ripe, 0.20)]))
        #expect(result.state == .rotten)
    }

    @Test func noMajorityIsUnsure() {
        let result = rules.evaluate(predictions([(.ripe, 0.45), (.overripe, 0.35), (.unripe, 0.20)]))
        #expect(result.state == .unsure)
        #expect(result.confidence == 0.45) // confidence still reported
        #expect(result.topTwo.first?.state == .ripe) // best guess kept
    }

    // Case C: exact tie at 50% -> later ripening stage wins, physical check offered.
    @Test func exactTieChoosesLaterStage() {
        let result = rules.evaluate(predictions([(.ripe, 0.5), (.overripe, 0.5)]))
        #expect(result.state == .overripe)
        #expect(result.isTie)
        #expect(DecisionRules.offersPhysicalCheck(for: result, fruit: .banana))
    }

    @Test func tieIsDeterministicRegardlessOfInputOrder() {
        let a = rules.evaluate(predictions([(.rotten, 0.5), (.unripe, 0.5)]))
        let b = rules.evaluate(predictions([(.unripe, 0.5), (.rotten, 0.5)]))
        #expect(a.state == .rotten) // non-adjacent tie: safest (latest) stage
        #expect(b.state == .rotten)
    }

    // Case B: looks like 50/50 when rounded, but one class is ahead.
    @Test func nearTiePicksHigherAndShowsDecimals() {
        let result = rules.evaluate(predictions([(.overripe, 0.496), (.ripe, 0.504)]))
        #expect(result.state == .ripe)
        #expect(!result.isTie)
        #expect(result.topTwo.map(\.percentText) == ["50,4 persen", "49,6 persen"])
    }

    @Test func tieBelowMajorityIsUnsure() {
        let result = rules.evaluate(predictions([(.ripe, 0.4), (.overripe, 0.4), (.unripe, 0.2)]))
        #expect(result.state == .unsure)
        #expect(result.topTwo.first?.state == .overripe)
    }

    @Test func customMarginStillWorks() {
        // Teams can tighten the rule again from validation data.
        let rules = DecisionRules(minTopConfidence: 0.5, minMargin: 0.2)
        let result = rules.evaluate(predictions([(.ripe, 0.55), (.overripe, 0.40), (.unripe, 0.05)]))
        #expect(result.state == .unsure)
    }

    @Test func unsortedInputIsRanked() {
        let result = rules.evaluate(predictions([(.unripe, 0.05), (.rotten, 0.90), (.ripe, 0.05)]))
        #expect(result.state == .rotten)
        #expect(result.topTwo.first?.state == .rotten)
    }

    @Test func singleClassUsesZeroAsSecond() {
        let result = rules.evaluate(predictions([(.ripe, 0.9)]))
        #expect(result.state == .ripe)
    }

    @Test func emptyInputIsUnsure() {
        let result = rules.evaluate([])
        #expect(result.state == .unsure)
        #expect(result.confidence == 0)
    }

    @Test func mangoAlwaysOffersPhysicalCheck() {
        let confident = rules.evaluate(predictions([(.ripe, 0.95), (.overripe, 0.05)]))
        #expect(DecisionRules.offersPhysicalCheck(for: confident, fruit: .mango))
        #expect(DecisionRules.offersPhysicalCheck(for: confident, fruit: .orange))
        #expect(DecisionRules.offersPhysicalCheck(for: confident, fruit: .pineapple))
        #expect(!DecisionRules.offersPhysicalCheck(for: confident, fruit: .banana))
        #expect(!DecisionRules.offersPhysicalCheck(for: confident, fruit: .papaya))
    }

    @Test func unsureOffersPhysicalCheck() {
        let unsure = rules.evaluate(predictions([(.ripe, 0.45), (.overripe, 0.35), (.unripe, 0.2)]))
        #expect(unsure.state == .unsure)
        #expect(DecisionRules.offersPhysicalCheck(for: unsure, fruit: .banana))
    }

    @Test func confidenceTextIsRounded() {
        let result = rules.evaluate(predictions([(.ripe, 0.824), (.overripe, 0.1)]))
        #expect(result.confidenceText == "Keyakinan 82%")
    }

    @Test func unsureTextPointsToPhysicalCheck() {
        let result = rules.evaluate(predictions([(.ripe, 0.45), (.overripe, 0.35), (.unripe, 0.2)]))
        #expect(result.confidenceText == "Hasil foto belum meyakinkan. Lanjutkan dengan cek fisik.")
    }
}

struct LabelMappingTests {
    @Test(arguments: [
        ("mentah", RipenessState.unripe), ("unripe", .unripe), ("Unripe", .unripe),
        ("matang", .ripe), ("ripe", .ripe), ("Fresh", .ripe),
        ("terlalu_matang", .overripe), ("overripe", .overripe), ("Overipe", .overripe),
        ("busuk", .rotten), ("rotten", .rotten),
    ])
    func knownLabels(label: String, expected: RipenessState) {
        #expect(RipenessState(modelLabel: label) == expected)
    }

    @Test func unknownLabelIsNil() {
        #expect(RipenessState(modelLabel: "half-ripe") == nil)
        #expect(RipenessState(modelLabel: "tidak_yakin") == nil) // never a model class
    }

    @Test func probabilitiesPassThrough() {
        let output = CoreMLClassifier.normalize([("matang", 0.7), ("mentah", 0.2), ("busuk", 0.1)])
        #expect(output.first { $0.state == .ripe }?.probability == 0.7)
    }

    @Test func logitsAreSoftmaxed() {
        let output = CoreMLClassifier.normalize([("matang", 4.0), ("mentah", 1.0), ("busuk", -2.0)])
        let sum = output.map(\.probability).reduce(0, +)
        #expect(abs(sum - 1) < 1e-9)
        #expect(output.allSatisfy { (0...1).contains($0.probability) })
        #expect(output.max { $0.probability < $1.probability }?.state == .ripe)
    }

    @Test func unknownModelLabelsAreDropped() {
        let output = CoreMLClassifier.normalize([("matang", 0.6), ("setengah_matang", 0.4)])
        #expect(output.map(\.state) == [.ripe])
    }
}

struct PhysicalCheckSummaryTests {
    private let steps = [
        CheckStep(id: "a", instruction: "", options: [
            CheckOption(id: "hard", label: "", suggests: "mentah"),
            CheckOption(id: "soft", label: "", suggests: "matang"),
        ]),
        CheckStep(id: "b", instruction: "", options: [
            CheckOption(id: "green", label: "", suggests: "mentah"),
            CheckOption(id: "none", label: "", suggests: nil),
        ]),
    ]

    @Test func majorityWins() {
        #expect(PhysicalCheckSummary.suggestion(steps: steps, answers: ["a": "hard", "b": "green"]) == .unripe)
    }

    @Test func tieIsMixed() {
        let steps = steps + [CheckStep(id: "c", instruction: "", options: [
            CheckOption(id: "ripe", label: "", suggests: "matang"),
        ])]
        #expect(PhysicalCheckSummary.suggestion(steps: steps, answers: ["a": "hard", "c": "ripe"]) == nil)
    }

    @Test func neutralAnswersDoNotVote() {
        #expect(PhysicalCheckSummary.suggestion(steps: steps, answers: ["a": "soft", "b": "none"]) == .ripe)
    }
}

struct CSVExporterTests {
    @Test func escapesSpecialCharacters() {
        #expect(CSVExporter.escape("a,b") == "\"a,b\"")
        #expect(CSVExporter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExporter.escape("plain") == "plain")
    }
}
