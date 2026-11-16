import Foundation
import Metal
import Testing

@testable import ClasifySkins

/// CLA-105 PR D: the input that takes the device apart on About, as the showroom trial
/// (design-review/round20/bt/show/index.html lines 66 to 78).
struct K3DApartInputTests {
    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    /// Dates round (`at(2.3)` is 2.2999999999999545 s): compare within 1e-6, and check a
    /// phase's end 1 µs after it.
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
    func after(_ s: Double) -> Date { at(s + 1e-6) }

    var onBack: K3DFlip {
        var flip = K3DFlip()
        flip.toggle(at: t0.addingTimeInterval(-5), screen: nil)
        return flip
    }

    /// The hold works only on the back, at rest, closed.
    @Test func theHoldIsOnlyOnTheBack() {
        #expect(K3DShowroom.holdTime == 1.2)
        #expect(K3DShowroom.canHold(flip: onBack, at: t0))
        #expect(!K3DShowroom.canHold(flip: K3DFlip(), at: t0))
        var turning = K3DFlip()
        turning.toggle(at: t0, screen: nil)
        #expect(!K3DShowroom.canHold(flip: turning, at: at(0.5)))
        let open = onBack.apart(at: t0)
        #expect(!K3DShowroom.canHold(flip: open, at: at(1)) && !K3DShowroom.canHold(flip: open, at: at(5)))
    }

    /// Apart, a drag turns the device 0.5° per point (row 3, change 309) and tilts it 0.3° per point from the tilt
    /// at the press, up to 35° each way. The release leaves it where it is, still apart.
    @Test func apartADragTurnsAndTilts() {
        let open = onBack.apart(at: t0)
        var drag = K3DShowroom(flip: open, at: at(3))
        #expect(drag.apart && near(drag.angle0, 305) && near(drag.tilt0, 20))
        let a = drag.changed(CGSize(width: 50, height: 10), flip: open)
        #expect(abs(a.angle(at: at(3)) - 330) < 1e-9 && abs(a.tilt(at: at(3)) - 23) < 1e-9)
        let b = drag.changed(CGSize(width: -100, height: 100), flip: open)
        #expect(abs(b.angle(at: at(3)) - 255) < 1e-9 && b.tilt(at: at(3)) == 35)
        let c = drag.changed(CGSize(width: 0, height: -300), flip: open)
        #expect(c.tilt(at: at(3)) == -35)
        let released = drag.ended(flip: b, reduceMotion: false, at: at(3))
        #expect(released.angle(at: at(4)) == b.angle(at: at(3)) && released.ex(at: at(4)) == 1)
    }

    /// Apart, a click with no move puts the device together and turns it to the front.
    @Test func apartAClickCloses() {
        let open = onBack.apart(at: t0)
        let click = K3DShowroom(flip: open, at: at(3))
        let close = click.ended(flip: open, reduceMotion: false, at: at(3))
        #expect(close.apartRuns(at: at(3.1)) && near(close.ex(at: at(4.6)), 0))
        #expect(close.restsOnFront(at: after(5.2)) && near(close.angle(at: after(5.2)), 0))
    }

    /// While the device opens or closes, input waits; apart, it counts as apart.
    @Test func whileItRunsInputWaits() {
        let open = onBack.apart(at: t0)
        #expect(open.apartRuns(at: at(1)) && open.isApart(at: at(0.1)))
        #expect(!open.apartRuns(at: after(2.3)) && open.isApart(at: after(2.3)))
        #expect(!onBack.isApart(at: t0) && !onBack.apartRuns(at: t0))
        let closed = open.apart(at: at(3))
        #expect(!closed.isApart(at: after(5.2)))
    }

    /// The warm-up frame at the hold's start does not count as apart: a closed frame after it
    /// does not free the prints. Its time goes to the log.
    @Test(.enabled(if: Self.hasMetal, "no Metal device")) @MainActor func theWarmUpFrameKeepsThePrints() async throws {
        let renderer = try #require(K3DRenderer())
        await renderer.preparePrints().value
        #expect(renderer.printsReady)
        let clock = ContinuousClock()
        let start = clock.now
        renderer.warmApart()
        let warm = clock.now - start
        _ = renderer.image(K3DPose(angle: 180), screen: nil, size: CGSize(width: 64, height: 64), scale: 1)
        #expect(renderer.printsReady)
        #expect(renderer.warmed)
        print("CLA-105 D: warm-up apart frame, main actor time (not waited for) \(warm)")
        let bind = try #require(renderer.printsBindTime)
        print("CLA-105 D: prints bind on the main actor (upload + mipmap commands) \(bind)")
    }
}
