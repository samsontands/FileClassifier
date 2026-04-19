import SwiftUI
import AppKit

/// Sheet shown from the main window's "History" button. Lists every rename
/// we've recorded and lets the user revert any of them — or clear the log.
///
/// The sheet reads from `RenameHistory.all()` on appear and refreshes when
/// the Services-menu revert fires a `fileClassifierDidRevert` notification,
/// so it stays accurate while open.
struct HistoryView: View {
    @Binding var isPresented: Bool
    @State private var records: [RenameRecord] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 360)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .fileClassifierDidRevert)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fileClassifierDidRename)) { _ in
            reload()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rename History").font(.headline)
                Text("Revert any file back to its original name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { isPresented = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if records.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No renames yet.")
                    .foregroundStyle(.secondary)
                Text("Files renamed via the window or Finder right-click will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(records) { r in
                        row(for: r)
                    }
                }
                .padding(10)
            }
        }
    }

    private func row(for record: RenameRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.renamedName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(record.originalName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(Self.dateFormatter.string(from: record.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Button {
                revert(record)
            } label: {
                Label("Revert", systemImage: "arrow.uturn.backward.circle")
            }
            .controlSize(.small)
            .help("Rename back to \(record.originalName)")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var footer: some View {
        HStack {
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text("\(records.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear History", role: .destructive) { clearAll() }
                .disabled(records.isEmpty)
                .controlSize(.small)
        }
        .padding(12)
    }

    // MARK: - Actions

    private func reload() {
        records = RenameHistory.all()
    }

    private func revert(_ record: RenameRecord) {
        switch RenameHistory.revert(id: record.id) {
        case .success:
            errorMessage = nil
            reload()
        case .failure(let err):
            errorMessage = err.localizedDescription
        }
    }

    private func clearAll() {
        let alert = NSAlert()
        alert.messageText = "Clear rename history?"
        alert.informativeText = "Files will not be affected — only the list of past renames. You won't be able to revert them after this."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            RenameHistory.clear()
            reload()
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
