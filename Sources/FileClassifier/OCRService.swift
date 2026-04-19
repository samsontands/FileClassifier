import Foundation
import Vision
import AppKit
import CoreImage
import QuickLookThumbnailing

enum OCRError: Error {
    case unsupported(String)
    case failed(String)
}

struct OCRService {
    /// Priority order. Vision intersects this with what it actually supports
    /// at runtime (which varies by macOS version and request revision).
    private static let desiredLanguages: [String] = [
        "en-US",
        "ms",                           // Malay
        "zh-Hans", "zh-Hant",           // Chinese
        "ja-JP", "ko-KR",               // Japanese, Korean
        "fr-FR", "de-DE", "es-ES",
        "pt-BR", "it-IT",
        "ru-RU", "uk-UA",
        "th-TH", "vi-VT",
        "ar-SA",                        // Arabic
    ]

    /// File extensions we handle natively — either by reading text directly,
    /// rasterising (PDF), OCRing an image, or rendering a QuickLook preview
    /// and OCRing that.
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tiff", "tif", "bmp",
        "heic", "heif", "webp", "gif",
    ]

    /// Formats whose text we can read without OCR via NSAttributedString.
    static let attributedExtensions: Set<String> = [
        "docx", "doc", "rtf", "rtfd", "odt", "html", "htm", "webarchive",
    ]

    /// Plain-text formats — just read UTF-8.
    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "log",
    ]

    /// Other formats we can't parse directly — render a QuickLook preview
    /// and OCR the image. Covers Pages, Keynote, Numbers, PowerPoint,
    /// Excel, etc.
    static let quickLookExtensions: Set<String> = [
        "pages", "key", "keynote", "numbers",
        "pptx", "ppt", "xlsx", "xls",
    ]

    /// Extract text from any supported document.
    ///
    /// Dispatches based on extension:
    ///   - PDF     → rasterise pages, OCR each
    ///   - images  → OCR directly
    ///   - DOCX/RTF/HTML → read via NSAttributedString (no OCR needed)
    ///   - TXT/MD/CSV    → UTF-8 read
    ///   - anything else → render a QuickLook preview and OCR it
    static func extractText(from url: URL, maxPDFPages: Int = 3) throws -> String {
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            let images = try PDFRasterizer.rasterize(url: url, maxPages: maxPDFPages)
            return images.map { ocr(cgImage: $0) }.joined(separator: "\n")
        }
        if imageExtensions.contains(ext) {
            guard let image = NSImage(contentsOf: url),
                  let cg = cgImage(from: image) else {
                throw OCRError.failed("Could not read image: \(url.lastPathComponent)")
            }
            return ocr(cgImage: cg)
        }
        if textExtensions.contains(ext) {
            return (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1))
                ?? ""
        }
        if attributedExtensions.contains(ext) {
            if let text = readAttributed(url: url), !text.isEmpty { return text }
            // If NSAttributedString couldn't parse it (e.g. newer DOCX variants),
            // fall through to QuickLook rendering.
            return try quickLookOCR(url: url)
        }
        if quickLookExtensions.contains(ext) {
            return try quickLookOCR(url: url)
        }
        // Unknown extension — best effort: try QuickLook. If it can't render,
        // surface the unsupported error.
        if let text = try? quickLookOCR(url: url), !text.isEmpty {
            return text
        }
        throw OCRError.unsupported(ext)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func ocr(cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }
        if let supported = try? request.supportedRecognitionLanguages() {
            let active = desiredLanguages.filter { supported.contains($0) }
            if !active.isEmpty {
                request.recognitionLanguages = active
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    // MARK: - Word / RTF / HTML via NSAttributedString

    /// Read DOCX/RTF/HTML/ODT via the native Cocoa attributed-string reader.
    /// No network, no external libraries — Apple has shipped this since 10.3.
    private static func readAttributed(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        if let attr = try? NSAttributedString(
            data: data, options: options,
            documentAttributes: nil
        ) {
            return attr.string
        }
        return nil
    }

    // MARK: - QuickLook preview → OCR

    /// Render a file as a QuickLook thumbnail and OCR the result. Gives us
    /// text from formats NSAttributedString can't handle (Pages, Keynote,
    /// Numbers, PPTX, XLSX) without shelling out to LibreOffice.
    private static func quickLookOCR(url: URL) throws -> String {
        guard let cg = renderQuickLookImage(url: url) else {
            throw OCRError.failed("Could not render preview: \(url.lastPathComponent)")
        }
        return ocr(cgImage: cg)
    }

    private static func renderQuickLookImage(url: URL) -> CGImage? {
        let size = CGSize(width: 2000, height: 2800)
        let scale: CGFloat = 1.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        let sem = DispatchSemaphore(value: 0)
        var result: CGImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumb, _ in
            result = thumb?.cgImage
            sem.signal()
        }
        // QuickLook renders complex docs off-main; wait up to 30s.
        _ = sem.wait(timeout: .now() + 30)
        return result
    }
}
