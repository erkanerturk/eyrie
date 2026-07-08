#!/usr/bin/swift
// Regenerates App/Assets.xcassets/AppIcon.appiconset from scratch:
// an indigo→teal gradient squircle with a white bird SF Symbol.
// Run from the repo root: swift Scripts/generate-appicon.swift

import AppKit

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let iconsetURL = repoRoot.appending(path: "App/Assets.xcassets/AppIcon.appiconset")

let variants: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = CGFloat(pixels)
    // Classic macOS icon proportions: artwork fills ~80% of the canvas,
    // corner radius ~22.4% of the artwork size. Tahoe re-masks as needed.
    let shape = CGRect(x: 0, y: 0, width: canvas, height: canvas)
        .insetBy(dx: canvas * 0.10, dy: canvas * 0.10)
    let path = NSBezierPath(
        roundedRect: shape,
        xRadius: shape.width * 0.224,
        yRadius: shape.width * 0.224
    )
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.32, green: 0.30, blue: 0.92, alpha: 1),
        ending: NSColor(srgbRed: 0.12, green: 0.62, blue: 0.72, alpha: 1)
    )!
    gradient.draw(in: path, angle: -65)

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: canvas * 0.40, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let size = symbol.size
        let origin = CGPoint(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2)
        symbol.draw(in: CGRect(origin: origin, size: size))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try? FileManager.default.removeItem(at: iconsetURL)
try! FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

var contentsImages: [[String: String]] = []
for (size, scale) in variants {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    let filename = "icon_\(size)x\(size)\(suffix).png"
    let rep = renderIcon(pixels: size * scale)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: iconsetURL.appending(path: filename))
    contentsImages.append([
        "filename": filename,
        "idiom": "mac",
        "scale": "\(scale)x",
        "size": "\(size)x\(size)",
    ])
}

let contents: [String: Any] = [
    "images": contentsImages,
    "info": ["author": "xcode", "version": 1],
]
let json = try! JSONSerialization.data(
    withJSONObject: contents,
    options: [.prettyPrinted, .sortedKeys]
)
try! json.write(to: iconsetURL.appending(path: "Contents.json"))

print("Wrote \(variants.count) icons to \(iconsetURL.path)")
