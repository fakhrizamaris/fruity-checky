import UIKit

extension UIImage {
    /// Redraws the image upright (no EXIF rotation left) with the longest side at most `maxDimension`.
    /// Keeps memory low and lets Vision read the pixels in the right orientation.
    func normalized(maxDimension: CGFloat = 1024) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return self }
        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
