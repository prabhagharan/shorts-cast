import Foundation
import CoreGraphics

/// Maps a CameraState + output format to a crop rectangle in screen pixel space.
public enum VirtualCamera {
    /// Largest rect of the format's aspect ratio that fits inside the screen (resting crop).
    public static func baseCropSize(screen: CGSize, format: OutputFormat) -> CGSize {
        let a = format.aspectRatio
        let screenA = screen.width / screen.height
        if a <= screenA {
            // Output is narrower (or equal) than the screen → height-limited.
            return CGSize(width: screen.height * a, height: screen.height)
        } else {
            // Output is wider than the screen → width-limited.
            return CGSize(width: screen.width, height: screen.width / a)
        }
    }

    public static func cropRect(state: CameraState,
                                format: OutputFormat,
                                screen: CGSize) -> CGRect {
        let base = baseCropSize(screen: screen, format: format)
        let z = max(state.scale, 0.0001)
        var w = base.width / z
        var h = base.height / z
        w = min(w, screen.width)
        h = min(h, screen.height)

        var x = state.center.x - w / 2
        var y = state.center.y - h / 2
        x = min(max(x, 0), screen.width - w)
        y = min(max(y, 0), screen.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
