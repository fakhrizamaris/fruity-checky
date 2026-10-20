import CoreGraphics
import Foundation

/// Raw output of a shelf detector before filtering: one box with the detector's best label.
struct ShelfCandidate: Sendable, Equatable {
    /// Normalized box (0...1, top-left origin).
    let box: CGRect
    /// Detector label ("mango", ...). Empty when the detector does not know fruit kinds.
    let label: String
    /// 0...1.
    let confidence: Double
}

/// One fruit found on the shelf photo.
struct ShelfDetection: Identifiable, Sendable, Equatable {
    /// 1-based reading order (top row first, then left to right); shown on the photo.
    let number: Int
    /// Normalized box (0...1, top-left origin).
    let box: CGRect
    /// Nil when the detector found an object but not its kind (fallback detector or unknown label).
    let fruit: ShelfFruit?
    let confidence: Double

    var id: Int { number }
}

/// Pure post-processing shared by all detectors, so it can be unit tested without a model.
enum ShelfPostProcessing {
    /// Below this confidence a box is dropped. Testers can change it on the scan screen.
    static let defaultMinConfidence = 0.4
    /// Boxes overlapping more than this are the same fruit.
    static let defaultIoUThreshold = 0.5

    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> Double {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let inter = intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - inter
        return union > 0 ? Double(inter / union) : 0
    }

    /// Greedy non-maximum suppression across all labels. The Create ML model already suppresses
    /// duplicates per label; this also removes one fruit reported as two different kinds.
    static func suppress(_ candidates: [ShelfCandidate], iouThreshold: Double) -> [ShelfCandidate] {
        var kept: [ShelfCandidate] = []
        for candidate in candidates.sorted(by: { $0.confidence > $1.confidence }) where
            !kept.contains(where: { intersectionOverUnion($0.box, candidate.box) > iouThreshold }) {
            kept.append(candidate)
        }
        return kept
    }

    /// Top row first, then left to right. Boxes whose centres are closer than half a typical
    /// box height vertically count as one row, so a slightly crooked row still reads left to right.
    static func readingOrder(_ boxes: [CGRect]) -> [Int] {
        guard !boxes.isEmpty else { return [] }
        let heights = boxes.map(\.height).sorted()
        let tolerance = heights[heights.count / 2] / 2
        let byY = boxes.indices.sorted { boxes[$0].midY < boxes[$1].midY }

        var rows: [[Int]] = []
        for index in byY {
            if let last = rows.last?.last, boxes[index].midY - boxes[last].midY <= tolerance {
                rows[rows.count - 1].append(index)
            } else {
                rows.append([index])
            }
        }
        return rows.flatMap { row in row.sorted { boxes[$0].midX < boxes[$1].midX } }
    }

    static func finalize(_ candidates: [ShelfCandidate],
                         minConfidence: Double = defaultMinConfidence,
                         iouThreshold: Double = defaultIoUThreshold) -> [ShelfDetection] {
        let kept = suppress(candidates.filter { $0.confidence >= minConfidence }, iouThreshold: iouThreshold)
        return readingOrder(kept.map(\.box)).enumerated().map { position, index in
            let candidate = kept[index]
            return ShelfDetection(number: position + 1, box: candidate.box,
                                  fruit: ShelfFruit(detectorLabel: candidate.label), confidence: candidate.confidence)
        }
    }

    /// Count per fruit kind, most common first; unknown kinds last.
    static func counts(_ detections: [ShelfDetection]) -> [(fruit: ShelfFruit?, count: Int)] {
        Dictionary(grouping: detections, by: \.fruit)
            .map { (fruit: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if (lhs.fruit == nil) != (rhs.fruit == nil) { return rhs.fruit == nil }
                return lhs.count != rhs.count ? lhs.count > rhs.count
                    : (lhs.fruit?.rawValue ?? "") < (rhs.fruit?.rawValue ?? "")
            }
    }
}
