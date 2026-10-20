import SwiftUI

@MainActor
@Observable
final class CameraModel {
    enum Status: Equatable {
        case idle
        case running
        case capturing
        case denied
        case unavailable(String)
    }

    /// What the live scan currently sees in the guide frame. A preview only: the result screen
    /// judges the captured photo again.
    struct LiveScan: Equatable {
        /// Nil when no supported fruit is recognised with enough confidence.
        let fruit: Fruit?
        let state: RipenessState
    }

    private(set) var status: Status = .idle
    private(set) var liveScan: LiveScan?
    /// Minimum fruit-head probability to name the fruit in the live label.
    var confirmThreshold = FruitIdentity.defaultThreshold
    let service = CameraService()

    private let scanner = RipeNetClassifier.shared
    private var isScanning = false
    /// Last raw scan; the label only changes after two scans agree, so it does not flicker.
    private var lastScan: LiveScan?

    func start() async {
        guard await CameraService.requestAccess() else {
            status = .denied
            return
        }
        if RipeNetClassifier.isAvailable {
            service.onFrame = { [weak self] frame in
                Task { @MainActor in await self?.scan(frame) }
            }
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
        liveScan = nil
        lastScan = nil
    }

    /// Takes a photo and returns it upright and downscaled.
    func capture() async throws -> UIImage {
        status = .capturing
        defer { status = .running }
        let data = try await service.capturePhoto()
        guard let image = UIImage(data: data) else { throw CameraError.noData }
        return image.normalized()
    }

    /// Frames that arrive while a scan is running are dropped.
    private func scan(_ frame: CGImage) async {
        guard !isScanning, status == .running else { return }
        isScanning = true
        defer { isScanning = false }
        guard let scan = try? await scanner.scan(image: frame) else { return }
        let recognition = FruitIdentity.recognize(scores: scan.fruitScores, threshold: confirmThreshold)
        let current = LiveScan(fruit: recognition.identity.verdict == .match ? recognition.fruit : nil,
                               state: scan.result.state)
        if current == lastScan { liveScan = current }
        lastScan = current
    }
}
