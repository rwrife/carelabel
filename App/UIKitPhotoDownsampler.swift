import UIKit
import CoreGraphics

/// UIKit-backed photo downsampler enforcing the CareKit promise
/// (`CarePhotoLimits.maximumPhotoDimensionPoints`): the longest edge of any
/// imported image is at most the cap, and the result is re-encoded as JPEG.
/// Lives in the app target so the CareStore package stays UIKit-free and
/// Linux-testable (issue #4).
struct UIKitPhotoDownsampler: PhotoDownsampler {
    func downscale(imageData: Data, maximumDimension: Int) throws -> Data {
        guard let image = UIImage(data: imageData) else {
            throw DownsamplerError.undecodableImage
        }
        return try Self.downscale(image: image, maximumDimension: maximumDimension)
    }

    static func downscale(image: UIImage, maximumDimension: Int) throws -> Data {
        let pixelSize = image.size
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            throw DownsamplerError.emptyImage
        }
        let longestEdge = max(pixelSize.width, pixelSize.height)
        let scale = longestEdge > CGFloat(maximumDimension)
            ? CGFloat(maximumDimension) / longestEdge
            : 1.0
        let target = CGSize(
            width: (pixelSize.width * scale).rounded(),
            height: (pixelSize.height * scale).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1  // target size IS the pixel size after downscale
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else {
            throw DownsamplerError.encodingFailed
        }
        return jpeg
    }

    enum DownsamplerError: Error {
        case undecodableImage
        case emptyImage
        case encodingFailed
    }
}
