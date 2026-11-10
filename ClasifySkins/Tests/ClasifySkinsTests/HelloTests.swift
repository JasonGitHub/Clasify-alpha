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

    /// Card AW: the comet waits on the wheel (change 200), then follows the thumb (change 202); the turn hint after 2 s (change 179);
    /// after the first turn, the press hint after 3 pulses.
    @Test func theColorPickTeachesTheTurnThenThePress() {
        // Change 200: 9 o'clock over the top to 3 o'clock in 2.9 s, fading at the ends, then 1 s of rest.
        let start = ColorPick.waiting(at: 0), top = ColorPick.waiting(at: 1.45), end = ColorPick.waiting(at: 2.9)
        #expect(close(start?.angle ?? 0, 180) && close(start?.opacity ?? 1, 0) && close(start?.longTail ?? 1, 0))
        #expect(close(top?.angle ?? 0, 270) && close(top?.opacity ?? 0, 1) && close(top?.longTail ?? 0, 1))
        #expect(close(end?.angle ?? 0, 360) && close(end?.opacity ?? 1, 0))
        #expect(ColorPick.waiting(at: 3.4) == nil && ColorPick.waiting(at: -1) == nil && close(ColorPick.waiting(at: 3.9)?.angle ?? 0, 180))
        // Change 202: in over 0.3 s, out 0.6 s after the last move over 0.6 s; the long tail in over 0.35 s.
        #expect(close(ColorPick.following(since: 0.15, idle: 0).opacity, 0.5) && close(ColorPick.following(since: 0.175, idle: 0).longTail, 0.5))
        #expect(close(ColorPick.following(since: 2, idle: 0.6).opacity, 1) && close(ColorPick.following(since: 2, idle: 0.9).opacity, 0.5))
        #expect(close(ColorPick.following(since: 2, idle: 1.2).opacity, 0))
        let before = ColorPick.hint(openedAt: 100, turnedAt: 0, now: 102)
        #expect(before.text == "Turn the wheel to try one" && close(before.opacity, 0))
        #expect(close(ColorPick.hint(openedAt: 100, turnedAt: 0, now: 102.4).opacity, 1))
        let after = ColorPick.hint(openedAt: 100, turnedAt: 104, now: 111.2)
        #expect(after.text == "Then press center button" && close(after.opacity, 0))
        #expect(close(ColorPick.hint(openedAt: 100, turnedAt: 104, now: 111.6).opacity, 1))
        #expect(Hello.pulse(-1) == 0 && close(Hello.pulse(0.4), 1) && close(Hello.pulse(1.6), 0.55))
    }
}
