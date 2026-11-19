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
///   past it puts the device together where it is: only Cmd up turns it to the front.
/// - 355: with a mouse, Cmd + a drag turns it, Cmd + a hold of `holdTime` with no move past
///   `slop` takes it apart, and Cmd + a click puts it together where it is.
public struct K3DTurn: Equatable {
    public static let perPoint = K3DShowroom.perPoint, tiltPerPoint = K3DShowroom.tiltPerPoint
    public static let maxTilt = K3DShowroom.maxTilt
    /// The pinch's sum of magnification that opens (+) or closes (−) the device.
    public static let pinch = 0.15
    /// Change 355: the mouse hold that takes the device apart, and the move that is not a hold.
    public static let holdTime = 1.2, slop = 4.0

    /// The pinch since the last open or close, or since Cmd went down.
    public private(set) var magnified = 0.0

    /// Build 308 (Jason: the device jumped up for one frame as a swipe started): a turn from the
    /// resting front grows the window's room (CLA-119), and for one frame the 3D body drew 53 px
    /// off. A trackpad swipe turns past 2° in its first frame, where a mouse drag does not. So
    /// for `settle` seconds the device holds at the front, where the 2D device covers the 3D body
    /// while the room grows, and the swipe's travel waits; then it turns by all of it.
    public static let settle = 0.05
    /// When this turn left the resting front, and the travel that waits for `settle`.
    public private(set) var settledFrom: Date?
    public private(set) var waitingX = 0.0, waitingY = 0.0

    public init() {}

    /// A swipe moved the fingers `dx`, `dy` points (right and down are +). The device holds the
    /// new pose. During an arrival, a spin or the apart script, it does not move.
    public func swiped(dx: Double, dy: Double, flip: K3DFlip, at now: Date) -> K3DFlip {
        guard Self.canTurn(flip, at: now) else { return flip }
        let tilt = min(Self.maxTilt, max(-Self.maxTilt, flip.tilt(at: now) + dy * Self.tiltPerPoint))
        return flip.held(angle: flip.angle(at: now) + dx * Self.perPoint, tilt: tilt)
    }

    /// A swipe event as the app sends it: `swiped`, with the first `settle` seconds held at the
    /// front when the turn leaves the resting front.
    public mutating func swipe(dx: Double, dy: Double, flip: K3DFlip, at now: Date) -> K3DFlip {
        guard Self.canTurn(flip, at: now) else { return flip }
        if settledFrom == nil, flip.restsOnFront(at: now) { settledFrom = now }
        waitingX += dx
        waitingY += dy
        if let from = settledFrom, now.timeIntervalSince(from) < Self.settle {
            return flip.held(angle: flip.angle(at: now), tilt: flip.tilt(at: now))
        }
        defer { (waitingX, waitingY) = (0, 0) }
        return swiped(dx: waitingX, dy: waitingY, flip: flip, at: now)
    }

    /// The pinch moved by `amount` (NSEvent.magnification: + is out). Past `pinch`, the device
    /// opens or closes, and the sum starts again.
    public mutating func pinched(_ amount: Double, flip: K3DFlip, at now: Date) -> K3DFlip {
        guard Self.canTurn(flip, at: now) else { return flip }
        magnified += amount
        let apart = flip.isApart(at: now)
        guard magnified >= Self.pinch && !apart || magnified <= -Self.pinch && apart else { return flip }
        magnified = 0
        return flip.apart(at: now, staysTurned: apart)
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

/// CLA-130: which scroll events turn the device, and when the turn ends (353). Plain values, so
/// the app's AppKit wrapper (`K3DTurnInput`) stays thin and this is tested. Holding Cmd alone
/// changes nothing: only a swipe, a wheel or a pinch with Cmd on the device starts a turn.
public struct K3DTurnGesture: Equatable {
    /// A scroll event, from its `phase` and `momentumPhase`.
    public enum Scroll: Equatable { case begin, move, lift, glide, glideEnd, wheel }
    /// Pass the event on; take it and do nothing; turn by its deltas; or end the turn.
    public enum Answer: Equatable { case pass, swallow, turn, end }

    /// A turn runs: the device is off its front by Cmd.
    public private(set) var turning = false
    /// The turn's fingers are down, or its glide runs.
    private(set) var fingers = false, gliding = false
    /// Cmd went up during the swipe or the glide: the turn ends when they end.
    private(set) var endPending = false
    /// The glide after a turn that ended: it goes nowhere, not to the wheel. A new swipe clears it.
    private(set) var swallowGlide = false

    public init() {}

    /// A scroll event. `command`: Cmd is down. `inside`: the event is over the device.
    public mutating func scroll(_ kind: Scroll, command: Bool, inside: Bool) -> Answer {
        switch kind {
        case .begin:
            swallowGlide = false
            guard command && inside || turning else { return .pass }
            (turning, fingers) = (true, true)
            return .turn
        case .move:
            return fingers ? .turn : .pass
        case .lift:
            guard fingers else { return .pass }
            fingers = false
            return endPending ? end() : .turn
        case .glide:
            if swallowGlide { return .swallow }
            guard turning else { return .pass }
            gliding = true
            return .turn
        case .glideEnd:
            if swallowGlide { swallowGlide = false; return .swallow }
            guard gliding else { return .pass }
            gliding = false
            return endPending ? end() : .turn
        case .wheel:
            guard command && inside || turning && command else { return .pass }
            turning = true
            return .turn
        }
    }

    /// A pinch event: it is part of the turn when Cmd is down over the device, or a turn runs.
    public mutating func pinch(command: Bool, inside: Bool) -> Bool {
        guard command && (inside || turning) else { return false }
        turning = true
        return true
    }

    /// Cmd changed. True: the turn ends now. With the fingers down or a glide running, it ends
    /// when they end (352: a flick glides first).
    public mutating func command(down: Bool) -> Bool {
        guard turning else { return false }
        if down {
            endPending = false  // Cmd down again before the swipe or glide ended: the turn goes on
            return false
        }
        if fingers || gliding {
            endPending = true
            return false
        }
        return end() == .end
    }

    /// Cmd as a turn event or the app's poll sees it (build 317). AppKit sends `flagsChanged`
    /// only to the active app, but scroll and pinch events go to the window under the pointer.
    /// So a turn can start while another app is active, and its Cmd up never comes. A system
    /// shortcut can also take the Cmd up. Cmd seen up counts as the Cmd up. True: the turn
    /// ends now. With the fingers down or a glide running, it ends when they end, as for Cmd up.
    /// Cmd seen down again before they end keeps the turn, as a Cmd down does.
    public mutating func sync(command: Bool) -> Bool {
        guard turning, command == endPending else { return false }
        return self.command(down: command)
    }

    /// The app or the window is no longer in front: a lost Cmd up must not leave input dead.
    /// True when a turn ran.
    public mutating func resign() -> Bool {
        guard turning else { return false }
        return end() == .end
    }

    /// Ends the turn. A glide may still come after it, also when Cmd went up between the lift
    /// and the glide's first event, so any glide until the next swipe goes nowhere.
    private mutating func end() -> Answer {
        (turning, fingers, gliding, endPending, swallowGlide) = (false, false, false, false, true)
        return .end
    }
}
