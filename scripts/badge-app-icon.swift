#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: badge-app-icon.swift <source.icns> <output.iconset> <label>\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let label = CommandLine.arguments[3]

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Could not read app icon at \(sourceURL.path).\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL,
    withIntermediateDirectories: true
)

let representations = [
    (points: 16, scale: 1),
    (points: 16, scale: 2),
    (points: 32, scale: 1),
    (points: 32, scale: 2),
    (points: 128, scale: 1),
    (points: 128, scale: 2),
    (points: 256, scale: 1),
    (points: 256, scale: 2),
    (points: 512, scale: 1),
    (points: 512, scale: 2),
]

for representation in representations {
    let pixels = representation.points * representation.scale
    guard let bitmap = NSBitmapImageRep(
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
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fputs("Could not create the \(pixels) pixel icon representation.\n", stderr)
        exit(1)
    }

    let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    sourceImage.draw(
        in: canvas,
        from: .zero,
        operation: .copy,
        fraction: 1
    )

    let margin = max(CGFloat(pixels) * 0.08, 1)
    let badgeHeight = max(CGFloat(pixels) * 0.32, 5)
    let badgeRect = NSRect(
        x: margin,
        y: margin,
        width: CGFloat(pixels) - (margin * 2),
        height: badgeHeight
    )
    let badgePath = NSBezierPath(
        roundedRect: badgeRect,
        xRadius: badgeHeight * 0.28,
        yRadius: badgeHeight * 0.28
    )
    NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.24, alpha: 0.94).setFill()
    badgePath.fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let text = label as NSString
    var fontSize = badgeHeight * 0.58
    var attributes: [NSAttributedString.Key: Any] = [:]
    repeat {
        attributes = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        if text.size(withAttributes: attributes).width <= badgeRect.width - (margin * 2) {
            break
        }
        fontSize -= 1
    } while fontSize > 4

    let textHeight = text.size(withAttributes: attributes).height
    let textRect = NSRect(
        x: badgeRect.minX + margin,
        y: badgeRect.midY - (textHeight / 2),
        width: badgeRect.width - (margin * 2),
        height: textHeight
    )
    text.draw(in: textRect, withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Could not encode the \(pixels) pixel icon representation.\n", stderr)
        exit(1)
    }

    let suffix = representation.scale == 2 ? "@2x" : ""
    let filename = "icon_\(representation.points)x\(representation.points)\(suffix).png"
    try png.write(to: outputURL.appendingPathComponent(filename), options: .atomic)
}
