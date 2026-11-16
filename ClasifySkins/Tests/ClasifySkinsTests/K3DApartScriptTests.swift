import Foundation
import Testing

@testable import ClasifySkins

/// CLA-105 PR C: the take-apart script, as mock K.3D.8 `explode` (k3d_src3.js line 647).
struct K3DApartScriptTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    /// From the front: the parts move apart on a cubic in-out over 1.6 s, and the device turns to
    /// -55° and tilts to 20° on a quad in-out over the first 1 / 1.8 of the time.
    @Test func openingFromTheFrontTurnsAndTilts() {
        let flip = K3DFlip().apart(at: t0)
        #expect(flip.ex(at: at(0)) == 0 && flip.angle(at: at(0)) == 0 && flip.tilt(at: at(0)) == 0)
        #expect(abs(flip.ex(at: at(0.8)) - 0.5) < 1e-9)
        #expect(abs(flip.ex(at: at(0.4)) - K3DFlip.ease(0.25)) < 1e-9)
        let turned = K3DFlip.apartTime / K3DFlip.apartTurnRate
        #expect(abs(flip.angle(at: at(turned)) + 55) < 1e-9 && abs(flip.tilt(at: at(turned)) - 20) < 1e-9)
        #expect(abs(flip.angle(at: at(turned / 2)) + 27.5) < 1e-9)
        #expect(flip.ex(at: at(1.6)) == 1 && flip.angle(at: at(1.6)) == -55 && flip.tilt(at: at(1.6)) == 20)
        #expect(flip.isResting(at: at(1.6)) && !flip.isResting(at: at(1.59)))
    }

    /// Apart, only the 3D parts show: no 2D device, and the device does not rest on the front.
    @Test func apartTheTwoDDeviceDoesNotShow() {
        let flip = K3DFlip().apart(at: t0)
        #expect(flip.restsOnFront(at: at(-1)) == false)
        for s in [0.01, 0.5, 1.6, 10] {
            #expect(flip.flatOpacity(at: at(s)) == 0, "at \(s) s")
            #expect(!flip.restsOnFront(at: at(s)), "at \(s) s")
        }
    }

    /// Closing keeps the angle and the tilt; closed at -55° it still does not rest on the front.
    @Test func closingKeepsTheAngleAndTilt() {
        let open = K3DFlip().apart(at: t0)
        let close = open.apart(at: at(2))
        #expect(close.ex(at: at(2)) == 1 && close.ex(at: at(3.6)) == 0)
        #expect(abs(close.ex(at: at(2.8)) - 0.5) < 1e-9)
        for s in [2.0, 2.5, 3.6] {
            #expect(close.angle(at: at(s)) == -55 && close.tilt(at: at(s)) == 20, "at \(s) s")
        }
        #expect(!close.restsOnFront(at: at(3.6)))
        #expect(close.flatOpacity(at: at(3.6)) == 0)
    }

    /// Less than half apart, it opens again; more than half, it closes (mock `exv > .5`).
    @Test func halfwayDecidesTheWay() {
        let open = K3DFlip().apart(at: t0)
        let early = open.apart(at: at(0.5))  // ex below 0.5: opens on from where it is
        #expect(early.ex(at: at(0.5)) == open.ex(at: at(0.5)) && early.ex(at: at(2.1)) == 1)
        let late = open.apart(at: at(1.0))  // ex above 0.5: closes
        #expect(late.ex(at: at(2.6)) == 0)
    }

    /// From the back, the angle stays; the tilt still comes to 20°.
    @Test func openingFromTheBackKeepsTheAngle() {
        var flip = K3DFlip()
        flip.toggle(at: t0, screen: nil)
        let apart = flip.apart(at: at(2))
        #expect(apart.angle(at: at(3.6)) == 180 && apart.tilt(at: at(3.6)) == 20 && apart.ex(at: at(3.6)) == 1)
    }

    /// A turn of the open device keeps it open.
    @Test func aTurnKeepsTheDeviceOpen() {
        let open = K3DFlip().apart(at: t0)
        let held = open.held(angle: 200, tilt: 10)
        #expect(held.ex(at: at(3)) == 1 && held.flatOpacity(at: at(3)) == 0)
        let back = held.go(to: 180, time: 0.8, soft: true, at: at(3))
        #expect(back.ex(at: at(5)) == 1)
    }
}
