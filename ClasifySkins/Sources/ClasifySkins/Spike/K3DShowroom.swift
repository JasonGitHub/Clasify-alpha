import CoreGraphics
import Foundation
import SwiftUI

/// Card BT row 2 (CLA-118): the About showroom's rules, as in the trial page's row 2
/// (design-review/round20/bt/show/index.html). The skin sends the drag to it and shows the
/// `K3DFlip` it gives back.
///
/// - 296: the case is the handle. On the resting front, the screen and the wheel keep their jobs.
/// - 304: a click turns the device over in 0.8 s. On the back, it turns to the front.
/// - 305: a drag turns it 0.6° per point. A release 20° or more from the side it started on goes
///   on to the next side in 0.8 s; less goes back in 0.4 s.
/// - 306: every turn-over has the soft landing (`K3DFlip.go`).
/// - 307: a drag tilts it 0.1° per point of vertical travel, at most 6°. It levels on release.
/// - 302: with Reduce Motion, a release or a click changes side with a 0.2 s crossfade.
public struct K3DShowroom: Equatable {
    public static let perPoint = 0.6, tiltPerPoint = 0.1, maxTilt = 6.0, goOn = 20.0
    /// A drag shorter than this (|dx| + |dy|, points) is a click (trial: 4).
    public static let slop = 4.0
    /// Change 297: the nudge comes 1.4 s after About first opens.
    public static let nudgeDelay = 1.4

    /// The angle at the press, and the side the device was nearest then.
    public let angle0: Double, side0: Double
    /// The drag went past `slop` at some time: the release is not a click.
    public private(set) var moved = false

    public init(flip: K3DFlip, at now: Date) {
        angle0 = flip.angle(at: now)
        side0 = (angle0 / 180).rounded() * 180
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
        let tilt = min(Self.maxTilt, max(-Self.maxTilt, translation.height * Self.tiltPerPoint))
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
        let go = target(angle: flip.angle(at: now))
        if reduceMotion { return flip.swap(to: go.side, at: now) }
        return flip.go(to: go.side, time: go.time, soft: go.soft, at: now)
    }

    /// Change 301: on the back, MENU (Esc or Delete) turns the device to the front. Nil when the
    /// device is not on the back.
    public static func front(flip: K3DFlip, reduceMotion: Bool, at now: Date) -> K3DFlip? {
        guard flip.toBack else { return nil }
        let side = (flip.angle(at: now) / 180).rounded() * 180
        // The nearest front: the side before or after the back the device is on.
        let to = side + (flip.angle(at: now) < side ? -180 : 180)
        if reduceMotion { return flip.swap(to: to, at: now) }
        return flip.go(to: to, time: K3DFlip.turnOver, soft: true, at: now)
    }

    /// Change 296: the case, the device's metal round the screen and the wheel, in the 2D
    /// device's points. Fill it with the even-odd rule.
    public static var casePath: Path {
        var path = Path(roundedRect: CGRect(origin: .zero, size: PocketSkin.size), cornerRadius: K3DMesh.radius)
        // The window (K3DMesh: 313 x 238.5 at y 161.25 from the center, radius 7).
        path.addRoundedRect(in: CGRect(x: 26.5, y: 26, width: 313, height: 238.5), cornerSize: CGSize(width: 7, height: 7))
        // The wheel (K3DMesh: radius 112.8 at y −127 from the center).
        let wheel = CGPoint(x: PocketSkin.size.width / 2, y: PocketSkin.size.height / 2 - K3DMesh.wheelCenter.y)
        path.addEllipse(in: CGRect(x: wheel.x - 112.8, y: wheel.y - 112.8, width: 225.6, height: 225.6))
        return path
    }
}
