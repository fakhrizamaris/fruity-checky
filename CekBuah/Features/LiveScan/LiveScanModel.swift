import CoreGraphics
import Foundation
import Observation
import UIKit

/// Live scan for shopping: the camera shows one fruit at a time with a box and two labels
/// (kind and ripeness). The user taps "Tambah ke keranjang" to keep it, then points at the next fruit.
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

    /// The fruit currently shown in the live view.
    struct LiveFruit {
        let kind: ShelfFruit
        /// Normalized box inside the live frame (the centre square of the camera image).
        let box: CGRect
        /// Nil while ripeness is being judged, or when the app has no ripeness model for this kind.
        var result: ClassificationResult?
        /// The crop that was judged; becomes the basket thumbnail.
        let crop: CGImage
    }

    private(set) var status: Status = .idle
    private(set) var current: LiveFruit?
    /// Short confirmation after adding, e.g. "Pisang ditambahkan". Cleared after a few seconds.
    private(set) var toast: String?
    let service = CameraService()

    /// True when the trained shelf detector is bundled; otherwise RipeNet recognises the centre of the frame.
    let usesDetector = CoreMLShelfDetector.isAvailable
    var detectorName: String { usesDetector ? CoreMLShelfDetector.modelName : RipeNetClassifier.modelName }

    private var classifier: (any FruitClassifying)?
    private var isScanning = false
    /// Last raw pick; the shown fruit only changes after two consecutive frames agree, so it does not flicker.
    private var lastPick: ShelfCandidate?
    private var toastTask: Task<Void, Never>?

    func start(classifier: any FruitClassifying) async {
        self.classifier = classifier
        guard await CameraService.requestAccess() else {
            status = .denied
            return
        }
        service.onFrame = { [weak self] frame in
            Task { @MainActor in await self?.scan(frame) }
        }
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
        current = nil
        lastPick = nil
    }

    /// Whole photo for the shelf scan, upright and large enough for small fruits at the back.
    func captureShelfPhoto() async throws -> UIImage {
        status = .capturing
        defer { status = .running }
        let data = try await service.capturePhoto()
        guard let image = UIImage(data: data) else { throw CameraError.noData }
        return image.normalized(maxDimension: 2048)
    }

    /// Puts the shown fruit in the basket and waits for the next one.
    func addCurrent(to basket: Basket) {
        guard let current else { return }
        basket.add(BasketItem(source: .live(UUID()), kind: current.kind, result: current.result,
                              thumbnail: UIImage(cgImage: current.crop)))
        show(toast: "\(current.kind.displayName) ditambahkan ke keranjang")
        // Forget the fruit so the next one is recognised fresh.
        self.current = nil
        lastPick = nil
    }

    func undoLast(in basket: Basket) {
        guard let removed = basket.removeLast() else { return }
        show(toast: "\(removed.kind?.displayName ?? "Buah") dikembalikan")
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

    /// Frames that arrive while a scan is running are dropped.
    private func scan(_ frame: CGImage) async {
        guard !isScanning, status == .running else { return }
        isScanning = true
        defer { isScanning = false }

        guard let pick = await pick(in: frame) else {
            // Two empty frames in a row clear the label.
            if lastPick == nil { current = nil }
            lastPick = nil
            return
        }
        defer { lastPick = pick.candidate }
        guard let previous = lastPick, LiveFruitPick.isSameFruit(previous, pick.candidate),
              let kind = ShelfFruit(detectorLabel: pick.candidate.label) else { return }

        let crop = FruitAnalyzer.squareCrop(of: frame, around: pick.candidate.box) ?? frame
        // Same fruit as shown: only move the box, keep the ripeness already judged.
        if let shown = current, shown.kind == kind, shown.result != nil {
            current = LiveFruit(kind: kind, box: pick.candidate.box, result: shown.result, crop: shown.crop)
            return
        }
        var live = LiveFruit(kind: kind, box: pick.candidate.box, result: pick.result, crop: crop)
        if live.result == nil, let fruit = kind.ripenessFruit, let classifier {
            live.result = try? await classifier.classify(image: crop, fruit: fruit)
        }
        current = live
    }

    /// Detector when bundled, otherwise RipeNet on the whole frame (one fruit in the guide square).
    private func pick(in frame: CGImage) async -> (candidate: ShelfCandidate, result: ClassificationResult?)? {
        if usesDetector {
            guard let candidates = try? await CoreMLShelfDetector.shared.candidates(in: frame),
                  let best = LiveFruitPick.best(candidates) else { return nil }
            return (best, nil)
        }
        guard RipeNetClassifier.isAvailable,
              let scan = try? await RipeNetClassifier.shared.scan(image: frame) else { return nil }
        let recognition = FruitIdentity.recognize(scores: scan.fruitScores)
        guard recognition.identity.verdict == .match, let fruit = recognition.fruit,
              let kind = ShelfFruit(detectorLabel: fruit.rawValue) else { return nil }
        let box = CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84)
        let confidence = scan.fruitScores[fruit] ?? 0
        return (ShelfCandidate(box: box, label: kind.rawValue, confidence: confidence), scan.result)
    }
}
