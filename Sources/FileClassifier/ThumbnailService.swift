import Foundation
import AppKit
import QuickLookThumbnailing

/// Generates file thumbnails via QuickLook — async, cached on disk by macOS.
/// For a document-renaming tool the thumbnail is the fastest way for the
/// user to confirm the right file got the right name.
enum ThumbnailService {
    static func generate(for url: URL, size: CGSize = CGSize(width: 72, height: 96)) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { cont in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                cont.resume(returning: rep?.nsImage)
            }
        }
    }
}
