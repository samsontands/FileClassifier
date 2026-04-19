import Foundation
import FileClassifierCore

struct ProcessingResult: Identifiable {
    let id = UUID()
    let source: URL              // original (never touched)
    let staged: URL?             // renamed copy in the session staging dir
    let docType: DocType
    let personName: String
    let nameSource: NameSource   // NLTagger / labelled field / none
    let matchedKeyword: String?  // what triggered the doc-type classification
    let ocrText: String          // full OCR result — shown in details view
    let error: String?

    var didStage: Bool { staged != nil && error == nil }
}

enum FileProcessor {
    /// All file extensions the pipeline will attempt. Assembled from the four
    /// buckets OCRService knows about so there's one source of truth.
    static let supportedExtensions: Set<String> = {
        var set: Set<String> = ["pdf"]
        set.formUnion(OCRService.imageExtensions)
        set.formUnion(OCRService.attributedExtensions)
        set.formUnion(OCRService.textExtensions)
        set.formUnion(OCRService.quickLookExtensions)
        return set
    }()

    /// OCR → classify → extract name → copy to staging under the new name.
    /// Original file is never modified.
    static func process(url: URL) -> ProcessingResult {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            return ProcessingResult(
                source: url, staged: nil,
                docType: .document, personName: "",
                nameSource: .none, matchedKeyword: nil,
                ocrText: "", error: "Unsupported file type: .\(ext)"
            )
        }

        do {
            let text = try OCRService.extractText(from: url)
            let hit = DocumentClassifier.classify(text)
            let name = NameExtractor.extract(from: text)
            let newName = RenameService.buildFilename(
                name: name.name, docType: hit.type, ext: ext
            )
            let staged = try FileStaging.stage(src: url, as: newName)
            return ProcessingResult(
                source: url, staged: staged,
                docType: hit.type, personName: name.name,
                nameSource: name.source, matchedKeyword: hit.evidence,
                ocrText: text, error: nil
            )
        } catch {
            return ProcessingResult(
                source: url, staged: nil,
                docType: .document, personName: "",
                nameSource: .none, matchedKeyword: nil,
                ocrText: "", error: String(describing: error)
            )
        }
    }
}
