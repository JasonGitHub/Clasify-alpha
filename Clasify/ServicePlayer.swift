import ClasifyCore

/// The `Player` that the store uses: it sends each call to the player of the active music
/// service (CLA-103). One service is active at a time, so lists and queues never mix.
/// Code above it does not know which engine plays.
final class ServicePlayer: Player {
    let spotify: SpotifyConnectPlayer
    let appleMusic: AppleMusicPlayer
    /// The active service. A change stops the player of the service that was active.
    var service: MusicService {
        didSet { if service != oldValue { player(for: oldValue).stop() } }
    }

    init(spotify: SpotifyConnectPlayer, appleMusic: AppleMusicPlayer, service: MusicService) {
        self.spotify = spotify
        self.appleMusic = appleMusic
        self.service = service
    }

    private func player(for service: MusicService) -> any Player {
        switch service {
        case .spotify: spotify
        case .appleMusic: appleMusic
        }
    }

    private var active: any Player { player(for: service) }

    func load(trackID: String, context: String?, autoplay: Bool, generation: Int) {
        active.load(trackID: trackID, context: context, autoplay: autoplay, generation: generation)
    }
    func pause() { active.pause() }
    func resume() { active.resume() }
    func stop() { active.stop() }
    func next(generation: Int) { active.next(generation: generation) }
    func prev(generation: Int) { active.prev(generation: generation) }
    // Both players keep shuffle and repeat, so a switch plays with the same modes.
    func setShuffle(_ on: Bool) { spotify.setShuffle(on); appleMusic.setShuffle(on) }
    func setRepeat(_ mode: RepeatMode) { spotify.setRepeat(mode); appleMusic.setRepeat(mode) }
    func seek(to seconds: Double, generation: Int) { active.seek(to: seconds, generation: generation) }
    func setVolume(_ percent: Int) { active.setVolume(percent) }
}
