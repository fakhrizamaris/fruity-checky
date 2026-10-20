import Foundation
import Testing
@testable import CekBuah

struct ShelfLifeTests {
    private let banana = ShelfLife(days: ["mentah": 6, "matang": 3, "busuk": 0], source: "test")

    @Test func estimateIsProbabilityWeighted() {
        let estimate = banana.estimateDaysLeft(from: [
            ClassPrediction(state: .unripe, probability: 0.7),
            ClassPrediction(state: .ripe, probability: 0.3),
            ClassPrediction(state: .rotten, probability: 0.0),
        ])
        #expect(abs((estimate ?? 0) - 5.1) < 1e-9)
    }

    @Test func statesWithoutTableValueAreReweighted() {
        // "terlalu matang" is not in the RipeNet table, so only mentah/matang count.
        let estimate = banana.estimateDaysLeft(from: [
            ClassPrediction(state: .overripe, probability: 0.5),
            ClassPrediction(state: .ripe, probability: 0.5),
        ])
        #expect(estimate == 3)
    }

    @Test func manualDefaults() {
        #expect(banana.defaultDaysLeft(for: .unripe) == 6)
        #expect(banana.defaultDaysLeft(for: .overripe) == 1.5)
        #expect(banana.readyWithinDays == 3)
    }

    @Test(arguments: Fruit.allCases)
    func everyFruitHasShelfLife(fruit: Fruit) throws {
        let kb = try KnowledgeBase.load()
        let table = try #require(kb.knowledge(for: fruit)?.shelfLife)
        #expect(table.days(for: .unripe) != nil && table.days(for: .ripe) != nil)
    }

    @Test func daysText() {
        #expect(DaysText.remaining(5.4) == "±5 hari lagi")
        #expect(DaysText.remaining(0.2) == "hari ini")
        #expect(DaysText.remaining(-1.2) == "lewat 1 hari")
    }
}

struct StockQueueTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func entry(_ fruit: Fruit, daysLeft: Double, ready: Double = 3) -> QueueEntry {
        QueueEntry(id: UUID(), fruit: fruit, daysLeftAtEstimate: daysLeft, estimatedAt: start, readyWithinDays: ready)
    }

    @Test func statusFollowsDaysLeft() {
        #expect(entry(.banana, daysLeft: 6).status(at: start) == .waiting)
        #expect(entry(.banana, daysLeft: 3).status(at: start) == .ready)
        #expect(entry(.banana, daysLeft: 0).status(at: start) == .overdue)
    }

    @Test func fruitMovesToFrontAsDaysPass() {
        let unripe = entry(.banana, daysLeft: 6)
        #expect(unripe.status(at: start) == .waiting)
        #expect(unripe.status(at: start.addingTimeInterval(3 * 86_400)) == .ready)
        #expect(unripe.status(at: start.addingTimeInterval(6 * 86_400)) == .overdue)
        #expect(unripe.daysUntilReady(at: start.addingTimeInterval(86_400)) == 2)
    }

    @Test func queueOrder() {
        let readySoon = entry(.mango, daysLeft: 1)
        let readyLater = entry(.banana, daysLeft: 2.5)
        let waitingShort = entry(.papaya, daysLeft: 3, ready: 2)   // ready in 1 day
        let waitingLong = entry(.orange, daysLeft: 8, ready: 5)    // ready in 3 days
        let overdue = entry(.pineapple, daysLeft: -1)
        let ordered = StockQueue.ordered([waitingLong, readyLater, overdue, waitingShort, readySoon], at: start)
        #expect(ordered.map(\.fruit) == [.pineapple, .mango, .banana, .papaya, .orange])
    }

    @Test func testClockShiftsDays() {
        let real = Date(timeIntervalSince1970: 0)
        #expect(TestClock.now(offsetDays: 2, real: real) == real.addingTimeInterval(2 * 86_400))
    }
}

struct PlanAdviceTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func entry(plannedInDays days: Double?) -> QueueEntry {
        QueueEntry(id: UUID(), fruit: .banana, daysLeftAtEstimate: 6, estimatedAt: start, readyWithinDays: 3,
                   plannedEatDate: days.map { start.addingTimeInterval($0 * 86_400) })
    }

    @Test func noPlanNoAdvice() { #expect(entry(plannedInDays: nil).planAdvice() == nil) }
    @Test func tooEarly() { #expect(entry(plannedInDays: 1).planAdvice() == .beforeReady) }
    @Test func fits() { #expect(entry(plannedInDays: 4).planAdvice() == .fits) }
    @Test func tooLate() { #expect(entry(plannedInDays: 7).planAdvice() == .afterLimit) }
}

struct OutcomeSummaryTests {
    private let now = Date(timeIntervalSince1970: 10_000_000)
    private func day(_ offset: Double) -> Date { now.addingTimeInterval(offset * 86_400) }

    @Test func countsConsumedAndDiscardedInRange() {
        let summary = OutcomeSummary.make([
            (kind: .consumed, date: day(-1), wasOverdue: false),
            (kind: .consumed, date: day(-2), wasOverdue: true),
            (kind: .discarded, date: day(-3), wasOverdue: true),
            (kind: .consumed, date: day(-40), wasOverdue: false), // outside 30 days
        ], since: day(-30), until: now)
        #expect(summary == OutcomeSummary(consumed: 2, consumedOnTime: 1, discarded: 1))
        #expect(summary.savedRatio == 2.0 / 3.0)
    }

    @Test func emptyHasNoRatio() {
        #expect(OutcomeSummary.make([], since: day(-30), until: now).savedRatio == nil)
    }
}
