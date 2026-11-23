import AppKit
import ClasifyCore
import SwiftUI
import Testing

@testable import ClasifySkins

/// Launch video only, not for merge: the real Pocket screens with real albums, saved as large PNGs of the screen (300 x 225 points at 8x) when SNAPSHOT_DIR is set.
@Suite @MainActor struct LaunchVideoScreens {
    static let scale = 8
    static func coverID(_ i: Int) -> String { String(repeating: String(format: "%02x", 0xc0 + i), count: 20) }
    /// Real albums (Jason, 11-22). The covers are not in the repo: the test reads them at run time from
    /// Apple's iTunes Search API (the same mzstatic.com image server the app uses) and keeps them in memory.
    /// This is the only test that touches the network, and it is not for merge.
    static let songs: [(title: String, artist: String, album: String, duration: Double, term: String)] = [
        ("Come Together", "The Beatles", "Abbey Road", 260, "beatles abbey road"),
        ("Money", "Pink Floyd", "The Dark Side of the Moon", 382, "pink floyd dark side of the moon"),
        ("Bring Me to Life", "Evanescence", "Fallen", 237, "evanescence fallen"),
        ("Man on Fire", "Edward Sharpe & The Magnetic Zeros", "Here", 272, "edward sharpe magnetic zeros here"),
        ("Complicated", "Avril Lavigne", "Let Go", 244, "avril lavigne let go"),
        ("Say It Right", "Nelly Furtado", "Loose", 223, "nelly furtado loose"),
        ("Smells Like Teen Spirit", "Nirvana", "Nevermind", 301, "nirvana nevermind"),
    ]
    nonisolated(unsafe) static var covers: [String: CGImage] = [:]  // filled once on the main actor before any render; read only after

    static func loadCovers() async throws {
        for (i, song) in songs.enumerated() {
            var q = URLComponents(string: "https://itunes.apple.com/search")!
            q.queryItems = [.init(name: "term", value: song.term), .init(name: "entity", value: "album"),
                            .init(name: "limit", value: "5"), .init(name: "country", value: "US")]
            let (json, _) = try await URLSession.shared.data(from: q.url!)
            let obj = try JSONSerialization.jsonObject(with: json) as? [String: Any]
            let results = obj?["results"] as? [[String: Any]] ?? []
            let pick = results.first { ($0["collectionName"] as? String ?? "").localizedCaseInsensitiveContains(song.album) } ?? results.first
            let small = try #require(pick?["artworkUrl100"] as? String, "no cover for \(song.album)")
            let big = try #require(URL(string: small.replacingOccurrences(of: "100x100bb", with: "1000x1000bb")))
            let (img, _) = try await URLSession.shared.data(from: big)
            covers[coverID(i + 1)] = try #require(NSBitmapImageRep(data: img)?.cgImage, "bad image for \(song.album)")
        }
    }

    static func cover(_ id: String) -> CGImage? { covers[id] }

    func state() -> AppState {
        var s = AppState()
        s.signedIn = true
        s.setupDone = true
        s.activated = true
        s.stack = [Frame(screen: .main)]
        s.library = [
            Playlist(id: Playlist.likedSongsID, name: "Liked Songs", tracks: Self.songs.enumerated().map { i, x in
                Track(id: "spotify:track:v\(i + 1)", title: x.title, artist: x.artist, duration: x.duration, coverID: Self.coverID(i + 1),
                      album: Album(id: "spotify:album:v\(i + 1)", name: x.album, artist: x.artist))
            }),
            Playlist(id: "spotify:playlist:v1", name: "Road Trip", tracks: []),
            Playlist(id: "spotify:playlist:v2", name: "2000s Mix", tracks: []),
            Playlist(id: "spotify:playlist:v3", name: "Classics", tracks: []),
        ]
        s.current = TrackRef(playlist: Playlist.likedSongsID, track: "spotify:track:v2")
        s.isPlaying = true
        s.t = 67
        s.artRow = .nowPlaying
        s.refreshArt()
        return s
    }

    func save(_ s: AppState, _ name: String, time: Double = 1) throws {
        let art = Artwork { Self.cover($0) }
        let skin = PocketSkin(state: s, interactive: false, pressed: nil)
            .environment(\.artwork, art)
            .environment(\.animationTime, time)
        let renderer = ImageRenderer(content: skin)
        renderer.scale = CGFloat(Self.scale)
        let image = try #require(renderer.cgImage)
        let k = CGFloat(Self.scale)
        let screen = try #require(image.cropping(to: CGRect(x: 33 * k, y: 32.4 * k, width: 300 * k, height: 225 * k)))
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let rep = NSBitmapImageRep(cgImage: screen)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("video-\(name).png"))
        if name == "main-0" {
            let full = NSBitmapImageRep(cgImage: image)
            try #require(full.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("video-device-main.png"))
        }
    }

    @Test func screensForTheLaunchVideo() async throws {
        try await Self.loadCovers()
        var s = state()
        for sel in 0...6 {
            s.stack[0].sel = sel
            try save(s, "main-\(sel)", time: 1 + Double(sel) * 0.25)
        }
        s.stack[0].sel = 4
        s.stack.append(Frame(screen: .tracks(playlist: Playlist.likedSongsID)))
        for sel in 0...3 {
            s.stack[1].sel = sel
            try save(s, "liked-\(sel)")
        }
        s.stack[1].sel = 1
        s.stack.append(Frame(screen: .now))
        for t in [66.0, 67, 68, 69] {
            s.t = t
            try save(s, "now-\(Int(t))")
        }
        var g = state()
        g.stack[0].sel = 6
        g.stack.append(Frame(screen: .settings))
        try save(g, "settings-spotify")
        g.pendingService = .appleMusic
        try save(g, "settings-apple")
        g.pendingService = nil
        g.stack[1].sel = 4
        try save(g, "settings-color")
        var p = state()
        p.stack[0].sel = 2
        p.stack.append(Frame(screen: .playlists))
        try save(p, "playlists")
        var c = state()
        c.stack[0].sel = 1
        c.stack.append(Frame(screen: .coverFlow))
        try save(c, "coverflow")
    }
}
