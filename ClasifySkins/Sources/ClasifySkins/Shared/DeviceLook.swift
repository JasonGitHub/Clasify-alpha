import SwiftUI

// CLA-202: moved as they are from Spike/K3DView.swift, which is Mac-only. The 2D device uses
// them on both platforms.

/// CLA-119: the wheel key the pointer is over and the key pressed, as the app's 2D device shows
/// them now, so the 3D front's picture (`K3DSpike.snapshot`) is the face as it is at the swap.
/// Only the app's own full-size device writes `live`; nothing observes it.
@MainActor public final class WheelLook {
    public static let live = WheelLook()
    var hovered: ClickWheel.Zone?
    var pressed: ClickWheel.Zone?
    public init() {}

    /// CLA-119 (build 258: the centre button grey for the whole color spin): the live look with
    /// no key pressed. A color spin starts on the centre button's press, and the 2D device lets
    /// it go a moment later, so the spin's 3D front shows the key let go. The hover stays.
    public static var released: WheelLook {
        let look = WheelLook()
        look.hovered = live.hovered
        return look
    }
}

private struct SpinBlackKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Changes 289 and 290: while a color spin runs, the color the 2D device shows (black or
    /// not), with no fade. Nil shows the state's color with its usual fade.
    var spinBlack: Bool? {
        get { self[SpinBlackKey.self] }
        set { self[SpinBlackKey.self] = newValue }
    }
}
