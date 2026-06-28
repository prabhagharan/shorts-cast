import Foundation
import CoreGraphics

/// A social-media output target. `aspect` is the ratio shape; `exportSize` the pixel size.
public struct OutputFormat: Equatable, Codable {
    public let name: String
    public let aspect: CGSize
    public let exportSize: CGSize

    public init(name: String, aspect: CGSize, exportSize: CGSize) {
        self.name = name; self.aspect = aspect; self.exportSize = exportSize
    }

    /// width / height
    public var aspectRatio: CGFloat { aspect.width / aspect.height }

    public static let vertical9x16 = OutputFormat(
        name: "9:16", aspect: CGSize(width: 9, height: 16),
        exportSize: CGSize(width: 1080, height: 1920))
    public static let square1x1 = OutputFormat(
        name: "1:1", aspect: CGSize(width: 1, height: 1),
        exportSize: CGSize(width: 1080, height: 1080))
    public static let portrait4x5 = OutputFormat(
        name: "4:5", aspect: CGSize(width: 4, height: 5),
        exportSize: CGSize(width: 1080, height: 1350))
    public static let landscape16x9 = OutputFormat(
        name: "16:9", aspect: CGSize(width: 16, height: 9),
        exportSize: CGSize(width: 1920, height: 1080))

    public static let all: [OutputFormat] =
        [.vertical9x16, .square1x1, .portrait4x5, .landscape16x9]
}
