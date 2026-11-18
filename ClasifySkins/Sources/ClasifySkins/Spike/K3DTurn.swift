import Foundation

/// CLA-130 (card BT row 4, changes 351-354): Cmd + a two-finger swipe turns the 3D device on
/// any screen. The app's event wrapper sends the swipe here and shows the `K3DFlip` it gives back.
///
/// The angle and the tilt are view animation state, like the About drag (`K3DShowroom`): a
/// trackpad sends about 120 scroll events a second, and those must not go through the Store,
/// where each one would draw the skin again. Only `Action.deviceTurned` goes through the reducer.
///
/// - 351: the device turns 0.5° per point of finger travel across, and tilts 0.3° per point
///   up and down, at most 35° each way. A mouse wheel with Cmd does the same.
/// - 352: lifted fingers leave the device at its angle. A flick glides: macOS sends the glide
///   as momentum scroll events, so this takes them like the swipe and needs no timer.
/// - 353: Cmd up ends the turn. If the device is apart, it closes (which turns it to the
///   front); else it turns 0.8 s to the nearest front with the 3° soft landing (306). With
///   Reduce Motion it changes side as the About drag does today (the 302 swap).
/// - 354: Cmd + a pinch out past `pinch` takes the device apart (the 308 motion); a pinch in
///   past it puts the device together.
public struct K3DTurn: Equatable {
    public static let perPoint = K3DShowroom.perPoint, tiltPerPoint = K3DShowroom.tiltPerPoint
    public static let maxTilt = K3DShowroom.maxTilt
    /// The pinch's sum of magnification that opens (+) or closes (−) the device.
    public static let pinch = 0.15

    /// The pinch since the last open or close, or since Cmd went down.
    public private(set) var magnified = 0.0

    public init() {}

    /// A swipe moved the fingers `dx`, `dy` points (right and down are +). The device holds the
    /// new pose. During an arrival, a spin or the apart script, it does not move.
    public func swiped(dx: Double, dy: Double, flip: K3DFlip, at now: Date) -> K3DFlip {
        guard Self.canTurn(flip, at: now) else { return flip }
        let tilt = min(Self.maxTilt, max(-Self.maxTilt, flip.tilt(at: now) + dy * Self.tiltPerPoint))
        return flip.held(angle: flip.angle(at: now) + dx * Self.perPoint, tilt: tilt)
    }

    /// The pinch moved by `amount` (NSEvent.magnification: + is out). Past `pinch`, the device
    /// opens or closes, and the sum starts again.
    public mutating func pinched(_ amount: Double, flip: K3DFlip, at now: Date) -> K3DFlip {
        guard Self.canTurn(flip, at: now) else { return flip }
        magnified += amount
        let apart = flip.isApart(at: now)
        guard magnified >= Self.pinch && !apart || magnified <= -Self.pinch && apart else { return flip }
        magnified = 0
        return flip.apart(at: now)
    }

    /// Cmd up, once the swipe and its glide have ended: the device goes back to its front.
    public static func ended(flip: K3DFlip, reduceMotion: Bool, at now: Date) -> K3DFlip {
        if flip.apartRuns(at: now) { return flip }
        if flip.isApart(at: now) { return flip.apart(at: now) }  // closing turns it to the front
        let front = (flip.angle(at: now) / 360).rounded() * 360
        if flip.restsOnFront(at: now), flip.angle(at: now) == front, flip.tilt(at: now) == 0 { return flip }
        if reduceMotion { return flip.swap(to: front, at: now) }
        return flip.go(to: front, time: K3DFlip.turnOver, soft: true, at: now)
    }

    /// The device can take the turn: no arrival, no color spin, and no apart script running.
    public static func canTurn(_ flip: K3DFlip, at now: Date) -> Bool {
        !flip.arriving && !flip.isSpinning(at: now) && !flip.apartRuns(at: now)
    }
}
