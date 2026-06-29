// Sources/ShortsCastRender/ExportOptions.swift
import Foundation
import ShortsCastCore

public enum ExportParseError: Error, Equatable {
    case missingRequired(String)
    case badValue(String)
    case unknownFormat(String)
}

public struct ExportOptions: Equatable {
    public var bundle: String
    public var formats: [String]
    public var out: String
    public var stylePath: String?

    public static func parse(_ args: [String]) throws -> ExportOptions {
        var bundle: String?
        var formats: [String]?
        var out: String?
        var stylePath: String?

        var i = 0
        func nextValue(_ flag: String) throws -> String {
            i += 1
            guard i < args.count else { throw ExportParseError.badValue(flag) }
            return args[i]
        }
        while i < args.count {
            let a = args[i]
            switch a {
            case "--format":
                let parts = try nextValue(a).split(separator: ",").map(String.init)
                guard !parts.isEmpty else { throw ExportParseError.badValue(a) }
                formats = parts
            case "--out":
                out = try nextValue(a)
            case "--style":
                stylePath = try nextValue(a)
            default:
                if a.hasPrefix("--") { throw ExportParseError.badValue(a) }
                if bundle == nil { bundle = a } else { throw ExportParseError.badValue(a) }
            }
            i += 1
        }

        guard let b = bundle else { throw ExportParseError.missingRequired("bundle") }
        guard let f = formats else { throw ExportParseError.missingRequired("--format") }
        guard let o = out else { throw ExportParseError.missingRequired("--out") }
        return ExportOptions(bundle: b, formats: f, out: o, stylePath: stylePath)
    }

    public static func resolveFormats(_ names: [String]) throws -> [OutputFormat] {
        try names.map { name in
            guard let f = OutputFormat.all.first(where: { $0.name == name }) else {
                throw ExportParseError.unknownFormat(name)
            }
            return f
        }
    }
}
