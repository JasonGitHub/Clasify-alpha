import CoreGraphics
import SwiftUI
import Testing

@testable import ClasifySkins

/// CLA-142: the device window's first place, with no saved frame.
struct FirstWindowPlaceTests {
    /// `DeviceWindow.margin` and the device window's size (the 366 x 613 device and that margin).
    let margin = EdgeInsets(top: 5, leading: 60, bottom: 90, trailing: 60)
    let window = CGSize(width: 486, height: 708)

    /// Jason's screen: 1710 x 1107 pt, the menu bar 37 pt. The device's center is at the visible
    /// area's center, not 207 pt left and 100 pt low as in build 330.
    @Test func theDeviceIsAtTheCenter() {
        let visible = CGRect(x: 0, y: 37, width: 1710, height: 1070)
        let origin = FirstWindowPlace.origin(visible: visible, window: window, margin: margin)
        #expect(origin == CGPoint(x: 612, y: 260.5))
        #expect(origin.x + 60 + 183 == visible.midX)
        #expect(origin.y + 5 + 306.5 == visible.midY)
    }

    /// A display whose visible area does not start at 0 (a second screen, a Dock on the left).
    @Test func anOffsetDisplayKeepsTheDeviceAtItsCenter() {
        let visible = CGRect(x: 1710, y: 25, width: 1920, height: 1055)
        let origin = FirstWindowPlace.origin(visible: visible, window: window, margin: margin)
        #expect(origin.x + 243 == visible.midX)
        #expect(origin.y + 311.5 == visible.midY)
    }

    /// A small screen: the window stays inside the visible area.
    @Test func aSmallScreenKeepsTheWindowInside() {
        let visible = CGRect(x: 0, y: 25, width: 1024, height: 700)
        let origin = FirstWindowPlace.origin(visible: visible, window: window, margin: margin)
        #expect(origin.y == 25)  // the device's center would put the window's bottom below the area
        #expect(origin.x + window.width <= visible.maxX)
        #expect(origin.x + 243 == visible.midX)
        let tiny = CGRect(x: 0, y: 25, width: 400, height: 500)
        #expect(FirstWindowPlace.origin(visible: tiny, window: window, margin: margin) == CGPoint(x: 0, y: 25))
    }
}
