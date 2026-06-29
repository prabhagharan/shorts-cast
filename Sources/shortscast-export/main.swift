import Foundation
import ShortsCastRender
import ShortsCastCore

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let options: ExportOptions
do {
    options = try ExportOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("""
    Usage: shortscast-export <bundle.shortscast> --format 9:16[,1:1,4:5,16:9] --out <dir> [--style <style.json>]
    Error: \(error)
    """)
}

let formats: [OutputFormat]
do {
    formats = try ExportOptions.resolveFormats(options.formats)
} catch {
    fail("Invalid --format: \(error). Valid names: \(OutputFormat.all.map { $0.name }.joined(separator: ", "))")
}

var style = RenderStyle.default
if let stylePath = options.stylePath {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: stylePath))
        style = try JSONDecoder().decode(RenderStyle.self, from: data)
    } catch {
        fail("Could not read --style \(stylePath): \(error)")
    }
}

do {
    let urls = try ExportJob.run(bundleURL: URL(fileURLWithPath: options.bundle),
                                 formats: formats, style: style,
                                 settings: AutoDirectorSettings(),
                                 outDir: URL(fileURLWithPath: options.out))
    for u in urls { print("Wrote \(u.path)") }
} catch {
    fail("Export failed: \(error)", code: 2)
}
