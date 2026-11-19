import Foundation
import Testing

@testable import ClasifySkins

/// CLA-138 (build 327: one empty frame as a Cmd turn starts): the 3D body must be on screen
/// under the opaque 2D device for some frames before the 2D device goes, as in a color spin.
@MainActor struct K3DCmdStartTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    /// One 60 fps frame: the 2D device's opacity (the Metal view is ready) and whether the
    /// Metal view is at full opacity, as `K3DFlipView` shows them.
    struct Frame { let shown: Double, visible: Bool, angle: Double }

    func frame(_ flip: K3DFlip, at time: Date) -> Frame {
        let shown = flip.flatOpacity(at: time)
        return Frame(shown: shown, visible: flip.bodyShows(shown: shown), angle: flip.angle(at: time))
    }

    /// A fast swipe from the resting front, one event per frame of 20 points (10°).
    @Test func aCmdStartShowsTheBodyUnderThe2DDeviceFirst() throws {
        var turn = K3DTurn()
        var flip = K3DFlip()
        var frames: [Frame] = []
        for i in 0..<12 {
            let time = t0.addingTimeInterval(Double(i) / 60)
            flip = turn.swipe(dx: 20, dy: 0, flip: flip, at: time)
            frames.append(frame(flip, at: time))
        }
        let gone = try #require(frames.firstIndex { $0.shown < 1 })
        // Before the 2D device drops below 1: frames with the Metal view at full opacity, at the
        // front pose (a body drawn where the 2D device is), under the opaque 2D device.
        let under = frames[..<gone].filter { $0.visible && $0.shown >= 1 && $0.angle == 0 }
        #expect(under.count >= 2, "\(under.count) frames of overlap")
        #expect(frames[gone - 1].visible)  // the frame just before the 2D device goes
        #expect(frames[gone].angle > K3DShader.restAngle)  // the jump that needs the overlap
        let hidden = frames[gone...].filter { !$0.visible }.count
        #expect(hidden == 0)  // the 3D body stays on screen while the device is turned
    }

    /// At rest on the front, and on every timed path, the Metal view is visible only when the
    /// 2D device is below 1, as before: the reduce-motion swap and the turn back at Cmd up.
    @Test func otherPathsAreUnchanged() {
        let rest = K3DFlip()
        #expect(!rest.bodyShows(shown: rest.flatOpacity(at: t0)))
        let held = K3DTurn().swiped(dx: 200, dy: 0, flip: K3DFlip(), at: t0)
        for reduceMotion in [true, false] {
            let back = K3DTurn.ended(flip: held, reduceMotion: reduceMotion, at: t0)
            for i in 0..<120 {
                let time = t0.addingTimeInterval(Double(i) / 60)
                let shown = back.flatOpacity(at: time)
                #expect(back.bodyShows(shown: shown) == (shown < 1), "frame \(i), reduce motion \(reduceMotion)")
            }
        }
    }
}
