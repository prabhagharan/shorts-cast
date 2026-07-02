import Foundation
import CoreGraphics

public enum StartArgError: Error, Equatable { case conflictingTargets, badRegion }

/// Parses `start_recording` arguments into the mutually-exclusive target trio that
/// `TargetResolver.resolve` consumes. Mirrors CLIOptions' conflict rules.
public struct StartArgs: Equatable {
    public var displayIndex: Int?
    public var windowQuery: String?
    public var region: CGRect?

    public static func parse(_ args: JSONValue?) throws -> StartArgs {
        var out = StartArgs()
        if let t = args?["target"]?.stringValue, !t.isEmpty { out.windowQuery = t }
        if let d = args?["display"]?.intValue { out.displayIndex = d }
        if let r = args?["region"] {
            guard let x = r["x"]?.doubleValue, let y = r["y"]?.doubleValue,
                  let w = r["w"]?.doubleValue, let h = r["h"]?.doubleValue else {
                throw StartArgError.badRegion
            }
            out.region = CGRect(x: x, y: y, width: w, height: h)
        }
        let count = [out.displayIndex != nil, out.windowQuery != nil, out.region != nil].filter { $0 }.count
        if count > 1 { throw StartArgError.conflictingTargets }
        return out
    }
}
