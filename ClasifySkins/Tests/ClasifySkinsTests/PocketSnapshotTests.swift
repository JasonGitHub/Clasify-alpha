import AppKit
import ClasifyCore
import QuartzCore
import SwiftUI
import Testing

@testable import ClasifySkins

/// Snapshot tests of the Pocket skin's main screens, drawn with ImageRenderer. They check
/// colors at known points of the mockup layout. When SNAPSHOT_DIR is set, they also save
/// each screen as a PNG there, so a person can compare it with the mockup. CI uploads them.
@Suite @MainActor struct PocketSnapshotTests {
    /// The rendered device and its pixels, read in points from the top left.
    struct Snapshot {
        let bitmap: NSBitmapImageRep
        static let scale = 2

        func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let color = bitmap.colorAt(x: x * Self.scale, y: y * Self.scale)?.usingColorSpace(.sRGB)
            let c = color ?? .clear
            return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }

        func isBlue(_ x: Int, _ y: Int) -> Bool { let c = rgb(x, y); return c.b > c.r + 60 && c.b > 150 }
        func isLight(_ x: Int, _ y: Int) -> Bool { let c = rgb(x, y); return min(c.r, c.g, c.b) > 180 }
        func isDark(_ x: Int, _ y: Int) -> Bool { let c = rgb(x, y); return max(c.r, c.g, c.b) < 120 }
    }

    // Points in the mockup layout: the device border 1, its padding 24.8, the bezel 6.6 (the
    // screen starts at 33 x 32.4), the header 19 with its line (the list starts at 51.4), and 9
    // rows of 22.9. Song lists have 5 two-line rows: 41.2 with no bar, 36.6 over the bar. The
    // bar shows only with Now Playing Bar on (card AK). The screen is 300 x 225, so its bottom is at 257.4.
    static let screenLeft = 33, screenTop = 32, listTop = 51, screenWidth = 300, screenBottom = 257

    static func rowCenter(_ index: Int, bar: Bool = false, songs: Bool = false) -> Int {
        let height = songs ? (bar ? 183.1 : 206) / 5 : 206 / 9
        return Int(51.4 + (Double(index) + 0.5) * height)
    }

    func render(
        _ state: AppState, _ name: String, pressed: ClickWheel.Zone? = nil, artwork: Artwork = .none, time: Double = 1
    ) throws -> Snapshot {
        let skin = PocketSkin(state: state, interactive: false, pressed: pressed)
            .environment(\.artwork, artwork)
            .environment(\.animationTime, time)  // 1: the main menu's first cover, just faded in
        let renderer = ImageRenderer(content: skin)
        renderer.scale = CGFloat(Snapshot.scale)
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(PocketSkin.size.width) * Snapshot.scale)
        #expect(image.height == Int(PocketSkin.size.height) * Snapshot.scale)
        let bitmap = NSBitmapImageRep(cgImage: image)
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pocket-\(name).png"))
        }
        return Snapshot(bitmap: bitmap)
    }

    /// One flat color drawn by ImageRenderer and read back the same way as the snapshots.
    /// The color read back can differ a little from the hex value, so the tests compare against this.
    func reference(_ hex: UInt32) throws -> (r: Int, g: Int, b: Int) {
        let renderer = ImageRenderer(content: Color(hex: hex).frame(width: 10, height: 10))
        renderer.scale = CGFloat(Snapshot.scale)
        let image = try #require(renderer.cgImage)
        return Snapshot(bitmap: NSBitmapImageRep(cgImage: image)).rgb(5, 5)
    }

    func near(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Bool {
        abs(a.r - b.r) < 12 && abs(a.g - b.g) < 12 && abs(a.b - b.b) < 12
    }

    @Test func login() throws {
        var s = AppState()
        s.restoring = false
        let shot = try render(s, "login")
        #expect(shot.isBlue(175, Self.rowCenter(0) + 77))  // "Log in with Spotify" is selected, under the words (card AX)
        let headerTop = shot.rgb(50, 34), want = try reference(0xffffff)
        #expect(near(headerTop, want), "header top \(headerTop)")  // no glass shadow over the header
        #expect(shot.isLight(150, 42))  // the header, right of the title
        let bezel = shot.rgb(Self.screenLeft - 3, 120), dark = try reference(0x2a2c2e)
        #expect(near(bezel, dark), "bezel \(bezel)")  // the dark bezel left of the screen (card BH, change 239)
    }

    @Test func mainMenuShowsCoversOnTheRight() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:2")
        s.isPlaying = true
        s.top.sel = 1
        s.artRow = .nowPlaying
        s.refreshArt()
        let shot = try render(s, "main")
        // A 150 point pane (x 33 to 183) with 9 rows of 22.9 and no bar.
        #expect(shot.isLight(125, Self.rowCenter(0)))  // right of "Now Playing"
        #expect(shot.isBlue(125, Self.rowCenter(1)))
        // On the right, the playing track's cover: no image is loaded, so the blue-grey square.
        // Its gradient runs from d5dee8 at the top to a9b8c8 at the bottom; the point is low in it.
        let art = shot.rgb(Self.screenLeft + 170, Self.screenTop + 191)  // past the pane's shadow, 85 % down
        let want = try reference(0xb0bece)
        #expect(near(art, want), "art \(art), want \(want)")

        s.albumArt = .off  // Album Art off: a full-width list, with no covers
        let plain = try render(s, "main-no-art")
        #expect(plain.isBlue(Self.screenLeft + 170, Self.rowCenter(1)))
        s.albumArt = .nowPlaying  // the cover on Now Playing only: the menu is full width too
        let nowOnly = try render(s, "main-now-playing-art")
        #expect(nowOnly.isBlue(Self.screenLeft + 170, Self.rowCenter(1)))
    }

    /// Build 308: the 3D front's picture of the main menu shows the loaded cover. It used to
    /// show SwiftUI's yellow box with a red "no" sign, because it cannot draw the AppKit cover.
    @Test func theThreeDFrontsPictureShowsTheCover() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:2")
        s.isPlaying = true
        s.artRow = .nowPlaying
        s.refreshArt()
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0.6, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let green = try #require(context.makeImage())
        let image = try #require(K3DSpike.snapshot(s, artwork: Artwork { _ in green }))
        let shot = Snapshot(bitmap: NSBitmapImageRep(cgImage: image))
        let art = shot.rgb(Self.screenLeft + 170, Self.screenTop + 191)
        #expect(art.g > art.r + 60 && art.g > art.b + 60, "art \(art)")
    }

    @Test func mainArtCrossfadesWithNoDarkDip() {
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        let pose = { (t: Double, i: Int) in MainArt.pose(at: t, index: i, count: 4) }
        #expect(pose(0, 0).opacity == 1 && pose(0, 3).opacity == 0)  // a cover at once
        #expect(MainArt.slot == 6.8 && MainArt.fade == 0.6)  // as on the device
        #expect(close(pose(6.5, 1).opacity, 0.5))  // the second cover fades in
        #expect(pose(6.5, 0).opacity == 1)  // and the first stays fully shown under it
        #expect(pose(6.5, 1).order > pose(6.5, 0).order)
        #expect(pose(7.5, 0).opacity == 0 && pose(7.5, 1).opacity == 1)
        #expect(close(pose(26.9, 0).opacity, 0.5) && pose(26.9, 3).opacity == 1)  // the loop wraps on top too
        let later = pose(3 + 4 * MainArt.slot, 2)  // a 27.2 s loop
        #expect(close(pose(3, 2).opacity, later.opacity) && close(pose(3, 2).order, later.order))
        for t in stride(from: 0.0, to: 40, by: 0.25) {
            #expect(MainArt.pose(at: t, index: 0, count: 1).opacity == 1)  // one cover always shows
        }
    }

    @Test func mainArtPansLeftThenRightAndDownWithNoEdge() {
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        // Where each of 10 covers in a row starts and ends its pan, with 3 covers in the loop.
        // (6.8 is not exact in binary, so it asks in the middle of each turn, not at its ends.)
        let moves = (0..<10).map { n -> (x: Double, y: Double) in
            let m = MainArt.motion(at: Double(n) * MainArt.slot + 1, index: n % 3, count: 3)
            return (m.to.x - m.from.x, m.to.y - m.from.y)
        }
        let travel = MainArt.panSpeed * (MainArt.slot + MainArt.fade)
        #expect(abs(travel - 49.58) < 1e-9)
        for n in 0..<10 {
            if n % 2 == 0 {  // left only, also across the loop
                #expect(close(moves[n].x, -travel) && moves[n].y == 0)
            } else {  // right and down, on a diagonal
                #expect(close(moves[n].x, travel) && close(moves[n].y, MainArt.drop))
            }
        }
        // The cover is 250 points in the 150 x 225 panel, so the pan never shows an edge.
        #expect(MainArt.coverSide == 250 && MainArt.drop == 25)
        // A down turn goes from 12.5 points up to 12.5 points down, the whole margin (card AL).
        let down = MainArt.motion(at: MainArt.slot + 1, index: 1, count: 3)
        #expect(down.from.y == -12.5 && down.to.y == 12.5)
        for i in 0..<3 {
            for t in stride(from: 0.0, to: 48, by: 0.25) {
                let f = MainArt.pose(at: t, index: i, count: 3)
                #expect(abs(f.dx) <= (MainArt.coverSide - Pocket.paneWidth) / 2)
                #expect(abs(f.dy) <= (MainArt.coverSide - Pocket.screenHeight) / 2)
            }
        }
        // Constant speed: equal time steps move the same distance, at `panSpeed`.
        let a = MainArt.pose(at: 2, index: 0, count: 3).dx, b = MainArt.pose(at: 3, index: 0, count: 3).dx
        let c = MainArt.pose(at: 4, index: 0, count: 3).dx
        #expect(abs((b - a) - (c - b)) < 1e-12 && abs(abs(b - a) - MainArt.panSpeed) < 1e-9)
    }

    @Test func mainMenuShowsALoadedCoverAtOnceAndNoDarkDip() throws {
        let red = try #require(Self.solidImage(red: 1, green: 0, blue: 0))
        let blue = try #require(Self.solidImage(red: 0, green: 0, blue: 1))
        let a = String(repeating: "aa", count: 20), b = String(repeating: "bb", count: 20)
        var s = sampleState()
        s.library[0].tracks = [
            Track(id: "spotify:track:a", title: "A", artist: "x", duration: 200, coverID: a),
            Track(id: "spotify:track:b", title: "B", artist: "y", duration: 200, coverID: b),
        ]
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:a")
        s.mainArt = s.library[0].tracks  // the playing cover first, then one more
        let art = Artwork { $0 == a ? red : $0 == b ? blue : nil }
        let point = (Self.screenLeft + 190, Self.listTop + 90)
        let first = try render(s, "main-art-first", artwork: art, time: 0)
        let c = first.rgb(point.0, point.1)
        #expect(c.r > 150 && c.b < 100, "first frame \(c)")  // the playing track's cover, fully shown
        let mid = try render(s, "main-art-fade", artwork: art, time: MainArt.slot - MainArt.fade / 2)
        let m = mid.rgb(point.0, point.1)
        #expect(m.r > 90 && m.b > 90, "mid fade \(m)")  // red under half blue: no dark dip
    }

    @Test func theMainArtPanKeepsItsStartWithinATurn() {
        // Within one cover's turn the pan is the same value, so a view update never restarts it.
        let first = MainArt.motion(at: 0.5, index: 1, count: 3)
        #expect(first == MainArt.motion(at: 5, index: 1, count: 3))
        // The next turn of the same layer is a new pan, in the other direction (3 covers: odd turns).
        let next = MainArt.motion(at: 0.5 + 3 * MainArt.slot, index: 1, count: 3)
        #expect(next.turn == first.turn + 3 && next.from.x == -first.from.x)
        #expect(abs(next.start - (first.start + 3 * MainArt.slot)) < 1e-9)
        // Every frame of a turn gives the same value, also at a large time with rounding errors.
        let late = MainArt.motion(at: 992.3, index: 2, count: 8)  // shown from 992.2 to 999.6
        for frame in 1...195 {
            #expect(MainArt.motion(at: 992.3 + Double(frame) / 30, index: 2, count: 8) == late)
        }
        // The pose follows the same pan, at a constant speed from `from` to `to`.
        let m = MainArt.motion(at: 9, index: 1, count: 3)
        let span = MainArt.slot + MainArt.fade
        for t in stride(from: m.start + 0.05, through: m.start + span - 0.05, by: 0.5) {
            let f = MainArt.pose(at: t, index: 1, count: 3), q = (t - m.start) / span
            #expect(abs(f.dx - (m.from.x + (m.to.x - m.from.x) * q)) < 1e-9)
            #expect(abs(f.dy - (m.from.y + (m.to.y - m.from.y) * q)) < 1e-9)
        }
    }

    @Test func aLargeCoverShowsOnlyFromTheTurnAfterItLoads() {
        let track = ClasifyCore.Track(id: "t", title: "", artist: "", duration: 1, coverID: "small", largeCoverID: "large")
        let loadsAt = 3.0  // the large cover arrives 3 s after the menu opens (time 0)
        // The choice for layer 0 of 2 at time t, with the turn start that the view uses.
        func pick(_ t: Double, loaded: Bool = true) -> String? {
            let turnStart = MainArt.motion(at: t, index: 0, count: 2).start
            return MainArt.coverID(for: track, turnStart: turnStart, loaded: { _ in loaded }, loadedAt: { _ in loadsAt })
        }
        // Layer 0's first turn runs from -0.6 s to 6.8 s: the large cover arrives during it,
        // so every frame of that turn keeps the default cover. No change while it shows.
        for frame in 0..<(6 * 30) { #expect(pick(Double(frame) / 30) == "small") }
        // Its next turn starts at 13.0 s, after the load: the large cover, for the whole turn
        // (from just after its start, because 13.6 is not exact in binary).
        for frame in 0..<(6 * 30) { #expect(pick(13.05 + Double(frame) / 30) == "large") }
        #expect(pick(14, loaded: false) == "small")  // not in memory: the default cover
        let none = ClasifyCore.Track(id: "t", title: "", artist: "", duration: 1, coverID: "small")
        #expect(MainArt.coverID(for: none, turnStart: 99, loaded: { _ in true }, loadedAt: { _ in 0 }) == "small")
    }

    /// Card AM: a line that is too long is cut, not ended with "…", and its last 22 points fade.
    /// A line that fits is drawn as it is, with no mask.
    @Test func aLongLineIsCutAndFadesAndAShortLineIsPlain() throws {
        func shot(_ view: some View) throws -> NSBitmapImageRep {
            let framed = view.font(.helvetica(13, bold: true)).foregroundStyle(Color.black)
                .frame(width: 100, height: 20, alignment: .leading).background(Color.white)
            let renderer = ImageRenderer(content: framed)
            renderer.scale = CGFloat(Snapshot.scale)
            return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        }
        /// The darkness of the pixel columns from point `from` to point `to`.
        func ink(_ b: NSBitmapImageRep, _ from: Int, _ to: Int) -> Double {
            var sum = 0.0
            for x in from * Snapshot.scale..<to * Snapshot.scale {
                for y in 0..<b.pixelsHigh {
                    let c = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .white
                    sum += 3 - (c.redComponent + c.greenComponent + c.blueComponent)
                }
            }
            return sum
        }
        let long = "Bohemian Rhapsody Remastered 2011 Version"
        let faded = try shot(FadeLine(Text(long)))
        // The same text, cut at the edge with no fade and no "…".
        let cut = try shot(Text(long).lineLimit(1).fixedSize().frame(width: 100, alignment: .leading).clipped())
        let fadeStart = 100 - Int(FadeMask.width)
        // Before the fade, the same pixels as the cut text: no "…" and no other layout.
        #expect(abs(ink(faded, 0, fadeStart) - ink(cut, 0, fadeStart)) < 0.5)
        // In the fade, much lighter than the cut text, and almost clear at the very end.
        #expect(ink(faded, fadeStart, 100) < ink(cut, fadeStart, 100) * 0.7)
        #expect(ink(faded, 98, 100) < ink(cut, 98, 100) * 0.2 + 0.5)
        // A short line: the same pixels as plain text, so no mask.
        let short = try shot(FadeLine(Text("Abbey Road")))
        let plain = try shot(Text("Abbey Road"))
        #expect(abs(ink(short, 0, 100) - ink(plain, 0, 100)) < 0.5)
    }

    @Test func thePanningCoverMovesItsLayerWithCoreAnimation() throws {
        let image = try #require(Self.solidImage(red: 1, green: 0, blue: 0))
        let view = PanView(frame: NSRect(x: 0, y: 0, width: 116, height: 180))
        let m = MainArt.motion(at: 0, index: 0, count: 3)
        view.update(image: image, side: MainArt.coverSide, pan: m, elapsed: 0)
        view.layout()
        #expect(view.cover.bounds.size == CGSize(width: 250, height: 250))
        #expect(view.cover.position == CGPoint(x: 58, y: 90))
        let move = try #require(view.cover.animation(forKey: "pan") as? CABasicAnimation)
        #expect(move.keyPath == "position")
        #expect((move.fromValue as? NSValue)?.pointValue == NSPoint(x: 58 + m.from.x, y: 90 - m.from.y))
        #expect((move.toValue as? NSValue)?.pointValue == NSPoint(x: 58 + m.to.x, y: 90 - m.to.y))
        #expect(move.duration == MainArt.slot + MainArt.fade)
        // A right-and-down turn: the layer's y goes up, so the cover moves to a lower y.
        let diagonal = MainArt.motion(at: MainArt.slot, index: 1, count: 3)
        view.update(image: image, side: MainArt.coverSide, pan: diagonal, elapsed: 0)
        view.layout()
        let down = try #require(view.cover.animation(forKey: "pan") as? CABasicAnimation)
        let from = try #require((down.fromValue as? NSValue)?.pointValue)
        let to = try #require((down.toValue as? NSValue)?.pointValue)
        #expect(to.x > from.x && to.y < from.y)
        // Reduce Motion: no animation, the cover stays at the center.
        view.update(image: image, side: MainArt.coverSide, pan: nil, elapsed: 0)
        view.layout()
        #expect(view.cover.animation(forKey: "pan") == nil)
    }

    @Test func aMissingMainArtCoverShowsTheOneBeforeIt() {
        #expect(MainArt.filled([nil, "A", nil, "B"]) == ["B", "A", "A", "B"])
        #expect(MainArt.filled([String?]([nil, nil])) == [nil, nil])  // all nil stays nil
        #expect(MainArt.sources([false, true, false]) == [1, 1, 1])
    }

    @Test func aLateCoverDoesNotCutTheMainArt() throws {
        let red = try #require(Self.solidImage(red: 1, green: 0, blue: 0))
        let blue = try #require(Self.solidImage(red: 0, green: 0, blue: 1))
        let a = String(repeating: "aa", count: 20), b = String(repeating: "bb", count: 20)
        var s = sampleState()
        s.mainArt = [
            Track(id: "spotify:track:a", title: "A", artist: "x", duration: 200, coverID: a),
            Track(id: "spotify:track:b", title: "B", artist: "y", duration: 200, coverID: b),
        ]
        let point = (Self.screenLeft + 190, Self.listTop + 90)
        // Only the second cover is loaded: it stands in for the first, not the square.
        let early = try render(s, "main-art-late", artwork: Artwork { $0 == b ? blue : nil }, time: 0)
        let e = early.rgb(point.0, point.1)
        #expect(e.b > 150 && e.r < 100, "stand-in \(e)")
        let loaded = try render(s, "main-art-loaded", artwork: Artwork { $0 == a ? red : $0 == b ? blue : nil }, time: 0)
        let l = loaded.rgb(point.0, point.1)
        #expect(l.r > 150 && l.b < 100, "own cover \(l)")
    }

    @Test func aRowChangeSwitchesTheMainArtOnlyWhenItCanShowACover() {
        let loaded: (String?) -> Bool = { $0 == "a" || $0 == "b" }
        #expect(!MainArtPanel.switches(to: ["a"], from: ["a"], loaded: loaded))  // same covers
        #expect(MainArtPanel.switches(to: ["b", "x"], from: ["a"], loaded: loaded))  // a new cover is loaded
        #expect(!MainArtPanel.switches(to: ["x"], from: ["a"], loaded: loaded))  // keep the shown cover
        #expect(MainArtPanel.switches(to: ["x"], from: ["y"], loaded: loaded))  // nothing shows anyway
    }

    @Test func aScreenChangePushesTheOldScreenOutTheOtherSide() {
        // Forward: the new screen comes from the right, and the old one goes out to the left.
        #expect(Push.offset(side: 1, forward: true) == 1)
        #expect(Push.offset(side: -1, forward: true) == -1)
        // Back: the mirror.
        #expect(Push.offset(side: 1, forward: false) == -1)
        #expect(Push.offset(side: -1, forward: false) == 1)
        #expect(Push.offset(side: 0, forward: true) == 0 && Push.offset(side: 0, forward: false) == 0)
    }

    @Test func aLongSelectedLabelScrolls() throws {
        var s = sampleState()
        let name = "The Longest Road Trip Playlist Ever Made"  // 40 characters: 296 points, a 14 s loop
        s.library.append(Playlist(id: "spotify:playlist:c", name: name, tracks: []))
        s.stack.append(Frame(screen: .playlists))
        s.top.sel = 2
        let loop = Labels.marqueeLoop(name)
        let still = try render(s, "marquee-start")  // 1 s: the hold at the start
        let moved = try render(s, "marquee-moved", time: loop * 0.59)  // half of one copy's width
        func changed(_ y: Int) -> Int {
            stride(from: Self.screenLeft + 12, to: Self.screenLeft + 230, by: 1)
                .filter { still.rgb($0, y) != moved.rgb($0, y) }.count
        }
        #expect(changed(Self.rowCenter(2)) > 10)  // the selected label moved
        #expect(changed(Self.rowCenter(0)) == 0)  // the other rows stay still
        #expect(Marquee.shift(at: 1, loop: 14) == 0)
        #expect(abs(Marquee.shift(at: 14 * 0.59, loop: 14) - 0.5) < 1e-9)
        #expect(Marquee.shift(at: 15, loop: 14) == 0)  // it loops
        // With "Road Trip" selected: it fits, so it stays still, and the long label is cut and stays still.
        s.top.sel = 0
        let a = try render(s, "marquee-unselected"), b = try render(s, "marquee-unselected-later", time: loop * 0.59)
        for row in [0, 2] {
            #expect((Self.screenLeft + 12 ..< Self.screenLeft + 230).allSatisfy { a.rgb($0, Self.rowCenter(row)) == b.rgb($0, Self.rowCenter(row)) })
        }
    }

    @Test func fiveSongRowsFillTheList() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))
        s.top.sel = 4
        let shot = try render(s, "tracks-last-row")
        #expect(shot.isBlue(100, Self.rowCenter(4, songs: true)))  // the 5th row ends at the screen's bottom
        #expect(shot.isBlue(100, Self.screenBottom - 2))
        #expect(!shot.isBlue(100, Self.rowCenter(3, songs: true)))
    }

    @Test func onlyTheSelectedRowShowsAChevron() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .settings))
        s.top.sel = 8  // About; Log out under it also opens a screen
        let shot = try render(s, "settings-chevron")
        // The chevron is 8 points wide, 10 points in from the right edge of the list.
        let xs = Self.screenLeft + Self.screenWidth - 20...Self.screenLeft + Self.screenWidth - 8
        func box(_ row: Int) -> [(Int, Int)] {
            let c = Self.rowCenter(row)
            return xs.flatMap { x in (c - 5...c + 5).map { (x, $0) } }
        }
        #expect(box(8).contains { shot.isLight($0.0, $0.1) })  // a white chevron on the blue row
        // Card AN.1: Menu Bar shows "On" where a chevron goes, so About is checked unselected.
        s.top.sel = 7
        let off = try render(s, "settings-chevron-off")
        #expect(box(8).allSatisfy { off.isLight($0.0, $0.1) })  // no chevron on About
    }

    @Test func songListShowsArtistsAndTheScrollBar() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))
        s.scrollUntil = 1  // a wheel step or a screen change just happened
        let shot = try render(s, "tracks")
        #expect(shot.isBlue(100, Self.rowCenter(0, songs: true)))
        // The second row (41.2 points, no bar) is not selected. Its lower half holds the gray artist line, "Band 2".
        let top = Self.listTop + 41
        let artist = (top + 21...top + 35).contains { y in
            (Self.screenLeft + 10...Self.screenLeft + 50).contains { x in
                let c = shot.rgb(x, y)
                return max(c.r, c.g, c.b) < 185  // the detail gray #9ba3ad
            }
        }
        #expect(artist)
        let thumbX: Int = Self.screenLeft + Self.screenWidth - 4, thumbY: Int = Self.listTop + 8
        let thumb = shot.rgb(thumbX, thumbY), want = try reference(0x5d6772)
        #expect(near(thumb, want), "thumb \(thumb), want \(want)")
        // There is no track: under the thumb, the bar's place shows the row, as 6 points to its left.
        let below = Self.listTop + 150
        let bar = shot.rgb(thumbX, below), row = shot.rgb(thumbX - 6, below)
        #expect(near(bar, row), "bar \(bar), row \(row)")
    }

    /// Round 10 card AI: the lines between two-line rows sit on the pixel grid, so they all have
    /// the same thickness, though the rows are 41.2 points tall. Read in pixels at 2x.
    @Test func rowDividersAreEquallyThick() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))  // row 0 selected, no bar
        let shot = try render(s, "tracks-dividers")
        let px = Snapshot.scale, x = (Self.screenLeft + 250) * px  // right of the short labels
        func value(_ y: Int) -> Int {
            let c = shot.bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .clear
            return Int((c.redComponent + c.greenComponent + c.blueComponent) * 255)
        }
        // The rows end at 51.4 + 41.2 k points. Under rows 1, 2 and 3 (not selected), count the
        // pixels that are darker than the glass 4 pixels above them.
        let thickness = [2, 3, 4].map { k -> Int in
            let bottom = Int((51.4 + 41.2 * Double(k)) * Double(px))
            return (bottom - 6...bottom + 2).filter { value($0) <= value($0 - 4) - 4 }.count
        }
        #expect(thickness.allSatisfy { $0 > 0 }, "thickness \(thickness)")
        #expect(Set(thickness).count == 1, "thickness \(thickness)")
    }

    @Test func theScrollBarHidesWhenTheListIsStill() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))
        let shot = try render(s, "tracks-still")
        let thumbX: Int = Self.screenLeft + Self.screenWidth - 4, thumbY: Int = Self.listTop + 8
        #expect(shot.isBlue(thumbX, thumbY))  // the selected row's blue, with no thumb over it
    }

    @Test func albumsIsAHalfScreenOfTwoLineRows() throws {
        var s = sampleState()
        s.library[0].tracks[0].album = Album(id: "spotify:album:p", name: "Kala", artist: "M.I.A.")
        s.library[0].tracks[1].album = Album(id: "spotify:album:s", name: "Speakerboxxx/The Love Below", artist: "OutKast")
        s.stack.append(Frame(screen: .albums))
        s.top.sel = 1
        let shot = try render(s, "albums")
        #expect(shot.isBlue(Self.screenLeft + 60, Self.rowCenter(1, songs: true)))  // the second two-line row
        #expect(!shot.isBlue(Self.screenLeft + 60, Self.rowCenter(0, songs: true)))
    }

    @Test func coverFlowPosesFollowTheMockup() {
        // Card AE.1 (change 127): 68 points out, turned 61°, scaled to 0.63. No darkening.
        #expect(CoverFlowStrip.pose(0) == .init(x: 0, angle: 0, scale: 1, opacity: 1))
        #expect(CoverFlowStrip.pose(1) == .init(x: 68, angle: -61, scale: 0.63, opacity: 1))
        let half = CoverFlowStrip.pose(-0.5)
        #expect(half.x == -34 && half.angle == 30.5 && abs(half.scale - 0.815) < 1e-9 && half.opacity == 1)
        let far = CoverFlowStrip.pose(-3)  // the stack: 27 points apart past the first cover
        #expect(far.x == -122 && far.angle == 61 && abs(far.scale - 0.63) < 1e-9)
        #expect(CoverFlowStrip.pose(7).opacity == 0 && abs(CoverFlowStrip.pose(6.5).opacity - 0.5) < 1e-9)
    }

    /// Card AE.1 (change 129): a side cover's 1 point edge shows just outside its outer side,
    /// wide enough to see, and it does not cover the face.
    @Test func theCoverEdgeShowsOutsideTheFace() {
        func project(_ m: CATransform3D, _ x: CGFloat, _ y: CGFloat) -> CGFloat {
            (x * m.m11 + y * m.m21 + m.m41) / (x * m.m14 + y * m.m24 + m.m44)
        }
        let p = CoverFlowStrip.pose(1)
        let face = TurnY.matrix(angle: p.angle, scale: p.scale)
        let edge = CoverEdge.matrix(side: 1, angle: p.angle, scale: p.scale)
        let outer = project(face, 120, 60), inner = project(face, 0, 60)
        let a = project(edge, 0, 60), b = project(edge, 1, 60)
        #expect(abs(a - outer) < 1e-6, "the strip starts on the face's edge")
        #expect(b - a > 0.5 && b - a < 3, "strip \(a) to \(b)")
        #expect(inner < outer)  // the strip is beyond the outer side
        // The left side mirrors it.
        let q = CoverFlowStrip.pose(-1)
        let left = CoverEdge.matrix(side: -1, angle: q.angle, scale: q.scale)
        let leftFace = TurnY.matrix(angle: q.angle, scale: q.scale)
        let la = project(left, 1, 60), lb = project(left, 0, 60)
        #expect(abs(la - project(leftFace, 0, 60)) < 1e-6 && la - lb > 0.5 && la - lb < 3, "left \(lb) to \(la)")
    }

    @Test func theDoorsFollowTheMockupTimes() {
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
        // `side` runs linearly over 0.5 s on the way in and 0.35 s on the way back.
        let opening = { (t: Double) in DoorsStage(side: -t / DoorsStage.openTime, forward: true) }
        let behind = { (t: Double) in DoorsStage(side: 1 - t / DoorsStage.openTime, forward: true) }
        #expect(close(opening(0).open, 0))  // closed at the press
        #expect(opening(0.125).open > 0 && opening(0.125).open < 0.5)  // speeding up
        #expect(close(opening(0.25).open, 1) && close(opening(0.3).open, 1))  // open after 0.25 s
        #expect(behind(0).headerY == -20 && behind(0).names == 0)  // Cover Flow: no title bar, no names
        #expect(behind(0.19).names == 0 && close(behind(0.25).names, 0.5) && close(behind(0.3).names, 1))
        // The title bar waits until the doors are open, then slides down, quick at first (CLA-73).
        #expect(close(behind(0.25).headerY, -20) && behind(0.26).headerY > -20)
        #expect(behind(0.375).headerY > -10 && behind(0.45).headerY < 0)
        #expect(close(behind(0.5).headerY, 0) && close(behind(0.5).open, 0))
        // MENU: the names go at once, the title bar goes up in 0.1 s, then the doors close.
        let leaving = { (t: Double) in DoorsStage(side: -t / DoorsStage.closeTime, forward: false) }
        let closing = { (t: Double) in DoorsStage(side: 1 - t / DoorsStage.closeTime, forward: false) }
        #expect(leaving(0).names == 1 && close(leaving(0).headerY, 0) && leaving(0.01).names == 0)
        #expect(close(leaving(0.1).headerY, -20))
        #expect(close(closing(0).open, 1) && close(closing(0.1).open, 1))  // open until 0.1 s
        #expect(closing(0.2).open < 0.5)  // quick at first, slowing down at the end
        #expect(close(closing(0.35).open, 0))
    }

    /// On the way in, a new copy of the main menu opens its doors over Cover Flow (CLA-63). Here
    /// it is drawn alone at fixed stages, so the gap between the doors is empty.
    @Test func theMainMenuDoorsOpenAsTheirOwnLayer() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:2")
        s.top.sel = 1
        s.artRow = .nowPlaying
        s.refreshArt()
        func doors(_ open: Double, _ name: String) throws -> NSBitmapImageRep {
            var stage = DoorsStage()
            stage.open = open
            let view = PocketScreen(state: s, doorsOnly: true)
                .environment(\.doorsStage, stage)
                .environment(\.animationTime, 1)
                .frame(width: Pocket.screenWidth, height: Pocket.screenHeight)
                .clipped()
            let renderer = ImageRenderer(content: view)
            renderer.scale = CGFloat(Snapshot.scale)
            let image = try #require(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
               let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pocket-\(name).png"))
            }
            return bitmap
        }
        func alpha(_ b: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
            b.colorAt(x: x * Snapshot.scale, y: y * Snapshot.scale)?.alphaComponent ?? 0
        }
        let closed = try doors(0, "doors-closed")
        #expect(alpha(closed, 40, 100) > 0.9 && alpha(closed, 150, 100) > 0.9 && alpha(closed, 240, 100) > 0.9)
        // Half open: the pane is 75 points left at half opacity, the covers 75 points right.
        let half = try doors(0.5, "doors-half-open")
        #expect(alpha(half, 150, 100) < 0.1, "gap \(alpha(half, 150, 100))")
        #expect(alpha(half, 240, 100) > 0.9)
        let pane = alpha(half, 40, 100)
        #expect(pane > 0.3 && pane < 0.7, "pane \(pane)")
    }

    @Test func coverFlowShowsTheMiddleAlbumAndTheLetter() throws {
        let red = try #require(Self.solidImage(red: 1, green: 0, blue: 0))
        let blue = try #require(Self.solidImage(red: 0, green: 0, blue: 1))
        var s = sampleState()
        let names = ["Aja", "Blue", "Clouds", "Dark Side", "Eno"]
        s.library[0].tracks = names.enumerated().map { i, name in
            Track(id: "t\(i)", title: "t\(i)", artist: "a", duration: 100, coverID: "c\(i)",
                  album: Album(id: "spotify:album:\(i)", name: name, artist: "Artist \(i)"))
        }
        s.stack.append(Frame(screen: .coverFlow))
        s.top.sel = 2  // Clouds
        let art = Artwork { $0 == "c2" ? red : blue }
        let shot = try render(s, "cover-flow", artwork: art)
        // The middle cover is 120 points, 22 points under the header: its center is at 150, 82.
        let middle = shot.rgb(Self.screenLeft + 150, Self.listTop + 82)
        #expect(middle.r > 200 && middle.b < 60, "middle \(middle)")
        // The covers next to it turn toward it, 68 points to each side.
        for x in [150 - 72, 150 + 72] {
            let side = shot.rgb(Self.screenLeft + x, Self.listTop + 82)
            #expect(side.b > 150 && side.r < 60, "side \(side)")
        }
        // The album name, bold black, on the line at 164.
        #expect((100...200).contains { shot.isDark(Self.screenLeft + $0, Self.listTop + 172) })

        // A fast spin: the big letter box over the middle cover, dark over the red.
        s.letterUntil = 1
        let spin = try render(s, "cover-flow-letter", artwork: art)
        let box = spin.rgb(Self.screenLeft + 125, Self.listTop + 57)
        #expect(spin.isDark(Self.screenLeft + 125, Self.listTop + 57), "box \(box)")
        #expect(!shot.isDark(Self.screenLeft + 125, Self.listTop + 57))
    }

    @Test func theSongPanelFollowsTheMockup() {
        #expect(AlbumPanel.height(songs: 1) == 188 && AlbumPanel.height(songs: 6) == 188)  // the smallest panel
        #expect(AlbumPanel.height(songs: 7) == 197 && AlbumPanel.height(songs: 14) == 197)  // then it scrolls
        // The rows move up by whole rows, but the last row stops at the panel's bottom.
        #expect(AlbumPanel.scroll(off: 1, songs: 9, height: 197) == 23)
        #expect(AlbumPanel.scroll(off: 3, songs: 9, height: 197) == 51)  // 9 x 23 - 156
        #expect(AlbumPanel.scroll(off: 0, songs: 3, height: 188) == 0)
        #expect(AlbumPanel.thumb(track: 152, songs: 6, scroll: 0, height: 188) == nil)  // all rows fit
        let thumb = AlbumPanel.thumb(track: 152, songs: 9, scroll: 51, height: 197)
        #expect(thumb.map { abs($0.length + $0.offset - 152) < 1e-9 } == true)  // at the end of the track
        // The side covers move 44 points out; the middle one stays.
        #expect(CoverFlowStrip.pose(1, spread: 1).x == 112 && CoverFlowStrip.pose(-2, spread: 0.5).x == -117)
        #expect(CoverFlowStrip.pose(0, spread: 1).x == 0)
    }

    @Test func coverFlowSongPanel() throws {
        var s = sampleState()
        let clouds = Album(id: "spotify:album:c", name: "Clouds", artist: "Joni Mitchell")
        s.library[0].tracks = (0..<9).map { i in
            Track(id: "t\(i)", title: "Song \(i)", artist: "Joni Mitchell", duration: 200, album: clouds)
        }
        s.stack.append(Frame(screen: .coverFlow))
        s.stack.append(Frame(screen: .albumPanel(album: "spotify:album:c")))
        s.top.sel = 1
        let shot = try render(s, "cover-flow-panel")
        // The blue top bar, 9 points under the title bar and 41 tall.
        let bar = shot.rgb(Self.screenLeft + 150, Self.listTop + 9 + 30)
        #expect(bar.b > bar.r + 30 && bar.b < 200, "bar \(bar)")
        // The second song is selected: our blue bar, at 9 + 41 + 23 + 11.5 under the title bar.
        #expect(shot.isBlue(Self.screenLeft + 150, Self.listTop + 9 + 41 + 23 + 11))
        #expect(!shot.isBlue(Self.screenLeft + 150, Self.listTop + 9 + 41 + 11))
        // 28 points from each side, the Cover Flow glass shows beside the panel.
        #expect(shot.isLight(Self.screenLeft + 10, Self.listTop + 120))
    }

    /// CLA-46: while the album loads, the panel shows with its top bar, and the loading
    /// message is inside it, not in place of Cover Flow.
    @Test func coverFlowSongPanelWhileItLoads() throws {
        var s = sampleState()
        let clouds = Album(id: "spotify:album:c", name: "Clouds", artist: "Joni Mitchell")
        s.library[0].tracks = [Track(id: "t0", title: "Song 0", artist: "Joni Mitchell", duration: 200, album: clouds)]
        s.stack.append(Frame(screen: .coverFlow))
        s.stack.append(Frame(screen: .albumPanel(album: "spotify:album:c"), loading: true, token: 1))
        let shot = try render(s, "cover-flow-panel-loading")
        let bar = shot.rgb(Self.screenLeft + 150, Self.listTop + 9 + 30)
        #expect(bar.b > bar.r + 30 && bar.b < 200, "bar \(bar)")
        // No song row: the liked song does not show while the whole album loads.
        #expect(!shot.isBlue(Self.screenLeft + 150, Self.listTop + 9 + 41 + 11))
        #expect(shot.isLight(Self.screenLeft + 10, Self.listTop + 120))  // the glass beside the panel
        let loading = AlbumPanel.Shown(s)
        #expect(loading?.message?.title == "Loading…" && loading?.text(in: s).songs.isEmpty == true)
    }

    @Test func theCoverFliesFromThePanelToNowPlayingsCover() {
        let size = CGSize(width: 244, height: 197)
        func at(_ fly: Double, _ p: CGPoint) -> CGPoint { p.applying(FlyEffect(fly: fly).effectValue(size: size)) }
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01 }
        // At the start the card is the panel, turned over: its left edge is on the right.
        #expect(near(at(0, .zero), CGPoint(x: 244, y: 0)))
        // At the end it is Now Playing's 126.6 point cover, with the photo's tilt, at (9, 14.6):
        // 19 points left of and 5.6 under the panel's top left (28, 9).
        #expect(near(at(1, .zero), CGPoint(x: -19, y: 5.6)))
        let corner = CGPoint(x: 126.6, y: 126.6).applying(Tilt().effectValue(size: size))
        #expect(near(at(1, CGPoint(x: 244, y: 197)), CGPoint(x: corner.x - 19, y: corner.y + 5.6)))
    }

    @Test func nowPlayingOverTheSongPanelLooksLikeNowPlaying() throws {
        var s = sampleState()
        let album = Album(id: "spotify:album:h", name: "Hey", artist: "OutKast")
        s.library[0].tracks[1].album = album
        s.current = TrackRef(playlist: album.id, track: "spotify:track:2")
        s.isPlaying = true
        s.t = 61
        s.stack += [Frame(screen: .now)]
        let plain = try render(s, "now-plain")
        s.stack = [Frame(screen: .main), Frame(screen: .coverFlow), Frame(screen: .albumPanel(album: album.id)), Frame(screen: .now)]
        #expect(s.nowOverPanel)
        let over = try render(s, "now-over-panel")
        // The cover, the text and the bars are where the plain Now Playing has them.
        for (x, y) in [(16, 75), (70, 80), (150, 120), (150, 200), (250, 230)] {
            let a = plain.rgb(Self.screenLeft + x, y), b = over.rgb(Self.screenLeft + x, y)
            let diff: Int = abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
            #expect(diff < 30, "at \(x), \(y): \(a) vs \(b)")
        }
    }

    /// Card BN: Apple Music's main menu (7 rows), Playlists with Favorite Songs first, and
    /// Artists: one-line rows with no big letter.
    @Test func appleMusicLibraryScreens() throws {
        // A row is selected when most of the pane's width is blue: the white words cover only part of it.
        func selected(_ shot: Snapshot, _ row: Int) -> Bool {
            (Self.screenLeft + 3...Self.screenLeft + 147).filter { shot.isBlue($0, Self.rowCenter(row)) }.count > 60
        }
        var s = sampleState()
        s.service = .appleMusic; s.words = .appleMusic
        #expect(s.rows(for: s.top) == [.coverFlow, .playlists, .artists, .albums, .songs, .shuffleSongs, .settings])
        s.top.sel = 2
        let main = try render(s, "apple-main")
        #expect(selected(main, 2) && !selected(main, 1))
        #expect(main.isLight(125, Self.rowCenter(7)))  // no 8th row (the pane is 150 points wide)

        s.stack = [Frame(screen: .main), Frame(screen: .playlists)]
        s.stack[0].sel = 1
        s.playlistsLoaded = true
        #expect(s.rows(for: s.top).first == .playlist(Playlist.likedSongsID))
        let playlists = try render(s, "apple-playlists")
        #expect(selected(playlists, 0) && !selected(playlists, 1))

        s.artists = ["2Pac", "Low Orbit", "The Lowlights"].enumerated().map {
            Playlist(id: "applemusic:artist:\($0.offset)", name: $0.element, tracks: [])
        }
        s.artistsLoaded = true
        s.stack = [Frame(screen: .main), Frame(screen: .artists)]
        s.stack[0].sel = 2; s.top.sel = 1
        let artists = try render(s, "apple-artists")
        // One-line rows of 22.9 points, like the main menu: the 2nd row is selected, the 4th is empty.
        #expect(selected(artists, 1) && !selected(artists, 0))
        #expect(artists.isLight(125, Self.rowCenter(3)))
    }

    @Test func settings() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .settings))
        s.top.sel = 2
        let shot = try render(s, "settings")
        #expect(shot.isBlue(100, Self.rowCenter(2)))
        // The values on the right are bold blue; on the selected row, white on the blue selection.
        let right = (Self.screenLeft + Self.screenWidth - 52)...(Self.screenLeft + Self.screenWidth - 8)
        let rows = { (row: Int, test: (Int, Int) -> Bool) in
            right.contains { x in (-3...3).contains { dy in test(x, Self.rowCenter(row) + dy) } }
        }
        #expect(rows(0) { shot.isBlue($0, $1) })  // "Spotify" on the Service row (card BM)
        #expect(rows(2) { shot.isLight($0, $1) })  // the selected row's value
    }

    /// Card AN.1 (CLA-43, 346): the 10th row, "Menu Bar: On", after Now Playing Bar.
    @Test func settingsMenuBarRow() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .settings))
        s.top.sel = 7
        s.scrollUntil = 1  // 10 rows: the list scrolls, so a wheel step shows the scroll bar
        let shot = try render(s, "settings-menu-bar")
        #expect(shot.isBlue(100, Self.rowCenter(7)))
        #expect(!shot.isBlue(100, Self.rowCenter(6)))
        let thumbX: Int = Self.screenLeft + Self.screenWidth - 4, want = try reference(0x5d6772)
        #expect(near(shot.rgb(thumbX, Self.listTop + 8), want))  // the thumb starts at the top
    }

    /// Card AN.1: at Log out, the list has moved down one row and the thumb touches the bottom.
    @Test func settingsScrollsToLogOut() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .settings))
        s.top.sel = 9
        s.top.off = 1
        s.scrollUntil = 1
        let shot = try render(s, "settings-log-out")
        #expect(shot.isBlue(100, Self.rowCenter(8)))  // Log out, the last row on screen
        #expect(!shot.isBlue(100, Self.rowCenter(7)))  // About
        let thumbX: Int = Self.screenLeft + Self.screenWidth - 4, want = try reference(0x5d6772)
        #expect(near(shot.rgb(thumbX, Self.listTop + 200), want))  // the thumb's bottom
        #expect(!near(shot.rgb(thumbX, Self.listTop + 8), want))  // the thumb left the top
    }

    @Test func nowPlayingShowsTheCover() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:2")
        s.isPlaying = true
        s.t = 61
        s.stack.append(Frame(screen: .now))
        let shot = try render(s, "now")
        // The cover is not loaded, so it is the same blue-grey square as a track with no cover.
        // The tilted cover's top left is at 9 x 14.6 under the title bar; this point is 6 x 8 into it.
        let got = shot.rgb(Self.screenLeft + 16, 75), want = try reference(0xd5dee8)
        #expect(near(got, want), "cover \(got), want \(want)")
    }

    /// Round 8 card AA: a long title and artist are cut with a fade, not "…", and scroll once each
    /// in turn: the title first, then the artist. The playlist fits, so it stays still.
    @Test func longNowPlayingLinesFadeAndTakeTurns() throws {
        var s = sampleState()
        let title = "Everything You Wanted Before the Rain", artist = "Hana and the Static Orchestra"
        s.library[0].tracks.append(Track(id: "spotify:track:3", title: title, artist: artist, duration: 263))
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:3")
        s.stack.append(Frame(screen: .now))
        let titleWidth = NowLines.width(title, size: 15.1), artistWidth = NowLines.width(artist, size: 11.7)
        #expect(titleWidth > 141.4 && artistWidth > 141.4 && NowLines.width("Liked Songs", size: 11.7) < 141.4)
        let still = try render(s, "now-long")  // 1 s: the title's wait
        let titleMoves = try render(s, "now-long-title", time: 1.5 + Labels.nowScrollSeconds(width: titleWidth) / 2)
        let artistMoves = try render(
            s, "now-long-artist", time: Labels.nowTurn(width: titleWidth) + 1.5 + Labels.nowScrollSeconds(width: artistWidth) / 2)
        // The lines' middles, 19 points of title bar plus each line's top and half its size.
        let titleY = Self.screenTop + 19 + 44, artistY = Self.screenTop + 19 + 63, listY = Self.screenTop + 19 + 80
        let left = Self.screenLeft + 151, right = Self.screenLeft + Self.screenWidth - 8
        func changed(_ a: Snapshot, _ b: Snapshot, _ y: Int) -> Int {
            (left..<right).filter { x in (y - 4...y + 4).contains { a.rgb(x, $0) != b.rgb(x, $0) } }.count
        }
        #expect(changed(still, titleMoves, titleY) > 10)  // the title's turn
        #expect(changed(still, titleMoves, artistY) == 0)
        #expect(changed(still, artistMoves, titleY) == 0)  // the title waits at the start
        #expect(changed(still, artistMoves, artistY) > 10)  // the artist's turn
        #expect(changed(still, artistMoves, listY) == 0)
        // The title has ink in its middle, and none in the last 3 points of the fade.
        let ink = (left + 10..<right - 30).filter { x in (titleY - 6...titleY + 6).contains { still.isDark(x, $0) } }
        let edge = (right - 3..<right).filter { x in (titleY - 6...titleY + 6).contains { still.isDark(x, $0) } }
        #expect(ink.count > 20)
        #expect(edge.isEmpty, "dark at \(edge)")
    }

    @Test func aTrackWithNoCoverShowsTheBlueGreySquare() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")  // no cover ID
        s.stack.append(Frame(screen: .now))
        let shot = try render(s, "now-no-cover")
        // The cover's top left is at 9 x 14.6 under the title bar (y 66); this point is 6 x 8 into it.
        let got = shot.rgb(Self.screenLeft + 16, 75), want = try reference(0xd5dee8)
        #expect(near(got, want), "placeholder \(got), want \(want)")
    }

    @Test func nowPlayingShowsTheLoadedCover() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:2")
        s.stack.append(Frame(screen: .now))
        let red = try #require(Self.solidImage(red: 1, green: 0, blue: 0))
        let wanted = String(repeating: "ab", count: 20)
        let shot = try render(s, "now-cover", artwork: Artwork { $0 == wanted ? red : nil })
        let got = shot.rgb(Self.screenLeft + 77, 129)  // the middle of the tilted cover, where the notes were
        #expect(got.r > 200 && got.g < 60 && got.b < 60, "cover \(got)")
    }

    @Test func theLastCoverStaysWhileTheNextOneLoads() throws {
        let red = try #require(Self.solidImage(red: 1, green: 0, blue: 0))
        let blue = try #require(Self.solidImage(red: 0, green: 0, blue: 1))
        let last = CoverArt.Shown(coverID: "a", image: red)
        #expect(CoverArt.shown(fresh: blue, coverID: "b", pending: false, last: last) === blue)
        #expect(CoverArt.shown(fresh: nil, coverID: "b", pending: true, last: last) === red)  // no flash to the square
        #expect(CoverArt.shown(fresh: nil, coverID: "b", pending: false, last: last) == nil)  // no cover, or it failed
        #expect(CoverArt.shown(fresh: nil, coverID: nil, pending: false, last: last) == nil)  // the track has no cover
    }

    /// The cover dropped out of memory, and is not loading yet: the same cover stays.
    @Test func theSameCoverNeverBlinksToTheSquare() throws {
        let red = try #require(Self.solidImage(red: 1, green: 0, blue: 0))
        let last = CoverArt.Shown(coverID: "a", image: red)
        #expect(CoverArt.shown(fresh: nil, coverID: "a", pending: false, last: last) === red)
        #expect(CoverArt.shown(fresh: nil, coverID: "a", pending: true, last: last) === red)
        #expect(CoverArt.shown(fresh: nil, coverID: "a", pending: false, last: nil) == nil)
    }

    /// Repeat One adds a filled badge at the loop's lower left; Repeat All leaves that spot clear.
    /// Shuffle shows both arrowheads on the right.
    @Test func modeIconsDrawTheirShapes() throws {
        func shot(_ kind: ModeIcon.Kind) throws -> Snapshot {
            let view = ModeIcon(kind: kind).foregroundStyle(Color(hex: 0x4f5965)).background(ModeIcon.cut)
            let renderer = ImageRenderer(content: view)
            renderer.scale = CGFloat(Snapshot.scale)
            return Snapshot(bitmap: NSBitmapImageRep(cgImage: try #require(renderer.cgImage)))
        }
        let all = try shot(.repeatAll), one = try shot(.repeatOne), shuffle = try shot(.shuffle)
        let ink = try reference(0x4f5965), cut = try reference(0xedf2f6)
        func check(_ shot: Snapshot, _ x: Int, _ y: Int, _ want: (r: Int, g: Int, b: Int)) -> Bool {
            near(shot.rgb(x, y), want)
        }
        #expect(check(all, 2, 13, cut), "\(all.rgb(2, 13))")  // under the loop's bottom edge
        #expect(check(one, 2, 13, ink), "\(one.rgb(2, 13))")  // inside the badge
        #expect(check(all, 7, 11, ink), "\(all.rgb(7, 11))")  // the loop's bottom edge
        #expect(check(shuffle, 13, 3, ink), "\(shuffle.rgb(13, 3))")  // the two arrowheads
        #expect(check(shuffle, 13, 10, ink), "\(shuffle.rgb(13, 10))")
        // All three take the same 16 x 14 frame, so they share a top edge in the row.
        let scale = Snapshot.scale
        #expect([all, one, shuffle].allSatisfy { $0.bitmap.pixelsWide == 16 * scale && $0.bitmap.pixelsHigh == 14 * scale })
    }

    /// The wider hit area of the shuffle and repeat icons does not change their size.
    @Test func widerHitAreaKeepsTheLayout() throws {
        let plain = try #require(ImageRenderer(content: Color.red.frame(width: 14, height: 12)).cgImage)
        let wide = try #require(ImageRenderer(content: Color.red.frame(width: 14, height: 12).widerHitArea()).cgImage)
        #expect(wide.width == plain.width && wide.height == plain.height)
    }
    /// A long list keeps a thumb that you can see, and it still reaches both ends of the track.
    @Test func scrollThumbHasAMinimumLengthAndReachesTheEnds() {
        let top = PocketList.thumb(height: 176, shown: 5, count: 1000, first: 0)
        #expect(top.length == PocketList.minThumb && top.offset == 0)
        let bottom = PocketList.thumb(height: 176, shown: 5, count: 1000, first: 995)
        #expect(bottom.offset + bottom.length == 176)
        let short = PocketList.thumb(height: 176, shown: 5, count: 10, first: 5)  // long enough already
        #expect(short.length == 88 && short.offset + short.length == 176)
    }

    /// A 4 x 4 image of one color, as a stand-in for a loaded album cover.
    static func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context?.makeImage()
    }

    @Test func nowPlayingVolumeAndScrub() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.stack.append(Frame(screen: .now))
        s.overlayUntil = 1
        s.volume = 60
        let volume = try render(s, "now-volume")
        // The bottom row is 22 points high, 13.6 above the bottom, so the bars center at y 233.
        // The bar runs from x 87.6 to 279.
        #expect(volume.isBlue(100, 233))  // inside the 60% soft blue fill
        #expect(volume.isLight(250, 233))  // past it: white, with no border
        s.nowMode = .scrub
        s.albumArt = .off
        s.t = 102.5  // half of the track
        let scrub = try render(s, "now-scrub")
        // The times sit on the bar's line: the bar is 191.4 points wide, 54.6 from the screen's left.
        let start: Int = Self.screenLeft + 55, end: Int = Self.screenLeft + 55 + 191
        #expect(scrub.isBlue((start + end) / 2, 233))  // the soft blue diamond at the half
        #expect(scrub.isLight(start + 10, 233))  // the empty white bar, no fill
        #expect(scrub.isLight(end - 10, 233))
    }

    @Test func nowPlayingSliders() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.stack.append(Frame(screen: .now))
        s.nowMode = .shuffle
        s.shuffle = true
        let on = try render(s, "now-shuffle")
        // The slider's 13.2 point bar is where the progress bar is: 174.8 points under the title bar
        // (y 226.2), 54.6 from the screen's left, and 191.4 wide. The 16 point knob is centered on it, at y 233.
        let right: Int = Self.screenLeft + 55 + 191, left: Int = Self.screenLeft + 55, knobY: Int = 233
        #expect(on.isBlue(right - 2, knobY))  // Songs
        #expect(!on.isBlue(left + 2, knobY))
        s.nowMode = .repeatMode
        s.repeatMode = .one
        let one = try render(s, "now-repeat")
        #expect(one.isBlue((left + right) / 2, knobY))  // Off, One, All: One is in the middle
        #expect(!one.isBlue(right - 2, knobY))
    }

    @Test func messageAndToast() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .playlists, loading: true))
        let loading = try render(s, "loading")
        #expect(!loading.isBlue(150, Self.rowCenter(0)))  // no list while loading
        // Round 15 card BD: a box that fits its text, centered, 16 points above the screen's
        // bottom (change 185, 186). The main menu has 6 rows, so glass is under it. The box is
        // #1b1f24 at 60% (change 194): clearly darker than the glass.
        s.stack = [Frame(screen: .main)]
        s.albumArt = .off
        s.toast = "Paused while you’re offline"
        let shot = try render(s, "toast")
        let bottom = Self.screenBottom - 16  // the box's bottom edge
        func light(_ x: Int, _ y: Int) -> Int { let c = shot.rgb(x, y); return max(c.r, c.g, c.b) }
        let box = light(Self.screenLeft + 150, bottom - 6)  // the box, by its middle
        let gap = light(Self.screenLeft + 150, bottom + 6)  // the gap under it
        let side = light(Self.screenLeft + 20, bottom - 6)  // it does not fill the width
        #expect(box + 60 < gap && box + 60 < side, "box \(box), gap \(gap), side \(side)")
    }

    /// Round 14 card BA: the MENU hint lights the MENU label (151), and after 3 pulses its tip
    /// shows in the toast look, centered 16 points above the screen's bottom (139, 195).
    @Test func theMenuHintLightsMenuThenShowsItsTip() throws {
        var s = sampleState()
        s.stack = [Frame(screen: .main), Frame(screen: .settings)]
        let plain = try render(s, "hint-none")
        s.hint = .menu
        s.hintAt = -7  // at the render's time 1: 8 s of glow, and the tip shown for 0.8 s
        let glow = try render(s, "hint-glow")
        s.hintTip = true
        let tip = try render(s, "hint-tip")
        // The MENU label: 60 x 29 points at the wheel's top. The wheel starts at 70.5 x 321.
        func lit(_ shot: Snapshot) -> Bool {
            (325..<354).contains { y in (153..<213).contains { x in shot.isBlue(x, y) } }
        }
        #expect(!lit(plain) && lit(glow) && lit(tip))
        let bottom = Self.screenBottom - 16  // the tip's bottom edge
        func light(_ shot: Snapshot, _ x: Int, _ y: Int) -> Int { let c = shot.rgb(x, y); return max(c.r, c.g, c.b) }
        #expect(light(glow, Self.screenLeft + 150, bottom - 6) == light(plain, Self.screenLeft + 150, bottom - 6))  // no tip yet
        let box = light(tip, Self.screenLeft + 150, bottom - 6), side = light(tip, Self.screenLeft + 20, bottom - 6)
        #expect(box + 60 < side, "box \(box), side \(side)")  // the tip, by its middle; it does not fill the width
    }

    /// Changes 176 and 195: on Now Playing the play/pause label lights, and its tip takes the
    /// time bar's place, 15 points above the screen's bottom.
    @Test func thePlayHintTipTakesTheTimeBarsPlace() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:2")
        s.isPlaying = true
        s.t = 61
        s.stack.append(Frame(screen: .now))
        let plain = try render(s, "hint-play-none")
        s.hint = .playPause
        s.hintAt = -7; s.hintTip = true  // at the render's time 1, the tip shows
        let tip = try render(s, "hint-play-tip")
        // The play/pause label: 50 x 32 points at the wheel's bottom. The wheel starts at 70.5 x 321.
        func lit(_ shot: Snapshot) -> Bool {
            (511..<543).contains { y in (158..<208).contains { x in shot.isBlue(x, y) } }
        }
        #expect(!lit(plain) && lit(tip))
        func light(_ shot: Snapshot, _ x: Int, _ y: Int) -> Int { let c = shot.rgb(x, y); return max(c.r, c.g, c.b) }
        let box = light(tip, Self.screenLeft + 150, Self.screenBottom - 15 - 6)
        let under = light(plain, Self.screenLeft + 150, Self.screenBottom - 15 - 6)
        #expect(box + 60 < under, "box \(box), under \(under)")  // the tip, by its middle
        // The time bar's filled start, left of the tip, is gone.
        let barY = Self.screenBottom - 14 - 11
        #expect(plain.rgb(Self.screenLeft + 60, barY) != tip.rgb(Self.screenLeft + 60, barY))
    }

    @Test func theCenterLooksPressedInAndDarkensWhenPressed() throws {
        let wheelTop: Int = 321  // device border 1, padding 24.8, bezel 239.4, gap 55.8
        let middle: Int = wheelTop + 112, nearTop: Int = middle - 30, nearBottom: Int = middle + 30
        let x = Int(PocketSkin.size.width) / 2  // the wheel's center
        let up = try render(AppState(), "wheel")
        let down = try render(AppState(), "wheel-pressed", pressed: .center)
        let ring = up.rgb(x, wheelTop + 60), white = try reference(0xf9fbfc)
        #expect(near(ring, white), "ring \(ring)")  // the light wheel (card BL)
        // Dark at the top, as if pressed in. Pressed, the whole button gets darker.
        #expect(up.rgb(x, nearTop).b < up.rgb(x, nearBottom).b)
        for y in [nearTop, middle, nearBottom] { #expect(down.rgb(x, y).b < up.rgb(x, y).b, "silver y \(y)") }
        // Black too: pressed, the whole button gets darker.
        var s = AppState()
        s.deviceColor = .black
        let blackUp = try render(s, "wheel-black"), blackDown = try render(s, "wheel-black-pressed", pressed: .center)
        for y in [nearTop, middle, nearBottom] { #expect(blackDown.rgb(x, y).b < blackUp.rgb(x, y).b, "black y \(y)") }
    }

    /// Card BL v3: the black device has a charcoal body, the #2a2c2e bezel and a near black
    /// wheel with a dark center. The screen does not change.
    @Test func blackDeviceColorsTheBodyBezelAndWheel() throws {
        var s = AppState()
        s.deviceColor = .black
        let shot = try render(s, "black")
        let wheelTop: Int = 321, x = Int(PocketSkin.size.width) / 2
        let middle: Int = wheelTop + 112
        let ring = shot.rgb(x, wheelTop + 60), wheel = try reference(0x202123)
        #expect(near(ring, wheel), "ring \(ring)")
        let bezel = shot.rgb(29, Self.screenTop + 60), want = try reference(0x2a2c2e)  // left of the screen
        #expect(near(bezel, want), "bezel \(bezel)")
        #expect(shot.isDark(10, 300))  // the body, beside the screen
        #expect(shot.rgb(x, middle - 30).b < shot.rgb(x, middle + 30).b)  // the center: dark at the top
        #expect(shot.isLight(100, Self.screenTop + 60))  // the screen's glass stays light
    }

    /// CLA-94: in the window's margins, no shadow reaches the top 5 pt, but the shadow still
    /// shows under the device.
    @Test func theShadowDoesNotReachTheTopMargin() throws {
        for color in [DeviceColor.silver, .black] {
            var s = AppState()
            s.deviceColor = color
            let framed = PocketSkin(state: s, interactive: false)
                .padding(EdgeInsets(top: 5, leading: 60, bottom: 90, trailing: 60))
            let renderer = ImageRenderer(content: framed)
            renderer.scale = CGFloat(Snapshot.scale)
            let image = try #require(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
               let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pocket-window-\(color).png"))
            }
            func alpha(_ x: Int, _ y: Int) -> CGFloat { bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
            let top = (0..<5 * Snapshot.scale).flatMap { y in (0..<bitmap.pixelsWide).map { alpha($0, y) } }.max() ?? 0
            // At most 2/255 (under 1%): no line shows where the window cuts it.
            #expect(top <= 2.5 / 255, "\(color): top margin alpha \(top)")
            let below = alpha(bitmap.pixelsWide / 2, bitmap.pixelsHigh - 70 * Snapshot.scale)  // 20 pt under the device
            #expect(below > 0.05, "\(color): shadow under the device \(below)")
        }
    }

    /// CLA-100: the device stays opaque through the color fade, and it keeps one drop shadow. In
    /// the middle of the fade no desktop shows through, and Black's shadow is as strong as before.
    @Test func theColorFadeStaysOpaqueWithOneShadow() throws {
        let margin = EdgeInsets(top: 5, leading: 60, bottom: 90, trailing: 60)
        func framed(_ view: some View) throws -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: view.padding(margin))
            renderer.scale = CGFloat(Snapshot.scale)
            return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        }
        func alpha(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
            bitmap.colorAt(x: (60 + x) * Snapshot.scale, y: (5 + y) * Snapshot.scale)?.alphaComponent ?? 0
        }
        // Points on the body, in device points: both sides, between the screen and the wheel,
        // and near the bottom.
        let body = [(8, 300), (358, 300), (183, 290), (183, 600), (40, 580)]
        for fade in [0, 0.25, 0.5, 0.75, 1] {
            let shot = try framed(PocketSkin(state: AppState(), interactive: false, fade: fade))
            for (x, y) in body {
                #expect(alpha(shot, x, y) >= 254.5 / 255, "fade \(fade) at (\(x), \(y)): alpha \(alpha(shot, x, y))")
            }
        }
        // At each end, one shadow, as strong as the shadow of the old single body.
        for (color, shadow) in [(DeviceColor.silver, Color(hex: 0x1e1e1e, opacity: 0.3)), (.black, .black.opacity(0.45))] {
            var s = AppState()
            s.deviceColor = color
            let shot = try framed(PocketSkin(state: s, interactive: false))
            let old = try framed(
                RoundedRectangle(cornerRadius: 34).fill(Color.black).padding(.top, PocketSkin.shadowDrop)
                    .shadow(color: shadow, radius: 20, y: 20)
                    .frame(width: PocketSkin.size.width, height: PocketSkin.size.height))
            for (x, y) in [(183, 633), (183, 653), (20, 640), (370, 400)] {
                let now = alpha(shot, x, y), before = alpha(old, x, y)
                #expect(abs(now - before) <= 3 / 255, "\(color) shadow at (\(x), \(y)): \(now), before \(before)")
            }
        }
    }

    /// About, card BF: one page with the capybara at the top, then the steel name and lines with
    /// the red heart. Card BS and BF.2: 4 steps, each ending on a whole row in the 206 pt view.
    /// Step 1 shows Version whole, step 2 Status, step 3 the selected Licenses row whole, step 4
    /// the legal text whole.
    @Test func aboutScrollsOnePageWithTheCapybaraAndLicensesRow() throws {
        #expect(PocketAbout.poses.count == AboutPose.allCases.count)  // the art is bundled
        #expect(PocketAbout.stops == [0, 30.9, 53.8, 76.7, 138.4] && PocketAbout.stops.count == AppState.aboutSteps + 1)
        var s = sampleState()
        s.stack = [Frame(screen: .main), Frame(screen: .settings), Frame(screen: .about)]
        let top = Self.listTop, left = Self.screenLeft, x = left + 150
        let glass = try reference(0xf4f8fb)
        let first = try render(s, "about-0")
        // The capybara: not plain glass in its 88 pt box, 18 pt down.
        let art = (top + 26..<top + 102).filter { !near(first.rgb(x, $0), glass) }
        #expect(art.count > 40)
        // The heart: red pixels in the "Made with ♥ by CappyAI" line, 153 to 169 pt down.
        let red = (left + 60..<left + 240).filter { x in
            (top + 153...top + 169).contains { y in let c = first.rgb(x, y); return c.r > 180 && c.g < 140 && c.b < 140 }
        }
        #expect(!red.isEmpty)
        // Step 1: the page moved up 30.9 pt. The Version row, at 183.1 to 206 pt, is whole: its
        // ink shows, and nothing is selected.
        s.stack[2].off = 1
        let one = try render(s, "about-1")
        #expect((left + 9..<left + 60).contains { x in (top + 188...top + 201).contains { one.isDark(x, $0) } })
        #expect(!one.isBlue(x, top + 194))
        // Step 2: up 53.8 pt. The Status row ("Not activated" here) is at 183.1 to 206 pt, not selected.
        s.stack[2].off = 2
        let two = try render(s, "about-2")
        #expect(!two.isBlue(x, top + 194))
        // Step 3: up 76.7 pt. The Licenses row, at 183.1 to 206 pt, is whole and selected.
        s.stack[2].off = 3
        let three = try render(s, "about-3")
        #expect(three.isBlue(x, top + 185) && three.isBlue(x, top + 204))
        // Step 4: up 138.4 pt. Licenses is at 121.4 pt, and the legal text, at 154.5 to 196.5 pt,
        // is ink on the glass.
        s.stack[2].off = 4
        let last = try render(s, "about-4")
        #expect(last.isBlue(x, top + 132))
        let legal = (left + 60..<left + 240).filter { x in (top + 158...top + 195).contains { last.isDark(x, $0) } }
        #expect(legal.count > 10)
    }

    /// CLA-141, card BF.2: at step 2 an activated Mac's Status row is selected (blue) when it
    /// opens, and Activation shows one selected two-line row (changes 360-362).
    @Test func aboutStatusAndActivation() throws {
        var s = sampleState()
        s.activateOn = true
        s.activated = true
        s.activation = .active(ActiveInfo(email: "s***@example.com", since: 1_795_014_000, macs: 1, limit: 2))
        s.stack = [Frame(screen: .main), Frame(screen: .settings), Frame(screen: .about)]
        s.stack[2].off = 2
        let top = Self.listTop, x = Self.screenLeft + 150
        let status = try render(s, "about-status")
        #expect(status.isBlue(x, top + 185) && status.isBlue(x, top + 204))
        s.activation = .locked  // no connection at launch: "Activated", no selection
        let offline = try render(s, "about-status-offline")
        #expect(!offline.isBlue(x, top + 194))
        s.activation = .active(ActiveInfo(email: "s***@example.com", since: 1_795_014_000, macs: 1, limit: 2))
        s.stack.append(Frame(screen: .activation))
        let page = try render(s, "activation")
        #expect(page.isBlue(x, top + 3) && page.isBlue(x, top + 38))  // one 41.2 pt row, selected
        #expect(!page.isBlue(x, top + 60))
        s.activation = .active(ActiveInfo(email: "a-very-long-name***@mail.example-company.co.jp", since: 1_795_014_000, macs: 2, limit: 2))
        _ = try render(s, "activation-long")
    }

    /// Change 210: the capybara waves in the first second, then stands, then sleeps. Changes 209
    /// and 218: the glint crosses the signature, then the tagline, and is gone after.
    @Test func aboutCapybaraChangesPoseAndBothLinesGlint() throws {
        var s = sampleState()
        s.stack = [Frame(screen: .main), Frame(screen: .settings), Frame(screen: .about)]
        let top = Self.listTop, left = Self.screenLeft
        let wave = try render(s, "about-wave", time: 0.5)
        let glint = try render(s, "about-glint", time: 0.9)
        let stand = try render(s, "about-stand", time: 3)
        let sleep = try render(s, "about-sleep", time: 30)
        func differ(_ a: Snapshot, _ b: Snapshot) -> Int {
            (left + 102..<left + 198).reduce(0) { n, x in
                n + stride(from: top + 18, to: top + 106, by: 4).filter { !near(a.rgb(x, $0), b.rgb(x, $0)) }.count
            }
        }
        #expect(differ(wave, stand) > 40)
        #expect(differ(sleep, stand) > 40)
        // Change 218: the band is in the middle of "Made with ♥ by CappyAI" (153 to 169 pt down)
        // 0.9 s into the wave, and of the tagline (172 to 188 pt down) 0.15 s later.
        func light(_ c: (r: Int, g: Int, b: Int)) -> Int { c.r + c.g + c.b }
        func brighter(_ a: Snapshot, _ ys: ClosedRange<Int>) -> Int {
            (left + 120..<left + 180).filter { x in ys.contains { light(a.rgb(x, $0)) > light(stand.rgb(x, $0)) + 60 } }.count
        }
        let later = try render(s, "about-glint-tagline", time: 1.05)
        #expect(brighter(glint, top + 153...top + 169) > 5)
        #expect(brighter(later, top + 172...top + 188) > 5)
    }

    /// Change 213: the Licenses list has one row a license, the first selected. A license's text
    /// screen shows its name in bold, then gray text lines, and moves a line a step.
    @Test func licensesListAndTextShow() throws {
        var s = sampleState()
        s.stack = [Frame(screen: .main), Frame(screen: .settings), Frame(screen: .about), Frame(screen: .licenses)]
        let list = try render(s, "licenses")
        #expect(list.isBlue(Self.screenLeft + 170, Self.rowCenter(0)))
        #expect(!list.isBlue(Self.screenLeft + 170, Self.rowCenter(1)))
        s.stack.append(Frame(screen: .license(0)))
        let text = try render(s, "license-mit")
        let top = Self.listTop, left = Self.screenLeft
        let name = (left + 100..<left + 200).filter { x in (top + 10...top + 28).contains { text.isDark(x, $0) } }
        #expect(name.count > 10)
        let ink = (left + 18..<left + 200).filter { x in (top + 36...top + 46).contains { text.isDark(x, $0) } }
        #expect(ink.count > 20)  // the first line of the text
        s.stack[4].off = 2
        let moved = try render(s, "license-mit-2")
        let differ = (left + 18..<left + 280).filter { !near(text.rgb($0, top + 41), moved.rgb($0, top + 41)) }
        #expect(differ.count > 10)
    }

    /// The battery's shadow fades downward only, from y 49 to 53 of the view box: its rows have
    /// the same color at both ends, and the lower row is much lighter than the upper one.
    @Test func theBatteryShadowFadesDownward() throws {
        let battery = Labels.BatteryText(level: 0.5, red: false, mark: nil, label: "Battery 50%")
        let renderer = ImageRenderer(content: BatteryView(battery: battery).background(Color.white))
        renderer.scale = 10
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        func rgb(_ x: Int, _ unitY: Double) -> (r: Int, g: Int, b: Int) {
            let c = bitmap.colorAt(x: x, y: Int(unitY / 53 * 11 * 10))?.usingColorSpace(.sRGB) ?? .clear
            return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }
        let leftX = 10, rightX = Int(95.0 / 111 * BatteryView.width * 10)  // 5 and 95 units in
        for unitY in [49.6, 52.4] {
            let left = rgb(leftX, unitY), right = rgb(rightX, unitY)
            #expect(near(left, right), "at y \(unitY): left \(left), right \(right)")
        }
        let upper = rgb(leftX, 49.6), lower = rgb(leftX, 52.4)
        #expect(upper.r < 200, "the top of the shadow is dark: \(upper)")
        #expect(lower.r - upper.r > 40, "it fades out downward: \(upper) to \(lower)")
    }

    /// Card Y as Jason chose it (22:17 JST, 11-07): the gray frame #636364 and the first shading,
    /// not the gray-green Y.1 of CLA-30.
    @Test func theBatteryHasTheGrayFrameAndFirstShading() throws {
        let battery = Labels.BatteryText(level: 0.5, red: false, mark: nil, label: "Battery 50%")
        let renderer = ImageRenderer(content: BatteryView(battery: battery).background(Color.white))
        renderer.scale = 10
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let perUnit = BatteryView.width * 10 / 111  // pixels per view box unit
        // The frame's left side, x 0 to 2 of the view box, halfway down.
        let c = bitmap.colorAt(x: Int(1 * perUnit), y: Int(25 * perUnit))?.usingColorSpace(.sRGB) ?? .clear
        let frame = (r: Int(c.redComponent * 255), g: Int(c.greenComponent * 255), b: Int(c.blueComponent * 255))
        let want = try reference(0x636364)
        #expect(near(frame, want), "frame \(frame), want \(want)")
        // The gradients, as the first card Y lists them: 47 colors each, top to bottom.
        #expect(BatteryView.fillAll.count == 47 && BatteryView.emptyAll.count == 47 && BatteryView.redAll.count == 47)
        #expect(BatteryView.fillAll.first == 0x666866 && BatteryView.fillAll.last == 0x61695d)
        #expect(BatteryView.emptyAll.first == 0x626263 && BatteryView.emptyAll.last == 0x686869)
        #expect(BatteryView.redAll.first == 0x706866 && BatteryView.redAll.last == 0x66605f)
    }

    /// Round 7 card Y: the battery sits at the right of the title bar, 7 points after the play
    /// mark. A Mac with no battery shows none, and the mark stays at the right edge.
    @Test func theTitleBarShowsTheBattery() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.stack.append(Frame(screen: .settings))  // a full-width header
        let none = try render(s, "battery-none")
        s.battery = Battery(level: 0.5, charging: false, onPower: false)
        let half = try render(s, "battery-half")
        s.battery = Battery(level: 0.19, charging: false, onPower: false)
        let low = try render(s, "battery-low")
        s.battery = Battery(level: 0.6, charging: true, onPower: true)
        _ = try render(s, "battery-charging")
        s.battery = Battery(level: 1, charging: false, onPower: true)
        _ = try render(s, "battery-plugged")
        // The battery is 23 x 11 points, 8 in from the screen's right edge. Its fill starts 0.4
        // points into it: at 19% the fill ends 4.2 points in, at 50% 10.6 points in.
        let right: Int = Self.screenLeft + Self.screenWidth - 8, midY: Int = Self.screenTop + 9
        let fillX = right - 21  // 2 points into the battery: inside the fill at 19% and at 50%
        let green = half.rgb(fillX, midY), red = low.rgb(fillX, midY)
        #expect(green.g > green.r + 15, "green \(green)")
        #expect(red.r > red.g + 15, "red \(red)")
        // With no battery, the play mark sits where the battery is now.
        #expect(none.isBlue(right - 8, midY))
        #expect(!half.isBlue(right - 8, midY))
    }

    @Test func pausedMarkIsTwoBars() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.isPlaying = false
        s.stack.append(Frame(screen: .settings))  // a full-width header; on the half screens it is 150 points
        let shot = try render(s, "paused")
        // The header mark: two glossy blue bars, 3.1 points wide with a 2.5 point gap, at the right of the header.
        let left: Int = Self.screenLeft + Self.screenWidth - 8 - 10, midY: Int = Self.screenTop + 10
        #expect(shot.isBlue(left + 2, midY))  // the first bar
        #expect(!shot.isBlue(left + 5, midY))  // the gap
        #expect(shot.isBlue(left + 7, midY))  // the second bar
    }

    /// Card AK, change 110: with Now Playing Bar on, the main menu shows the bar under its pane.
    @Test func theMainMenuShowsTheBarUnderItsPane() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        let off = try render(s, "main-no-bar")
        s.nowPlayingBar = true
        let on = try render(s, "main-bar")
        // The bar's background, 2 points over the screen's bottom, under the pane's text.
        let barColor = try reference(0xe8eef3)
        let y = Self.screenBottom - 2
        #expect(near(on.rgb(Self.screenLeft + 100, y), barColor))
        #expect(!near(off.rgb(Self.screenLeft + 100, y), barColor))
    }

    /// Card AK: a song list while a song plays. Off (the default): no bar, and the 5 two-line
    /// rows grow to 41.2 points to fill the screen. On: the bar, and rows of 36.6 over it.
    @Test func aSongListShowsTheBarOnlyWithTheSettingOn() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))  // row 0 selected
        let off = try render(s, "tracks-bar-off")
        s.nowPlayingBar = true
        let on = try render(s, "tracks-bar-on")
        let barColor = try reference(0xe8eef3)
        let x = Self.screenLeft + 100, bottom = Self.screenBottom - 2
        #expect(near(on.rgb(x, bottom), barColor) && !near(off.rgb(x, bottom), barColor))
        // The selected row ends at 51.4 + 41.2 = 92.6 with no bar, at 51.4 + 36.6 = 88 over it.
        let right = Self.screenLeft + 240  // past the row's text
        #expect(off.isBlue(right, 90) && !on.isBlue(right, 90))
        #expect(off.isBlue(right, 86) && on.isBlue(right, 86))
    }

    @Test func theBarShowsANoteThatStaysWhenPaused() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))
        s.nowPlayingBar = true  // card AK: the bar shows only with the setting on
        s.isPlaying = true
        let playing = try render(s, "bar-playing")
        s.isPlaying = false
        let paused = try render(s, "bar-paused")
        // The bar is the screen's last 21.9 points; the note is its first 11 x 11, after 9 of padding.
        // The text starts 6 points after the note, so this box holds only the note.
        let gray = try reference(0x5d6772)
        var ink = 0
        for x in (Self.screenLeft + 7)...(Self.screenLeft + 19) {
            for y in (Self.screenBottom - 20)...(Self.screenBottom - 2) {
                #expect(playing.rgb(x, y) == paused.rgb(x, y), "at \(x), \(y)")  // no change on pause
                if near(playing.rgb(x, y), gray) { ink += 1 }
            }
        }
        #expect(ink > 0)  // the note is drawn, in the bar's gray text color

        // Round 7 card W, change 55: the note's middle is on the text's middle, not above it.
        // "Paper Planes — M.I.A." runs from the cap tops to the "p" tails, so the middle of its
        // ink is within a few tenths of a point of the middle of its x-height. Read in pixels.
        let px = Snapshot.scale
        func inkRows(_ xs: ClosedRange<Int>) -> [Int] {
            ((Self.screenBottom - 21) * px...Self.screenBottom * px).filter { y in
                (xs.lowerBound * px...xs.upperBound * px).contains { x in
                    let c = playing.bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .clear
                    return max(c.redComponent, c.greenComponent, c.blueComponent) < 0.6
                }
            }
        }
        let note = inkRows((Self.screenLeft + 9)...(Self.screenLeft + 19))
        let text = inkRows((Self.screenLeft + 27)...(Self.screenLeft + 120))
        let noteTop = try #require(note.first), noteBottom = try #require(note.last)
        let textTop = try #require(text.first), textBottom = try #require(text.last)
        // The note is a little taller than the text, so its top may be up to 1 point above it, no more.
        #expect(noteTop >= textTop - px, "note top \(noteTop), text top \(textTop)")
        let offset = Double(noteTop + noteBottom - textTop - textBottom) / 2 / Double(px)
        #expect(abs(offset) <= 1, "note middle \(offset) points from the text middle")
    }

    /// The mockup states that the other tests do not draw. Each one must render at full size.
    @Test func otherMockupStates() throws {
        var s = sampleState()
        _ = try render(s, "main-idle")  // nothing plays: no Now Playing row and no bar

        s.current = TrackRef(playlist: "spotify:playlist:a", track: "spotify:track:r2")
        s.isPlaying = true
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))
        _ = try render(s, "tracks-playing")  // the playing row shows a speaker

        s.offline = true
        _ = try render(s, "offline")  // OFF in the header
        s.offline = false

        s.shuffle = true
        s.repeatMode = .one
        s.stack.append(Frame(screen: .now))
        _ = try render(s, "now-icons")  // shuffle dark, repeat dark with its "1" badge
        s.shuffle = false
        s.repeatMode = .off
        _ = try render(s, "now-icons-off")  // both dimmed

        var error = Frame(screen: .playlists)
        error.error = true
        s.stack = [Frame(screen: .main), error]
        _ = try render(s, "error")
        s.stack = [Frame(screen: .main), Frame(screen: .tracks(playlist: "spotify:playlist:b"))]
        _ = try render(s, "empty")
        s.stack = [Frame(screen: .login), Frame(screen: .auth)]
        _ = try render(s, "auth")
        s.stack = [Frame(screen: .main), Frame(screen: .settings), Frame(screen: .about)]
        _ = try render(s, "about")
        s.stack = [Frame(screen: .main), Frame(screen: .settings), Frame(screen: .confirm)]
        _ = try render(s, "confirm")
    }

    /// Hello (card AT): the word writes itself in four looks; the center glows from 13 s, and
    /// the begin text shows at 14.9 s. `time` is seconds since Hello opened.
    @Test func helloWritesItsLooksThenGlowsThenShowsTheText() throws {
        var s = AppState()
        s.stack = [Frame(screen: .hello)]
        let ink = (x: 113, y: 142)  // on the h's first stroke
        let ring = (x: 183, y: 392)  // just above the wheel's center button
        func text(_ shot: Snapshot) -> Bool {  // any dark text pixel in the begin line: screen y 198 to 211
            for y in 231...242 {
                for x in 100...200 {
                    let c = shot.rgb(x, y)
                    if c.r < 140 && c.g < 140 { return true }
                }
            }
            return false
        }
        let line = try render(s, "hello-t2-ink", time: 2.4)
        #expect(line.isDark(ink.x, ink.y) && !line.isBlue(ring.x, ring.y) && !text(line))
        #expect(line.isLight(150, 51))  // no title bar, so no line under it
        let glass = try render(s, "hello-t5-glow", time: 13.4)
        #expect(glass.isBlue(ring.x, ring.y) && !text(glass))
        let begin = try render(s, "hello-text", time: 18.2)
        #expect(begin.isBlue(ring.x, ring.y) && text(begin))
    }

    /// The color pick (card AW): the rows on the left, the small device on the right, the
    /// fingertip dot and the turn hint before the first turn; after it, the new color and the glow.
    @Test func theColorPickShowsTheSmallDeviceAndTriesTheColorOn() throws {
        var s = AppState()
        s.stack = [Frame(screen: .color)]
        func hint(_ shot: Snapshot) -> Bool {  // dark text under the two rows, in the left pane
            for y in 106...117 {
                for x in 45...120 {
                    let c = shot.rgb(x, y)
                    if c.r < 140 && c.g < 140 { return true }
                }
            }
            return false
        }
        let preview = (x: 209, y: 224)  // the small device's body, near its bottom
        let body = (x: 20, y: 590)  // the big device's body, near its bottom
        let silver = try render(s, "color-pick", time: 10)
        #expect(silver.isBlue(100, Self.rowCenter(0)))  // Silver is selected
        #expect(hint(silver))
        #expect(!silver.isBlue(183, 392))  // no center glow before the turn
        s.top.sel = 1
        s.colorTurnAt = 5
        let black = try render(s, "color-pick-black", time: 7.8)
        #expect(black.isBlue(100, Self.rowCenter(1)))
        #expect(black.isDark(preview.x, preview.y) && black.isDark(body.x, body.y))  // both devices are black
        // Silver was light at the same points. Near the bottom the card BH roll darkens it, so
        // compare it with Black.
        for p in [preview, body] { #expect(silver.rgb(p.x, p.y).g > black.rgb(p.x, p.y).g + 60, "\(p)") }
        #expect(black.isBlue(183, 392) && !hint(black))  // the glow first; the press hint comes at 12.2 s
    }

    /// Card BQ, change 287: before the first turn, the fingertip dot shows on the wheel, the same
    /// on Silver and Black. At 0.8 s into its loop it is fully in at 10 o'clock: 83 points from
    /// the wheel's center (183, 433.5) at -60°. It is hidden at 0.3 s, and gone after a turn.
    @Test func theColorPickShowsTheFingertipDotUntilTheFirstTurn() throws {
        let dot = (x: 111, y: 392)
        // The dot's middle is #5aa3f0 at 60% over the wheel: blue by 90 over red on both colors.
        // The wheel alone is gray there.
        func lit(_ shot: Snapshot, _ x: Int, _ y: Int) -> Bool { let c = shot.rgb(x, y); return c.b > c.r + 60 }
        for color in [DeviceColor.silver, .black] {
            var s = AppState()
            s.stack = [Frame(screen: .color)]
            s.top.sel = color == .black ? 1 : 0  // the pick shows the selected color
            s.colorAt = 100
            let shot = try render(s, "color-pick-finger-\(color)", time: 100.8)
            #expect(lit(shot, dot.x, dot.y), "\(color): \(shot.rgb(dot.x, dot.y))")
            #expect(!lit(shot, dot.x + 30, dot.y), "\(color): the dot is 33 points wide")
            #expect(!lit(shot, Int(PocketSkin.size.width) - dot.x, dot.y), "\(color): only one dot")
            let early = try render(s, "color-pick-finger-early-\(color)", time: 100.3)
            #expect(!lit(early, dot.x, dot.y), "\(color): hidden at the start of the loop")
            s.colorTurnAt = 101
            let turned = try render(s, "color-pick-finger-turned-\(color)", time: 104.6 + 0.8)
            #expect(!lit(turned, dot.x, dot.y), "\(color): gone after the first turn")
        }
    }

    /// Card BM, changes 257 and 264: Pick Your Music has the two services on the left and the
    /// big logo tile of the selected one on the right, in place of the small device. Spotify's
    /// tile has its green marks; Apple Music's tile is dark with a white note and no green.
    @Test func pickYourMusicShowsTheLogoOfTheSelectedService() throws {
        #expect(ServiceLogo.logos.count == 2)  // both logos are bundled
        var s = AppState()
        s.stack = [Frame(screen: .pickMusic)]
        // The green points on the right side, where the tile and its reflection are.
        func green(_ shot: Snapshot) -> Int {
            var n = 0
            for x in Self.screenLeft + 150..<Self.screenLeft + 300 {
                for y in Self.listTop..<Self.screenBottom {
                    let c = shot.rgb(x, y)
                    if c.g > c.r + 100 && c.g > c.b + 80 { n += 1 }
                }
            }
            return n
        }
        let spotify = try render(s, "pick-music", time: 10)
        #expect(spotify.isBlue(100, Self.rowCenter(0)) && !spotify.isBlue(100, Self.rowCenter(1)))
        #expect(green(spotify) > 300, "\(green(spotify))")
        s.top.sel = 1
        let apple = try render(s, "pick-music-apple", time: 10)
        #expect(apple.isBlue(100, Self.rowCenter(1)))
        #expect(green(apple) == 0)  // the Spotify tile has faded out
        let logo = (x: Self.screenLeft + 225, y: 165)  // in the tile, under its middle
        #expect(apple.isDark(logo.x, logo.y), "\(apple.rgb(logo.x, logo.y))")
    }

    /// Card AW.1, change 236: after a turn, Pick Your Color shows no light on the wheel's rim.
    /// Only the center glows.
    @Test func theColorPickShowsNoRimLightAfterATurn() throws {
        var s = AppState()
        s.stack = [Frame(screen: .color)]
        s.colorAt = 0; s.colorTurnAt = 5
        let shot = try render(s, "color-pick-turned", time: 7.8)
        let center = (x: Double(PocketSkin.size.width) / 2, y: 321 + 112.5)
        for degrees in stride(from: 0, to: 360, by: 10) {
            let a = Double(degrees) * .pi / 180
            let x = Int(center.x + 105 * cos(a)), y = Int(center.y + 105 * sin(a))
            #expect(!shot.isBlue(x, y), "light at \(degrees)°")
        }
        #expect(shot.isBlue(183, 392))  // the center glows
    }

    /// Card AX: the login screens are split like the color pick. A headline and a line sit over
    /// the rows, which start 77 points under the title bar. "You’re in" shows the green check.
    @Test func theLoginScreensShowTheWordsTheRowsAndTheSmallDevice() throws {
        var s = AppState()
        s.setupDone = true
        func any(_ shot: Snapshot, x: ClosedRange<Int>, y: ClosedRange<Int>, _ test: (Int, Int, Int) -> Bool) -> Bool {
            for py in y {
                for px in x {
                    let c = shot.rgb(px, py)
                    if test(c.r, c.g, c.b) { return true }
                }
            }
            return false
        }
        func headline(_ shot: Snapshot) -> Bool {  // dark bold text 9 points under the title bar
            any(shot, x: 42...120, y: 60...74) { r, g, b in max(r, g, b) < 100 }
        }
        func check(_ shot: Snapshot) -> Bool {  // the green check on the small device's screen
            any(shot, x: 225...300, y: 60...120) { r, g, b in g > r + 60 && g > b + 30 }
        }
        func blue(_ shot: Snapshot) -> String {  // where the selection shows, for a failure message
            let ys = (Self.listTop...Self.screenBottom).filter { shot.isBlue(175, $0) }
            return "blue rows \(ys.first ?? -1)...\(ys.last ?? -1)"
        }
        // x 175: right of the row labels, whose white text covers the blue, inside the 150 point pane.
        let firstRow = Self.rowCenter(0) + 77
        s.stack = [Frame(screen: .login)]
        let login = try render(s, "login-words", time: 10)
        #expect(headline(login))
        #expect(login.isBlue(175, firstRow) && !login.isBlue(175, Self.rowCenter(0)), "\(blue(login))")
        #expect(!check(login))
        s.stack.append(Frame(screen: .auth, token: 1))
        let wait = try render(s, "login-wait", time: 10)
        #expect(headline(wait))
        #expect(wait.isBlue(175, firstRow) && !wait.isBlue(175, firstRow + 23), "\(blue(wait))")  // Open browser again
        s.stack[1] = Frame(screen: .loginFailed)
        let failed = try render(s, "login-failed", time: 10)
        #expect(headline(failed) && failed.isBlue(175, firstRow), "\(blue(failed))")
        s.stack = [Frame(screen: .loggedIn)]
        let done = try render(s, "logged-in", time: 10)
        #expect(headline(done) && !done.isBlue(175, firstRow) && check(done))  // no rows
        // Card BB: the same split screen, with one row. A gray cross until the app is found,
        // then the green check.
        s.stack = [Frame(screen: .spotifyApp)]
        s.spotifyApp = false
        let missing = try render(s, "spotify-app", time: 10)
        #expect(headline(missing) && missing.isBlue(175, firstRow) && !check(missing), "\(blue(missing))")
        s.spotifyApp = true
        let linked = try render(s, "spotify-app-linked", time: 10)
        #expect(check(linked))
        // Card AX, screen 135 (CLA-66): the same split screen with three rows, "Check again"
        // selected. A gray cross ("No Premium") until Premium is found, then the green check.
        s.stack = [Frame(screen: .premium)]
        let premium = try render(s, "premium-needed", time: 10)
        #expect(headline(premium) && premium.isBlue(175, firstRow) && !check(premium), "\(blue(premium))")
        #expect(!premium.isBlue(175, firstRow + 23))  // Get Premium
        s.premiumFound = true; s.premiumAt = 9.5  // the light is halfway up the cable
        let found = try render(s, "premium-found", time: 10)
        #expect(check(found))
        s.premiumFound = false; s.premiumAt = 0
        // Card BM: Access is off (258) has two rows; Not subscribed (259) has three, with Apple
        // Music's words. The rows start at the same place, so the blue bar never jumps.
        s.stack = [Frame(screen: .accessOff)]
        let off = try render(s, "access-off", time: 10)
        #expect(headline(off) && off.isBlue(175, firstRow) && !check(off), "\(blue(off))")
        #expect(!off.isBlue(175, firstRow + 23))  // Use Spotify
        s.service = .appleMusic; s.words = .appleMusic
        s.stack = [Frame(screen: .premium)]
        let plan = try render(s, "not-subscribed", time: 10)
        #expect(headline(plan) && plan.isBlue(175, firstRow) && !check(plan), "\(blue(plan))")
        s.service = .spotify; s.words = .spotify
        // Card AY: the bar moves under the words while the names fill the small screen. Then
        // "You’re all set" and the green check.
        s.library = [Playlist(id: "spotify:playlist:a", name: "Road Trip", tracks: [])]
        s.stack = [Frame(screen: .yourMusic, loading: true, token: 1)]
        s.namesAt = 1  // the names came at 1 s, so at 10 s all show
        let reading = try render(s, "your-music", time: 10)
        let bar = Self.listTop + 77 + 3  // its middle; at 10 s its blue part is about 31 to 77 points into the pane
        #expect(headline(reading) && reading.isBlue(85, bar) && !reading.isBlue(170, bar) && !check(reading))
        s.readDone = 300; s.readTotal = 1240; s.readAlbums = 84  // the fill reaches about 24% of the bar
        // Change 188: "1 playlist", "84 albums" and "300 liked songs" under the bar.
        let counting = try render(s, "your-music-count", time: 10)
        #expect(counting.isBlue(48, bar) && !counting.isBlue(120, bar))
        s.stack = [Frame(screen: .yourMusic, token: 1)]
        s.setupDone = true
        let allSet = try render(s, "your-music-all-set", time: 10)
        #expect(headline(allSet) && !allSet.isBlue(85, bar) && check(allSet))
    }

    /// Card BW, 319 to 327: the same split screen as AX and BB. The rows start at the same
    /// place (the first one selected), 323 has none, and its mark is the green check.
    @Test func theActivateScreens() throws {
        var s = AppState()
        s.stack = [Frame(screen: .activate)]
        func any(_ shot: Snapshot, x: ClosedRange<Int>, y: ClosedRange<Int>, _ test: (Int, Int, Int) -> Bool) -> Bool {
            for py in y { for px in x { let c = shot.rgb(px, py); if test(c.r, c.g, c.b) { return true } } }
            return false
        }
        let firstRow = Self.rowCenter(0) + 77
        let steps: [(String, (inout AppState) -> Void)] = [
            ("319-join", { _ in }),
            ("320-browser-open", { $0.activateOpenMail = 0; $0.activateStopAt = 1000 }),
            ("321-check-mail", { $0.activation = .waiting(email: "sam.longname.example@example.com", mail: 1); $0.activateStopAt = 1000 }),
            ("322-stopped", { $0.activation = .waiting(email: "sam@example.com", mail: 1) }),
            ("323-confirmed", { $0.activation = .active() }),
            ("324-mail-busy", { $0.activation = .mailBusy }),
            ("325-full", { $0.activation = .full }),
            ("326-off", { $0.activation = .off }),
            ("327-offline", { $0.activation = .offline }),
        ]
        for (name, set) in steps {
            var step = s
            set(&step)
            let shot = try render(step, "activate-\(name)", time: 10)
            #expect(any(shot, x: 42...120, y: 60...74) { r, g, b in max(r, g, b) < 100 }, "\(name): headline")
            let green = any(shot, x: 225...300, y: 60...120) { r, g, b in g > r + 60 && g > b + 30 }
            #expect(green == (step.activateStep == .confirmed), "\(name): green check")
            #expect(shot.isBlue(175, firstRow) == (step.activateStep != .confirmed), "\(name): first row")
        }
    }

    /// Card BI v2: the warning (233) and the end (234) are split setup screens with two rows,
    /// the first selected. The small device shows a blue download arrow, or the gray cross.
    /// The grey BETA pill (279) shows on song lists of a beta only.
    @Test func theBetaScreensAndTheBetaTag() throws {
        var s = sampleState()
        s.beta = BetaBuild(signed: 0)
        func any(_ shot: Snapshot, x: ClosedRange<Int>, y: ClosedRange<Int>, _ test: (Int, Int, Int) -> Bool) -> Bool {
            y.contains { py in x.contains { px in let c = shot.rgb(px, py); return test(c.r, c.g, c.b) } }
        }
        let firstRow = Self.rowCenter(0) + 77
        let arrow = { (shot: Snapshot) in any(shot, x: 225...300, y: 60...120) { r, _, b in b > r + 60 && b > 150 } }
        let headline = { (shot: Snapshot) in any(shot, x: 42...120, y: 60...74) { r, g, b in max(r, g, b) < 100 } }
        s.stack = [Frame(screen: .main), Frame(screen: .betaSoon)]
        let soon = try render(s, "beta-soon", time: 10)
        #expect(headline(soon) && arrow(soon))
        #expect(soon.isBlue(175, firstRow) && !soon.isBlue(175, firstRow + 23))  // Get New Beta, then Later
        s.stack = [Frame(screen: .betaEnded)]
        let ended = try render(s, "beta-ended", time: 10)
        #expect(headline(ended) && !arrow(ended))
        #expect(ended.isBlue(175, firstRow) && !ended.isBlue(175, firstRow + 23))  // Get New Beta, then Quit
        // Card BV (312, 315): the update notice, the same on Silver and Black.
        s.beta?.number = 286
        s.newBetaNow = 290
        s.stack = [Frame(screen: .main), Frame(screen: .betaNew)]
        for color in DeviceColor.allCases {
            s.deviceColor = color
            let new = try render(s, "beta-new-\(color.rawValue)", time: 10)
            #expect(headline(new) && arrow(new))
            #expect(new.isBlue(175, firstRow) && !new.isBlue(175, firstRow + 23))  // Get New Beta, then Later
        }
        s.deviceColor = .silver
        // The pill: grey, right in the title bar, where the play mark is not.
        let pill = { (shot: Snapshot) in
            any(shot, x: (Self.screenLeft + 255)...(Self.screenLeft + 292), y: (Self.screenTop + 4)...(Self.screenTop + 14)) { r, g, b in
                (80...150).contains(r) && b > r && b - r < 40 && g > r
            }
        }
        s.stack = [Frame(screen: .main), Frame(screen: .tracks(playlist: Playlist.likedSongsID))]
        let songs = try render(s, "beta-tag-songs")
        #expect(pill(songs))
        s.beta = nil  // an ad-hoc build
        let none = try render(s, "beta-tag-none")
        #expect(!pill(none))
    }
}
