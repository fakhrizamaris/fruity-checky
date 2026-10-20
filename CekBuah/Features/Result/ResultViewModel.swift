import SwiftData
import SwiftUI

@MainActor
@Observable
final class ResultViewModel {
    enum Phase {
        case loading
        case done([DetectedFruit])
        case failed(String)
    }

    let photo: CapturedPhoto
    private(set) var phase: Phase = .loading
    private(set) var latencyMs: Int?
    /// Tester verdict per fruit number.
    private(set) var feedback: [Int: Bool] = [:]
    /// Fruit numbers already saved to the stock queue.
    private(set) var savedToStock: Set<Int> = []
    /// Fruit numbers whose result is being recomputed after "Ganti ke ...".
    private(set) var switching: Set<Int> = []
    private var logEntries: [Int: LogEntry] = [:]
    private var analyzer: FruitAnalyzer?

    init(photo: CapturedPhoto) {
        self.photo = photo
    }

    var items: [DetectedFruit] {
        if case .done(let items) = phase { items } else { [] }
    }

    var isDemo: Bool { items.first?.result.isDemo ?? false }

    /// The single fruit of this photo, or nil once the user switched some fruits to another type.
    var uniformFruit: Fruit? {
        let fruits = Set(items.map(\.fruit))
        return fruits.count == 1 ? fruits.first : nil
    }

    func reason(for item: DetectedFruit) -> String {
        KnowledgeBase.shared.knowledge(for: item.fruit)?.reason(for: item.result.state)
            ?? "Keterangan belum tersedia."
    }

    /// Rough days left, weighted by the model's probabilities but kept inside the shown stage's range
    /// (RipeNet table, not measured). Nil for busuk and tidak yakin.
    func estimatedDays(for item: DetectedFruit) -> Double? {
        KnowledgeBase.shared.knowledge(for: item.fruit)?.shelfLife?.estimate(for: item.result.state, from: item.result.ranked)
    }

    /// Rough days until ripe; only for fruit shown as mentah.
    func daysUntilReady(for item: DetectedFruit) -> Double? {
        guard item.result.state == .unripe, let days = estimatedDays(for: item) else { return nil }
        return KnowledgeBase.shared.knowledge(for: item.fruit)?.shelfLife?.daysUntilReady(fromDaysLeft: days)
    }

    /// Rotten fruit is not stocked: it should not be eaten.
    func canAddToStock(_ item: DetectedFruit) -> Bool { item.result.state != .rotten }

    /// Puts one detected fruit in the stock queue, counting down from the test-clock day.
    func addToStock(_ item: DetectedFruit, context: ModelContext, now: Date) {
        guard !savedToStock.contains(item.number) else { return }
        let state = item.result.state == .unsure ? (item.result.ranked.first?.state ?? .ripe) : item.result.state
        let days = estimatedDays(for: item)
            ?? KnowledgeBase.shared.knowledge(for: item.fruit)?.shelfLife?.defaultDaysLeft(for: state) ?? 0
        context.insert(StockItem(fruit: item.fruit, state: state, daysLeft: days, at: now, source: "scan"))
        try? context.save()
        savedToStock.insert(item.number)
    }

    /// First fruit in the photo for which the physical check is offered.
    private var physicalCheckItem: DetectedFruit? {
        items.first { DecisionRules.offersPhysicalCheck(for: $0.result, fruit: $0.fruit) }
    }

    var offersPhysicalCheck: Bool { physicalCheckItem != nil }

    /// Fruit the physical check is about.
    var physicalCheckFruit: Fruit { physicalCheckItem?.fruit ?? items.first?.fruit ?? .banana }

    /// True when every fruit is unsure: then the physical check is the main next step.
    var allUnsure: Bool {
        !items.isEmpty && items.allSatisfy { $0.result.state == .unsure }
    }

    func analyze(using classifier: any FruitClassifying, identifier: any FruitIdentifying,
                 identityThreshold: Double, context: ModelContext, savePhoto: Bool) async {
        guard case .loading = phase else { return }
        guard let cgImage = photo.image.cgImage else {
            phase = .failed("Foto tidak dapat dibaca. Silakan coba foto lain.")
            return
        }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let analyzer = FruitAnalyzer(classifier: classifier, identifier: identifier, identityThreshold: identityThreshold)
            self.analyzer = analyzer
            let items = [try await analyzer.analyzeSingle(image: cgImage)]
            latencyMs = Int((start.duration(to: clock.now) / .milliseconds(1)).rounded())
            phase = .done(items)
            saveLog(items, context: context, savePhoto: savePhoto)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// "Ganti ke ...": judges this fruit again as the suggested fruit.
    func switchFruit(_ item: DetectedFruit, to newFruit: Fruit, context: ModelContext) async {
        guard let analyzer, let cgImage = photo.image.cgImage,
              !switching.contains(item.number), !savedToStock.contains(item.number) else { return }
        switching.insert(item.number)
        defer { switching.remove(item.number) }
        guard let updated = try? await analyzer.reclassify(item, as: newFruit, in: cgImage) else { return }
        replace(updated)
        feedback[item.number] = nil
        logEntries[item.number]?.applySwitch(to: newFruit, result: updated.result, estimatedDays: estimatedDays(for: updated))
        try? context.save()
    }

    /// "Tetap nilai sebagai ...": the user keeps their own choice.
    func keepPicked(_ item: DetectedFruit, context: ModelContext) {
        guard var updated = items.first(where: { $0.number == item.number }) else { return }
        updated.identityAction = .kept
        replace(updated)
        logEntries[item.number]?.recordIdentityAction(.kept)
        try? context.save()
    }

    private func replace(_ item: DetectedFruit) {
        guard case .done(var current) = phase, let index = current.firstIndex(where: { $0.number == item.number }) else { return }
        current[index] = item
        phase = .done(current)
    }

    /// Tester verdict for one fruit: does the result match what they see?
    func setFeedback(_ matches: Bool, for number: Int, context: ModelContext) {
        feedback[number] = matches
        logEntries[number]?.matchesExpectation = matches
        try? context.save()
    }

    private func saveLog(_ items: [DetectedFruit], context: ModelContext, savePhoto: Bool) {
        let photoID = UUID()
        let photoData = savePhoto ? photo.image.jpegData(compressionQuality: 0.7) : nil
        for item in items {
            let entry = LogEntry(
                fruit: item.fruit,
                result: item.result,
                latencyMs: latencyMs ?? 0,
                photoData: item.number == 1 ? photoData : nil, // store the photo once
                photoID: photoID,
                itemIndex: item.number,
                itemCount: items.count,
                boxText: item.coversWholePhoto ? "" : Self.format(item.box),
                estimatedDays: estimatedDays(for: item),
                identity: item.identity,
                pickedFruit: item.pickedFruit,
                identityAction: item.identityAction
            )
            context.insert(entry)
            logEntries[item.number] = entry
        }
        try? context.save()
    }

    private static func format(_ box: CGRect) -> String {
        [box.minX, box.minY, box.width, box.height].map { String(format: "%.3f", $0) }.joined(separator: ";")
    }
}
