import Foundation
import FileClassifierCore

/// Result of an in-place rename (Finder right-click Service or `--rename` CLI).
struct InPlaceRenameResult {
    let source: URL
    let renamed: URL?
    let docType: DocType
    let personName: String
    let nameSource: NameSource
    let needsManualName: Bool
    let error: String?

    var succeeded: Bool { renamed != nil && error == nil }
}

/// Renames files in their existing directory — used by the Finder right-click
/// Service and the `--rename` CLI flag. The drop-zone flow in the main window
/// still uses staging (copy, don't touch original); this path explicitly
/// renames in place because the user opted in.
enum FileRenamer {
    static func renameInPlace(url: URL) -> InPlaceRenameResult {
        let ext = url.pathExtension.lowercased()
        guard FileProcessor.supportedExtensions.contains(ext) else {
            return InPlaceRenameResult(
                source: url, renamed: nil, docType: .document,
                personName: "", nameSource: .none,
                needsManualName: false,
                error: "Unsupported file type: .\(ext)"
            )
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return InPlaceRenameResult(
                source: url, renamed: nil, docType: .document,
                personName: "", nameSource: .none,
                needsManualName: false,
                error: "File not found: \(url.path)"
            )
        }
        do {
            let text = try OCRService.extractText(from: url)
            let hit = DocumentClassifier.classify(text)
            let nameHit = NameExtractor.extract(from: text)
            let newName = RenameService.buildFilename(
                name: nameHit.name, docType: hit.type, ext: url.pathExtension
            )
            let parent = url.deletingLastPathComponent()
            let dest = uniqueURL(in: parent, named: newName)
            // If computed name equals existing name, nothing to do.
            if dest.lastPathComponent == url.lastPathComponent {
                return InPlaceRenameResult(
                    source: url, renamed: url, docType: hit.type,
                    personName: nameHit.name, nameSource: nameHit.source,
                    needsManualName: RenameService.needsManualName(newName),
                    error: nil
                )
            }
            try FileManager.default.moveItem(at: url, to: dest)
            return InPlaceRenameResult(
                source: url, renamed: dest, docType: hit.type,
                personName: nameHit.name, nameSource: nameHit.source,
                needsManualName: RenameService.needsManualName(dest.lastPathComponent),
                error: nil
            )
        } catch {
            return InPlaceRenameResult(
                source: url, renamed: nil, docType: .document,
                personName: "", nameSource: .none,
                needsManualName: false,
                error: String(describing: error)
            )
        }
    }

    /// Avoids clobbering an existing file: appends `-1`, `-2`, ... before the
    /// extension until a free name is found.
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
}
