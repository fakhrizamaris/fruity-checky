import CoreGraphics
import Foundation
import Testing
@testable import CekBuah

struct BasketTests {
    private func result(_ state: RipenessState) -> ClassificationResult {
        ClassificationResult(state: state, confidence: 0.9,
                             ranked: [ClassPrediction(state: state, probability: 0.9)], isDemo: true)
    }

    private func item(_ kind: ShelfFruit?, _ state: RipenessState?) -> BasketItem {
        BasketItem(source: .live(UUID()), kind: kind, result: state.map(result), thumbnail: nil)
    }

    @Test func groupsByKindThenRipeningOrder() {
        let items = [
            item(.papaya, .ripe), item(.banana, .overripe), item(.banana, .unripe),
            item(.banana, .unripe), item(nil, nil), item(.avocado, nil),
        ]
        let groups = BasketRules.groups(items)
        #expect(groups.map(\.kind) == [.avocado, .banana, .banana, .papaya, nil])
        #expect(groups[1] == BasketGroup(kind: .banana, state: .unripe, count: 2))
        #expect(groups[2].state == .overripe)
    }

    @Test func onlyKnownRipenessThatIsNotRottenIsStocked() {
        #expect(item(.banana, .ripe).canStock)
        #expect(!item(.banana, .rotten).canStock)
        #expect(!item(.banana, nil).canStock)       // ripeness not judged
        #expect(!item(.avocado, .ripe).canStock)    // no stock fruit for avocado yet
        #expect(!item(nil, .ripe).canStock)
    }

    @MainActor @Test func sameLiveScanIsNotAddedTwice() {
        let basket = Basket()
        let scan = BasketItem(source: .live(UUID()), kind: .mango, result: result(.ripe), thumbnail: nil)
        basket.add(scan)
        basket.add(scan)
        #expect(basket.count == 1)
    }

    @MainActor @Test func undoRemovesTheLastLiveFruit() {
        let basket = Basket()
        basket.add(item(.banana, .ripe))
        basket.add(item(.papaya, .unripe))
        #expect(basket.removeLast()?.kind == .papaya)
        #expect(basket.count == 1)
    }
}

struct LiveFruitPickTests {
    private func candidate(_ x: CGFloat, _ y: CGFloat, _ confidence: Double, _ label: String = "mango") -> ShelfCandidate {
        ShelfCandidate(box: CGRect(x: x, y: y, width: 0.2, height: 0.2), label: label, confidence: confidence)
    }

    @Test func centreFruitBeatsAMoreConfidentEdgeFruit() {
        let centre = candidate(0.4, 0.4, 0.7)
        let edge = candidate(0.0, 0.0, 0.9)
        #expect(LiveFruitPick.best([edge, centre]) == centre)
    }

    @Test func lowConfidenceIsIgnored() {
        #expect(LiveFruitPick.best([candidate(0.4, 0.4, 0.3)]) == nil)
    }

    @Test func largeBoxAtTheEdgeIsTooClose() {
        #expect(LiveFruitPick.isTooClose(CGRect(x: 0, y: 0.1, width: 0.8, height: 0.8)))
        #expect(!LiveFruitPick.isTooClose(CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)))   // big but inside
        #expect(!LiveFruitPick.isTooClose(CGRect(x: 0, y: 0.4, width: 0.2, height: 0.2)))        // small fruit at the edge
    }

    @Test func sameFruitNeedsSameKindAndOverlap() {
        #expect(LiveFruitPick.isSameFruit(candidate(0.4, 0.4, 0.8), candidate(0.42, 0.41, 0.7)))
        #expect(!LiveFruitPick.isSameFruit(candidate(0.4, 0.4, 0.8), candidate(0.42, 0.41, 0.7, "papaya")))
        #expect(!LiveFruitPick.isSameFruit(candidate(0.0, 0.0, 0.8), candidate(0.6, 0.6, 0.8)))
    }
}
