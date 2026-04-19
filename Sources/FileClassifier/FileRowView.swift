import SwiftUI
import AppKit
import FileClassifierCore

/// One row in the staged-files list.
///
/// Shows thumbnail + new filename + metadata, and makes the staged file
/// draggable out of the window. A disclosure button reveals the OCR text
/// and "why" details so the user can verify each rename.
struct FileRowView: View {
    let result: ProcessingResult
    var onRemove: () -> Void

    @State private var thumbnail: NSImage?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if expanded {
                Divider().padding(.vertical, 8)
                detailsView
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbView
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(displayName)
                    if needsManualRename {
                        Text("RENAME ME")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.orange)
                            )
                            .help("No person name was detected — rename manually before using.")
                    }
                }
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let err = result.error {
                    Text(err).font(.caption).foregroundStyle(.red)
                } else if needsManualRename {
                    Text("Drag out, then rename before using")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if result.didStage {
                    Text("Drag out to save")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove from list")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(expanded ? "Hide details" : "Show details")
            }
        }
        .contentShape(Rectangle())
        .onDrag(makeDragProvider)
        .task(id: result.staged?.path ?? "") {
            if let url = result.staged {
                thumbnail = await ThumbnailService.generate(for: url)
            }
        }
    }

    // MARK: - Details

    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow("Original", result.source.lastPathComponent)
            detailRow("Doc type", result.docType.rawValue +
                      (result.matchedKeyword.map { " (matched '\($0)')" } ?? " (no keyword)"))
            detailRow("Name", result.personName.isEmpty
                      ? "—"
                      : "\(result.personName) (via \(result.nameSource.rawValue))")

            if !result.ocrText.isEmpty {
                Text("OCR text").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    Text(result.ocrText)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.06))
                )
                .textSelection(.enabled)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var thumbView: some View {
        let frame: CGFloat = 48
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
            if let nsImage = thumbnail {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(2)
            } else if result.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: frame, height: frame)
    }

    // MARK: - Helpers

    private var displayName: String {
        result.staged?.lastPathComponent ?? result.source.lastPathComponent
    }

    private var needsManualRename: Bool {
        guard let staged = result.staged else { return false }
        return RenameService.needsManualName(staged.lastPathComponent)
    }

    private var metadata: String {
        let type = result.docType.rawValue
        let name = result.personName.isEmpty ? "no name detected" : result.personName
        return "\(type) · \(name)"
    }

    private func makeDragProvider() -> NSItemProvider {
        guard let url = result.staged else { return NSItemProvider() }
        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }
}
