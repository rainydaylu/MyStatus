import AppKit

/// Store small menu-bar drawings as pixels so AppKit's menu-bar replicas do not
/// repeatedly lay out text and redraw every source image.
enum MenuBarRaster {
    static func image(size: NSSize, scales: [CGFloat] = [1, 2],
                      drawing: (NSRect) -> Bool) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let result = NSImage(size: size)
        let appearance = NSAppearance.currentDrawing()
        for scale in scales {
            guard scale.isFinite, scale > 0,
                  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                      pixelsWide: Int(ceil(size.width * scale)), pixelsHigh: Int(ceil(size.height * scale)),
                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = size
            guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            appearance.performAsCurrentDrawingAppearance { _ = drawing(NSRect(origin: .zero, size: size)) }
            NSGraphicsContext.restoreGraphicsState()
            result.addRepresentation(bitmap)
        }
        return result.representations.isEmpty ? nil : result
    }
}
