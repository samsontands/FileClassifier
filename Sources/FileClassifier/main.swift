import Foundation
import AppKit
import FileClassifierCore

/// Entry point. Dispatches between:
///   - `FileClassifier --classify <path>` — dry-run: prints what the
///     pipeline would rename the file to without moving anything.
///   - `FileClassifier --rename <path> [<path>...]` — in-place rename.
///     Same logic as the Finder Services menu entry, wrapped as a CLI so
///     Automator workflows / shell scripts can use it.
///   - `FileClassifier --revert <path> [<path>...]` — undo a previous
///     rename using the on-disk history.
///   - `FileClassifier --undo-last` — revert the most recent rename.
///   - `FileClassifier --history` — list recorded renames.
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

if args.count >= 3, args[1] == "--revert" {
    let paths = Array(args.dropFirst(2))
    runRevertCLI(for: paths)
    exit(0)
}

if args.count >= 2, args[1] == "--undo-last" {
    runUndoLastCLI()
    exit(0)
}

if args.count >= 2, args[1] == "--history" {
    runHistoryCLI()
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

/// Reverts one or more files using the on-disk rename history. Matches first
/// by full path, then by basename so the user can still undo even if they've
/// moved the file.
func runRevertCLI(for paths: [String]) {
    var failures = 0
    for raw in paths {
        let url = URL(fileURLWithPath: raw).standardizedFileURL
        switch RenameHistory.revert(fileAt: url) {
        case .success(let restored):
            print("OK    \(url.lastPathComponent)  →  \(restored.lastPathComponent)")
        case .failure(let err):
            print("FAIL  \(url.lastPathComponent): \(err.localizedDescription)")
            failures += 1
        }
    }
    exit(failures == 0 ? 0 : 1)
}

func runUndoLastCLI() {
    guard let last = RenameHistory.lastRecord() else {
        print("Nothing to undo — history is empty.")
        exit(1)
    }
    switch RenameHistory.revertLast() {
    case .success(let restored):
        print("OK    \(last.renamedName)  →  \(restored.lastPathComponent)")
        exit(0)
    case .failure(let err):
        print("FAIL  \(last.renamedName): \(err.localizedDescription)")
        exit(1)
    }
}

func runHistoryCLI() {
    let all = RenameHistory.all()
    if all.isEmpty {
        print("No renames recorded yet.")
        return
    }
    let fmt = ISO8601DateFormatter()
    print("Most recent first — \(all.count) entries")
    for r in all {
        print("\(fmt.string(from: r.timestamp))  \(r.originalName)  →  \(r.renamedName)")
    }
}
