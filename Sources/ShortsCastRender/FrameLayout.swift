import Foundation
import CoreGraphics

public enum FrameLayout {
    /// The centered, aspect-preserving rect the screen content occupies inside the export frame.
    public static func contentRect(exportSize: CGSize, paddingFraction: CGFloat) -> CGRect {
        let p = min(max(paddingFraction, 0), 0.49)
        let scale = 1 - 2 * p
        let w = exportSize.width * scale
        let h = exportSize.height * scale
        return CGRect(x: (exportSize.width - w) / 2, y: (exportSize.height - h) / 2, width: w, height: h)
    }
}
