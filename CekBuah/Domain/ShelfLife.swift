import Foundation

/// Rough "days until no longer good to eat" per ripeness state, stored per fruit in knowledge-base.json.
/// Values come from the RipeNet dataset's labelling table (author-chosen, not measured),
/// so the app always shows them as a rough estimate.
struct ShelfLife: Decodable, Sendable {
    /// Keyed by RipenessState raw value: mentah, matang, terlalu_matang, busuk.
    let days: [String: Double]
    let source: String

    func days(for state: RipenessState) -> Double? { days[state.rawValue] }

    /// From this many days left the fruit counts as ready to eat (the "matang" value).
    var readyWithinDays: Double { days(for: .ripe) ?? 0 }

    /// Expected days left, weighted by the model's probabilities:
    /// Σ p(state) × days(state). States without a table value are left out and the rest re-weighted.
    func estimateDaysLeft(from predictions: [ClassPrediction]) -> Double? {
        var weighted = 0.0
        var total = 0.0
        for prediction in predictions {
            guard let value = days(for: prediction.state) else { continue }
            weighted += prediction.probability * value
            total += prediction.probability
        }
        return total > 0 ? weighted / total : nil
    }

    /// Days left for the result shown to the user, kept inside that stage's range so the text
    /// never contradicts the label (e.g. "matang" never says "matang 1 hari lagi").
    /// Nil for busuk and tidak yakin: no consumption estimate is shown then.
    func estimate(for state: RipenessState, from predictions: [ClassPrediction]) -> Double? {
        guard let weighted = estimateDaysLeft(from: predictions) else { return nil }
        switch state {
        case .rotten, .unsure:
            return nil
        case .ripe, .overripe:
            return min(max(weighted, 0), readyWithinDays)
        case .unripe:
            let upper = days(for: .unripe) ?? weighted
            return min(max(weighted, readyWithinDays + 1), max(upper, readyWithinDays + 1))
        }
    }

    /// Days until the fruit reaches "matang", from the days left until it spoils.
    /// Nil when it is already ripe (or past), so the screen shows only the spoil estimate.
    func daysUntilReady(fromDaysLeft daysLeft: Double) -> Double? {
        let wait = daysLeft - readyWithinDays
        return wait.rounded() >= 1 ? wait : nil
    }

    /// Days left for a state chosen by hand (manual add / editing in the stock queue).
    func defaultDaysLeft(for state: RipenessState) -> Double {
        if let value = days(for: state) { return value }
        switch state {
        case .overripe: return readyWithinDays / 2 // RipeNet has no "terlalu matang" stage
        case .rotten: return 0
        default: return readyWithinDays
        }
    }
}

enum DaysText {
    /// "±5 hari lagi", "hari ini", "lewat 1 hari".
    static func remaining(_ days: Double) -> String {
        let rounded = Int(days.rounded())
        if rounded > 0 { return "±\(rounded) hari lagi" }
        if rounded == 0 { return "hari ini" }
        return "lewat \(-rounded) hari"
    }
}
