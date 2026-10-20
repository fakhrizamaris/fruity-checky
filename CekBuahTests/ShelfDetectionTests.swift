import CoreGraphics
import Testing
@testable import CekBuah

struct ShelfDetectionTests {
    private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 0.1, _ h: CGFloat = 0.1) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    @Test func intersectionOverUnion() {
        #expect(ShelfPostProcessing.intersectionOverUnion(box(0, 0), box(0, 0)) == 1)
        #expect(ShelfPostProcessing.intersectionOverUnion(box(0, 0), box(0.5, 0.5)) == 0)
        // Half overlap: 0.005 / (0.01 + 0.01 - 0.005) = 1/3
        #expect(abs(ShelfPostProcessing.intersectionOverUnion(box(0, 0), box(0.05, 0)) - 1.0 / 3) < 1e-9)
    }

    @Test func suppressionKeepsBestAcrossLabels() {
        let candidates = [
            ShelfCandidate(box: box(0.1, 0.1), label: "mango", confidence: 0.6),
            ShelfCandidate(box: box(0.11, 0.1), label: "papaya", confidence: 0.9), // same fruit, other label
            ShelfCandidate(box: box(0.5, 0.5), label: "mango", confidence: 0.7),
        ]
        let kept = ShelfPostProcessing.suppress(candidates, iouThreshold: 0.5)
        #expect(kept.map(\.label) == ["papaya", "mango"])
    }

    @Test func readingOrderIsRowsThenLeftToRight() {
        // Second row is slightly crooked; still read left to right.
        let boxes = [box(0.6, 0.52), box(0.1, 0.1), box(0.2, 0.5), box(0.5, 0.12), box(0.3, 0.08)]
        #expect(ShelfPostProcessing.readingOrder(boxes) == [1, 4, 3, 2, 0])
    }

    @Test func finalizeFiltersNumbersAndMapsLabels() {
        let candidates = [
            ShelfCandidate(box: box(0.5, 0.1), label: "dragon_fruit", confidence: 0.8),
            ShelfCandidate(box: box(0.1, 0.1), label: "Mango", confidence: 0.9),
            ShelfCandidate(box: box(0.3, 0.1), label: "mango", confidence: 0.2), // below threshold
            ShelfCandidate(box: box(0.1, 0.6), label: "apple", confidence: 0.9), // unknown kind
        ]
        let detections = ShelfPostProcessing.finalize(candidates, minConfidence: 0.4)
        #expect(detections.map(\.number) == [1, 2, 3])
        #expect(detections.map(\.fruit) == [.mango, .dragonFruit, nil])
    }

    @Test func countsMostCommonFirstUnknownLast() {
        let detections = [
            ShelfDetection(number: 1, box: box(0, 0), fruit: nil, confidence: 1),
            ShelfDetection(number: 2, box: box(0, 0), fruit: .banana, confidence: 1),
            ShelfDetection(number: 3, box: box(0, 0), fruit: .mango, confidence: 1),
            ShelfDetection(number: 4, box: box(0, 0), fruit: .mango, confidence: 1),
            ShelfDetection(number: 5, box: box(0, 0), fruit: nil, confidence: 1),
            ShelfDetection(number: 6, box: box(0, 0), fruit: nil, confidence: 1),
        ]
        let counts = ShelfPostProcessing.counts(detections)
        #expect(counts.map(\.fruit) == [.mango, .banana, nil])
        #expect(counts.map(\.count) == [2, 1, 3])
    }

    @Test func detectorLabelsMatchPipeline() {
        // Labels written by shelf-detection/pipeline/common.py (FRUITS).
        let pipelineLabels = ["avocado", "banana", "dragon_fruit", "mango", "papaya"]
        #expect(pipelineLabels.compactMap(ShelfFruit.init(detectorLabel:)) == ShelfFruit.allCases)
        #expect(ShelfFruit(detectorLabel: "Dragon Fruit") == .dragonFruit)
        #expect(ShelfFruit(detectorLabel: "apple") == nil)
    }

    @Test func onlySupportedKindsHaveRipenessModel() {
        #expect(ShelfFruit.allCases.filter { $0.ripenessFruit != nil } == [.banana, .mango, .papaya])
    }
}
