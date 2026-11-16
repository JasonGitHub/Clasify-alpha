import Foundation
import Testing

@testable import ClasifySkins

/// CLA-105 PR C: the take-apart script, as the showroom trial Jason approved
/// (design-review/round20/bt/show/index.html `open` and `close`, with mock K.3D.8 `explode`).
struct K3DApartScriptTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    /// Dates round: `at(2.3)` is 2.2999999999999545 s after `t0`. Values are compared within
    /// 1e-6, and a phase's end is checked 1 µs after it.
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
    func after(_ s: Double) -> Date { at(s + 1e-6) }

    /// The device resting on the back, as the take-apart starts there.
    var onBack: K3DFlip {
        var flip = K3DFlip()
        flip.toggle(at: t0.addingTimeInterval(-5), screen: nil)
        return flip
    }

    /// Opening: a turn from 180° to 305° and a tilt to 20° in 0.7 s (quad in-out), with the
    /// parts closed; then the parts move apart in 1.6 s (cubic in-out) at 305°.
    @Test func openingTurnsThenMovesTheParts() {
        let flip = onBack.apart(at: t0)
        #expect(near(flip.angle(at: at(0)), 180) && near(flip.tilt(at: at(0)), 0) && near(flip.ex(at: at(0)), 0))
        #expect(near(flip.angle(at: at(0.35)), 242.5) && near(flip.tilt(at: at(0.35)), 10))
        #expect(near(flip.ex(at: at(0.35)), 0) && near(flip.ex(at: at(0.7)), 0))
        #expect(near(flip.angle(at: at(0.7)), 305) && near(flip.tilt(at: at(0.7)), 20))
        #expect(near(flip.ex(at: at(1.5)), 0.5) && near(flip.angle(at: at(1.5)), 305))
        #expect(near(flip.ex(at: at(1.1)), K3DFlip.ease(0.25)))
        #expect(near(flip.ex(at: at(2.3)), 1) && near(flip.angle(at: at(2.3)), 305) && near(flip.tilt(at: at(2.3)), 20))
        #expect(flip.isResting(at: after(2.3)) && !flip.isResting(at: at(2.29)))
    }

    /// The opening starts from the angle now as 0° to 360°: from -180° it is the same turn.
    @Test func openingStartsFromTheAngleAsZeroTo360() {
        let flip = onBack.held(angle: -180, tilt: 0).apart(at: t0)
        #expect(near(flip.angle(at: at(0)), 180) && near(flip.angle(at: at(0.7)), 305))
    }

    /// While it opens and apart, only the 3D parts show: no 2D device, not at rest on the front.
    @Test func apartTheTwoDDeviceDoesNotShow() {
        let flip = onBack.apart(at: t0)
        for s in [0.0, 0.35, 0.7, 1.5, 2.3, 10] {
            #expect(flip.flatOpacity(at: at(s)) == 0, "at \(s) s")
            #expect(!flip.restsOnFront(at: at(s)), "at \(s) s")
        }
    }

    /// Closing: the parts move together in 1.6 s where the device is (after a look-around drag),
    /// then it turns to the front by the short way and levels out in 0.6 s. Only then it rests on
    /// the front and the 2D device shows.
    @Test func closingMovesThePartsThenTurnsToTheFront() {
        let open = onBack.apart(at: t0)
        let looked = open.held(angle: 400, tilt: 30)  // a drag while apart: 400° is 40°
        let close = looked.apart(at: at(5))
        #expect(near(close.ex(at: at(5)), 1) && near(close.ex(at: at(5.8)), 0.5) && near(close.ex(at: at(6.6)), 0))
        for s in [5.0, 5.8, 6.6] {
            #expect(near(close.angle(at: at(s)), 40) && near(close.tilt(at: at(s)), 30), "at \(s) s")
            #expect(close.flatOpacity(at: at(s)) == 0 && !close.restsOnFront(at: at(s)), "at \(s) s")
        }
        #expect(near(close.angle(at: at(6.9)), 20) && near(close.tilt(at: at(6.9)), 15))
        #expect(!close.restsOnFront(at: at(7.19)))
        #expect(near(close.angle(at: at(7.2)), 0) && near(close.tilt(at: at(7.2)), 0))
        #expect(close.restsOnFront(at: after(7.2)) && close.flatOpacity(at: after(7.2)) == 1)
    }

    /// The short way: from 305° the turn to the front goes through 330°, as -55° to 0°.
    @Test func closingTurnsTheShortWay() {
        let close = onBack.apart(at: t0).apart(at: at(3))
        #expect(near(close.angle(at: at(4.6)), -55) && near(close.angle(at: at(4.9)), -27.5))
        #expect(near(close.angle(at: at(5.2)), 0))
    }

    /// Input while the script runs changes nothing (the trial's `busy`).
    @Test func theScriptRunsToItsEnd() {
        let open = onBack.apart(at: t0)
        let pressed = open.apart(at: at(1))
        #expect(near(pressed.ex(at: at(3)), 1) && near(pressed.angle(at: at(3)), 305) && pressed.ends == open.ends)
        #expect(open.apart(at: after(2.3)).ex(at: at(4)) < 1)  // ended: the next press closes
    }

    /// A drag of the open device keeps it open.
    @Test func aDragKeepsTheDeviceOpen() {
        let held = onBack.apart(at: t0).held(angle: 200, tilt: 10)
        #expect(near(held.ex(at: at(3)), 1) && held.flatOpacity(at: at(3)) == 0 && !held.restsOnFront(at: at(3)))
    }
}
