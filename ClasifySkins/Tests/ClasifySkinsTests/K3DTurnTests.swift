import Foundation
import Testing

@testable import ClasifySkins

/// CLA-130 (card BT row 4, changes 351-354): Cmd + a two-finger swipe turns the 3D device.
@MainActor struct K3DTurnTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    /// Change 351: 0.5° per point across, 0.3° tilt per point up and down, at most 35°.
    @Test func aSwipeHoldsTheDeviceWithAClampedTilt() {
        let turn = K3DTurn()
        let held = turn.swiped(dx: 100, dy: 30, flip: K3DFlip(), at: t0)
        #expect(held.angle(at: t0) == 50)
        #expect(abs(held.tilt(at: t0) - 9) < 1e-9)
        #expect(!held.restsOnFront(at: t0))
        let more = turn.swiped(dx: -40, dy: 500, flip: held, at: t0)
        #expect(more.angle(at: t0) == 30)
        #expect(more.tilt(at: t0) == K3DTurn.maxTilt)
        #expect(turn.swiped(dx: 0, dy: -9000, flip: more, at: t0).tilt(at: t0) == -K3DTurn.maxTilt)
    }

    /// Change 352: with no more swipe events, the device stays at its angle.
    @Test func liftedFingersLeaveTheDeviceAtItsAngle() {
        let held = K3DTurn().swiped(dx: 260, dy: 0, flip: K3DFlip(), at: t0)
        #expect(held.angle(at: t0.addingTimeInterval(5)) == 130)
    }

    /// Change 353: Cmd up turns the device 0.8 s to the nearest front, the short way.
    @Test func cmdUpTurnsToTheNearestFront() {
        let turn = K3DTurn()
        let near = turn.swiped(dx: 200, dy: 20, flip: K3DFlip(), at: t0)  // 100°
        let back = K3DTurn.ended(flip: near, reduceMotion: false, at: t0)
        #expect(!back.restsOnFront(at: t0.addingTimeInterval(0.4)))
        let end = t0.addingTimeInterval(K3DFlip.turnOver + 0.01)
        #expect(back.restsOnFront(at: end))
        #expect(abs(back.tilt(at: end)) < 1e-9)
        let far = turn.swiped(dx: 600, dy: 0, flip: K3DFlip(), at: t0)  // 300°: the front ahead
        let ahead = K3DTurn.ended(flip: far, reduceMotion: false, at: t0)
        #expect(ahead.restsOnFront(at: end))
        #expect((-60.0...0).contains(ahead.angle(at: t0.addingTimeInterval(0.1))))
    }

    /// Change 353 with Reduce Motion: the side change is the 302 swap, as in the About drag.
    @Test func cmdUpWithReduceMotionSwaps() {
        let held = K3DTurn().swiped(dx: 200, dy: 0, flip: K3DFlip(), at: t0)
        let swap = K3DTurn.ended(flip: held, reduceMotion: true, at: t0)
        #expect(swap.script == .swap)
        #expect(swap.restsOnFront(at: t0.addingTimeInterval(2 * K3DFlip.swapTime + 0.01)))
    }

    /// Cmd up on the resting front changes nothing.
    @Test func cmdUpOnTheFrontDoesNothing() {
        #expect(K3DTurn.ended(flip: K3DFlip(), reduceMotion: false, at: t0).script == .flip)
    }

    /// Change 354: a pinch out past 0.15 opens the device, a pinch in past it closes it.
    @Test func aPinchOpensAndClosesTheDevice() {
        var turn = K3DTurn()
        var flip = turn.pinched(0.1, flip: K3DFlip(), at: t0)
        #expect(!flip.isApart(at: t0))
        #expect(turn.magnified == 0.1)
        flip = turn.pinched(0.06, flip: flip, at: t0)
        #expect(flip.isApart(at: t0))
        #expect(turn.magnified == 0)
        let open = t0.addingTimeInterval(K3DFlip.apartTurn + K3DFlip.apartTime + 0.1)
        #expect(flip.isApart(at: open) && !flip.apartRuns(at: open))
        // A pinch out on the open device does not close it.
        flip = turn.pinched(0.3, flip: flip, at: open)
        #expect(flip.isApart(at: open) && !flip.apartRuns(at: open))
        turn = K3DTurn()
        flip = turn.pinched(-0.2, flip: flip, at: open)
        #expect(flip.apartRuns(at: open))
    }

    /// Change 354: Cmd up on the open device closes it.
    @Test func cmdUpClosesTheOpenDevice() {
        var turn = K3DTurn()
        let opened = turn.pinched(0.2, flip: K3DFlip(), at: t0)
        let open = t0.addingTimeInterval(K3DFlip.apartTurn + K3DFlip.apartTime + 0.1)
        let closing = K3DTurn.ended(flip: opened, reduceMotion: false, at: open)
        #expect(closing.apartRuns(at: open) && closing.start == open)
        // While the apart script runs, Cmd up waits.
        #expect(K3DTurn.ended(flip: opened, reduceMotion: false, at: t0).start == t0)
    }

    /// The device takes no swipe or pinch during an arrival, a color spin or the apart script.
    @Test func noTurnWhileAScriptRuns() {
        var turn = K3DTurn()
        let arriving = K3DFlip.waiting
        #expect(!K3DTurn.canTurn(arriving, at: t0))
        #expect(turn.swiped(dx: 100, dy: 0, flip: arriving, at: t0).arriving)
        let opening = turn.pinched(0.2, flip: K3DFlip(), at: t0)
        #expect(!K3DTurn.canTurn(opening, at: t0))
        #expect(turn.swiped(dx: 100, dy: 0, flip: opening, at: t0).script == .apart)
        #expect(K3DTurn.canTurn(K3DFlip(), at: t0))
    }
}
