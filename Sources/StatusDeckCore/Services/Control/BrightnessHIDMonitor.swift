import Foundation
import Darwin
import IOKit.hid
import IOKit.hidsystem

/// Listens to display brightness and the two physical function keys before the
/// keyboard driver translates them into events for the window server.
@MainActor
final class BrightnessHIDMonitor {
    enum State: Equatable {
        case inactive, permissionNeeded, unavailable(IOReturn?), listening
    }

    private var manager: IOHIDManager?
    private var openedDevices: Set<IOHIDDevice> = []
    private var devicesHoldingFn: Set<IOHIDDevice> = []
    var isFnDown: Bool { !devicesHoldingFn.isEmpty }
    var onPress: ((MediaKeyController.Key, UInt32, UInt64) -> Void)?

    nonisolated private static let nanosecondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    nonisolated private static let usages: [(page: UInt32, usage: UInt32, key: MediaKeyController.Key)] = [
        (0x0C, 0x6F, .brightnessUp), (0x0C, 0x70, .brightnessDown),
        (0xFF01, 0x20, .brightnessUp), (0xFF01, 0x21, .brightnessDown),
        (0x00FF, 0x04, .brightnessUp), (0x00FF, 0x05, .brightnessDown)
    ]
    nonisolated private static let functionKeys: [(page: UInt32, usage: UInt32, key: MediaKeyController.Key)] = [
        (0x07, 0x3A, .brightnessDown), (0x07, 0x3B, .brightnessUp)
    ]
    // Fn may be reported by either Apple vendor collection.
    nonisolated private static let fnPages: [UInt32] = [0x00FF, 0xFF01]
    nonisolated private static let fnUsage: UInt32 = 0x03

    nonisolated static func key(page: UInt32, usage: UInt32, allowFunctionKeys: Bool = false) -> MediaKeyController.Key? {
        let candidates = page == 0x07 && allowFunctionKeys ? functionKeys : usages
        return candidates.first { $0.page == page && $0.usage == usage }?.key
    }

    static func requestAccess() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func sync(enabled: Bool, allowFunctionKeys: Bool) -> State {
        guard enabled else { stop(); return .inactive }
        // Quartz event taps and IOKit can report different access. Check the
        // permission of the actual API and prompt only from the settings button.
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            stop()
            return .permissionNeeded
        }
        if manager == nil {
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let matches: [[String: Int]] = [
                [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6],
                [kIOHIDDeviceUsagePageKey: 0x0C, kIOHIDDeviceUsageKey: 1],
                [kIOHIDVendorIDKey: 0x004C, kIOHIDPrimaryUsagePageKey: 0xFF00],
                [kIOHIDVendorIDKey: 0x05AC, kIOHIDPrimaryUsagePageKey: 0xFF00]
            ]
            IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            self.manager = manager
        }
        guard let manager else { return .unavailable(nil) }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        for device in openedDevices.subtracting(devices) { close(device) }
        openedDevices.formIntersection(devices)
        devicesHoldingFn.formIntersection(devices)

        // One locked HID service can fail IOHIDManagerOpen for every keyboard.
        // Open each service independently and subscribe only to brightness and Fn.
        var openError: IOReturn?
        let usages = allowFunctionKeys ? Self.usages + Self.functionKeys : Self.usages
        let elements = usages.map { [kIOHIDElementUsagePageKey: $0.page, kIOHIDElementUsageKey: $0.usage] }
            + Self.fnPages.map { [kIOHIDElementUsagePageKey: $0, kIOHIDElementUsageKey: Self.fnUsage] }
        for device in devices.subtracting(openedDevices) {
            let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard result == kIOReturnSuccess else {
                if result == kIOReturnNotPermitted || result == kIOReturnNotPrivileged || openError == nil {
                    openError = result
                }
                continue
            }
            attach(to: device, elements: elements as CFArray)
            openedDevices.insert(device)
        }
        if !openedDevices.isEmpty { return .listening }
        if openError == kIOReturnNotPermitted || openError == kIOReturnNotPrivileged {
            return .permissionNeeded
        }
        return .unavailable(openError)
    }

    private func attach(to device: IOHIDDevice, elements: CFArray) {
        IOHIDDeviceSetInputValueMatchingMultiple(device, elements)
        IOHIDDeviceRegisterInputValueCallback(device, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let isDown = IOHIDValueGetIntegerValue(value) != 0
            let monitor = Unmanaged<BrightnessHIDMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if usage == BrightnessHIDMonitor.fnUsage, BrightnessHIDMonitor.fnPages.contains(page) {
                    let device = IOHIDElementGetDevice(element)
                    if isDown { monitor.devicesHoldingFn.insert(device) }
                    else { monitor.devicesHoldingFn.remove(device) }
                } else if isDown, let key = BrightnessHIDMonitor.key(page: page, usage: usage, allowFunctionKeys: true) {
                    let time = UInt64(Double(IOHIDValueGetTimeStamp(value)) * BrightnessHIDMonitor.nanosecondsPerTick)
                    monitor.onPress?(key, page, time)
                }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    private func close(_ device: IOHIDDevice) {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func stop() {
        guard let manager else { return }
        for device in openedDevices { close(device) }
        openedDevices.removeAll()
        devicesHoldingFn.removeAll()
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = nil
    }
}
