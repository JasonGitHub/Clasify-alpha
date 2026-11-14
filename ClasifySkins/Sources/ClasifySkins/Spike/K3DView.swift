import ClasifyCore
import MetalKit
import SwiftUI
import simd

/// SPIKE (CLA-101): the About screen's K.3D.7 flip in true 3D, behind the hidden UserDefaults
/// switch `spike.k3d` (default off). Only the app reads the switch. Remove the Spike folder,
/// the three k3d PNGs and the app's K3DSpikeSkin to take the spike out.
public enum K3DSpike {
    /// The hidden switch: `defaults write app.clasify.Clasify spike.k3d -bool true`.
    public static let key = "spike.k3d"

    /// The device as it shows now, at 2x, with its covers, for the 3D front's screen.
    @MainActor public static func snapshot(_ state: AppState, artwork: Artwork = .none) -> CGImage? {
        let renderer = ImageRenderer(content: PocketSkin(state: state, interactive: false).environment(\.artwork, artwork))
        renderer.scale = 2
        return renderer.cgImage
    }
}

/// Shows `content`, the 2D device, while the front rests flat. While the device turns or shows
/// its back, the 3D body shows in its place, over the window's margins too, with the 2D
/// device's drop shadow cast from its outline. The two crossfade in 0.1 s where a turn leaves or reaches the resting
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
    let content: Content
    /// Counts the turns that ended, so the body runs again and pauses the timeline.
    @State private var settled = 0
    /// The Metal view has shown its first frame.
    @State private var ready = false

    public init(
        flip: K3DFlip, black: Bool, margin: EdgeInsets, onTap: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) {
        self.flip = flip
        self.black = black
        self.margin = margin
        self.onTap = onTap
        self.content = content()
    }

    public var body: some View {
        // The timeline runs only while the device turns. At rest on either side it pauses, and
        // the pose is the side it rests on. A new turn changes `flip`, which starts it again.
        // Reading `settled` makes the body run again when a turn ends.
        let resting = settled >= 0 && flip.isResting(at: .now)
        TimelineView(.animation(paused: resting)) { context in
            let date = resting ? Date.distantFuture : context.date
            let flat = flip.flatOpacity(at: date)
            let pose = flip.pose(at: date)
            K3DHandover(flat: flat, ready: ready, content: content) { shown in
                body3D(angle: pose.angle, lift: pose.lift, shown: shown)
            }
        }
        .task(id: flip.start) {
            // When the turn ends, run the body again so the timeline pauses.
            let left = K3DFlip.duration - Date.now.timeIntervalSince(flip.start)
            guard left > 0 else { return }
            try? await Task.sleep(for: .seconds(left + 0.05))
            settled += 1
        }
    }

    /// The 3D body and its shadow, under the 2D device that shows with opacity `shown`.
    private func body3D(angle: Double, lift: Double, shown: Double) -> some View {
        let shows = shown < 1
        let size = PocketSkin.size
        let ready = $ready
        return ZStack {
            // The 2D device's drop shadow, from the 3D body's outline, only while the 3D body shows
            // (`shows`). Then the 2D device's own shadow is off (`K3DHandover`), so one shadow
            // shows at any time, with no step where they hand over (shadow option 1, Jason 17:30
            // JST 11-14). At rest on the front, the 2D device draws its own.
            if shows { K3DShadow(angle: angle, lift: lift, black: black) }
            K3DMetalView(
                angle: angle, lift: lift, black: black, screen: flip.screen,
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
/// 2D device shows with. Until the 3D body is `ready`, the 2D device stays opaque.
struct K3DHandover<Flat: View, Body3D: View>: View {
    let flat: Double
    let ready: Bool
    let content: Flat
    @ViewBuilder let body3D: (Double) -> Body3D

    /// The 2D device's opacity: `flat`, or 1 while the 3D body has no frame to show.
    static func shown(flat: Double, ready: Bool) -> Double { ready ? flat : 1 }

    var body: some View {
        let shown = Self.shown(flat: flat, ready: ready)
        content
            // While the 3D body shows, it draws the one shadow: the 2D device's own is off.
            .environment(\.pocketDropShadow, shown >= 1)
            .compositingGroup()
            .opacity(shown)
            .allowsHitTesting(shown >= 1)
            .background { body3D(shown) }
    }
}

/// The Metal view, drawn on demand: SwiftUI's timeline asks for each frame.
struct K3DMetalView: NSViewRepresentable {
    let angle: Double, lift: Double
    let black: Bool
    let screen: CGImage?
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
        let pose = K3DPose(angle: angle, lift: lift, black: black)
        // Draw only when the picture changes: the view stays mounted while the device rests.
        guard pose != view.pose || screen !== view.screen || center != view.deviceCenter || !view.drewOnce else { return }
        view.pose = pose
        view.screen = screen
        view.deviceCenter = center
        view.needsDisplay = true
    }
}

/// What the renderer draws: the turn, the push back, and the color.
struct K3DPose: Equatable {
    var angle = 0.0, lift = 0.0
    var black = false
}

final class K3DLayerView: MTKView {
    var pose = K3DPose()
    var screen: CGImage?
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
        depthStencilPixelFormat = .depth32Float
        sampleCount = K3DRenderer.samples
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
    }

    /// Clicks go through to SwiftUI, which turns the device back.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        if K3DRenderer.shared?.draw(in: self) == true { drewOnce = true }
    }

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
    /// The mock's camera: the eye 2600 pt from the body's center, near 500, far 3000.
    static let distance: Float = 2600, near: Float = 500, far: Float = 3000

    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let depth: any MTLDepthStencilState
    private let vertices: any MTLBuffer, indices: any MTLBuffer
    private let indexCount: Int
    private let front: any MTLTexture, back: any MTLTexture, steel: any MTLTexture
    private let linear: any MTLSamplerState, nearest: any MTLSamplerState
    /// The screen picture now in the front texture.
    private var frontScreen: CGImage?
    /// The front texture's bytes as bundled, read once: a turn's new screen goes into a copy.
    private let frontBytes: [UInt8]

    struct Uniforms {
        var mv: simd_float4x4
        var pr: simd_float4x4
        var blk: Float
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let pipeline = try? Self.makePipeline(device), let depth = Self.makeDepth(device)
        else { return nil }
        let mesh = K3DMesh()
        guard let vertices = device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * 4, options: []),
              let indices = device.makeBuffer(bytes: mesh.indices, length: mesh.indices.count * 4, options: []),
              let frontBytes = K3DTextures.rgba(.front),
              let front = Self.texture(device, queue, frontBytes),
              let back = Self.texture(device, queue, K3DTextures.back(version: K3DTextures.version)),
              let steel = Self.texture(device, queue, K3DTextures.rgba(.steel)),
              let linear = Self.sampler(device, .linear), let nearest = Self.sampler(device, .nearest)
        else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.depth = depth
        self.vertices = vertices
        self.indices = indices
        indexCount = mesh.indices.count
        self.front = front
        self.frontBytes = frontBytes
        self.back = back
        self.steel = steel
        self.linear = linear
        self.nearest = nearest
        // Warm-up: one frame of the back, off screen, when the view is mounted. In build 194 the
        // first turn repeated a frame near edge-on, where the back first shows. The likely cause
        // is first-use work for the back texture and its shader path, so it is done here.
        _ = image(K3DPose(angle: 180), screen: nil, size: PocketSkin.size, scale: 1)
    }

    /// The shaders and the pipeline. Internal so a test can check that the shaders compile.
    static func makePipeline(_ device: any MTLDevice) throws -> any MTLRenderPipelineState {
        let library = try device.makeLibrary(source: K3DShader.source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "k3dVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "k3dFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = samples
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeDepth(_ device: any MTLDevice) -> (any MTLDepthStencilState)? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: descriptor)
    }

    /// An RGBA texture with the bytes as they are (unorm, not sRGB), with mipmaps for the color,
    /// as the mock's power-of-two copies have.
    private static func texture(_ device: any MTLDevice, _ queue: any MTLCommandQueue, _ bytes: [UInt8]?) -> (any MTLTexture)? {
        guard let bytes else { return nil }
        let w = K3DTextures.width, h = K3DTextures.height
        guard bytes.count == w * h * 4 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: true)
        descriptor.usage = [.shaderRead, .renderTarget]  // render target: so the blit can make the mipmaps
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        fill(texture, bytes, queue)
        return texture
    }

    /// Puts the bytes in level 0 and makes the smaller levels from them.
    private static func fill(_ texture: any MTLTexture, _ bytes: [UInt8], _ queue: any MTLCommandQueue) {
        let w = K3DTextures.width, h = K3DTextures.height
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
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    /// Puts a new screen picture in the front's LCD now, before a turn starts, so the turn's
    /// first frame has no texture work to do.
    func prepare(screen: CGImage) { show(screen: screen) }

    /// Puts a new screen picture in the front's LCD.
    private func show(screen: CGImage?) {
        guard screen !== frontScreen, let bytes = K3DTextures.front(screen: screen, base: frontBytes) else { return }
        Self.fill(front, bytes, queue)
        frontScreen = screen
    }

    /// Draws one frame in the view. Returns false when it drew nothing.
    @discardableResult func draw(in view: K3DLayerView) -> Bool {
        show(screen: view.screen)
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return false }
        encode(encoder, pose: view.pose, size: view.bounds.size, center: view.deviceCenter)
        if view.firstFrame != nil {
            // Before the commit, so the handler cannot miss the presentation.
            drawable.addPresentedHandler(Self.presentedHandler(for: view))
        }
        buffer.present(drawable)
        buffer.commit()
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

    private func encode(_ encoder: any MTLRenderCommandEncoder, pose: K3DPose, size: CGSize, center: CGPoint) {
        var uniforms = Uniforms(
            mv: Self.modelView(angle: pose.angle, lift: pose.lift),
            pr: Self.projection(size: size, center: center), blk: pose.black ? 1 : 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depth)
        // As the mock: only front faces draw. Metal's clip space has y up, as WebGL's, so the
        // mock's counterclockwise front faces are counterclockwise here too.
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(front, index: 0)
        encoder.setFragmentTexture(back, index: 1)
        encoder.setFragmentTexture(steel, index: 2)
        encoder.setFragmentSamplerState(linear, index: 0)
        encoder.setFragmentSamplerState(nearest, index: 1)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indices, indexBufferOffset: 0)
        encoder.endEncoding()
    }

    /// One frame drawn off screen, `size` points at `scale` pixels per point, the device
    /// centered: for tests. Its pixels are premultiplied BGRA rows from the top.
    func image(_ pose: K3DPose, screen: CGImage?, size: CGSize, scale: Int) -> [UInt8]? {
        show(screen: screen)
        let w = Int(size.width) * scale, h = Int(size.height) * scale
        func target(_ format: MTLPixelFormat, samples: Int, storage: MTLStorageMode) -> (any MTLTexture)? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            descriptor.textureType = samples > 1 ? .type2DMultisample : .type2D
            descriptor.sampleCount = samples
            descriptor.usage = .renderTarget
            descriptor.storageMode = storage
            return device.makeTexture(descriptor: descriptor)
        }
        guard let color = target(.bgra8Unorm, samples: Self.samples, storage: .private),
              let resolved = target(.bgra8Unorm, samples: 1, storage: .managed),
              let depth = target(.depth32Float, samples: Self.samples, storage: .private),
              let buffer = queue.makeCommandBuffer()
        else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].resolveTexture = resolved
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encode(encoder, pose: pose, size: size, center: CGPoint(x: size.width / 2, y: size.height / 2))
        guard let blit = buffer.makeBlitCommandEncoder() else { return nil }
        blit.synchronize(resource: resolved)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var out = [UInt8](repeating: 0, count: w * h * 4)
        resolved.getBytes(&out, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return out
    }

    /// The mock's M = Translate(0, 0, -2600 - lift) * RotY(angle), with no tilt.
    static func modelView(angle: Double, lift: Double) -> simd_float4x4 {
        let a = Float(angle * .pi / 180), ca = cos(a), sa = sin(a)
        return simd_float4x4(columns: (
            SIMD4(ca, 0, -sa, 0), SIMD4(0, 1, 0, 0), SIMD4(sa, 0, ca, 0), SIMD4(0, 0, -distance - Float(lift), 1)))
    }

    /// A perspective with the mock's camera, scaled so the flat front (34 pt nearer than the
    /// center) shows at 1 pt per pt, the size of the 2D device. The lens shifts so the device's
    /// center falls on `center`, which is not the view's center. Metal's depth runs 0 to 1.
    static func projection(size: CGSize, center: CGPoint) -> simd_float4x4 {
        let w = Float(max(size.width, 1)), h = Float(max(size.height, 1))
        let d0 = distance - Float(K3DMesh.depth / 2)
        let fx = 2 * d0 / w, fy = 2 * d0 / h
        let sx = (Float(center.x) - w / 2) / (w / 2), sy = -(Float(center.y) - h / 2) / (h / 2)
        let n = near, f = far
        return simd_float4x4(columns: (
            SIMD4(fx, 0, 0, 0), SIMD4(0, fy, 0, 0), SIMD4(-sx, -sy, f / (n - f), -1), SIMD4(0, 0, f * n / (n - f), 0)))
    }
}
