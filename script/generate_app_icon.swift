#!/usr/bin/env swift

import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = rootURL.appendingPathComponent("Assets/AppIcon.iconset", isDirectory: true)
let previewURL = rootURL.appendingPathComponent("Assets/AppIconPreview.png")
let resourcesURL = rootURL.appendingPathComponent("Resources", isDirectory: true)

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "IconGeneration", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current = context
    context?.shouldAntialias = true

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    func v(_ value: CGFloat) -> CGFloat { value * size / 1024 }

    NSColor.clear.setFill()
    bounds.fill()

    let outer = NSBezierPath(
        roundedRect: bounds.insetBy(dx: v(36), dy: v(36)),
        xRadius: v(224),
        yRadius: v(224)
    )
    outer.addClip()

    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1),
            NSColor(calibratedRed: 0.04, green: 0.36, blue: 0.46, alpha: 1)
        ]
    )?.draw(in: bounds, angle: -38)

    NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
    outer.lineWidth = v(8)
    outer.stroke()

    let lensRect = NSRect(x: v(244), y: v(244), width: v(536), height: v(536))
    let lens = NSBezierPath(roundedRect: lensRect, xRadius: v(88), yRadius: v(88))
    NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
    lens.fill()

    NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
    lens.lineWidth = v(10)
    lens.stroke()

    let screenRect = NSRect(x: v(306), y: v(366), width: v(412), height: v(252))
    let screen = NSBezierPath(roundedRect: screenRect, xRadius: v(36), yRadius: v(36))
    NSColor(calibratedRed: 0.93, green: 0.98, blue: 1, alpha: 0.92).setFill()
    screen.fill()

    let lineColor = NSColor(calibratedRed: 0.10, green: 0.76, blue: 0.88, alpha: 1)
    lineColor.setStroke()
    let scanLine = NSBezierPath()
    scanLine.move(to: NSPoint(x: v(350), y: v(494)))
    scanLine.line(to: NSPoint(x: v(674), y: v(494)))
    scanLine.lineWidth = v(24)
    scanLine.lineCapStyle = .round
    scanLine.stroke()

    func cornerPath(points: [NSPoint]) {
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.lineWidth = v(34)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    lineColor.setStroke()
    cornerPath(points: [NSPoint(x: v(226), y: v(682)), NSPoint(x: v(226), y: v(776)), NSPoint(x: v(320), y: v(776))])
    cornerPath(points: [NSPoint(x: v(704), y: v(776)), NSPoint(x: v(798), y: v(776)), NSPoint(x: v(798), y: v(682))])
    cornerPath(points: [NSPoint(x: v(798), y: v(342)), NSPoint(x: v(798), y: v(248)), NSPoint(x: v(704), y: v(248))])
    cornerPath(points: [NSPoint(x: v(320), y: v(248)), NSPoint(x: v(226), y: v(248)), NSPoint(x: v(226), y: v(342))])

    let sparkle = NSBezierPath()
    sparkle.move(to: NSPoint(x: v(728), y: v(680)))
    sparkle.line(to: NSPoint(x: v(758), y: v(742)))
    sparkle.line(to: NSPoint(x: v(788), y: v(680)))
    sparkle.line(to: NSPoint(x: v(758), y: v(618)))
    sparkle.close()
    NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.35, alpha: 1).setFill()
    sparkle.fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 2)
    }
    return pngData
}

let iconFiles: [(String, CGFloat)] = [
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

for (filename, size) in iconFiles {
    try drawIcon(size: size).write(to: iconsetURL.appendingPathComponent(filename))
}

try drawIcon(size: 1024).write(to: previewURL)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconsetURL.path,
    "-o", resourcesURL.appendingPathComponent("AppIcon.icns").path
]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "IconGeneration", code: Int(process.terminationStatus))
}
