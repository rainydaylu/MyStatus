import AppKit
import StatusDeckKit
import SwiftUI

enum PanelBackdropDepth {
    static let key = "ui.backgroundDepth"
    static let defaultValue = 0.50

    static func intensity(at depth: Double) -> CGFloat {
        let depth = min(1, max(0, depth))
        // Keep the desktop visible even at full depth.
        return 0.82 * (depth + 0.30 * depth * (1 - depth))
    }
}

enum PanelBackdropBlur {
    static let key = "ui.backgroundBlur"
    static let defaultValue = 0.50
}

/// A window material behind the control cards, feathered where the menu meets the desktop.
struct PanelBackdrop: View {
    let feather: PanelBackdropMask.Feather
    @AppStorage(PanelBackdropDepth.key) private var depth = PanelBackdropDepth.defaultValue
    @AppStorage(PanelBackdropBlur.key) private var blur = PanelBackdropBlur.defaultValue
    @Environment(\.deckUsesGlass) private var usesGlass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if usesGlass && !reduceTransparency && (depth > 0 || blur > 0) {
            MenuBackdrop(blur: blur, tint: PanelBackdropDepth.intensity(at: depth) * 0.28, feather: feather)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct MenuBackdrop: NSViewRepresentable {
    let blur: CGFloat
    let tint: CGFloat
    let feather: PanelBackdropMask.Feather

    func makeNSView(context: Context) -> BackdropView { BackdropView() }

    func updateNSView(_ view: BackdropView, context: Context) {
        view.configure(blur: blur, tint: tint, feather: feather, isDark: context.environment.colorScheme == .dark)
    }

    final class BackdropView: NSView {
        private let material = NSVisualEffectView()
        private let veil = NSImageView()
        private var blur: CGFloat = 0
        private var tint: CGFloat = 0
        private var feather: PanelBackdropMask.Feather?
        private var isDark = false
        private var renderedSize: CGSize = .zero

        init() {
            super.init(frame: .zero)
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.isHidden = true
            veil.imageScaling = .scaleAxesIndependently
            addSubview(material)
            addSubview(veil)
        }

        required init?(coder: NSCoder) { return nil }

        func configure(blur: CGFloat, tint: CGFloat, feather: PanelBackdropMask.Feather, isDark: Bool) {
            guard self.blur != blur || self.tint != tint || self.feather != feather || self.isDark != isDark else { return }
            self.blur = blur
            self.tint = tint
            self.feather = feather
            self.isDark = isDark
            material.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            updateSurfaces()
        }

        override func layout() {
            super.layout()
            if bounds.size != renderedSize { updateSurfaces() }
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            if bounds.size != renderedSize { updateSurfaces() }
        }

        private func updateSurfaces() {
            let size = bounds.size
            renderedSize = size
            material.frame = bounds
            veil.frame = bounds
            guard let feather else { return }
            let mask = PanelBackdropMask.make(size: size, intensity: blur, feather: feather)
            material.maskImage = mask.map { NSImage(cgImage: $0, size: size) }
            material.isHidden = mask == nil

            let gray: CGFloat = isDark ? 0.16 : 0.44
            let tintImage = PanelBackdropMask.make(size: size, intensity: tint, feather: feather, gray: gray)
            veil.image = tintImage.map { NSImage(cgImage: $0, size: size) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

enum PanelBackdropMask {
    struct Feather: Equatable {
        let left: CGFloat
        let right: CGFloat
        let top: CGFloat
        let bottom: CGFloat
    }

    static func make(size: CGSize, intensity: CGFloat, feather: Feather, gray: CGFloat = 0) -> CGImage? {
        guard size.width > 0, size.height > 0, intensity > 0 else { return nil }
        let width = Int(size.width.rounded(.up))
        let height = Int(size.height.rounded(.up))
        let rgb = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: rgb,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        let graySpace = CGColorSpaceCreateDeviceGray()
        let samples = (0...32).map { CGFloat($0) / 32 }
        // The mask reaches zero with a flat slope on every side of the window.
        let alpha = samples.map { t in t * t * t * (t * (6 * t - 15) + 10) }
        let bottom = min(feather.bottom / CGFloat(height), 0.70)
        let top = min(feather.top / CGFloat(height), 0.25)
        let left = min(feather.left / CGFloat(width), 0.49)
        let right = min(feather.right / CGFloat(width), 0.49)
        let fade = alpha + Array(alpha.reversed())
        let verticalColors = fade.map { CGColor(gray: gray, alpha: $0 * min(1, intensity)) }
        let horizontalColors = fade.map { CGColor(gray: 0, alpha: $0) }
        // Quartz bitmap coordinates start at the bottom of the panel.
        guard let vertical = CGGradient(colorsSpace: graySpace, colors: verticalColors as CFArray,
                                        locations: samples.map { $0 * bottom } + samples.map { 1 - top + $0 * top }),
              let horizontal = CGGradient(colorsSpace: graySpace, colors: horizontalColors as CFArray,
                                          locations: samples.map { $0 * left } + samples.map { 1 - right + $0 * right }) else { return nil }

        context.drawLinearGradient(vertical, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        context.setBlendMode(.destinationIn)
        context.drawLinearGradient(horizontal, start: .zero, end: CGPoint(x: width, y: 0), options: [])
        return context.makeImage()
    }
}
