import CoreGraphics
import CoreVideo
import Testing
@testable import CekBuah

struct DetectionTests {
    /// 100x50 mask with instance 1 on the left and instance 2 on the right.
    private func makeMask() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 100, 50, kCVPixelFormatType_OneComponent8, nil, &buffer)
        let mask = try #require(buffer)
        CVPixelBufferLockBaseAddress(mask, [])
        let base = try #require(CVPixelBufferGetBaseAddress(mask)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(mask)
        for y in 0..<50 {
            for x in 0..<100 {
                base[y * stride + x] = (10..<30).contains(x) && (5..<45).contains(y) ? 1
                    : (60..<90).contains(x) && (10..<20).contains(y) ? 2 : 0
            }
        }
        CVPixelBufferUnlockBaseAddress(mask, [])
        return mask
    }

    @Test func boundingBoxPerInstance() throws {
        let boxes = ForegroundFruitDetector.boundingBoxes(of: try makeMask()).sorted { $0.minX < $1.minX }
        #expect(boxes.count == 2)
        #expect(boxes[0] == CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.80))
        #expect(boxes[1] == CGRect(x: 0.60, y: 0.20, width: 0.30, height: 0.20))
    }

    private func blankImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }

    @Test func squareCropStaysInsidePhoto() throws {
        let image = try blankImage(width: 1000, height: 500)
        // Tall box at the left edge: square must shift right instead of going outside.
        let crop = try #require(FruitAnalyzer.squareCrop(of: image, around: CGRect(x: 0, y: 0.1, width: 0.1, height: 0.8)))
        #expect(crop.width == crop.height)
        #expect(crop.height <= 500)
    }

    @Test func wholePhotoCropIsCentreSquare() throws {
        let image = try blankImage(width: 800, height: 600)
        let crop = try #require(FruitAnalyzer.squareCrop(of: image, around: FruitAnalyzer.wholePhoto))
        #expect(crop.width == 600 && crop.height == 600)
    }

    @Test func wholePhotoItemHasNoBox() {
        let result = DecisionRules.standard.evaluate([ClassPrediction(state: .ripe, probability: 0.9)])
        #expect(DetectedFruit(number: 1, box: FruitAnalyzer.wholePhoto, fruit: .banana, result: result).coversWholePhoto)
        #expect(!DetectedFruit(number: 1, box: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.5), fruit: .banana, result: result).coversWholePhoto)
    }
}

struct ColourSplitTests {
    /// One merged instance: left half green, right half yellow, both big.
    private func twoToneScene(rightIsYellow: Bool = true) throws -> (CVPixelBuffer, CGImage) {
        let (w, h) = (100, 50)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_OneComponent8, nil, &buffer)
        let mask = try #require(buffer)
        CVPixelBufferLockBaseAddress(mask, [])
        let base = try #require(CVPixelBufferGetBaseAddress(mask)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(mask)
        for y in 0..<h { for x in 0..<w { base[y * stride + x] = (5..<95).contains(x) && (5..<45).contains(y) ? 1 : 0 } }
        CVPixelBufferUnlockBaseAddress(mask, [])

        let context = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 50, height: h))
        context.setFillColor(rightIsYellow ? CGColor(red: 0.95, green: 0.8, blue: 0.1, alpha: 1)
                                           : CGColor(red: 0.2, green: 0.7, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 50, y: 0, width: 50, height: h))
        return (mask, try #require(context.makeImage()))
    }

    @Test func greenAndYellowFruitAreSeparated() throws {
        let (mask, image) = try twoToneScene()
        let boxes = ForegroundFruitDetector.splitByColour(mask: mask, image: image).sorted { $0.minX < $1.minX }
        #expect(boxes.count == 2)
        #expect(boxes[0].maxX <= 0.52)
        #expect(boxes[1].minX >= 0.48)
    }

    @Test func singleColourInstanceIsKept() throws {
        let (mask, image) = try twoToneScene(rightIsYellow: false)
        #expect(ForegroundFruitDetector.splitByColour(mask: mask, image: image).count == 1)
    }

    @Test func hueClassification() {
        #expect(ForegroundFruitDetector.isGreen(r: 60, g: 170, b: 60))
        #expect(!ForegroundFruitDetector.isGreen(r: 240, g: 200, b: 30))
        #expect(!ForegroundFruitDetector.isGreen(r: 90, g: 60, b: 30))
    }
}
