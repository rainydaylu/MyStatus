import AppKit
import StatusDeckKit
import Testing
@testable import StatusDeckCore

@MainActor
@Suite("Combined menu bar button")
struct StatusBarTests {
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
