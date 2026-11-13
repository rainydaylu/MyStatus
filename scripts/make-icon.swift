// Draws Support/AppIcon.icns. Run with: swift scripts/make-icon.swift
import AppKit

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(pixels)
    // The standard macOS icon grid leaves a margin around the tile.
    let tile = NSRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
    let shape = NSBezierPath(roundedRect: tile, xRadius: size * 0.18, yRadius: size * 0.18)
    NSGradient(starting: NSColor(red: 0.13, green: 0.17, blue: 0.27, alpha: 1),
               ending: NSColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1))?
        .draw(in: shape, angle: -90)

    let center = NSPoint(x: size / 2, y: size / 2)
    let radius = size * 0.26
    let width = size * 0.052

    func arc(from start: CGFloat, to end: CGFloat, _ color: NSColor) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }
    arc(from: 215, to: -35, NSColor.white.withAlphaComponent(0.14))
    arc(from: 215, to: 30, NSColor(red: 0.04, green: 0.49, blue: 1, alpha: 1))
    arc(from: 30, to: -5, NSColor(red: 0.965, green: 0.30, blue: 0.62, alpha: 1))

    // A small bar graph inside the gauge.
    let heights: [CGFloat] = [0.32, 0.55, 0.4, 0.8, 0.62, 0.95, 0.5]
    let barWidth = size * 0.034
    let gap = size * 0.018
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    let base = center.y - size * 0.11
    for (index, height) in heights.enumerated() {
        let x = center.x - total / 2 + CGFloat(index) * (barWidth + gap)
        let bar = NSRect(x: x, y: base, width: barWidth, height: size * 0.22 * height)
        NSColor(red: 0.04, green: 0.49, blue: 1, alpha: 1).setFill()
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 3, yRadius: barWidth / 3).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("StatusDeck-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let data = drawIcon(pixels: points * scale).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Support/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
