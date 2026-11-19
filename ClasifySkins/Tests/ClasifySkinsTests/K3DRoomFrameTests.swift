import AppKit
import Testing

@testable import ClasifySkins

/// CLA-138 (build 330: for one frame as the first Cmd turn started, a second flat device front
/// showed 190 pt right and 124 pt down): the window's room gave the Metal view its new center
/// before its new size, and a frame was drawn at the new center in the old-size view.
@MainActor struct K3DRoomFrameTests {
    static let device = CGSize(width: K3DMesh.width, height: K3DMesh.height)
    /// Today's margins (`DeviceWindow.margin`) and the same with the room (`K3DRoom.extra`, top cut to 124).
    static let small = CGSize(width: device.width + 120, height: device.height + 95)
    static let large = CGSize(width: small.width + 380, height: small.height + 124 + 110)

    /// SwiftUI's whole-pixel rounding still fits; the room's change does not.
    @Test func onlyTheSizeTheCenterIsForFits() {
        #expect(K3DLayerView.fits(Self.large, Self.large))
        #expect(K3DLayerView.fits(CGSize(width: Self.large.width + 0.5, height: Self.large.height - 1), Self.large))
        #expect(!K3DLayerView.fits(Self.small, Self.large))
        #expect(!K3DLayerView.fits(Self.large, Self.small))
        #expect(!K3DLayerView.fits(CGSize(width: Self.large.width, height: Self.large.height - 110), Self.large))
    }

    /// The room grows: the view still has its old size. It hides and draws nothing, so no frame
    /// puts the body at the new center in the old size. Once SwiftUI gives it the new size, it
    /// may draw. The same holds as the room goes at the end of the turn.
    @Test func noFrameIsDrawnUntilTheViewHasItsNewSize() {
        for (from, to) in [(Self.small, Self.large), (Self.large, Self.small)] {
            let view = K3DLayerView()
            view.setFrameSize(from)
            view.expectedSize = from
            #expect(view.sizeFits && view.shows)
            view.expectedSize = to
            #expect(!view.sizeFits)
            #expect(!view.shows, "the layer hides from the size change")
            #expect(!view.drawNow(), "no frame at the new center in the old size")
            #expect(!view.drewOnce)
            view.setFrameSize(to)
            #expect(view.sizeFits, "with its new size the view draws, and the frame shows it again")
        }
    }

    /// A change that is not a size change (a new pose or center in the same room) never hides
    /// the layer: a turn's frames all show.
    @Test func theSameSizeKeepsTheLayerShown() {
        let view = K3DLayerView()
        view.setFrameSize(Self.large)
        view.expectedSize = Self.large
        view.deviceCenter = CGPoint(x: 250 + Self.device.width / 2, y: 129 + Self.device.height / 2)
        view.expectedSize = Self.large
        #expect(view.shows)
    }
}
