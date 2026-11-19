import CoreGraphics
import Testing

@testable import ClasifySkins

@Suite struct ScrollCatcherTests {
    /// CLA-131: fingers down are more on every screen, Now Playing too, with natural scrolling
    /// on or off (CLA-48).
    @Test func fingersDownArePlusWithAnyScrollSetting() {
        #expect(ScrollCatcher.fingersDown(12, natural: true) == 12)  // natural on: down is +deltaY
        #expect(ScrollCatcher.fingersDown(-12, natural: false) == 12)  // natural off: down is -deltaY
        #expect(ScrollCatcher.fingersDown(-12, natural: true) == -12)  // fingers up: less
    }
}
