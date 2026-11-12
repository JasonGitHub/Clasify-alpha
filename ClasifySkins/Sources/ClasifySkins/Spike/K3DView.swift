import ClasifyCore
import MetalKit
import SwiftUI
import simd

/// SPIKE (CLA-101): the About screen's K.3D.1 flip in true 3D, behind the hidden UserDefaults
/// switch `spike.k3d` (default off). Only the app reads the switch. Remove the Spike folder,
/// the three k3d PNGs and the app's K3DSpikeSkin to take the spike out.
public enum K3DSpike {
    /// The hidden switch: `defaults write app.clasify.Clasify spike.k3d -bool true`.
    public static let key = "spike.k3d"

    /// The device as it shows now, at 2x, for the 3D front's screen.
    @MainActor public static func snapshot(_ state: AppState) -> CGImage? {
        let renderer = ImageRenderer(content: PocketSkin(state: state, interactive: false))
        renderer.scale = 2
        return renderer.cgImage
    }
}

/// Shows `content`, the 2D device, while the front rests flat. While the device turns or shows
/// its back, the 3D body shows in its place, over the window's margins too, with the mock's
/// soft ground shadow. A click on the 3D body calls `onTap`.
public struct K3DFlipView<Content: View>: View {
    let flip: K3DFlip
    let margin: EdgeInsets
    let onTap: () -> Void
    let content: Content

    public init(flip: K3DFlip, margin: EdgeInsets, onTap: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.flip = flip
        self.margin = margin
        self.onTap = onTap
        self.content = content()
    }

    public var body: some View {
        TimelineView(.animation(paused: flip.restsOnFront(at: .now))) { context in
            let front = flip.restsOnFront(at: context.date)
            let pose = flip.pose(at: context.date)
            content
                .opacity(front ? 1 : 0)
                .overlay {
                    if !front { body3D(angle: pose.angle, lift: pose.lift) }
                }
        }
    }

    private func body3D(angle: Double, lift: Double) -> some View {
        let size = PocketSkin.size
        let a = angle * .pi / 180
        // The mock's ground: 340 x 20 pt, 3.5 pt under the device, as wide as the body seen now.
        let wide = abs(cos(a)) + K3DMesh.depth / K3DMesh.width * abs(sin(a))
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [.black.opacity(0.22), .black.opacity(0)], center: .center, startRadius: 0, endRadius: 10))
                .frame(width: 20, height: 20)
                .scaleEffect(x: 17 * wide, y: 1)
                .position(x: size.width / 2, y: size.height + 13.5)
            K3DMetalView(
                angle: angle, lift: lift, screen: flip.screen,
                center: CGPoint(x: margin.leading + size.width / 2, y: margin.top + size.height / 2))
                .padding(EdgeInsets(top: -margin.top, leading: -margin.leading, bottom: -margin.bottom, trailing: -margin.trailing))
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// The Metal view, drawn on demand: SwiftUI's timeline asks for each frame.
struct K3DMetalView: NSViewRepresentable {
    let angle: Double, lift: Double
    let screen: CGImage?
    /// The device's center in the view, in points from the top left.
    let center: CGPoint

    func makeNSView(context: Context) -> K3DLayerView { K3DLayerView() }

    func updateNSView(_ view: K3DLayerView, context: Context) {
        view.angle = angle
        view.lift = lift
        view.screen = screen
        view.deviceCenter = center
        view.needsDisplay = true
    }
}

final class K3DLayerView: MTKView {
    var angle = 0.0, lift = 0.0
    var screen: CGImage?
    var deviceCenter = CGPoint.zero

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
        K3DRenderer.shared?.draw(in: self)
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

    struct Uniforms {
        var mv: simd_float4x4
        var pr: simd_float4x4
        var vr: Float
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let pipeline = try? Self.makePipeline(device), let depth = Self.makeDepth(device)
        else { return nil }
        let mesh = K3DMesh()
        guard let vertices = device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * 4, options: []),
              let indices = device.makeBuffer(bytes: mesh.indices, length: mesh.indices.count * 4, options: []),
              let front = Self.texture(device, K3DTextures.rgba(.front)),
              let back = Self.texture(device, K3DTextures.rgba(.back)),
              let steel = Self.texture(device, K3DTextures.rgba(.steel)),
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
        self.back = back
        self.steel = steel
        self.linear = linear
        self.nearest = nearest
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

    /// An RGBA texture with the bytes as they are: unorm, not sRGB, no mipmaps.
    private static func texture(_ device: any MTLDevice, _ bytes: [UInt8]?) -> (any MTLTexture)? {
        guard let bytes else { return nil }
        let w = K3DTextures.width, h = K3DTextures.height
        guard bytes.count == w * h * 4 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
        return texture
    }

    private static func sampler(_ device: any MTLDevice, _ filter: MTLSamplerMinMagFilter) -> (any MTLSamplerState)? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = filter
        descriptor.magFilter = filter
        descriptor.mipFilter = .notMipmapped
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    func draw(in view: K3DLayerView) {
        if view.screen !== frontScreen, let bytes = K3DTextures.front(screen: view.screen) {
            let w = K3DTextures.width, h = K3DTextures.height
            front.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
            frontScreen = view.screen
        }
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        var uniforms = Uniforms(
            mv: Self.modelView(angle: view.angle, lift: view.lift),
            pr: Self.projection(size: view.bounds.size, center: view.deviceCenter), vr: 1)
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depth)
        encoder.setCullMode(.none)
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
        buffer.present(drawable)
        buffer.commit()
    }

    /// The mock's M = Translate(0, 0, -2600 - lift) * RotY(angle), with no tilt.
    static func modelView(angle: Double, lift: Double) -> simd_float4x4 {
        let a = Float(angle * .pi / 180), ca = cos(a), sa = sin(a)
        return simd_float4x4(columns: (
            SIMD4(ca, 0, -sa, 0), SIMD4(0, 1, 0, 0), SIMD4(sa, 0, ca, 0), SIMD4(0, 0, -distance - Float(lift), 1)))
    }

    /// A perspective with the mock's camera, scaled so the flat front (31 pt nearer than the
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
