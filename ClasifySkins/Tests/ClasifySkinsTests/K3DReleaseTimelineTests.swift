import Foundation
import Testing

@testable import ClasifySkins

/// CLA-138 (build 330: at Cmd up from a big angle the device jumped about 25° toward the front
/// in one frame): `K3DFlipView`'s timeline must already run while the device is held, so the
/// turn that starts at the release draws its first frames with no wait.
@MainActor struct K3DReleaseTimelineTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    /// Held by a Cmd turn or an About drag: the timeline is not paused, at any time.
    @Test func theTimelineRunsWhileHeld() {
        var turn = K3DTurn()
        var flip = K3DFlip()
        for i in 0..<12 { flip = turn.swipe(dx: 20, dy: 10, flip: flip, at: t0.addingTimeInterval(Double(i) / 60)) }
        #expect(flip.script == .held)
        for later in [0.0, 0.5, 10] { #expect(!flip.pausesTimeline(at: t0.addingTimeInterval(later))) }
        let drag = K3DTurn().swiped(dx: 90, dy: 0, flip: K3DFlip(), at: t0)
        #expect(!drag.pausesTimeline(at: t0.addingTimeInterval(5)))
    }

    /// The release's turn runs the timeline until it ends; at rest on the front it pauses again.
    @Test func theReleaseRunsItThenRestPausesIt() {
        let held = K3DTurn().swiped(dx: 90, dy: 60, flip: K3DFlip(), at: t0)
        let back = K3DTurn.ended(flip: held, reduceMotion: false, at: t0)
        #expect(!back.pausesTimeline(at: t0))
        #expect(!back.pausesTimeline(at: t0.addingTimeInterval(K3DFlip.turnOver / 2)))
        #expect(back.pausesTimeline(at: t0.addingTimeInterval(K3DFlip.turnOver + 0.01)))
        #expect(K3DFlip().pausesTimeline(at: t0))
    }

    /// The release's first frames move as the turn's clock says: at 60 fps the first frame is at
    /// most 4.5° from the held pose, from 45° and the full tilt. Build 330 showed about 25°.
    @Test func theFirstReleaseFrameIsSmall() {
        let held = K3DTurn().swiped(dx: 90, dy: 200, flip: K3DFlip(), at: t0)
        #expect(held.angle(at: t0) == 45)
        let back = K3DTurn.ended(flip: held, reduceMotion: false, at: t0)
        let next = t0.addingTimeInterval(1.0 / 60)
        #expect(abs(back.angle(at: next) - 45) < 4.5)
        #expect(abs(back.tilt(at: next) - held.tilt(at: t0)) < 6)
    }
}
