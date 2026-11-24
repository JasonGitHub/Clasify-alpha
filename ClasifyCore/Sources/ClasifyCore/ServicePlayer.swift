/// The `Player` that the store uses: it sends each call to the player of the active music
/// service (CLA-103). One service is active at a time, so lists and queues never mix.
/// Code above it does not know which engine plays.
public final class ServicePlayer: Player {
    private let spotify: any Player
    private let appleMusic: any Player
    /// CLA-179: the player of On This Mac. nil until the app wires `LocalPlayer`: then On This
    /// Mac plays nothing.
    private let local: (any Player)?
    /// The active service. A change stops the player of the service that was active.
    public var service: MusicService {
        didSet {
            guard service != oldValue else { return }
            player(for: oldValue)?.stop()
            player(for: oldValue)?.setActive(false)
            active?.setActive(true)
        }
    }

    public init(spotify: any Player, appleMusic: any Player, local: (any Player)? = nil, service: MusicService) {
        self.spotify = spotify
        self.appleMusic = appleMusic
        self.local = local
        self.service = service
        active?.setActive(true)  // CLA-168
    }

    private func player(for service: MusicService) -> (any Player)? {
        switch service {
        case .spotify: spotify
        case .appleMusic: appleMusic
        case .local: local
        }
    }

    private var active: (any Player)? { player(for: service) }

    public func load(trackID: String, context: String?, autoplay: Bool, generation: Int) {
        active?.load(trackID: trackID, context: context, autoplay: autoplay, generation: generation)
    }
    public func pause() { active?.pause() }
    public func resume() { active?.resume() }
    public func stop() { active?.stop() }
    public func next(generation: Int) { active?.next(generation: generation) }
    public func prev(generation: Int) { active?.prev(generation: generation) }
    // All players keep shuffle and repeat, so a switch plays with the same modes.
    public func setShuffle(_ on: Bool) { spotify.setShuffle(on); appleMusic.setShuffle(on); local?.setShuffle(on) }
    public func setRepeat(_ mode: RepeatMode) { spotify.setRepeat(mode); appleMusic.setRepeat(mode); local?.setRepeat(mode) }
    public func seek(to seconds: Double, generation: Int) { active?.seek(to: seconds, generation: generation) }
    public func setVolume(_ percent: Int) { active?.setVolume(percent) }
}
