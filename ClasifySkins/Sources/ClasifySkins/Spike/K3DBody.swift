import Foundation

/// CLA-196: the body that the one 3D engine draws. The classic is the K.3D.13 device of the
/// app. Every other body is the same engine with other numbers: the mesh (`K3DMesh(body:)`), the
/// shader (`K3DShader.shader(for:)`) and the textures read them. Units are points, the origin is
/// the body's center, y is up. The textures are 2 px per pt.
struct K3DBody: Equatable, Sendable {
    /// A rounded rectangle: center and half size, in points.
    struct Box: Equatable, Sendable {
        var x: Double, y: Double, hx: Double, hy: Double, r: Double
    }

    var width: Double, height: Double, depth: Double, radius: Double
    /// The plate's rolled edge: the classic curve (r = 4.4 + 180 (1 - turn / 90°)^9) times this.
    var edgeScale: Double
    /// The steel back's round onto the flat back: in from the side, and down from the straight wall.
    var backIn: Double, backDown: Double
    /// The window: the plate's hole and the glass, then the hole the shader cuts in the plate.
    var window: Box
    var windowCut: SIMD2<Double>
    /// The wheel's and the center button's center.
    var wheelCenter: SIMD2<Double>
    /// The plate's hole for the wheel, the wheel, the button's hole in the wheel, the button.
    var wheelHole: Double, wheel: Double, buttonHole: Double, button: Double
    /// The shader's shade and line radii round the wheel and the button (the mock's numbers).
    var wheelLine: SIMD2<Double>, buttonLine: SIMD2<Double>
    var wheelShade: SIMD2<Double>, wheelBlack: SIMD2<Double>, buttonShade: SIMD2<Double>
    /// The button's dish: its radius in the shader.
    var dish: Double
    /// The wheel's and the button's edges in the front texture, in px from the wheel's center.
    var textureWheel: SIMD2<Double>, textureButton: SIMD2<Double>
    /// The front and back textures: their bundled names, their size in px, and the LCD's rect
    /// in px: x from, x to, y from, y to.
    var front: String, back: String
    var textureSize: SIMD2<Int>
    var lcd: SIMD4<Double>
    /// Ids 250 (bezel) and 251 (LCD) live only above this part of the front texture's height.
    var topPart: Double
    /// The plate's color (the mock's uTint). The wheel and the back do not take it.
    var tint: SIMD3<Double>
    /// The classic has Take apart's parts in its mesh. Other bodies are closed devices only.
    var hasParts: Bool

    /// The classic: the app's device, K.3D.13. These are the numbers the engine had before CLA-196.
    static let classic = K3DBody(
        width: 366, height: 613, depth: 68, radius: 34, edgeScale: 1, backIn: 22, backDown: 24.8,
        window: Box(x: 0, y: 161.25, hx: 156.5, hy: 119.25, r: 7), windowCut: SIMD2(149.5, 112.25),
        wheelCenter: SIMD2(0, -127), wheelHole: 112.65, wheel: 112.8, buttonHole: 41.65, button: 41.8,
        wheelLine: SIMD2(111.6, 112.5), buttonLine: SIMD2(40.6, 41.5), wheelShade: SIMD2(108, 112), wheelBlack: SIMD2(107.5, 111.5),
        buttonShade: SIMD2(46, 42.5), dish: 41, textureWheel: SIMD2(225.8, 224.2), textureButton: SIMD2(82.7, 81.3),
        front: "k3d-front", back: "k3d-back", textureSize: SIMD2(732, 1226), lcd: SIMD4(66, 666, 65, 515), topPart: 0.5,
        tint: SIMD3(0.995, 0.997, 1), hasParts: true)
}
