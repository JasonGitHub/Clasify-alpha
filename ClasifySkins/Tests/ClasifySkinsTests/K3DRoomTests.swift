import AppKit
import SwiftUI
import Testing

@testable import ClasifySkins

/// CLA-119 (build 258: the top of the turned device cut off): with `K3DRoom.extra` round the
/// app's margins, the body's frame rect is never clamped at the window's edge, at any pose the
/// app can show: every turn (tilt ±35°, lift up to 70) and the take-apart (any angle, tilt ±35°).
@MainActor struct K3DRoomTests {
    /// The app's `DeviceWindow.margin` (Clasify/ClasifyApp.swift).
    static let margin = EdgeInsets(top: 5, leading: 60, bottom: 90, trailing: 60)

    func unclamped(_ pose: K3DPose, apart: Bool) -> Bool {
        let room = K3DRoom.extra, m = Self.margin, device = PocketSkin.size
        let left = m.leading + room.leading, top = m.top + room.top
        let size = CGSize(
            width: left + device.width + m.trailing + room.trailing, height: top + device.height + m.bottom + room.bottom)
        let center = CGPoint(x: left + device.width / 2, y: top + device.height / 2)
        guard let r = K3DRenderer.bodyRect(box(apart), pose: pose, size: size, center: center, pixelScale: 1) else { return false }
        return r.x > 0 && r.y > 0 && r.x + r.w < Int(size.width) && r.y + r.h < Int(size.height)
    }

    let closed = K3DRenderer.box(K3DMesh(), apart: false)
    let apartBox = K3DRenderer.box(K3DMesh(), apart: true)
    func box(_ apart: Bool) -> (min: SIMD3<Float>, max: SIMD3<Float>) { apart ? apartBox : closed }

    @Test func theTurnsAreNotCut() {
        for angle in stride(from: 0.0, to: 360, by: 3) {
            // Row 3 (change 310): a drag tilts the closed device up to 35° each way, and the
            // turn after the release starts from that tilt.
            for tilt in [-35.0, -20, -6, 0, 6, 20, 35] {
                for lift in [0.0, 35, 70] {
                    let pose = K3DPose(angle: angle, lift: lift, tilt: tilt)
                    #expect(unclamped(pose, apart: false), "angle \(angle), tilt \(tilt), lift \(lift)")
                }
            }
        }
    }

    @Test func theTakeApartIsNotCut() {
        for angle in stride(from: 0.0, to: 360, by: 5) {
            for tilt in stride(from: -35.0, through: 35, by: 5) {
                let pose = K3DPose(angle: angle, tilt: tilt, ex: 1)
                #expect(unclamped(pose, apart: true), "angle \(angle), tilt \(tilt)")
            }
        }
    }

    /// CLA-119 (build 269): the top room is only the space up to the screen's visible top, so
    /// macOS never moves the grown window. The sides and the bottom keep their room.
    @Test func theTopRoomFitsUnderTheMenuBar() {
        let room = K3DRoom.extra
        #expect(K3DRoom.fit(room, windowTop: 500, visibleTop: 1000) == room)  // far from the top
        #expect(K3DRoom.fit(room, windowTop: 971, visibleTop: 1000).top == 29)
        #expect(K3DRoom.fit(room, windowTop: 1000, visibleTop: 1000).top == 0)  // at the menu bar
        #expect(K3DRoom.fit(room, windowTop: 1010, visibleTop: 1000).top == 0)
        #expect(K3DRoom.fit(room, windowTop: 0, visibleTop: -.infinity).top == 0)  // no screen
        let fit = K3DRoom.fit(room, windowTop: 990, visibleTop: 1000)
        #expect(fit.leading == room.leading && fit.trailing == room.trailing && fit.bottom == room.bottom)
    }

    /// CLA-122: a window that records the calls `K3DRoom.resize` makes.
    final class Recorder: NSWindow {
        var calls: [String] = []
        override func disableScreenUpdatesUntilFlush() {
            calls.append("hold")
            super.disableScreenUpdatesUntilFlush()
        }
        override func setFrame(_ frameRect: NSRect, display flag: Bool) {
            calls.append("frame")
            super.setFrame(frameRect, display: flag)
        }
    }

    func recorder() -> Recorder {
        _ = NSApplication.shared
        let window = Recorder(
            contentRect: NSRect(x: 300, y: 300, width: 400, height: 700), styleMask: .borderless, backing: .buffered, defer: true)
        window.calls = []
        return window
    }

    /// CLA-122 (build 279): the screen holds the old picture before the window's frame changes,
    /// when the room comes (a turn starts) and when it goes (the device rests on the front).
    @Test func theScreenHoldsBeforeTheWindowGrowsOrShrinks() {
        let room = K3DRoom.fit(K3DRoom.extra, windowTop: 1000, visibleTop: 1300)
        let grow = recorder()
        K3DRoom.resize(grow, from: EdgeInsets(), to: room)
        #expect(grow.calls == ["hold", "frame"])
        #expect(grow.frame == NSRect(x: 110, y: 190, width: 780, height: 1010))

        let shrink = recorder()
        shrink.setFrame(NSRect(x: 110, y: 190, width: 780, height: 1010), display: false)
        shrink.calls = []
        K3DRoom.resize(shrink, from: room, to: EdgeInsets())
        #expect(shrink.calls == ["hold", "frame"])
        #expect(shrink.frame == NSRect(x: 300, y: 300, width: 400, height: 700))
    }

    /// The device stays at the same point on the screen: each edge moves by its room.
    @Test func theFrameMovesEachEdgeByItsRoom() {
        let old = NSRect(x: 300, y: 300, width: 400, height: 700)
        let cut = EdgeInsets(top: 45, leading: 190, bottom: 110, trailing: 190)
        let new = K3DRoom.frame(old, from: EdgeInsets(), to: cut)
        #expect(new.maxY == old.maxY + 45)
        #expect(new.minY == old.minY - 110)
        #expect(new.minX == old.minX - 190)
        #expect(new.maxX == old.maxX + 190)
        #expect(K3DRoom.frame(new, from: cut, to: EdgeInsets()) == old)
    }
}
