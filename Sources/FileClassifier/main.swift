import Foundation
import AppKit
import FileClassifierCore

/// Entry point. Dispatches between:
///   - `FileClassifier --classify <path>` — dry-run: prints what the
///     pipeline would rename the file to without moving anything.
///   - `FileClassifier --rename <path> [<path>...]` — in-place rename.
///     Same logic as the Finder Services menu entry, wrapped as a CLI so
///     Automator workflows / shell scripts can use it.
///   - GUI mode (no args): launches the SwiftUI drop-zone window.

let args = CommandLine.arguments

if args.count >= 3, args[1] == "--classify" {
    let url = URL(fileURLWithPath: args[2]).standardizedFileURL
    runClassifyCLI(for: url)
    exit(0)
}

if args.count >= 3, args[1] == "--rename" {
    let paths = Array(args.dropFirst(2))
    runRenameCLI(for: paths)
    exit(0)
}

FileClassifierApp.main()

// MARK: - CLI

/// Runs OCR + classification + name extraction, prints the result, and
/// DOES NOT copy/rename. Pure read-only — ideal for automated testing.
func runClassifyCLI(for url: URL) {
    let ext = url.pathExtension.lowercased()
    guard FileProcessor.supportedExtensions.contains(ext) else {
        print("unsupported file type: .\(ext)")
        exit(2)
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
        print("file not found: \(url.path)")
        exit(2)
    }

    do {
        let text = try OCRService.extractText(from: url)
        let hit = DocumentClassifier.classify(text)
        let nameHit = NameExtractor.extract(from: text)
        let newName = RenameService.buildFilename(
            name: nameHit.name, docType: hit.type, ext: ext
        )
        print("original:  \(url.lastPathComponent)")
        print("new name:  \(newName)")
        print("doc type:  \(hit.type.rawValue)\(hit.evidence.map { "  (matched '\($0)')" } ?? "")")
        print("person:    \(nameHit.name.isEmpty ? "—" : nameHit.name)  (via \(nameHit.source.rawValue))")
        let snippet = text.prefix(300).replacingOccurrences(of: "\n", with: " ⏎ ")
        print("ocr head:  \(snippet)\(text.count > 300 ? "..." : "")")
    } catch {
        print("error:     \(error)")
        exit(1)
    }
}

/// Renames each file in place and prints a one-line summary per file.
/// Same pipeline as the Finder right-click Services menu; exposed on the CLI
/// so shell scripts and Automator Quick Actions can call it for batches.
///
/// Exit code: 0 if every file was renamed, 1 if any failed.
func runRenameCLI(for paths: [String]) {
    var failures = 0
    for raw in paths {
        let url = URL(fileURLWithPath: raw).standardizedFileURL
        let r = FileRenamer.renameInPlace(url: url)
        if let err = r.error {
            print("FAIL  \(url.lastPathComponent): \(err)")
            failures += 1
            continue
        }
        let from = r.source.lastPathComponent
        let to = r.renamed?.lastPathComponent ?? "?"
        let tag = r.needsManualName ? "  [needs manual review]" : ""
        print("OK    \(from)  →  \(to)\(tag)")
    }
    exit(failures == 0 ? 0 : 1)
}
