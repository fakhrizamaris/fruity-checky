@preconcurrency import AVFoundation
import CoreImage

enum CameraError: LocalizedError {
    case unavailable
    case busy
    case noData

    var errorDescription: String? {
        switch self {
        case .unavailable: "Kamera tidak tersedia di perangkat ini."
        case .busy: "Kamera masih memproses foto sebelumnya."
        case .noData: "Foto gagal diambil. Coba lagi."
        }
    }
}

/// Owns the AVCaptureSession. All session work runs on one private serial queue,
/// which is why the mutable state below is safe (`@unchecked Sendable`).
final class CameraService: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "CekBuah.camera")
    private let frameQueue = DispatchQueue(label: "CekBuah.camera.frames")
    private let ciContext = CIContext()
    private var isConfigured = false
    private var photoContinuation: CheckedContinuation<Data, Error>?

    /// Live frames for scanning: the centre square, upright, at most `frameSide` px. Set before `start()`.
    /// Called on a background queue at most `framesPerSecond` times per second.
    var onFrame: (@Sendable (CGImage) -> Void)?
    var framesPerSecond: Double = 3
    /// Side of the live frame. 448 is enough when one fruit fills the guide square (single-fruit scan); the
    /// shopping scan crops a fruit out of the frame, so it asks for more pixels to keep that crop sharp.
    var frameSide: CGFloat = 448
    private var lastFrame: CFAbsoluteTime = 0

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try configureIfNeeded()
                    if !session.isRunning { session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Returns the captured photo as encoded image data (HEIC/JPEG with orientation).
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard photoContinuation == nil else {
                    continuation.resume(throwing: CameraError.busy)
                    return
                }
                photoContinuation = continuation
                if let connection = photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90 // app is portrait only
                }
                photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw CameraError.unavailable
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .balanced

        // Live scanning is optional: the photo flow still works if this output cannot be added.
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
            session.addOutput(videoOutput)
            if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90 // portrait frames, like the preview
            }
        }
        isConfigured = true
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let result: Result<Data, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(CameraError.noData)
        }

        queue.async { [self] in
            let continuation = photoContinuation
            photoContinuation = nil
            continuation?.resume(with: result)
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let onFrame else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrame >= 1 / framesPerSecond,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now

        // Centre square (the guide frame), downscaled to `frameSide`.
        let image = CIImage(cvPixelBuffer: pixels)
        let side = min(image.extent.width, image.extent.height)
        let square = CGRect(x: image.extent.midX - side / 2, y: image.extent.midY - side / 2, width: side, height: side)
        let scale = min(1, frameSide / side)
        let cropped = image.cropped(to: square)
            .transformed(by: CGAffineTransform(translationX: -square.minX, y: -square.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let frame = ciContext.createCGImage(cropped, from: cropped.extent) else { return }
        onFrame(frame)
    }
}
