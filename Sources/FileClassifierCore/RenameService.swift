import Foundation

/// Builds the new filename.
///
/// Format: `PERSON-NAME_DOCTYPE.ext`
/// Fallbacks:
///   - no name, has type  → `RENAME-ME_DOCTYPE.ext`
///   - has name, no type  → `PERSON-NAME.ext`
///   - neither            → `RENAME-ME_DOCUMENT_YYYYMMDD-HHMMSS.ext`
/// Names are uppercased; spaces and apostrophes collapse to dashes.
///
/// When the name can't be extracted the filename starts with the `RENAME-ME`
/// sentinel so the user sees immediately which files still need a manual
/// name. The sentinel is checked by `needsManualName(_:)`.
public enum RenameService {
    /// Prefix used when name extraction couldn't find a person. Picked up by
    /// the UI (FileRowView) to badge the row as "rename me".
    public static let manualRenamePlaceholder = "RENAME-ME"

    public static func buildFilename(name: String, docType: DocType, ext: String) -> String {
        let slug = slugifyName(name)
        let typeSlug = docType.rawValue
        let suffix = ext.isEmpty ? "" : ".\(ext.lowercased())"

        switch (slug.isEmpty, docType == .document) {
        case (false, false): return "\(slug)_\(typeSlug)\(suffix)"
        case (false, true):  return "\(slug)\(suffix)"
        case (true, false):  return "\(manualRenamePlaceholder)_\(typeSlug)\(suffix)"
        case (true, true):   return "\(manualRenamePlaceholder)_DOCUMENT_\(timestamp())\(suffix)"
        }
    }

    /// True when the filename starts with the manual-rename sentinel — used
    /// by the UI to flag rows the user should double-check.
    public static func needsManualName(_ filename: String) -> Bool {
        filename.hasPrefix("\(manualRenamePlaceholder)_")
    }

    // MARK: - Helpers

    private static func slugifyName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var allowed = CharacterSet.letters
        allowed.insert(charactersIn: " -'")
        let scalars = trimmed.uppercased().unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars))

        let parts = cleaned
            .replacingOccurrences(of: "'", with: "")
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .map(String.init)
            .filter { !$0.isEmpty }

        return parts.joined(separator: "-")
    }

    private static func timestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: Date())
    }
}
