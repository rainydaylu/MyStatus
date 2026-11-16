import Darwin
import IOKit
import IOKit.pwr_mgt

/// Kernel IOPMLib interface, also documented in LogoLight's MIT research notes.
enum LogoLidPower {
    static func setSleepDisabled(_ disabled: Bool) -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        var client: io_connect_t = 0
        guard IOServiceOpen(root, mach_task_self_, 0, &client) == KERN_SUCCESS else { return false }
        defer { IOServiceClose(client) }
        var setting: UInt64 = disabled ? 1 : 0
        return IOConnectCallScalarMethod(client, UInt32(kPMSetClamshellSleepState), &setting, 1, nil, nil) == KERN_SUCCESS
    }
}
