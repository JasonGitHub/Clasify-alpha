import CoreGraphics
import Testing

@testable import ClasifySkins

/// The Hello screen's times (Round 13, card AT, changes 161 to 168 and 178).
@Suite struct HelloTests {
    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

    @Test func theWordIsOnePathOf22Curves() {
        #expect(Hello.curves.start == CGPoint(x: 20, y: 80))
        #expect(Hello.curves.curves.count == 22)
        #expect(Hello.curves.curves.last?.2 == CGPoint(x: 282, y: 62))
    }

    @Test func eachLookWritesInTwoSecondsThenFades() {
        // T2 Ink is look 0, T3 starts at 3.0 s.
        #expect(close(Hello.written(look: 0, at: 0.2), 0) && close(Hello.written(look: 0, at: 2.2), 1))
        #expect(close(Hello.written(look: 1, at: 4.2), 0.5))  // ease-in-out is half way at half time
        #expect(Hello.opacity(look: 0, at: 0) == 1)
        #expect(Hello.opacity(look: 1, at: 2.9) == 0 && Hello.opacity(look: 1, at: 5.8) == 1)
        #expect(close(Hello.opacity(look: 1, at: 6.0), 0.5) && close(Hello.opacity(look: 1, at: 6.2), 0))
        // T5 writes from 9.2 s, stays to 19.0 s and fades by 19.4 s, in a 19.5 s loop.
        #expect(Hello.glass == 3 && Hello.loop == 19.5)
        #expect(close(Hello.written(look: Hello.glass, at: 9.2), 0) && close(Hello.written(look: Hello.glass, at: 11.2), 1))
        #expect(Hello.opacity(look: Hello.glass, at: 19.0) == 1 && close(Hello.opacity(look: Hello.glass, at: 19.4), 0))
    }

    @Test func glassWobblesOnceAndALightRunsAlongIt() {
        #expect(Hello.wobble(at: 11.0) == CGSize(width: 1, height: 1))
        #expect(close(Hello.wobble(at: 11.45).width, 1.035) && close(Hello.wobble(at: 11.45).height, 0.97))
        #expect(Hello.wobble(at: 12.0) == CGSize(width: 1, height: 1))
        #expect(Hello.glint(at: 10.9) == nil && Hello.glint(at: 11.0) == nil && Hello.glint(at: 13) == nil)
        let middle = Hello.glint(at: 11.95)
        #expect(middle.map { close($0.lowerBound, 0.5) && close($0.upperBound, 0.55) } == true)
    }

    /// Change 178: the text comes 2 s after the T5 light ends, not after 3 pulses.
    @Test func theGlowComesFirstThenTheText() {
        #expect(Hello.glow(at: 12.9, reduceMotion: false) == 0)
        #expect(close(Hello.glow(at: 13.4, reduceMotion: false), 1))
        #expect(close(Hello.glow(at: 14.6, reduceMotion: false), 0.55))
        #expect(Hello.text(at: 14.9, reduceMotion: false) == 0 && close(Hello.text(at: 15.3, reduceMotion: false), 1))
        #expect(Hello.text(at: 100, reduceMotion: false) == 1)  // it stays through the redraws
        // Reduce Motion: the glow from the start, the text after 2 s.
        #expect(close(Hello.glow(at: 0.4, reduceMotion: true), 1))
        #expect(Hello.text(at: 2.0, reduceMotion: true) == 0 && close(Hello.text(at: 2.4, reduceMotion: true), 1))
    }

    /// CLA-86: a hint label stays solid and only its glow pulses, 0 to 1 to 0 in 2.4 s, each
    /// half eased in and out.
    @Test func theHintGlowPulsesFromNothing() {
        let p = ClickWheel.LabelGlow.strength(at:)
        #expect(p(0) == 0 && p(-1) == 0)
        #expect(close(p(1.2), 1) && close(p(2.4), 0) && close(p(3.6), 1))
        #expect(close(p(0.6), 0.5) && close(p(1.8), 0.5))  // half way by symmetry
        #expect(close(p(0.3), 0.12916) && close(p(0.9), 0.87084))  // cubic-bezier(.42, 0, .58, 1)
    }

    /// Card BQ, change 287: the fingertip dot shows the turn (the mock's `fgr` and `fgo`). Card
    /// AW: the turn hint after 2 s (change 179); after the first turn, the press hint after 3 pulses.
    @Test func theColorPickTeachesTheTurnThenThePress() {
        func at(_ t: Double) -> (angle: Double, opacity: Double) { ColorPick.finger(at: t) }
        // Hidden to 0.6 s, at 10 o'clock; faded in by 0.8 s.
        #expect(close(at(0).angle, -60) && at(0).opacity == 0 && at(0.6).opacity == 0)
        #expect(at(0.7).opacity > 0 && at(0.7).opacity < 1 && close(at(0.8).opacity, 1) && close(at(0.8).angle, -60))
        // To 3 o'clock by 2.0 s, back to 10 o'clock by 3.1 s. The ease is symmetric, so each
        // turn is half way at half time.
        #expect(close(at(1.4).angle, 15) && close(at(2.0).angle, 90) && close(at(2.55).angle, 15) && close(at(3.1).angle, -60))
        #expect(at(1.0).angle < -60 + 150 * 0.2)  // slow at the start: under 20% of the turn in the first 17% of the time
        // Faded out by 3.3 s, then rests to 4.6 s, and the loop starts again.
        #expect(at(3.2).opacity > 0 && at(3.2).opacity < 1 && at(3.3).opacity == 0 && at(4.5).opacity == 0)
        #expect(close(at(4.6 + 1.4).angle, 15) && close(at(4.6 + 0.8).opacity, 1))
        #expect(at(-1).opacity == 0)
        // cubic-bezier(.45, 0, .55, 1) and CSS ease at a few points.
        #expect(close(ColorPick.bezier(0.5, 0.45, 0, 0.55, 1), 0.5) && ColorPick.bezier(2, 0.45, 0, 0.55, 1) == 1)
        #expect(close(ColorPick.bezier(0.5, 0.25, 0.1, 0.25, 1), 0.8024))
        let before = ColorPick.hint(openedAt: 100, turnedAt: 0, now: 102)
        #expect(before.text == "Turn the wheel to try one" && close(before.opacity, 0))
        #expect(close(ColorPick.hint(openedAt: 100, turnedAt: 0, now: 102.4).opacity, 1))
        let after = ColorPick.hint(openedAt: 100, turnedAt: 104, now: 111.2)
        #expect(after.text == "Then press center button" && close(after.opacity, 0))
        #expect(close(ColorPick.hint(openedAt: 100, turnedAt: 104, now: 111.6).opacity, 1))
        #expect(Hello.pulse(-1) == 0 && close(Hello.pulse(0.4), 1) && close(Hello.pulse(1.6), 0.55))
    }
}
