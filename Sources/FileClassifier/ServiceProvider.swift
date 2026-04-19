import AppKit
@preconcurrency import UserNotifications

extension Notification.Name {
    /// Posted when files were renamed via the Services menu or `--rename`
    /// CLI. `userInfo["results"]` is `[InPlaceRenameResult]`.
    static let fileClassifierDidRename = Notification.Name("FileClassifierDidRename")
}

/// Finder right-click / Services integration. The app registers this as its
/// services provider on launch; the `NSServices` entry in Info.plist tells
/// Finder to expose "Rename with FileClassifier" on file selections, single
/// or multi.
///
/// macOS routes the user's selection here as an `NSPasteboard`. We read the
/// file URLs off it, run each one through `FileRenamer.renameInPlace`, and
/// post a completion notification.
@MainActor
final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()

    /// Registered in Info.plist under `NSMessage = "renameFiles"`.
    /// The signature matches Cocoa's service-provider convention exactly;
    /// missing the trailing `error:` parameter means the Services system
    /// will fail to dispatch.
    @objc func renameFiles(
        _ pboard: NSPasteboard,
        userData: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        let urls = Self.readFileURLs(from: pboard)
        guard !urls.isEmpty else {
            errorPointer?.pointee = "No files selected." as NSString
            return
        }

        // The Services call must return quickly — offload the heavy work.
        // Capture URLs by value and do all filesystem work off-main; notify
        // via the UI layer from the main actor afterwards.
        let filesToProcess = urls
        Task.detached(priority: .userInitiated) {
            var results: [InPlaceRenameResult] = []
            for url in filesToProcess {
                let r = FileRenamer.renameInPlace(url: url)
                results.append(r)
            }
            await ServiceProvider.deliverSummary(results)
        }
    }

    // MARK: - URL extraction

    private static func readFileURLs(from pboard: NSPasteboard) -> [URL] {
        // Modern path: read NSURL objects directly. Restricting to file URLs
        // so remote/web URLs in the pasteboard don't sneak through.
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let objs = pboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] {
            return objs
        }
        // Legacy path: NSFilenamesPboardType is deprecated but Finder still
        // sends it in some routing cases.
        if let names = pboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String] {
            return names.map { URL(fileURLWithPath: $0) }
        }
        return []
    }

    // MARK: - Completion summary

    @MainActor
    private static func deliverSummary(_ results: [InPlaceRenameResult]) {
        let succeeded = results.filter { $0.succeeded }
        let failed = results.filter { !$0.succeeded }
        let review = succeeded.filter { $0.needsManualName }

        let title = "FileClassifier"
        var body = "\(succeeded.count) renamed"
        if !failed.isEmpty  { body += " · \(failed.count) failed" }
        if !review.isEmpty  { body += " · \(review.count) need manual review" }
        postNotification(title: title, body: body)

        // Broadcast to any open window so it can show a verification row.
        NotificationCenter.default.post(
            name: .fileClassifierDidRename,
            object: nil,
            userInfo: ["results": results]
        )
    }

    private static func postNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(req, withCompletionHandler: nil)
        }
    }
}
