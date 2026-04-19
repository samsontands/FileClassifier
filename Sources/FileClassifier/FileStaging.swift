import Foundation

/// Holds renamed copies of files in a per-session temp directory so the
/// originals are never touched. Items live here until the app quits
/// (or the user clicks Clear) — long enough to drag them out to Finder.
enum FileStaging {
    static let directory: URL = {
        let pid = ProcessInfo.processInfo.processIdentifier
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileClassifier-\(pid)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Copy `src` into the staging dir under `newName`. Returns the new URL.
    /// Appends -1, -2, … if the name already exists in staging.
    static func stage(src: URL, as newName: String) throws -> URL {
        let dst = uniquify(directory.appendingPathComponent(newName))
        try FileManager.default.copyItem(at: src, to: dst)
        return dst
    }

    static func remove(_ url: URL) {
        guard url.path.hasPrefix(directory.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func uniquify(_ url: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { return url }

        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent

        var i = 1
        while true {
            let candidate = ext.isEmpty
                ? dir.appendingPathComponent("\(stem)-\(i)")
                : dir.appendingPathComponent("\(stem)-\(i)").appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
