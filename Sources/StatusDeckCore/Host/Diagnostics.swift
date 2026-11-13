import StatusDeckKit
import AppKit
import CoreAudio
import CoreGraphics
import CPrivateAPI
import Foundation

/// `--diagnose-audio`: prints what every display and audio device actually answers.
/// With `--write`, nudges each display's volume and reads it back, then restores it.
enum Diagnostics {
    static func runCPU() {
        let kinds = CPUReader.readCoreKinds()
        for kind in CoreKind.allCases {
            let ids = kinds.filter { $0.value == kind }.keys.sorted()
            if !ids.isEmpty { print("\(kind.title): count=\(ids.count), ids=\(ids)") }
        }
        let reader = CPUReader()
        let soc = IOReportReader()
        _ = reader.read()
        _ = soc?.read()
        Thread.sleep(forTimeInterval: 1)
        let cpu = reader.read()
        let sample = soc?.read() ?? SoCStats()
        for kind in cpu.coreKinds {
            print("\(kind.title): load=\(Format.percent(cpu.average(of: kind))), frequency=\(Format.gigahertz(sample.frequency(for: kind)))")
        }
    }

    @MainActor
    static func runAudio(write: Bool) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        let displays = Array(ids.prefix(Int(count)))
        print("online displays:", displays, "main:", CGMainDisplayID())

        for match in Arm64DDC.getServiceMatches(displayIDs: displays) {
            let name = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == match.displayID
            }?.localizedName ?? "?"
            print("DDC service for \(name) id=\(match.displayID) score=\(match.matchScore) dummy=\(match.dummy) hasService=\(match.service != nil)")
            guard let service = match.service else { continue }
            for (label, code) in [("luminance 0x10", UInt8(0x10)), ("contrast 0x12", 0x12), ("volume 0x62", 0x62), ("mute 0x8D", 0x8D), ("input 0x60", 0x60)] {
                if let value = Arm64DDC.read(service: service, command: code, numOfRetryAttemps: 3) {
                    print("  read \(label): current=\(value.current) max=\(value.max)")
                } else {
                    print("  read \(label): no answer")
                }
                usleep(60_000)
            }
            print("  capabilities:", capabilities(service))
            if write, let before = Arm64DDC.read(service: service, command: 0x62, numOfRetryAttemps: 3) {
                let far = before.current > 30 ? before.current - 15 : before.current + 15
                let accepted = Arm64DDC.write(service: service, command: 0x62, value: far, numOfWriteCycles: 4)
                for delay in [200_000, 800_000, 1_500_000] as [UInt32] {
                    usleep(delay)
                    print("  long test wrote \(far) accepted=\(accepted), read after \(delay / 1000) ms:", Arm64DDC.read(service: service, command: 0x62, numOfRetryAttemps: 3)?.current as Any)
                }
                _ = Arm64DDC.write(service: service, command: 0x62, value: before.current, numOfWriteCycles: 4)
            }
            guard write, let before = Arm64DDC.read(service: service, command: 0x62, numOfRetryAttemps: 3) else { continue }
            let target = before.current >= 2 ? before.current - 2 : before.current + 2
            let accepted = Arm64DDC.write(service: service, command: 0x62, value: target)
            usleep(300_000)
            let after = Arm64DDC.read(service: service, command: 0x62, numOfRetryAttemps: 3)
            print("  write volume \(before.current) -> \(target): accepted=\(accepted) readBack=\(after.map { String($0.current) } ?? "no answer")")
            _ = Arm64DDC.write(service: service, command: 0x62, value: before.current)
            usleep(300_000)
            let restored = Arm64DDC.read(service: service, command: 0x62, numOfRetryAttemps: 3)
            print("  restored to \(before.current): readBack=\(restored.map { String($0.current) } ?? "no answer")")
        }

        if #available(macOS 15.4, *) {
            print("general pasteboard access behavior:", NSPasteboard.general.accessBehavior.rawValue, "(0 default, 1 ask, 2 always allow, 3 always deny)")
        }
        let controller = CoreAudioOutputController()
        let current = controller.defaultOutputDeviceID()
        print("default output id:", current as Any)
        for device in controller.outputDevices() {
            print("output \(device.name ?? "?"): id=\(device.id) current=\(device.isCurrent) transport=\(String(describing: device.transport)) volume=\(device.volume.map { String(format: "%.2f", $0) } ?? "nil") uid=\(device.uid ?? "?") settable=\(settableElements(device.id))")
        }
    }

    /// VCP capabilities request (0xF3), read fragment by fragment.
    private static func capabilities(_ service: IOAVService) -> String {
        var text = ""
        var offset: UInt16 = 0
        for _ in 0..<40 {
            var send: [UInt8] = [0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)]
            var reply = [UInt8](repeating: 0, count: 38)
            // A short fragment fails the fixed-position checksum, but the bytes are still valid.
            _ = Arm64DDC.performDDCCommunication(service: service, send: &send, reply: &reply, numOfRetryAttemps: 1)
            let length = Int(reply[1] & 0x7F)
            guard reply[2] == 0xE3, length > 3 else { break }
            let count = min(length - 3, reply.count - 6)
            guard count > 0 else { break }
            text += String(decoding: reply[5..<(5 + count)].filter { $0 != 0 }, as: UTF8.self)
            offset += UInt16(count)
            usleep(50_000)
        }
        return text.isEmpty ? "(no answer)" : text
    }

    /// `--diagnose-softvolume`: asks for the permission if needed, then runs the real tap
    /// and aggregate device for a few seconds and plays a short sound through them. Run it
    /// from the app bundle, because macOS attributes the audio permission to the bundle.
    @MainActor
    static func runSoftwareVolume() {
        guard #available(macOS 14.2, *) else {
            print("requires macOS 14.2")
            return
        }
        let audio = AudioController()
        guard let output = audio.currentOutput, let uid = output.uid else {
            print("no current output")
            return
        }
        print("output: \(output.name ?? "?") transport=\(String(describing: output.transport)) hardwareVolume=\(audio.volume.map { String($0) } ?? "nil")")
        print("permission before:", AudioCapturePermission.status)
        // Checks only that the audio path builds and runs. Without permission the tap
        // delivers silence, so this plays nothing and runs just long enough to tell.
        if CommandLine.arguments.contains("--wiring-only") {
            do {
                let engine = try SoftwareVolumeEngine(outputUID: uid, initialGain: 1)
                print("engine started")
                RunLoop.main.run(until: Date().addingTimeInterval(3))
                print("callbacks=\(Int(engine.diagnostics.callbacks))")
            } catch {
                print("engine failed:", error.localizedDescription)
            }
            print("engine stopped; output path restored")
            return
        }
        if AudioCapturePermission.status == .unknown {
            print("asking for permission...")
            var answered = false
            AudioCapturePermission.request { granted in
                print("permission answer:", granted)
                answered = true
            }
            let deadline = Date().addingTimeInterval(90)
            while !answered, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            }
        }
        print("permission now:", AudioCapturePermission.status)
        guard AudioCapturePermission.status == .authorized else {
            print("not authorized; engine not started")
            return
        }
        do {
            // A slider at 50% is a gain of 0.25, so the output peak should be a quarter of the input.
            let engine = try SoftwareVolumeEngine(outputUID: uid, initialGain: 0.25)
            print("engine started")
            let play = {
                let sound = Process()
                sound.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                sound.arguments = ["/System/Library/Sounds/Tink.aiff"]
                try? sound.run()
            }
            for second in 1...6 {
                engine.resetPeaks()
                if second % 2 == 1 { play() }
                RunLoop.main.run(until: Date().addingTimeInterval(1))
                let stats = engine.diagnostics
                print("t=\(second)s callbacks=\(Int(stats.callbacks)) inputPeak=\(String(format: "%.4f", stats.inputPeak)) outputPeak=\(String(format: "%.4f", stats.outputPeak))")
            }
        } catch {
            print("engine failed:", error.localizedDescription)
        }
        print("engine stopped; output path restored")
    }

    private static func settableElements(_ id: AudioDeviceID) -> [UInt32] {
        [kAudioObjectPropertyElementMain, 1, 2].filter { element in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(id, &address) else { return false }
            var settable: DarwinBoolean = false
            return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
        }
    }

    /// Whether keys can be received, then lists every media key pressed in the next
    /// 20 seconds without taking it. Run from the bundle, as macOS checks access by app.
    static func runKeys() {
        print(DeckL("辅助功能权限:"), MediaKeyController.isTrusted ? DeckL("有") : DeckL("没有"))
        print(DeckL("功能键设置（fnState）:"), UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.keyboard.fnState"] ?? DeckL("未设置"))
        let mask = CGEventMask(1 << 14)
        let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in
                if let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
                    let data = nsEvent.data1
                    print("媒体键 code=\((data & 0xFFFF_0000) >> 16) state=\(String((data & 0xFF00) >> 8, radix: 16))")
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        guard let port else {
            print(DeckL("监听失败：macOS 不允许这个进程接收按键"))
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        print(DeckL("监听 20 秒，请按 F1、F2、F11、F12"))
        RunLoop.main.run(until: Date().addingTimeInterval(20))
        print(DeckL("结束"))
    }
}
