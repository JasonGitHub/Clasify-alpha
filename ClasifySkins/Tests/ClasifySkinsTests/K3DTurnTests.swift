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

    /// Build 308: from the resting front, the first 0.05 s hold at the front, where the 2D device
    /// covers the 3D body while the window grows its room. Then the device turns by all of it.
    @Test func aSwipeFromTheFrontWaitsWhileTheRoomGrows() {
        var turn = K3DTurn()
        let first = turn.swipe(dx: 100, dy: 0, flip: K3DFlip(), at: t0)
        #expect(first.angle(at: t0) == 0 && !first.restsOnFront(at: t0))  // the room grows now
        #expect(first.flatOpacity(at: t0) == 1)  // the 2D device covers the 3D body
        let soon = t0.addingTimeInterval(0.03)
        let second = turn.swipe(dx: 20, dy: 10, flip: first, at: soon)
        #expect(second.angle(at: soon) == 0 && second.flatOpacity(at: soon) == 1)
        let later = t0.addingTimeInterval(K3DTurn.settle + 0.01)
        let third = turn.swipe(dx: 10, dy: 0, flip: second, at: later)
        #expect(third.angle(at: later) == 65)  // 130 points
        #expect(abs(third.tilt(at: later) - 3) < 1e-9)  // 10 points
        let fourth = turn.swipe(dx: 2, dy: 0, flip: third, at: later)
        #expect(fourth.angle(at: later) == 66)  // the travel that waited counts once
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
        // Closed, it stays at the open angle and tilt until Cmd up (354).
        let closed = open.addingTimeInterval(K3DFlip.apartTime + K3DFlip.closeTurn + 0.1)
        #expect(!flip.isApart(at: closed) && !flip.restsOnFront(at: closed))
        #expect(abs(flip.angle(at: closed) - flip.angle(at: open)) < 1e-6)
        #expect(abs(flip.tilt(at: closed) - flip.tilt(at: open)) < 1e-6)
        #expect(K3DTurn.ended(flip: flip, reduceMotion: false, at: closed).restsOnFront(at: closed.addingTimeInterval(1)))
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

/// CLA-130: which events turn the device, and when Cmd up ends the turn.
struct K3DTurnGestureTests {
    @Test func cmdAloneOrASwipeOffTheDeviceDoesNothing() {
        var g = K3DTurnGesture()
        let a1 = g.command(down: true)
        let a2 = g.command(down: false)
        #expect(!a1 && !a2)
        let a3 = g.scroll(.begin, command: false, inside: true)
        #expect(a3 == .pass)
        let a4 = g.scroll(.move, command: false, inside: true)
        #expect(a4 == .pass)
        let a5 = g.scroll(.begin, command: true, inside: false)
        #expect(a5 == .pass)
        let a6 = g.scroll(.wheel, command: true, inside: false)
        #expect(a6 == .pass)
        let a7 = g.pinch(command: false, inside: true)
        #expect(!a7 && !g.turning)
    }

    /// 352 and 353: lifted fingers keep the turn; Cmd up then ends it at once.
    @Test func cmdUpAfterTheFingersLiftEndsTheTurn() {
        var g = K3DTurnGesture()
        let a8 = g.scroll(.begin, command: true, inside: true)
        #expect(a8 == .turn)
        let a9 = g.scroll(.move, command: true, inside: false)
        #expect(a9 == .turn)  // the fingers may leave the device
        let a10 = g.scroll(.lift, command: true, inside: false)
        #expect(a10 == .turn)
        #expect(g.turning)
        let a11 = g.command(down: false)
        #expect(a11)
        #expect(!g.turning)
    }

    /// 352: Cmd up during a flick: the glide turns on, then the turn ends.
    @Test func cmdUpDuringTheGlideEndsWhenItEnds() {
        var g = K3DTurnGesture()
        _ = g.scroll(.begin, command: true, inside: true)
        _ = g.scroll(.lift, command: true, inside: true)
        let a12 = g.scroll(.glide, command: true, inside: true)
        #expect(a12 == .turn)
        let a13 = g.command(down: false)
        #expect(!a13)
        let a14 = g.scroll(.glide, command: false, inside: true)
        #expect(a14 == .turn)
        let a15 = g.scroll(.glideEnd, command: false, inside: true)
        #expect(a15 == .end)
        let a16 = g.scroll(.begin, command: false, inside: true)
        #expect(a16 == .pass)
    }

    /// Cmd up with the fingers down ends the turn at the lift; its glide goes nowhere.
    @Test func theGlideOfAnEndedTurnIsSwallowed() {
        var g = K3DTurnGesture()
        _ = g.scroll(.begin, command: true, inside: true)
        let a17 = g.command(down: false)
        #expect(!a17)
        let a18 = g.scroll(.move, command: false, inside: true)
        #expect(a18 == .turn)
        let a19 = g.scroll(.lift, command: false, inside: true)
        #expect(a19 == .end)
        let a20 = g.scroll(.glide, command: false, inside: true)
        #expect(a20 == .swallow)
        let a21 = g.scroll(.glideEnd, command: false, inside: true)
        #expect(a21 == .swallow)
        let a22 = g.scroll(.glide, command: false, inside: true)
        #expect(a22 == .pass)
    }

    /// Cmd up after the lift, before the glide's first event: the glide still goes nowhere.
    @Test func aGlideAfterCmdUpBetweenLiftAndGlideIsSwallowed() {
        var g = K3DTurnGesture()
        _ = g.scroll(.begin, command: true, inside: true)
        _ = g.scroll(.lift, command: true, inside: true)
        let a23 = g.command(down: false)
        #expect(a23)
        let a24 = g.scroll(.glide, command: false, inside: true)
        #expect(a24 == .swallow)
        let a25 = g.scroll(.glideEnd, command: false, inside: true)
        #expect(a25 == .swallow)
        let a26 = g.scroll(.begin, command: false, inside: true)
        #expect(a26 == .pass)
        let a27 = g.scroll(.glide, command: false, inside: true)
        #expect(a27 == .pass)
    }

    /// Cmd up and down again during the swipe: the turn goes on after the lift.
    @Test func cmdDownAgainKeepsTheTurn() {
        var g = K3DTurnGesture()
        _ = g.scroll(.begin, command: true, inside: true)
        _ = g.command(down: false)
        _ = g.command(down: true)
        let lift = g.scroll(.lift, command: true, inside: true)
        #expect(lift == .turn && g.turning)
        let up = g.command(down: false)
        #expect(up && !g.turning)
    }

    /// The CTO's safety exit: the app or the window goes to the back during a turn.
    @Test func resignEndsTheTurn() {
        var g = K3DTurnGesture()
        let a28 = g.resign()
        #expect(!a28)
        let a29 = g.pinch(command: true, inside: true)
        #expect(a29)
        let a30 = g.resign()
        #expect(a30 && !g.turning)
        _ = g.scroll(.begin, command: true, inside: true)
        let a31 = g.resign()
        #expect(a31)
        let a32 = g.scroll(.glide, command: false, inside: true)
        #expect(a32 == .swallow)
    }

    @Test func aWheelWithCmdTurns() {
        var g = K3DTurnGesture()
        let a33 = g.scroll(.wheel, command: true, inside: true)
        #expect(a33 == .turn)
        let a34 = g.scroll(.wheel, command: true, inside: false)
        #expect(a34 == .turn)
        let a35 = g.scroll(.wheel, command: false, inside: true)
        #expect(a35 == .pass)
        let a36 = g.command(down: false)
        #expect(a36)
    }
}
