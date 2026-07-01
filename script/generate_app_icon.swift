#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate_app_icon.swift <output.icns>\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let fileManager = FileManager.default
let workDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("veil-icon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = workDirectory.appendingPathComponent("VeilAppIcon.iconset", isDirectory: true)

try fileManager.createDirectory(
    at: iconsetURL,
    withIntermediateDirectories: true
)
try fileManager.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

defer {
    try? fileManager.removeItem(at: workDirectory)
}

let iconVariants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for variant in iconVariants {
    let data = try renderIconPNG(pixels: variant.pixels)
    try data.write(to: iconsetURL.appendingPathComponent(variant.name), options: [.atomic])
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    iconsetURL.path,
    "-o",
    outputURL.path
]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}

private func renderIconPNG(pixels: Int) throws -> Data {
    guard let representation = NSBitmapImageRep(
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
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    representation.size = NSSize(width: pixels, height: pixels)

    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.setShouldAntialias(true)

    drawIcon(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))

    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }

    return data
}

private func drawIcon(in rect: NSRect) {
    NSColor.clear.setFill()
    rect.fill()

    let scale = rect.width / 1024
    func s(_ value: CGFloat) -> CGFloat { value * scale }

    let outerRect = rect.insetBy(dx: s(58), dy: s(58))
    let outerPath = NSBezierPath(
        roundedRect: outerRect,
        xRadius: s(184),
        yRadius: s(184)
    )

    NSGraphicsContext.current?.cgContext.setShadow(
        offset: CGSize(width: 0, height: -s(34)),
        blur: s(68),
        color: NSColor.black.withAlphaComponent(0.30).cgColor
    )
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.15, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.05, alpha: 1)
        ]
    )?.draw(in: outerPath, angle: -35)
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    NSColor.white.withAlphaComponent(0.20).setStroke()
    outerPath.lineWidth = s(6)
    outerPath.stroke()

    let backPaneRect = NSRect(
        x: outerRect.minX + s(170),
        y: outerRect.minY + s(280),
        width: s(410),
        height: s(410)
    )
    let backPanePath = NSBezierPath(roundedRect: backPaneRect, xRadius: s(86), yRadius: s(86))
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.06, green: 0.66, blue: 0.92, alpha: 1),
            NSColor(calibratedRed: 0.17, green: 0.86, blue: 0.74, alpha: 1)
        ]
    )?.draw(in: backPanePath, angle: -28)

    let frontPaneRect = NSRect(
        x: outerRect.minX + s(430),
        y: outerRect.minY + s(170),
        width: s(410),
        height: s(410)
    )
    let frontPanePath = NSBezierPath(roundedRect: frontPaneRect, xRadius: s(86), yRadius: s(86))
    NSGradient(
        colors: [
            NSColor(calibratedRed: 1.00, green: 0.40, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.20, alpha: 1)
        ]
    )?.draw(in: frontPanePath, angle: -20)

    NSColor.white.withAlphaComponent(0.24).setStroke()
    backPanePath.lineWidth = s(5)
    backPanePath.stroke()
    frontPanePath.lineWidth = s(5)
    frontPanePath.stroke()

    let monogramRect = outerRect.insetBy(dx: s(260), dy: s(245))
    let monogram = NSBezierPath()
    monogram.lineWidth = s(64)
    monogram.lineCapStyle = .round
    monogram.lineJoinStyle = .round
    monogram.move(to: NSPoint(x: monogramRect.minX + s(22), y: monogramRect.maxY - s(16)))
    monogram.line(to: NSPoint(x: monogramRect.midX, y: monogramRect.minY + s(20)))
    monogram.line(to: NSPoint(x: monogramRect.maxX - s(22), y: monogramRect.maxY - s(16)))
    NSColor.white.withAlphaComponent(0.96).setStroke()
    monogram.stroke()
}
