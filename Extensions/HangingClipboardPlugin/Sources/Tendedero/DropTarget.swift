import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Hanging things back: a picture dragged from Finder, a web page or any other
/// app and let go over the line goes up on it.
///
/// What a drag carries decides how it arrives:
/// - Image or video files hang where they are, like a screenshot.
/// - A promised file (Photos, some browsers) is received into Tendedero's folder.
/// - Raw image data is saved there as a PNG.
/// - A web image is downloaded there.
enum Dropper {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp", "bmp"]

    static func isMedia(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased()) || isRecording(url)
    }

    static let types: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .tiff, .png, .html]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    private static func fileURLs(_ pb: NSPasteboard) -> [URL] {
        (pb.readObjects(forClasses: [NSURL.self],
                        options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).map(resolved)
    }

    /// An old-style iCloud placeholder, ".name.png.icloud", stands for "name.png".
    private static func resolved(_ url: URL) -> URL {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), url.pathExtension == "icloud" else { return url }
        return url.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(7)))
    }

    /// A cloud file that is not on this Mac yet (iCloud Drive, OneDrive and
    /// the like keep only a stub until something reads it).
    private static func needsDownload(_ url: URL) -> Bool {
        var st = stat()
        if lstat(url.path, &st) != 0 { return true }
        return st.st_flags & 0x4000_0000 != 0 // SF_DATALESS
    }

    /// Brings a cloud file down, then calls back on the main thread. Reading
    /// it through a file coordinator makes the provider fetch it.
    private static func download(_ url: URL, done: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                _ = try? Data(contentsOf: readable, options: .alwaysMapped).first
            }
            // An iCloud download can land a little later than the coordinated read.
            var waited = 0.0
            while needsDownload(url), waited < 120 {
                Thread.sleep(forTimeInterval: 0.5)
                waited += 0.5
            }
            let ok = !needsDownload(url)
            DispatchQueue.main.async { done(ok) }
        }
    }

    private static func promises(_ pb: NSPasteboard) -> [NSFilePromiseReceiver] {
        pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
    }

    /// The address of a web image: a dragged link to one, or the picture a
    /// browser puts in the HTML it provides.
    private static func webImageURL(_ pb: NSPasteboard) -> URL? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls where !url.isFileURL && url.scheme?.hasPrefix("http") == true
                && imageExtensions.contains(url.pathExtension.lowercased()) {
                return url
            }
        }
        guard let html = pb.string(forType: .html),
              let range = html.range(of: #"<img[^>]*?\ssrc\s*=\s*["']([^"']+)["']"#,
                                     options: [.regularExpression, .caseInsensitive]),
              let src = html[range].range(of: #"["'][^"']+["']"#, options: .regularExpression)
        else { return nil }
        let text = html[range][src].dropFirst().dropLast()
        guard let url = URL(string: String(text)), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    static func isAcceptable(_ pb: NSPasteboard) -> Bool {
        let files = fileURLs(pb)
        // A drag of files is for them alone: a PDF is not a picture.
        if !files.isEmpty { return files.contains(where: isMedia) }
        if !promises(pb).isEmpty { return true }
        if pb.canReadObject(forClasses: [NSImage.self], options: nil) { return true }
        return webImageURL(pb) != nil
    }

    /// Reads what the drag carries and calls `hang` with each file, on the main
    /// thread, as soon as it is on disk.
    /// `busy` is told +1 when something starts arriving and -1 when it is done.
    @MainActor static func load(_ pb: NSPasteboard, busy: @escaping (Int) -> Void,
                                hang: @escaping (URL) -> Void) {
        let files = fileURLs(pb).filter(isMedia)
        if !files.isEmpty {
            for file in files {
                guard needsDownload(file) else { hang(file); continue }
                busy(1)
                download(file) { ok in
                    if ok { hang(file) } else { log.error("Could not download \(file.lastPathComponent, privacy: .public)") }
                    busy(-1)
                }
            }
            return
        }
        let promised = promises(pb)
        if !promised.isEmpty {
            let folder = Inbox.folder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for receiver in promised {
                busy(1)
                receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: .main) { url, error in
                    defer { busy(-1) }
                    if let error { log.error("Promised file failed: \(error.localizedDescription, privacy: .public)"); return }
                    guard isMedia(url) || makeThumbnail(url) != nil else { return }
                    hang(url)
                }
            }
            return
        }
        if let image = (pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first,
           let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            if let url = save(png, ext: "png") { hang(url) }
            return
        }
        if let web = webImageURL(pb) {
            busy(1)
            URLSession.shared.dataTask(with: web) { data, _, _ in
                guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
                      CGImageSourceGetCount(source) > 0 else {
                    DispatchQueue.main.async { busy(-1) }
                    return
                }
                var ext = web.pathExtension.lowercased()
                if !imageExtensions.contains(ext) {
                    let type = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }
                    ext = type?.preferredFilenameExtension ?? "png"
                }
                DispatchQueue.main.async {
                    if let url = save(data, ext: ext) { hang(url) }
                    busy(-1)
                }
            }.resume()
        }
    }

    /// Writes into Tendedero's folder under a fresh name.
    private static func save(_ data: Data, ext: String) -> URL? {
        let folder = Inbox.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Dropped \(f.string(from: Date())) \(UUID().uuidString.prefix(4)).\(ext)"
        let url = folder.appendingPathComponent(name)
        do { try data.write(to: url); return url } catch {
            log.error("Could not save dropped image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// What a view that accepts drops reports to the app. The views are only
/// destinations so the drag is really accepted: the source app then knows it
/// landed, instead of sliding the picture back.
@MainActor
final class DropTarget {
    /// The pointer moved during a drag over this view.
    var moved: () -> Void = {}
    /// Let go over this view.
    var dropped: (NSPasteboard) -> Bool = { _ in false }
    /// The drag is over, wherever it ended.
    var ended: () -> Void = {}

    func update(_ info: NSDraggingInfo) -> NSDragOperation {
        guard !GrabView.isDragging, Dropper.isAcceptable(info.draggingPasteboard) else { return [] }
        moved()
        return .copy
    }
}

final class DropHostingView<Content: View>: NSHostingView<Content> {
    let target = DropTarget()

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes(Dropper.types)
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError() }

    /// The line never takes focus, so the first click must already count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { target.update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { target.update(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        target.dropped(sender.draggingPasteboard)
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { target.ended() }
    override func draggingEnded(_ sender: NSDraggingInfo) { target.ended() }
}

/// Covers the menu bar while a picture is being dragged to it, so letting go
/// there is a drop like any other.
final class DropCatcher: NSPanel {
    let target = DropTarget()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        let view = CatcherView()
        view.target = target
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class CatcherView: NSView {
    var target: DropTarget?

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes(Dropper.types)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { target?.update(sender) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { target?.update(sender) ?? [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        target?.dropped(sender.draggingPasteboard) ?? false
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { target?.ended() }
    override func draggingEnded(_ sender: NSDraggingInfo) { target?.ended() }
}
