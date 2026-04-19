import Foundation

/// Rule-based document type detection.
/// Fast, deterministic, zero runtime cost — exactly what an 8GB M1 Air wants.
public enum DocType: String, CaseIterable, Sendable {
    case passport          = "PASSPORT"
    case idCard            = "ID-CARD"
    case drivingLicense    = "DRIVING-LICENSE"
    case workPermit        = "WORK-PERMIT"
    case visa              = "VISA"
    case birthCert         = "BIRTH-CERT"
    case marriageCert      = "MARRIAGE-CERT"
    case resume            = "RESUME"
    case transcript        = "TRANSCRIPT"
    case diploma           = "DIPLOMA"
    case serviceStatement  = "SERVICE-STATEMENT"
    case epfStatement      = "EPF-STATEMENT"
    case bankStatement     = "BANK-STATEMENT"
    case payslip           = "PAYSLIP"
    case taxReturn         = "TAX-RETURN"
    case utilityBill       = "UTILITY-BILL"
    case medical           = "MEDICAL"
    case certificate       = "CERTIFICATE"   // generic fallback
    case photo             = "PHOTO"
    case document          = "DOCUMENT"
}

public struct ClassificationHit: Sendable {
    public let type: DocType
    /// The keyword or regex that matched — useful for showing "why" in the UI.
    public let evidence: String?

    public init(type: DocType, evidence: String?) {
        self.type = type
        self.evidence = evidence
    }
}

struct ClassifierRule {
    let type: DocType
    let keywords: [String]
    let regexes: [String]
    let score: Int
}

public enum DocumentClassifier {
    /// Rules are scored; highest-scoring match wins. More specific rules
    /// score higher so e.g. "birth certificate" beats generic "certificate".
    private static let rules: [ClassifierRule] = [
        // --- identity documents ---
        .init(type: .passport,
              keywords: ["passport", "passeport", "pasaporte"],
              regexes: ["\\bP<[A-Z]{3}"],           // MRZ
              score: 10),
        .init(type: .drivingLicense,
              keywords: ["driving licence", "driving license", "driver license",
                         "driver's license", "permis de conduire"],
              regexes: [], score: 10),
        .init(type: .idCard,
              keywords: ["identity card", "national identity", "identification card",
                         "nric", "national id", "national registration",
                         "mykad", "kad pengenalan", "pendaftaran negara",
                         "carte d'identité"],
              regexes: ["\\bID<[A-Z]{3}"],          // MRZ
              score: 9),
        .init(type: .workPermit,
              keywords: ["work permit", "employment pass", "work pass"],
              regexes: ["\\bs[\\s\\-]?pass\\b"],     // exact "s pass", not substring
              score: 8),
        .init(type: .visa,
              keywords: ["visa", "entry permit", "residence permit"],
              regexes: ["\\bV<[A-Z]{3}"], score: 7),

        // --- civil records ---
        .init(type: .birthCert,
              keywords: ["birth certificate", "certificate of birth", "acte de naissance"],
              regexes: [], score: 9),
        .init(type: .marriageCert,
              keywords: ["marriage certificate", "certificate of marriage",
                         "certificat de mariage"],
              regexes: [], score: 9),

        // --- employment / education ---
        .init(type: .resume,
              keywords: ["curriculum vitae", "résumé", "resume",
                         "work experience", "professional experience"],
              regexes: [], score: 8),
        .init(type: .transcript,
              keywords: ["transcript of records", "academic transcript",
                         "official transcript", "grade report", "transcript"],
              regexes: [], score: 8),
        .init(type: .diploma,
              keywords: ["diploma", "bachelor of", "master of", "doctor of",
                         "degree of", "graduation certificate",
                         "certificate of graduation", "has been conferred",
                         "is hereby awarded", "hereby confers",
                         "is conferred upon", "the award of", "senate confers"],
              regexes: [], score: 7),
        .init(type: .serviceStatement,
              keywords: ["statement of service", "service record",
                         "record of service", "certificate of service",
                         "letter of service"],
              regexes: [], score: 8),

        // --- financial ---
        // Scored above ID-CARD (9) because real KWSP statements embed
        // "No Kad Pengenalan" as a field label, which would otherwise win.
        .init(type: .epfStatement,
              keywords: ["epf statement", "kwsp", "penyata ahli",
                         "employees provident fund", "retirement savings",
                         "jumlah simpanan"],
              regexes: [], score: 11),
        .init(type: .bankStatement,
              keywords: ["bank statement", "statement of account",
                         "account statement", "opening balance", "closing balance"],
              regexes: [], score: 6),
        .init(type: .payslip,
              keywords: ["payslip", "pay slip", "salary slip",
                         "earnings statement", "net pay", "gross pay"],
              regexes: [], score: 6),
        .init(type: .taxReturn,
              keywords: ["tax return", "notice of assessment", "income tax"],
              regexes: [], score: 5),
        .init(type: .utilityBill,
              keywords: ["electricity bill", "water bill", "utility bill", "gas bill"],
              regexes: [], score: 4),

        // --- other ---
        .init(type: .medical,
              keywords: ["medical report", "medical certificate", "vaccination"],
              regexes: [], score: 4),
        .init(type: .photo,
              keywords: ["passport photo", "passport-size photo", "photograph"],
              regexes: [], score: 2),

        // --- generic fallback: last-resort catch for any "certificate" doc ---
        .init(type: .certificate,
              keywords: ["certificate", "certification", "awarded to",
                         "is awarded", "certificate of completion",
                         "course completion", "bootcamp", "capstone project"],
              regexes: [], score: 3),
    ]

    public static func classify(_ text: String) -> ClassificationHit {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ClassificationHit(type: .document, evidence: nil) }

        let lower = trimmed.lowercased()
        var best: (type: DocType, score: Int, evidence: String)? = nil

        for rule in rules {
            var evidence: String? = nil
            for kw in rule.keywords where lower.contains(kw) {
                evidence = kw
                break
            }
            if evidence == nil {
                for pattern in rule.regexes {
                    if let range = trimmed.range(of: pattern, options: .regularExpression) {
                        evidence = String(trimmed[range])
                        break
                    }
                }
            }
            if let e = evidence, (best?.score ?? 0) < rule.score {
                best = (rule.type, rule.score, e)
            }
        }
        if let b = best {
            return ClassificationHit(type: b.type, evidence: b.evidence)
        }
        return ClassificationHit(type: .document, evidence: nil)
    }
}
