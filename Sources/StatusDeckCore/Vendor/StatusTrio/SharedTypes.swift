// From Status Trio (https://github.com/lingyired/status-trio), Copyright 2026 lingyired.
// Licensed under the Apache License 2.0; see LICENSES/StatusTrio-Apache-2.0.txt.
// The small shared types the reused Status Trio files depend on, extracted unchanged.

import CoreAudio
import Foundation

enum AudioOutputTransport: Hashable, Sendable {
    case builtIn
    case bluetooth
    case bluetoothLowEnergy
    case usb
    case hdmi
    case displayPort
    case thunderbolt
    case airPlay
    case aggregate
    case virtual
    case other

    init(coreAudioValue: UInt32) {
        self = Self.transportsByCoreAudioValue
            .first { $0.value == coreAudioValue }?
            .transport ?? .other
    }

    /// Whether the transport is one of CoreAudio's two Bluetooth families.
    var isBluetooth: Bool {
        self == .bluetooth || self == .bluetoothLowEnergy
    }

    private static let transportsByCoreAudioValue: [(value: UInt32, transport: Self)] = [
        (kAudioDeviceTransportTypeBuiltIn, .builtIn),
        (kAudioDeviceTransportTypeBluetooth, .bluetooth),
        (kAudioDeviceTransportTypeBluetoothLE, .bluetoothLowEnergy),
        (kAudioDeviceTransportTypeUSB, .usb),
        (kAudioDeviceTransportTypeHDMI, .hdmi),
        (kAudioDeviceTransportTypeDisplayPort, .displayPort),
        (kAudioDeviceTransportTypeThunderbolt, .thunderbolt),
        (kAudioDeviceTransportTypeAirPlay, .airPlay),
        (kAudioDeviceTransportTypeAggregate, .aggregate),
        (kAudioDeviceTransportTypeAutoAggregate, .aggregate),
        (kAudioDeviceTransportTypeVirtual, .virtual)
    ]
}

enum AudioOutputDataSource: Hashable, Sendable {
    case internalSpeaker
    case headphones
    case externalSpeaker
    case other

    init(coreAudioValue: UInt32) {
        self = Self.dataSourcesByCoreAudioValue
            .first { $0.value == coreAudioValue }?
            .dataSource ?? .other
    }

    private static func fourCharacterCode(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static let dataSourcesByCoreAudioValue: [(value: UInt32, dataSource: Self)] = [
        (fourCharacterCode("ispk"), .internalSpeaker),
        (fourCharacterCode("hdpn"), .headphones),
        (fourCharacterCode("espk"), .externalSpeaker),
        (fourCharacterCode("spkr"), .externalSpeaker)
    ]
}

enum WiFiNameAccess: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum BluetoothRadioPower: Equatable, Sendable {
    case on
    case off
    case unavailable
    case unknown

    var isOn: Bool { self == .on }
}

@MainActor
protocol BluetoothRadioPowerBacking: AnyObject {
    var isAvailable: Bool { get }
    func readPower() -> BluetoothRadioPower
    func setPower(_ enabled: Bool) async -> Bool
}
