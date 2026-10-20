import Foundation
import SwiftData

/// A fruit (or a few of the same) kept at home, ordered in the stock queue.
@Model
final class StockItem {
    var fruitRaw: String
    var quantity: Int
    /// State shown when the estimate was made (from a scan or chosen by hand).
    var stateRaw: String
    /// Estimated days left at `estimatedAt`; the queue counts down from here.
    var daysLeftAtEstimate: Double
    var estimatedAt: Date
    var addedAt: Date
    /// "scan" or "manual".
    var source: String
    var queueID: UUID = UUID()
    /// Optional eating plan entered by the user (storyboard panel 5), on the test-clock timeline.
    var plannedEatDate: Date?

    init(fruit: Fruit, quantity: Int = 1, state: RipenessState, daysLeft: Double, at date: Date, source: String) {
        self.fruitRaw = fruit.rawValue
        self.quantity = quantity
        self.stateRaw = state.rawValue
        self.daysLeftAtEstimate = daysLeft
        self.estimatedAt = date
        self.addedAt = date
        self.source = source
    }

    var fruit: Fruit? { Fruit(rawValue: fruitRaw) }
    var state: RipenessState? { RipenessState(rawValue: stateRaw) }

    var readyWithinDays: Double {
        guard let fruit else { return 0 }
        return KnowledgeBase.shared.knowledge(for: fruit)?.shelfLife?.readyWithinDays ?? 0
    }

    /// nil when the fruit is gone (quantity 0) or unknown. Items at 0 are kept so undo can restore them.
    func entry() -> QueueEntry? {
        guard let fruit, quantity > 0 else { return nil }
        return QueueEntry(id: queueID, fruit: fruit, daysLeftAtEstimate: daysLeftAtEstimate,
                          estimatedAt: estimatedAt, readyWithinDays: readyWithinDays, plannedEatDate: plannedEatDate)
    }

    /// Manual correction: "from now (test clock), this fruit has `days` left".
    func reestimate(daysLeft days: Double, state: RipenessState, at now: Date) {
        daysLeftAtEstimate = days
        stateRaw = state.rawValue
        estimatedAt = now
    }
}
