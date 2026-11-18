import Testing
@testable import ClasifyCore

/// CLA-130 (card BT row 4): while Cmd + a swipe holds the 3D device off its front, the wheel,
/// the buttons and the keys do nothing.
@Suite struct DeviceTurnTests {
    @Test func aTurnedDeviceTakesNoInputUntilItIsBack() {
        var s = mainMenu()
        send(&s, .deviceTurned(true))
        #expect(s.deviceTurned)
        let before = s
        for action: Action in [.wheel(1), .select, .menu, .play, .next, .prev, .toggleShuffle, .cycleRepeat] {
            let fx = send(&s, action)
            #expect(s == before && fx.isEmpty, "\(action)")
        }
        send(&s, .deviceTurned(false))
        #expect(!s.deviceTurned)
        let sel = s.top.sel
        send(&s, .wheel(1))
        #expect(s.top.sel == sel + 1)  // back on its front, the wheel moves the row again
    }
}
