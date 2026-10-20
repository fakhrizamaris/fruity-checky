import CoreGraphics
import Foundation
import Testing
@testable import CekBuah

struct RipeNetModelTests {
    private func image() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.95, green: 0.8, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 50, y: 100, width: 200, height: 100))
        return try #require(context.makeImage())
    }

    @Test func modelIsBundled() {
        #expect(RipeNetClassifier.isAvailable)
    }

    @Test func producesThreeStageProbabilitiesAndExtras() async throws {
        let result = try await RipeNetClassifier().classify(image: image(), fruit: .banana)
        #expect(result.ranked.count == 3)
        #expect(abs(result.ranked.map(\.probability).reduce(0, +) - 1) < 0.02)
        #expect(result.modelName == "RipeNetV2")
        let extras = try #require(result.extras)
        #expect(RipeNetClassifier.fruitLabels.contains(extras.fruitLabel))
        #expect(!result.isDemo)
    }

    @Test func fruitHeadCoversAllSixFruits() async throws {
        let scan = try await RipeNetClassifier.shared.scan(image: image())
        #expect(Set(scan.fruitScores.keys) == Set(Fruit.allCases))
        #expect(abs(scan.fruitScores.values.reduce(0, +) - 1) < 0.02)
    }

    @Test func choiceOnlyAppliesInTesterMode() throws {
        let defaults = try #require(UserDefaults(suiteName: "RipeNetModelTests"))
        defaults.removePersistentDomain(forName: "RipeNetModelTests")
        defaults.set(RipenessModelChoice.perFruit.rawValue, forKey: RipenessModelChoice.key)
        #expect(RipenessModelChoice.current(in: defaults) == .standard)
        defaults.set(true, forKey: SettingsKey.testerMode)
        #expect(RipenessModelChoice.current(in: defaults) == .perFruit)
    }
}
