import AppKit
import CoreGraphics
import Foundation
@testable import StatusDeckKit
import SwiftUI
@testable import StatusDeckCore
import Testing

@Suite("Panel layout")
struct PanelLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 3000, height: 1600)
    private let cardGap = PanelGeometry.gap

    private func anchor(x: CGFloat) -> CGRect {
        CGRect(x: x, y: 1600, width: 30, height: 24)
    }

    @Test func opensLeftWhenThePanelIsOnTheRightOfTheScreen() {
        let layout = PanelGeometry.layout(anchor: anchor(x: 2600), visible: screen)
        #expect(layout.flyoutX + DeckTheme.flyoutWidth + cardGap == layout.panelX)
    }

    @Test func opensRightWhenThePanelIsOnTheLeftOfTheScreen() {
        let layout = PanelGeometry.layout(anchor: anchor(x: 100), visible: screen)
        #expect(layout.panelX + DeckTheme.panelWidth + cardGap == layout.flyoutX)
    }

    @Test func compactRightCardPrefersRightAndFallsBackWhenThatSideCannotFit() {
        for (anchorX, fitsRight) in [(2000.0, true), (2990.0, false)] {
            let layout = PanelGeometry.layout(anchor: anchor(x: anchorX), visible: screen)
            let width = PanelTileLayout.compactWidth
            let row = CGRect(x: layout.panelX + DeckTheme.panelWidth - width, y: 0, width: width, height: 65)
            let side = layout.flyoutPosition(for: row)
            #expect((side > layout.panelX) == fitsRight)
            #expect(side >= 0)
            #expect(side + DeckTheme.flyoutWidth <= layout.window.width)
        }
    }

    @Test func aPanelAtTheEdgeStaysOnTheScreen() {
        let layout = PanelGeometry.layout(anchor: anchor(x: 2990), visible: screen)
        #expect(layout.window.minX + layout.panelX + DeckTheme.panelWidth <= screen.maxX)
        let backdrop = layout.backdropFrame(contentHeight: 500)
        #expect(backdrop.maxX <= layout.window.width)
        #expect(backdrop.maxX > layout.panelX + DeckTheme.panelWidth)
        #expect(layout.panelX - backdrop.minX == backdrop.maxX - layout.panelX - DeckTheme.panelWidth)
    }

    @Test func backdropHasRoomToFadeBeyondTheCards() {
        let layout = PanelGeometry.layout(anchor: anchor(x: 1600), visible: screen)
        let backdrop = layout.backdropFrame(contentHeight: 500)
        #expect(layout.panelX - backdrop.minX == PanelGeometry.backdropSideSpread)
        #expect(backdrop.maxX - layout.panelX - DeckTheme.panelWidth == PanelGeometry.backdropSideSpread)
        #expect(backdrop.height == 500 + PanelGeometry.backdropBottomSpread)
        #expect(layout.backdropFrame(contentHeight: layout.window.height).height == layout.window.height)
    }

    @Test func aScreenTooNarrowForBothKeepsTheDetailOnIt() {
        let narrow = CGRect(x: 0, y: 0, width: 400, height: 1600)
        let layout = PanelGeometry.layout(anchor: anchor(x: 150), visible: narrow)
        let flyoutLeft = layout.window.minX + layout.flyoutX
        #expect(flyoutLeft >= narrow.minX)
        #expect(flyoutLeft + DeckTheme.flyoutWidth <= narrow.maxX)
    }

    @Test func worksOnASecondScreenWithItsOwnOrigin() {
        let second = CGRect(x: 3000, y: 200, width: 1600, height: 900)
        let layout = PanelGeometry.layout(anchor: CGRect(x: 4400, y: 1100, width: 30, height: 24), visible: second)
        #expect(layout.window.minX >= second.minX - PanelGeometry.margin)
        #expect(layout.window.maxX <= second.maxX + PanelGeometry.margin)
        #expect(layout.window.minY == second.minY)
    }

    @Test func theWindowHoldsBothColumnsAndHangsFromTheMenuBar() {
        let layout = PanelGeometry.layout(anchor: anchor(x: 2600), visible: screen)
        #expect(layout.flyoutX >= PanelGeometry.margin)
        #expect(layout.panelX + DeckTheme.panelWidth + PanelGeometry.margin <= layout.window.width)
        #expect(layout.window.maxY == 1600)
        #expect(layout.window.minY == screen.minY)
    }

    @Test func theDetailLinesUpWithItsRow() {
        let top = PanelGeometry.flyoutY(rowTop: 300, height: 500, windowHeight: 1600)
        #expect(top + PanelGeometry.verticalPadding == 300)
    }

    @Test func aLowRowKeepsTheDetailInsideTheWindow() {
        #expect(PanelGeometry.flyoutY(rowTop: 1500, height: 500, windowHeight: 1600) == 1100)
    }

    @Test func aDetailTallerThanTheScreenStartsAtTheTop() {
        #expect(PanelGeometry.flyoutY(rowTop: 300, height: 1600, windowHeight: 1600) == 0)
    }

    @Test func backdropFeathersToTransparentOnAllFourSides() throws {
        let image = try #require(PanelBackdropMask.make(size: CGSize(width: 460, height: 320), intensity: 0.62,
                                                      feather: .init(left: 110, right: 110, top: 48, bottom: 155)))
        let data = try #require(image.dataProvider?.data)
        let pixels = try #require(CFDataGetBytePtr(data))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[y * image.bytesPerRow + x * 4 + 3] }

        #expect(alpha(230, 4) < 5)
        #expect(alpha(230, 24) > 60)
        #expect(alpha(230, 80) > 145)
        #expect(alpha(230, 260) < alpha(230, 80))
        #expect(alpha(230, 313) < 5)
        #expect(alpha(8, 80) < 5)
        #expect(alpha(451, 80) < 5)
        #expect(alpha(55, 80) > 60)
        #expect(alpha(55, 80) == alpha(404, 80))
    }

    @Test func backgroundDepthHasAnIndependentMidpointAndFullRange() {
        let midpoint = PanelBackdropDepth.intensity(at: PanelBackdropDepth.defaultValue)
        #expect(PanelBackdropDepth.defaultValue == 0.5)
        #expect(PanelBackdropDepth.intensity(at: 0) == 0)
        #expect(midpoint > PanelBackdropDepth.intensity(at: 0.25))
        #expect(midpoint < PanelBackdropDepth.intensity(at: 0.75))
        #expect(PanelBackdropDepth.intensity(at: 1) > PanelBackdropDepth.intensity(at: 0.75))
        #expect(PanelBackdropDepth.intensity(at: 1) < 1)
    }

    @Test func pointerHighlightStaysOnTheRoundedRim() {
        let size = CGSize(width: 300, height: 120)
        let radius: CGFloat = 22
        #expect(DeckGlowAnchor.nearestEdge(to: CGPoint(x: 150, y: 38), size: size, radius: radius)
                == CGPoint(x: 150, y: 0))
        #expect(DeckGlowAnchor.nearestEdge(to: CGPoint(x: 280, y: 60), size: size, radius: radius)
                == CGPoint(x: 300, y: 60))
        #expect(DeckGlowAnchor.nearestEdge(to: CGPoint(x: 4, y: 4), size: size, radius: radius)
                == CGPoint(x: radius, y: 0))
    }

    @MainActor
    @Test func previousMaximumTransparencyIsNowTheMidpoint() throws {
        func luminance(_ gray: Double) -> Double {
            gray <= 0.04045 ? gray / 12.92 : pow((gray + 0.055) / 1.055, 2.4)
        }
        let lightInk = try #require(NSColor(DeckTheme.controlCenterLight.secondary).usingColorSpace(.sRGB))
        let darkInk = try #require(NSColor(DeckTheme.controlCenter.secondary).usingColorSpace(.sRGB))
        let lightWash = MenuPanelSurface.washOpacity(translucency: 0.5, isDark: false)
        let darkWash = MenuPanelSurface.washOpacity(translucency: 0.5, isDark: true)
        #expect(lightWash == 0.60)
        #expect(darkWash == 0.88)
        #expect(MenuPanelSurface.washOpacity(translucency: 1, isDark: false) < lightWash)
        #expect(MenuPanelSurface.washOpacity(translucency: 1, isDark: true) < darkWash)
        let lightOverBlack = luminance(lightWash * MenuPanelSurface.washGray(isDark: false))
        let darkOverWhite = darkWash * luminance(MenuPanelSurface.washGray(isDark: true)) + (1 - darkWash)
        #expect((lightOverBlack + 0.05) / (luminance(lightInk.redComponent) + 0.05) >= 4.5)
        #expect((luminance(darkInk.redComponent) + 0.05) / (darkOverWhite + 0.05) >= 4.5)
        #expect(lightWash < MenuPanelSurface.washOpacity(translucency: 0.20, isDark: false))
        #expect(darkWash < MenuPanelSurface.washOpacity(translucency: 0.20, isDark: true))
    }

    @MainActor
    @Test func compactTilesShareRowsAndSlidersStayFullWidth() {
        let sections = ["wifi", "bluetooth", "inputsource", "battery", "display", "sound"]
            .map { id in DeckSection(id: id, title: id) { EmptyView() } }
        #expect(PanelTileLayout.rows(sections).map { $0.map(\.id) }
                == [["wifi", "bluetooth"], ["inputsource", "battery"], ["display"], ["sound"]])
    }

    @MainActor
    @Test func anUnpairedTileDoesNotJumpAcrossAFullWidthRow() {
        let sections = ["bluetooth", "display", "wifi", "battery", "sound", "inputsource"]
            .map { id in DeckSection(id: id, title: id) { EmptyView() } }
        #expect(PanelTileLayout.rows(sections).map { $0.map(\.id) }
                == [["bluetooth"], ["display"], ["wifi", "battery"], ["sound"], ["inputsource"]])
    }
}

@Suite("Row under the pointer")
struct RowLookupTests {
    private let window = CGRect(x: 1000, y: 0, width: 660, height: 1600)
    private let frames = [
        "cpu": CGRect(x: 340, y: 40, width: 300, height: 200),
        "memory": CGRect(x: 340, y: 247, width: 300, height: 120)
    ]

    @Test func convertsFromTheScreenToTheWindow() {
        let point = PanelGeometry.localPoint(CGPoint(x: 1400, y: 1500), window: window)
        #expect(point == CGPoint(x: 400, y: 100))
    }

    @Test func findsTheRow() {
        #expect(PanelGeometry.row(at: CGPoint(x: 400, y: 100), frames: frames) == "cpu")
        #expect(PanelGeometry.row(at: CGPoint(x: 400, y: 300), frames: frames) == "memory")
    }

    @Test func theGapBetweenCardsIsNoRow() {
        #expect(PanelGeometry.row(at: CGPoint(x: 400, y: 243), frames: frames) == nil)
    }
}

@Suite("Hover intent")
struct HoverIntentTests {
    @Test func opensAfterARest() {
        var intent = HoverIntent()
        #expect(intent.update(rowID: "cpu", isHeadingToFlyout: false, now: 0) == nil)
        #expect(intent.update(rowID: "cpu", isHeadingToFlyout: false, now: HoverIntent.openDelay / 2) == nil)
        #expect(intent.update(rowID: "cpu", isHeadingToFlyout: false, now: HoverIntent.openDelay) == "cpu")
        #expect(intent.activeID == "cpu")
    }

    @Test func passingOverARowQuicklyOpensNothing() {
        var intent = HoverIntent()
        _ = intent.update(rowID: "cpu", isHeadingToFlyout: false, now: 0)
        #expect(intent.update(rowID: nil, isHeadingToFlyout: false, now: 0.05) == nil)
        #expect(intent.update(rowID: "cpu", isHeadingToFlyout: false, now: 0.06) == nil)
    }

    @Test func aRowOnTheWayToTheWindowDoesNotSwapIt() {
        var intent = HoverIntent()
        intent.force("cpu")
        #expect(intent.update(rowID: "memory", isHeadingToFlyout: true, now: 0) == nil)
        #expect(intent.update(rowID: "memory", isHeadingToFlyout: true, now: HoverIntent.switchDelay * 2) == nil)
        #expect(intent.activeID == "cpu")
    }

    @Test func stoppingOnARowEventuallySwapsEvenWhileAiming() {
        var intent = HoverIntent()
        intent.force("cpu")
        _ = intent.update(rowID: "memory", isHeadingToFlyout: true, now: 0)
        #expect(intent.update(rowID: "memory", isHeadingToFlyout: true, now: HoverIntent.headingDelay) == "memory")
    }

    @Test func browsingBetweenRowsSwitchesQuickly() {
        var intent = HoverIntent()
        intent.force("cpu")
        _ = intent.update(rowID: "memory", isHeadingToFlyout: false, now: 0)
        #expect(intent.update(rowID: "memory", isHeadingToFlyout: false, now: HoverIntent.switchDelay) == "memory")
    }

    @Test func theCurrentRowAndTheWindowChangeNothing() {
        var intent = HoverIntent()
        intent.force("cpu")
        #expect(intent.update(rowID: "cpu", isHeadingToFlyout: false, now: 5) == nil)
        #expect(intent.update(rowID: nil, isHeadingToFlyout: false, now: 6) == nil)
        #expect(intent.activeID == "cpu")
    }

    private let flyout = CGRect(x: 600, y: 400, width: 320, height: 600)

    @Test func movingTowardTheWindowCountsAsAiming() {
        let isHeading = HoverIntent.isHeading(from: CGPoint(x: 1100, y: 700), to: CGPoint(x: 1050, y: 690), toward: flyout)
        #expect(isHeading)
    }

    @Test func movingStraightDownTheRowsDoesNot() {
        let isHeading = HoverIntent.isHeading(from: CGPoint(x: 1100, y: 700), to: CGPoint(x: 1100, y: 500), toward: flyout)
        #expect(!isHeading)
    }

    @Test func movingAwayFromTheWindowDoesNot() {
        let isHeading = HoverIntent.isHeading(from: CGPoint(x: 1100, y: 700), to: CGPoint(x: 1150, y: 700), toward: flyout)
        #expect(!isHeading)
    }

    @Test func aPointerAtRestIsNotAiming() {
        let point = CGPoint(x: 1100, y: 700)
        #expect(!HoverIntent.isHeading(from: point, to: point, toward: flyout))
    }
}

@Suite("Media key routing")
struct MediaKeyRoutingTests {
    private func display(_ kind: DisplayState.Kind, builtIn: Bool = false) -> DisplayState {
        DisplayState(id: 1, name: "屏", isBuiltIn: builtIn, kind: kind, brightness: 0.5)
    }

    @Test func aMacWithNoMonitorKeepsItsOwnBrightnessKeys() {
        #expect(!MediaKeyRouting.takesBrightness(on: display(.apple, builtIn: true)))
    }

    @Test func standardFunctionKeysCanControlAppleDisplays() {
        #expect(MediaKeyRouting.takesBrightness(on: display(.apple, builtIn: true), isMediaEvent: false))
        #expect(MediaKeyRouting.takesBrightness(on: display(.apple), isMediaEvent: false))
    }

    @Test func thePointerOnAnUnknownScreenLeavesTheKeyToTheSystem() {
        #expect(!MediaKeyRouting.takesBrightness(on: nil))
    }

    @Test func appleMonitorsStayWithTheSystem() {
        #expect(!MediaKeyRouting.takesBrightness(on: display(.apple)))
    }

    @Test func otherMonitorsAreOurs() {
        #expect(MediaKeyRouting.takesBrightness(on: display(.ddc)))
        #expect(MediaKeyRouting.takesBrightness(on: display(.software)))
    }

    @Test func hardwareBrightnessRemainsAvailableWithTheBuiltInScreenOpen() {
        let builtIn = display(.apple, builtIn: true)
        #expect(!MediaKeyRouting.needsHardwareBrightnessListener(for: []))
        #expect(!MediaKeyRouting.needsHardwareBrightnessListener(for: [builtIn, display(.apple)]))
        #expect(MediaKeyRouting.needsHardwareBrightnessListener(for: [builtIn, display(.ddc)]))
        #expect(MediaKeyRouting.needsHardwareBrightnessListener(for: [display(.software), builtIn]))
    }

    @Test func speakersMacOSCanDriveStayWithTheSystem() {
        #expect(!MediaKeyRouting.takesVolume(route: .hardware, softwareEngineRuns: true))
        #expect(!MediaKeyRouting.takesVolume(route: .unavailable, softwareEngineRuns: true))
    }

    @Test func softwareVolumeNeedsItsEngine() {
        #expect(MediaKeyRouting.takesVolume(route: .software, softwareEngineRuns: true))
        #expect(MediaKeyRouting.takesVolume(route: .softwareAvailable, softwareEngineRuns: true))
        #expect(!MediaKeyRouting.takesVolume(route: .software, softwareEngineRuns: false))
        #expect(!MediaKeyRouting.takesVolume(route: .softwareAvailable, softwareEngineRuns: false))
    }

    @Test func ddcVolumeIsOurs() {
        #expect(MediaKeyRouting.takesVolume(route: .ddc(1), softwareEngineRuns: false))
    }

    @Test func aFineStepIsAQuarterOfANormalOne() {
        #expect(MediaKeyRouting.step(isFine: true) * 4 == MediaKeyRouting.step(isFine: false))
    }
}

@Suite("Appearance")
struct AppearanceTests {
    @Test func automaticLeavesTheWindowToMacOS() {
        #expect(PanelAppearance.system.isAutomatic)
        #expect(PanelAppearance.system.nsAppearance == nil)
        #expect(PanelAppearance.system.colorScheme(following: .light) == .light)
        #expect(PanelAppearance.system.colorScheme(following: .dark) == .dark)
    }

    @Test func aFixedModeIgnoresMacOS() {
        #expect(!PanelAppearance.light.isAutomatic)
        #expect(!PanelAppearance.dark.isAutomatic)
        #expect(PanelAppearance.light.nsAppearance?.name == .aqua)
        #expect(PanelAppearance.dark.nsAppearance?.name == .darkAqua)
        #expect(PanelAppearance.light.colorScheme(following: .dark) == .light)
        #expect(PanelAppearance.dark.colorScheme(following: .light) == .dark)
    }

    @Test func leavingAutomaticKeepsWhatIsShowing() {
        #expect(PanelAppearance.fixed(isDark: true) == .dark)
        #expect(PanelAppearance.fixed(isDark: false) == .light)
    }

    @Test func aSavedChoiceSurvivesARestart() {
        for appearance in PanelAppearance.allCases {
            #expect(PanelAppearance(rawValue: appearance.rawValue) == appearance)
        }
    }
}
