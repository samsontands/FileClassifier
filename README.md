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

---

## ⬇️ Install (non-technical users)

**You just need a Mac.** No Xcode, no terminal, no Python, no downloads behind
the scenes.

1. Go to the [**Releases page**](https://github.com/samsontands/FileClassifier/releases/latest)
   and download **`FileClassifier.dmg`**.
2. Double-click the downloaded `.dmg` → a window opens showing the app
   and an `Applications` folder.
3. **Drag `FileClassifier` onto the `Applications` folder.** Done installing.
4. Open **Applications** in Finder, **right-click** `FileClassifier` → **Open**.
   Click **Open** in the popup.

> **Why right-click the first time?** The app isn't notarized by Apple (that
> needs a $99/year developer account). macOS shows a scary "can't be opened"
> popup on the first double-click. Right-clicking → Open is Apple's built-in
> escape hatch — you only need to do it **once**. After that, it opens like
> any other app.

### Using it

**To rename a pile of files fast:**

1. Select the files in Finder (one or many).
2. Right-click → **Services** → **Rename with FileClassifier**.
3. A notification tells you how many were renamed.

**Or drag them into the app window:**

1. Open FileClassifier.
2. Drop files or folders into the window.
3. Drag the renamed rows from the window into the folder where you want them
   saved. Originals are not touched.

**Made a mistake? Revert it.**

- Click **History** in the app window → hit **Revert** on any row.
- Or right-click the renamed file in Finder → **Services** → **Revert
  FileClassifier Rename**.

---

## What it does

- **Offline.** No cloud, no AI service, no model downloads. Uses Apple's
  on-device Vision OCR and NaturalLanguage frameworks.
- **Multi-language OCR.** English, Malay, Chinese, Japanese, Korean, French,
  German, Spanish, Portuguese, Italian, Russian, Ukrainian, Thai,
  Vietnamese, Arabic.
- **Originals preserved** in the drop-zone flow. Files are copied into a
  per-session staging folder under the new name; drag them out to save.
- **Right-click rename** in Finder (single or multi-select) for the fast
  path — renames in place, with one-click revert.
- **~1 MB download.** Universal binary (Apple Silicon + Intel). Runs fine
  on an 8 GB M1 MacBook Air.

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

## Filename format

```
PERSON-NAME_DOCTYPE.ext
```

Fallbacks:

- No person name detected → `RENAME-ME_DOCTYPE.ext` (the UI flags the row
  with a **RENAME ME** pill so you catch it).
- No doc type → `PERSON-NAME.ext`.
- Neither → `RENAME-ME_DOCUMENT_<timestamp>.ext`.

---

## Build from source (developers)

Requires Xcode command-line tools (`xcode-select --install`).

```bash
./build.sh                  # universal .app + .zip in build/
./Scripts/make-dmg.sh       # drag-to-Applications .dmg
swift test                  # 34 unit tests
```

To regenerate the app icon from its SF Symbol source:

```bash
swift Scripts/make-icon.swift
```

## CLI

```bash
# Dry-run: print the proposed new name without moving the file
./FileClassifier.app/Contents/MacOS/FileClassifier --classify "file.pdf"

# Rename files in place (scriptable — exit 0 = all ok)
./FileClassifier.app/Contents/MacOS/FileClassifier --rename file1.pdf file2.png

# Revert a previous rename
./FileClassifier.app/Contents/MacOS/FileClassifier --revert file.pdf

# Undo the most recent rename
./FileClassifier.app/Contents/MacOS/FileClassifier --undo-last

# Show rename history
./FileClassifier.app/Contents/MacOS/FileClassifier --history
```

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
  ├── RenameHistory               ← JSON-persisted log; powers --revert
  ├── FileStaging                 ← per-session /tmp directory
  ├── ServiceProvider             ← NSServices handler for Finder right-click
  └── SwiftUI views               ← drop zone, result list, history sheet
```
