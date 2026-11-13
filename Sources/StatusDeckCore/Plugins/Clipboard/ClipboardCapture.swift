import AppKit
import Foundation

/// How macOS treats this app reading the general pasteboard (macOS 15.4 and later).
enum ClipboardAccess: Equatable {
    case allowed
    /// Each read may show the system's "paste from another app" alert.
    case willAsk
    case denied

    static func current(for pasteboard: NSPasteboard) -> ClipboardAccess {
        if #available(macOS 15.4, *) {
            switch pasteboard.accessBehavior {
            case .alwaysAllow: return .allowed
            case .alwaysDeny: return .denied
            default: return .willAsk
            }
        }
        return .allowed
    }
}

/// The capture engine's small system boundary; named pasteboards can be denied
/// to developer/test runners even when the real application has access.
protocol CapturePasteboard: AnyObject {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    @discardableResult func clearContents() -> Int
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}
extension NSPasteboard: CapturePasteboard {}

/// Watches a pasteboard and records what lands on it.
///
/// macOS offers no notification for this, so it checks `changeCount` twice a second,
/// which costs next to nothing. The contents are only read after a change, on a
/// background queue, since that read can wait on a large copy or a system alert.
final class ClipboardCapture {
    struct Options: Sendable {
        var isPaused = false
        var blockedApps: Set<String> = []
        var maximumItemBytes = 64 * 1024 * 1024
        var maximumItems = 1000
        var maximumAge: TimeInterval? = 30 * 86400
    }

    /// Called on the capture queue after the history changed.
    var onChange: (() -> Void)?

    private let pasteboard: any CapturePasteboard
    private let store: ClipboardStore
    private let source: () -> (bundleID: String?, name: String?)
    private let queue = DispatchQueue(label: "statusdeck.clipboard.capture", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private var options = Options()

    convenience init(pasteboard: NSPasteboard, store: ClipboardStore,
        source: @escaping () -> (bundleID: String?, name: String?) = ClipboardCapture.frontmostApplication) {
        self.init(pasteboardBackend: pasteboard, store: store, source: source)
    }

    init(
        pasteboardBackend pasteboard: any CapturePasteboard,
        store: ClipboardStore,
        source: @escaping () -> (bundleID: String?, name: String?) = ClipboardCapture.frontmostApplication
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.source = source
        // What was already on the clipboard before this started is not a new copy.
        lastChangeCount = pasteboard.changeCount
    }

    static func frontmostApplication() -> (bundleID: String?, name: String?) {
        let application = NSWorkspace.shared.frontmostApplication
        return (application?.bundleIdentifier, application?.localizedName)
    }

    func setOptions(_ newOptions: Options) {
        queue.async { [self] in
            options = newOptions
            store.purge(maximumItems: newOptions.maximumItems, maximumAge: newOptions.maximumAge)
        }
    }

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            lastChangeCount = pasteboard.changeCount
            store.purge(maximumItems: options.maximumItems, maximumAge: options.maximumAge)
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(150))
            source.setEventHandler { [weak self] in self?.poll() }
            source.resume()
            timer = source
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    /// Checks once, immediately, and waits for the result.
    func pollNow() {
        queue.sync { poll() }
    }

    /// Puts an entry back on the pasteboard exactly as it was copied, flavors and
    /// all, without recording that as a new copy. False if nothing could be restored.
    @discardableResult
    func restore(_ id: Int64) -> Bool {
        queue.sync {
            let representations = store.representations(of: id)
            guard !representations.isEmpty else { return false }
            let groups = Dictionary(grouping: representations, by: \.itemIndex)
            let items = groups.keys.sorted().map { index -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for representation in groups[index] ?? [] {
                    item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
                }
                return item
            }
            pasteboard.clearContents()
            guard pasteboard.writeObjects(items) else { return false }
            lastChangeCount = pasteboard.changeCount
            store.touch(id)
            return true
        }
    }

    @discardableResult
    func restorePlainText(_ id: Int64) -> Bool {
        queue.sync {
            let representations = store.representations(of: id)
            guard let text = ClipboardPlainText.from(representations), !text.isEmpty else { return false }
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else { return false }
            lastChangeCount = pasteboard.changeCount
            store.touch(id)
            return true
        }
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard !options.isPaused else { return }

        // The types are checked before any content is read, so a concealed password
        // is never even loaded into this process.
        let types = pasteboard.types?.map(\.rawValue) ?? []
        let application = source()
        guard !ClipboardPrivacy.shouldSkip(types: types, sourceBundleID: application.bundleID, blockedApps: options.blockedApps) else {
            return
        }

        let items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (type: String, data: Data)? in
                item.data(forType: type).map { (type.rawValue, $0) }
            }
        }
        guard let payload = ClipboardPayload.make(items: items, maxBytes: options.maximumItemBytes) else { return }
        store.insert(payload, sourceBundleID: application.bundleID, sourceName: application.name)
        store.purge(maximumItems: options.maximumItems, maximumAge: options.maximumAge)
        onChange?()
    }
}
