import CoreGraphics
import Foundation
import Testing
@testable import CekBuah

struct BasketTests {
    private let photo = UUID()

    private func result(_ state: RipenessState) -> ClassificationResult {
        ClassificationResult(state: state, confidence: 0.9,
                             ranked: [ClassPrediction(state: state, probability: 0.9)], isDemo: true)
    }

    private func shelfItem(_ number: Int, _ kind: ShelfFruit?, _ state: RipenessState?) -> BasketItem {
        BasketItem(source: .shelf(photoID: photo, number: number), kind: kind,
                   result: state.map(result), thumbnail: nil)
    }

    @Test func tappingTheSameBoxTwicePutsTheFruitBack() {
        var items: [BasketItem] = []
        #expect(BasketRules.toggle(shelfItem(3, .mango, .ripe), in: &items))
        #expect(items.count == 1)
        // A new BasketItem value for the same box still matches by source.
        #expect(!BasketRules.toggle(shelfItem(3, .mango, .ripe), in: &items))
        #expect(items.isEmpty)
    }

    @Test func differentBoxesAndPhotosAreDifferentFruits() {
        var items: [BasketItem] = []
        BasketRules.toggle(shelfItem(1, .banana, .ripe), in: &items)
        BasketRules.toggle(shelfItem(2, .banana, .ripe), in: &items)
        BasketRules.toggle(BasketItem(source: .shelf(photoID: UUID(), number: 1), kind: .banana,
                                      result: result(.ripe), thumbnail: nil), in: &items)
        #expect(items.count == 3)
    }

    @Test func groupsByKindThenRipeningOrder() {
        let items = [
            shelfItem(1, .papaya, .ripe), shelfItem(2, .banana, .overripe), shelfItem(3, .banana, .unripe),
            shelfItem(4, .banana, .unripe), shelfItem(5, nil, nil), shelfItem(6, .avocado, nil),
        ]
        let groups = BasketRules.groups(items)
        #expect(groups.map(\.kind) == [.avocado, .banana, .banana, .papaya, nil])
        #expect(groups[1] == BasketGroup(kind: .banana, state: .unripe, count: 2))
        #expect(groups[2].state == .overripe)
    }

    @Test func onlyKnownRipenessThatIsNotRottenIsStocked() {
        #expect(shelfItem(1, .banana, .ripe).canStock)
        #expect(!shelfItem(2, .banana, .rotten).canStock)
        #expect(!shelfItem(3, .banana, nil).canStock)       // ripeness not judged yet
        #expect(!shelfItem(4, .avocado, .ripe).canStock)    // no stock fruit for avocado yet
        #expect(!shelfItem(5, nil, .ripe).canStock)
    }

    @MainActor @Test func lateRipenessFillsAPickedFruit() {
        let basket = Basket()
        let source = BasketSource.shelf(photoID: photo, number: 7)
        basket.toggle(BasketItem(source: source, kind: .mango, result: nil, thumbnail: nil))
        basket.update(source, result: result(.unripe))
        #expect(basket.items.first?.state == .unripe)
        // An existing judgement is not overwritten.
        basket.update(source, result: result(.rotten))
        #expect(basket.items.first?.state == .unripe)
    }

    @MainActor @Test func undoRemovesTheLastLiveFruit() {
        let basket = Basket()
        basket.add(BasketItem(source: .live(UUID()), kind: .banana, result: result(.ripe), thumbnail: nil))
        basket.add(BasketItem(source: .live(UUID()), kind: .papaya, result: result(.unripe), thumbnail: nil))
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

    @Test func sameFruitNeedsSameKindAndOverlap() {
        #expect(LiveFruitPick.isSameFruit(candidate(0.4, 0.4, 0.8), candidate(0.42, 0.41, 0.7)))
        #expect(!LiveFruitPick.isSameFruit(candidate(0.4, 0.4, 0.8), candidate(0.42, 0.41, 0.7, "papaya")))
        #expect(!LiveFruitPick.isSameFruit(candidate(0.0, 0.0, 0.8), candidate(0.6, 0.6, 0.8)))
    }
}
