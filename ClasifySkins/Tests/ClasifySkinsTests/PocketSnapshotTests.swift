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

    // Points in the mockup layout: the device padding is 24 x 20, the screen border 2,
    // the header 20 plus a 1 point line, and each row 24.
    static let screenLeft = 22, listTop = 47, rowHeight = 24

    static func rowCenter(_ index: Int) -> Int { listTop + index * rowHeight + rowHeight / 2 }

    func render(_ state: AppState, _ name: String) throws -> Snapshot {
        let renderer = ImageRenderer(content: PocketSkin(state: state, interactive: false))
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
        #expect(shot.isLight(50, 36))  // the header, left of the title
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
        let got = shot.rgb(Self.screenLeft + 12 + 8, 130)  // left part of the cover, beside the note
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
        #expect(volume.isBlue(80, 205))  // inside the 60% fill
        #expect(volume.isLight(230, 205))  // past it
        s.nowMode = .scrub
        s.showArt = false
        s.t = 102.5  // half of the track
        let scrub = try render(s, "now-scrub")
        // The progress bar sits at the top of its 22 point row.
        #expect(scrub.isGray(80, 198))  // the scrub fill
        #expect(scrub.isDark(147, 198))  // the diamond at the fill's end
        #expect(scrub.isLight(230, 198))
    }

    @Test func messageAndToast() throws {
        var s = sampleState()
        s.stack.append(Frame(screen: .playlists, loading: true))
        let loading = try render(s, "loading")
        #expect(!loading.isBlue(150, Self.rowCenter(0)))  // no list while loading
        s.stack = [Frame(screen: .login)]
        s.toast = "Logged out"
        let shot = try render(s, "toast")
        let toastX: Int = Self.screenLeft + 24, toastY: Int = 194  // 6 points above the toast's bottom, 26 above the screen's
        #expect(shot.isDark(toastX, toastY))  // the toast's dark box
    }

    @Test func wheelIsDrawn() throws {
        let shot = try render(AppState(), "wheel")
        let wheelTop: Int = 260  // device padding 24, screen 204, gap 32
        let centerY: Int = wheelTop + 98, ringY: Int = wheelTop + 60
        #expect(shot.isLight(150, centerY))  // the center button
        #expect(shot.isLight(150, ringY))  // the ring
    }
}
