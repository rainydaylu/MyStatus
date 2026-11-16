import AppKit
import Carbon
import Foundation
import IOKit

/// Observes timing/contact state only. No characters, touch buffers or coordinates are read.
@MainActor final class LogoInputs {
    var contacts = 0
    var typingUntil = 0.0
    var clickUntil = 0.0
    private var global: Any?
    private var local: Any?
    private var touchActive = false
    var typingAllowed: Bool { CGPreflightListenEventAccess() }

    func configure(mode: LogoMode, authorize: Bool = false) -> Bool {
        stop()
        if mode == .typing {
            if authorize { _ = CGRequestListenEventAccess() }
            guard typingAllowed else { return false }
            let handler: (NSEvent) -> Void = { [weak self] _ in
                MainActor.assumeIsolated {
                    guard !IsSecureEventInputEnabled() else { return }
                    self?.typingUntil = ProcessInfo.processInfo.systemUptime + 0.22
                }
            }
            global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
            local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in handler(event); return event }
            return global != nil
        }
        if mode == .trackpad {
            touchActive = LogoTrackpad.shared.start { [weak self] count in self?.contacts = count }
            global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                MainActor.assumeIsolated { self?.clickUntil = ProcessInfo.processInfo.systemUptime + 0.09 }
            }
            local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                MainActor.assumeIsolated { self?.clickUntil = ProcessInfo.processInfo.systemUptime + 0.09 }; return event
            }
            return touchActive
        }
        return true
    }

    func stop() {
        if let global { NSEvent.removeMonitor(global) }; global = nil
        if let local { NSEvent.removeMonitor(local) }; local = nil
        if touchActive { LogoTrackpad.shared.stop() }; touchActive = false
        contacts = 0; typingUntil = 0; clickUntil = 0
    }
}

/// Interoperability signatures: calftrail/Touch MultitouchSupport.h. Contact data is opaque.
private final class LogoTrackpad: @unchecked Sendable {
    static let shared = LogoTrackpad()
    typealias Callback = @convention(c) (UnsafeRawPointer?, Int, Int, UnsafeRawPointer?) -> Void
    typealias Register = @convention(c) (UnsafeRawPointer, Callback) -> Void
    typealias Start = @convention(c) (UnsafeRawPointer, Int32) -> Int32
    typealias Stop = @convention(c) (UnsafeRawPointer) -> Int32
    typealias Devices = @convention(c) () -> Unmanaged<CFArray>?
    typealias Service = @convention(c) (UnsafeRawPointer) -> io_service_t
    private let lock = NSLock()
    private var ledger = LogoTouchLedger()
    private var listener: (@MainActor (Int) -> Void)?
    private var selected: [UnsafeRawPointer] = []
    private var retained: CFArray?
    private var unregister: Register?
    private var stopDevice: Stop?
    private var generation = 0

    private static let event: Callback = { device, path, state, _ in
        guard let device else { return }
        let selfRef = LogoTrackpad.shared
        selfRef.lock.lock()
        guard selfRef.selected.contains(device) else { selfRef.lock.unlock(); return }
        selfRef.ledger.accept(device: UInt(bitPattern: device), path: path, state: state)
        let count = selfRef.ledger.count, generation = selfRef.generation
        selfRef.lock.unlock()
        DispatchQueue.main.async {
            selfRef.lock.lock(); let sink = generation == selfRef.generation ? selfRef.listener : nil; selfRef.lock.unlock()
            MainActor.assumeIsolated { sink?(count) }
        }
    }

    @MainActor func start(_ listener: @escaping @MainActor (Int) -> Void) -> Bool {
        stop()
        guard let library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY | RTLD_LOCAL),
              let listSymbol = dlsym(library, "MTDeviceCreateList"), let serviceSymbol = dlsym(library, "MTDeviceGetService"),
              let registerSymbol = dlsym(library, "MTRegisterPathCallback"), let unregisterSymbol = dlsym(library, "MTUnregisterPathCallback"),
              let startSymbol = dlsym(library, "MTDeviceStart"), let stopSymbol = dlsym(library, "MTDeviceStop") else { return false }
        let list = unsafeBitCast(listSymbol, to: Devices.self), service = unsafeBitCast(serviceSymbol, to: Service.self)
        let register = unsafeBitCast(registerSymbol, to: Register.self), start = unsafeBitCast(startSymbol, to: Start.self)
        guard let devices = list()?.takeRetainedValue() else { return false }
        retained = devices; self.listener = listener
        unregister = unsafeBitCast(unregisterSymbol, to: Register.self); stopDevice = unsafeBitCast(stopSymbol, to: Stop.self)
        for i in 0..<CFArrayGetCount(devices) {
            guard let pointer = CFArrayGetValueAtIndex(devices, i) else { continue }
            let node = service(pointer)
            guard node != 0, let usage = IORegistryEntryCreateCFProperty(node, "DeviceUsagePairs" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: NSNumber]],
                  usage.contains(where: { $0["DeviceUsagePage"]?.intValue == 13 && $0["DeviceUsage"]?.intValue == 5 }) else { continue }
            lock.lock(); selected.append(pointer); lock.unlock()
            register(pointer, Self.event)
            if start(pointer, 0) != 0 {
                unregister?(pointer, Self.event)
                lock.lock(); selected.removeAll { $0 == pointer }; lock.unlock()
            }
        }
        return !selected.isEmpty
    }

    @MainActor func stop() {
        lock.lock(); generation += 1; let devices = selected; selected = []; listener = nil; ledger = LogoTouchLedger(); lock.unlock()
        for device in devices { _ = stopDevice?(device); unregister?(device, Self.event) }
        retained = nil
    }
}
