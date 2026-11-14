import AudioToolbox
import CoreAudio
import Foundation

/// Volume and mute of the default output device.
///
/// CoreAudio calls run on a private queue; volume writes are coalesced to at most
/// ~60 per second so slow devices (USB, interfaces) never queue up a backlog.
public final class VolumeController: @unchecked Sendable {
    public struct State: Sendable, Equatable {
        public var volume: Double
        public var muted: Bool
        /// False for devices without a software volume (HDMI, some interfaces): use media keys instead.
        public var canSetVolume: Bool
        public var canMute: Bool
    }

    private let queue = DispatchQueue(label: "SlideEdge.Volume", qos: .userInitiated)
    private var writer: CoalescedWriter!

    // Confined to `queue`.
    private var device = AudioObjectID(kAudioObjectUnknown)

    public init() {
        writer = CoalescedWriter(queue: queue) { [unowned self] volume in
            write(Float32(volume), to: Self.volumeAddress)
        }
        queue.sync { device = Self.defaultOutputDevice() }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue) { [weak self] _, _ in
            guard let self else { return }
            device = Self.defaultOutputDevice()
            writer.discardPending()
        }
    }

    public func state() -> State {
        queue.sync {
            State(
                volume: readVolume() ?? 0,
                muted: readMute() ?? false,
                canSetVolume: isSettable(Self.volumeAddress),
                canMute: isSettable(Self.muteAddress)
            )
        }
    }

    /// Sets the volume (0...1). Only the latest value within a write interval reaches the device.
    public func setVolume(_ volume: Double) {
        writer.submit(min(max(volume, 0), 1))
    }

    public func setMuted(_ muted: Bool) {
        queue.async { [self] in
            write(UInt32(muted ? 1 : 0), to: Self.muteAddress)
        }
    }

    // MARK: - CoreAudio (queue)

    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static func defaultOutputDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : AudioObjectID(kAudioObjectUnknown)
    }

    private func isSettable(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private func readVolume() -> Double? {
        read(Float32.self, from: Self.volumeAddress).map(Double.init)
    }

    private func readMute() -> Bool? {
        read(UInt32.self, from: Self.muteAddress).map { $0 != 0 }
    }

    private func read<T: BitwiseCopyable>(_: T.Type, from address: AudioObjectPropertyAddress) -> T? {
        var address = address
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private func write<T: BitwiseCopyable>(_ value: T, to address: AudioObjectPropertyAddress) {
        var address = address
        var value = value
        guard device != kAudioObjectUnknown else { return }
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }
}
