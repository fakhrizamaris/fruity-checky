import Foundation

/// Where a stored fruit sits in the queue right now.
enum StockStatus: Int, CaseIterable, Comparable, Sendable {
    /// Days left ≤ 0: past its estimated limit, check before eating.
    case overdue
    /// 0 < days left ≤ the fruit's "matang" value: eat these first.
    case ready
    /// Still needs time: waits at the back of the queue.
    case waiting

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .overdue: "Perlu diperiksa"
        case .ready: "Siap dikonsumsi"
        case .waiting: "Menunggu matang"
        }
    }

    var symbolName: String {
        switch self {
        case .overdue: "exclamationmark.triangle"
        case .ready: "fork.knife"
        case .waiting: "hourglass"
        }
    }

    /// Reuses the ripeness colours: overdue = rotten, ready = ripe, waiting = unripe.
    var state: RipenessState {
        switch self {
        case .overdue: .rotten
        case .ready: .ripe
        case .waiting: .unripe
        }
    }
}

/// One stored fruit as seen by the queue, independent of SwiftData so it can be unit tested.
struct QueueEntry: Identifiable, Sendable {
    let id: UUID
    let fruit: Fruit
    /// Estimated days left at `estimatedAt`.
    let daysLeftAtEstimate: Double
    let estimatedAt: Date
    /// From this many days left the fruit counts as ready.
    let readyWithinDays: Double
    var plannedEatDate: Date? = nil

    func daysLeft(at now: Date) -> Double {
        daysLeftAtEstimate - now.timeIntervalSince(estimatedAt) / 86_400
    }

    func status(at now: Date) -> StockStatus {
        let left = daysLeft(at: now)
        if left <= 0 { return .overdue }
        return left <= readyWithinDays ? .ready : .waiting
    }

    /// How the user's eating plan fits the estimate, nil without a plan.
    func planAdvice() -> PlanAdvice? {
        guard let plannedEatDate else { return nil }
        let leftOnPlan = daysLeft(at: plannedEatDate)
        if leftOnPlan <= 0 { return .afterLimit }
        if leftOnPlan > readyWithinDays { return .beforeReady }
        return .fits
    }

    /// Days until it moves to the front (0 when already ready or overdue).
    func daysUntilReady(at now: Date) -> Double {
        max(0, daysLeft(at: now) - readyWithinDays)
    }
}

enum PlanAdvice: Sendable {
    case fits, beforeReady, afterLimit

    var text: String {
        switch self {
        case .fits: "Sesuai perkiraan"
        case .beforeReady: "Kemungkinan belum matang pada tanggal ini"
        case .afterLimit: "Melewati perkiraan, sebaiknya dikonsumsi lebih awal"
        }
    }

    var symbolName: String {
        switch self {
        case .fits: "checkmark.circle"
        case .beforeReady: "hourglass"
        case .afterLimit: "exclamationmark.triangle"
        }
    }
}

enum StockQueue {
    /// Front of the queue first: overdue (needs checking), then ready fruits that spoil soonest,
    /// then waiting fruits that become ready soonest.
    static func ordered(_ entries: [QueueEntry], at now: Date) -> [QueueEntry] {
        entries.sorted { lhs, rhs in
            let ls = lhs.status(at: now), rs = rhs.status(at: now)
            if ls != rs { return ls < rs }
            let lk = ls == .waiting ? lhs.daysUntilReady(at: now) : lhs.daysLeft(at: now)
            let rk = rs == .waiting ? rhs.daysUntilReady(at: now) : rhs.daysLeft(at: now)
            if lk != rk { return lk < rk }
            return lhs.estimatedAt < rhs.estimatedAt
        }
    }
}

/// App clock with a manual offset, so testers can jump days ahead without waiting.
enum TestClock {
    static let offsetKey = "testDayOffset"

    static func now(offsetDays: Double, real: Date = .now) -> Date {
        real.addingTimeInterval(offsetDays * 86_400)
    }
}

/// Why a fruit left the stock.
enum OutcomeKind: String, Sendable {
    case consumed
    case discarded

    var pastTense: String {
        switch self {
        case .consumed: "ditandai dikonsumsi"
        case .discarded: "ditandai dibuang"
        }
    }

    var actionTitle: String {
        switch self {
        case .consumed: "Dikonsumsi"
        case .discarded: "Dibuang"
        }
    }

    var symbolName: String {
        switch self {
        case .consumed: "fork.knife"
        case .discarded: "trash"
        }
    }
}

/// Waste summary over a period: how many fruits were eaten vs thrown away.
struct OutcomeSummary: Equatable, Sendable {
    let consumed: Int
    let consumedOnTime: Int
    let discarded: Int

    var total: Int { consumed + discarded }

    /// Share of fruits that were eaten instead of thrown away (0...1), nil without data.
    var savedRatio: Double? { total > 0 ? Double(consumed) / Double(total) : nil }

    static func make(_ outcomes: [(kind: OutcomeKind, date: Date, wasOverdue: Bool)],
                     since start: Date, until end: Date) -> OutcomeSummary {
        let inRange = outcomes.filter { $0.date >= start && $0.date <= end }
        let consumed = inRange.filter { $0.kind == .consumed }
        return OutcomeSummary(
            consumed: consumed.count,
            consumedOnTime: consumed.filter { !$0.wasOverdue }.count,
            discarded: inRange.filter { $0.kind == .discarded }.count
        )
    }
}
