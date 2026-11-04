import Foundation
import LibrespotBridge
import os

/// One Spotify Connect device of the account, other than Clasify itself.
struct ConnectDevice: Sendable, Equatable {
    let id: String
    let name: String
    let type: String
    let software: String
    let isActive: Bool
}

/// The Spotify app's player, from the account's Connect cluster.
struct SpotifyPlayerState: Sendable, Equatable {
    let activeDeviceID: String
    let trackURI: String
    let contextURI: String
    let position: Double  // seconds, at the time of the callback
    let duration: Double
    /// A track is loaded and not paused.
    let isRunning: Bool
    /// A track is loaded. It can be paused.
    let hasTrack: Bool
}

/// Where the bridge sends each player state. The handler runs on a bridge thread.
final class StateBox: Sendable {
    private let handler = OSAllocatedUnfairLock<(@Sendable (SpotifyPlayerState) -> Void)?>(initialState: nil)

    func set(_ new: @escaping @Sendable (SpotifyPlayerState) -> Void) { handler.withLock { $0 = new } }

    func deliver(_ state: SpotifyPlayerState) { handler.withLock { $0 }?(state) }
}

extension LibrespotClient {
    /// Registers Clasify as a Connect device, then lists the account's other devices.
    func devices() async throws -> [ConnectDevice] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ConnectDevice], any Error>) in
            let box = Unmanaged.passRetained(ResultBox(continuation)).toOpaque()
            let status = lsb_connect_devices(handle, devicesCallback, box)
            if status != LSB_OK {
                Unmanaged<ResultBox<[ConnectDevice]>>.fromOpaque(box).takeRetainedValue()
                    .resume(.failure(BridgeError(status: status, message: "cannot list devices")))
            }
        }
    }

    /// Plays `context` on `device`, from `track`.
    func play(device: String, context: String, track: String) async throws {
        try await command("cannot play") { lsb_connect_play(handle, device, context, track, commandCallback, $0) }
    }

    /// `command` is one of `LSB_COMMAND_*`.
    func send(_ command: Int32, to device: String) async throws {
        try await self.command("command failed") { lsb_connect_command(handle, device, UInt32(command), commandCallback, $0) }
    }

    func seek(device: String, seconds: Double) async throws {
        let ms = UInt32(clamping: Int((max(seconds, 0) * 1000).rounded()))
        try await command("cannot seek") { lsb_connect_seek(handle, device, ms, commandCallback, $0) }
    }

    /// `percent` is 0 to 100.
    func volume(device: String, percent: Int) async throws {
        let value = UInt16(clamping: min(max(percent, 0), 100) * 65535 / 100)
        try await command("cannot set volume") { lsb_connect_volume(handle, device, value, commandCallback, $0) }
    }

    /// `option` is one of `LSB_OPTION_*`.
    func setOption(_ option: Int32, _ on: Bool, device: String) async throws {
        try await command("cannot set option") { lsb_connect_set_option(handle, device, UInt32(option), on, commandCallback, $0) }
    }

    /// Runs one bridge command call. `start` gets the callback context and returns the call status.
    private func command(_ failure: String, _ start: (UnsafeMutableRawPointer) -> Int32) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let box = Unmanaged.passRetained(ResultBox(continuation)).toOpaque()
            let status = start(box)
            if status != LSB_OK {
                Unmanaged<ResultBox<Void>>.fromOpaque(box).takeRetainedValue()
                    .resume(.failure(BridgeError(status: status, message: failure)))
            }
        }
    }
}

// MARK: - C callbacks (global, so nonisolated; they run on bridge threads)

private func devicesCallback(
    _ context: UnsafeMutableRawPointer?, _ status: Int32, _ message: UnsafePointer<CChar>?,
    _ items: UnsafePointer<LsbDevice>?, _ count: Int
) {
    guard let context else { return }
    let box = Unmanaged<ResultBox<[ConnectDevice]>>.fromOpaque(context).takeRetainedValue()
    guard status == LSB_OK else {
        return box.resume(.failure(BridgeError(status: status, message: string(message) ?? "cannot list devices")))
    }
    let devices = UnsafeBufferPointer(start: items, count: items == nil ? 0 : count).map {
        ConnectDevice(
            id: string($0.id) ?? "", name: string($0.name) ?? "", type: string($0.device_type) ?? "",
            software: string($0.software) ?? "", isActive: $0.is_active)
    }
    box.resume(.success(devices))
}

private func commandCallback(_ context: UnsafeMutableRawPointer?, _ status: Int32, _ message: UnsafePointer<CChar>?) {
    guard let context else { return }
    let box = Unmanaged<ResultBox<Void>>.fromOpaque(context).takeRetainedValue()
    if status == LSB_OK {
        box.resume(.success(()))
    } else {
        box.resume(.failure(BridgeError(status: status, message: string(message) ?? "command failed")))
    }
}

/// Copies the state and returns at once. The bridge waits for this callback in
/// `lsb_connect_watch` and `lsb_free`, so it must never block on the main thread.
func stateCallback(_ context: UnsafeMutableRawPointer?, _ state: UnsafePointer<LsbPlayerState>?) {
    guard let context, let state else { return }
    let box = Unmanaged<StateBox>.fromOpaque(context).takeUnretainedValue()
    let raw = state.pointee
    box.deliver(SpotifyPlayerState(
        activeDeviceID: string(raw.active_device_id) ?? "", trackURI: string(raw.track_uri) ?? "",
        contextURI: string(raw.context_uri) ?? "", position: Double(raw.position_ms) / 1000,
        duration: Double(raw.duration_ms) / 1000, isRunning: raw.is_playing && !raw.is_paused,
        hasTrack: raw.is_playing))
}
