import AppKit
import StatusDeckKit
import Testing
@testable import StatusDeckCore

@MainActor
@Suite("Combined menu bar button")
struct StatusBarTests {
    @Test func repeatedStatusBarReplicaDrawsReuseTheSameSourcePixels() throws {
        var drawings = 0
        let source = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { bounds in
            drawings += 1
            NSColor.systemRed.setFill(); bounds.fill()
            return true
        }
        let combined = try #require(StatusBarGroup.image([source, solidImage(.black, size: NSSize(width: 8, height: 12))]))
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 24,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = combined.size
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        combined.draw(in: NSRect(origin: .zero, size: combined.size))
        let firstDrawings = drawings
        #expect(firstDrawings > 0)
        for _ in 0..<20 { combined.draw(in: NSRect(origin: .zero, size: combined.size)) }
        #expect(drawings == firstDrawings, "Menu-bar replicas must not repeatedly draw the source")
    }

    @Test func readoutBitmapsSupportBothDisplayDensitiesAndKeepTemplateTinting() throws {
        let image = StatusPillRenderer.image(for: .init(upload: "12 KB/s", download: "1 MB/s", cpu: "15%", memory: "50%"))
        #expect(image.isTemplate)
        let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        #expect(reps.count == 2)
        #expect(Set(reps.map(\.pixelsHigh)) == [22, 44])
        #expect(reps.allSatisfy { $0.size == image.size })
        #expect(image.tiffRepresentation != nil)
    }
    @Test func trioPrecedesReadoutsInOneGroupRegardlessOfPluginOrder() throws {
        let trio = DeckMenuBarItem()
        let readouts = DeckMenuBarItem()
        let external = DeckMenuBarItem()
        let groups = StatusBarGroup.groups([
            (StatsPillPlugin.id, readouts),
            ("com.test.external", external),
            (TrioIconPlugin.id, trio)
        ])
        #expect(groups.count == 2)
        let main = try #require(groups.first)
        #expect(main.id == TrioIconPlugin.id)
        #expect(main.models.count == 2)
        #expect(main.models[0] === trio)
        #expect(main.models[1] === readouts)
        #expect(groups[1].models.first === external)
    }

    @Test func eitherSwitchCanLeaveTheOtherPartInTheSameButton() throws {
        for id in [TrioIconPlugin.id, StatsPillPlugin.id] {
            let model = DeckMenuBarItem()
            let groups = StatusBarGroup.groups([(id, model)])
            #expect(groups.count == 1)
            #expect(groups.first?.id == TrioIconPlugin.id)
            #expect(groups.first?.models.first === model)
        }
        #expect(StatusBarGroup.groups([]).isEmpty)
    }

    @Test func combinedImagePreservesOrderSpacingAndTemplateContrast() throws {
        let icon = solidImage(.systemRed, size: NSSize(width: 10, height: 12))
        let readout = solidImage(.black, size: NSSize(width: 6, height: 10))
        readout.isTemplate = true
        let image = try #require(StatusBarGroup.image([icon, readout]))
        #expect(image.size == NSSize(width: 20, height: 12))
        #expect(!image.isTemplate)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 12,
                                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            let appearance = try #require(NSAppearance(named: name))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            appearance.performAsCurrentDrawingAppearance {
                image.draw(in: NSRect(origin: .zero, size: image.size))
            }
            NSGraphicsContext.restoreGraphicsState()
            let left = try #require(bitmap.colorAt(x: 4, y: 6)?.usingColorSpace(.deviceRGB))
            let gap = try #require(bitmap.colorAt(x: 12, y: 6))
            let right = try #require(bitmap.colorAt(x: 16, y: 6)?.usingColorSpace(.deviceRGB))
            #expect(left.redComponent > left.greenComponent)
            #expect(gap.alphaComponent == 0)
            #expect(right.alphaComponent > 0.99)
            #expect(name == .aqua ? right.redComponent < 0.01 : right.redComponent > 0.99)
        }
        #expect(StatusBarGroup.image([nil, icon]) === icon)
        #expect(StatusBarGroup.image([nil, nil]) == nil)
    }

    private func solidImage(_ color: NSColor, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { bounds in
            color.setFill()
            bounds.fill()
            return true
        }
    }
}
