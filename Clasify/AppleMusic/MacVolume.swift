import AudioToolbox
import CoreAudio
import Foundation

/// CLA-168: the Mac's own output volume, for Apple Music. MusicKit's `ApplicationMusicPlayer`
/// has no volume on the Mac, so the wheel changes the volume of the default output device,
/// with Core Audio (the same volume as the menu bar and the volume keys). Apple frameworks only.
///
/// While it listens, it reports the volume on each change: the volume keys, the menu bar, or a
/// new default output device. A device with no volume (some HDMI or USB outputs) reports
/// nothing and takes no writes.
@MainActor final class MacVolume {
    /// Gets the volume in percent, on the main queue.
    var onChange: (Int) -> Void = { _ in }

    private static let none = AudioObjectID(kAudioObjectUnknown)
    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private var device = none
    private var listening = false

    private static var defaultOutput: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// The volume that the menu bar's slider shows, 0 to 1, for all channels of the device.
    private static var volume: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    // Core Audio calls these on the main queue (the queue given when they are added).
    private lazy var deviceChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.follow() }
    }
    private lazy var volumeChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.report() }
    }

    /// Starts to listen, and reports the volume now.
    func start() {
        guard !listening else { return }
        listening = true
        var address = Self.defaultOutput
        AudioObjectAddPropertyListenerBlock(Self.system, &address, .main, deviceChanged)
        follow()
    }

    /// Stops listening. Nothing is reported after this.
    func stop() {
        guard listening else { return }
        listening = false
        var address = Self.defaultOutput
        AudioObjectRemovePropertyListenerBlock(Self.system, &address, .main, deviceChanged)
        listen(to: Self.none)
    }

    /// The volume in percent, or nil: no output device, or one with no volume.
    func read() -> Int? {
        guard device != Self.none else { return nil }
        var address = Self.volume
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Int((min(max(value, 0), 1) * 100).rounded())
    }

    /// Sets the volume in percent. A device with no volume, or one that does not take it, is left as it is.
    func write(_ percent: Int) {
        guard device != Self.none else { return }
        var address = Self.volume
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return }
        var value = Float32(min(max(percent, 0), 100)) / 100
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    /// The default output device now: the volume of the new one, if it changed.
    private func follow() {
        guard listening else { return }
        var id = Self.none
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.defaultOutput
        if AudioObjectGetPropertyData(Self.system, &address, 0, nil, &size, &id) != noErr { id = Self.none }
        listen(to: id)
        report()
    }

    private func listen(to new: AudioObjectID) {
        guard new != device else { return }
        var address = Self.volume
        if device != Self.none { AudioObjectRemovePropertyListenerBlock(device, &address, .main, volumeChanged) }
        device = new
        if device != Self.none && AudioObjectHasProperty(device, &address) {
            AudioObjectAddPropertyListenerBlock(device, &address, .main, volumeChanged)
        }
    }

    private func report() {
        guard listening, let percent = read() else { return }
        onChange(percent)
    }
}
