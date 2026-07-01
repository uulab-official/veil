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

    let outerRect = rect.insetBy(dx: s(56), dy: s(56))
    let outerPath = NSBezierPath(
        roundedRect: outerRect,
        xRadius: s(190),
        yRadius: s(190)
    )

    NSGraphicsContext.current?.cgContext.setShadow(
        offset: CGSize(width: 0, height: -s(28)),
        blur: s(56),
        color: NSColor.black.withAlphaComponent(0.22).cgColor
    )
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.06, green: 0.12, blue: 0.24, alpha: 1),
            NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.10, alpha: 1)
        ]
    )?.draw(in: outerPath, angle: -35)
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    NSColor.white.withAlphaComponent(0.18).setStroke()
    outerPath.lineWidth = s(5)
    outerPath.stroke()

    let paneRect = outerRect.insetBy(dx: s(150), dy: s(170))
    let panePath = NSBezierPath(
        roundedRect: paneRect,
        xRadius: s(78),
        yRadius: s(78)
    )
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.10, green: 0.52, blue: 1.00, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.92, alpha: 1)
        ]
    )?.draw(in: panePath, angle: -25)

    NSColor.white.withAlphaComponent(0.24).setStroke()
    panePath.lineWidth = s(4)
    panePath.stroke()

    NSColor.white.withAlphaComponent(0.86).setStroke()
    let divider = NSBezierPath()
    divider.lineWidth = s(18)
    divider.lineCapStyle = .round
    divider.move(to: NSPoint(x: paneRect.midX, y: paneRect.minY + s(78)))
    divider.line(to: NSPoint(x: paneRect.midX, y: paneRect.maxY - s(78)))
    divider.move(to: NSPoint(x: paneRect.minX + s(78), y: paneRect.midY))
    divider.line(to: NSPoint(x: paneRect.maxX - s(78), y: paneRect.midY))
    divider.stroke()

    let veilPath = NSBezierPath()
    veilPath.lineWidth = s(48)
    veilPath.lineCapStyle = .round
    veilPath.lineJoinStyle = .round
    veilPath.move(to: NSPoint(x: paneRect.minX + s(118), y: paneRect.maxY - s(120)))
    veilPath.line(to: NSPoint(x: paneRect.midX, y: paneRect.minY + s(125)))
    veilPath.line(to: NSPoint(x: paneRect.maxX - s(118), y: paneRect.maxY - s(120)))
    NSColor.white.withAlphaComponent(0.94).setStroke()
    veilPath.stroke()
}
