import Foundation
import PDFKit
import AppKit

enum PDFRasterizer {
    /// Convert the first `maxPages` pages of a PDF into CGImages for OCR.
    static func rasterize(url: URL, maxPages: Int = 3, dpi: CGFloat = 200) throws -> [CGImage] {
        guard let doc = PDFDocument(url: url) else {
            throw OCRError.failed("Could not open PDF: \(url.lastPathComponent)")
        }
        let pageCount = min(doc.pageCount, maxPages)
        var images: [CGImage] = []
        let scale = dpi / 72.0

        for i in 0..<pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

            let image = NSImage(size: size)
            image.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()
            }
            image.unlockFocus()

            var rect = CGRect(origin: .zero, size: size)
            if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                images.append(cg)
            }
        }
        return images
    }
}
