// Sources/ShortsCastRender/ExportJob.swift
import Foundation
import ShortsCastCore
import ShortsCastCapture

public enum ExportJob {
    public static func run(bundleURL: URL, formats: [OutputFormat], style: RenderStyle,
                           settings: AutoDirectorSettings, outDir: URL,
                           overrides: [SegmentOverride] = []) throws -> [URL] {
        let (eventLog, _, rawVideoURL) = try ProjectBundle.read(bundleURL)
        let result = Director(settings: settings).direct(log: eventLog, overrides: overrides)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let base = bundleURL.deletingPathExtension().lastPathComponent
        var written: [URL] = []
        for format in formats {
            let safe = format.name.replacingOccurrences(of: ":", with: "x")
            let outURL = outDir.appendingPathComponent("\(base)-\(safe).mp4")
            try VideoExporter.export(rawVideoURL: rawVideoURL, result: result, format: format,
                                     style: style, screenSize: eventLog.screenSize, to: outURL)
            written.append(outURL)
        }
        return written
    }
}
