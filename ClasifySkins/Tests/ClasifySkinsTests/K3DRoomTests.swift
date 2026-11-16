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

    /// The device's top left on the screen (AppKit: y up), for a window frame and the room the
    /// content has, as `K3DRoomAnchor` places the content in the window less the margin.
    func device(window: CGRect, room: EdgeInsets, split: CGPoint) -> CGPoint {
        let m = Self.margin, device = PocketSkin.size
        let bounds = CGRect(x: 0, y: 0, width: window.width - m.leading - m.trailing, height: window.height - m.top - m.bottom)
        let size = CGSize(width: device.width + room.leading + room.trailing, height: device.height + room.top + room.bottom)
        let origin = K3DRoomAnchor.origin(in: bounds, size: size, fraction: split)
        return CGPoint(x: window.minX + m.leading + origin.x + room.leading, y: window.maxY - m.top - origin.y - room.top)
    }

    /// CLA-122 (build 279: the device 45 pt too high for one frame as an About drag started):
    /// the device stays at the same point on the screen whichever of the window and the content
    /// has its new size, as the room comes and as it goes, with the full room and with a top cut
    /// under the menu bar.
    @Test func theDeviceStaysWhileTheWindowAndTheContentChangeApart() {
        let m = Self.margin, device = PocketSkin.size
        let small = CGRect(x: 300, y: 200, width: device.width + m.leading + m.trailing, height: device.height + m.top + m.bottom)
        for visibleTop in [small.maxY + 400, small.maxY + 45, small.maxY] {
            let room = K3DRoom.fit(K3DRoom.extra, windowTop: small.maxY, visibleTop: visibleTop)
            let big = CGRect(
                x: small.minX - room.leading, y: small.minY - room.bottom,
                width: small.width + room.leading + room.trailing, height: small.height + room.top + room.bottom)
            let split = K3DRoomAnchor.Fraction()
            split.set(room)
            split.set(EdgeInsets())  // the room going keeps the split
            let at = device(window: small, room: EdgeInsets(), split: split.point)
            for window in [small, big] {
                for content in [EdgeInsets(), room] {
                    let now = device(window: window, room: content, split: split.point)
                    #expect(abs(now.x - at.x) < 0.001 && abs(now.y - at.y) < 0.001, "top room \(room.top)")
                }
            }
        }
    }

    /// The old centring moved the device 45 pt up for the frame with the new window and the old
    /// content, as Jason's clip showed.
    @Test func centringMovedTheDevice45Points() {
        let m = Self.margin, device = PocketSkin.size, room = K3DRoom.extra
        let small = CGRect(x: 300, y: 200, width: device.width + m.leading + m.trailing, height: device.height + m.top + m.bottom)
        let big = CGRect(
            x: small.minX - room.leading, y: small.minY - room.bottom,
            width: small.width + room.leading + room.trailing, height: small.height + room.top + room.bottom)
        let centre = CGPoint(x: 0.5, y: 0.5)
        let before = device(window: small, room: EdgeInsets(), split: centre)
        let jump = device(window: big, room: EdgeInsets(), split: centre)
        #expect(jump.y - before.y == 45)  // up, in AppKit's y
        #expect(jump.x == before.x)
    }
}
