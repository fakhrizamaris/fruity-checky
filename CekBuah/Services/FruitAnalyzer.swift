import CoreGraphics

/// One fruit found in the photo, with its own ripeness result.
struct DetectedFruit: Identifiable, Sendable {
    /// 1-based, left to right; shown on the photo.
    let number: Int
    /// Normalized box (0...1, top-left origin). The whole photo when nothing was separated.
    let box: CGRect
    /// Fruit the ripeness was judged as: the user's pick, or the suggestion after "Ganti".
    var fruit: Fruit
    var result: ClassificationResult
    /// Fruit the user originally picked on the home screen.
    var pickedFruit: Fruit
    var identity: FruitIdentity = .unavailable
    /// What the user did with the identity warning; nil while unanswered.
    var identityAction: IdentityAction?

    init(number: Int, box: CGRect, fruit: Fruit, result: ClassificationResult,
         identity: FruitIdentity = .unavailable, identityAction: IdentityAction? = nil) {
        self.number = number
        self.box = box
        self.fruit = fruit
        self.result = result
        self.pickedFruit = fruit
        self.identity = identity
        self.identityAction = identityAction
    }

    /// Warning to show: the check found a problem and the user has not answered yet.
    var needsIdentityNotice: Bool {
        identityAction == nil && (identity.verdict == .looksLike || identity.verdict == .unrecognized)
    }

    var id: Int { number }
    var coversWholePhoto: Bool { box.width > 0.98 && box.height > 0.98 }
}

/// Three steps: find each fruit (Vision), check its identity (Vision), then classify each crop (Core ML or mock).
struct FruitAnalyzer: Sendable {
    var detector = ForegroundFruitDetector()
    let classifier: any FruitClassifying
    var identifier: any FruitIdentifying = RipeNetClassifier.shared
    var identityThreshold = FruitIdentity.defaultThreshold

    static let wholePhoto = CGRect(x: 0, y: 0, width: 1, height: 1)

    func analyze(image: CGImage, fruit: Fruit) async throws -> [DetectedFruit] {
        // Detection is a helper: if it fails (e.g. unsupported on Simulator), classify the whole photo.
        let found = (try? await detector.regions(in: image)) ?? []
        let boxes = found.isEmpty ? [Self.wholePhoto] : found

        var items: [DetectedFruit] = []
        for (index, box) in boxes.enumerated() {
            let crop = Self.squareCrop(of: image, around: box) ?? image
            // The identity check only warns: if it fails, the ripeness result is still shown.
            let identity = (try? await identifier.scores(for: crop)).map {
                FruitIdentity.assess(scores: $0, picked: fruit, threshold: identityThreshold)
            } ?? .unavailable
            let result = try await classifier.classify(image: crop, fruit: fruit)
            items.append(DetectedFruit(number: index + 1, box: box, fruit: fruit, result: result, identity: identity))
        }
        return items
    }

    /// One fruit per photo, no fruit picked beforehand: recognise the fruit in the centre square
    /// (the camera's guide frame), then judge its ripeness. Unknown fruit falls back to `fallback`
    /// and is marked unrecognised, so the screen asks the user to confirm.
    func analyzeSingle(image: CGImage, fallback: Fruit = .banana) async throws -> DetectedFruit {
        let box = Self.centerSquare(of: image)
        let crop = Self.squareCrop(of: image, around: box, padding: 0) ?? image
        let scores = (try? await identifier.scores(for: crop)) ?? [:]
        let recognition = FruitIdentity.recognize(scores: scores, threshold: identityThreshold)
        let fruit = recognition.fruit ?? fallback
        let result = try await classifier.classify(image: crop, fruit: fruit)
        return DetectedFruit(number: 1, box: box, fruit: fruit, result: result, identity: recognition.identity)
    }

    /// Normalized centre square of the photo (what the camera's guide frame shows).
    static func centerSquare(of image: CGImage) -> CGRect {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard width > 0, height > 0 else { return wholePhoto }
        let side = min(width, height)
        return CGRect(x: (width - side) / 2 / width, y: (height - side) / 2 / height,
                      width: side / width, height: side / height)
    }

    /// Judges one fruit again as another fruit (user tapped "Ganti ke ...").
    func reclassify(_ item: DetectedFruit, as fruit: Fruit, in image: CGImage) async throws -> DetectedFruit {
        let crop = Self.squareCrop(of: image, around: item.box) ?? image
        var updated = item
        updated.result = try await classifier.classify(image: crop, fruit: fruit)
        updated.fruit = fruit
        updated.identity = item.identity.reassessed(for: fruit, threshold: identityThreshold)
        updated.identityAction = .switched
        return updated
    }

    /// Crops a padded square around the box, so a long banana is not cut off by the
    /// model's centre crop and the input looks like the close-up training photos.
    static func squareCrop(of image: CGImage, around box: CGRect, padding: CGFloat = 0.08) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let pixelBox = CGRect(x: box.minX * width, y: box.minY * height,
                              width: box.width * width, height: box.height * height)
        let side = min(max(pixelBox.width, pixelBox.height) * (1 + padding * 2), min(width, height))
        var square = CGRect(x: pixelBox.midX - side / 2, y: pixelBox.midY - side / 2, width: side, height: side)
        // Keep the square inside the photo.
        square.origin.x = min(max(square.minX, 0), width - side)
        square.origin.y = min(max(square.minY, 0), height - side)
        return image.cropping(to: square.integral)
    }
}
