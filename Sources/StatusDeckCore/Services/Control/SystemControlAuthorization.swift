import Combine
import CryptoKit
import Darwin
import Foundation
import StatusDeckKit

/// Shared, narrowly scoped administrator authorization for the bundled helper.
@MainActor
final class SystemControlAuthorization: ObservableObject {
    @Published private(set) var isAuthorizing = false
    @Published private(set) var error: String?
    private var callbacks: [(Bool) -> Void] = []
    private let isDryRun: Bool

    init(isDryRun: Bool) { self.isDryRun = isDryRun }

    let helperPath = "/Library/PrivilegedHelperTools/local.statusdeck.controls.v2.\(getuid())"
    var isAuthorized: Bool { !isDryRun && Self.isInstalled(helperPath) }

    var bundledHelper: URL? { Bundle.main.url(forAuxiliaryExecutable: "mystatus-fan-helper") }

    func authorize(completion: @escaping (Bool) -> Void = { _ in }) {
        if isAuthorized { completion(true); return }
        guard !isDryRun else { completion(false); return }
        callbacks.append(completion)
        guard !isAuthorizing else { return }
        guard let bundled = bundledHelper, FileManager.default.isExecutableFile(atPath: bundled.path),
              let bytes = try? Data(contentsOf: bundled) else {
            finish(false, error: DeckL("当前应用缺少系统控制辅助程序。", "This build is missing the system control helper."))
            return
        }

        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let command = """
            set -eu
            /usr/bin/install -d -o root -g wheel -m 0755 /Library/PrivilegedHelperTools
            tmp=$(/usr/bin/mktemp /Library/PrivilegedHelperTools/.mystatus-controls.XXXXXX)
            trap '/bin/rm -f "$tmp"' 0
            /bin/cp \(Self.shellQuote(bundled.path)) "$tmp"
            checksum=$(/usr/bin/shasum -a 256 "$tmp")
            test "${checksum%% *}" = '\(digest)'
            /usr/sbin/chown root:wheel "$tmp"
            /bin/chmod 4755 "$tmp"
            /bin/mv -f "$tmp" \(Self.shellQuote(helperPath))
            """
        let script = """
            on run argv
                do shell script (item 1 of argv) with administrator privileges
            end run
            """
        isAuthorizing = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = Subprocess.output("/usr/bin/osascript", ["-e", script, "--", command], timeout: 120) != nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let authorized = success && self.isAuthorized
                    self.finish(authorized, error: authorized ? nil : DeckL("管理员授权未完成。", "Administrator authorization did not complete."))
                }
            }
        }
    }

    private func finish(_ success: Bool, error: String?) {
        self.error = error
        isAuthorizing = false
        let pending = callbacks
        callbacks.removeAll()
        for callback in pending { callback(success) }
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func isInstalled(_ path: String) -> Bool {
        var metadata = stat()
        guard FileManager.default.isExecutableFile(atPath: path), lstat(path, &metadata) == 0 else { return false }
        let mode = metadata.st_mode
        return metadata.st_uid == 0 && mode & S_IFMT == S_IFREG && mode & S_ISUID != 0 && mode & 0o022 == 0
    }

    nonisolated static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        guard isInstalled(path) else { return nil }
        return Subprocess.output(path, arguments, timeout: timeout)
    }
}
