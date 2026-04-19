import Foundation

/// One row of the rename history — what a file was called before, what it's
/// called now, when the rename happened. Persisted to disk so the user can
/// revert after quitting and relaunching the app.
struct RenameRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    /// Path at the time of rename. Informational only; the revert logic
    /// prefers to work against the CURRENT location of the file (see below).
    let originalPath: String
    let originalName: String
    let renamedPath: String
    let renamedName: String
}

enum HistoryError: LocalizedError {
    case notFound
    case fileMissing(String)

    var errorDescription: String? {
        switch self {
        case .notFound:            return "No rename record found for this file."
        case .fileMissing(let p):  return "File no longer exists at \(p)."
        }
    }
}

/// Durable rename log.
///
/// Stored at `~/Library/Application Support/FileClassifier/rename-history.json`.
/// Newest entries first. Capped so the file doesn't grow forever.
///
/// The revert operation intentionally renames back to the ORIGINAL NAME in the
/// file's CURRENT directory — not the original directory — because the user
/// may have moved the file between rename and revert. That keeps behaviour
/// predictable: "give me back the old name, wherever this file now lives."
enum RenameHistory {
    private static let historyCap = 500
    private static let queue = DispatchQueue(label: "fileclassifier.history")

    private static var storeURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("FileClassifier", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rename-history.json")
    }

    // MARK: - Writes

    static func record(original: URL, renamed: URL) {
        queue.sync {
            var list = readUnlocked()
            let rec = RenameRecord(
                id: UUID(),
                timestamp: Date(),
                originalPath: original.path,
                originalName: original.lastPathComponent,
                renamedPath: renamed.path,
                renamedName: renamed.lastPathComponent
            )
            list.insert(rec, at: 0)
            if list.count > historyCap { list = Array(list.prefix(historyCap)) }
            writeUnlocked(list)
        }
    }

    static func clear() {
        queue.sync { writeUnlocked([]) }
    }

    static func removeRecord(id: UUID) {
        queue.sync {
            var list = readUnlocked()
            list.removeAll { $0.id == id }
            writeUnlocked(list)
        }
    }

    // MARK: - Reads

    static func all() -> [RenameRecord] {
        queue.sync { readUnlocked() }
    }

    static func lastRecord() -> RenameRecord? {
        all().first
    }

    /// Find the most recent record whose *current* filename matches.
    /// Lets the user point at any file on disk and ask "was this renamed?"
    static func record(forRenamedPath path: URL) -> RenameRecord? {
        let std = path.standardizedFileURL.path
        let byPath = all().first { $0.renamedPath == std }
        if byPath != nil { return byPath }
        // If the user moved the file, fall back to matching by basename.
        let name = path.lastPathComponent
        return all().first { $0.renamedName == name }
    }

    // MARK: - Revert

    /// Undo a rename. Moves the file back to its original name in its CURRENT
    /// directory, and removes the record from history on success.
    static func revert(id: UUID) -> Result<URL, Error> {
        queue.sync {
            var list = readUnlocked()
            guard let idx = list.firstIndex(where: { $0.id == id }) else {
                return .failure(HistoryError.notFound)
            }
            let rec = list[idx]
            let current = resolveCurrentURL(for: rec)
            guard let current = current else {
                return .failure(HistoryError.fileMissing(rec.renamedPath))
            }
            let dir = current.deletingLastPathComponent()
            let dest = uniqueURL(in: dir, named: rec.originalName)
            do {
                try FileManager.default.moveItem(at: current, to: dest)
                list.remove(at: idx)
                writeUnlocked(list)
                return .success(dest)
            } catch {
                return .failure(error)
            }
        }
    }

    /// Revert a record looked up by the file's current URL (either the
    /// original `renamedPath` or a matching basename if the file was moved).
    static func revert(fileAt url: URL) -> Result<URL, Error> {
        guard let rec = record(forRenamedPath: url) else {
            return .failure(HistoryError.notFound)
        }
        return revert(id: rec.id)
    }

    static func revertLast() -> Result<URL, Error> {
        guard let last = lastRecord() else { return .failure(HistoryError.notFound) }
        return revert(id: last.id)
    }

    // MARK: - Internals

    /// Best guess at where the renamed file now lives. Tries the stored
    /// renamedPath first; falls back to searching the original directory
    /// for the renamed filename in case the user moved it.
    private static func resolveCurrentURL(for rec: RenameRecord) -> URL? {
        let fm = FileManager.default
        let stored = URL(fileURLWithPath: rec.renamedPath)
        if fm.fileExists(atPath: stored.path) { return stored }
        let fallback = URL(fileURLWithPath: rec.originalPath)
            .deletingLastPathComponent()
            .appendingPathComponent(rec.renamedName)
        if fm.fileExists(atPath: fallback.path) { return fallback }
        return nil
    }

    private static func uniqueURL(in dir: URL, named: String) -> URL {
        let dest = dir.appendingPathComponent(named)
        if !FileManager.default.fileExists(atPath: dest.path) { return dest }
        let ns = named as NSString
        let stem = ns.deletingPathExtension
        let ext = ns.pathExtension
        var i = 1
        while true {
            let candidate = ext.isEmpty
                ? "\(stem)-\(i)"
                : "\(stem)-\(i).\(ext)"
            let url = dir.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            i += 1
        }
    }

    private static func readUnlocked() -> [RenameRecord] {
        let url = storeURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RenameRecord].self, from: data)) ?? []
    }

    private static func writeUnlocked(_ list: [RenameRecord]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
