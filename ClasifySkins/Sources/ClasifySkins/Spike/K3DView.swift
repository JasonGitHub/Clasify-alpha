#if os(macOS)  // CLA-202: Mac only (the 3D device). `WheelLook` and `spinBlack` moved to Shared/DeviceLook.swift.
import ClasifyCore
import MetalKit
import SwiftUI
import simd
import Synchronization

/// CLA-101: the About screen's K.3D.8 flip in true 3D. It is on in every build.
public enum K3DSpike {
    /// The device as it shows now, at 2x, with its covers, for the 3D front: its screen, and
    /// (CLA-119) the whole picture as the 2D layer. `time` pins the skin's loops to one frame;
    /// nil draws them as they are now. `wheel`: the wheel key the pointer is over or presses,
    /// so the picture is the face as it is at the swap. `black`: the color a spin shows, as the
    /// 2D device shows it (`spinBlack`), or nil for the state's own.
    @MainActor public static func snapshot(
        _ state: AppState, artwork: Artwork = .none, time: Double? = nil, wheel: WheelLook? = nil, black: Bool? = nil
    ) -> CGImage? {
        let wheel = wheel ?? .live
        // No drop shadow: the picture is the 2D layer of the 3D front, so its round corners stay clear.
        let skin = PocketSkin(state: state, interactive: false, pressed: wheel.pressed, hovered: wheel.hovered)
            .environment(\.artwork, artwork).environment(\.animationTime, time).environment(\.pocketDropShadow, false)
            .environment(\.spinBlack, black).environment(\.pocketSnapshot, true)
        let renderer = ImageRenderer(content: skin)
        renderer.scale = 2
        return renderer.cgImage
    }
}

/// CLA-119 (build 258: the top of the turned device cut off): the room the window gets round
/// today's margins while the 3D body shows, so the body's frame is never cut at any pose. One
/// size for every turn and the take-apart, so the window does not change size while the 3D
/// body shows. From the bounding box of the parts apart at any angle with tilt ±35°, plus a
/// little: 192 pt above, 184 at the sides, 107 below today's window
/// (`K3DRoomTests` checks every pose). At rest on the front the window has no extra room.
public enum K3DRoom {
    public static let extra = EdgeInsets(top: 200, leading: 190, bottom: 110, trailing: 190)

    /// CLA-119 (build 269): `room` with its top cut to the space between the window's top and the
    /// top of the screen's visible area (AppKit points, y up), never below 0. macOS moves a window
    /// whose top passes that line down, and the device would jump.
    public static func fit(_ room: EdgeInsets, windowTop: CGFloat, visibleTop: CGFloat) -> EdgeInsets {
        var fit = room
        fit.top = min(room.top, max(0, visibleTop - windowTop))
        return fit
    }
}

/// CLA-122 (build 279: the device 45 pt too high for one frame as an About drag started): the
/// window and the padded content change size in different frames now and then. The hosting view
/// centred the content in the window, so for that frame the device moved by (top - bottom) / 2 =
/// (200 - 110) / 2 = 45 pt. This layout is the window's root view. It places the content by the
/// room's own split instead of the centre: `fraction` = top / (top + bottom), and leading /
/// (leading + trailing). Then the device is at the same point on the screen whichever of the
/// window and the content has its new size. `fraction` is set as the room is picked, before
/// either changes, and kept as the room goes, so the shrink uses the same split.
///
/// Sizes: a proposal of a real size (the window's content size, as the hosting view lays out)
/// takes that size, so the content is placed in the whole window. A proposal with no size
/// (ideal), 0 (min) or infinity (max) gets the content's own size, so
/// `.windowResizability(.contentSize)` still sizes the window from the content.
public struct K3DRoomAnchor: Layout {
    /// The room's split. A reference, so a layout pass reads the new split even when it still
    /// has the old content.
    public final class Fraction: Sendable {
        private let value = Mutex(CGPoint(x: 0.5, y: 0.5))
        public init() {}
        public var point: CGPoint { value.withLock { $0 } }
        /// Sets the split from `room`. A room of 0 keeps the split it had.
        public func set(_ room: EdgeInsets) {
            let width = room.leading + room.trailing, height = room.top + room.bottom
            value.withLock { point in
                if width > 0 { point.x = room.leading / width }
                if height > 0 { point.y = room.top / height }
            }
        }
    }

    let fraction: Fraction

    public init(fraction: Fraction) { self.fraction = fraction }

    /// The content's top left in `bounds`. Smaller content moves in by its share of the space
    /// left; larger content moves out by its share of the overflow.
    static func origin(in bounds: CGRect, size: CGSize, fraction: CGPoint) -> CGPoint {
        CGPoint(
            x: bounds.minX + fraction.x * (bounds.width - size.width), y: bounds.minY + fraction.y * (bounds.height - size.height))
    }

    /// A real proposed length, or the content's length for none, 0 or infinity.
    static func length(_ proposed: CGFloat?, content: CGFloat) -> CGFloat {
        guard let proposed, proposed > 0, proposed.isFinite else { return content }
        return proposed
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first?.sizeThatFits(.unspecified) else { return .zero }
        return CGSize(
            width: Self.length(proposal.width, content: content.width), height: Self.length(proposal.height, content: content.height))
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let size = content.sizeThatFits(.unspecified)
        content.place(
            at: Self.origin(in: bounds, size: size, fraction: fraction.point), anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}

extension EnvironmentValues {
    /// CLA-122: the device window's room split, set by the skin as it picks the room.
    @Entry public var roomSplit: K3DRoomAnchor.Fraction? = nil
}

/// Shows `content`, the 2D device, while the front rests flat. While the device turns or shows
/// its back, the 3D body shows in its place, over the window's margins too, with the 2D
/// device's drop shadow cast from its outline. The two hand over by angle within 2° of the resting
/// front. A click on the 3D body calls `onTap`.
///
/// The Metal view stays mounted behind the 2D device, drawn at the pose the device rests in, so
/// its frame is ready when a turn starts. Until it has shown its first frame, the 2D device
/// stays opaque (build 167 showed the desktop through the device for 2 frames at each click:
/// the Metal view was made at the click and had not drawn yet).
public struct K3DFlipView<Content: View>: View {
    let flip: K3DFlip
    let black: Bool
    let margin: EdgeInsets
    let onTap: () -> Void
    /// CLA-119: true while the 3D body may show (the device is not at rest on the front), so the
    /// window needs `K3DRoom.extra`; false once the 2D device rests on the front again.
    let onRoom: (Bool) -> Void
    let content: Content
    /// Counts the turns that ended, so the body runs again and pauses the timeline.
    @State private var settled = 0
    /// The Metal view has shown its first frame.
    @State private var ready = false

    public init(
        flip: K3DFlip, black: Bool, margin: EdgeInsets, onTap: @escaping () -> Void, onRoom: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.flip = flip
        self.black = black
        self.margin = margin
        self.onTap = onTap
        self.onRoom = onRoom
        self.content = content()
    }

    public var body: some View {
        // The timeline runs only while the device turns. At rest on either side it pauses, and
        // the pose is the side it rests on. A new turn changes `flip`, which starts it again.
        // Reading `settled` makes the body run again when a turn ends.
        let resting = settled >= 0 && flip.pausesTimeline(at: .now)  // CLA-138: runs while held
        let needsRoom = !(settled >= 0 && flip.restsOnFront(at: .now))
        TimelineView(.animation(paused: resting)) { context in
            let date = resting ? Date.distantFuture : context.date
            let flat = flip.flatOpacity(at: date)
            let pose = flip.pose(at: date), look = flip.look(at: date), tilt = flip.tilt(at: date), ex = flip.ex(at: date)
            let black = flip.black(at: date, live: self.black)  // a spin shows the old color to 90°
            let flatDevice = content.environment(\.spinBlack, flip.blackOverride(at: date, live: self.black))
            K3DHandover(
                flat: flat, ready: ready, hidesUntilReady: flip.arriving, keepsInput: flip.takesInput(at: date), content: flatDevice
            ) { shown in
                // Never 0, as for `body3D`'s own opacity: a hidden Metal view does not draw.
                body3D(
                    angle: pose.angle, lift: pose.lift, tilt: tilt, ex: ex, scale: look.scale, black: black, shown: shown,
                    visible: flip.bodyShows(shown: shown), trail: K3DShadow.trail(flip, at: date))
                    .opacity(max(look.opacity, 0.001))
            }
        }
        // CLA-119: the window grows as a turn starts (the 2D device still covers the first 2°)
        // and shrinks once the 2D device rests on the front again.
        .onChange(of: needsRoom, initial: true) { _, needs in onRoom(needs) }
        .task(id: flip.ends) {
            // When the turn ends, run the body again so the timeline pauses. A hurried short
            // arrival (change 303) ends sooner, so its end starts a new wait.
            let left = flip.ends.timeIntervalSinceNow
            guard left > 0 else { return }
            try? await Task.sleep(for: .seconds(left + 0.05))
            settled += 1
        }
    }

    /// The 3D body and its shadow, under the 2D device that shows with opacity `shown`.
    private func body3D(
        angle: Double, lift: Double, tilt: Double, ex: Double, scale: Double, black: Bool, shown: Double, visible: Bool,
        trail: [K3DShadow.Trail]
    ) -> some View {
        let shows = shown < 1
        let size = PocketSkin.size
        let ready = $ready
        return ZStack {
            // The 2D device's drop shadow, from the 3D body's outline, only while the 3D body shows
            // (`shows`). Then the 2D device's own shadow is off (`K3DHandover`), so one shadow
            // shows at any time, with no step where they hand over (shadow option 1, Jason 17:30
            // JST 11-14). At rest on the front, the 2D device draws its own.
            // CLA-105 (Jason OK 17:54 JST 11-16): the shadow is the closed body's, so it fades out
            // as the device opens and back in as it closes. Open, there is none, as in the mock.
            let fade = K3DShadow.fade(ex: ex)
            if shows && fade > 0 { K3DShadow(angle: angle, lift: lift, tilt: tilt, black: black, trail: trail).scaleEffect(scale).opacity(fade) }
            K3DMetalView(
                angle: angle, lift: lift, tilt: tilt, ex: ex, scale: scale, black: black, screen: flip.screen, oldScreen: flip.oldScreen,
                center: CGPoint(x: margin.leading + size.width / 2, y: margin.top + size.height / 2),
                viewSize: CGSize(width: size.width + margin.leading + margin.trailing, height: size.height + margin.top + margin.bottom),
                onFirstFrame: { ready.wrappedValue = true })
                .padding(EdgeInsets(top: -margin.top, leading: -margin.leading, bottom: -margin.bottom, trailing: -margin.trailing))
                // At rest behind the opaque 2D device, the 3D body must not show round its edge
                // or through its shadow. 0.001, not 0: it rounds to nothing on screen, but the
                // view still draws and presents, so its first frame (and `ready`) comes. At 0,
                // SwiftUI may hide the view, and a hidden view does not draw.
                // CLA-138: during a Cmd turn's settle it is at 1 already, under the opaque 2D
                // device (`K3DFlip.bodyShows`), so its layer and a frame at the new size are on
                // screen before the 2D device goes. The shadow still follows `shows`.
                .opacity(visible ? 1 : 0.001)
        }
        // No fade or other animation when the shadow comes and goes: the timeline drives it.
        .transaction { $0.animation = nil }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // At rest behind the 2D device, a click must not reach the 3D body's tap.
        .allowsHitTesting(shows)
    }
}

/// The flat 2D device over the 3D body, `flat` its opacity. The 2D device fades as one flat
/// picture: without the compositing group, SwiftUI fades each of its layers on its own, so
/// the body and bezel show through the screen and labels and the whole device dims to grey
/// mid-fade (build 166). The 3D body stays mounted behind it; `body3D` gets the opacity the
/// 2D device shows with. Until the 3D body is `ready`, the 2D device stays opaque, except while
/// the device arrives: then neither shows until the 3D body has drawn (change 288).
struct K3DHandover<Flat: View, Body3D: View>: View {
    let flat: Double
    let ready: Bool
    /// The arrival (change 288): until the 3D body is ready, nothing shows, not the 2D device.
    var hidesUntilReady = false
    /// A color spin (changes 289 and 290) or the short arrival (change 303): the hidden 2D
    /// device still takes the wheel's clicks and drags. 0.001, not 0: a view at opacity 0 takes no clicks.
    var keepsInput = false
    let content: Flat
    @ViewBuilder let body3D: (Double) -> Body3D

    /// The 2D device's opacity: `flat`, or 1 while the 3D body has no frame to show.
    static func shown(flat: Double, ready: Bool, hidesUntilReady: Bool = false) -> Double {
        ready ? flat : hidesUntilReady ? 0 : 1
    }

    var body: some View {
        let shown = Self.shown(flat: flat, ready: ready, hidesUntilReady: hidesUntilReady)
        content
            // While the 3D body shows, it draws the one shadow: the 2D device's own is off.
            .environment(\.pocketDropShadow, shown >= 1)
            .compositingGroup()
            .opacity(keepsInput ? max(shown, 0.001) : shown)
            .allowsHitTesting(shown >= 1 || keepsInput)
            .background { body3D(shown) }
    }
}

/// The Metal view, drawn on demand: SwiftUI's timeline asks for each frame.
struct K3DMetalView: NSViewRepresentable {
    let angle: Double, lift: Double
    /// Change 307: the tilt toward the viewer while the About drag holds the device, in degrees.
    var tilt = 0.0
    /// CLA-105: how far apart the parts are, 0 closed to 1 apart.
    var ex = 0.0
    /// The body's size on screen about the device's center: 1, or less while it arrives.
    var scale = 1.0
    let black: Bool
    let screen: CGImage?
    var oldScreen: CGImage?
    /// The device's center in the view, in points from the top left.
    let center: CGPoint
    /// CLA-138: the view's size once SwiftUI lays it out for `center` (the device and its margins).
    let viewSize: CGSize
    /// Called once, on the main actor, when the view's first frame is on screen.
    let onFirstFrame: @MainActor () -> Void

    func makeNSView(context: Context) -> K3DLayerView {
        let view = K3DLayerView()
        view.firstFrame = onFirstFrame
        return view
    }

    func updateNSView(_ view: K3DLayerView, context: Context) {
        let pose = K3DPose(angle: angle, lift: lift, tilt: tilt, ex: ex, black: black, scale: scale)
        // Draw only when the picture changes: the view stays mounted while the device rests.
        guard pose != view.pose || screen !== view.screen || oldScreen !== view.oldScreen || center != view.deviceCenter
              || viewSize != view.expectedSize || !view.drewOnce else { return }
        view.expectedSize = viewSize
        view.pose = pose
        view.screen = screen
        view.oldScreen = oldScreen
        view.deviceCenter = center
        // CLA-132 (build 323: a pale box round the body in a fast Cmd drag): the frame is drawn
        // now, in this SwiftUI update, so it shows in the same transaction as `K3DShadow`'s cut
        // for this pose. Marked for display only, it was drawn in the next display pass: one
        // frame after the cut (frames: the cut of frame n was the body of frame n + 1). The
        // trail hid that in timed turns; a Cmd drag's held poses have no trail. Once per changed
        // input: the guard above returns when nothing drawn changed. When nothing could be drawn
        // yet (no size, or not the size `center` is for: CLA-138), the next display pass draws it.
        if !view.drawNow() { view.needsDisplay = true }
    }
}

/// What the renderer draws: the turn, the push back, and the color.
struct K3DPose: Equatable {
    var angle = 0.0, lift = 0.0
    /// Change 307: the pitch, in degrees (k3d_src3.js `tilt`).
    var tilt = 0.0
    /// CLA-105 Take apart: 0 closed, 1 apart. Above 0 the renderer draws the parts too.
    var ex = 0.0
    var black = false
    /// The size on screen about the device's center (change 288). It scales the projection only,
    /// so the light on the body does not change.
    var scale = 1.0
}

final class K3DLayerView: MTKView {
    var pose = K3DPose()
    var screen: CGImage?
    /// CLA-119: the old color's picture during a color spin.
    var oldScreen: CGImage?
    var deviceCenter = CGPoint.zero
    /// CLA-138 (build 330: a second, flat device front 190 pt right and 124 pt down for one frame
    /// as the first Cmd turn started): the window's room changes the margins, and SwiftUI calls
    /// `updateNSView` with the new `deviceCenter` before it gives this view its new size. A frame
    /// drawn then put the body at the new center in the old-size view. So until the view has the
    /// size `deviceCenter` is for, it draws a clear frame: no body, and not the old frame either
    /// (`contentsGravity` `.center` would show it moved by (bottom − top) / 2). The 2D device is
    /// opaque over the body then: in a Cmd turn's settle, at rest, and as the room goes at the
    /// end. The frame is cleared in the view's own drawable, so nothing fights SwiftUI's opacity.
    /// If the size never fits within `sizeWait`, the body is drawn at the real size anyway.
    var expectedSize = CGSize.zero {
        didSet { if expectedSize != oldValue { sizeChanged = .now } }
    }
    /// When `expectedSize` last changed.
    private(set) var sizeChanged = Date.distantPast
    /// CLA-138: the longest wait for the expected size; then the body is drawn in the real one.
    nonisolated static let sizeWait = 0.1
    /// The body's center for a frame of the view's real size `bounds`, or nil for a clear frame.
    /// A size within 1.5 pt of `expected` fits (SwiftUI rounds frames to whole pixels; the room
    /// changes the size by 100 pt or more). A size that still does not fit after `sizeWait`
    /// seconds gets the body anyway, its center kept inside `bounds`.
    nonisolated static func bodyCenter(_ center: CGPoint, bounds: CGSize, expected: CGSize, waited: Double) -> CGPoint? {
        let fits = abs(bounds.width - expected.width) < 1.5 && abs(bounds.height - expected.height) < 1.5
        if fits { return center }
        guard waited >= sizeWait else { return nil }
        return CGPoint(x: min(max(center.x, 0), bounds.width), y: min(max(center.y, 0), bounds.height))
    }
    /// A redraw at the end of `sizeWait` is set, for a view that does not get its size.
    private var waitsForSize = false
    /// Called once when the first frame is on screen, then cleared.
    var firstFrame: (@MainActor () -> Void)?
    /// A frame was drawn.
    private(set) var drewOnce = false

    init() {
        super.init(frame: .zero, device: K3DRenderer.shared?.device)
        isPaused = true
        enableSetNeedsDisplay = true
        colorPixelFormat = .bgra8Unorm  // the mock writes its colors as they are, like a canvas
        // CLA-119: the scene is drawn at 2x in the renderer's own targets, then filtered into
        // the drawable, so the drawable needs no samples and no depth.
        depthStencilPixelFormat = .invalid
        sampleCount = 1
        framebufferOnly = true
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer?.isOpaque = false
        // CLA-119 (build 269: pale strips beside the body edge-on in a color spin): the frame
        // shows in the same Core Animation commit as SwiftUI's views, so the body and
        // `K3DShadow` are at the same angle. Presented on its own, the drawable came about one
        // frame late: 4.3° in a 1.4 s spin, a cut 24 pt wider than the body at 90°.
        presentsWithTransaction = true
        // CLA-119 (build 269: the device 1.8x too big for one frame as a turn started): the window's
        // room makes this view larger. Its last frame must never be stretched to the new size.
        // A frame of the new size comes in the same transaction (`setFrameSize`).
        layer?.contentsGravity = .center
    }

    /// A new size draws a new frame, at the new size and center, in the same transaction.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        layer?.contentsGravity = .center
    }

    /// Clicks go through to SwiftUI, which turns the device back.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let renderer = K3DRenderer.shared else { return }
        let waited = Date.now.timeIntervalSince(sizeChanged)
        let center = Self.bodyCenter(deviceCenter, bounds: bounds.size, expected: expectedSize, waited: waited)
        if center == nil { redrawAfterSizeWait(waited) }
        if renderer.draw(in: self, center: center) {
            drewLast = true
            if center != nil { drewOnce = true }
        }
        preparePrintsIfNeeded(renderer)
    }

    /// CLA-138: the safety net. A clear frame waits for `setFrameSize`; if that never comes, this
    /// draws the body at the end of `sizeWait`, so the device is never empty for a whole turn.
    private func redrawAfterSizeWait(_ waited: Double) {
        guard !waitsForSize else { return }
        waitsForSize = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, Self.sizeWait - waited) + 0.005))
            guard let self else { return }
            self.waitsForSize = false
            self.needsDisplay = true
        }
    }

    /// The last `draw(_:)` drew a frame.
    private var drewLast = false

    /// Draws and presents one frame now, in the current transaction, through MTKView's own
    /// `draw()`: it gives the frame a new drawable and lets go of it after the draw, as in a
    /// display pass. Returns false when it drew nothing. It changes no SwiftUI state: the first
    /// frame's call and the prints' redraw come later, from their own tasks.
    func drawNow() -> Bool {
        drewLast = false
        draw()
        return drewLast
    }

    private func preparePrintsIfNeeded(_ renderer: K3DRenderer) {
        // CLA-105: apart before the prints are bound, the parts show plain. Draw again once
        // they are, as the device may rest and SwiftUI then asks for no new frame.
        if pose.ex > 0, !renderer.printsReady, !waitsForPrints {
            waitsForPrints = true
            let task = renderer.preparePrints()
            Task { [weak self] in
                await task.value
                guard let self else { return }
                self.waitsForPrints = false
                if renderer.printsReady { self.needsDisplay = true }
            }
        }
    }

    /// A redraw waits for the prints.
    private var waitsForPrints = false

    /// The renderer calls this when a frame drawn while `firstFrame` was set is on screen.
    func firstFrameShown() {
        let call = firstFrame
        firstFrame = nil
        call?()
    }
}

/// The mesh, textures and pipeline, made once.
@MainActor final class K3DRenderer {
    static let shared = K3DRenderer()
    /// CLA-196: the body this renderer draws. Only the classic shows in the app; another body is
    /// drawn closed, with no screen picture (`image(_:screen:size:scale:)` with no screen).
    let body: K3DBody
    static let samples = 4
    /// CLA-119: the scene is drawn at twice the screen's pixels and filtered down 2:1, as the
    /// mock's canvas (k3d_src3.js lines 7-9: the canvas at 2x, the browser scales it down).
    /// MSAA smooths only the outline; the shader's own edges, text and the steel need the
    /// extra pixels.
    nonisolated static let supersample = 2
    /// The mock's camera: the eye 2600 pt from the body's center, near 500, far 3000.
    static let distance: Float = 2600, near: Float = 500, far: Float = 3000

    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let depth: any MTLDepthStencilState
    /// Take apart: the window glass, blended over the parts with no depth write (the mock's pass 1).
    private let glassPipeline: any MTLRenderPipelineState
    private let glassDepth: any MTLDepthStencilState
    /// CLA-150 PR 4 (K.3D.12 item 5): the lamp's shadow map pass: each point's distance to the
    /// lamp, one sample, no culling (the mock's `shadowPass`).
    private let shadowPipeline: any MTLRenderPipelineState
    /// The lamp's map and its depth, made at the first apart frame and freed when the device is
    /// closed again (with the prints). About 16 MB; the depth lives in tile memory where it can.
    private var shadowMap: (color: any MTLTexture, depth: any MTLTexture)?
    /// The real shadow on the inside parts. Off: they keep their painted shadows (K.3D.11).
    /// For tests, and the fallback if the pass is too slow.
    var realShadows = true
    /// CLA-119: the 2:1 filter into the screen's pixels.
    private let downPipeline: any MTLRenderPipelineState
    private let vertices: any MTLBuffer, indices: any MTLBuffer
    /// CLA-119: the closed body's outer points, for the shadow's cut (`K3DShadow.cut`).
    let outerPoints: [SIMD3<Double>]
    /// The body's box in its own points, closed and with the take-apart parts at every `ex`.
    private let closedBox: (min: SIMD3<Float>, max: SIMD3<Float>), apartBox: (min: SIMD3<Float>, max: SIMD3<Float>)
    /// The 2x scene targets, kept while big enough.
    private var targets: (color: any MTLTexture, resolved: any MTLTexture, depth: any MTLTexture)?
    private let closedIndexCount: Int, indexCount: Int
    private let front: any MTLTexture, back: any MTLTexture
    private let linear: any MTLSamplerState, nearest: any MTLSamplerState
    /// The 2:1 filter's sampler: linear, no mipmaps.
    private let filterSampler: any MTLSamplerState
    /// The screen picture now in the front texture.
    private var frontScreen: CGImage?
    /// CLA-119, the mock's 2D layer (`t2`): the whole 2D device as `frontScreen` shows it, and
    /// whether that picture is Black. Nil: no picture, the front is 3D only.
    private let flat: any MTLTexture
    private var flatBlack: Bool?
    /// CLA-119: the old color's picture in a color spin (`K3DFlip.oldScreen`), the 2D device as it
    /// shows to 90°, so the spin starts from the 2D device with no step.
    private let oldFlat: any MTLTexture
    private var oldScreen: CGImage?, oldBlack: Bool?
    /// CLA-119: the 2D layer fades out over the first part of the take-apart (`ex` 0 to this).
    nonisolated static let exFade = 0.05
    /// The 2D picture's sampler: nearest when magnified, so at 0° each pixel is the picture's own.
    private let flatSampler: any MTLSamplerState
    /// CLA-105 B3: the parts' printed textures (`K3DPrints`: tl, tp, tq). Drawn off the main
    /// actor when the device starts to come apart (`preparePrints`); until they are ready the
    /// parts show their plain colors. About 70 MB with mipmaps, so they are released when the
    /// device is closed again.
    private var prints: [any MTLTexture]?
    private var printsTask: Task<Void, Never>?
    /// Whether a frame with the parts apart was drawn since the device was last closed.
    private var wasApart = false
    /// Whether the printed textures are bound to the take-apart frames.
    var printsReady: Bool { prints != nil }
    /// The front texture's bytes as bundled, read once: a turn's new screen goes into a copy.
    private let frontBytes: [UInt8]

    struct Uniforms {
        var mv: simd_float4x4
        var pr: simd_float4x4
        var blk: Float
        /// CLA-105: how far apart the parts are, and the pass (0, or 1 for the window glass).
        var ex: Float = 0
        var pass: Float = 0
        /// CLA-119: 1 when the front shows the 2D layer.
        var flat: Float = 0
        /// CLA-105 B3: 1 when the printed textures are bound; 0 draws each part's plain color.
        var prints: Float = 0
        /// CLA-150 PR 4: 1 when the lamp's map is bound for the inside parts; `shPass` 1 in the
        /// pass that draws it. `lvp`: the lamp's camera. `lp`: the lamp, and the map's far distance.
        var shadow: Float = 0
        var shPass: Float = 0
        var lvp = matrix_identity_float4x4
        var lp = SIMD4<Float>(0, 0, 0, 1)
    }

    /// The mock's shadow map: 2048 pixels square (SHN), read 1.5 pixels apart (uShT).
    nonisolated static let shadowSize = 2048
    nonisolated static let shadowTexel = 1.5 / Double(shadowSize)

    /// CLA-105: closed, only the closed device draws, in one pass with back faces culled, as
    /// before. Apart, every part draws; from `ex` .001 their back faces too, and from .0005 the
    /// window glass in a second pass (the mock's `draw`). CLA-150 PR 4: from .0005 too, the
    /// lamp's shadow map is drawn first. Closed, there is no shadow pass.
    nonisolated static func passes(ex: Float) -> (all: Bool, cull: Bool, glass: Bool, shadow: Bool) {
        (ex > 0, ex <= 0.001, ex > 0.0005, ex > 0.0005)
    }

    /// CLA-150 PR 4: the lamp's camera, as the mock's `shadowPass` with the lamp not locked to
    /// the device (`uLock` 0): from the lamp (`K3DShader`'s `lamp`) to the device's center, a
    /// perspective that holds the device (near d - 700, far d + 700, 500 pt round the center).
    /// The mock's matrix is WebGL's (depth -1 to 1); Metal's depth runs 0 to 1, so z is halved.
    /// `far`: the map's far distance, the mock's uShF.
    static func lampCamera(lift: Double) -> (lvp: simd_float4x4, lamp: SIMD3<Float>, far: Float) {
        let c = SIMD3<Double>(0, 0, -Double(distance) - lift)
        let l = SIMD3<Double>(-350, 800, Double(K3DMesh.depth / 2) + 1000 - Double(distance))
        let d = simd_length(c - l), f = (c - l) / d
        let up = abs(f.y) > 0.95 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
        let sx = simd_normalize(simd_cross(f, up)), uy = simd_cross(sx, f)
        let view = simd_double4x4(columns: (
            SIMD4(sx.x, uy.x, -f.x, 0), SIMD4(sx.y, uy.y, -f.y, 0), SIMD4(sx.z, uy.z, -f.z, 0),
            SIMD4(-simd_dot(sx, l), -simd_dot(uy, l), simd_dot(f, l), 1)))
        let n = max(50, d - 700), fa = d + 700, t = d / 500
        let lens = simd_double4x4(columns: (
            SIMD4(t, 0, 0, 0), SIMD4(0, t, 0, 0), SIMD4(0, 0, (fa + n) / (n - fa), -1), SIMD4(0, 0, 2 * fa * n / (n - fa), 0)))
        let half = simd_double4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 0.5, 0), SIMD4(0, 0, 0.5, 1)))
        let m = half * lens * view
        func float(_ v: SIMD4<Double>) -> SIMD4<Float> { SIMD4<Float>(Float(v.x), Float(v.y), Float(v.z), Float(v.w)) }
        let lvp = simd_float4x4(columns: (float(m.columns.0), float(m.columns.1), float(m.columns.2), float(m.columns.3)))
        return (lvp, SIMD3<Float>(Float(l.x), Float(l.y), Float(l.z)), Float(fa + 100))
    }

    init?(body: K3DBody = .classic) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? Self.makeLibrary(device, body: body),
              let pipeline = try? Self.makePipeline(library), let depth = Self.makeDepth(device, write: true),
              let glassPipeline = try? Self.makePipeline(library, blend: true), let glassDepth = Self.makeDepth(device, write: false),
              let downPipeline = try? Self.makeDownPipeline(library),
              let shadowPipeline = try? Self.makeShadowPipeline(library)
        else { return nil }
        let mesh = K3DMesh(body: body), size = body.textureSize
        guard let vertices = device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * 4, options: []),
              let indices = device.makeBuffer(bytes: mesh.indices, length: mesh.indices.count * 4, options: []),
              let frontBytes = K3DTextures.rgba(named: body.front),
              let front = Self.texture(device, queue, frontBytes, width: size.x, height: size.y),
              let back = Self.texture(
                device, queue, body == .classic ? K3DTextures.back(version: K3DTextures.version) : K3DTextures.rgba(named: body.back),
                width: size.x, height: size.y),
              let linear = Self.sampler(device, .linear), let nearest = Self.sampler(device, .nearest),
              let filterSampler = Self.filterSampler(device),
              let flat = Self.texture(device, queue, [UInt8](repeating: 0, count: size.x * size.y * 4), width: size.x, height: size.y),
              let oldFlat = Self.texture(device, queue, [UInt8](repeating: 0, count: size.x * size.y * 4), width: size.x, height: size.y),
              let flatSampler = Self.flatSampler(device)
        else { return nil }
        self.body = body
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.depth = depth
        self.glassPipeline = glassPipeline
        self.glassDepth = glassDepth
        self.downPipeline = downPipeline
        self.shadowPipeline = shadowPipeline
        closedBox = Self.box(mesh, apart: false)
        apartBox = Self.box(mesh, apart: true)
        self.vertices = vertices
        outerPoints = K3DShadow.outerPoints(mesh)
        self.indices = indices
        closedIndexCount = mesh.closedIndexCount
        indexCount = mesh.indices.count
        self.front = front
        self.frontBytes = frontBytes
        self.back = back
        self.linear = linear
        self.nearest = nearest
        self.filterSampler = filterSampler
        self.flat = flat
        self.oldFlat = oldFlat
        self.flatSampler = flatSampler
        // Warm-up: one frame of the back, off screen, when the view is mounted. In build 194 the
        // first turn repeated a frame near edge-on, where the back first shows. The likely cause
        // is first-use work for the back texture and its shader path, so it is done here.
        _ = image(K3DPose(angle: 180), screen: nil, size: PocketSkin.size, scale: 1)
    }

    /// The shaders and the pipeline. Internal so a test can check that the shaders compile.
    /// `blend`: the window glass pass, as the mock's blendFuncSeparate(SRC_ALPHA,
    /// ONE_MINUS_SRC_ALPHA, ONE, ONE_MINUS_SRC_ALPHA).
    static func makeLibrary(_ device: any MTLDevice, body: K3DBody = .classic) throws -> any MTLLibrary {
        try device.makeLibrary(source: K3DShader.shader(for: body), options: nil)
    }

    static func makePipeline(_ library: any MTLLibrary, blend: Bool = false) throws -> any MTLRenderPipelineState {
        let device = library.device
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "k3dVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "k3dFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        if blend {
            let color = descriptor.colorAttachments[0]!
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .sourceAlpha
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = samples
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// CLA-150 PR 4: the lamp's map pass: the same shaders (`shPass` 1), into one 32-bit float
    /// channel, one sample.
    static func makeShadowPipeline(_ library: any MTLLibrary) throws -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "k3dVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "k3dFragment")
        descriptor.colorAttachments[0].pixelFormat = .r32Float
        descriptor.depthAttachmentPixelFormat = .depth32Float
        return try library.device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// CLA-119: the 2:1 filter's pipeline: one sample, no depth.
    static func makeDownPipeline(_ library: any MTLLibrary) throws -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "k3dDownVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "k3dDownFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try library.device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// The box round the mesh's points, in the body's own points. Apart (`apart`), each part
    /// can be anywhere from its closed place to its place at `ex` 1, and the wheel's cable
    /// anywhere along its slide (K3DShader's vertex shader), so the box takes both ends of each.
    /// The shader's moves are straight lines, so the box holds every `ex` between.
    nonisolated static func box(_ mesh: K3DMesh, apart: Bool) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        let count = apart ? mesh.vertexCount : mesh.closedVertexCount
        for i in 0..<count {
            let e = i * K3DMesh.stride
            let p = K3DShader.turnsDrive(SIMD3(mesh.vertices[e], mesh.vertices[e + 1], mesh.vertices[e + 2]), part: mesh.vertices[e + 12])
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
            guard apart else { continue }
            let m = mesh.vertices[e + 11], pt = mesh.vertices[e + 12]
            let dz = K3DShader.apart[Int(min(max(pt + 0.5, 0), 9))] - K3DShader.apartBack
            let cable = pt > 2.5 && pt < 3.5 && ((m > 13.5 && m < 16.5) || (m > 40.5 && m < 41.5))
            var ends: [SIMD3<Float>] = [p + SIMD3<Float>(0, 0, dz)]
            if cable {
                ends.append(p + SIMD3<Float>(160, 0, -2))
                ends.append(p + SIMD3<Float>(160, 0, dz - 2))
            }
            for q in ends {
                lo = simd_min(lo, q)
                hi = simd_max(hi, q)
            }
        }
        return (lo, hi)
    }

    /// CLA-119: the frame's rect holds the parts' moves only from `ex` 0.002. Below it every
    /// part is less than 0.4 pt from its closed place (the most is the shell's move back, 192
    /// pt at `ex` 1), inside the closed rect's 2 px margin; the parts' own faces and the cable are
    /// hidden there (K3DShader). So a frame a hair apart is drawn in the same rect as the closed
    /// one, and looks the same (K3DApartRenderTests).
    nonisolated static func apartRect(ex: Double) -> Bool { ex > 0.002 }

    /// CLA-119: the part of a frame of `size` points the body can cover at the pose, in pixels
    /// at `pixelScale` from the top left: the box's 8 corners through the same matrices as the
    /// draw, 2 pixels out, on whole pixels, inside the frame. Nil when the body is off the frame.
    static func bodyRect(
        _ box: (min: SIMD3<Float>, max: SIMD3<Float>), pose: K3DPose, size: CGSize, center: CGPoint, pixelScale: Double
    ) -> (x: Int, y: Int, w: Int, h: Int)? {
        let m = projection(size: size, center: center, scale: pose.scale) * modelView(angle: pose.angle, lift: pose.lift, tilt: pose.tilt)
        var x0 = Double.infinity, y0 = Double.infinity, x1 = -Double.infinity, y1 = -Double.infinity
        for i in 0..<8 {
            let c = SIMD4<Float>(i & 1 == 0 ? box.min.x : box.max.x, i & 2 == 0 ? box.min.y : box.max.y, i & 4 == 0 ? box.min.z : box.max.z, 1)
            let q = m * c
            let x = (Double(q.x / q.w) + 1) / 2 * size.width, y = (1 - Double(q.y / q.w)) / 2 * size.height
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        }
        let wPx = Int((size.width * pixelScale).rounded()), hPx = Int((size.height * pixelScale).rounded())
        let l = max(0, Int((x0 * pixelScale).rounded(.down)) - 2), t = max(0, Int((y0 * pixelScale).rounded(.down)) - 2)
        let r = min(wPx, Int((x1 * pixelScale).rounded(.up)) + 2), b = min(hPx, Int((y1 * pixelScale).rounded(.up)) + 2)
        guard r > l && b > t else { return nil }
        return (l, t, r - l, b - t)
    }

    private static func makeDepth(_ device: any MTLDevice, write: Bool) -> (any MTLDepthStencilState)? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = write
        return device.makeDepthStencilState(descriptor: descriptor)
    }

    /// An RGBA texture with the bytes as they are (unorm, not sRGB), with mipmaps for the color,
    /// as the mock's power-of-two copies have.
    private static func texture(
        _ device: any MTLDevice, _ queue: any MTLCommandQueue, _ bytes: [UInt8]?,
        width: Int = K3DTextures.width, height: Int = K3DTextures.height
    ) -> (any MTLTexture)? {
        guard let bytes else { return nil }
        let w = width, h = height
        guard bytes.count == w * h * 4 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: true)
        descriptor.usage = [.shaderRead, .renderTarget]  // render target: so the blit can make the mipmaps
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        fill(texture, bytes, queue)
        return texture
    }

    /// Puts the bytes in level 0 and makes the smaller levels from them.
    private static func fill(_ texture: any MTLTexture, _ bytes: [UInt8], _ queue: any MTLCommandQueue) {
        let w = texture.width, h = texture.height
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
        guard let buffer = queue.makeCommandBuffer(), let blit = buffer.makeBlitCommandEncoder() else { return }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        buffer.commit()
    }

    private static func sampler(_ device: any MTLDevice, _ filter: MTLSamplerMinMagFilter) -> (any MTLSamplerState)? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = filter
        descriptor.magFilter = filter
        // The id sampler reads level 0 only; the color sampler blends levels, like the mock's tm.
        descriptor.mipFilter = filter == .linear ? .linear : .notMipmapped
        // CLA-119: as the mock's export (k3d_src3.js `up`): anisotropic filtering, up to 8, so the
        // front's print stays sharp at a steep angle.
        if filter == .linear { descriptor.maxAnisotropy = 8 }
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    private static func filterSampler(_ device: any MTLDevice) -> (any MTLSamplerState)? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    /// CLA-119: the 2D picture's sampler: nearest when magnified, linear with mipmaps when made
    /// smaller. Drawn at 2x and filtered 2:1, at 0° each pixel of the 2D picture covers 2 x 2
    /// samples, so the frame's pixel is the picture's pixel.
    private static func flatSampler(_ device: any MTLDevice) -> (any MTLSamplerState)? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .nearest
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    /// Puts a new screen picture in the front's LCD now, before a turn starts, so the turn's
    /// first frame has no texture work to do.
    func prepare(screen: CGImage) { show(screen: screen) }

    /// Puts a new screen picture in the front's LCD, and the whole picture in the 2D layer.
    private func show(screen: CGImage?) {
        guard screen !== frontScreen, body == .classic else { return }  // CLA-196: the screen is the classic's
        let picture = screen.flatMap(K3DTextures.picture)
        guard let bytes = K3DTextures.front(live: picture, base: frontBytes) else { return }
        Self.fill(front, bytes, queue)
        if let picture { Self.fill(flat, picture, queue) }
        flatBlack = picture.map(K3DTextures.isBlack)
        frontScreen = screen
    }

    /// Puts the old color's picture of a color spin in the 2D layer's second slot.
    func show(old screen: CGImage?) {
        guard screen !== oldScreen, body == .classic else { return }
        let picture = screen.flatMap(K3DTextures.picture)
        if let picture { Self.fill(oldFlat, picture, queue) }
        oldBlack = picture.map(K3DTextures.isBlack)
        oldScreen = screen
    }

    /// CLA-119: the 2D layer for the body's color, and how much it shows: 1 closed, 0 from
    /// `ex` 0.05 apart. Nil: no picture in that color, the front is 3D only.
    private func layer(_ pose: K3DPose) -> (texture: any MTLTexture, weight: Float)? {
        guard pose.ex < Self.exFade else { return nil }
        let weight = Float(1 - Self.smooth(pose.ex / Self.exFade))
        if flatBlack == pose.black { return (flat, weight) }
        if oldBlack == pose.black { return (oldFlat, weight) }
        return nil
    }

    nonisolated static func smooth(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    /// Draws one frame in the view. Returns false when it drew nothing.
    /// `center`: the body's center in the view, or nil for a clear frame (CLA-138).
    @discardableResult func draw(in view: K3DLayerView, center: CGPoint?) -> Bool {
        show(screen: view.screen)
        show(old: view.oldScreen)
        guard let drawable = view.currentDrawable, let buffer = queue.makeCommandBuffer(), view.bounds.width > 0,
              render(buffer, pose: view.pose, size: view.bounds.size, center: center,
                     pixelScale: Double(view.drawableSize.width / view.bounds.width), into: drawable.texture)
        else { return false }
        if view.firstFrame != nil, center != nil {  // CLA-138: a clear frame is not the body's first
            // Before the commit, so the handler cannot miss the presentation.
            drawable.addPresentedHandler(Self.presentedHandler(for: view))
        }
        // With `presentsWithTransaction`: commit, wait until the GPU has the work, then present in
        // the current transaction (Apple's order). The handler above still fires on presentation.
        buffer.commit()
        buffer.waitUntilScheduled()
        drawable.present()
        return true
    }

    /// The handler for the first frame's presentation. Metal calls it on its own queue
    /// (com.Metal.CompletionQueueDispatch), never on the main thread. A closure written inside
    /// `draw(in:)` is main-actor code in Swift 6, and the runtime stops the app when it runs off
    /// the main queue (build 168 crashed this way 0.3 s after launch). Made here, outside the
    /// main actor, the closure is @Sendable and nonisolated: it only starts a main-actor task.
    /// The view is a main-actor class, so it is Sendable and may be captured.
    nonisolated static func presentedHandler<Drawable>(for view: K3DLayerView) -> @Sendable (Drawable) -> Void {
        { [weak view] _ in Task { @MainActor in view?.firstFrameShown() } }
    }

    /// CLA-119: one frame of `size` points into `out` (one sample, `pixelScale` pixels per
    /// point). The scene is drawn at `supersample` times the pixels over the body's rect only,
    /// then filtered 2:1 into the same rect of `out`, on whole pixels. The rest is clear.
    private func render(
        _ buffer: any MTLCommandBuffer, pose: K3DPose, size: CGSize, center: CGPoint?, pixelScale: Double, into out: any MTLTexture
    ) -> Bool {
        let down = MTLRenderPassDescriptor()
        down.colorAttachments[0].texture = out
        down.colorAttachments[0].loadAction = .clear
        down.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        down.colorAttachments[0].storeAction = .store
        guard let center,
              let rect = Self.bodyRect(Self.apartRect(ex: pose.ex) ? apartBox : closedBox, pose: pose, size: size, center: center, pixelScale: pixelScale)
        else {
            buffer.makeRenderCommandEncoder(descriptor: down)?.endEncoding()
            return true
        }
        let k = Self.supersample, w = rect.w * k, h = rect.h * k
        guard let targets = sceneTargets(w, h) else { return false }
        let map = shadowPass(buffer, pose: pose)
        let scene = MTLRenderPassDescriptor()
        scene.colorAttachments[0].texture = targets.color
        scene.colorAttachments[0].resolveTexture = targets.resolved
        scene.colorAttachments[0].loadAction = .clear
        scene.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        scene.colorAttachments[0].storeAction = .multisampleResolve
        scene.depthAttachment.texture = targets.depth
        scene.depthAttachment.loadAction = .clear
        scene.depthAttachment.clearDepth = 1
        scene.depthAttachment.storeAction = .dontCare
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: scene) else { return false }
        // The rect's own camera: the same lens, cut to the rect, so the body is where it would be.
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(w), height: Double(h), znear: 0, zfar: 1))
        let points = CGSize(width: Double(rect.w) / pixelScale, height: Double(rect.h) / pixelScale)
        let shifted = CGPoint(x: center.x - Double(rect.x) / pixelScale, y: center.y - Double(rect.y) / pixelScale)
        encode(encoder, pose: pose, size: points, center: shifted, map: map)
        guard let filter = buffer.makeRenderCommandEncoder(descriptor: down) else { return false }
        filter.setViewport(MTLViewport(
            originX: Double(rect.x), originY: Double(rect.y), width: Double(rect.w), height: Double(rect.h), znear: 0, zfar: 1))
        filter.setRenderPipelineState(downPipeline)
        var scale = SIMD2<Float>(Float(w) / Float(targets.resolved.width), Float(h) / Float(targets.resolved.height))
        filter.setVertexBytes(&scale, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        filter.setFragmentTexture(targets.resolved, index: 0)
        filter.setFragmentSamplerState(filterSampler, index: 0)
        filter.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        filter.endEncoding()
        return true
    }

    /// CLA-150 PR 4: the lamp's map for this frame, drawn into `buffer` before the scene, or nil
    /// (closed, the real shadow off, or no memory for the map).
    private func shadowPass(_ buffer: any MTLCommandBuffer, pose: K3DPose) -> (any MTLTexture)? {
        guard realShadows, Self.passes(ex: Float(pose.ex)).shadow, let map = shadowTargets() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = map.color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = map.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let lamp = Self.lampCamera(lift: pose.lift)
        var uniforms = Uniforms(
            mv: Self.modelView(angle: pose.angle, lift: pose.lift, tilt: pose.tilt), pr: lamp.lvp, blk: pose.black ? 1 : 0, ex: Float(pose.ex))
        uniforms.shPass = 1
        uniforms.lvp = lamp.lvp
        uniforms.lp = SIMD4(lamp.lamp, lamp.far)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(Self.shadowSize), height: Double(Self.shadowSize), znear: 0, zfar: 1))
        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setDepthStencilState(depth)
        encoder.setCullMode(.none)
        bind(encoder, &uniforms, flat: flat, prints: nil, map: nil)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indices, indexBufferOffset: 0)
        encoder.endEncoding()
        return map.color
    }

    /// The lamp's map and its depth, made once and kept until the device is closed.
    private func shadowTargets() -> (color: any MTLTexture, depth: any MTLTexture)? {
        if let shadowMap { return shadowMap }
        let n = Self.shadowSize
        let color = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: n, height: n, mipmapped: false)
        color.usage = [.renderTarget, .shaderRead]
        color.storageMode = .private
        let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: n, height: n, mipmapped: false)
        depth.usage = .renderTarget
        depth.storageMode = device.supportsFamily(.apple7) ? .memoryless : .private
        guard let c = device.makeTexture(descriptor: color), let d = device.makeTexture(descriptor: depth) else { return nil }
        shadowMap = (c, d)
        return shadowMap
    }

    /// Whether the lamp's map is made now. For tests.
    var hasShadowMap: Bool { shadowMap != nil }

    /// The 2x targets, made again only when they are too small. The MSAA color and the depth
    /// live in tile memory where the GPU can (Apple silicon); elsewhere they are private.
    private func sceneTargets(_ w: Int, _ h: Int) -> (color: any MTLTexture, resolved: any MTLTexture, depth: any MTLTexture)? {
        if let t = targets, t.resolved.width >= w, t.resolved.height >= h { return t }
        let tile = device.supportsFamily(.apple7)
        func target(_ format: MTLPixelFormat, samples: Int, read: Bool) -> (any MTLTexture)? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            descriptor.textureType = samples > 1 ? .type2DMultisample : .type2D
            descriptor.sampleCount = samples
            descriptor.usage = read ? [.renderTarget, .shaderRead] : .renderTarget
            descriptor.storageMode = read ? .private : (tile ? .memoryless : .private)
            return device.makeTexture(descriptor: descriptor)
        }
        guard let color = target(.bgra8Unorm, samples: Self.samples, read: false),
              let resolved = target(.bgra8Unorm, samples: 1, read: true),
              let depth = target(.depth32Float, samples: Self.samples, read: false)
        else { return nil }
        targets = (color, resolved, depth)
        return targets
    }

    /// Starts drawing the printed textures off the main actor, if they are not ready or on the
    /// way. Call it when a take-apart may start (the press-and-hold, or About opening); the first
    /// apart frame calls it too. The task ends when they are bound.
    @discardableResult func preparePrints() -> Task<Void, Never> {
        if let printsTask { return printsTask }
        let task = Task { [weak self] in
            let bytes = await Task.detached(priority: .userInitiated) { K3DPrints.all() }.value
            guard !Task.isCancelled, let self, let bytes else { return }
            self.prints = self.printTextures(bytes)
        }
        printsTask = task
        return task
    }

    /// CLA-105 D: the first frame with the parts apart costs time (the parts' shader path). One
    /// small frame off screen, at the start of the press-and-hold, takes that cost before the
    /// device opens. It does not count as apart, so it releases nothing. It is committed and not
    /// waited for, so the press goes on at once; once per renderer is enough.
    func warmApart() {
        guard !warmed else { return }
        let was = wasApart
        defer { wasApart = was }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .private
        guard let target = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer(),
              render(buffer, pose: K3DPose(angle: 305, tilt: 20, ex: 0.1), size: CGSize(width: 64, height: 64),
                     center: CGPoint(x: 32, y: 32), pixelScale: 1, into: target)
        else { return }
        buffer.commit()
        warmed = true
        if !was { shadowMap = nil }  // the buffer keeps its own hold on the map until it is done
    }

    /// The warm-up frame was sent.
    private(set) var warmed = false

    /// Frees the printed textures: the device is closed again.
    func releasePrints() {
        printsTask?.cancel()
        printsTask = nil
        prints = nil
    }

    /// Draws the printed textures now, on the caller's thread. For the tests' design frames.
    func makePrintsNow() {
        guard prints == nil, let bytes = K3DPrints.all() else { return }
        printsTask?.cancel()
        printsTask = Task {}
        prints = printTextures(bytes)
    }

    /// The main actor's time for the last bind: the level-0 copies and the mipmap commands (the
    /// GPU makes the mipmaps after it). The tests print it to the CI log.
    private(set) var printsBindTime: Duration?

    private func printTextures(_ bytes: K3DPrints.Bytes) -> [any MTLTexture]? {
        let clock = ContinuousClock()
        let start = clock.now
        defer { printsBindTime = clock.now - start }
        let label = Self.texture(device, queue, bytes.label, width: K3DPrints.labelSize, height: K3DPrints.labelSize)
        let board = Self.texture(device, queue, bytes.board, width: K3DPrints.boardSize.w, height: K3DPrints.boardSize.h)
        let parts = Self.texture(device, queue, bytes.parts, width: K3DPrints.partsSize, height: K3DPrints.partsSize)
        guard let label, let board, let parts else { return nil }
        return [label, board, parts]
    }

    /// The prints for this frame: apart, they are bound once ready (and asked for if not on the
    /// way); closed again after a take-apart, they are released.
    private func printsFor(ex: Double) -> [any MTLTexture]? {
        if ex > 0 {
            wasApart = true
            if prints == nil { preparePrints() }
            return prints
        }
        if wasApart {
            wasApart = false
            releasePrints()
            shadowMap = nil
        }
        return nil
    }

    private func encode(_ encoder: any MTLRenderCommandEncoder, pose: K3DPose, size: CGSize, center: CGPoint, map: (any MTLTexture)?) {
        var uniforms = Uniforms(
            mv: Self.modelView(angle: pose.angle, lift: pose.lift, tilt: pose.tilt),
            pr: Self.projection(size: size, center: center, scale: pose.scale), blk: pose.black ? 1 : 0,
            ex: Float(pose.ex))
        // The 2D layer shows in the body's own color: in the first half of a color spin the 3D
        // body is the old color, and shows the old color's picture. It fades as the parts move apart.
        let layer = self.layer(pose)
        uniforms.flat = layer?.weight ?? 0
        let prints = printsFor(ex: pose.ex)
        uniforms.prints = prints == nil ? 0 : 1
        if map != nil {
            let lamp = Self.lampCamera(lift: pose.lift)
            uniforms.shadow = 1
            uniforms.lvp = lamp.lvp
            uniforms.lp = SIMD4(lamp.lamp, lamp.far)
        }
        let passes = Self.passes(ex: uniforms.ex)
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depth)
        // As the mock: closed, only front faces draw. Metal's clip space has y up, as WebGL's, so
        // the mock's counterclockwise front faces are counterclockwise here too.
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(passes.cull ? .back : .none)
        bind(encoder, &uniforms, flat: layer?.texture ?? flat, prints: prints, map: map)
        let count = passes.all ? indexCount : closedIndexCount
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32, indexBuffer: indices, indexBufferOffset: 0)
        if passes.glass {
            uniforms.pass = 1
            encoder.setRenderPipelineState(glassPipeline)
            encoder.setDepthStencilState(glassDepth)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32, indexBuffer: indices, indexBufferOffset: 0)
        }
        encoder.endEncoding()
    }

    /// The buffers, textures and samplers both the scene and the lamp's map pass read.
    private func bind(_ encoder: any MTLRenderCommandEncoder, _ uniforms: inout Uniforms, flat: any MTLTexture, prints: [any MTLTexture]?, map: (any MTLTexture)?) {
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(front, index: 0)
        encoder.setFragmentTexture(back, index: 1)
        encoder.setFragmentSamplerState(linear, index: 0)
        encoder.setFragmentSamplerState(nearest, index: 1)
        encoder.setFragmentTexture(flat, index: 3)
        encoder.setFragmentSamplerState(flatSampler, index: 2)
        // Closed, no part reads the prints: the front texture stands in for them. The lamp's
        // map pass and a frame with no map do not read the map: the front stands in for it too.
        for index in 0..<3 { encoder.setFragmentTexture(prints?[index] ?? front, index: 4 + index) }
        encoder.setFragmentTexture(map ?? front, index: 7)
    }

    /// One frame drawn off screen, `size` points at `scale` pixels per point, the device
    /// centered: for tests. Its pixels are premultiplied BGRA rows from the top.
    func image(_ pose: K3DPose, screen: CGImage?, old: CGImage? = nil, size: CGSize, scale: Int) -> [UInt8]? {
        show(screen: screen)
        show(old: old)
        let w = Int(size.width) * scale, h = Int(size.height) * scale
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .managed
        guard let resolved = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer(),
              render(buffer, pose: pose, size: size, center: CGPoint(x: size.width / 2, y: size.height / 2),
                     pixelScale: Double(scale), into: resolved)
        else { return nil }
        guard let blit = buffer.makeBlitCommandEncoder() else { return nil }
        blit.synchronize(resource: resolved)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var out = [UInt8](repeating: 0, count: w * h * 4)
        resolved.getBytes(&out, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return out
    }

    /// The mock's M = Translate(0, 0, -2600 - lift) * RotX(tilt) * RotY(angle) (k3d_src3.js
    /// `draw`). The tilt is 0 except while the About drag holds the device (change 307).
    static func modelView(angle: Double, lift: Double, tilt: Double = 0) -> simd_float4x4 {
        let a = Float(angle * .pi / 180), ca = cos(a), sa = sin(a)
        let b = Float(tilt * .pi / 180), cb = cos(b), sb = sin(b)
        return simd_float4x4(columns: (
            SIMD4(ca, sb * sa, -cb * sa, 0), SIMD4(0, cb, sb, 0), SIMD4(sa, -sb * ca, cb * ca, 0),
            SIMD4(0, 0, -distance - Float(lift), 1)))
    }

    /// A perspective with the mock's camera, scaled so the flat front (34 pt nearer than the
    /// center) shows at 1 pt per pt, the size of the 2D device. The lens shifts so the device's
    /// center falls on `center`, which is not the view's center. Metal's depth runs 0 to 1.
    static func projection(size: CGSize, center: CGPoint, scale: Double = 1) -> simd_float4x4 {
        let w = Float(max(size.width, 1)), h = Float(max(size.height, 1))
        let d0 = distance - Float(K3DMesh.depth / 2)
        let fx = 2 * d0 / w * Float(scale), fy = 2 * d0 / h * Float(scale)  // scales about the lens shift: the device's center
        let sx = (Float(center.x) - w / 2) / (w / 2), sy = -(Float(center.y) - h / 2) / (h / 2)
        let n = near, f = far
        return simd_float4x4(columns: (
            SIMD4(fx, 0, 0, 0), SIMD4(0, fy, 0, 0), SIMD4(-sx, -sy, f / (n - f), -1), SIMD4(0, 0, f * n / (n - f), 0)))
    }
}
#endif
