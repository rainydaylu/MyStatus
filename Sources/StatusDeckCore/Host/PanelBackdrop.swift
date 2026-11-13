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

/// A neutral shade behind the controls. Live glass stays inside each card.
struct PanelBackdrop: View {
    let feather: PanelBackdropMask.Feather
    @AppStorage(PanelBackdropDepth.key) private var depth = PanelBackdropDepth.defaultValue
    @Environment(\.deckUsesGlass) private var usesGlass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if usesGlass && !reduceTransparency && depth > 0 {
            GeometryReader { geometry in
                if let mask = PanelBackdropMask.make(size: geometry.size,
                                                     intensity: PanelBackdropDepth.intensity(at: depth) * 0.20,
                                                     feather: feather) {
                    Image(decorative: mask, scale: 1)
                        .resizable()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

enum PanelBackdropMask {
    struct Feather: Equatable {
        let left: CGFloat
        let right: CGFloat
        let top: CGFloat
        let bottom: CGFloat
    }

    static func make(size: CGSize, intensity: CGFloat, feather: Feather) -> CGImage? {
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
        let verticalColors = fade.map { CGColor(gray: 0, alpha: $0 * min(1, intensity)) }
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
