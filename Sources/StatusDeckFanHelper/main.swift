import Darwin
import Foundation

struct Fan: Codable {
    let id: Int
    let name: String
    let currentSpeed: Int?
    let minSpeed: Int
    let maxSpeed: Int
    let targetSpeed: Int
    let mode: Int
}

struct Status: Codable { let fans: [Fan] }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func safeInteger(_ number: Double?) -> Int? {
    guard let number, number.isFinite, number >= 0, number <= 65_535 else { return nil }
    return Int(number.rounded())
}

func isAuthorizedInstall() -> Bool {
    var path = [CChar](repeating: 0, count: 4096)
    guard geteuid() == 0, proc_pidpath(getpid(), &path, UInt32(path.count)) > 0 else { return false }
    return String(cString: path) == "/Library/PrivilegedHelperTools/local.statusdeck.controls.v2.\(getuid())"
}

let args = Array(CommandLine.arguments.dropFirst())
if args == ["--version"] { print("MyStatus system control helper 2"); exit(0) }

let isRead = args == ["get"]
if !isRead, !isAuthorizedInstall() { fail("System writes require the authorized MyStatus helper.") }
if args.count == 2, args[0] == "power", ["0", "1"].contains(args[1]) {
    // pmset receives a fixed executable and a validated single-bit value.
    guard setuid(0) == 0 else { fail("Could not authorize pmset.") }
    let command = Process()
    command.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    command.arguments = ["-a", "lowpowermode", args[1]]
    command.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C"]
    do { try command.run() } catch { fail("Could not start pmset.") }
    command.waitUntilExit()
    guard command.terminationStatus == 0 else { fail("pmset rejected the power mode.") }
    print("SUCCESS: Low Power Mode")
    exit(0)
}
guard isRead || (args.count == 3 || args.count == 4) && args.first == "set" else { fail("Unsupported command.") }

let smc = SMC.shared
guard let count = safeInteger(smc.getValue("FNum")), (0...8).contains(count) else {
    fail("The SMC did not report a supported fan count.")
}

func fanMode(_ id: Int) -> Int {
    if let mode = safeInteger(smc.getValue(smc.fanModeKey(id))) { return mode }
    #if arch(x86_64)
    if let mask = safeInteger(smc.getValue("FS! ")) { return (mask >> id) & 1 }
    #endif
    return -1
}

if isRead {
    let fans = (0..<count).map { id in
        Fan(id: id, name: "Fan \(id + 1)", currentSpeed: safeInteger(smc.getValue("F\(id)Ac")),
                   minSpeed: safeInteger(smc.getValue("F\(id)Mn")) ?? 0,
                   maxSpeed: safeInteger(smc.getValue("F\(id)Mx")) ?? 0,
                   targetSpeed: safeInteger(smc.getValue("F\(id)Tg")) ?? 0, mode: fanMode(id))
    }
    guard let output = try? JSONEncoder().encode(Status(fans: fans)) else { fail("Unable to encode fan readings.") }
    FileHandle.standardOutput.write(output)
    exit(0)
}

guard let id = Int(args[1]), (0..<count).contains(id) else { fail("Unknown fan.") }
func returnToAuto() -> Bool {
    // Always release diagnostic mode when the last manual fan has been released.
    let auto = fanMode(id) == 1 ? smc.setFanMode(id, mode: .automatic) : fanMode(id) >= 0
    let idle = smc.releaseFanTestModeIfIdle(fanCount: count)
    let mode = fanMode(id)
    return (auto || mode == 0 || mode == 3) && mode != 1 && mode >= 0 && idle
}

if args.count == 3, args[2] == "0" {
    guard returnToAuto() else { fail("Could not return the fan to system control.") }
} else if args.count == 4, args[2] == "1", let speed = Int(args[3]) {
    guard let minimum = safeInteger(smc.getValue("F\(id)Mn")),
          let maximum = safeInteger(smc.getValue("F\(id)Mx")),
          minimum > 0, maximum > minimum, maximum <= 20_000, (minimum...maximum).contains(speed),
          ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
        fail("The requested speed is outside the fan limits or the system is under thermal pressure.")
    }
    guard smc.setFanMode(id, mode: .forced), smc.setFanSpeed(id, speed: speed) else {
        _ = returnToAuto()
        fail("The SMC rejected the target.")
    }
} else {
    fail("Invalid control mode.")
}
print("SUCCESS: Fan \(id)")
