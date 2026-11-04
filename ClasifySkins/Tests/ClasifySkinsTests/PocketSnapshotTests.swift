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
        /// The scrub fill, #9aa6b2: mid gray with a little blue.
        func isGray(_ x: Int, _ y: Int) -> Bool {
            let c = rgb(x, y); return (130...200).contains(c.r) && c.b > c.r && c.b - c.r < 45
        }
    }

    // Points in the mockup layout: the device border 1, its padding 24 x 20, the screen border 2,
    // the header 20 plus a 1 point line, and each row 24.
    static let screenLeft = 23, listTop = 48, rowHeight = 24

    static func rowCenter(_ index: Int) -> Int { listTop + index * rowHeight + rowHeight / 2 }

    func render(_ state: AppState, _ name: String, pressed: ClickWheel.Zone? = nil) throws -> Snapshot {
        let renderer = ImageRenderer(content: PocketSkin(state: state, interactive: false, pressed: pressed))
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
        #expect(shot.isLight(50, 37))  // the header, left of the title
    }

    @Test func mainMenuWithTheBar() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.isPlaying = true
        s.top.sel = 1
        let shot = try render(s, "main")
        #expect(shot.isLight(150, Self.rowCenter(0)))
        #expect(shot.isBlue(150, Self.rowCenter(1)))
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

    @Test func nowPlayingVolumeAndScrub() throws {
        var s = sampleState()
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:1")
        s.stack.append(Frame(screen: .now))
        s.overlayUntil = 1
        s.volume = 60
        let volume = try render(s, "now-volume")
        // The volume bar is 8 points high, centered 21 points above the screen's bottom.
        #expect(volume.isBlue(80, 206))  // inside the 60% fill
        #expect(volume.isLight(230, 206))  // past it
        s.nowMode = .scrub
        s.showArt = false
        s.t = 102.5  // half of the track
        let scrub = try render(s, "now-scrub")
        // The progress bar sits at the top of its 22 point row.
        #expect(scrub.isGray(80, 199))  // the scrub fill
        #expect(scrub.isDark(148, 199))  // the diamond at the fill's end
        #expect(scrub.isLight(230, 199))
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
        // The header mark: two 3 point bars with a 4 point gap, 9 points tall, at the left of the header.
        let left: Int = Self.screenLeft + 8, midY: Int = 25 + 2 + 10
        #expect(shot.isDark(left + 1, midY))  // the first bar
        #expect(!shot.isDark(left + 5, midY))  // the gap
        #expect(shot.isDark(left + 8, midY))  // the second bar
    }

    /// The mockup states that the other tests do not draw. Each one must render at full size.
    @Test func otherMockupStates() throws {
        var s = sampleState()
        _ = try render(s, "main-idle")  // nothing plays: no Now Playing row and no bar

        s.current = TrackRef(playlist: "spotify:playlist:a", track: "spotify:track:r2")
        s.isPlaying = true
        s.stack.append(Frame(screen: .tracks(playlist: "spotify:playlist:a")))
        _ = try render(s, "tracks-playing")  // the playing row shows ▶

        s.offline = true
        _ = try render(s, "offline")  // OFF in the header
        s.offline = false

        s.shuffle = true
        s.repeatMode = .one
        s.stack.append(Frame(screen: .now))
        _ = try render(s, "now-flags")  // SHUFFLE REPEAT 1

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
