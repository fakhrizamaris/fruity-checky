import Foundation
import Observation
import UIKit

/// Where a basket item came from. Only the live scan adds fruit since the shelf photo was removed
/// (21 Oct 2026); kept as an enum so a manual add can join later.
enum BasketSource: Hashable, Sendable {
    /// One fruit added from the live scan.
    case live(UUID)
}

/// One fruit the user picked while shopping. Lives in memory until it is saved to stock.
struct BasketItem: Identifiable, Sendable {
    let id = UUID()
    let source: BasketSource
    /// Nil when the detector found an object but not its kind.
    let kind: ShelfFruit?
    /// Nil when the app has no ripeness model for this kind (avocado, dragon fruit) or it was not judged yet.
    var result: ClassificationResult?
    /// Crop of the fruit, shown in the basket list.
    let thumbnail: UIImage?
    let addedAt: Date

    init(source: BasketSource, kind: ShelfFruit?, result: ClassificationResult?, thumbnail: UIImage?, addedAt: Date = .now) {
        self.source = source
        self.kind = kind
        self.result = result
        self.thumbnail = thumbnail
        self.addedAt = addedAt
    }

    var state: RipenessState? { result?.state }

    /// Fruit used by the stock queue and knowledge base; nil for kinds the stock does not support yet.
    var stockFruit: Fruit? { kind?.ripenessFruit }

    /// Rotten fruit and fruit without a known kind or ripeness are not stocked.
    var canStock: Bool { stockFruit != nil && result != nil && state != .rotten }

    /// Rough days left (knowledge-base table, not measured). Nil when there is no estimate.
    var estimatedDays: Double? {
        guard let fruit = stockFruit, let result else { return nil }
        return KnowledgeBase.shared.knowledge(for: fruit)?.shelfLife?.estimate(for: result.state, from: result.ranked)
    }
}

/// Basket rows grouped by kind and ripeness, as shown on the basket screen.
struct BasketGroup: Identifiable, Equatable, Sendable {
    let kind: ShelfFruit?
    let state: RipenessState?
    let count: Int

    var id: String { "\(kind?.rawValue ?? "unknown")|\(state?.rawValue ?? "none")" }
}

/// Pure basket rules, kept apart from the observable store so they can be unit tested.
enum BasketRules {
    /// Groups by kind, then by ripeness in ripening order; unknown kinds and unjudged fruit last.
    static func groups(_ items: [BasketItem]) -> [BasketGroup] {
        let grouped = Dictionary(grouping: items) { GroupKey(kind: $0.kind, state: $0.state) }
        return grouped.map { BasketGroup(kind: $0.key.kind, state: $0.key.state, count: $0.value.count) }
            .sorted { lhs, rhs in
                let lk = lhs.kind.map { ShelfFruit.allCases.firstIndex(of: $0) ?? 0 } ?? Int.max
                let rk = rhs.kind.map { ShelfFruit.allCases.firstIndex(of: $0) ?? 0 } ?? Int.max
                if lk != rk { return lk < rk }
                return (lhs.state?.ripeningStage ?? Int.max) < (rhs.state?.ripeningStage ?? Int.max)
            }
    }

    private struct GroupKey: Hashable {
        let kind: ShelfFruit?
        let state: RipenessState?
    }
}

/// The shopping basket shared by the live scan and the basket screen.
@MainActor
@Observable
final class Basket {
    private(set) var items: [BasketItem] = []

    var count: Int { items.count }
    var groups: [BasketGroup] { BasketRules.groups(items) }

    func contains(_ source: BasketSource) -> Bool { items.contains { $0.source == source } }

    func add(_ item: BasketItem) {
        guard !contains(item.source) else { return }
        items.append(item)
    }

    func remove(_ id: BasketItem.ID) { items.removeAll { $0.id == id } }

    /// Undo for the live scan: removes the most recently added item.
    @discardableResult
    func removeLast() -> BasketItem? { items.popLast() }

    func removeAll(where shouldRemove: (BasketItem) -> Bool) { items.removeAll(where: shouldRemove) }

    func clear() { items.removeAll() }
}
