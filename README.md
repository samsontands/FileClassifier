# FileClassifier

A lightweight macOS app that auto-renames documents based on their content —
person name + document type, all on-device. Built for migration agents who
process ID scans, passports, diplomas, bank statements, etc.

```
IC - Scan.pdf                   →  CHAN-KAI-YUEN_ID-CARD.pdf
Passport - Screenshot.png       →  CHAN-KAI-YUEN_PASSPORT.png
EPF Statement - 2024.pdf        →  CHAN-KAI-YUEN_EPF-STATEMENT.pdf
Masters Certificate.pdf         →  CHAN-KAI-YUEN_DIPLOMA.pdf
```

## What it does

- **Offline**. No cloud, no Ollama, no model downloads. Uses Apple's on-device
  Vision OCR and NaturalLanguage frameworks.
- **Multi-language**. OCR covers English, Malay, Chinese, Japanese, Korean,
  French, German, Spanish, Portuguese, Italian, Russian, Ukrainian, Thai,
  Vietnamese, Arabic.
- **Originals are never modified** in the drop-zone flow. Files are copied
  to a per-session staging folder under the new name; drag them out to save.
- **Right-click rename** in Finder (single or multi-select) via a macOS
  Services entry — this one does rename in place because you opted in.
- **Lightweight**. ~320 KB zip, universal binary (arm64 + x86_64), runs on
  an 8 GB M1 MacBook Air without breaking a sweat.

## Supported formats

| Bucket         | Extensions                                                 | How              |
|----------------|------------------------------------------------------------|------------------|
| PDF            | `pdf`                                                      | Rasterize + OCR  |
| Images         | `png jpg jpeg tiff bmp heic heif webp gif`                 | Vision OCR       |
| Office docs    | `docx doc rtf rtfd odt html htm webarchive`                | NSAttributedString |
| Plain text     | `txt md csv tsv log`                                       | UTF-8 read       |
| Rich docs      | `pages key numbers pptx ppt xlsx xls`                      | QuickLook → OCR  |

## Document types detected

`PASSPORT · ID-CARD · DRIVING-LICENSE · WORK-PERMIT · VISA · BIRTH-CERT ·
MARRIAGE-CERT · RESUME · TRANSCRIPT · DIPLOMA · SERVICE-STATEMENT ·
EPF-STATEMENT · BANK-STATEMENT · PAYSLIP · TAX-RETURN · UTILITY-BILL ·
MEDICAL · CERTIFICATE · PHOTO · DOCUMENT`

Rule-based keyword + regex scoring — deterministic, fast, zero runtime cost.
Specific rules (e.g. "birth certificate") outscore the generic "certificate"
fallback.

## Filename format

```
PERSON-NAME_DOCTYPE.ext
```

Fallbacks:

- No person name detected → `RENAME-ME_DOCTYPE.ext` (the UI badges the row
  with a **RENAME ME** pill so you catch it).
- No doc type → `PERSON-NAME.ext`.
- Neither → `RENAME-ME_DOCUMENT_<timestamp>.ext`.

## Build

```bash
./build.sh
open build/FileClassifier.app
```

Produces `build/FileClassifier.app` and a `FileClassifier.zip` you can send
to someone else.

First run: right-click the .app and choose **Open** so Gatekeeper lets it
through (it's ad-hoc signed, not notarized).

## Use

**GUI (drop-zone):**

1. Launch the app.
2. Drop files or folders into the window — they OCR, get renamed, and land
   in a staging folder.
3. Drag the renamed row out of the window into your save location in Finder.
   Originals stay untouched.

**Finder right-click (rename in place):**

1. Select one or more files in Finder.
2. Right-click → Services → **Rename with FileClassifier**.
3. Files are renamed in their current folder. A notification summarizes the
   batch (e.g. "5 renamed · 1 needs manual review").

> On first install the Services menu may take a minute to appear. Launching
> the app once calls `NSUpdateDynamicServices()` which forces macOS to pick
> it up; if you still don't see it, log out and back in.

**CLI (dry-run):**

```bash
./.build/debug/FileClassifier --classify "path/to/file.pdf"
```

Prints the proposed new filename, doc type, detected name, and OCR head
snippet — useful for testing against a sample set without moving anything.

**CLI (rename in place, scriptable / Automator):**

```bash
./FileClassifier.app/Contents/MacOS/FileClassifier --rename file1.pdf file2.png …
```

Exit code is `0` if every file renamed, `1` otherwise.

## Tests

```bash
swift test
```

34 tests covering doc-type detection, name extraction (labelled,
next-line-label, all-caps, title-case, NLTagger), filename building, and
end-to-end pipelines — including Malaysian bilingual edge cases (MyKad,
KWSP EPF, Nama/Name passports, split surname/given-names transcripts).

## Architecture

```
FileClassifierCore (library)      ← pure logic, no AppKit, testable
  ├── DocumentClassifier          ← keyword + regex scoring
  ├── NameExtractor               ← 5-layer person-name extraction
  └── RenameService               ← PERSON-NAME_DOCTYPE.ext builder

FileClassifier (executable)       ← app layer
  ├── OCRService                  ← Vision + NSAttributedString + QuickLook
  ├── PDFRasterizer               ← PDFKit → 200 DPI CGImages
  ├── FileProcessor               ← drop-zone pipeline (OCR → classify → stage)
  ├── FileRenamer                 ← in-place rename for Services / --rename
  ├── FileStaging                 ← per-session /tmp directory
  ├── ServiceProvider             ← NSServices handler for Finder right-click
  └── SwiftUI views               ← drop zone, result list, draggable rows
```
