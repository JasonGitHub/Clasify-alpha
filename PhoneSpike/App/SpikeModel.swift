import ClasifyAppleMusic
import ClasifyCore
import Foundation
@preconcurrency import MusicKit
import SwiftUI
import UIKit

/// CLA-202 spike: drives the shared `AppleMusicLibrary` and `AppleMusicPlayer` as the Store
/// would, and feeds the `Probe`. Names show on screen only; the report never holds them.
@MainActor @Observable final class SpikeModel {
    @ObservationIgnored let library = AppleMusicLibrary(covers: NoLibraryCovers())  // no iTunesLibrary on the phone
    @ObservationIgnored let player = AppleMusicPlayer(volume: nil)  // the phone's volume stays with iOS
    @ObservationIgnored let probe = Probe()

    var auth = "not asked"
    var subscription = "not read"
    var lists: [ClasifyCore.Playlist] = []
    var nowTitle = ""
    var playing = false
    var cover: UIImage?
    var report: [String] = []

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var songs: [String: ClasifyCore.Track] = [:]
    @ObservationIgnored private var coverFor: String?
    /// No URL cache: covers stay in memory only, as on the Mac (`ArtworkLoader`).
    @ObservationIgnored private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// The Audio background mode is on in this build (scheme "PhoneSpike"), or off ("PhoneSpike NoBG").
    let audioMode = (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("audio") == true

    init() {
        player.send = { [weak self] action in self?.heard(action) }
        player.setActive(true)
        log("build: Audio background mode \(audioMode ? "on" : "off")")
    }

    func log(_ text: String) {
        probe.log(text)
        report = probe.lines
    }

    // MARK: - Access and lists

    func start() async {
        let result = await library.logIn(page: nil)  // MusicAuthorization.request(), then the subscription
        auth = "\(MusicAuthorization.currentStatus)"
        log("access: \(auth), login result: \(result)")
        if let sub = try? await MusicSubscription.current {
            subscription = "can play catalog: \(sub.canPlayCatalogContent), can subscribe: \(sub.canBecomeSubscriber)"
        } else {
            subscription = "read failed"
        }
        log("subscription: \(subscription)")
        guard result != .denied else { return }
        let clock = ContinuousClock.now
        let read = await library.playlists()
        log("playlists read: \(read.map { "\($0.count)" } ?? "failed") in \(clock.duration(to: .now))")
        lists = [ClasifyCore.Playlist(id: ClasifyCore.Playlist.likedSongsID, name: "Favorite Songs", tracks: [])] + (read ?? [])
    }

    func play(_ list: ClasifyCore.Playlist) async {
        let tapped = Date.now, clock = ContinuousClock.now
        generation += 1  // from the tap on, reports of the song that played before are not this play's
        let mine = generation
        let tracks = await library.tracks(of: list.id)
        log("list read: \(tracks.map { "\($0.count) songs" } ?? "failed") in \(clock.duration(to: .now))")
        guard mine == generation, let tracks, let first = tracks.first else { return }  // a newer tap or skip wins
        for track in tracks { songs[track.id] = track }
        probe.play(tapped: tapped)
        report = probe.lines
        player.load(trackID: first.id, context: list.id, autoplay: true, generation: generation)
    }

    func next() { generation += 1; probe.skip(true); report = probe.lines; player.next(generation: generation) }
    func prev() { generation += 1; probe.skip(false); report = probe.lines; player.prev(generation: generation) }

    func playPause() {
        if playing { player.pause(); playing = false; log("pause pressed") } else { player.resume(); log("resume pressed") }
    }

    // MARK: - Reports from the player

    private func heard(_ action: Action) {
        switch action {
        case .position(let t, let gen) where gen == generation:
            probe.position(t)
        case .trackChanged(let id, let isPlaying, let gen) where gen == generation:
            playing = isPlaying
            let track = songs[id]
            nowTitle = track.map { "\($0.title) - \($0.artist)" } ?? "(unknown song)"
            probe.trackChanged(id, playing: isPlaying, duration: track?.duration ?? 0)
            loadCover(track)
        case .trackEnded(let gen) where gen == generation:
            playing = false
            probe.ended()
        case .loadFailed(let message, _): probe.error("load failed", message)
        case .playbackFailed(let message, _): probe.error("playback failed", message)
        case .controlLost: probe.log("control lost")
        case .controlBack: probe.log("control back")
        default: return
        }
        report = probe.lines
    }

    /// One cover from MusicKit's Artwork URL (`*.mzstatic.com`), in memory only.
    private func loadCover(_ track: ClasifyCore.Track?) {
        guard let id = track?.coverID, id != coverFor else { return }
        coverFor = id
        guard let url = CoverURL.url(for: id) else { return log("cover: no allowed URL") }
        Task {
            guard let data = try? await session.data(from: url).0, coverFor == id else { return log("cover: read failed") }
            cover = UIImage(data: data)
            log("cover: \(cover == nil ? "bad image" : "shown"), \(data.count / 1024) KB")
        }
    }

    // MARK: - Background

    func phaseChanged(_ phase: ScenePhase) {
        let state = ApplicationMusicPlayer.shared.state
        let status = "\(state.playbackStatus)"
        let time = ApplicationMusicPlayer.shared.playbackTime
        switch phase {
        case .background: probe.background(audioMode: audioMode, status: status, time: time)
        case .active: probe.active(status: status, time: time)
        default: return
        }
        report = probe.lines
    }

    // MARK: - Reducer check

    func reducerCheck() async {
        #if DEBUG
        log("reducer, main thread, Store: \(await ReducerRun.storeOnMain())")
        log("reducer, main thread, reduce: \(ReducerRun.reduceOnly())")
        log("reducer, thread with 512 KB stack, reduce: \(await ReducerRun.onSmallThread())")
        #else
        log("reducer check runs only in a Debug build")
        #endif
    }

    func copyReport() {
        UIPasteboard.general.string = (["myPod phone spike report (CLA-202)"] + probe.lines).joined(separator: "\n")
    }
}
