import Foundation
import Testing
import StatusDeckKit
@testable import StatusDeckCore

@Suite struct FormatTests {
    @Test func speedPicksUnitAndKeepsSmallValuesInKilobytes() {
        #expect(Format.speed(0) == "0 KB/s")
        #expect(Format.speed(45_000) == "45 KB/s")
        #expect(Format.speed(1_200_000) == "1.2 MB/s")
        #expect(Format.speed(25_000_000) == "25 MB/s")
    }

    @Test func memoryReadsInBinaryAndStorageInDecimal() {
        #expect(Format.bytes(17_179_869_184, binary: true) == "16.0 GB")
        #expect(Format.bytes(22_500_000_000) == "22.5 GB")
        #expect(Format.bytes(995_000_000_000) == "995 GB")
    }

    @Test func durationDropsMinutesOnceItReachesDays() {
        #expect(Format.duration(5 * 60) == "5分钟")
        #expect(Format.duration(2 * 3600 + 11 * 60) == "2小时11分钟")
        #expect(Format.duration(3 * 86400 + 4 * 3600 + 30 * 60) == "3天 4小时")
    }

    @Test func missingReadingsShowADashNotZero() {
        #expect(Format.gigahertz(nil) == "--")
        #expect(Format.degrees(nil) == "--")
        #expect(Format.watts(nil) == "--")
    }
}

@Suite struct FrequencyTests {
    /// The start of `voltage-states9` as read from an M1 Pro.
    @Test func decodesHertzTables() {
        let data = Data([0x00, 0x00, 0x00, 0x00, 0x90, 0x01, 0x00, 0x00,
                         0x00, 0x9e, 0x2c, 0x17, 0x64, 0x02, 0x00, 0x00,
                         0x00, 0x64, 0x3f, 0x4d, 0x6b, 0x03, 0x00, 0x00])
        let table = DVFSTables.megahertz(fromVoltageStates: data)
        #expect(table.count == 3)
        #expect(table[0] == 0)
        #expect(abs(table[1] - 388.8) < 0.01)
        #expect(abs(table[2] - 1296) < 0.01)
    }

    @Test func decodesKilohertzTables() {
        // 912,000 kHz, the storage newer chips use.
        let data = Data([0x80, 0xea, 0x0d, 0x00, 0x00, 0x00, 0x00, 0x00])
        #expect(DVFSTables.megahertz(fromVoltageStates: data) == [912])
    }

    @Test func ignoresIdleAndWeighsByResidency() {
        var accumulator = FrequencyAccumulator()
        accumulator.add(residencies: [1000, 1, 3], table: [600, 2000], tableIncludesIdle: false)
        #expect(accumulator.averageMHz == 1650)
    }

    @Test func tableWithLeadingOffStateShiftsByOne() {
        var accumulator = FrequencyAccumulator()
        accumulator.add(residencies: [5, 1], table: [0, 388], tableIncludesIdle: true)
        #expect(accumulator.averageMHz == 388)
    }

    /// M1 Pro's GPU publishes 15 active states over 6 frequencies.
    @Test func statesPastTheTableClampToItsLastEntry() {
        var accumulator = FrequencyAccumulator()
        accumulator.add(residencies: [0, 0, 0, 2], table: [0, 388, 486], tableIncludesIdle: true)
        #expect(accumulator.averageMHz == 486)
    }

    @Test func allIdleHasNoFrequency() {
        var accumulator = FrequencyAccumulator()
        accumulator.add(residencies: [100, 0, 0], table: [600, 2000], tableIncludesIdle: false)
        #expect(accumulator.averageMHz == nil)
    }
}

@Suite struct SensorTests {
    @Test func groupsAppleSiliconSensorNames() {
        #expect(TemperatureReader.group(forSensor: "PMU tdie6") == .cpu)
        #expect(TemperatureReader.group(forSensor: "pACC MTR Temp Sensor2") == .cpu)
        #expect(TemperatureReader.group(forSensor: "GPU MTR Temp Sensor1") == .gpu)
        #expect(TemperatureReader.group(forSensor: "PMU TP2g") == .gpu)
        #expect(TemperatureReader.group(forSensor: "PMU TP1s") == .soc)
        #expect(TemperatureReader.group(forSensor: "NAND CH0 temp") == .storage)
        #expect(TemperatureReader.group(forSensor: "gas gauge battery") == .battery)
        #expect(TemperatureReader.group(forSensor: "PMU tdev3") == .board)
    }

    @Test func calibrationValueIsNotATemperature() {
        #expect(TemperatureReader.group(forSensor: "PMU tcal") == nil)
        #expect(TemperatureReader.readings(from: ["PMU tcal": [51.9]]).isEmpty)
    }

    @Test func repeatedSensorNamesAverageIntoOneReading() {
        let readings = TemperatureReader.readings(from: ["PMU tdie1": [40, 42]])
        #expect(readings.count == 1)
        #expect(readings[0].celsius == 41)
    }

    @Test func decodesSMCValues() {
        // flt, little-endian
        #expect(SMCClient.decode(type: 0x666c7420, payload: [0x00, 0x00, 0xbb, 0x44]) == 1496)
        // fpe2, big-endian with two fractional bits
        #expect(SMCClient.decode(type: 0x66706532, payload: [0x17, 0x70]) == 1500)
        #expect(SMCClient.decode(type: 0x75693820, payload: [2]) == 2)
        // An unknown type is no reading rather than a wrong one.
        #expect(SMCClient.decode(type: 0x12345678, payload: [1, 2]) == nil)
    }

    @Test func fanWithoutMaximumStillReportsWhetherItSpins() {
        #expect(FanReading(id: 0, rpm: 0, minimumRPM: nil, maximumRPM: nil).fraction == 0)
        #expect(FanReading(id: 0, rpm: 2148, minimumRPM: 1499, maximumRPM: 4296).fraction == 0.5)
    }
}

@Suite struct ProcessTests {
    @Test func parsesPSOutputWithSpacesInNames() {
        let rows = ProcessReader.parse("  123   4.5  2048 Google Chrome\n   7   0.0    16 launchd\nbroken line\n")
        #expect(rows == [
            .init(pid: 123, cpuPercent: 4.5, residentBytes: 2_097_152, name: "Google Chrome"),
            .init(pid: 7, cpuPercent: 0, residentBytes: 16_384, name: "launchd")
        ])
    }

    @Test func helpersBelongToTheirOutermostApp() {
        #expect(ProcessReader.outermostBundle(of: "/Applications/Foo.app/Contents/Frameworks/Bar Helper.app/Contents/MacOS/Bar") == "/Applications/Foo.app")
        #expect(ProcessReader.outermostBundle(of: "/usr/libexec/opendirectoryd") == nil)
    }
}

@Suite struct BatteryTests {
    @Test func readsTheRegistryAndIgnoresTheCalculatingMarker() {
        let stats = BatteryReader.parse(registry: [
            "CurrentCapacity": 100, "FullyCharged": true, "ExternalConnected": true,
            "CycleCount": 523, "NominalChargeCapacity": 7171, "DesignCapacity": 8694,
            "Temperature": 3023, "Voltage": 12566, "InstantAmperage": -1500, "TimeRemaining": 65535
        ], into: BatteryStats(), adapter: ["Watts": 90])
        #expect(stats.statusText == "已充电")
        #expect(stats.minutesRemaining == nil)
        #expect(stats.cycleCount == 523)
        #expect(abs((stats.health ?? 0) - 0.8248) < 0.001)
        #expect(stats.temperatureCelsius == 30.23)
        #expect(stats.adapterWatts == 90)
        #expect(abs((stats.watts ?? 0) + 18.849) < 0.001)
    }

    @Test func noBatteryIsNotAnEmptyBattery() {
        #expect(BatteryStats().statusText == "无电池")
    }
}

@Suite struct BluetoothTests {
    private let report = """
    {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
      "device_connected":[{"我的Magic Keyboard":{"device_address":"AC:49:DB:F3:FB:79","device_minorType":"Keyboard"}}],
      "device_not_connected":[{"Buds":{"device_address":"34:0E:22:4F:4A:F7","device_batteryLevelLeft":"94%","device_batteryLevelRight":"80%","device_minorType":"Headphones"}}]
    }]}
    """

    @Test func parsesConnectionStateAndBattery() throws {
        let parsed = try #require(BluetoothReport.parse(Data(report.utf8)))
        #expect(parsed.isControllerOn == true)
        let keyboard = try #require(parsed.devices.first { $0.isConnected })
        #expect(keyboard.isInputDevice)
        let buds = try #require(parsed.devices.first { !$0.isConnected })
        #expect(!buds.isInputDevice)
        #expect(buds.summaryBattery == 80, "the bud that dies first speaks for the pair")
    }

    @Test func addressFormsCompareEqual() {
        #expect(BluetoothReport.normalizedAddress("AC:49:DB:F3:FB:79") == BluetoothReport.normalizedAddress("ac-49-db-f3-fb-79"))
    }

    @Test func malformedReportIsNoReport() {
        #expect(BluetoothReport.parse(Data("not json".utf8)) == nil)
    }
}

@Suite struct MiscellaneousTests {
    @Test func virtualInterfacesDoNotCountTowardsTraffic() {
        #expect(NetworkReader.isUserFacing("en0"))
        #expect(!NetworkReader.isUserFacing("utun3"))
        #expect(!NetworkReader.isUserFacing("awdl0"))
        #expect(!NetworkReader.isUserFacing("lo0"))
    }

    @Test func historyStaysBounded() {
        var history = History()
        for _ in 0..<(History.capacity + 10) {
            history.append(SystemSnapshot(), includesPanelOnlySeries: true)
        }
        #expect(history.cpuUser.count == History.capacity)
        #expect(history.gpu.count == History.capacity)
    }

    @Test func panelOnlySeriesWaitForThePanel() {
        var history = History()
        history.append(SystemSnapshot(), includesPanelOnlySeries: false)
        #expect(history.cpuUser.count == 1)
        #expect(history.gpu.isEmpty)
    }

    @Test func speakersMatchAudioDevicesIgnoringPunctuation() {
        #expect(DisplayController.normalized("DELL U2723QX") == DisplayController.normalized("dell-u2723qx"))
    }

    @Test func helperInputSourcesAreHidden() {
        #expect(InputSourceController.isUserFacing("com.apple.keylayout.ABC"))
        #expect(!InputSourceController.isUserFacing("com.apple.PressAndHold"))
    }
}
