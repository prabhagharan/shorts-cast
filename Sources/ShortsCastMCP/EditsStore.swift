import Foundation
import ShortsCastEditor

/// Reads/writes the bundle's project.json (ProjectEdits) — the same file the GUI editor
/// uses — so agent edits, export, and the app all agree.
public enum EditsStore {
    private static func url(_ bundle: URL) -> URL { bundle.appendingPathComponent("project.json") }

    public static func read(_ bundle: URL) -> ProjectEdits {
        guard let data = try? Data(contentsOf: url(bundle)),
              let edits = try? JSONDecoder().decode(ProjectEdits.self, from: data) else {
            return RecordingSessionStore.defaultEdits()
        }
        return edits
    }

    public static func write(_ edits: ProjectEdits, to bundle: URL) throws {
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(edits)
        try data.write(to: url(bundle))
    }
}
