import AppKit
import Foundation
import Testing

@testable import ClasifySkins

/// CLA-138 (build 330: for one frame as the first Cmd turn started, a second flat device front
/// showed 190 pt right and 124 pt down): the window's room gave the Metal view its new center
/// before its new size, and a frame was drawn at the new center in the old-size view.
@MainActor struct K3DRoomFrameTests {
    static let device = CGSize(width: K3DMesh.width, height: K3DMesh.height)
    /// Today's margins (`DeviceWindow.margin`), and the same with the room (`K3DRoom.extra`, top cut to 124).
    static let small = CGSize(width: device.width + 120, height: device.height + 95)
    static let large = CGSize(width: small.width + 380, height: small.height + 124 + 110)
    static let smallCenter = CGPoint(x: 60 + device.width / 2, y: 5 + device.height / 2)
    static let largeCenter = CGPoint(x: 250 + device.width / 2, y: 129 + device.height / 2)

    /// The room grows, and then goes at the turn's end: until the view has the size the new
    /// center is for, its frame is clear. It never draws the body at the new center in the old size.
    @Test func theOldSizeGetsAClearFrame() {
        for (bounds, expected, center) in [(Self.small, Self.large, Self.largeCenter), (Self.large, Self.small, Self.smallCenter)] {
            for waited in [0, 0.05, K3DLayerView.sizeWait - 0.001] {
                #expect(K3DLayerView.bodyCenter(center, bounds: bounds, expected: expected, waited: waited) == nil, "\(bounds) \(waited)")
            }
        }
    }

    /// The size the center is for, also as SwiftUI rounds it to whole pixels, draws the body there.
    @Test func theRightSizeDrawsTheBody() {
        #expect(K3DLayerView.bodyCenter(Self.largeCenter, bounds: Self.large, expected: Self.large, waited: 0) == Self.largeCenter)
        let rounded = CGSize(width: Self.large.width + 0.5, height: Self.large.height - 1)
        #expect(K3DLayerView.bodyCenter(Self.largeCenter, bounds: rounded, expected: Self.large, waited: 0) == Self.largeCenter)
        #expect(K3DLayerView.bodyCenter(Self.smallCenter, bounds: Self.small, expected: Self.small, waited: 0) == Self.smallCenter)
    }

    /// The safety net: a view that never gets its expected size still shows the body after
    /// `sizeWait`, with its center inside the view, so the device is never empty for a turn.
    @Test func aSizeThatNeverFitsStillShowsTheBody() {
        let late = K3DLayerView.sizeWait
        #expect(late <= 0.1)
        #expect(K3DLayerView.bodyCenter(Self.smallCenter, bounds: Self.small, expected: Self.large, waited: late) == Self.smallCenter)
        #expect(K3DLayerView.bodyCenter(Self.largeCenter, bounds: Self.small, expected: Self.large, waited: late) == Self.largeCenter)
        let outside = CGPoint(x: Self.small.width + 50, y: -20)
        #expect(K3DLayerView.bodyCenter(outside, bounds: Self.small, expected: Self.large, waited: late) == CGPoint(x: Self.small.width, y: 0))
    }

    /// A new expected size starts the wait; the same size again does not.
    @Test func onlyASizeChangeStartsTheWait() {
        let view = K3DLayerView()
        view.expectedSize = Self.small
        let first = view.sizeChanged
        #expect(Date.now.timeIntervalSince(first) < 1)
        view.expectedSize = Self.small
        #expect(view.sizeChanged == first)
        view.expectedSize = Self.large
        #expect(view.sizeChanged >= first)
    }
}
