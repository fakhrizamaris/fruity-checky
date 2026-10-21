import CoreGraphics
import Foundation
import Observation
import UIKit

/// Live scan for shopping, one fruit at a time: the user holds a fruit close and turns it; the app looks at
/// several frames and, once they agree, asks "Ambil?" in a pop-up. "Pilih yang lain" skips the fruit.
@MainActor
@Observable
final class LiveScanModel {
    enum Status: Equatable {
        case idle
        case running
        case capturing
        case denied
        case unavailable(String)
    }

    /// The fruit shown in the live view while frames are collected.
    struct LiveFruit {
        let kind: ShelfFruit
        /// Normalized square inside the live frame (the centre square of the camera image) that the model
        /// looked at: the detector box plus its margin.
        let box: CGRect
        /// Latest ripeness; nil while judging or when the app has no ripeness model for this kind.
        let result: ClassificationResult?
    }

    /// Answer shown in the pop-up.
    struct Offer: Identifiable {
        let id = UUID()
        let verdict: LiveVerdict
        let crop: CGImage

        var basketItem: BasketItem {
            BasketItem(source: .live(id), kind: verdict.kind, result: verdict.result, thumbnail: UIImage(cgImage: crop))
        }
    }

    private(set) var status: Status = .idle
    private(set) var current: LiveFruit?
    /// 0...1 while the user turns the fruit.
    private(set) var progress = 0.0
    /// Set when the frames agree; the view presents it as a sheet. Scanning pauses meanwhile.
    var offer: Offer?
    /// True from the moment an offer is made until the user takes it, skips it, or swipes the sheet away.
    private var awaitingDecision = false
    /// True right after a decision until the fruit leaves the frame (or a few seconds pass),
    /// so the same fruit is not offered again.
    private(set) var waitingForNextFruit = false
    /// The fruit looks like one the app does not support (apple, orange, ...).
    private(set) var unsupportedHint = false
    /// The fruit fills the frame: the user should move the phone back so the whole fruit shows.
    private(set) var tooCloseHint = false
    /// Short confirmation after taking a fruit, e.g. "Pisang masuk keranjang". Cleared after a few seconds.
    private(set) var toast: String?
    /// Last detector failure, so a broken model is visible instead of looking like "no fruit".
    private(set) var detectorError: String?
    /// Tester details of the latest frame: which model named the fruit, its label and confidence.
    private(set) var lastKindInfo = "–"
    /// Tester details from the multi-task model: shared stage name and damage probability.
    private(set) var lastStageInfo = "–"
    private(set) var lastDamageInfo = "–"
    let service = CameraService()

    let usesDetector = CoreMLShelfDetector.isAvailable
    /// Multi-task model (species + ripeness + damage); when bundled it replaces the two below.
    let usesMultitask = FruitMultitaskClassifier.isAvailable
    /// Species classifier trained on the classifier dataset; when bundled it decides the kind.
    let usesSpeciesModel = FruitSpeciesClassifier.isAvailable
    var detectorName: String {
        let box = usesDetector ? CoreMLShelfDetector.modelName : "kotak tengah"
        let kind = usesSpeciesModel ? FruitSpeciesClassifier.modelName
            : usesDetector ? "label detektor / \(RipeNetClassifier.modelName)" : RipeNetClassifier.modelName
        return "kotak: \(box) · jenis: \(kind)"
    }

    private var classifier: (any FruitClassifying)?
    private var accumulator = LiveScanAccumulator()
    private var crops: [Int: CGImage] = [:]
    private var frameCounter = 0
    private var isScanning = false
    private var emptyFrames = 0
    private var unsupportedFrames = 0
    private var waitingSince: Date?
    private var toastTask: Task<Void, Never>?

    /// Box used when the detector finds nothing: the fruit is held close and fills the guide square.
    private static let closeUpBox = CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84)
    /// Margin around a detector box in the live view (per side, as a share of the box), so the whole fruit
    /// and a bit of background are in the crop, like the training crops.
    private static let livePadding: CGFloat = 0.25
    /// Live frame side in pixels (camera centre square). 768 instead of 448 keeps the fruit crop sharp when the
    /// fruit fills only part of the square; the models still get 224 x 224. Measure on the iPhone if it lags.
    private static let frameSide: CGFloat = 768
    /// Margin of the yellow box drawn around the fruit. Smaller than the crop margin (`livePadding`) so the box
    /// hugs the fruit; the model still sees the wider crop.
    private static let displayPadding: CGFloat = 0.1
    /// Box drawn in the latest frame (normalized, inside the camera card).
    private var lastViewBox = closeUpBox
    /// Give up waiting for the previous fruit to leave after this long.
    private static let maxWait: TimeInterval = 4

    func start(classifier: any FruitClassifying) async {
        self.classifier = classifier
        guard await CameraService.requestAccess() else {
            status = .denied
            return
        }
        service.onFrame = { [weak self] frame in
            Task { @MainActor in await self?.scan(frame) }
        }
        service.frameSide = Self.frameSide
        do {
            try await service.start()
            status = .running
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    func stop() {
        service.stop()
        if status == .running { status = .idle }
        resetCollection()
    }

    /// "Ambil": the offered fruit goes into the basket. `manualResult` replaces the photo's ripeness when the
    /// user did the hand check (avocado, mango).
    func take(_ offer: Offer, into basket: Basket, manualResult: ClassificationResult? = nil) {
        var item = offer.basketItem
        if let manualResult { item.result = manualResult }
        basket.add(item)
        show(toast: "\(offer.verdict.kind.displayName) masuk keranjang")
        finishOffer()
    }

    /// "Pilih yang lain".
    func skip() {
        finishOffer()
    }

    /// The sheet was swiped away without a choice: treat it as "Pilih yang lain".
    func skipIfPending() {
        if awaitingDecision { finishOffer() }
    }

    func undoLast(in basket: Basket) {
        guard let removed = basket.removeLast() else { return }
        show(toast: "\(removed.kind?.displayName ?? "Buah") dikembalikan")
    }

    private func finishOffer() {
        awaitingDecision = false
        offer = nil
        resetCollection()
        waitingForNextFruit = true
        waitingSince = .now
    }

    private func resetCollection() {
        accumulator.reset()
        crops.removeAll()
        current = nil
        progress = 0
        unsupportedFrames = 0
        unsupportedHint = false
    }

    private func show(toast message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// Frames that arrive while a scan is running, or while the pop-up is open, are dropped.
    private func scan(_ frame: CGImage) async {
        guard !isScanning, status == .running, offer == nil, !awaitingDecision else { return }
        isScanning = true
        defer { isScanning = false }

        let observation = await observe(frame)
        if waitingForNextFruit {
            let waited = Date.now.timeIntervalSince(waitingSince ?? .now)
            if observation == nil { emptyFrames += 1 }
            // The previous fruit is gone (two empty frames) or the user kept going: start fresh.
            guard emptyFrames >= 2 || waited > Self.maxWait else { return }
            waitingForNextFruit = false
            emptyFrames = 0
        }
        guard let observation else {
            emptyFrames += 1
            if emptyFrames >= 2 { resetCollection() }
            return
        }
        emptyFrames = 0
        accumulator.add(observation)
        crops = crops.filter { frame in accumulator.observations.contains { $0.frame == frame.key } }
        progress = accumulator.progress
        current = LiveFruit(kind: accumulator.leadingKind ?? observation.kind, box: lastViewBox,
                            result: observation.result)
        if let verdict = accumulator.verdict(), let crop = crops[verdict.bestFrame] {
            awaitingDecision = true
            offer = Offer(verdict: verdict, crop: crop)
        }
    }

    private static func info(_ model: String, _ label: String, _ confidence: Double) -> String {
        "\(model) · \(label) \(Int((confidence * 100).rounded()))%"
    }

    /// One frame: find the fruit (detector, or the close-up square), name it, and judge its ripeness.
    private func observe(_ frame: CGImage) async -> LiveObservation? {
        var box = Self.closeUpBox
        var fromDetector = false
        var kind: ShelfFruit?
        var confidence = 0.0
        if usesDetector {
            do {
                let candidates = try await CoreMLShelfDetector.shared.candidates(in: frame)
                detectorError = nil
                if let best = LiveFruitPick.best(candidates) {
                    box = best.box
                    fromDetector = true
                    // A one-class "fruit" detector gives no kind; a 5-kind detector does.
                    if let detected = ShelfFruit(detectorLabel: best.label) {
                        kind = detected
                        confidence = best.confidence
                        lastKindInfo = Self.info(CoreMLShelfDetector.modelName, best.label, best.confidence)
                    }
                }
            } catch {
                detectorError = error.localizedDescription
            }
        }
        // A fruit held too close fills the frame: the classifier then sees only skin, not the shape that tells
        // mango from papaya (21 Oct 2026: a box inside a mango read "other" 0.95, the whole mango "mango" 0.88).
        tooCloseHint = fromDetector && LiveFruitPick.isTooClose(box)
        if tooCloseHint { return nil }
        // The shelf detector's box tends to sit inside a close fruit, so the crop gets a wide margin.
        let padding = fromDetector ? Self.livePadding : 0
        let crop = FruitAnalyzer.squareCrop(of: frame, around: box, padding: padding) ?? frame
        lastViewBox = FruitAnalyzer.normalizedSquare(around: box, width: CGFloat(frame.width), height: CGFloat(frame.height),
                                                     padding: fromDetector ? Self.displayPadding : 0)

        // The multi-task model, when bundled, gives kind, ripeness and damage in one pass.
        if usesMultitask {
            guard let reading = try? await FruitMultitaskClassifier.shared.read(crop) else { return nil }
            lastKindInfo = Self.info(FruitMultitaskClassifier.modelName, reading.label, reading.speciesConfidence)
            lastStageInfo = reading.stageIndex.map {
                "\(MultitaskRules.stageNames[$0]) \(Int((reading.stageConfidence * 100).rounded()))%"
            } ?? "tidak ada tahap"
            lastDamageInfo = "\(Int((reading.damage * 100).rounded()))%" + (reading.damageTrusted ? "" : " (diabaikan untuk buah ini)")
            guard let supported = reading.kind else {
                // "other", or the species is below the threshold: no observation this frame.
                if reading.isOther, reading.speciesConfidence >= MultitaskRules.speciesThreshold { unsupportedFrames += 1 }
                unsupportedHint = unsupportedFrames >= 3
                return nil
            }
            unsupportedFrames = 0
            unsupportedHint = false
            frameCounter += 1
            crops[frameCounter] = crop
            return LiveObservation(frame: frameCounter, kind: supported, kindConfidence: reading.speciesConfidence,
                                   box: box, result: reading.result)
        }

        // The species model, when bundled, overrides the detector's kind (that was trained on synthetic
        // shelves and mixed up green mango and papaya).
        if usesSpeciesModel {
            guard let prediction = try? await FruitSpeciesClassifier.shared.classify(crop) else { return nil }
            lastKindInfo = Self.info(FruitSpeciesClassifier.modelName, prediction.label, prediction.confidence)
            guard let supported = prediction.kind else {
                if prediction.confidence >= LiveScanAccumulator.minKindConfidence { unsupportedFrames += 1 }
                unsupportedHint = unsupportedFrames >= 3
                return nil
            }
            kind = supported
            confidence = prediction.confidence
        }

        if kind == nil {
            // Until the multi-task classifier exists, RipeNet's fruit head names the fruit
            // (banana, mango, papaya; apple, orange and pineapple are not in the app's list).
            guard RipeNetClassifier.isAvailable, let scan = try? await RipeNetClassifier.shared.scan(image: crop) else { return nil }
            let recognition = FruitIdentity.recognize(scores: scan.fruitScores)
            if let fruit = recognition.fruit {
                lastKindInfo = Self.info(RipeNetClassifier.modelName, fruit.rawValue, scan.fruitScores[fruit] ?? 0)
            }
            guard recognition.identity.verdict == .match, let fruit = recognition.fruit else { return nil }
            guard let supported = ShelfFruit(detectorLabel: fruit.rawValue) else {
                unsupportedFrames += 1
                unsupportedHint = unsupportedFrames >= 3
                return nil
            }
            kind = supported
            confidence = scan.fruitScores[fruit] ?? 0
        }
        guard let kind else { return nil }
        unsupportedFrames = 0
        unsupportedHint = false

        var result: ClassificationResult?
        if let fruit = kind.ripenessFruit, let classifier {
            result = try? await classifier.classify(image: crop, fruit: fruit)
        }
        frameCounter += 1
        crops[frameCounter] = crop
        return LiveObservation(frame: frameCounter, kind: kind, kindConfidence: confidence, box: box, result: result)
    }
}
