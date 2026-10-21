import CoreGraphics
import Testing
@testable import CekBuah

struct LiveScanAccumulatorTests {
    private let box = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

    private func result(_ state: RipenessState, _ confidence: Double = 0.8) -> ClassificationResult {
        ClassificationResult(state: state, confidence: confidence,
                             ranked: [ClassPrediction(state: state, probability: confidence)], isDemo: true)
    }

    private func observation(_ frame: Int, _ kind: ShelfFruit, _ confidence: Double = 0.9,
                             _ state: RipenessState? = .ripe, box: CGRect? = nil) -> LiveObservation {
        LiveObservation(frame: frame, kind: kind, kindConfidence: confidence, box: box ?? self.box,
                        result: state.map { result($0) })
    }

    @Test func noVerdictBeforeEnoughFrames() {
        var acc = LiveScanAccumulator()
        for i in 0..<(LiveScanAccumulator.framesNeeded - 1) { acc.add(observation(i, .mango)) }
        #expect(acc.verdict() == nil)
        #expect(acc.progress < 1)
        acc.add(observation(99, .mango))
        #expect(acc.verdict()?.kind == .mango)
        #expect(acc.progress == 1)
    }

    @Test func disagreeingFramesBlockTheVerdict() {
        var acc = LiveScanAccumulator()
        // 6 mango + 4 papaya: 60% agreement, below the 70% needed.
        for i in 0..<6 { acc.add(observation(i, .mango)) }
        for i in 6..<10 { acc.add(observation(i, .papaya)) }
        #expect(acc.verdict() == nil)
    }

    @Test func lowConfidenceBlocksTheVerdict() {
        var acc = LiveScanAccumulator()
        for i in 0..<8 { acc.add(observation(i, .banana, 0.4)) }
        #expect(acc.verdict() == nil)
    }

    @Test func ripenessIsTheMostCommonStateOverTheSides() {
        var acc = LiveScanAccumulator()
        let states: [RipenessState] = [.unripe, .ripe, .ripe, .ripe, .unripe, .ripe]
        for (i, state) in states.enumerated() { acc.add(observation(i, .papaya, 0.9, state)) }
        #expect(acc.verdict()?.result?.state == .ripe)
    }

    @Test func kindWithoutRipenessModelStillGetsAVerdict() {
        var acc = LiveScanAccumulator()
        for i in 0..<6 { acc.add(observation(i, .avocado, 0.9, nil)) }
        let verdict = acc.verdict()
        #expect(verdict?.kind == .avocado)
        #expect(verdict?.result == nil)
    }

    @Test func aDifferentFruitStartsOver() {
        var acc = LiveScanAccumulator()
        for i in 0..<5 { acc.add(observation(i, .mango)) }
        // Box jumps to the other side: another fruit was put in front of the camera.
        acc.add(observation(5, .mango, box: CGRect(x: 0.85, y: 0.85, width: 0.1, height: 0.1)))
        #expect(acc.observations.count == 1)
        #expect(acc.verdict() == nil)
    }

    @Test func bestFrameIsTheMostConfident() {
        var acc = LiveScanAccumulator()
        for i in 0..<6 { acc.add(observation(i, .banana, i == 3 ? 0.99 : 0.8)) }
        #expect(acc.verdict()?.bestFrame == 3)
    }
}
