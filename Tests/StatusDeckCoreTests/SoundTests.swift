import Combine
import CoreAudio
import Foundation
import Testing
@testable import StatusDeckCore

/// Runs `render` over ordinary arrays, one array per buffer.
private func render(
    input: [(channels: Int, samples: [Float32])],
    outputChannels: [Int],
    frames: Int,
    from start: Float = 1,
    to end: Float = 1
) -> [[Float32]] {
    var inputStorage = input.map(\.samples)
    var outputStorage = outputChannels.map { [Float32](repeating: -9, count: $0 * frames) }

    let inputList = AudioBufferList.allocate(maximumBuffers: max(1, input.count))
    let outputList = AudioBufferList.allocate(maximumBuffers: outputChannels.count)
    defer {
        free(inputList.unsafeMutablePointer)
        free(outputList.unsafeMutablePointer)
    }
    inputList.count = input.count
    for index in input.indices {
        inputStorage[index].withUnsafeMutableBytes { bytes in
            inputList[index] = AudioBuffer(mNumberChannels: UInt32(input[index].channels), mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress)
        }
    }
    for index in outputChannels.indices {
        outputStorage[index].withUnsafeMutableBytes { bytes in
            outputList[index] = AudioBuffer(mNumberChannels: UInt32(outputChannels[index]), mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress)
        }
    }
    SoftwareVolumeMixer.render(input: inputList.unsafePointer, output: outputList.unsafeMutablePointer, from: start, to: end)
    return outputList.indices.map { index in
        let buffer = outputList[index]
        return Array(UnsafeBufferPointer(start: buffer.mData!.assumingMemoryBound(to: Float32.self), count: Int(buffer.mDataByteSize) / 4))
    }
}

@Suite struct SoftwareVolumeMixerTests {
    @Test func gainCurveIsAudioTaperedAndClamped() {
        #expect(SoftwareVolumeMixer.gain(forSliderValue: 0) == 0)
        #expect(SoftwareVolumeMixer.gain(forSliderValue: 1) == 1)
        #expect(SoftwareVolumeMixer.gain(forSliderValue: 0.5) == 0.25)
        #expect(SoftwareVolumeMixer.gain(forSliderValue: 2) == 1)
        #expect(SoftwareVolumeMixer.gain(forSliderValue: -1) == 0)
    }

    @Test func fullGainPassesInterleavedStereoThrough() {
        let output = render(input: [(2, [0.1, 0.2, 0.3, 0.4])], outputChannels: [2], frames: 2)
        #expect(output == [[0.1, 0.2, 0.3, 0.4]])
    }

    @Test func gainScalesEverySample() {
        let output = render(input: [(2, [1, 1, 1, 1])], outputChannels: [2], frames: 2, from: 0.5, to: 0.5)
        #expect(output == [[0.5, 0.5, 0.5, 0.5]])
    }

    @Test func zeroGainIsSilence() {
        let output = render(input: [(2, [1, 1])], outputChannels: [2], frames: 1, from: 0, to: 0)
        #expect(output == [[0, 0]])
    }

    @Test func gainChangesRampAcrossTheBufferSoNothingClicks() {
        let output = render(input: [(1, [1, 1, 1, 1])], outputChannels: [1], frames: 4, from: 0, to: 1)
        #expect(output[0] == [0, 0.25, 0.5, 0.75])
    }

    @Test func handlesSeparateBuffersPerChannel() {
        let output = render(input: [(1, [0.1, 0.3]), (1, [0.2, 0.4])], outputChannels: [1, 1], frames: 2)
        #expect(output == [[0.1, 0.3], [0.2, 0.4]])
    }

    @Test func interleavedInputCanFeedSeparateOutputs() {
        let output = render(input: [(2, [0.1, 0.2, 0.3, 0.4])], outputChannels: [1, 1], frames: 2)
        #expect(output == [[0.1, 0.3], [0.2, 0.4]])
    }

    @Test func aDeviceInputBeforeTheTapIsNotPlayedBack() {
        // The microphone of an output device with inputs comes first in the aggregate.
        let output = render(input: [(1, [9, 9]), (2, [0.1, 0.2, 0.3, 0.4])], outputChannels: [2], frames: 2)
        #expect(output == [[0.1, 0.2, 0.3, 0.4]])
    }

    @Test func extraOutputChannelsRepeatTheStereoPair() {
        let output = render(input: [(2, [0.1, 0.2])], outputChannels: [4], frames: 1)
        #expect(output == [[0.1, 0.2, 0.1, 0.2]])
    }

    @Test func noInputGivesSilenceNotStaleMemory() {
        let output = render(input: [], outputChannels: [2], frames: 2)
        #expect(output == [[0, 0, 0, 0]])
    }
}

@MainActor
@Suite struct SoftwareVolumeControllerTests {
    /// Every change in the app asks to sync. If a refused start retried each time, its
    /// own state change would trigger the next attempt, forever.
    @Test func aRefusedStartIsNotRetriedByLaterSyncs() {
        let controller = SoftwareVolumeController(permission: { .denied })
        var changes = 0
        let watcher = controller.objectWillChange.sink { changes += 1 }
        controller.run(onOutput: "display")
        #expect(controller.state == .permissionDenied)
        let settled = changes
        for _ in 0..<5 { controller.run(onOutput: "display") }
        #expect(changes == settled)
        withExtendedLifetime(watcher) {}
    }

    @Test func stoppingClearsTheState() {
        let controller = SoftwareVolumeController(permission: { .denied })
        controller.run(onOutput: "display")
        controller.stop()
        #expect(controller.state == .off)
    }

    @Test func aDifferentOutputIsATryAgain() {
        var answer = AudioCapturePermission.Status.denied
        let controller = SoftwareVolumeController(permission: { answer })
        controller.run(onOutput: "a")
        #expect(controller.state == .permissionDenied)
        answer = .authorized
        controller.run(onOutput: "a")
        #expect(controller.state == .permissionDenied, "the same output is not reconsidered")
    }

    @Test func aGrantInSystemSettingsIsNoticed() {
        var answer = AudioCapturePermission.Status.denied
        let controller = SoftwareVolumeController(permission: { answer })
        controller.run(onOutput: "not-a-real-device")
        #expect(controller.state == .permissionDenied)
        answer = .authorized
        controller.pollSignal()
        #expect(controller.state == .starting)
        controller.stop()
    }

    @Test func restartOnlyAppliesToARunningEngine() {
        let controller = SoftwareVolumeController(permission: { .denied })
        controller.run(onOutput: "display")
        controller.restartIfRunning()
        #expect(controller.state == .permissionDenied)
    }
}

@Suite struct SoftwareVolumeDeviceTests {
    /// Our private aggregate appears in this process's device list.
    @Test func ourAggregateIsNotOfferedAsADevice() {
        #expect(SoftwareVolumeDevice.isOurs(uid: SoftwareVolumeDevice.uidPrefix + "1234"))
        #expect(!SoftwareVolumeDevice.isOurs(uid: "10AC7942-0000-0000-1B20-0104B53C2278"))
        #expect(!SoftwareVolumeDevice.isOurs(uid: nil))
    }
}

@Suite struct DDCWriteCheckTests {
    /// What the Dell U2723QX really did: accepted the write and stayed at 50.
    @Test func aMonitorThatIgnoresTheWriteIsCaught() {
        #expect(DDCWriteCheck.tookEffect(before: 50, written: 35, readBack: 50) == false)
    }

    @Test func aMonitorThatObeysPasses() {
        #expect(DDCWriteCheck.tookEffect(before: 50, written: 35, readBack: 35) == true)
    }

    @Test func coarseStepsStillCountAsObeying() {
        #expect(DDCWriteCheck.tookEffect(before: 50, written: 35, readBack: 36) == true)
    }

    @Test func noAnswerProvesNothing() {
        #expect(DDCWriteCheck.tookEffect(before: 50, written: 35, readBack: nil) == nil)
    }

    @Test func aTinyMoveProvesNothing() {
        #expect(DDCWriteCheck.tookEffect(before: 50, written: 49, readBack: 50) == nil)
    }
}

@Suite struct VolumeRouterTests {
    private func display(volume: Double? = 0.5, ignores: Bool = false) -> DisplayState {
        DisplayState(id: 3, name: "DELL", isBuiltIn: false, kind: .ddc, brightness: 0.5, volume: volume, ignoresVolumeWrites: ignores)
    }

    private func route(
        hardware: Bool = false,
        ddc: DisplayState? = nil,
        softwareEnabled: Bool = false,
        supported: Bool = true,
        preference: VolumeRoutePreference = .automatic
    ) -> VolumeRoute {
        VolumeRouter.route(hasHardwareVolume: hardware, ddcDisplay: ddc, softwareEnabled: softwareEnabled, softwareSupported: supported, preference: preference)
    }

    @Test func hardwareVolumeAlwaysWins() {
        #expect(route(hardware: true, ddc: display(), softwareEnabled: true) == .hardware)
    }

    @Test func workingDDCIsUsedAutomatically() {
        #expect(route(ddc: display()) == .ddc(3))
    }

    /// The reported bug: a slider that moved and changed nothing.
    @Test func aMonitorIgnoringDDCOffersSoftwareVolumeInstead() {
        #expect(route(ddc: display(volume: nil, ignores: true)) == .softwareAvailable)
        #expect(route(ddc: display(ignores: true)) == .softwareAvailable)
    }

    @Test func softwareVolumeOnceEnabledStaysInCharge() {
        #expect(route(ddc: display(ignores: true), softwareEnabled: true) == .software)
        #expect(route(ddc: display(), softwareEnabled: true) == .software)
    }

    @Test func nonDisplayDevicesWithoutVolumeCanUseSoftware() {
        #expect(route() == .softwareAvailable)
    }

    @Test func olderSystemsHaveNoRouteLeft() {
        #expect(route(supported: false) == .unavailable)
    }

    @Test func preferenceCanForceEitherWay() {
        #expect(route(ddc: display(), softwareEnabled: true, preference: .ddc) == .ddc(3))
        #expect(route(ddc: display(), preference: .software) == .softwareAvailable)
        #expect(route(ddc: display(ignores: true), preference: .ddc) == .softwareAvailable)
    }
}
