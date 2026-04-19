import XCTest
@testable import FileClassifierCore

final class ClassifierTests: XCTestCase {

    // MARK: - Doc type detection (each target category)

    func testPassport() {
        let text = """
        REPUBLIC OF SINGAPORE
        PASSPORT
        Surname / Nom: TAN
        Given Names / Prénoms: WEI MING
        Passport No.: E1234567F
        P<SGPTAN<<WEI<MING<<<<<<<<<<<<<<<<<<<<<<<<<<
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .passport)
    }

    func testDrivingLicense() {
        let text = """
        SINGAPORE DRIVING LICENCE
        NAME: TAN WEI MING
        Licence No.: S1234567A
        Class: 3, 3A
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .drivingLicense)
    }

    func testIDCard() {
        let text = """
        NATIONAL REGISTRATION IDENTITY CARD
        Name: TAN WEI MING
        NRIC: S1234567A
        Date of Birth: 01-01-1990
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .idCard)
    }

    func testResume() {
        let text = """
        Curriculum Vitae
        Tan Wei Ming
        Email: tan@example.com
        Professional Experience:
        2020–2024 Senior Engineer, Acme
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .resume)
    }

    func testDiploma() {
        let text = """
        UNIVERSITY OF EXAMPLE
        This is to certify that TAN WEI MING
        has been conferred the degree of
        Bachelor of Science
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .diploma)
    }

    func testTranscript() {
        let text = """
        OFFICIAL TRANSCRIPT
        Student: Tan Wei Ming
        Semester 1 Grades:
        Module A  B+
        Module B  A-
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .transcript)
    }

    func testBirthCertBeatsGenericCertificate() {
        // Ensures specific rules outscore the generic `certificate` fallback.
        let text = "BIRTH CERTIFICATE\nName of child: TAN WEI MING\nDate of birth: 01-01-1990"
        XCTAssertEqual(DocumentClassifier.classify(text).type, .birthCert)
    }

    func testMarriageCert() {
        let text = "CERTIFICATE OF MARRIAGE\nBetween TAN WEI MING and LIM HUI LING"
        XCTAssertEqual(DocumentClassifier.classify(text).type, .marriageCert)
    }

    func testStatementOfService() {
        let text = """
        STATEMENT OF SERVICE
        This is to certify that TAN WEI MING served
        in the organization from 2015 to 2024.
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .serviceStatement)
    }

    func testBankStatement() {
        let text = """
        DBS BANK
        Statement of Account
        Account Holder: TAN WEI MING
        Opening Balance: 1,234.56
        Closing Balance: 2,345.67
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .bankStatement)
    }

    func testPayslip() {
        let text = """
        Payslip for April 2026
        Employee: Tan Wei Ming
        Gross Pay: 5,000
        Net Pay: 4,200
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .payslip)
    }

    func testGenericCertificateFallback() {
        // No specific keyword matches — falls back to the generic `certificate`.
        let text = "Certificate of Completion — Yoga 101 course\nAwarded to Tan Wei Ming"
        XCTAssertEqual(DocumentClassifier.classify(text).type, .certificate)
    }

    func testEmptyText() {
        XCTAssertEqual(DocumentClassifier.classify("").type, .document)
        XCTAssertEqual(DocumentClassifier.classify("   \n  ").type, .document)
    }

    func testEvidenceIsReported() {
        let hit = DocumentClassifier.classify("PASSPORT\nName: foo")
        XCTAssertEqual(hit.evidence, "passport")
    }

    // MARK: - Name extraction

    func testLabelledNameExtraction() {
        let text = "PASSPORT\nName: TAN WEI MING\nPassport No: E1234567F"
        let hit = NameExtractor.extract(from: text)
        XCTAssertEqual(hit.source, .labelledField)
        XCTAssertEqual(hit.name.uppercased(), "TAN WEI MING")
    }

    func testSurnameLabelledField() {
        let text = "Surname: Tan\nGiven Names: Wei Ming"
        let hit = NameExtractor.extract(from: text)
        XCTAssertEqual(hit.source, .labelledField)
        XCTAssertFalse(hit.name.isEmpty)
    }

    func testNLTaggerFallbackOnFreeText() {
        // No labelled field — NLTagger should still find "John Smith".
        let text = "This statement of service certifies that John Smith served here."
        let hit = NameExtractor.extract(from: text)
        // NLTagger's English model reliably finds "John Smith" in plain prose.
        XCTAssertTrue(hit.source == .nlTagger || hit.source == .labelledField)
        XCTAssertFalse(hit.name.isEmpty, "Expected a name, got empty")
    }

    func testEmptyTextProducesNoName() {
        let hit = NameExtractor.extract(from: "")
        XCTAssertEqual(hit.source, .none)
        XCTAssertEqual(hit.name, "")
    }

    // MARK: - Filename building

    func testFilenameWithNameAndType() {
        let name = RenameService.buildFilename(
            name: "Tan Wei Ming", docType: .passport, ext: "pdf"
        )
        XCTAssertEqual(name, "TAN-WEI-MING_PASSPORT.pdf")
    }

    func testFilenameWithNameOnly() {
        let name = RenameService.buildFilename(
            name: "Tan Wei Ming", docType: .document, ext: "jpg"
        )
        XCTAssertEqual(name, "TAN-WEI-MING.jpg")
    }

    func testFilenameTypeOnlyUsesPlaceholder() {
        let name = RenameService.buildFilename(
            name: "", docType: .passport, ext: "pdf"
        )
        XCTAssertEqual(name, "RENAME-ME_PASSPORT.pdf")
        XCTAssertTrue(RenameService.needsManualName(name))
    }

    func testFilenameNeitherUsesPlaceholderAndTimestamp() {
        let name = RenameService.buildFilename(
            name: "", docType: .document, ext: "png"
        )
        XCTAssertNotNil(name.range(of: #"^RENAME-ME_DOCUMENT_\d{8}-\d{6}\.png$"#, options: .regularExpression))
        XCTAssertTrue(RenameService.needsManualName(name))
    }

    func testFilenameHandlesApostropheAndAccents() {
        let name = RenameService.buildFilename(
            name: "O'Brien", docType: .drivingLicense, ext: "pdf"
        )
        XCTAssertEqual(name, "OBRIEN_DRIVING-LICENSE.pdf")
    }

    func testFilenameStripsDigitsAndPunctuation() {
        let name = RenameService.buildFilename(
            name: "Tan Wei Ming 123!@#", docType: .passport, ext: "pdf"
        )
        XCTAssertEqual(name, "TAN-WEI-MING_PASSPORT.pdf")
    }

    // MARK: - End-to-end pipeline (text only — OCR is tested separately)

    func testPipelinePassport() {
        let ocr = """
        REPUBLIC OF SINGAPORE
        PASSPORT
        Name: TAN WEI MING
        Passport No.: E1234567F
        """
        let hit = DocumentClassifier.classify(ocr)
        let nameHit = NameExtractor.extract(from: ocr)
        let filename = RenameService.buildFilename(
            name: nameHit.name, docType: hit.type, ext: "pdf"
        )
        XCTAssertEqual(filename, "TAN-WEI-MING_PASSPORT.pdf")
    }

    // MARK: - Malaysian bilingual docs (the real samples)

    func testMyKadIsIDCard() {
        let text = """
        MyKad
        MALAYSIA
        CHAN KAI YUEN
        971112-10-6937
        KETUA PENGARAH PENDAFTARAN NEGARA
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .idCard)
    }

    func testEPFStatementDetected() {
        let text = """
        KWSP
        EPF
        SULIT DAN PERSENDIRIAN
        CHAN KAI YUEN
        Penyata Ahli Tahun 2024
        JUMLAH SIMPANAN: RM57,805.86
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .epfStatement)
    }

    func testHerebyConfersIsDiploma() {
        let text = """
        ASIA PACIFIC UNIVERSITY
        With the approval of the University Senate,
        the Asia Pacific University hereby confers upon
        Chan Kai Yuen
        the Award of MSc in Data Science
        """
        XCTAssertEqual(DocumentClassifier.classify(text).type, .diploma)
    }

    func testSPassNoLongerFalsePositive() {
        // Previously "s pass" as a substring false-matched in "SENATE"-ish
        // text. Now requires a word boundary.
        let text = "TRANSCRIPT\nASIA PACIFIC UNIVERSITY\nMSc in Data Science\nStatistical Methods MSTAT"
        XCTAssertNotEqual(DocumentClassifier.classify(text).type, .workPermit)
    }

    // MARK: - Name extraction: Malaysian-style docs

    func testNextLineLabelPassport() {
        let text = """
        MALAYSIA
        Passport
        Nama / Name
        CHAN KAI YUEN
        Warganegara / Nationality
        MALAYSIA
        """
        let hit = NameExtractor.extract(from: text)
        XCTAssertEqual(hit.source, .nextLineLabel)
        XCTAssertEqual(hit.name.uppercased(), "CHAN KAI YUEN")
    }

    func testAllCapsNameWithNoLabel() {
        // EPF-statement style: name at the top, no label.
        let text = """
        KWSP
        EPF
        SULIT DAN PERSENDIRIAN
        CHAN KAI YUEN
        19 JALAN KANTAN 13
        """
        let hit = NameExtractor.extract(from: text)
        XCTAssertEqual(hit.source, .allCapsLine)
        XCTAssertEqual(hit.name.uppercased(), "CHAN KAI YUEN")
    }

    func testBlacklistRejectsInstitutionName() {
        // "ASIA PACIFIC UNIVERSITY" is all caps but must not be picked as a name.
        let text = """
        ASIA PACIFIC UNIVERSITY
        OF TECHNOLOGY & INNOVATION
        hereby confers upon
        CHAN KAI YUEN
        the Award of MSc
        """
        let hit = NameExtractor.extract(from: text)
        XCTAssertFalse(hit.name.uppercased().contains("PACIFIC"))
        XCTAssertFalse(hit.name.uppercased().contains("UNIVERSITY"))
    }

    func testSplitSurnameGivenNamesMerge() {
        // Transcript layout where labels precede values on later lines.
        let text = """
        Surname / Nom
        Given Names / Prénoms
        CHAN
        KAI YUEN
        """
        let hit = NameExtractor.extract(from: text)
        XCTAssertEqual(hit.name.uppercased(), "CHAN KAI YUEN")
    }

    func testPipelineDrivingLicence() {
        let ocr = """
        DRIVING LICENCE
        Name: LIM HUI LING
        Licence No: S1234567A
        """
        let hit = DocumentClassifier.classify(ocr)
        let nameHit = NameExtractor.extract(from: ocr)
        let filename = RenameService.buildFilename(
            name: nameHit.name, docType: hit.type, ext: "pdf"
        )
        XCTAssertEqual(filename, "LIM-HUI-LING_DRIVING-LICENSE.pdf")
    }
}
