// Sources/ShortsCastCapture/CLIOptions.swift
import Foundation
import CoreGraphics

public enum CLIParseError: Error, Equatable {
    case missingRequired(String)
    case badValue(String)
    case conflictingTargets
}

public struct CLIOptions: Equatable {
    public var seconds: Double
    public var out: String
    public var displayIndex: Int?
    public var windowQuery: String?
    public var region: CGRect?
    public var runDirect: Bool

    public static func parse(_ args: [String]) throws -> CLIOptions {
        var seconds: Double?
        var out: String?
        var displayIndex: Int?
        var windowQuery: String?
        var region: CGRect?
        var runDirect = false

        var i = 0
        func nextValue(_ flag: String) throws -> String {
            i += 1
            guard i < args.count else { throw CLIParseError.badValue(flag) }
            return args[i]
        }

        while i < args.count {
            let a = args[i]
            switch a {
            case "--seconds":
                guard let v = Double(try nextValue(a)) else { throw CLIParseError.badValue(a) }
                seconds = v
            case "--out":
                out = try nextValue(a)
            case "--display":
                guard let v = Int(try nextValue(a)) else { throw CLIParseError.badValue(a) }
                displayIndex = v
            case "--window":
                windowQuery = try nextValue(a)
            case "--rect":
                let parts = try nextValue(a).split(separator: ",").map { Double($0) }
                guard parts.count == 4, !parts.contains(where: { $0 == nil }) else {
                    throw CLIParseError.badValue(a)
                }
                region = CGRect(x: parts[0]!, y: parts[1]!, width: parts[2]!, height: parts[3]!)
            case "--direct":
                runDirect = true
            default:
                throw CLIParseError.badValue(a)
            }
            i += 1
        }

        let targetCount = [displayIndex != nil, windowQuery != nil, region != nil].filter { $0 }.count
        if targetCount > 1 { throw CLIParseError.conflictingTargets }
        guard let s = seconds else { throw CLIParseError.missingRequired("--seconds") }
        guard let o = out else { throw CLIParseError.missingRequired("--out") }

        return CLIOptions(seconds: s, out: o, displayIndex: displayIndex,
                          windowQuery: windowQuery, region: region, runDirect: runDirect)
    }
}
