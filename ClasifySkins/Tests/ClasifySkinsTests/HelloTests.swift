import CoreGraphics
import Testing

@testable import ClasifySkins

/// The Hello screen's times (Round 13, card AT, changes 160 to 168).
@Suite struct HelloTests {
    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

    @Test func theWordIsOnePathOf22Curves() {
        #expect(Hello.curves.start == CGPoint(x: 20, y: 80))
        #expect(Hello.curves.curves.count == 22)
        #expect(Hello.curves.curves.last?.2 == CGPoint(x: 282, y: 62))
    }

    @Test func eachLookWritesInTwoSecondsThenFades() {
        #expect(close(Hello.written(look: 1, at: 3.2), 0) && close(Hello.written(look: 1, at: 5.2), 1))
        #expect(close(Hello.written(look: 1, at: 4.2), 0.5))  // ease-in-out is half way at half time
        #expect(close(Hello.written(look: 0, at: 0.7), 0.25))  // T1's pixels come on at an even pace
        #expect(Hello.opacity(look: 1, at: 2.9) == 0 && Hello.opacity(look: 1, at: 5.8) == 1)
        #expect(close(Hello.opacity(look: 1, at: 6.0), 0.5) && close(Hello.opacity(look: 1, at: 6.2), 0))
        #expect(Hello.opacity(look: 4, at: 22.0) == 1 && close(Hello.opacity(look: 4, at: 22.4), 0))
        #expect(Hello.opacity(look: 0, at: 0) == 1)
    }

    @Test func glassWobblesOnceAndALightRunsAlongIt() {
        #expect(Hello.wobble(at: 14.0) == CGSize(width: 1, height: 1))
        #expect(close(Hello.wobble(at: 14.45).width, 1.035) && close(Hello.wobble(at: 14.45).height, 0.97))
        #expect(Hello.wobble(at: 15.0) == CGSize(width: 1, height: 1))
        #expect(Hello.glint(at: 13.9) == nil && Hello.glint(at: 14.0) == nil && Hello.glint(at: 16) == nil)
        let middle = Hello.glint(at: 14.95)
        #expect(middle.map { close($0.lowerBound, 0.5) && close($0.upperBound, 0.55) } == true)
    }

    @Test func theGlowComesFirstThenTheTextAfterThreePulses() {
        #expect(Hello.glow(at: 15.9, reduceMotion: false) == 0)
        #expect(close(Hello.glow(at: 16.4, reduceMotion: false), 1))
        #expect(close(Hello.glow(at: 17.6, reduceMotion: false), 0.55))
        #expect(Hello.text(at: 23.2, reduceMotion: false) == 0 && close(Hello.text(at: 23.6, reduceMotion: false), 1))
        #expect(Hello.text(at: 100, reduceMotion: false) == 1)  // it stays through the redraws
        // Reduce Motion: the glow from the start, the text after 3 pulses.
        #expect(close(Hello.glow(at: 0.4, reduceMotion: true), 1) && close(Hello.text(at: 7.6, reduceMotion: true), 1))
    }

    @Test func thePixelsFollowThePath() {
        #expect(Hello.pixels.count > 300)
        #expect(Hello.pixels.first?.part == 0 && Hello.pixels.last?.part == 39)
        // The first pixels sit at the path's start: x 50 + 20 x 2/3, y 72.5 + 80 x 2/3, in 1.875 point pixels.
        let first = Hello.pixels.filter { $0.part == 0 }
        #expect(first.contains { abs(Double($0.x) - 33.8) < 3 && abs(Double($0.y) - 67.1) < 3 })
    }

    /// Card AW: the rim light goes around every 3 s; the turn hint after 9 s; after the first
    /// turn, the press hint after 3 pulses.
    @Test func theColorPickTeachesTheTurnThenThePress() {
        #expect(close(ColorPick.rimAngle(at: 0), 0) && close(ColorPick.rimAngle(at: 1.5), 180) && close(ColorPick.rimAngle(at: 3), 0))
        let before = ColorPick.hint(openedAt: 100, turnedAt: 0, now: 109)
        #expect(before.text == "Turn the wheel to try one" && before.opacity == 0)
        #expect(close(ColorPick.hint(openedAt: 100, turnedAt: 0, now: 109.4).opacity, 1))
        let after = ColorPick.hint(openedAt: 100, turnedAt: 104, now: 111.2)
        #expect(after.text == "Then press center button" && after.opacity == 0)
        #expect(close(ColorPick.hint(openedAt: 100, turnedAt: 104, now: 111.6).opacity, 1))
        #expect(Hello.pulse(-1) == 0 && close(Hello.pulse(0.4), 1) && close(Hello.pulse(1.6), 0.55))
    }
}
