import Testing
@testable import ClasifyCore

/// Card AN.1: a partly covered myPod is not shown, so the icon brings it to the front.
@Suite struct WindowCoverTests {
    typealias Box = WindowCover.Box
    // A 400 x 600 window at x 100, y 200 (AppKit, y up) on a 1000 point high main screen.
    let frame = Box(x: 100, y: 200, width: 400, height: 600)
    var device: Box { WindowCover.device(frame: frame, mainHeight: 1000, top: 5, leading: 60, bottom: 90, trailing: 60) }

    @Test func theDeviceIsTheWindowLessItsMargin() {
        // The window's top is at y 1000 - 800 = 200 from the top of the screen.
        #expect(device == Box(x: 160, y: 205, width: 280, height: 505))
    }

    @Test func aWindowOverTheDeviceCovers() {
        let over = WindowCover.Window(bounds: Box(x: 400, y: 300, width: 500, height: 100), layer: 0, alpha: 1)
        #expect(WindowCover.isCovered(device, by: [over]))
    }

    @Test func aWindowOverOnlyTheMarginDoesNotCover() {
        // Over the right margin (x 440 to 500) and the bottom margin, not the device.
        let right = WindowCover.Window(bounds: Box(x: 440, y: 205, width: 300, height: 400), layer: 0, alpha: 1)
        let below = WindowCover.Window(bounds: Box(x: 100, y: 710, width: 400, height: 200), layer: 0, alpha: 1)
        #expect(!WindowCover.isCovered(device, by: [right, below]))
    }

    @Test func menusClearWindowsAndOtherLayersDoNotCover() {
        let bounds = Box(x: 200, y: 300, width: 100, height: 100)
        let menu = WindowCover.Window(bounds: bounds, layer: 101, alpha: 1)
        let clear = WindowCover.Window(bounds: bounds, layer: 0, alpha: 0)
        #expect(!WindowCover.isCovered(device, by: [menu, clear]))
        #expect(!WindowCover.isCovered(device, by: []))
    }
}
