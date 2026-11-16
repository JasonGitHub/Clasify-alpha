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

    /// CLA-122: finds the device's frame in its window.
    @MainActor final class ProbeBox {
        var view: NSView?
    }

    struct Probe: NSViewRepresentable {
        let box: ProbeBox
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            box.view = view
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {}
    }

    /// The app's tree: `DeviceRoot` (the anchor round the content and the margin) and the skin's
    /// `.padding(room)` round the device. `split` nil leaves the anchor out, as before CLA-122.
    struct Tree: View {
        let room: EdgeInsets
        let split: K3DRoomAnchor.Fraction?
        let box: ProbeBox

        var body: some View {
            let content = Color.gray.frame(width: PocketSkin.size.width, height: PocketSkin.size.height)
                .background(Probe(box: box))
                .padding(room)
                .padding(K3DRoomTests.margin)
            if let split {
                K3DRoomAnchor(fraction: split) { content }
            } else {
                content
            }
        }
    }

    /// The window's frame (AppKit, y up) with each edge moved out by `room`.
    func grown(_ frame: CGRect, by room: EdgeInsets) -> CGRect {
        CGRect(
            x: frame.minX - room.leading, y: frame.minY - room.bottom,
            width: frame.width + room.leading + room.trailing, height: frame.height + room.top + room.bottom)
    }

    /// Lays the tree out in a window with frame `window` (a hosting view that does not size the
    /// window), and returns the device's top left on the screen (AppKit: y up) and the tree's
    /// fitting size.
    func layOut(window frame: CGRect, room: EdgeInsets, split: K3DRoomAnchor.Fraction?) -> (top: CGPoint, fitting: CGSize) {
        _ = NSApplication.shared
        let box = ProbeBox()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: frame.size), styleMask: .borderless, backing: .buffered, defer: true)
        let host = NSHostingView(rootView: Tree(room: room, split: split, box: box))
        host.sizingOptions = []
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.layoutSubtreeIfNeeded()
        guard let view = box.view else { return (CGPoint(x: -1, y: -1), .zero) }
        let rect = view.convert(view.bounds, to: nil)
        // The size the window gets from the content (`.contentSize`), from a hosting view that
        // sizes itself as the app's does.
        let fitting = NSHostingView(rootView: Tree(room: room, split: split, box: ProbeBox())).fittingSize
        return (CGPoint(x: frame.minX + rect.minX, y: frame.minY + rect.maxY), fitting)
    }

    var small: CGRect {
        let m = Self.margin, device = PocketSkin.size
        return CGRect(x: 300, y: 200, width: device.width + m.leading + m.trailing, height: device.height + m.top + m.bottom)
    }

    /// CLA-122 (build 279: the device 45 pt too high for one frame as an About drag started):
    /// through the real SwiftUI tree in a hosting view, the device stays at the same point on
    /// the screen whichever of the window and the content has its new size, as the room comes
    /// and as it goes, with the full room, a top cut under the menu bar and no top room. The
    /// fitting size, which `.windowResizability(.contentSize)` uses, is the content's.
    @Test func theDeviceStaysWhileTheWindowAndTheContentChangeApart() {
        for visibleTop in [small.maxY + 400, small.maxY + 45, small.maxY] {
            let room = K3DRoom.fit(K3DRoom.extra, windowTop: small.maxY, visibleTop: visibleTop)
            let big = grown(small, by: room)
            let split = K3DRoomAnchor.Fraction()
            split.set(room)
            split.set(EdgeInsets())  // the room going keeps the split
            let at = layOut(window: small, room: EdgeInsets(), split: split).top
            for window in [small, big] {
                for content in [EdgeInsets(), room] {
                    let now = layOut(window: window, room: content, split: split)
                    #expect(abs(now.top.x - at.x) < 0.5 && abs(now.top.y - at.y) < 0.5, "top room \(room.top), window \(window.size), content \(content.top)")
                    let fits = layOut(window: window, room: content, split: nil).fitting
                    #expect(now.fitting == fits)
                    #expect(now.fitting == grown(small, by: content).size)
                }
            }
        }
    }

    /// The same tree with no anchor: the hosting view centres the old content in the new window,
    /// and the device moves 45 pt up, as Jason's clip showed. This is the defect CLA-122 fixes.
    @Test func withNoAnchorTheDeviceJumps45Points() {
        let big = grown(small, by: K3DRoom.extra)
        let before = layOut(window: small, room: EdgeInsets(), split: nil).top
        let jump = layOut(window: big, room: EdgeInsets(), split: nil).top
        #expect(abs(jump.y - before.y - 45) < 0.5)  // up, in AppKit's y
        #expect(abs(jump.x - before.x) < 0.5)
    }
}
