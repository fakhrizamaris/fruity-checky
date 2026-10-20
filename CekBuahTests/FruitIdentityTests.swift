import CoreGraphics
import Foundation
import Testing
@testable import CekBuah

struct FruitIdentityTests {
    private func scores(_ pairs: [Fruit: Double]) -> [Fruit: Double] {
        var all = Dictionary(uniqueKeysWithValues: Fruit.enabled.map { ($0, 0.0) })
        all.merge(pairs) { _, new in new }
        return all
    }

    @Test func matchWhenPickedFruitIsRecognised() {
        let identity = FruitIdentity.assess(scores: scores([.banana: 0.9]), picked: .banana)
        #expect(identity.verdict == .match)
        #expect(identity.suggested == nil)
    }

    @Test func warnsWhenAnotherFruitIsRecognised() {
        let identity = FruitIdentity.assess(scores: scores([.papaya: 0.8, .banana: 0.02]), picked: .banana)
        #expect(identity.verdict == .looksLike)
        #expect(identity.suggested == .papaya)
    }

    @Test func otherFruitWinsWhenBothPassThreshold() {
        let identity = FruitIdentity.assess(scores: scores([.banana: 0.2, .mango: 0.6]), picked: .banana)
        #expect(identity.verdict == .looksLike)
        #expect(identity.suggested == .mango)
    }

    @Test func pickedFruitWinsWhenItScoresHigher() {
        let identity = FruitIdentity.assess(scores: scores([.banana: 0.6, .mango: 0.3]), picked: .banana)
        #expect(identity.verdict == .match)
    }

    @Test func unrecognisedWhenNothingReachesThreshold() {
        let identity = FruitIdentity.assess(scores: scores([.banana: 0.05, .mango: 0.04]), picked: .banana, threshold: 0.1)
        #expect(identity.verdict == .unrecognized)
        #expect(identity.suggested == nil)
    }

    @Test func thresholdIsTunable() {
        let low = FruitIdentity.assess(scores: scores([.banana: 0.15]), picked: .banana, threshold: 0.1)
        let high = FruitIdentity.assess(scores: scores([.banana: 0.15]), picked: .banana, threshold: 0.3)
        #expect(low.verdict == .match)
        #expect(high.verdict == .unrecognized)
    }

    @Test func reassessingAfterSwitchMatchesNewFruit() {
        let first = FruitIdentity.assess(scores: scores([.papaya: 0.8]), picked: .banana)
        #expect(first.reassessed(for: .papaya).verdict == .match)
        #expect(FruitIdentity.unavailable.reassessed(for: .papaya).verdict == .unavailable)
    }

    @Test func visionLabelsMapToSupportedFruits() {
        let mapped = FruitIdentity.scores(from: [
            (label: "food", confidence: 0.9), (label: "oranges", confidence: 0.6),
            (label: "citrus_fruit", confidence: 0.7), (label: "pineapple", confidence: 0.4),
        ])
        #expect(mapped[.orange] == 0.7)
        #expect(mapped[.pineapple] == 0.4)
        #expect(mapped[.banana] == 0)
        #expect(mapped.count == Fruit.enabled.count)
    }
}

struct IdentityFlowTests {
    private struct FakeIdentifier: FruitIdentifying {
        let result: [Fruit: Double]?
        func scores(for image: CGImage) async throws -> [Fruit: Double] {
            guard let result else { throw CocoaError(.featureUnsupported) }
            return result
        }
    }

    /// Fixed answer, so the test does not depend on the mock's randomness.
    private struct FixedClassifier: FruitClassifying {
        func classify(image: CGImage, fruit: Fruit) async throws -> ClassificationResult {
            DecisionRules.standard.evaluate([
                ClassPrediction(state: .ripe, probability: 0.8),
                ClassPrediction(state: .unripe, probability: 0.15),
                ClassPrediction(state: .rotten, probability: 0.05),
            ], isDemo: true)
        }
    }

    private func image() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }

    private func analyzer(_ scores: [Fruit: Double]?) -> FruitAnalyzer {
        FruitAnalyzer(detector: ForegroundFruitDetector(), classifier: FixedClassifier(),
                      identifier: FakeIdentifier(result: scores))
    }

    @Test func mismatchProducesNoticeAndKeepsRipenessResult() async throws {
        let items = try await analyzer([.papaya: 0.9]).analyze(image: image(), fruit: .banana)
        let item = try #require(items.first)
        #expect(item.identity.suggested == .papaya)
        #expect(item.needsIdentityNotice)
        #expect(item.fruit == .banana)
        #expect(item.result.state == .ripe)
    }

    @Test func identifierFailureNeverBlocksAnalysis() async throws {
        let items = try await analyzer(nil).analyze(image: image(), fruit: .banana)
        let item = try #require(items.first)
        #expect(item.identity.verdict == .unavailable)
        #expect(!item.needsIdentityNotice)
    }

    @Test func reclassifySwitchesFruitAndClearsNotice() async throws {
        let analyzer = analyzer([.papaya: 0.9])
        let picture = try image()
        let item = try #require(try await analyzer.analyze(image: picture, fruit: .banana).first)
        let switched = try await analyzer.reclassify(item, as: .papaya, in: picture)
        #expect(switched.fruit == .papaya)
        #expect(switched.pickedFruit == .banana)
        #expect(switched.identityAction == .switched)
        #expect(switched.identity.verdict == .match)
        #expect(!switched.needsIdentityNotice)
    }

    @Test func csvIncludesIdentityColumns() throws {
        let identity = FruitIdentity.assess(scores: [.papaya: 0.8, .banana: 0.01], picked: .banana)
        let result = DecisionRules.standard.evaluate([ClassPrediction(state: .ripe, probability: 0.9),
                                                      ClassPrediction(state: .unripe, probability: 0.1)], isDemo: true)
        let entry = LogEntry(fruit: .papaya, result: result, latencyMs: 10, photoData: nil,
                             identity: identity, pickedFruit: .banana, identityAction: .switched)
        let csv = CSVExporter.csv(from: [LogRow(entry)])
        let lines = csv.split(separator: "\n")
        #expect(lines[0].hasSuffix("buah_dipilih,cek_jenis,saran_buah,skor_buah_dipilih,skor_saran,tindakan_penguji,model"))
        #expect(lines[1].hasSuffix("banana,looksLike,papaya,0.010,0.800,switched,"))
    }
}

struct AutoRecognitionTests {
    private struct FakeIdentifier: FruitIdentifying {
        let result: [Fruit: Double]
        func scores(for image: CGImage) async throws -> [Fruit: Double] { result }
    }

    private struct EchoClassifier: FruitClassifying {
        func classify(image: CGImage, fruit: Fruit) async throws -> ClassificationResult {
            DecisionRules.standard.evaluate([ClassPrediction(state: .ripe, probability: 0.9),
                                             ClassPrediction(state: .unripe, probability: 0.1)], isDemo: true)
        }
    }

    private func image(width: Int = 300, height: Int = 400) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }

    @Test func confidentFruitIsAcceptedWithoutAsking() {
        let recognition = FruitIdentity.recognize(scores: [.apple: 0.85, .banana: 0.1], threshold: 0.6)
        #expect(recognition.fruit == .apple)
        #expect(recognition.identity.verdict == .match)
    }

    @Test func unsureFruitAsksForConfirmation() {
        let recognition = FruitIdentity.recognize(scores: [.mango: 0.45, .papaya: 0.4], threshold: 0.6)
        #expect(recognition.fruit == .mango)
        #expect(recognition.identity.verdict == .unrecognized)
    }

    @Test func noScoresMeansUnavailable() {
        let recognition = FruitIdentity.recognize(scores: [:])
        #expect(recognition.fruit == nil)
        #expect(recognition.identity.verdict == .unavailable)
    }

    @Test func singlePhotoUsesRecognisedFruitAndCentreSquare() async throws {
        let analyzer = FruitAnalyzer(classifier: EchoClassifier(), identifier: FakeIdentifier(result: [.orange: 0.9]))
        let item = try await analyzer.analyzeSingle(image: image())
        #expect(item.fruit == .orange)
        #expect(!item.needsIdentityNotice)
        #expect(abs(item.box.width - 1) < 0.001)
        #expect(abs(item.box.height - 0.75) < 0.001)
        #expect(abs(item.box.minY - 0.125) < 0.001)
    }

    @Test func singlePhotoAsksWhenUnsure() async throws {
        let analyzer = FruitAnalyzer(classifier: EchoClassifier(), identifier: FakeIdentifier(result: [.papaya: 0.4, .mango: 0.35]))
        let item = try await analyzer.analyzeSingle(image: image())
        #expect(item.fruit == .papaya)
        #expect(item.needsIdentityNotice)
    }
}
