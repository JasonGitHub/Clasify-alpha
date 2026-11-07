import AppKit
import ClasifyCore
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
    // rows of 22.9. Song lists have 5 two-line rows: 41.2 with no bar, 36.6 over the bar. Only
    // song lists show the bar. The screen is 300 x 225, so its bottom is at 257.4.
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
        #expect(shot.isBlue(150, Self.rowCenter(0)))  // "Log in with Spotify" is selected
        let headerTop = shot.rgb(50, 34), want = try reference(0xffffff)
        #expect(near(headerTop, want), "header top \(headerTop)")  // no glass shadow over the header
        #expect(shot.isLight(150, 42))  // the header, right of the title
        let bezel = shot.rgb(Self.screenLeft - 3, 120), dark = try reference(0x4a4e53)
        #expect(near(bezel, dark), "bezel \(bezel)")  // the dark gray bezel left of the screen
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

    @Test func mainArtCrossfadesWithNoDarkDip() {
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        let pose = { (t: Double, i: Int) in MainArt.pose(at: t, index: i, count: 4) }
        #expect(pose(0, 0).opacity == 1 && pose(0, 3).opacity == 0)  // a cover at once
        #expect(close(pose(7.5, 1).opacity, 0.5))  // the second cover fades in
        #expect(pose(7.5, 0).opacity == 1)  // and the first stays fully shown under it
        #expect(pose(7.5, 1).order > pose(7.5, 0).order)
        #expect(pose(9, 0).opacity == 0 && pose(9, 1).opacity == 1)
        #expect(close(pose(31.5, 0).opacity, 0.5) && pose(31.5, 3).opacity == 1)  // the loop wraps on top too
        #expect(pose(3, 2) == pose(35, 2))  // a 32 s loop
        for t in stride(from: 0.0, to: 40, by: 0.25) {
            #expect(MainArt.pose(at: t, index: 0, count: 1).opacity == 1)  // one cover always shows
        }
    }

    @Test func mainArtPansSidewaysInTurnWithNoEdge() {
        // Where each of 10 covers in a row starts and ends its pan, with 3 covers in the loop.
        let moves = (0..<10).map { n -> Double in
            let start = Double(n) * MainArt.slot - MainArt.fade, end = Double(n) * MainArt.slot + MainArt.slot
            return MainArt.pose(at: end, index: n % 3, count: 3).dx - MainArt.pose(at: start, index: n % 3, count: 3).dx
        }
        for n in 0..<9 { #expect((moves[n] > 0) != (moves[n + 1] > 0)) }  // right, then left, also across the loop
        #expect(moves[0] > 0)  // the first cover moves to the right
        for i in 0..<3 {
            for t in stride(from: 0.0, to: 48, by: 0.25) {
                let f = MainArt.pose(at: t, index: i, count: 3)
                #expect(f.dy == 0 && f.scale == MainArt.baseScale)  // sideways only, no zoom
                #expect(abs(f.dx) <= (f.scale - 1) / 2)  // no edge shows
            }
        }
        // Constant speed: equal time steps move the same distance.
        let a = MainArt.pose(at: 2, index: 0, count: 3).dx, b = MainArt.pose(at: 3, index: 0, count: 3).dx
        let c = MainArt.pose(at: 4, index: 0, count: 3).dx
        #expect(abs((b - a) - (c - b)) < 1e-12)
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
        #expect(next.turn == first.turn + 3 && next.from == -first.from && next.start == first.start + 3 * MainArt.slot)
        // Every frame of a turn gives the same value, also at a large time with rounding errors.
        let late = MainArt.motion(at: 975, index: 2, count: 8)  // shown from 975 to 984
        for frame in 1...240 {
            #expect(MainArt.motion(at: 975 + Double(frame) / 30, index: 2, count: 8) == late)
        }
        // The pose follows the same pan, at a constant speed from `from` to `to`.
        let m = MainArt.motion(at: 9, index: 1, count: 3)
        let span = MainArt.slot + MainArt.fade
        for t in stride(from: m.start, through: m.start + span, by: 0.5) {
            let dx = MainArt.pose(at: t, index: 1, count: 3).dx
            #expect(abs(dx - (m.from + (m.to - m.from) * (t - m.start) / span)) < 1e-9)
        }
    }

    @Test func thePanningCoverMovesItsLayerWithCoreAnimation() throws {
        let image = try #require(Self.solidImage(red: 1, green: 0, blue: 0))
        let view = PanView(frame: NSRect(x: 0, y: 0, width: 116, height: 180))
        let m = MainArt.motion(at: 0, index: 0, count: 3)
        view.update(image: image, scale: MainArt.baseScale, pan: m, elapsed: 0)
        view.layout()
        #expect(abs(view.cover.bounds.width - 116 * MainArt.baseScale) < 1e-9)
        #expect(view.cover.position == CGPoint(x: 58, y: 90))
        let move = try #require(view.cover.animation(forKey: "pan") as? CABasicAnimation)
        #expect(move.keyPath == "position.x")
        #expect(abs(((move.fromValue as? NSNumber)?.doubleValue ?? 0) - (58 + m.from * 116)) < 1e-9)
        #expect(abs(((move.toValue as? NSNumber)?.doubleValue ?? 0) - (58 + m.to * 116)) < 1e-9)
        #expect(move.duration == MainArt.slot + MainArt.fade)
        // Reduce Motion: no animation, the cover stays at the center.
        view.update(image: image, scale: MainArt.baseScale, pan: nil, elapsed: 0)
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
        s.top.sel = 5  // About; Log out under it also opens a screen
        let shot = try render(s, "settings-chevron")
        // The chevron is 8 points wide, 10 points in from the right edge of the list.
        let xs = Self.screenLeft + Self.screenWidth - 20...Self.screenLeft + Self.screenWidth - 8
        func box(_ row: Int) -> [(Int, Int)] {
            let c = Self.rowCenter(row)
            return xs.flatMap { x in (c - 5...c + 5).map { (x, $0) } }
        }
        #expect(box(6).allSatisfy { shot.isLight($0.0, $0.1) })  // no chevron on Log out
        #expect(box(5).contains { shot.isLight($0.0, $0.1) })  // a white chevron on the blue row
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
                return max(c.r, c.g, c.b) < 170
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

    @Test func theScrollBarHidesWhenTheListIsStill() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))
        let shot = try render(s, "tracks-still")
        let thumbX: Int = Self.screenLeft + Self.screenWidth - 4, thumbY: Int = Self.listTop + 8
        #expect(shot.isBlue(thumbX, thumbY))  // the selected row's blue, with no thumb over it
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
        #expect(rows(0) { shot.isBlue($0, $1) })  // "Off" on the Shuffle row
        #expect(rows(2) { shot.isLight($0, $1) })  // the selected row's value
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
        s.stack = [Frame(screen: .login)]
        s.toast = "Logged out"
        let shot = try render(s, "toast")
        let toastX: Int = Self.screenLeft + 24, toastY: Int = 225  // 6 points above the toast's bottom, 26 above the screen's
        #expect(shot.isDark(toastX, toastY))  // the toast's dark box
    }

    @Test func theCenterLooksPressedInAndDarkensWhenPressed() throws {
        let wheelTop: Int = 321  // device border 1, padding 24.8, bezel 239.4, gap 55.8
        let middle: Int = wheelTop + 112, nearTop: Int = middle - 30, nearBottom: Int = middle + 30
        let x = Int(PocketSkin.size.width) / 2  // the wheel's center
        let up = try render(AppState(), "wheel")
        let down = try render(AppState(), "wheel-pressed", pressed: .center)
        let ring = up.rgb(x, wheelTop + 60), white = try reference(0xfefefe)
        #expect(near(ring, white), "ring \(ring)")  // the flat white wheel
        // Dark at the top, as if pressed in. Pressed, the whole button gets darker.
        #expect(up.rgb(x, nearTop).b < up.rgb(x, nearBottom).b)
        #expect(down.rgb(x, middle).b < up.rgb(x, middle).b)
    }

    /// Round 8 card Z: the black device has a dark body, a near black bezel and a dark gray
    /// wheel with a dark center. The screen does not change.
    @Test func blackDeviceColorsTheBodyBezelAndWheel() throws {
        var s = AppState()
        s.deviceColor = .black
        let shot = try render(s, "black")
        let wheelTop: Int = 321, x = Int(PocketSkin.size.width) / 2
        let middle: Int = wheelTop + 112
        let ring = shot.rgb(x, wheelTop + 60), wheel = try reference(0x2f2f2f)
        #expect(near(ring, wheel), "ring \(ring)")
        let bezel = shot.rgb(29, Self.screenTop + 60), want = try reference(0x050505)  // left of the screen
        #expect(near(bezel, want), "bezel \(bezel)")
        #expect(shot.isDark(10, 300))  // the body, beside the screen
        #expect(shot.rgb(x, middle - 30).b < shot.rgb(x, middle + 30).b)  // the center: dark at the top
        #expect(shot.isLight(100, Self.screenTop + 60))  // the screen's glass stays light
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

    /// Card Y as updated for CLA-30: the gray-green frame and the D4 shading from battery-icon-gen.py.
    @Test func theBatteryHasTheGrayGreenFrameAndD4Shading() throws {
        let battery = Labels.BatteryText(level: 0.5, red: false, mark: nil, label: "Battery 50%")
        let renderer = ImageRenderer(content: BatteryView(battery: battery).background(Color.white))
        renderer.scale = 10
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let perUnit = BatteryView.width * 10 / 111  // pixels per view box unit
        // The frame's left side, x 0 to 2 of the view box, halfway down.
        let c = bitmap.colorAt(x: Int(1 * perUnit), y: Int(25 * perUnit))?.usingColorSpace(.sRGB) ?? .clear
        let frame = (r: Int(c.redComponent * 255), g: Int(c.greenComponent * 255), b: Int(c.blueComponent * 255))
        let want = try reference(0x8a9886)
        #expect(near(frame, want), "frame \(frame), want \(want)")
        // The gradients, as the generator lists them: 47 colors each, top to bottom.
        #expect(BatteryView.fillAll.count == 47 && BatteryView.emptyAll.count == 47 && BatteryView.redAll.count == 47)
        #expect(BatteryView.fillAll.first == 0xb1e392 && BatteryView.fillAll.last == 0x7bb362)
        #expect(BatteryView.emptyAll.first == 0x76777a && BatteryView.emptyAll.last == 0x797a7d)
        #expect(BatteryView.redAll.first == 0xa37264 && BatteryView.redAll.last == 0x9e6e60)
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

    @Test func theBarShowsANoteThatStaysWhenPaused() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))  // only song lists show the bar
        s.isPlaying = true
        let playing = try render(s, "bar-playing")
        s.isPlaying = false
        let paused = try render(s, "bar-paused")
        // The bar is the screen's last 21.9 points; the note is its first 11 x 11, after 9 of padding.
        // The text starts 4 points after the note, so this box holds only the note.
        let gray = try reference(0x5d6772)
        var ink = 0
        for x in (Self.screenLeft + 7)...(Self.screenLeft + 19) {
            for y in (Self.screenBottom - 20)...(Self.screenBottom - 2) {
                #expect(playing.rgb(x, y) == paused.rgb(x, y), "at \(x), \(y)")  // no change on pause
                if near(playing.rgb(x, y), gray) { ink += 1 }
            }
        }
        #expect(ink > 0)  // the note is drawn, in the bar's gray text color
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
}
