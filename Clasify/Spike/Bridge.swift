import Foundation
import LibrespotBridge

/// One bridge event, copied out of the C callback.
struct BridgeEvent: Sendable {
    let kind: UInt32
    let positionMs: UInt32
    let playRequestID: UInt64
    let trackURI: String?
    let message: String?

    var name: String {
        switch Int32(kind) {
        case LSB_EVENT_LOGGED_IN: "LOGGED_IN"
        case LSB_EVENT_PLAYING: "PLAYING"
        case LSB_EVENT_PAUSED: "PAUSED"
        case LSB_EVENT_POSITION: "POSITION"
        case LSB_EVENT_TRACK_ENDED: "TRACK_ENDED"
        case LSB_EVENT_UNAVAILABLE: "UNAVAILABLE"
        case LSB_EVENT_VOLUME: "VOLUME"
        case LSB_EVENT_ERROR: "ERROR"
        case LSB_EVENT_PLAY_REQUEST: "PLAY_REQUEST"
        default: "KIND_\(kind)"
        }
    }
}

/// The result of `lsb_oauth_login`, copied out of the C callback.
struct OAuthResult: Sendable {
    let accessToken: String?
    let scopes: [String]
    let clientID: String
    let redirectURI: String
    let expiresInSeconds: UInt32
    let hasRefreshToken: Bool
    let message: String?
}

/// Context for the bridge callbacks. The bridge keeps it for the app's lifetime.
private final class BridgeContext: Sendable {
    let ring: AudioRing
    let onEvent: @Sendable (BridgeEvent) -> Void

    init(ring: AudioRing, onEvent: @escaping @Sendable (BridgeEvent) -> Void) {
        self.ring = ring
        self.onEvent = onEvent
    }
}

private final class OAuthContext: Sendable {
    let onResult: @Sendable (OAuthResult) -> Void

    init(onResult: @escaping @Sendable (OAuthResult) -> Void) {
        self.onResult = onResult
    }
}

private func string(_ text: UnsafePointer<CChar>?) -> String? {
    text.map { String(cString: $0) }
}

/// Thin Swift wrapper over the C bridge. The spike keeps one bridge for the app's lifetime,
/// so it never calls `lsb_free`.
@MainActor
final class Bridge {
    private let handle: OpaquePointer

    /// `onEvent` runs on a bridge thread.
    init?(ring: AudioRing, onEvent: @escaping @Sendable (BridgeEvent) -> Void) {
        let context = Unmanaged.passRetained(BridgeContext(ring: ring, onEvent: onEvent)).toOpaque()
        let handle = lsb_new(bridgeEventCallback, bridgeAudioCallback, context)
        guard let handle else {
            Unmanaged<BridgeContext>.fromOpaque(context).release()
            return nil
        }
        self.handle = handle
    }

    func login(accessToken: String) -> Int32 { lsb_login(handle, accessToken) }
    func load(_ trackURI: String) -> Int32 { lsb_load(handle, trackURI, true, 0) }
    func play() -> Int32 { lsb_play(handle) }
    func pause() -> Int32 { lsb_pause(handle) }

    /// Starts OAuth in the browser. `onResult` runs once, on a bridge thread.
    nonisolated static func oauthLogin(onResult: @escaping @Sendable (OAuthResult) -> Void) -> Int32 {
        let context = Unmanaged.passRetained(OAuthContext(onResult: onResult)).toOpaque()
        let status = lsb_oauth_login(oauthResultCallback, context)
        if status != LSB_OK {
            Unmanaged<OAuthContext>.fromOpaque(context).release()
        }
        return status
    }
}

// The C callbacks are global functions, so they are nonisolated. They run on bridge
// threads. A closure written inside a @MainActor method would be main-actor isolated,
// and Swift 6 traps when it runs off the main thread.

private func bridgeEventCallback(_ context: UnsafeMutableRawPointer?, _ event: UnsafePointer<LsbEvent>?) {
    guard let context, let event else { return }
    let box = Unmanaged<BridgeContext>.fromOpaque(context).takeUnretainedValue()
    let raw = event.pointee
    box.onEvent(BridgeEvent(
        kind: raw.kind,
        positionMs: raw.position_ms,
        playRequestID: raw.play_request_id,
        trackURI: string(raw.track_uri),
        message: string(raw.message)
    ))
}

private func bridgeAudioCallback(_ context: UnsafeMutableRawPointer?, _ samples: UnsafePointer<Float>?, _ count: Int) {
    guard let context, let samples else { return }
    Unmanaged<BridgeContext>.fromOpaque(context).takeUnretainedValue().ring.write(samples, count: count)
}

private func oauthResultCallback(_ context: UnsafeMutableRawPointer?, _ result: UnsafePointer<LsbOAuthResult>?) {
    guard let context, let result else { return }
    let box = Unmanaged<OAuthContext>.fromOpaque(context).takeRetainedValue()
    let raw = result.pointee
    box.onResult(OAuthResult(
        accessToken: string(raw.access_token),
        scopes: (string(raw.scopes) ?? "").split(separator: " ").map(String.init),
        clientID: string(raw.client_id) ?? "",
        redirectURI: string(raw.redirect_uri) ?? "",
        expiresInSeconds: raw.expires_in_s,
        hasRefreshToken: raw.has_refresh_token,
        message: string(raw.message)
    ))
}
