import Foundation
import NaturalLanguage

public enum NameSource: String, Sendable {
    case labelledField = "labelled field"   // e.g. "Name: JOHN DOE"
    case nextLineLabel = "next line label"  // e.g. "Nama / Name\nCHAN KAI YUEN"
    case allCapsLine   = "all-caps line"    // heuristic: a CHAN KAI YUEN line
    case titleCaseLine = "title-case line"  // heuristic: a "Chan Kai Yuen" line
    case nlTagger      = "NLTagger"          // Apple's on-device recognizer
    case none          = "none"
}

public struct NameHit: Sendable {
    public let name: String
    public let source: NameSource

    public init(name: String, source: NameSource) {
        self.name = name
        self.source = source
    }
}

/// Extracts the primary person's name from OCR text.
///
/// Tried in order:
///   1. Same-line labelled fields: "Name: JOHN DOE"
///   2. Next-line labelled fields (common on Malaysian bilingual docs):
///      "Nama / Name\nCHAN KAI YUEN"
///   3. All-caps name-shaped lines, with a blacklist of institution words
///      (handles docs like EPF statements where the name sits at the top
///      without any label).
///   4. Apple's NLTagger as last resort — good for English free prose,
///      unreliable for all-caps Malaysian IDs.
public enum NameExtractor {
    public static func extract(from text: String) -> NameHit {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return NameHit(name: "", source: .none) }

        if let v = sameLineLabelledName(in: cleaned) {
            return NameHit(name: normalize(v), source: .labelledField)
        }
        if let v = nextLineLabelledName(in: cleaned) {
            return NameHit(name: normalize(v), source: .nextLineLabel)
        }
        if let v = firstAllCapsNameLine(in: cleaned) {
            return NameHit(name: normalize(v), source: .allCapsLine)
        }
        if let v = firstTitleCaseNameLine(in: cleaned) {
            return NameHit(name: normalize(v), source: .titleCaseLine)
        }
        if let v = bestNLTaggerName(in: cleaned) {
            return NameHit(name: normalize(v), source: .nlTagger)
        }
        return NameHit(name: "", source: .none)
    }

    // MARK: - Layer 1: same-line "Name: JOHN DOE"

    private static let sameLinePattern =
        "(?im)^\\s*(?:full\\s*name|name(?:\\s+of\\s+\\w+)?|nama|surname|given\\s*names?|holder|nom|apellidos|account\\s*holder)\\s*[:\\-]\\s*(.+)$"

    private static func sameLineLabelledName(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: sameLinePattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else { continue }
            let raw = String(text[captureRange])
                .split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if isPlausibleName(trimmed) { return trimmed }
        }
        return nil
    }

    // MARK: - Layer 2: "Nama / Name" on one line, value on the next

    /// Matches label tokens anywhere in a line (not just at line start).
    /// Used to find bilingual labels like "Nama / Name" where the value is
    /// on a subsequent line.
    private static let nextLineLabels: [String] = [
        "name", "nama", "full name", "holder", "surname", "given names"
    ]

    private static func nextLineLabelledName(in text: String) -> String? {
        let lines = text.split(whereSeparator: { $0.isNewline }).map { String($0) }
        for i in 0..<lines.count {
            let lowerLine = lines[i].lowercased()
            let isLabel = nextLineLabels.contains { label in
                // e.g. "Nama / Name" contains "name" as a whole word
                lowerLine.range(of: "\\b\(NSRegularExpression.escapedPattern(for: label))\\b",
                                options: .regularExpression) != nil
            }
            guard isLabel else { continue }

            // Scan forward up to 3 lines for the first plausible name value.
            for j in (i + 1)..<min(i + 4, lines.count) {
                let candidate = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.isEmpty { continue }
                // Stop if we hit another label line
                if isLabelish(candidate) { break }
                if isPlausibleName(candidate) {
                    return mergeSurnameIfSplit(lines: lines, atIndex: j, value: candidate)
                }
            }
        }
        return nil
    }

    /// If the following line is also name-shaped and not too long, combine
    /// them — handles "CHAN\nKAI YUEN" split across lines.
    private static func mergeSurnameIfSplit(lines: [String], atIndex i: Int, value: String) -> String {
        // Combine single-word line with the next name-shaped line.
        let thisWords = value.split(separator: " ").count
        if thisWords == 1, i + 1 < lines.count {
            let next = lines[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            if isPlausibleName(next), !isLabelish(next) {
                return "\(value) \(next)"
            }
        }
        return value
    }

    // MARK: - Layer 3: all-caps line heuristic (Malaysian-style docs)

    /// Words that routinely appear in all-caps on institutional docs but
    /// are not personal names. When ANY word on a candidate line is in
    /// this set, the line is rejected.
    private static let nonNameTerms: Set<String> = [
        // institutions
        "UNIVERSITY", "UNIVERSITI", "COLLEGE", "KOLEJ",
        "INSTITUTE", "INSTITUT", "ACADEMY", "SCHOOL", "SEKOLAH",
        "FACULTY", "FAKULTI",
        // business types
        "BANK", "LIMITED", "LTD", "INC", "CORP", "CORPORATION",
        "BHD", "SDN", "GROUP", "HOLDINGS", "COMPANY", "SYARIKAT",
        "SERVICES", "SOLUTIONS", "ENTERPRISE",
        // geographic
        "MALAYSIA", "SINGAPORE", "INDONESIA", "THAILAND", "PHILIPPINES",
        "ASIA", "PACIFIC", "ATLANTIC", "EASTERN", "WESTERN",
        "KUALA", "LUMPUR", "SELANGOR", "JOHOR", "PENANG",
        "SABAH", "SARAWAK", "KEDAH", "PERAK", "PAHANG",
        "REPUBLIC", "STATE", "UNION", "FEDERAL",
        // government / admin
        "DEPARTMENT", "MINISTRY", "KEMENTERIAN", "JABATAN",
        "GOVERNMENT", "KERAJAAN", "OFFICE", "PEJABAT",
        "AUTHORITY", "BOARD", "LEMBAGA", "COMMITTEE", "COUNCIL",
        "KETUA", "PENGARAH", "PENDAFTARAN", "NEGARA",
        // document words
        "PASSPORT", "LICENCE", "LICENSE", "LESEN",
        "CERTIFICATE", "SIJIL", "DIPLOMA", "TRANSCRIPT",
        "STATEMENT", "PENYATA", "ACCOUNT", "AKAUN",
        "BALANCE", "RECORD", "REKOD",
        "CONFIDENTIAL", "SULIT", "PRIVATE", "PERSENDIRIAN",
        "PERSONAL", "OFFICIAL", "ORIGINAL",
        // layout / meta
        "PAGE", "MUKA", "SURAT", "TAHUN", "TARIKH", "NOMBOR",
        "NAMA", "NAME", "SURNAME", "GIVEN", "HOLDER",
        "DATE", "ISSUED", "DIKELUARKAN", "WARGANEGARA", "NATIONALITY",
        // common agency acronyms
        "KWSP", "EPF", "LHDN", "SOCSO", "PERKESO", "JPJ",
        // other noise we've actually seen
        "MINISTERE", "MINISTÈRE", "EDUCATION", "PENDIDIKAN",
        "TECHNOLOGY", "INNOVATION", "ENGINEERING",
        "DATA", "SCIENCE", "BUSINESS", "ANALYTICS",
        "MASTER", "BACHELOR", "DOCTOR", "MASTERS",
        "AWARD", "AWARDED", "CONFERS", "GRADUATE",
        // transcript / form layouts
        "STUDENT", "STUDENTS", "COURSE", "STUDY", "CODE",
        "SPECIALISATION", "SPECIALIZATION", "PROGRAMME", "PROGRAM",
        "MODULE", "MODULES", "CREDIT", "HOURS", "RESULT", "RESULTS",
        "GRADE", "POINT", "SEMESTER", "SUBJECT", "MARKS",
        "SENATE", "APPROVAL", "ONTARIO", "OFFSHORE", "SUNWAY",
        // OCR garbage we've seen at the top of docs
        "IDEN", "HUSP", "MALAYSN", "WARGANEGAR",
    ]

    private static func firstAllCapsNameLine(in text: String) -> String? {
        let lines = text.split(whereSeparator: { $0.isNewline }).map { String($0) }
        for (i, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard isAllCapsNameLine(line) else { continue }
            let thisWords = line.split(separator: " ").count
            if thisWords >= 2 {
                // Multi-word candidate — safe to accept. Also merge a preceding
                // single-word surname, e.g. "TAN" on its own line before it.
                let prev = i > 0
                    ? lines[i - 1].trimmingCharacters(in: .whitespaces)
                    : ""
                if isAllCapsNameLine(prev), prev.split(separator: " ").count == 1 {
                    return "\(prev) \(line)"
                }
                return line
            } else {
                // Single-word candidate — only accept if the next line is a
                // multi-word name line we can merge with. Prevents OCR garbage
                // like "HUSP" or "IDEN" at the top of a doc from being picked.
                let next = i + 1 < lines.count
                    ? lines[i + 1].trimmingCharacters(in: .whitespaces)
                    : ""
                if isAllCapsNameLine(next), next.split(separator: " ").count >= 2 {
                    return "\(line) \(next)"
                }
                continue
            }
        }
        return nil
    }

    private static func isAllCapsNameLine(_ line: String) -> Bool {
        guard (3...50).contains(line.count) else { return false }
        let words = line.split(separator: " ").map(String.init)
        guard (1...4).contains(words.count) else { return false }
        for w in words {
            guard w.count >= 2 else { return false }
            for ch in w {
                if !ch.isLetter { return false }
                if ch.isLetter && ch.isLowercase { return false }
            }
            if nonNameTerms.contains(w.uppercased()) { return false }
        }
        // At least one word must be 3+ chars to dodge "A B" kind of noise.
        return words.contains { $0.count >= 3 }
    }

    // MARK: - Layer 3.5: title-case line heuristic

    /// Catches names like "Chan Kai Yuen" that sit on their own line without
    /// any label, in documents like diplomas where the name is rendered in
    /// Title Case rather than ALL CAPS.
    private static func firstTitleCaseNameLine(in text: String) -> String? {
        let lines = text.split(whereSeparator: { $0.isNewline }).map { String($0) }
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if isTitleCaseNameLine(line) { return line }
        }
        return nil
    }

    private static func isTitleCaseNameLine(_ line: String) -> Bool {
        guard (5...50).contains(line.count) else { return false }
        let words = line.split(separator: " ").map(String.init)
        // Require 2-4 words to dodge single-word noise and long sentences.
        guard (2...4).contains(words.count) else { return false }
        for w in words {
            guard w.count >= 2 else { return false }
            // First char must be uppercase letter; rest must be lowercase letters.
            guard let first = w.first, first.isLetter, first.isUppercase else {
                return false
            }
            for ch in w.dropFirst() {
                if !ch.isLetter { return false }
                if ch.isUppercase { return false }
            }
            if nonNameTerms.contains(w.uppercased()) { return false }
        }
        return true
    }

    // MARK: - Layer 4: NLTagger fallback

    private static func bestNLTaggerName(in text: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        var candidates: [(text: String, range: Range<String.Index>)] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            if tag == .personalName {
                let value = String(text[range]).trimmingCharacters(in: .whitespaces)
                if value.count >= 3 { candidates.append((value, range)) }
            }
            return true
        }

        // Prefer multi-token candidates — single-token NLTagger hits are
        // often generic all-caps words mis-tagged as names.
        let multi = candidates.filter { $0.text.split(separator: " ").count >= 2 }
        let pool = multi.isEmpty ? candidates : multi

        return pool.max { lhs, rhs in
            if lhs.text.count != rhs.text.count {
                return lhs.text.count < rhs.text.count
            }
            return lhs.range.lowerBound > rhs.range.lowerBound
        }?.text
    }

    // MARK: - Shared helpers

    private static func isPlausibleName(_ s: String) -> Bool {
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 3, letters >= s.count / 2 else { return false }
        // Reject if ANY word is in the blacklist — catches e.g.
        // "Ministry of Education" picked up after a "Surname / Nom" label.
        let words = s.split(separator: " ").map { String($0).uppercased() }
        if words.contains(where: { nonNameTerms.contains($0) }) {
            return false
        }
        return true
    }

    private static func isLabelish(_ s: String) -> Bool {
        let lower = s.lowercased()
        if lower.hasSuffix(":") { return true }
        // Bilingual labels use a slash: "Nama / Name", "Given Names / Prénoms".
        if s.contains("/") { return true }
        let labelTokens = ["nationality", "warganegara", "date of birth",
                           "tarikh lahir", "passport no", "no. pasport",
                           "address", "alamat", "surname", "given names",
                           "holder", "full name", "name of", "prénoms", "nom",
                           // transcript/diploma form labels we've seen
                           "student id", "student no", "course of study",
                           "specialisation", "specialization", "programme",
                           "program of study", "module code", "subject code",
                           "year of study", "intake"]
        return labelTokens.contains { lower.contains($0) }
    }

    private static func normalize(_ raw: String) -> String {
        var allowed = CharacterSet.letters
        allowed.insert(charactersIn: " -'")
        let filteredScalars = raw.unicodeScalars.filter { allowed.contains($0) }
        let filtered = String(String.UnicodeScalarView(filteredScalars))
        let parts = filtered.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "'" })
        return parts.joined(separator: " ")
    }
}
