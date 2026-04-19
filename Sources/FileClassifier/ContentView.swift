import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FileClassifierCore

struct ContentView: View {
    @State private var results: [ProcessingResult] = []
    @State private var isProcessing = false
    @State private var isTargeted = false
    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 12) {
            header
            dropZone
            resultsArea
            footer
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
        .onReceive(NotificationCenter.default.publisher(for: .fileClassifierDidRename)) { note in
            guard let list = note.userInfo?["results"] as? [InPlaceRenameResult] else { return }
            appendRenameResults(list)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("File Classifier").font(.headline)
                Text("Drop in to rename. Drag out to save.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isProcessing {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
            VStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 26, weight: .light))
                Text("Drop files or folders here")
                    .font(.subheadline)
                Button("Choose Files…", action: openPicker)
                    .controlSize(.small)
            }
            .foregroundStyle(.secondary)
        }
        .frame(height: 120)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    private var resultsArea: some View {
        Group {
            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { r in
                            FileRowView(result: r, onRemove: { remove(r) })
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("Renamed files will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Drag them out to your target folder in Finder.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("\(results.count) staged")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
                showingHistory = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .controlSize(.small)
            .help("View and revert past renames")
            Button("Clear") { clearAll() }
                .disabled(results.isEmpty || isProcessing)
                .controlSize(.small)
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView(isPresented: $showingHistory)
        }
    }

    // MARK: - Actions

    private func openPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        // Keep picker parity with drag-and-drop: let users choose any file,
        // then filter unsupported extensions in `process(urls:)`.
        panel.allowedContentTypes = []
        if panel.runModal() == .OK {
            process(urls: panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let queue = DispatchQueue(label: "filedrop.collect")

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    queue.sync { urls.append(url) }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            process(urls: urls)
        }
        return true
    }

    private func process(urls: [URL]) {
        let expanded = urls.flatMap(expand)
        guard !expanded.isEmpty else { return }

        isProcessing = true
        Task.detached(priority: .userInitiated) {
            var batch: [ProcessingResult] = []
            for url in expanded {
                batch.append(FileProcessor.process(url: url))
            }
            let finalBatch = batch
            await MainActor.run {
                // newest first — feels more natural for a drop queue
                results.insert(contentsOf: finalBatch, at: 0)
                isProcessing = false
            }
        }
    }

    private func remove(_ r: ProcessingResult) {
        if let staged = r.staged { FileStaging.remove(staged) }
        results.removeAll { $0.id == r.id }
    }

    /// Turns rename-in-place results from the Services menu into display
    /// rows. `source` = pre-rename URL, `staged` = the final renamed file at
    /// its Finder location (so drag-out still works if the user wants to
    /// drag it elsewhere).
    private func appendRenameResults(_ list: [InPlaceRenameResult]) {
        let converted: [ProcessingResult] = list.compactMap { r in
            guard r.succeeded, let renamed = r.renamed else { return nil }
            return ProcessingResult(
                source: r.source,
                staged: renamed,
                docType: r.docType,
                personName: r.personName,
                nameSource: r.nameSource,
                matchedKeyword: nil,
                ocrText: "",
                error: nil
            )
        }
        if !converted.isEmpty {
            results.insert(contentsOf: converted, at: 0)
        }
    }

    private func clearAll() {
        for r in results {
            if let staged = r.staged { FileStaging.remove(staged) }
        }
        results.removeAll()
    }

    /// Expand directories into their supported files (recursive).
    private func expand(_ url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            return FileProcessor.supportedExtensions.contains(url.pathExtension.lowercased())
                ? [url] : []
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var out: [URL] = []
        for case let fileURL as URL in enumerator {
            if FileProcessor.supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                out.append(fileURL)
            }
        }
        return out
    }
}
