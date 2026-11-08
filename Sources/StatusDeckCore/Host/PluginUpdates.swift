import AppKit
import Foundation
import StatusDeckKit
import SwiftUI

struct UpstreamDescriptor: Codable, Equatable {
    var repository: String
    var commit: String
    var sourcePrefix: String?
    var adapter: String
    var files: [String: String]?
}

struct PluginUpdateRow: Identifiable {
    var id: String { package }
    let package: String
    let name: String
    var source: UpstreamDescriptor
    var latest: String?
    var message = ""
    var isBusy = false
    var error: String?
    var hasUpdate: Bool { latest.map { $0 != source.commit } ?? false }
}

/// Only the three reviewed adapters are supported. Upstream package manifests,
/// build scripts and standalone apps are never executed or installed.
@MainActor
final class PluginUpdateService: ObservableObject {
    @Published private(set) var rows: [PluginUpdateRow] = []
    @Published var pendingRestart = UserDefaults.standard.bool(forKey: "updates.pendingRestart")
    let pluginDirectory: URL
    private let files = FileManager.default
    private let templateOverride: URL?
    private let kitOverride: URL?
    private let session: URLSession
    private let allowed: [String: String] = ["HangingClipboardPlugin": "alejandrobujan/tendedero", "MosPlugin": "Caldis/Mos", "CodeIslandPlugin": "wxtsky/CodeIsland"]

    init(pluginDirectory: URL, templates: URL? = nil, kit: URL? = nil, session: URLSession = .shared) {
        self.pluginDirectory = pluginDirectory
        self.templateOverride = templates; self.kitOverride = kit; self.session = session
        reload()
    }

    private var templates: URL? { templateOverride ?? Bundle.main.resourceURL?.appendingPathComponent("ExtensionSources") }
    private var kit: URL? { kitOverride ?? Bundle.main.resourceURL?.appendingPathComponent("Packages/StatusDeckKit") }

    func reload() {
        guard let templates else { return }
        rows = allowed.keys.sorted().compactMap { package in
            let installed = pluginDirectory.appendingPathComponent(package + ".deckplugin")
            let template = templates.appendingPathComponent(package)
            guard let data = try? Data(contentsOf: template.appendingPathComponent("upstream.json")),
                  var source = try? JSONDecoder().decode(UpstreamDescriptor.self, from: data), source.repository == allowed[package],
                  let manifestData = try? Data(contentsOf: template.appendingPathComponent("plugin.json")),
                  let manifest = try? JSONDecoder().decode(ExternalPluginFile.self, from: manifestData) else { return nil }
            if let installedData = try? Data(contentsOf: installed.appendingPathComponent("upstream.json")),
               let previous = try? JSONDecoder().decode(UpstreamDescriptor.self, from: installedData),
               previous.repository == source.repository, Self.validSHA(previous.commit) { source.commit = previous.commit }
            return PluginUpdateRow(package: package, name: manifest.name, source: source)
        }
    }

    func checkAll() async {
        for package in rows.map(\.package) { await check(package) }
    }

    func check(_ package: String) async {
        guard let i = index(package), !rows[i].isBusy else { return }
        rows[i].isBusy = true; rows[i].error = nil
        defer { if let i = index(package) { rows[i].isBusy = false } }
        do {
            struct Commit: Decodable { let sha: String }
            let data = try await download(URL(string: "https://api.github.com/repos/\(rows[i].source.repository)/commits?per_page=1")!)
            guard let commit = try JSONDecoder().decode([Commit].self, from: data).first, Self.validSHA(commit.sha) else { throw UpdateError.invalidResponse }
            rows[i].latest = commit.sha
            rows[i].message = commit.sha == rows[i].source.commit ? DeckL("已是最新提交", "Up to date") : DeckL("有可构建的上游更新", "Upstream update available")
        } catch { rows[i].error = error.localizedDescription }
    }

    func install(_ package: String) async {
        guard let i = index(package), !rows[i].isBusy, let templates, let kit,
              allowed[package] == rows[i].source.repository else { return }
        rows[i].isBusy = true; rows[i].error = nil
        let stage = files.temporaryDirectory.appendingPathComponent("StatusDeck-Update-" + UUID().uuidString)
        defer {
            try? files.removeItem(at: stage)
            if let i = index(package) { rows[i].isBusy = false }
        }
        do {
            var descriptor = rows[i].source
            let revision = rows[i].latest ?? descriptor.commit
            guard Self.validSHA(revision) else { throw UpdateError.invalidResponse }
            let root = stage.appendingPathComponent("Extensions/" + package)
            try files.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.copyItem(at: templates.appendingPathComponent(package), to: root)
            let kitTarget = stage.appendingPathComponent("Packages/StatusDeckKit")
            try files.createDirectory(at: kitTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.copyItem(at: kit, to: kitTarget)
            setMessage(package, DeckL("正在拉取 GitHub 源码…", "Fetching GitHub source…"))
            let plan = try await sourcePlan(descriptor, revision: revision)
            if descriptor.adapter == "codeisland" {
                try files.removeItem(at: root.appendingPathComponent("Sources/CodeIslandCore"))
                try files.removeItem(at: root.appendingPathComponent("Sources/CodeIslandPlugin/Upstream"))
            } else if descriptor.adapter == "hanging" {
                let directory = root.appendingPathComponent("Sources/Tendedero")
                for file in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    where file.pathExtension == "swift" && !["DeckAdapter.swift", "Localization.swift"].contains(file.lastPathComponent) {
                    try files.removeItem(at: file)
                }
            }
            var total = 0
            for (remote, local) in plan {
                guard Self.safePath(local), Self.safePath(remote) else { throw UpdateError.invalidResponse }
                let url = URL(string: "https://raw.githubusercontent.com/\(descriptor.repository)/\(revision)/\(remote)")!
                let data = try await download(url)
                total += data.count
                guard total < 12 * 1024 * 1024 else { throw UpdateError.sourceTooLarge }
                let target = root.appendingPathComponent(local)
                try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
            }
            if ["hanging", "codeisland"].contains(descriptor.adapter) {
                _ = try await Self.run("/usr/bin/python3", [root.appendingPathComponent("adapt.py").path, root.path], cwd: stage)
            }
            descriptor.commit = revision
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(descriptor).write(to: root.appendingPathComponent("upstream.json"))
            setMessage(package, DeckL("正在构建插件…", "Building plugin…"))
            let scratch = stage.appendingPathComponent("Build")
            var arguments = ["swift", "build", "--disable-sandbox", "--package-path", root.path, "--scratch-path", scratch.path, "--cache-path", stage.appendingPathComponent("Cache").path, "-c", "release", "-j", "4"]
            _ = try await Self.run("/usr/bin/xcrun", arguments, cwd: stage)
            arguments.append("--show-bin-path")
            let bin = try await Self.run("/usr/bin/xcrun", arguments, cwd: stage).trimmingCharacters(in: .whitespacesAndNewlines)
            let data = try Data(contentsOf: root.appendingPathComponent("plugin.json"))
            var manifest = try JSONDecoder().decode(ExternalPluginFile.self, from: data)
            guard manifest.apiVersion == DeckPluginAPI.version, Self.safePath(manifest.library), !manifest.library.contains("/") else { throw UpdateError.invalidResponse }
            let payload = stage.appendingPathComponent(package + ".deckplugin")
            try files.createDirectory(at: payload, withIntermediateDirectories: true)
            let library = payload.appendingPathComponent(manifest.library)
            try files.copyItem(at: URL(fileURLWithPath: bin).appendingPathComponent(manifest.library), to: library)
            for url in (try? files.contentsOfDirectory(at: URL(fileURLWithPath: bin), includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "bundle" {
                try files.copyItem(at: url, to: payload.appendingPathComponent(url.lastPathComponent))
            }
            manifest.version = "git-" + revision.prefix(10)
            try encoder.encode(manifest).write(to: payload.appendingPathComponent("plugin.json"))
            try encoder.encode(descriptor).write(to: payload.appendingPathComponent("upstream.json"))
            if files.fileExists(atPath: root.appendingPathComponent("LICENSE").path) { try files.copyItem(at: root.appendingPathComponent("LICENSE"), to: payload.appendingPathComponent("LICENSE")) }
            _ = try await Self.run("/usr/bin/install_name_tool", ["-add_rpath", "@executable_path/../Frameworks", library.path], cwd: stage)
            _ = try await Self.run("/usr/bin/codesign", ["--force", "--sign", "-", library.path], cwd: stage)
            setMessage(package, DeckL("正在验证插件…", "Verifying plugin…"))
            guard let executable = Bundle.main.executableURL else { throw UpdateError.invalidResponse }
            _ = try await Self.run(executable.path, ["--verify-plugin", payload.path], cwd: stage)
            try files.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
            let destination = pluginDirectory.appendingPathComponent(package + ".deckplugin")
            let backup = backupURL(package)
            if files.fileExists(atPath: backup.path) { try files.removeItem(at: backup) }
            let hadPrevious = files.fileExists(atPath: destination.path)
            if hadPrevious { try files.moveItem(at: destination, to: backup) }
            do { try files.moveItem(at: payload, to: destination) }
            catch {
                if hadPrevious { try? files.moveItem(at: backup, to: destination) }
                throw error
            }
            UserDefaults.standard.set(ExternalPluginLoader.fingerprint(of: destination.appendingPathComponent(manifest.library)), forKey: "plugin.approvedFingerprint.\(manifest.id)")
            rows[i].source = descriptor
            setPendingRestart()
            setMessage(package, DeckL("已安装，重启 MyStatus 后生效", "Installed. Restart MyStatus to load it."))
        } catch {
            rows[i].error = error.localizedDescription
            setMessage(package, DeckL("更新未安装，继续使用原版本", "Update not installed. The current version is unchanged."))
        }
    }

    func canRollback(_ package: String) -> Bool { files.fileExists(atPath: backupURL(package).path) }

    func rollback(_ package: String) {
        guard allowed[package] != nil, canRollback(package), let i = index(package), !rows[i].isBusy else { return }
        let current = pluginDirectory.appendingPathComponent(package + ".deckplugin")
        let displaced = pluginDirectory.appendingPathComponent(package + ".rollback-temporary")
        do {
            if files.fileExists(atPath: displaced.path) { try files.removeItem(at: displaced) }
            if files.fileExists(atPath: current.path) { try files.moveItem(at: current, to: displaced) }
            do { try files.moveItem(at: backupURL(package), to: current) }
            catch { try? files.moveItem(at: displaced, to: current); throw error }
            if files.fileExists(atPath: displaced.path) { try files.moveItem(at: displaced, to: backupURL(package)) }
            let item = ExternalPluginLoader.read(current)
            if let id = item.file?.id, let library = item.libraryURL { UserDefaults.standard.set(ExternalPluginLoader.fingerprint(of: library), forKey: "plugin.approvedFingerprint.\(id)") }
            reload(); setPendingRestart()
        } catch { rows[i].error = error.localizedDescription }
    }

    private func sourcePlan(_ descriptor: UpstreamDescriptor, revision: String) async throws -> [(String, String)] {
        if let mapping = descriptor.files { return mapping.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } + [("LICENSE", "LICENSE")] }
        guard let prefix = descriptor.sourcePrefix, Self.safePath(prefix) else { throw UpdateError.invalidResponse }
        struct Tree: Decodable { struct Item: Decodable { var path: String; var type: String }; var tree: [Item]; var truncated: Bool? }
        let data = try await download(URL(string: "https://api.github.com/repos/\(descriptor.repository)/git/trees/\(revision)?recursive=1")!)
        let tree = try JSONDecoder().decode(Tree.self, from: data)
        guard tree.truncated != true else { throw UpdateError.invalidResponse }
        let desktop = "Sources/CodeIsland/"
        let source = tree.tree.filter { item in
            guard item.type == "blob" else { return false }
            if item.path.hasPrefix(prefix) { return item.path.hasSuffix(".swift") || item.path.hasSuffix(".strings") }
            if descriptor.adapter == "codeisland", item.path.hasPrefix(desktop) {
                return [".swift", ".strings", ".ts", ".js", ".json", ".py", ".png", ".wav", ".car"].contains { item.path.hasSuffix($0) }
            }
            return false
        }
        guard !source.isEmpty, source.count <= 320 else { throw UpdateError.invalidResponse }
        return source.map { item in
            let local = item.path.hasPrefix(desktop)
                ? "Sources/CodeIslandPlugin/Upstream/" + item.path.dropFirst(desktop.count)
                : item.path
            return (item.path, local)
        } + [("LICENSE", "LICENSE")]
    }

    private func download(_ url: URL) async throws -> Data {
        guard ["api.github.com", "raw.githubusercontent.com"].contains(url.host ?? "") else { throw UpdateError.invalidResponse }
        var request = URLRequest(url: url); request.timeoutInterval = 45
        request.setValue("StatusDeck-Plugin-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw UpdateError.network }
        guard data.count <= 4 * 1024 * 1024 else { throw UpdateError.sourceTooLarge }
        return data
    }

    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.split(separator: "/").contains("..")
    }
    static func validSHA(_ value: String) -> Bool { value.count == 40 && value.allSatisfy { $0.isHexDigit && $0.isASCII } }
    private func index(_ package: String) -> Int? { rows.firstIndex { $0.package == package } }
    private func backupURL(_ package: String) -> URL { pluginDirectory.appendingPathComponent(package + ".previous") }
    private func setMessage(_ package: String, _ message: String) { if let i = index(package) { rows[i].message = message } }
    private func setPendingRestart() { pendingRestart = true; UserDefaults.standard.set(true, forKey: "updates.pendingRestart") }

    nonisolated private static func run(_ path: String, _ arguments: [String], cwd: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let task = Process(); task.executableURL = URL(fileURLWithPath: path); task.arguments = arguments; task.currentDirectoryURL = cwd
            var env = ProcessInfo.processInfo.environment
            let cache = cwd.appendingPathComponent("ModuleCache").path
            env["CLANG_MODULE_CACHE_PATH"] = cache; env["SWIFTPM_MODULECACHE_OVERRIDE"] = cache
            task.environment = env
            let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
            try task.run()
            let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 240, execute: timeout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit(); timeout.cancel()
            let output = String(decoding: data, as: UTF8.self)
            guard task.terminationStatus == 0 else { throw UpdateError.build(String(output.suffix(6000))) }
            return output
        }.value
    }
}

private enum UpdateError: LocalizedError {
    case invalidResponse, network, sourceTooLarge, build(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return DeckL("上游结构或插件接口已改变，需要更新适配器。", "The upstream structure or plugin API changed. This adapter needs an update.")
        case .network: return DeckL("GitHub 请求失败或达到速率限制，请稍后重试。", "GitHub request failed or was rate limited. Try again later.")
        case .sourceTooLarge: return DeckL("源码超过此适配器允许的大小。", "Source exceeds the adapter's size limit.")
        case let .build(log): return log
        }
    }
}

struct PluginUpdatesView: View {
    @ObservedObject var service: PluginUpdateService
    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(DeckL("GitHub 插件更新", "GitHub plugin updates")).font(.title2.bold())
                        Text(DeckL("拉取源码并在本机重新构建插件", "Fetch source and rebuild plugins on this Mac")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(DeckL("检查全部", "Check all")) { Task { await service.checkAll() } }.disabled(service.rows.contains { $0.isBusy })
                }
            }
            if service.pendingRestart {
                Section { Label(DeckL("更新已就绪。退出并重新打开 MyStatus 后载入。", "Updates are ready. Quit and reopen MyStatus to load them."), systemImage: "arrow.clockwise.circle") }
            }
            ForEach(service.rows) { row in
                Section(DeckL(row.name)) {
                    Text(row.source.repository).font(.callout.monospaced()).foregroundStyle(.secondary)
                    LabeledContent(DeckL("当前提交", "Current commit"), value: String(row.source.commit.prefix(10)))
                    if let latest = row.latest { LabeledContent(DeckL("最新提交", "Latest commit"), value: String(latest.prefix(10))) }
                    HStack {
                        if row.isBusy { ProgressView().controlSize(.small) }
                        if !row.message.isEmpty { Text(row.message).font(.callout).foregroundStyle(.secondary) }
                    }
                    if let error = row.error { Text(error).font(.caption.monospaced()).foregroundStyle(.orange).textSelection(.enabled) }
                    HStack {
                        Button(DeckL("检查更新", "Check")) { Task { await service.check(row.package) } }
                        Button(row.hasUpdate ? DeckL("构建并更新", "Build update") : DeckL("重新构建安装", "Rebuild and install")) { Task { await service.install(row.package) } }
                        if service.canRollback(row.package) { Button(DeckL("回退旧版", "Roll back")) { service.rollback(row.package) } }
                    }.disabled(row.isBusy)
                }
            }
            Section {
                Text(DeckL("需要 Xcode Command Line Tools。构建失败时保留现有插件；上游改动超出适配范围时，会在这里显示原因。所有扩展运行在 MyStatus 内，不安装独立 App。", "Requires Xcode Command Line Tools. Failed builds preserve existing plugins; incompatible upstream changes appear here. All extensions run inside MyStatus without installing standalone apps."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
