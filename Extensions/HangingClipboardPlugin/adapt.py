from pathlib import Path
import sys
src=Path(sys.argv[1])/'Sources/Tendedero'
# Retain the original controller in a separate module, while eliminating app lifecycle ownership.
a=src/'AppDelegate.swift'; s=a.read_text()
s=s.replace('    private let line = Line()','    let line = Line()\n    private var pluginObservers: [(NotificationCenter, NSObjectProtocol)] = []')
s=s.replace('        restoreSettingsOnTermination()','        // The host owns process signals.')
s=s.replace('        setUpStatusItem()','        // The host owns the menu bar.')
s=s.replace('        if !Inbox.wasOffered {','        if false && !Inbox.wasOffered {').replace('        if !UserDefaults.standard.bool(forKey: "welcomed") {','        if false && !UserDefaults.standard.bool(forKey: "welcomed") {')
s=s.replace('workspace.addObserver(forName: name, object: nil, queue: .main) {','let token = workspace.addObserver(forName: name, object: nil, queue: .main) {')
s=s.replace('''                }
            }
        }

        NotificationCenter.default.addObserver(''','''                }
            }
            pluginObservers.append((workspace, token))
        }

        let screenToken = NotificationCenter.default.addObserver(''',1)
s=s.replace('''        if false && !Inbox.wasOffered {''','''        pluginObservers.append((NotificationCenter.default, screenToken))
        if false && !Inbox.wasOffered {''',1)
s=s.replace('    private func updateStatusIcon() {','    private func updateStatusIcon() {\n        guard statusItem != nil else { return }')
s=s.replace('    private func setClipboard(', '    func setClipboard(').replace('    private func toggle()', '    func toggle()')
s=s.replace('''    func applicationWillTerminate(_ notification: Notification) {
        if Inbox.isEnabled { Inbox.restore() }
    }''','''    func applicationWillTerminate(_ notification: Notification) { stopPlugin() }

    func stopPlugin() {
        mouseTimer?.invalidate(); mouseTimer = nil
        watcher?.stop(); safetyWatcher?.stop()
        folderWatchers.forEach { $0.stop() }; folderWatchers = []
        clipboardWatcher?.stop()
        hotKey = nil
        clickMonitors.forEach { NSEvent.removeMonitor($0) }; clickMonitors = []
        pluginObservers.forEach { $0.0.removeObserver($0.1) }; pluginObservers = []
        signalSources.forEach { $0.cancel() }; signalSources = []
        cancellables.removeAll()
        wanted = false; keepOpen = false
        panel?.orderOut(nil); catcher.orderOut(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        Markup.shared.onSaved = nil; Trim.shared.onSaved = nil
        if Inbox.isEnabled { Inbox.restore() }
    }''')
# The process must never be terminated from an embedded plugin.
s=s.replace('NSApp.terminate(nil)', 'self?.stopPlugin()')
s=s.replace('@objc private func toggle()', '@objc func toggle()')
s=s.replace('Markup.shared.onSaved = nil; Trim.shared.onSaved = nil', 'Markup.shared.onSaved = { _ in }; Trim.shared.onSaved = { _ in }').replace('self?.stopPlugin()', 'self.stopPlugin()')
a.write_text(s)

(src/'main.swift').unlink(missing_ok=True)
(src/'Localization.swift').write_text((Path(__file__).parent/'Localization.adapter.swift.txt').read_text())

for file in src.glob('*.swift'):
    if file.name not in ['DeckAdapter.swift','Localization.swift']:
        file.write_text(file.read_text().replace('UserDefaults.standard','HangingPreferences.store'))

p=src/'HotKey.swift'
s=p.read_text().replace("InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in", """InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var pressed = EventHotKeyID()
                guard let event,
                      GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed) == noErr,
                      pressed.signature == OSType(0x5445_4E44), pressed.id == 1 else { return OSStatus(eventNotHandledErr) }
""")
p.write_text(s)

p=src/'AppDelegate.swift'
p.write_text(p.read_text().replace('panel?.orderOut(nil); catcher.orderOut(nil)', 'panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil; catcher.orderOut(nil)'))
