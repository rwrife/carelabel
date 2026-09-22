import UIKit
import Foundation

// Issue #5: deterministic photo source for UI tests.
//
// The simulator has no camera and an empty photo library, so under the
// `-ui-testing` launch argument the editor exposes an "attach test photo"
// control feeding the SAME `PhotoStore.importPhoto` seam the camera and
// library-picker paths use. This proves attach -> downscale -> display ->
// persist end to end on CI; the real camera/library UI is verified on
// device.

enum TestPhotoSource {
    static let uiTestingFlag = "-ui-testing"

    @MainActor
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingFlag)
    }

    @MainActor
    static func makeTestPhotoData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 160))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
            let text = "CARE LABEL TEST" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 20),
                .foregroundColor: UIColor.white,
            ]
            text.draw(at: CGPoint(x: 16, y: 66), withAttributes: attributes)
        }
        // Deterministic renderer output always encodes; fall back to empty
        // (PhotoStore then rejects it) rather than crashing.
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
}
