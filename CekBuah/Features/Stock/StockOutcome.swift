import Foundation
import SwiftData

/// One fruit that left the stock: eaten or thrown away. Used for the waste summary and for undo.
@Model
final class StockOutcome {
    var fruitRaw: String
    /// OutcomeKind raw value.
    var kindRaw: String
    /// Test-clock date of the action.
    var date: Date
    /// Whether the fruit was already past its estimate when it left the stock.
    var wasOverdue: Bool
    /// StockItem.queueID it came from, so undo can return it.
    var itemQueueID: UUID

    init(fruit: Fruit, kind: OutcomeKind, date: Date, wasOverdue: Bool, itemQueueID: UUID) {
        self.fruitRaw = fruit.rawValue
        self.kindRaw = kind.rawValue
        self.date = date
        self.wasOverdue = wasOverdue
        self.itemQueueID = itemQueueID
    }

    var kind: OutcomeKind? { OutcomeKind(rawValue: kindRaw) }
}
