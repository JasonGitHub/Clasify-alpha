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

    // Points in the mockup layout: the device border 1, its padding 24 x 20, the screen border 2,
    // the header 20 with its line, and 8 rows of 22.5 (7 of 160 / 7 over the bar).
    static let screenLeft = 23, listTop = 47

    static func rowCenter(_ index: Int, bar: Bool = false) -> Int {
        let height = bar ? 160.0 / 7 : 22.5
        return listTop + Int((Double(index) + 0.5) * height)
    }

    func render(
        _ state: AppState, _ name: String, pressed: ClickWheel.Zone? = nil, artwork: Artwork = .none
    ) throws -> Snapshot {
        let skin = PocketSkin(state: state, interactive: false, pressed: pressed).environment(\.artwork, artwork)
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
        let headerTop = shot.rgb(50, 28), want = try reference(0xffffff)
        #expect(near(headerTop, want), "header top \(headerTop)")  // no glass shadow over the header
        #expect(shot.isLight(150, 37))  // the header, right of the title
    }

    @Test func mainMenuWithTheBar() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.isPlaying = true
        s.top.sel = 1
        let shot = try render(s, "main")
        #expect(shot.isLight(150, Self.rowCenter(0, bar: true)))
        #expect(shot.isBlue(150, Self.rowCenter(1, bar: true)))
    }

    @Test func eightRowsFillTheList() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))
        s.top.sel = 7
        let shot = try render(s, "tracks-last-row")
        #expect(shot.isBlue(100, Self.rowCenter(7)))  // the 8th row ends at the screen's bottom
        #expect(shot.isBlue(100, 225))
        #expect(!shot.isBlue(100, Self.rowCenter(6)))
    }

    @Test func longListShowsTheScrollBar() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))
        let shot = try render(s, "tracks")
        #expect(shot.isBlue(100, Self.rowCenter(0)))
        let thumbX: Int = Self.screenLeft + 248, thumbY: Int = Self.listTop + 8
        let thumb = shot.rgb(thumbX, thumbY), want = try reference(0x5d6772)
        #expect(near(thumb, want), "thumb \(thumb), want \(want)")
    }

    @Test func settings() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .settings))
        s.top.sel = 2
        let shot = try render(s, "settings")
        #expect(shot.isBlue(100, Self.rowCenter(2)))
    }

    @Test func nowPlayingShowsTheCover() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:2")
        s.isPlaying = true
        s.t = 61
        s.stack.append(Frame(screen: .now))
        let shot = try render(s, "now")
        let want = try reference(Labels.cover(for: "OutKast"))
        let got = shot.rgb(Self.screenLeft + 12 + 8, 131)  // left part of the cover, beside the note
        #expect(near(got, want), "cover \(got), want \(want)")
    }

    @Test func aTrackWithNoCoverShowsTheBlueGreySquare() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")  // no cover ID
        s.stack.append(Frame(screen: .now))
        let shot = try render(s, "now-no-cover")
        // The cover's top starts under the 14 point icon row: 47 + 6 + 14 + 2.
        let got = shot.rgb(Self.screenLeft + 12 + 6, 75), want = try reference(0xd5dee8)
        #expect(near(got, want), "placeholder \(got), want \(want)")
    }

    @Test func nowPlayingShowsTheLoadedCover() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:2")
        s.stack.append(Frame(screen: .now))
        let red = try #require(Self.solidImage(red: 1, green: 0, blue: 0))
        let wanted = String(repeating: "ab", count: 20)
        let shot = try render(s, "now-cover", artwork: Artwork { $0 == wanted ? red : nil })
        let got = shot.rgb(Self.screenLeft + 12 + 38, 131)  // the middle of the cover, where the note was
        #expect(got.r > 200 && got.g < 60 && got.b < 60, "cover \(got)")
    }

    @Test func theLastCoverStaysWhileTheNextOneLoads() throws {
        let red = try #require(Self.solidImage(red: 1, green: 0, blue: 0))
        let blue = try #require(Self.solidImage(red: 0, green: 0, blue: 1))
        #expect(CoverArt.shown(fresh: blue, pending: false, last: red) === blue)
        #expect(CoverArt.shown(fresh: nil, pending: true, last: red) === red)  // no flash to the square
        #expect(CoverArt.shown(fresh: nil, pending: false, last: red) == nil)  // no cover, or it failed
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
        // The bottom row is 24 points high over the 6 point padding, so bars center at y 209.
        #expect(volume.isBlue(80, 209))  // inside the 60% glossy fill
        #expect(volume.isLight(230, 209))  // past it
        s.nowMode = .scrub
        s.showArt = false
        s.t = 102.5  // half of the track
        let scrub = try render(s, "now-scrub")
        // The times sit on the bar's line: 28 + 6 points on the left, 6 + 32 on the right.
        let start: Int = Self.screenLeft + 12 + 34, end: Int = Self.screenLeft + 252 - 12 - 38
        #expect(scrub.isBlue((start + end) / 2, 209))  // the blue diamond at the half
        #expect(scrub.isLight(start + 10, 209))  // a thin light track, no fill
        #expect(scrub.isLight(end - 10, 209))
    }

    @Test func nowPlayingSliders() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.stack.append(Frame(screen: .now))
        s.nowMode = .shuffle
        s.shuffle = true
        let on = try render(s, "now-shuffle")
        // The slider fills the 42 points over the bottom padding. The knob sits on its 6 point track.
        let right: Int = Self.screenLeft + 12 + 6 + 216, left: Int = Self.screenLeft + 12 + 6, knobY: Int = 200
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
        let toastX: Int = Self.screenLeft + 24, toastY: Int = 195  // 6 points above the toast's bottom, 26 above the screen's
        #expect(shot.isDark(toastX, toastY))  // the toast's dark box
    }

    @Test func pressedCenterFlipsItsGradient() throws {
        let wheelTop: Int = 261  // device border 1, padding 24, screen 204, gap 32
        let nearTop: Int = wheelTop + 98 - 30, nearBottom: Int = wheelTop + 98 + 30
        let up = try render(AppState(), "wheel")
        let down = try render(AppState(), "wheel-pressed", pressed: .center)
        #expect(up.isLight(150, wheelTop + 60))  // the ring
        // Up, the button is lighter at the top. Pressed, the gradient flips.
        #expect(up.rgb(150, nearTop).b > up.rgb(150, nearBottom).b)
        #expect(down.rgb(150, nearTop).b < down.rgb(150, nearBottom).b)
    }

    @Test func pausedMarkIsTwoBars() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.isPlaying = false
        let shot = try render(s, "main-paused")
        // The header mark: two blue bars, 2.6 points wide with a 1.8 point gap, at the right of the header.
        let left: Int = Self.screenLeft + 252 - 8 - 9, midY: Int = 25 + 2 + 10
        #expect(shot.isBlue(left + 2, midY))  // the first bar
        #expect(!shot.isBlue(left + 5, midY))  // the gap
        #expect(shot.isBlue(left + 7, midY))  // the second bar
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
        _ = try render(s, "now-icons")  // shuffle dark, repeat dark with its "1"
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
