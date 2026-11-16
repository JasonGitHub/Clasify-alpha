import ClasifyCore
import Foundation
import Metal
import SwiftUI
import Testing

@testable import ClasifySkins

/// SPIKE (CLA-101): the K.3D.7 port. The textures load with their bytes as stored, the mesh
/// matches the mock's `k3d_src3.js`, and the shaders compile.
@Suite @MainActor struct K3DTests {
    func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * K3DTextures.width + x) * 4
        return Array(bytes[i..<(i + 4)])
    }

    /// The front's alpha is a material id. One pixel of each id, with its exact color: a
    /// premultiplied or color-matched load would change them.
    @Test func theFrontKeepsItsMaterialIds() throws {
        let front = try #require(K3DTextures.rgba(.front))
        #expect(front.count == K3DTextures.width * K3DTextures.height * 4)
        #expect(pixel(front, 500, 865) == [247, 250, 251, 255])  // wheel
        #expect(pixel(front, 100, 1100) == [195, 199, 190, 253])  // bare aluminium
        #expect(pixel(front, 100, 100) == [204, 210, 219, 251])  // LCD
        #expect(pixel(front, 58, 300) == [42, 44, 46, 250])  // bezel ink
        #expect(pixel(front, 365, 865) == [206, 207, 207, 249])  // center button
    }

    @Test func theBackAndSteelLoad() throws {
        for name in [K3DTextures.Name.back, .steel] {
            let bytes = try #require(K3DTextures.rgba(name))
            #expect(bytes.count == K3DTextures.width * K3DTextures.height * 4, "\(name)")
        }
    }

    /// A live screen changes only the LCD's color. Every alpha id stays.
    @Test func aLiveScreenKeepsTheIds() throws {
        let plain = try #require(K3DTextures.rgba(.front))
        let shot = try #require(K3DSpike.snapshot(AppState()))
        let live = try #require(K3DTextures.front(screen: shot))
        #expect(stride(from: 3, to: plain.count, by: 4).allSatisfy { plain[$0] == live[$0] })
        #expect(pixel(live, 100, 1100) == pixel(plain, 100, 1100))  // the aluminium does not change
    }

    /// Every LCD pixel (id 251) is in `K3DTextures.lcd`, the only rect a live screen looks at.
    @Test func theLCDIsInItsRect() throws {
        let plain = try #require(K3DTextures.rgba(.front))
        var count = 0
        for i in stride(from: 3, to: plain.count, by: 4) where plain[i] == 251 {
            let p = i / 4, x = p % K3DTextures.width, y = p / K3DTextures.width
            #expect(K3DTextures.lcd.x.contains(x) && K3DTextures.lcd.y.contains(y), "\(x), \(y)")
            count += 1
        }
        #expect(count == 600 * 450)
    }

    /// A turn to the back makes its screen picture first and starts its clock after: the
    /// snapshot's time does not come out of the turn (build 194 jumped at the turn's start).
    /// A turn to the front makes no picture.
    @Test func theTurnStartsAfterTheSnapshot() throws {
        var flip = K3DFlip()
        let shot = try #require(K3DSpike.snapshot(AppState()))
        var made = Date.distantFuture
        flip.turn {
            Thread.sleep(forTimeInterval: 0.05)
            made = .now
            return shot
        }
        #expect(flip.toBack)
        #expect(flip.start >= made)
        #expect(flip.screen === shot)
        var asked = false
        flip.turn { asked = true; return nil }
        #expect(!flip.toBack)
        #expect(!asked)
    }

    /// The shadow's shape follows the 3D body: straight on, it is the 2D body's own rounded
    /// rectangle (366 x 613 pt, 20 pt lower at the top for the shadow's copy). Edge-on it is as
    /// narrow as the body's depth; from the back as wide as the body, a little smaller.
    @Test func theShadowFollowsTheBody() {
        let front = K3DShadow.outline(angle: 0, lift: 0, drop: 0).boundingRect
        #expect(abs(front.minX) < 0.01 && abs(front.minY) < 0.01, "\(front)")
        #expect(abs(front.width - 366) < 0.01 && abs(front.height - 613) < 0.01, "\(front)")
        let copy = K3DShadow.outline(angle: 0, lift: 0, drop: PocketSkin.shadowDrop).boundingRect
        #expect(abs(copy.minY - 20) < 0.01 && abs(copy.maxY - 613) < 0.01, "\(copy)")
        let edge = K3DShadow.outline(angle: 90, lift: 70, drop: 0).boundingRect
        #expect(edge.width > 50 && edge.width < 80, "\(edge)")
        #expect(abs(edge.midX - 183) < 1, "\(edge)")
        let back = K3DShadow.outline(angle: 180, lift: 0, drop: 0).boundingRect
        #expect(back.width > 360 && back.width < 366, "\(back)")
        // The hull's corners are the 2D shape's: a point on the corner's curve is on the outline.
        let path = K3DShadow.outline(angle: 0, lift: 0, drop: 0)
        #expect(path.contains(CGPoint(x: 12, y: 12)) && !path.contains(CGPoint(x: 4, y: 4)))
        // CLA-119: the cut is the mesh's own outline: straight on, inside the 2D body and nearly
        // as big (the plate's rolled edge falls back from the front, so it shows 364.8 x 611.1).
        let cut = K3DShadow.cut(angle: 0, lift: 0).boundingRect
        #expect(cut.minX >= -0.01 && cut.minY >= -0.01 && cut.maxX <= 366.01 && cut.maxY <= 613.01, "\(cut)")
        #expect(cut.width > 364 && cut.height > 610, "\(cut)")
    }

    /// The back shows the app's version in place of the art's "1.0 · Build 161". Only the spec
    /// table's value changes.
    @Test func theBackShowsTheRealVersion() throws {
        let art = try #require(K3DTextures.rgba(.back))
        let back = try #require(K3DTextures.back(version: "9.9 · Build 999"))
        #expect(back.count == art.count)
        var changed = 0
        for y in 0..<K3DTextures.height {
            for x in 0..<K3DTextures.width where pixel(back, x, y) != pixel(art, x, y) {
                #expect((330..<540).contains(x) && (936..<958).contains(y), "\(x), \(y)")
                changed += 1
            }
        }
        #expect(changed > 100)
    }

    /// Counts, two vertices and some indices, checked against the mock's own code run in Node,
    /// with the Take apart parts and the hidden screen module left out: the closed device, which
    /// comes first in the mesh.
    @Test func theMeshMatchesTheMock() {
        let mesh = K3DMesh()
        #expect(mesh.closedVertexCount == 8542)
        #expect(mesh.closedIndexCount == 47040)
        #expect(mesh.indices[..<mesh.closedIndexCount].allSatisfy { Int($0) < mesh.closedVertexCount })
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertexCount })
        let want: [Int: [Float]] = [
            1234: [173.96415, -288.08357, 30.092016, 0.36168544, -0.24167049, 0.90043268, 0.97531189, 0.96995689, 0.97531189, 0.96995689, 1, 3, 1],
            6000: [-156.5, 241.42857, 34.054415, 1, 0, 0, 0.072404372, 0.10615241, 0.072404372, 0.10615241, 1, 0, 1],
        ]
        for (index, expected) in want {
            let v = Array(mesh.vertices[(index * K3DMesh.stride)..<((index + 1) * K3DMesh.stride)])
            for (got, value) in zip(v, expected) { #expect(abs(got - value) < 0.0001, "\(index): \(v)") }
        }
        #expect(Array(mesh.indices[40000..<40015]) == [7118, 7116, 7117, 7118, 7119, 7119, 7118, 7120, 7117, 7119, 7118, 7119, 7120, 7118, 7119])
    }

    /// The flip: 0.82 s to turn with a small overshoot, settled at 1.0 s, pushed back mid-turn.
    @Test func theFlipFollowsTheMock() {
        var flip = K3DFlip()
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(flip.restsOnFront(at: t0))
        flip.toggle(at: t0, screen: nil)
        #expect(flip.toBack && !flip.restsOnFront(at: t0) && !flip.isResting(at: t0))
        let mid = flip.pose(at: t0.addingTimeInterval(0.41))
        #expect(abs(mid.angle - 92.25) < 0.01 && abs(mid.lift - 70) < 0.01)
        #expect(flip.pose(at: t0.addingTimeInterval(0.82)).angle > 180)  // the overshoot
        let end = flip.pose(at: t0.addingTimeInterval(1))
        #expect(end.angle == 180 && end.lift == 0 && flip.isResting(at: t0.addingTimeInterval(1)))  // the back rests
        flip.toggle(at: t0.addingTimeInterval(2), screen: nil)
        #expect(!flip.toBack && !flip.restsOnFront(at: t0.addingTimeInterval(2.5)))
        #expect(flip.restsOnFront(at: t0.addingTimeInterval(3)))
    }

    /// CLA-119: the flat 2D device and the 3D body hand over by angle, within 2° of the resting
    /// front, as the shader's `nearRest`. A turn that lands on the front swings past it first:
    /// the 2D device waits for the landing.
    @Test func theFlatDeviceCrossfades() {
        var flip = K3DFlip()
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        func at(_ t: Double) -> Date { t0.addingTimeInterval(t) }
        func byAngle(_ t: Double) -> Bool {
            abs(flip.flatOpacity(at: at(t)) - K3DFlip.nearRest(angle: flip.angle(at: at(t)), tilt: 0)) < 1e-12
        }
        #expect(flip.flatOpacity(at: t0) == 1)
        flip.toggle(at: t0, screen: nil)
        #expect(flip.flatOpacity(at: t0) == 1)
        let early = flip.flatOpacity(at: at(0.05))
        #expect(early > 0.9 && early < 1 && byAngle(0.05) && byAngle(0.1))
        #expect(flip.flatOpacity(at: at(0.15)) == 0)  // past 2°
        // No push back while the 2D device shows: the 3D body under it is its size.
        let start = (0..<40).map { at(Double($0) / 200) }
        #expect(start.allSatisfy { flip.flatOpacity(at: $0) == 0 || flip.pose(at: $0).lift == 0 })
        #expect(flip.pose(at: at(0.3)).lift > 20)
        #expect(flip.flatOpacity(at: at(5)) == 0)  // the back rests
        flip.toggle(at: at(5), screen: nil)
        // The flip swings 4.5° past the front: it passes 0° while the 2D device waits.
        let swing = (0..<82).map { at(5 + Double($0) / 100) }
        #expect(swing.contains { abs(flip.angle(at: $0)) < 0.5 })
        #expect(swing.allSatisfy { flip.flatOpacity(at: $0) == 0 })
        let back = flip.flatOpacity(at: at(5.89))
        #expect(back > 0 && back < 0.2 && byAngle(5.89) && byAngle(5.95))
        #expect(flip.flatOpacity(at: at(6)) == 1)
        // A turn to the back that starts mid-turn, away from the front, shows no 2D.
        flip.toggle(at: at(10), screen: nil)
        flip.toggle(at: at(10.4), screen: nil)
        flip.toggle(at: at(10.45), screen: nil)
        #expect(flip.flatOpacity(at: at(10.46)) == 0)
    }

    /// CLA-119: the fade by angle is 1 at rest, smooth in degrees to 0 at 2°, and counts the tilt.
    @Test func theFadeByAngleEndsAt2Degrees() {
        #expect(K3DFlip.nearRest(angle: 0, tilt: 0) == 1)
        #expect(abs(K3DFlip.nearRest(angle: 1, tilt: 0) - 0.5) < 1e-6)
        #expect(abs(K3DFlip.nearRest(angle: -1, tilt: 0) - 0.5) < 1e-6)
        #expect(abs(K3DFlip.nearRest(angle: 0, tilt: 1) - 0.5) < 1e-6)
        #expect(K3DFlip.nearRest(angle: 2, tilt: 0) == 0 && K3DFlip.nearRest(angle: 180, tilt: 0) == 0)
        #expect(K3DFlip.nearRest(angle: 360, tilt: 0) > 0.999)
        #expect(K3DFlip.nearRest(angle: 1.5, tilt: 1.5) == 0)  // about 2.1° off rest
    }

    /// Change 288 must not change the About flip: the same 1.0 s, angles and 0.1 s crossfade,
    /// at full size and opacity.
    @Test func theFlipScriptStaysAsBefore() {
        var flip = K3DFlip()
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        flip.toggle(at: t0, screen: nil)
        #expect(!flip.arriving && flip.length == 1.0 && K3DFlip.fade == 0.1)
        #expect(flip.pose(at: t0).angle == 0 && flip.pose(at: t0.addingTimeInterval(1)).angle == 180)
        for dt in [0.0, 0.3, 0.9] {
            let look = flip.look(at: t0.addingTimeInterval(dt))
            #expect(look.scale == 1 && look.opacity == 1)
        }
        #expect(!flip.isResting(at: t0.addingTimeInterval(0.99)) && flip.isResting(at: t0.addingTimeInterval(1)))
    }

    /// Card BR, change 288 (gen.py `g1`): from -120° and 55% size, one ease-out turn to the front
    /// in 1.6 s, fading in over 0.8 s. Then the 2D device fades in over 0.35 s, with no rest.
    @Test func theArrivalFollowsTheSketch() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        let flip = K3DFlip.arrive(at: t0) { nil }
        func at(_ t: Double) -> Date { t0.addingTimeInterval(t) }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
        #expect(flip.arriving && !flip.toBack && near(flip.length, 1.95))
        let e = 1 - pow(0.5, 3.0)  // the ease-out at u = 0.5
        let angles = [0.0, 0.8, 1.6, 1.8].map { flip.pose(at: at($0)) }
        #expect(near(angles[0].angle, -120) && near(angles[1].angle, -120 + 120 * e))
        #expect(near(angles[2].angle, 0) && near(angles[3].angle, 0) && angles.allSatisfy { $0.lift == 0 })
        let looks = [0.0, 0.4, 0.8, 1.6].map { flip.look(at: at($0)) }
        #expect(near(looks[0].scale, 0.55) && near(looks[0].opacity, 0) && near(looks[1].opacity, 0.5))
        #expect(near(looks[2].scale, 0.55 + 0.45 * e) && near(looks[2].opacity, 1))
        #expect(near(looks[3].scale, 1) && near(looks[3].opacity, 1))
        #expect(flip.flatOpacity(at: at(1.59)) == 0)  // the turn shows only 3D
        #expect(near(flip.flatOpacity(at: at(1.775)), 0.5))
        #expect(flip.flatOpacity(at: at(1.96)) == 1)
        #expect(!flip.restsOnFront(at: at(1.9)) && flip.restsOnFront(at: at(1.96)))
        // `.arrived` goes 0.2 s before the turn ends. Hello writes nothing for 0.2 s, so its first
        // stroke starts as the 2D device starts to fade in, never on the 3D screen before.
        let sent = K3DFlip.arriveTurn - K3DFlip.arriveHelloLead
        #expect(near(sent, 1.4))
        #expect(Hello.written(look: 0, at: Hello.elapsed(at: 1.59, since: sent, waiting: false)) < 1e-6)
        #expect(Hello.written(look: 0, at: Hello.elapsed(at: 1.7, since: sent, waiting: false)) > 0)
        #expect(Hello.written(look: 0, at: Hello.elapsed(at: 1.39, since: 0, waiting: true)) < 1e-6)
    }

    /// CLA-117, change 303 (cold.py `arr`): from -60° and 80% size, one ease-out turn to the
    /// front in 1.0 s, fading in over 0.25 s. The 2D device fades in over the turn's last 0.15 s.
    @Test func theShortArrivalFollowsTheSketch() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        let flip = K3DFlip.arriveShort(at: t0) { nil }
        func at(_ t: Double) -> Date { t0.addingTimeInterval(t) }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
        #expect(flip.arriving && !flip.toBack && near(flip.length, 1.0) && near(flip.ends.timeIntervalSince(t0), 1.0))
        let e = 1 - pow(0.5, 3.0)  // the ease-out at u = 0.5
        #expect(near(flip.pose(at: at(0)).angle, -60) && near(flip.pose(at: at(0.5)).angle, -60 + 60 * e))
        #expect(near(flip.pose(at: at(1)).angle, 0) && flip.pose(at: at(0.5)).lift == 0)
        #expect(near(flip.look(at: at(0)).scale, 0.8) && near(flip.look(at: at(0.5)).scale, 0.8 + 0.2 * e))
        #expect(near(flip.look(at: at(0)).opacity, 0) && near(flip.look(at: at(0.125)).opacity, 0.5))
        #expect(near(flip.look(at: at(0.25)).opacity, 1) && near(flip.look(at: at(1)).scale, 1))
        #expect(flip.flatOpacity(at: at(0.84)) == 0 && near(flip.flatOpacity(at: at(0.925)), 0.5))
        #expect(flip.flatOpacity(at: at(1.01)) == 1 && flip.restsOnFront(at: at(1.01)))
        // The hidden 2D device takes input during the turn; nothing holds it.
        #expect(flip.takesInput(at: at(0.1)) && !flip.takesInput(at: at(1.01)))
        #expect(!flip.holdsInput(at: at(0.1)))
    }

    /// CLA-117: input during the short arrival runs the rest 4 times faster: it lands in 0.25 s
    /// at most, from where it was.
    @Test func inputHurriesTheShortArrival() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        func at(_ t: Double) -> Date { t0.addingTimeInterval(t) }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
        var flip = K3DFlip.arriveShort(at: t0) { nil }
        flip.hurry(at: at(0.2))
        #expect(near(flip.ends.timeIntervalSince(t0), 0.4))  // 0.8 s left, 4 times faster
        #expect(near(flip.pose(at: at(0.2)).angle, K3DFlip.arriveShort(at: t0) { nil }.pose(at: at(0.2)).angle))  // no jump
        #expect(near(flip.elapsed(at: at(0.3)), 0.6))
        #expect(!flip.restsOnFront(at: at(0.39)) && flip.restsOnFront(at: at(0.41)))
        flip.hurry(at: at(0.3))  // once only
        #expect(near(flip.ends.timeIntervalSince(t0), 0.4))
        var first = K3DFlip.arriveShort(at: t0) { nil }
        first.hurry(at: at(0))
        #expect(near(first.ends.timeIntervalSince(t0), 0.25))
        // Other scripts do not hurry.
        var arrive = K3DFlip.arrive(at: t0) { nil }
        arrive.hurry(at: at(0.2))
        #expect(near(arrive.ends.timeIntervalSince(t0), 1.95))
    }

    /// CLA-117: which arrival a window plays, for each case.
    @Test func eachLaunchPicksItsArrival() {
        typealias A = K3DArrival
        #expect(A.Cold(nil) == .short && A.Cold("short") == .short && A.Cold("full") == .full)
        #expect(A.Cold("off") == .off && A.Cold("Full") == .off && A.Cold("") == .off)
        for cold in [A.Cold.short, .full, .off] {
            // The first launch ever is 288 with Hello, whatever the setting.
            #expect(A.pick(arrived: false, launched: false, cold: cold, canTurn: true) == .first)
            #expect(A.pick(arrived: false, launched: true, cold: cold, canTurn: true) == .first)
            #expect(A.pick(arrived: false, launched: false, cold: cold, canTurn: false) == .still)
            // A window opened again in the same launch, or no motion: no turn.
            #expect(A.pick(arrived: true, launched: true, cold: cold, canTurn: true) == .still)
            #expect(A.pick(arrived: true, launched: false, cold: cold, canTurn: false) == .still)
        }
        #expect(A.pick(arrived: true, launched: false, cold: .short, canTurn: true) == .short)
        #expect(A.pick(arrived: true, launched: false, cold: .full, canTurn: true) == .full)
        #expect(A.pick(arrived: true, launched: false, cold: .off, canTurn: true) == .still)
    }

    /// CLA-117 "full" and change 288: input waits until the turn lands.
    @Test func theFullArrivalHoldsInputUntilItLands() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        let flip = K3DFlip.arrive(at: t0) { nil }
        #expect(flip.holdsInput(at: t0.addingTimeInterval(1.59)) && !flip.holdsInput(at: t0.addingTimeInterval(1.61)))
        #expect(!flip.takesInput(at: t0.addingTimeInterval(0.5)))
        #expect(K3DFlip.waiting.holdsInput(at: .now))
        #expect(!K3DFlip().holdsInput(at: .now))
        #expect(!K3DFlip.spin(turn: 0.8, fromBlack: false) { nil }.holdsInput(at: .now))
    }

    /// Card BR, changes 289 and 290 (gen.py `spin`): a 0.15 s crossfade to 3D, one 360° turn with
    /// a quad in-out, the old color until 180°, and a 0.15 s crossfade back.
    @Test(arguments: [K3DFlip.spinPick, K3DFlip.spinSettings]) func theColorSpinFollowsTheSketch(turn: Double) {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        let flip = K3DFlip.spin(turn: turn, fromBlack: false, at: t0) { nil }
        func at(_ t: Double) -> Date { t0.addingTimeInterval(t) }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
        #expect(near(flip.length, turn + 0.3) && !flip.arriving && !flip.toBack)
        // CLA-119: the 2D device hands over by angle: it shows while the spin waits at 0°.
        #expect(flip.flatOpacity(at: at(0)) == 1 && flip.flatOpacity(at: at(0.1)) == 1)
        #expect(flip.flatOpacity(at: at(0.15 + turn / 10)) == 0 && flip.flatOpacity(at: at(0.15 + turn / 2)) == 0)
        #expect(flip.flatOpacity(at: at(0.15 + 0.9 * turn)) == 0)
        let late = 0.15 + 0.99 * turn
        #expect(near(flip.flatOpacity(at: at(late)), K3DFlip.nearRest(angle: flip.angle(at: at(late)), tilt: 0)))
        #expect(flip.flatOpacity(at: at(turn + 0.15)) == 1 && flip.flatOpacity(at: at(turn + 0.31)) == 1)
        #expect(flip.pose(at: at(0.1)).angle == 0)  // no turn while it crossfades
        #expect(near(flip.pose(at: at(0.15 + turn / 4)).angle, 360 * 0.125))  // quad in: 2u²
        #expect(near(flip.pose(at: at(0.15 + turn / 2)).angle, 180))
        #expect(near(flip.pose(at: at(0.15 + 3 * turn / 4)).angle, 360 * 0.875))
        #expect(flip.pose(at: at(turn + 0.2)).angle == 0 && flip.pose(at: .distantFuture).angle == 0)  // 360° is 0 at rest
        #expect(flip.pose(at: at(0.15 + turn / 2)).lift == 0)
        #expect(flip.look(at: at(0.5)).scale == 1 && flip.look(at: at(0.5)).opacity == 1)
        // The old color to 180°, then the device's color now, even if it changed again.
        #expect(!flip.black(at: at(0.15 + turn * 0.49), live: true))
        #expect(flip.black(at: at(0.15 + turn * 0.51), live: true))
        #expect(flip.blackOverride(at: at(0.05), live: true) == false)
        #expect(flip.blackOverride(at: at(turn + 0.25), live: true) == true)
        #expect(flip.blackOverride(at: at(turn + 0.31), live: true) == nil)  // at rest the 2D device shows its own
        #expect(flip.isSpinning(at: at(turn)) && !flip.isSpinning(at: at(turn + 0.31)))
        #expect(flip.restsOnFront(at: at(turn + 0.31)))
    }

    /// As for a flip, the arrival and the spin start their clock after the screen picture is
    /// made, so a slow snapshot does not cut their start (Codex on #247).
    @Test func theArrivalAndTheSpinStartAfterTheSnapshot() {
        func slow(_ made: inout Date) -> CGImage? {
            Thread.sleep(forTimeInterval: 0.05)
            made = .now
            return nil
        }
        var made = Date.distantFuture
        let arrive = K3DFlip.arrive { slow(&made) }
        #expect(arrive.start >= made)
        made = .distantFuture
        let spin = K3DFlip.spin(turn: K3DFlip.spinPick, fromBlack: false) { slow(&made) }
        #expect(spin.start >= made)
    }

    /// Change 288 (Jason, build 237: the 2D device flashed before the turn): before the
    /// arrival starts, the first frame shows nothing, at any clock.
    @Test func theFirstFrameWaitsForTheArrival() {
        let flip = K3DFlip.waiting
        #expect(flip.arriving && !flip.restsOnFront(at: .now))
        for date in [Date.now, .now.addingTimeInterval(5), .distantPast] {
            #expect(flip.flatOpacity(at: date) == 0 && flip.look(at: date).opacity == 0)
        }
        #expect(K3DHandover<EmptyView, EmptyView>.shown(flat: flip.flatOpacity(at: .now), ready: false, hidesUntilReady: true) == 0)
        #expect(K3DHandover<EmptyView, EmptyView>.shown(flat: flip.flatOpacity(at: .now), ready: true, hidesUntilReady: true) == 0)
    }

    /// While it arrives, the 2D device stays hidden until the 3D body has drawn: no flash.
    @Test func theArrivalHidesThe2DDeviceUntilThe3DFrameIsReady() {
        typealias H = K3DHandover<EmptyView, EmptyView>
        #expect(H.shown(flat: 0, ready: false, hidesUntilReady: true) == 0)
        #expect(H.shown(flat: 0.4, ready: true, hidesUntilReady: true) == 0.4)
        #expect(H.shown(flat: 0, ready: false) == 1)  // a flip keeps the 2D device opaque
    }

    /// The shaders compile and link, where the machine has a Metal device.
    @Test func theShadersCompile() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let library = try K3DRenderer.makeLibrary(device)
        _ = try K3DRenderer.makePipeline(library)
        _ = try K3DRenderer.makePipeline(library, blend: true)
        _ = try K3DRenderer.makeDownPipeline(library)
        #expect(K3DRenderer.shared != nil)
    }
}
