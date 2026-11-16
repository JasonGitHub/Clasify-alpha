import CoreGraphics
import Foundation
import SwiftUI
import Testing
import simd

@testable import ClasifySkins

/// Card BT row 2 (CLA-118): the About showroom, checked against the trial page's row 2.
@MainActor struct K3DShowroomTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    /// At rest on the back: a turn to it that ended 1 s before `t0`.
    var back: K3DFlip { K3DFlip().go(to: 180, time: K3DFlip.turnOver, soft: true, at: t0.addingTimeInterval(-1)) }

    /// A drag of `dx`, `dy` points from the resting front, released at `t0`.
    func released(_ dx: Double, _ dy: Double = 0, from flip: K3DFlip = K3DFlip(), reduceMotion: Bool = false) -> K3DFlip {
        var drag = K3DShowroom(flip: flip, at: t0)
        let held = drag.changed(CGSize(width: dx, height: dy), flip: flip)
        return drag.ended(flip: held, reduceMotion: reduceMotion, at: t0)
    }

    @Test func theFlagReadsItsThreeModes() {
        #expect(K3DShowroom.Mode(nil) == .drag)
        #expect(K3DShowroom.Mode("drag") == .drag)
        #expect(K3DShowroom.Mode("option") == .option)
        #expect(K3DShowroom.Mode("off") == .off)
        #expect(K3DShowroom.Mode("other") == .off)
    }

    /// Changes 305 and 307: 0.6° per point of horizontal travel, 0.1° tilt per point of
    /// vertical travel, clamped to ±6°. The 2D device does not show while the drag holds it.
    @Test func aDragHoldsTheDeviceWithAClampedTilt() {
        var drag = K3DShowroom(flip: K3DFlip(), at: t0)
        let held = drag.changed(CGSize(width: 50, height: 30), flip: K3DFlip())
        #expect(drag.moved)
        #expect(held.angle(at: t0) == 30)
        #expect(abs(held.tilt(at: t0) - 3) < 1e-9)
        #expect(held.flatOpacity(at: t0) == 0 && !held.restsOnFront(at: t0))
        #expect(drag.changed(CGSize(width: 0, height: 200), flip: K3DFlip()).tilt(at: t0) == 6)
        #expect(drag.changed(CGSize(width: 0, height: -200), flip: K3DFlip()).tilt(at: t0) == -6)
    }

    /// A press that travels 4 points or less is a click.
    @Test func aShortPressIsAClick() {
        var drag = K3DShowroom(flip: K3DFlip(), at: t0)
        _ = drag.changed(CGSize(width: 2, height: 2), flip: K3DFlip())
        #expect(!drag.moved)
        let go = drag.target(angle: 0)
        #expect(go.side == 180 && go.time == K3DFlip.turnOver && go.soft)
    }

    /// Change 304: a click turns the device over in 0.8 s; a click on the back turns it to the front.
    @Test func aClickTurnsTheDeviceOver() {
        let back = released(1)
        #expect(back.toBack && back.length == 0.8)
        #expect(back.angle(at: t0.addingTimeInterval(0.8)) == 180)
        let front = released(1, from: self.back)
        #expect(!front.toBack)
        #expect(front.restsOnFront(at: t0.addingTimeInterval(0.8)))
    }

    /// Change 305: 20° or more goes on to the next side in 0.8 s; less goes back in 0.4 s.
    @Test func theReleaseGoesOnFrom20Degrees() {
        let on = released(34)  // 20.4°
        #expect(on.toBack && on.length == K3DFlip.turnOver)
        let left = released(-34)
        #expect(left.toBack && abs(left.angle(at: t0) - (360 - 34 * K3DShowroom.perPoint)) < 1e-9)
        let back = released(32)  // 19.2°
        #expect(!back.toBack && back.length == K3DFlip.dragReturn)
        #expect(back.restsOnFront(at: t0.addingTimeInterval(0.4)))
        // A drag past more than half a turn lands on the nearest side in that direction.
        let far = K3DShowroom(flip: K3DFlip(), at: t0)
        var moved = far
        _ = moved.changed(CGSize(width: 600, height: 0), flip: K3DFlip())
        #expect(moved.target(angle: 360).side == 360)
        #expect(moved.target(angle: 250).side == 180)
    }

    /// Change 306 (trial `go(.., .8, true)`): ease-out to 3° past the side over 75 % of the time,
    /// then a quad in-out back over 25 %.
    @Test func theTurnOverLandsSoftly() {
        let flip = K3DFlip().go(to: 180, time: 0.8, soft: true, at: t0)
        func angle(_ u: Double) -> Double { flip.angle(at: t0.addingTimeInterval(0.8 * u)) }
        #expect(abs(angle(0.75) - 183) < 1e-9)
        #expect(abs(angle(0.375) - 183 * K3DFlip.easeOut(0.5)) < 1e-9)
        #expect(abs(angle(0.875) - (180 + 3 * (1 - K3DFlip.quad(0.5)))) < 1e-9)
        #expect(angle(1) == 180 && angle(2) == 180)
        // Toward −180 the landing goes past on the other side, and the angles end at 0 or 180.
        let left = K3DFlip().go(to: -180, time: 0.8, soft: true, at: t0)
        #expect(left.to == 180 && left.toBack)
        #expect(abs(left.angle(at: t0.addingTimeInterval(0.6)) - 177) < 1e-9)
    }

    /// Change 307: the tilt levels out in the first half of the turn after the release.
    @Test func theTiltLevelsOnRelease() {
        let flip = released(50, 40)
        #expect(abs(flip.tilt(at: t0) - 4) < 1e-9)
        #expect(abs(flip.tilt(at: t0.addingTimeInterval(0.2)) - 4 * (1 - K3DFlip.easeOut(0.5))) < 1e-9)
        #expect(flip.tilt(at: t0.addingTimeInterval(0.4)) == 0)
        #expect(flip.tilt(at: .distantFuture) == 0)
    }

    /// Change 301: on the back, MENU turns the device to the front with the same landing; on the
    /// front it does nothing.
    @Test func menuOnTheBackTurnsToTheFront() throws {
        #expect(back.toBack && back.isResting(at: t0) && back.angle(at: t0) == 180)
        let front = try #require(K3DShowroom.front(flip: back, reduceMotion: false, at: t0))
        #expect(!front.toBack && front.length == K3DFlip.turnOver)
        #expect(abs(front.angle(at: t0.addingTimeInterval(0.6)) - 3) < 1e-9)
        #expect(front.restsOnFront(at: t0.addingTimeInterval(0.8)))
        #expect(K3DShowroom.front(flip: K3DFlip(), reduceMotion: false, at: t0) == nil)
        // Early in a turn to the back (77° after 0.1 s), MENU goes back to the front.
        let away = K3DFlip().go(to: 180, time: K3DFlip.turnOver, soft: true, at: t0)
        let t = t0.addingTimeInterval(0.1)
        #expect(away.angle(at: t) < 90)
        let back = try #require(K3DShowroom.front(flip: away, reduceMotion: false, at: t))
        #expect(!back.toBack && back.angle(at: t.addingTimeInterval(0.8)) == 0)
    }

    /// Change 302: with Reduce Motion the side changes with a 0.2 s crossfade, and no turn.
    @Test func reduceMotionSwapsTheSide() throws {
        let flip = released(40, reduceMotion: true)
        #expect(flip.toBack && flip.length == K3DFlip.swapTime)
        #expect(flip.angle(at: t0.addingTimeInterval(0.05)) == 24)
        #expect(flip.angle(at: t0.addingTimeInterval(0.15)).truncatingRemainder(dividingBy: 360) == 180)
        #expect(flip.look(at: t0.addingTimeInterval(0.1)).opacity < 1e-9)
        #expect(flip.look(at: t0.addingTimeInterval(0.2)).opacity == 1)
        let front = try #require(K3DShowroom.front(flip: back, reduceMotion: true, at: t0))
        #expect(front.flatOpacity(at: t0.addingTimeInterval(0.1)) < 1e-9)
        #expect(front.flatOpacity(at: t0.addingTimeInterval(0.25)) == 1)
    }

    /// Change 297: 16° and back in 0.9 s, a sine bump on a quad in-out. The 2D device fades
    /// out in its first 0.1 s and back in its last 0.1 s.
    @Test func theNudgeTurns16DegreesAndBack() {
        let flip = K3DFlip().nudge(at: t0)
        #expect(flip.length == 0.9)
        #expect(abs(flip.angle(at: t0.addingTimeInterval(0.45)) - 16) < 1e-9)
        #expect(abs(flip.angle(at: t0.addingTimeInterval(0.9))) < 1e-9)
        #expect(flip.flatOpacity(at: t0) == 1 && flip.flatOpacity(at: t0.addingTimeInterval(0.1)) == 0)
        #expect(flip.flatOpacity(at: t0.addingTimeInterval(0.45)) == 0)
        #expect(flip.flatOpacity(at: t0.addingTimeInterval(1)) == 1)
    }

    /// A turn that starts from the resting front fades the 2D device out in 0.1 s; a turn that
    /// ends on the front fades it in over its last 0.1 s.
    @Test func the2DDeviceCrossfadesAtTheFront() {
        let away = K3DFlip().go(to: 180, time: 0.8, soft: true, at: t0)
        #expect(away.flatOpacity(at: t0) == 1)
        #expect(abs(away.flatOpacity(at: t0.addingTimeInterval(0.05)) - 0.5) < 1e-9)
        #expect(away.flatOpacity(at: t0.addingTimeInterval(0.8)) == 0)
        let home = released(10)
        #expect(home.flatOpacity(at: t0) == 0)
        #expect(home.flatOpacity(at: t0.addingTimeInterval(0.5)) == 1)
    }

    /// Change 296: the case takes the drag; the screen and the wheel keep their jobs.
    @Test func theCaseIsTheHandle() {
        let path = K3DShowroom.casePath
        #expect(path.contains(CGPoint(x: 10, y: 300), eoFill: true))  // the side of the case
        #expect(path.contains(CGPoint(x: 183, y: 290), eoFill: true))  // between screen and wheel
        #expect(!path.contains(CGPoint(x: 183, y: 145), eoFill: true))  // the screen
        #expect(!path.contains(CGPoint(x: 183, y: 433.5), eoFill: true))  // the center button
        #expect(!path.contains(CGPoint(x: 183, y: 340), eoFill: true))  // the wheel
        #expect(!path.contains(CGPoint(x: 2, y: 2), eoFill: true))  // outside the round corner
    }

    /// Change 307: the tilt is a pitch about the x axis (k3d_src3.js `draw`); at 0 the matrix
    /// is the turn alone.
    @Test func theTiltPitchesTheModel() {
        let flat = K3DRenderer.modelView(angle: 30, lift: 0)
        #expect(flat == K3DRenderer.modelView(angle: 30, lift: 0, tilt: 0))
        let m = K3DRenderer.modelView(angle: 0, lift: 0, tilt: 6)
        let s = Float(sin(6 * Double.pi / 180)), c = Float(cos(6 * Double.pi / 180))
        #expect(abs(m.columns.1.y - c) < 1e-6 && abs(m.columns.1.z - s) < 1e-6)
        #expect(abs(m.columns.2.y + s) < 1e-6 && abs(m.columns.2.z - c) < 1e-6)
    }
}
