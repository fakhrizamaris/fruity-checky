import CoreGraphics
import Foundation
import Observation
import UIKit

/// Shelf scan: detect every fruit once, then judge ripeness per crop for kinds that have a model.
/// Changing the confidence threshold only re-filters the stored candidates; the detector does not run again.
@MainActor
@Observable
final class ShelfScanModel {
    enum Phase: Equatable {
        case detecting
        case done
        case failed(String)
    }

    let photo: CapturedPhoto
    private(set) var phase: Phase = .detecting
    private(set) var detectorName = ""
    private(set) var usesFallback = false
    private(set) var detections: [ShelfDetection] = []
    /// Ripeness per detection number; filled in progressively.
    private(set) var ripeness: [Int: ClassificationResult] = [:]
    /// Called when a fruit's ripeness arrives, so a fruit picked earlier gets its label in the basket.
    var onRipeness: (@MainActor (Int, ClassificationResult) -> Void)?

    var minConfidence = ShelfPostProcessing.defaultMinConfidence {
        didSet { if oldValue != minConfidence { refresh() } }
    }

    private var candidates: [ShelfCandidate] = []
    private var classifier: (any FruitClassifying)?
    private var ripenessTask: Task<Void, Never>?
    /// Crops judged at the same time; keeps memory and Neural Engine load steady on crowded shelves.
    private let maxConcurrentCrops = 4

    init(photo: CapturedPhoto) {
        self.photo = photo
    }

    var counts: [(fruit: ShelfFruit?, count: Int)] { ShelfPostProcessing.counts(detections) }

    func source(of item: ShelfDetection) -> BasketSource { .shelf(photoID: photo.id, number: item.number) }

    /// Basket entry for one box, with its crop as the thumbnail.
    func basketItem(for item: ShelfDetection) -> BasketItem {
        let crop = photo.image.cgImage.flatMap { FruitAnalyzer.squareCrop(of: $0, around: item.box) }
        return BasketItem(source: source(of: item), kind: item.fruit, result: ripeness[item.number],
                          thumbnail: crop.map { UIImage(cgImage: $0) })
    }

    func run(detector: any ShelfDetecting, classifier: any FruitClassifying) async {
        guard let image = photo.image.cgImage else {
            phase = .failed("Foto tidak dapat dibaca.")
            return
        }
        self.classifier = classifier
        detectorName = detector.name
        usesFallback = !(detector is CoreMLShelfDetector)
        phase = .detecting
        do {
            candidates = try await detector.candidates(in: image)
            phase = .done
            refresh()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func refresh() {
        detections = ShelfPostProcessing.finalize(candidates, minConfidence: minConfidence)
        ripeness = [:]
        ripenessTask?.cancel()
        guard let classifier, let image = photo.image.cgImage else { return }
        let jobs = detections.compactMap { item in item.fruit?.ripenessFruit.map { (item.number, item.box, $0) } }
        let limit = maxConcurrentCrops
        ripenessTask = Task { [weak self] in
            await withTaskGroup(of: (Int, ClassificationResult?).self) { group in
                var pending = jobs[...]
                func startNext() {
                    guard let (number, box, fruit) = pending.popFirst() else { return }
                    group.addTask {
                        let crop = FruitAnalyzer.squareCrop(of: image, around: box) ?? image
                        return (number, try? await classifier.classify(image: crop, fruit: fruit))
                    }
                }
                for _ in 0..<limit { startNext() }
                for await (number, result) in group {
                    guard !Task.isCancelled else { return }
                    if let result {
                        self?.ripeness[number] = result
                        self?.onRipeness?(number, result)
                    }
                    startNext()
                }
            }
        }
    }
}
