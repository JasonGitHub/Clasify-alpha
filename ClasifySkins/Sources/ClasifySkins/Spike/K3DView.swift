import ClasifyCore
import MetalKit
import SwiftUI
import simd

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
            .environment(\.spinBlack, black)
        let renderer = ImageRenderer(content: skin)
        renderer.scale = 2
        return renderer.cgImage
    }
}

/// CLA-119: the wheel key the pointer is over and the key pressed, as the app's 2D device shows
/// them now, so the 3D front's picture (`K3DSpike.snapshot`) is the face as it is at the swap.
/// Only the app's own full-size device writes `live`; nothing observes it.
@MainActor public final class WheelLook {
    public static let live = WheelLook()
    var hovered: ClickWheel.Zone?
    var pressed: ClickWheel.Zone?
    public init() {}

    /// CLA-119 (build 258: the centre button grey for the whole color spin): the live look with
    /// no key pressed. A color spin starts on the centre button's press, and the 2D device lets
    /// it go a moment later, so the spin's 3D front shows the key let go. The hover stays.
    public static var released: WheelLook {
        let look = WheelLook()
        look.hovered = live.hovered
        return look
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
        let resting = settled >= 0 && flip.isResting(at: .now)
        let needsRoom = !(settled >= 0 && flip.restsOnFront(at: .now))
        TimelineView(.animation(paused: resting)) { context in
            let date = resting ? Date.distantFuture : context.date
            let flat = flip.flatOpacity(at: date)
            let pose = flip.pose(at: date), look = flip.look(at: date), tilt = flip.tilt(at: date), ex = flip.ex(at: date)
            let black = flip.black(at: date, live: self.black)  // a spin shows the old color to 180°
            let flatDevice = content.environment(\.spinBlack, flip.blackOverride(at: date, live: self.black))
            K3DHandover(
                flat: flat, ready: ready, hidesUntilReady: flip.arriving, keepsInput: flip.takesInput(at: date), content: flatDevice
            ) { shown in
                // Never 0, as for `body3D`'s own opacity: a hidden Metal view does not draw.
                body3D(angle: pose.angle, lift: pose.lift, tilt: tilt, ex: ex, scale: look.scale, black: black, shown: shown)
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
    private func body3D(angle: Double, lift: Double, tilt: Double, ex: Double, scale: Double, black: Bool, shown: Double) -> some View {
        let shows = shown < 1
        let size = PocketSkin.size
        let ready = $ready
        return ZStack {
            // The 2D device's drop shadow, from the 3D body's outline, only while the 3D body shows
            // (`shows`). Then the 2D device's own shadow is off (`K3DHandover`), so one shadow
            // shows at any time, with no step where they hand over (shadow option 1, Jason 17:30
            // JST 11-14). At rest on the front, the 2D device draws its own.
            if shows { K3DShadow(angle: angle, lift: lift, tilt: tilt, black: black).scaleEffect(scale) }
            K3DMetalView(
                angle: angle, lift: lift, tilt: tilt, ex: ex, scale: scale, black: black, screen: flip.screen, oldScreen: flip.oldScreen,
                center: CGPoint(x: margin.leading + size.width / 2, y: margin.top + size.height / 2),
                onFirstFrame: { ready.wrappedValue = true })
                .padding(EdgeInsets(top: -margin.top, leading: -margin.leading, bottom: -margin.bottom, trailing: -margin.trailing))
                // At rest behind the opaque 2D device, the 3D body must not show round its edge
                // or through its shadow. 0.001, not 0: it rounds to nothing on screen, but the
                // view still draws and presents, so its first frame (and `ready`) comes. At 0,
                // SwiftUI may hide the view, and a hidden view does not draw.
                .opacity(shows ? 1 : 0.001)
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
        guard pose != view.pose || screen !== view.screen || oldScreen !== view.oldScreen || center != view.deviceCenter || !view.drewOnce else { return }
        view.pose = pose
        view.screen = screen
        view.oldScreen = oldScreen
        view.deviceCenter = center
        view.needsDisplay = true
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
        if renderer.draw(in: self) { drewOnce = true }
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
    private let front: any MTLTexture, back: any MTLTexture, steel: any MTLTexture
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
    /// shows to 180°, so the spin starts from the 2D device with no step.
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
    }

    /// CLA-105: closed, only the closed device draws, in one pass with back faces culled, as
    /// before. Apart, every part draws; from `ex` .001 their back faces too, and from .0005 the
    /// window glass in a second pass (the mock's `draw`).
    nonisolated static func passes(ex: Float) -> (all: Bool, cull: Bool, glass: Bool) {
        (ex > 0, ex <= 0.001, ex > 0.0005)
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? Self.makeLibrary(device),
              let pipeline = try? Self.makePipeline(library), let depth = Self.makeDepth(device, write: true),
              let glassPipeline = try? Self.makePipeline(library, blend: true), let glassDepth = Self.makeDepth(device, write: false),
              let downPipeline = try? Self.makeDownPipeline(library)
        else { return nil }
        let mesh = K3DMesh()
        guard let vertices = device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * 4, options: []),
              let indices = device.makeBuffer(bytes: mesh.indices, length: mesh.indices.count * 4, options: []),
              let frontBytes = K3DTextures.rgba(.front),
              let front = Self.texture(device, queue, frontBytes),
              let back = Self.texture(device, queue, K3DTextures.back(version: K3DTextures.version)),
              let steel = Self.texture(device, queue, K3DTextures.rgba(.steel)),
              let linear = Self.sampler(device, .linear), let nearest = Self.sampler(device, .nearest),
              let filterSampler = Self.filterSampler(device),
              let flat = Self.texture(device, queue, [UInt8](repeating: 0, count: K3DTextures.width * K3DTextures.height * 4)),
              let oldFlat = Self.texture(device, queue, [UInt8](repeating: 0, count: K3DTextures.width * K3DTextures.height * 4)),
              let flatSampler = Self.flatSampler(device)
        else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.depth = depth
        self.glassPipeline = glassPipeline
        self.glassDepth = glassDepth
        self.downPipeline = downPipeline
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
        self.steel = steel
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
    static func makeLibrary(_ device: any MTLDevice) throws -> any MTLLibrary {
        try device.makeLibrary(source: K3DShader.source, options: nil)
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
            let p = SIMD3(mesh.vertices[e], mesh.vertices[e + 1], mesh.vertices[e + 2])
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
    /// part is less than 0.35 pt from its closed place (the most is the device's move back, 172
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
        guard screen !== frontScreen else { return }
        let picture = screen.flatMap(K3DTextures.picture)
        guard let bytes = K3DTextures.front(live: picture, base: frontBytes) else { return }
        Self.fill(front, bytes, queue)
        if let picture { Self.fill(flat, picture, queue) }
        flatBlack = picture.map(K3DTextures.isBlack)
        frontScreen = screen
    }

    /// Puts the old color's picture of a color spin in the 2D layer's second slot.
    func show(old screen: CGImage?) {
        guard screen !== oldScreen else { return }
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
    @discardableResult func draw(in view: K3DLayerView) -> Bool {
        show(screen: view.screen)
        show(old: view.oldScreen)
        guard let drawable = view.currentDrawable, let buffer = queue.makeCommandBuffer(), view.bounds.width > 0,
              render(buffer, pose: view.pose, size: view.bounds.size, center: view.deviceCenter,
                     pixelScale: Double(view.drawableSize.width / view.bounds.width), into: drawable.texture)
        else { return false }
        if view.firstFrame != nil {
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
        _ buffer: any MTLCommandBuffer, pose: K3DPose, size: CGSize, center: CGPoint, pixelScale: Double, into out: any MTLTexture
    ) -> Bool {
        let down = MTLRenderPassDescriptor()
        down.colorAttachments[0].texture = out
        down.colorAttachments[0].loadAction = .clear
        down.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        down.colorAttachments[0].storeAction = .store
        guard let rect = Self.bodyRect(Self.apartRect(ex: pose.ex) ? apartBox : closedBox, pose: pose, size: size, center: center, pixelScale: pixelScale)
        else {
            buffer.makeRenderCommandEncoder(descriptor: down)?.endEncoding()
            return true
        }
        let k = Self.supersample, w = rect.w * k, h = rect.h * k
        guard let targets = sceneTargets(w, h) else { return false }
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
        encode(encoder, pose: pose, size: points, center: shifted)
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
        }
        return nil
    }

    private func encode(_ encoder: any MTLRenderCommandEncoder, pose: K3DPose, size: CGSize, center: CGPoint) {
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
        let passes = Self.passes(ex: uniforms.ex)
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depth)
        // As the mock: closed, only front faces draw. Metal's clip space has y up, as WebGL's, so
        // the mock's counterclockwise front faces are counterclockwise here too.
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(passes.cull ? .back : .none)
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(front, index: 0)
        encoder.setFragmentTexture(back, index: 1)
        encoder.setFragmentTexture(steel, index: 2)
        encoder.setFragmentSamplerState(linear, index: 0)
        encoder.setFragmentSamplerState(nearest, index: 1)
        encoder.setFragmentTexture(layer?.texture ?? flat, index: 3)
        encoder.setFragmentSamplerState(flatSampler, index: 2)
        // Closed, no part reads the prints: the front texture stands in for them.
        for index in 0..<3 { encoder.setFragmentTexture(prints?[index] ?? front, index: 4 + index) }
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

private struct SpinBlackKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Changes 289 and 290: while a color spin runs, the color the 2D device shows (black or
    /// not), with no fade. Nil shows the state's color with its usual fade.
    var spinBlack: Bool? {
        get { self[SpinBlackKey.self] }
        set { self[SpinBlackKey.self] = newValue }
    }
}
