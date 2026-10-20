import CoreGraphics
import CoreVideo
import Vision

/// Finds separate fruits in a photo with Vision's class-agnostic foreground instance mask
/// (on-device, no training). Returns normalized boxes (0...1, top-left origin), left to right.
/// An empty array means "no separate objects found": callers should use the whole photo.
struct ForegroundFruitDetector: Sendable {
    /// Ignore specks smaller than this fraction of the photo.
    var minAreaFraction: CGFloat = 0.02
    var maxObjects = 8

    func regions(in image: CGImage) async throws -> [CGRect] {
        let minArea = minAreaFraction
        let maxCount = maxObjects
        return try await Task.detached(priority: .userInitiated) {
            try Self.detect(in: image, minArea: minArea, maxCount: maxCount)
        }.value
    }

    private static func detect(in image: CGImage, minArea: CGFloat, maxCount: Int) throws -> [CGRect] {
        let request = VNGenerateForegroundInstanceMaskRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let observation = request.results?.first else { return [] }

        let boxes = splitByColour(mask: observation.instanceMask, image: image)
            .filter { $0.width * $0.height >= minArea }
            .sorted { $0.width * $0.height > $1.width * $1.height }
            .prefix(maxCount)
        return boxes.sorted { $0.minX < $1.minX }
    }

    /// Vision often merges touching fruits into one instance. Inside each instance, pixels are grouped
    /// into green vs warm (yellow/orange/brown) and each connected group of a colour becomes its own box,
    /// so an unripe and a ripe fruit side by side get separate boxes. An instance is only split when
    /// both colours are substantial; otherwise its plain bounding box is kept.
    static func splitByColour(mask: CVPixelBuffer, image: CGImage, minShare: Double = 0.15) -> [CGRect] {
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let rgba = { context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return context.data }()
        else { return boundingBoxes(of: mask) }
        let pixels = rgba.assumingMemoryBound(to: UInt8.self)

        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask)?.assumingMemoryBound(to: UInt8.self) else { return [] }
        let stride = CVPixelBufferGetBytesPerRow(mask)

        // Label per pixel: 0 background, otherwise instance id * 2 + (isGreen ? 1 : 0).
        var labels = [Int](repeating: 0, count: width * height)
        var counts: [UInt8: (green: Int, warm: Int)] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let id = base[y * stride + x]
                guard id != 0 else { continue }
                let i = (y * width + x) * 4
                let green = isGreen(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2])
                labels[y * width + x] = Int(id) * 2 + (green ? 1 : 0)
                var c = counts[id] ?? (0, 0)
                if green { c.green += 1 } else { c.warm += 1 }
                counts[id] = c
            }
        }

        // Instances whose colours are not both substantial keep a single label.
        let minPixels = max(8, Int(Double(width * height) * 0.005))
        var splittable: Set<UInt8> = []
        for (id, c) in counts {
            let total = Double(c.green + c.warm)
            if Double(c.green) / total >= minShare, Double(c.warm) / total >= minShare,
               c.green >= minPixels, c.warm >= minPixels { splittable.insert(id) }
        }
        for i in labels.indices where labels[i] != 0 && !splittable.contains(UInt8(labels[i] / 2)) {
            labels[i] = (labels[i] / 2) * 2
        }

        // Connected components (4-neighbour) per label; tiny specks are ignored.
        var seen = [Bool](repeating: false, count: width * height)
        var boxes: [CGRect] = []
        var queue: [Int] = []
        for start in labels.indices where labels[start] != 0 && !seen[start] {
            let label = labels[start]
            var (minX, minY, maxX, maxY, size) = (width, height, 0, 0, 0)
            queue = [start]
            seen[start] = true
            var head = 0
            while head < queue.count {
                let p = queue[head]; head += 1
                let x = p % width, y = p / width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y); size += 1
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let n = ny * width + nx
                    if !seen[n], labels[n] == label { seen[n] = true; queue.append(n) }
                }
            }
            // A split part must be big enough to be a fruit; unsplit instances keep any size.
            guard size >= minPixels || !splittable.contains(UInt8(label / 2)) else { continue }
            boxes.append(CGRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
                                width: CGFloat(maxX - minX + 1) / CGFloat(width),
                                height: CGFloat(maxY - minY + 1) / CGFloat(height)))
        }
        return boxes
    }

    /// Green peel: hue 75...170 degrees with enough colour and brightness. Everything else counts as warm.
    static func isGreen(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        let (rf, gf, bf) = (Double(r) / 255, Double(g) / 255, Double(b) / 255)
        let maxC = max(rf, gf, bf), minC = min(rf, gf, bf)
        let delta = maxC - minC
        guard maxC >= 0.2, delta / maxC >= 0.25 else { return false }
        var hue: Double
        if maxC == rf { hue = ((gf - bf) / delta).truncatingRemainder(dividingBy: 6) }
        else if maxC == gf { hue = (bf - rf) / delta + 2 }
        else { hue = (rf - gf) / delta + 4 }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (75...170).contains(hue)
    }

    /// One normalized box per instance id (0 is background) in a OneComponent8 mask.
    static func boundingBoxes(of mask: CVPixelBuffer) -> [CGRect] {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask)?.assumingMemoryBound(to: UInt8.self) else { return [] }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let stride = CVPixelBufferGetBytesPerRow(mask)
        var extents: [UInt8: (minX: Int, minY: Int, maxX: Int, maxY: Int)] = [:]

        for y in 0..<height {
            for x in 0..<width {
                let id = base[y * stride + x]
                guard id != 0 else { continue }
                if let e = extents[id] {
                    extents[id] = (min(e.minX, x), min(e.minY, y), max(e.maxX, x), max(e.maxY, y))
                } else {
                    extents[id] = (x, y, x, y)
                }
            }
        }
        return extents.values.map { e in
            CGRect(
                x: CGFloat(e.minX) / CGFloat(width),
                y: CGFloat(e.minY) / CGFloat(height),
                width: CGFloat(e.maxX - e.minX + 1) / CGFloat(width),
                height: CGFloat(e.maxY - e.minY + 1) / CGFloat(height)
            )
        }
    }
}
