#if os(macOS)  // CLA-202: Mac only
import CoreGraphics
import Foundation
import SwiftUI

/// Card BT rows 2 and 3 (CLA-118): the About showroom's rules, as in the trial page's row 3
/// (design-review/round20/bt/show/index.html, `dev(3, true, true)`). The skin sends the drag to it and shows the
/// `K3DFlip` it gives back.
///
/// - 296: the case is the handle. On the resting front, the screen and the wheel keep their jobs.
/// - 304: a click turns the device over in 0.8 s. On the back, it turns to the front.
/// - 305, 309: a drag turns it 0.5° per point (row 3; was 0.6). A release 20° or more from the side it started on goes
///   on to the next side in 0.8 s; less goes back in 0.4 s.
/// - 306: every turn-over has the soft landing (`K3DFlip.go`).
/// - 307, 310: a drag tilts it 0.3° per point of vertical travel from the tilt at the press, at
///   most 35° each way (row 3; was 0.1° and 6°). It levels on release.
/// - 302: with Reduce Motion, a release or a click changes side with a 0.2 s crossfade.
public struct K3DShowroom: Equatable {
    public static let perPoint = 0.5, tiltPerPoint = 0.3, maxTilt = 35.0, goOn = 20.0
    /// A drag shorter than this (|dx| + |dy|, points) is a click (trial: 4).
    public static let slop = 4.0
    /// Change 297: the nudge comes 1.4 s after About first opens.
    public static let nudgeDelay = 1.4
    /// CLA-105 D (the showroom trial, bt/show/index.html): a press with no move held 1.2 s on
    /// the back takes the device apart. Apart, a drag turns and tilts it as when closed (row 3:
    /// one rate); a click with no move puts it together.
    public static let holdTime = 1.2

    /// The angle at the press, and the side the device was nearest then.
    public let angle0: Double, side0: Double
    /// CLA-105 D: the tilt at the press, and whether the device was apart.
    public let tilt0: Double, apart: Bool
    /// The drag went past `slop` at some time: the release is not a click.
    public private(set) var moved = false

    public init(flip: K3DFlip, at now: Date) {
        angle0 = flip.angle(at: now)
        side0 = (angle0 / 180).rounded() * 180
        tilt0 = flip.tilt(at: now)
        apart = flip.isApart(at: now)
    }

    /// CLA-105 D: a press on the device resting on its back, closed, may become the hold.
    public static func canHold(flip: K3DFlip, at now: Date) -> Bool {
        flip.toBack && flip.isResting(at: now) && !flip.isApart(at: now)
    }

    /// The `about.turn` flag (UserDefaults string): missing or "drag" turns the device with a
    /// plain drag on the case; "option" with an Option-drag only, so a plain drag moves the
    /// window; "off" or any other value keeps build 224's About (Play/Pause turns the device).
    public enum Mode: Equatable, Sendable {
        case drag, option, off
        public init(_ value: String?) {
            switch value {
            case nil, "drag": self = .drag
            case "option": self = .option
            default: self = .off
            }
        }
    }

    /// The pose while the drag holds the device: the drag `translation`, in points.
    public mutating func changed(_ translation: CGSize, flip: K3DFlip) -> K3DFlip {
        if abs(translation.width) + abs(translation.height) > Self.slop { moved = true }
        // Row 3 (changes 309 and 310), closed and apart alike: from the pose at the press.
        let tilt = min(Self.maxTilt, max(-Self.maxTilt, tilt0 + translation.height * Self.tiltPerPoint))
        return flip.held(angle: angle0 + translation.width * Self.perPoint, tilt: tilt)
    }

    /// The side the release goes to, and the turn's time and landing.
    public func target(angle: Double) -> (side: Double, time: Double, soft: Bool) {
        guard moved else { return (side0 + 180, K3DFlip.turnOver, true) }
        let d = angle - side0
        guard abs(d) >= Self.goOn else { return (side0, K3DFlip.dragReturn, false) }
        let halves = max(1, (abs(d) / 180).rounded())
        return (side0 + (d < 0 ? -180 : 180) * halves, K3DFlip.turnOver, true)
    }

    /// The release: the turn that starts now.
    public func ended(flip: K3DFlip, reduceMotion: Bool, at now: Date) -> K3DFlip {
        // CLA-105 D: apart, a click puts the device together; a drag leaves it where it is.
        if apart { return moved ? flip : flip.apart(at: now) }
        let go = target(angle: flip.angle(at: now))
        if reduceMotion { return flip.swap(to: go.side, at: now) }
        return flip.go(to: go.side, time: go.time, soft: go.soft, at: now)
    }

    /// Change 301: on the back, MENU (Esc or Delete) turns the device to the front. Nil when the
    /// device is not on the back.
    public static func front(flip: K3DFlip, reduceMotion: Bool, at now: Date) -> K3DFlip? {
        guard flip.toBack else { return nil }
        // The nearest front, a multiple of 360°. Early in a turn to the back the nearest side is
        // still the front, so the target is not "the nearest side + 180°".
        let to = (flip.angle(at: now) / 360).rounded() * 360
        if reduceMotion { return flip.swap(to: to, at: now) }
        return flip.go(to: to, time: K3DFlip.turnOver, soft: true, at: now)
    }

    /// Change 296: the case, the device's metal round the screen and the wheel, in the 2D
    /// device's points. Fill it with the even-odd rule.
    public static var casePath: Path {
        // The body is 366 x 613 (K3DMesh), the 2D device's size: `PocketSkin.size` is main-actor isolated.
        let w = K3DMesh.width, h = K3DMesh.height
        var path = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: K3DMesh.radius)
        // The window (K3DMesh: 313 x 238.5 at y 161.25 from the center, radius 7).
        path.addRoundedRect(in: CGRect(x: 26.5, y: 26, width: 313, height: 238.5), cornerSize: CGSize(width: 7, height: 7))
        // The wheel (K3DMesh: radius 112.8 at y −127 from the center).
        let wheel = CGPoint(x: w / 2, y: h / 2 - K3DMesh.wheelCenter.y)
        path.addEllipse(in: CGRect(x: wheel.x - 112.8, y: wheel.y - 112.8, width: 225.6, height: 225.6))
        return path
    }
}
#endif
