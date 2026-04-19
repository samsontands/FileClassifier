#!/usr/bin/env swift
import AppKit
import Foundation

// Generates Resources/AppIcon.icns from an SF Symbol rendered onto a
// rounded-rect gradient. Re-run after tweaking the symbol or palette.
//
//     swift Scripts/make-icon.swift

let fm = FileManager.default
let rootURL = URL(fileURLWithPath: fm.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Resources")
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset")
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

try? fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
try? fm.removeItem(at: iconsetURL)
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let symbolName = "doc.text.magnifyingglass"
let gradientTop = NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.95, alpha: 1.0)
let gradientBottom = NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.78, alpha: 1.0)

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()

    let gradient = NSGradient(colors: [gradientTop, gradientBottom])
    gradient?.draw(in: rect, angle: -90)

    // Soft inner highlight along the top edge for depth
    let highlight = NSGradient(
        colors: [NSColor.white.withAlphaComponent(0.18), .clear]
    )
    highlight?.draw(in: rect, angle: -90)

    let symbolSize = size * 0.56
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
          let symbol = base.withSymbolConfiguration(config) else {
        return image
    }
    symbol.isTemplate = true

    // Tint the template to white.
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    let symRect = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: symRect)
    NSColor.white.set()
    symRect.fill(using: .sourceIn)
    tinted.unlockFocus()

    // Drop shadow behind the symbol.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = size * 0.04
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    let symOrigin = NSPoint(
        x: (size - tinted.size.width) / 2,
        y: (size - tinted.size.height) / 2
    )
    tinted.draw(at: symOrigin, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try data.write(to: url)
}

// iconset filename convention: icon_<size>x<size>[@2x].png
let renditions: [(pixelSize: CGFloat, filename: String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for r in renditions {
    let img = renderIcon(size: r.pixelSize)
    let out = iconsetURL.appendingPathComponent(r.filename)
    try writePNG(img, to: out)
    print("wrote \(r.filename) (\(Int(r.pixelSize))px)")
}

// iconutil is the canonical way to produce an .icns from an .iconset.
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

// Clean up the intermediate iconset folder — the .icns is the shipping artifact.
try? fm.removeItem(at: iconsetURL)

print("OK → \(icnsURL.path)")
