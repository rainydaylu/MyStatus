import StatusDeckKit
import SwiftUI

struct PanelDrilldown {
    let id: String
    let title: String
    let anchor: CGRect?
    let content: AnyView
}

struct PanelDrilldownTarget {
    let frame: CGRect
    let make: () -> PanelDrilldown
}

struct PanelDrilldownActions {
    let selected: String?
    let open: (PanelDrilldown) -> Void
    let track: (String, PanelDrilldownTarget?) -> Void
}

private struct PanelDrilldownsKey: EnvironmentKey {
    static let defaultValue: PanelDrilldownActions? = nil
}

extension EnvironmentValues {
    var panelDrilldowns: PanelDrilldownActions? {
        get { self[PanelDrilldownsKey.self] }
        set { self[PanelDrilldownsKey.self] = newValue }
    }
}

private struct DrilldownAnchorKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

struct PanelDrilldownLink<Label: View, Detail: View>: View {
    let id: String
    let title: String
    @ViewBuilder let label: () -> Label
    @ViewBuilder let detail: () -> Detail
    @Environment(\.panelDrilldowns) private var actions
    @Environment(\.deckTheme) private var theme
    @State private var anchor: CGRect?

    var body: some View {
        if let actions {
            Button {
                actions.open(makeDrilldown(anchor: anchor))
            } label: {
                label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .background {
                    if actions.selected == id {
                        RoundedRectangle(cornerRadius: 6).fill(theme.accent.opacity(0.12))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: DrilldownAnchorKey.self,
                                           value: proxy.frame(in: .named(PanelGeometry.coordinateSpace)))
                }
            }
            .onPreferenceChange(DrilldownAnchorKey.self) { frame in
                anchor = frame
                actions.track(id, frame.map { frame in
                    PanelDrilldownTarget(frame: frame) { makeDrilldown(anchor: frame) }
                })
            }
            .onDisappear { actions.track(id, nil) }
        } else {
            label()
        }
    }

    private func makeDrilldown(anchor: CGRect?) -> PanelDrilldown {
        PanelDrilldown(id: id, title: title, anchor: anchor, content: AnyView(detail()))
    }
}
