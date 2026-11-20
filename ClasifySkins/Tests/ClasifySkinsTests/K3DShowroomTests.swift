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

    /// Changes 309 and 310 (row 3): 0.5° per point of horizontal travel, 0.3° tilt per point of
    /// vertical travel, clamped to ±35°. The 2D device does not show while the drag holds it.
    @Test func aDragHoldsTheDeviceWithAClampedTilt() {
        var drag = K3DShowroom(flip: K3DFlip(), at: t0)
        let held = drag.changed(CGSize(width: 50, height: 30), flip: K3DFlip())
        #expect(drag.moved)
        #expect(held.angle(at: t0) == 25)
        #expect(abs(held.tilt(at: t0) - 9) < 1e-9)
        #expect(held.flatOpacity(at: t0) == 0 && !held.restsOnFront(at: t0))
        // CLA-119: within 2° of the front the 2D device shows by angle, the tilt counted.
        let near = drag.changed(CGSize(width: 1, height: 0), flip: K3DFlip())
        #expect(abs(near.flatOpacity(at: t0) - K3DFlip.nearRest(angle: 0.5, tilt: 0)) < 1e-12)
        #expect(drag.changed(CGSize(width: 1, height: 20), flip: K3DFlip()).flatOpacity(at: t0) == 0)
        #expect(drag.changed(CGSize(width: 0, height: 200), flip: K3DFlip()).tilt(at: t0) == 35)
        #expect(drag.changed(CGSize(width: 0, height: -200), flip: K3DFlip()).tilt(at: t0) == -35)
        // The tilt counts from the tilt at the press (trial row 3: `drag.tilt + dy * .3`).
        var again = K3DShowroom(flip: K3DFlip().held(angle: 10, tilt: 20), at: t0)
        #expect(abs(again.changed(CGSize(width: 0, height: 10), flip: K3DFlip()).tilt(at: t0) - 23) < 1e-9)
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
        #expect(back.angle(at: t0.addingTimeInterval(0.9)) == 180)
        let front = released(1, from: self.back)
        #expect(!front.toBack)
        #expect(front.restsOnFront(at: t0.addingTimeInterval(0.9)))
    }

    /// Change 305: 20° or more goes on to the next side in 0.8 s; less goes back in 0.4 s.
    @Test func theReleaseGoesOnFrom20Degrees() {
        let on = released(41)  // 20.5°
        #expect(on.toBack && on.length == K3DFlip.turnOver)
        let left = released(-41)
        #expect(left.toBack && abs(left.angle(at: t0) - (360 - 41 * K3DShowroom.perPoint)) < 1e-9)
        let back = released(38)  // 19°
        #expect(!back.toBack && back.length == K3DFlip.dragReturn)
        #expect(back.restsOnFront(at: t0.addingTimeInterval(0.5)))
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
        let flip = released(50, 40)  // 12° (change 310)
        #expect(abs(flip.tilt(at: t0) - 12) < 1e-9)
        #expect(abs(flip.tilt(at: t0.addingTimeInterval(0.2)) - 12 * (1 - K3DFlip.easeOut(0.5))) < 1e-9)
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
        #expect(front.restsOnFront(at: t0.addingTimeInterval(0.9)))
        #expect(K3DShowroom.front(flip: K3DFlip(), reduceMotion: false, at: t0) == nil)
        // Early in a turn to the back (77° after 0.1 s), MENU goes back to the front.
        let away = K3DFlip().go(to: 180, time: K3DFlip.turnOver, soft: true, at: t0)
        let t = t0.addingTimeInterval(0.1)
        #expect(away.angle(at: t) < 90)
        let home = try #require(K3DShowroom.front(flip: away, reduceMotion: false, at: t))
        #expect(!home.toBack && home.angle(at: t.addingTimeInterval(0.9)) == 0)
    }

    /// Change 302: with Reduce Motion the side changes with a 0.2 s crossfade, and no turn.
    @Test func reduceMotionSwapsTheSide() throws {
        let flip = released(42, reduceMotion: true)
        #expect(flip.toBack && flip.length == K3DFlip.swapTime)
        #expect(flip.angle(at: t0.addingTimeInterval(0.05)) == 21)
        #expect(flip.angle(at: t0.addingTimeInterval(0.15)).truncatingRemainder(dividingBy: 360) == 180)
        #expect(flip.look(at: t0.addingTimeInterval(0.1)).opacity < 1e-9)
        #expect(flip.look(at: t0.addingTimeInterval(0.2)).opacity == 1)
        let front = try #require(K3DShowroom.front(flip: back, reduceMotion: true, at: t0))
        #expect(front.flatOpacity(at: t0.addingTimeInterval(0.1)) < 1e-9)
        #expect(front.flatOpacity(at: t0.addingTimeInterval(0.25)) == 1)
    }

    /// Change 297: 16° and back in 0.9 s, a sine bump on a quad in-out. The 2D device hands
    /// over within 2° of the front (CLA-119). 386: it turns the way a right-to-left drag does.
    @Test func theNudgeTurns16DegreesAndBack() {
        let flip = K3DFlip().nudge(at: t0)
        #expect(flip.length == 0.9)
        #expect(abs(flip.angle(at: t0.addingTimeInterval(0.45)) + 16) < 1e-9)
        #expect(abs(flip.angle(at: t0.addingTimeInterval(0.9))) < 1e-9)
        let early = flip.flatOpacity(at: t0.addingTimeInterval(0.1))  // 1.2°
        #expect(flip.flatOpacity(at: t0) == 1 && early > 0 && early < 0.5)
        #expect(flip.flatOpacity(at: t0.addingTimeInterval(0.2)) == 0 && flip.flatOpacity(at: t0.addingTimeInterval(0.45)) == 0)
        #expect(flip.flatOpacity(at: t0.addingTimeInterval(1)) == 1)
    }

    /// CLA-163, card CE.1 (393): the turn hint's nudge is the same bump in 1.6 s.
    @Test func theTurnHintNudgeTakes1point6Seconds() {
        let flip = K3DFlip().nudge(at: t0, time: K3DFlip.hintNudgeTime)
        #expect(flip.length == 1.6)
        #expect(abs(flip.angle(at: t0.addingTimeInterval(0.8)) + 16) < 1e-9)
        #expect(abs(flip.angle(at: t0.addingTimeInterval(1.6))) < 1e-9)
        #expect(flip.flatOpacity(at: t0.addingTimeInterval(0.8)) == 0 && flip.flatOpacity(at: t0.addingTimeInterval(1.7)) == 1)
    }

    /// CLA-119: the 2D device hands over within 2° of the front, by angle. The turn-over that
    /// lands on the front swings 3° past it first: the 2D device waits for the landing.
    @Test func the2DDeviceCrossfadesAtTheFront() {
        let away = K3DFlip().go(to: 180, time: 0.8, soft: true, at: t0)
        #expect(away.flatOpacity(at: t0) == 1)
        let early = away.flatOpacity(at: t0.addingTimeInterval(0.002))
        #expect(early > 0 && early < 1 && away.flatOpacity(at: t0.addingTimeInterval(0.05)) == 0)
        #expect(away.flatOpacity(at: t0.addingTimeInterval(0.8)) == 0)
        let over = away.go(to: 0, time: 0.8, soft: true, at: t0.addingTimeInterval(1))
        let swing = (0..<60).map { t0.addingTimeInterval(1 + Double($0) / 100) }
        #expect(swing.contains { abs(over.angle(at: $0)) < 1 } && swing.allSatisfy { over.flatOpacity(at: $0) == 0 })
        let landing = t0.addingTimeInterval(1.7)
        #expect(abs(over.flatOpacity(at: landing) - K3DFlip.nearRest(angle: over.angle(at: landing), tilt: 0)) < 1e-12)
        #expect(over.flatOpacity(at: t0.addingTimeInterval(1.8)) == 1)
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
        #expect(!path.contains(CGPoint(x: 180, y: 440), eoFill: true))  // the center button
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
