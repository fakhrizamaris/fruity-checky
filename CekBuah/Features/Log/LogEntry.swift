import Foundation
import SwiftData

enum SettingsKey {
    static let savePhotos = "savePhotos"
    /// Shows testing tools (model details, feedback buttons, log, test clock). Off for regular users.
    static let testerMode = "testerMode"
    /// Minimum fruit-recognition probability before the app asks the user to confirm (tester setting).
    static let identityThreshold = "fruitConfirmThreshold"
}

/// One classified fruit, stored locally for evaluating the PoC.
/// A photo with several fruits creates one entry per fruit, sharing `photoID`.
@Model
final class LogEntry {
    var date: Date
    // Defaults keep SwiftData's automatic migration working for logs saved by older builds.
    var photoID: UUID = UUID()
    /// 1-based fruit number in the photo (as drawn on the boxes).
    var itemIndex: Int = 1
    var itemCount: Int = 1
    /// Normalized box "x;y;w;h" (top-left origin), empty for the whole photo.
    var boxText: String = ""
    /// Rough days-left estimate from the RipeNet table, nil when unavailable.
    var estimatedDays: Double?
    /// Fruit the user picked before any correction ("" in logs from older builds).
    var pickedFruitRaw: String = ""
    /// Fruit-identity check: match / looksLike / unrecognized / unavailable ("" in older logs).
    var identityRaw: String = ""
    /// Fruit the check suggested instead, if any.
    var identitySuggestedRaw: String = ""
    /// Vision scores (0...1) for the picked and the suggested fruit, to tune the threshold.
    var identityPickedScore: Double = 0
    var identitySuggestedScore: Double = 0
    /// Tester correction: "switched" (Ganti), "kept" (Tetap) or "" (no answer / no warning).
    var identityActionRaw: String = ""
    /// Model that produced the result ("" in logs from older builds).
    var modelName: String = ""
    var fruitRaw: String
    /// State shown to the user (can be tidak_yakin).
    var stateRaw: String
    /// Model's top class, even when the shown state is tidak_yakin.
    var modelTopRaw: String
    var confidence: Double
    var latencyMs: Int
    var isDemo: Bool
    /// Tester verdict: nil = not answered yet.
    var matchesExpectation: Bool?
    /// Only stored when the tester turned on photo saving.
    @Attribute(.externalStorage) var photoData: Data?

    init(
        fruit: Fruit,
        result: ClassificationResult,
        latencyMs: Int,
        photoData: Data?,
        photoID: UUID = UUID(),
        itemIndex: Int = 1,
        itemCount: Int = 1,
        boxText: String = "",
        estimatedDays: Double? = nil,
        identity: FruitIdentity = .unavailable,
        pickedFruit: Fruit? = nil,
        identityAction: IdentityAction? = nil,
        date: Date = .now
    ) {
        self.date = date
        self.photoID = photoID
        self.itemIndex = itemIndex
        self.itemCount = itemCount
        self.boxText = boxText
        self.estimatedDays = estimatedDays
        self.fruitRaw = fruit.rawValue
        self.modelName = result.modelName
        self.pickedFruitRaw = (pickedFruit ?? fruit).rawValue
        self.identityRaw = identity.verdict.rawValue
        self.identitySuggestedRaw = identity.suggested?.rawValue ?? ""
        self.identityPickedScore = identity.scores[pickedFruit ?? fruit] ?? 0
        self.identitySuggestedScore = identity.suggested.flatMap { identity.scores[$0] } ?? 0
        self.identityActionRaw = identityAction?.rawValue ?? ""
        self.stateRaw = result.state.rawValue
        self.modelTopRaw = result.topTwo.first?.state.rawValue ?? ""
        self.confidence = result.confidence
        self.latencyMs = latencyMs
        self.isDemo = result.isDemo
        self.photoData = photoData
    }

    /// Records the user's answer to the identity warning.
    func recordIdentityAction(_ action: IdentityAction) {
        identityActionRaw = action.rawValue
    }

    /// After "Ganti ke ...": the entry now describes the new fruit and its fresh result.
    func applySwitch(to fruit: Fruit, result: ClassificationResult, estimatedDays: Double?) {
        fruitRaw = fruit.rawValue
        modelName = result.modelName
        stateRaw = result.state.rawValue
        modelTopRaw = result.topTwo.first?.state.rawValue ?? ""
        confidence = result.confidence
        isDemo = result.isDemo
        self.estimatedDays = estimatedDays
        matchesExpectation = nil
        identityActionRaw = IdentityAction.switched.rawValue
    }

    var fruit: Fruit? { Fruit(rawValue: fruitRaw) }
    var state: RipenessState? { RipenessState(rawValue: stateRaw) }
}
