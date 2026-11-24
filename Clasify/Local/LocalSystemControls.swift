import AppKit
import ClasifyCore
import MediaPlayer

/// CLA-179: the Mac's media keys and Now Playing for local songs. The only code that touches
/// `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`. It holds the keys only while Local is
/// the active service (`activate` / `deactivate`); otherwise they go to other apps.
@MainActor
final class LocalSystemControls {
    /// A key or a Now Playing control was pressed.
    var onCommand: (LocalNowPlaying.Command) -> Void = { _ in }

    private let commands = MPRemoteCommandCenter.shared()
    private let info = MPNowPlayingInfoCenter.default()
    private var active = false
    /// The shown song's cover and the panel's image of it (read in memory, never written to disk).
    private var cover = LocalCover()
    private var artwork: MPMediaItemArtwork?

    /// The commands that myPod takes. Every other one is off, so the panel shows no dead control.
    private var used: [(MPRemoteCommand, LocalNowPlaying.Command)] {
        [(commands.playCommand, .play), (commands.pauseCommand, .pause), (commands.togglePlayPauseCommand, .toggle),
         (commands.nextTrackCommand, .next), (commands.previousTrackCommand, .previous)]
    }
    private var unused: [MPRemoteCommand] {
        [commands.stopCommand, commands.changePlaybackPositionCommand, commands.skipForwardCommand,
         commands.skipBackwardCommand, commands.seekForwardCommand, commands.seekBackwardCommand,
         commands.changeRepeatModeCommand, commands.changeShuffleModeCommand, commands.changePlaybackRateCommand,
         commands.ratingCommand, commands.likeCommand, commands.dislikeCommand, commands.bookmarkCommand,
         commands.enableLanguageOptionCommand, commands.disableLanguageOptionCommand]
    }

    func activate() {
        guard !active else { return }
        active = true
        for (command, kind) in used {
            command.isEnabled = true
            _ = command.addTarget { [weak self] _ in
                // MediaPlayer calls this on the main thread.
                MainActor.assumeIsolated { self?.onCommand(kind) }
                return .success
            }
        }
        for command in unused { command.isEnabled = false }
    }

    /// The keys go back to other apps: no target, no info, stopped.
    func deactivate() {
        guard active else { return }
        active = false
        for (command, _) in used {
            command.removeTarget(nil)
            command.isEnabled = false
        }
        info.nowPlayingInfo = nil
        info.playbackState = .stopped
        cover = LocalCover()
        artwork = nil
    }

    /// On macOS the state must follow every change, or the keys do not come to myPod.
    /// The words and the length come from the library read; no file is opened for them, and no cover is shown.
    func show(_ now: LocalNowPlaying) {
        guard active else { return }
        guard let shown = now.info else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            if cover.show(nil) { artwork = nil }
            return
        }
        if cover.show(shown.cover) {
            artwork = nil  // never the last song's cover
            if let wanted = cover.wanted { read(wanted) }
        }
        var values: [String: Any] = [
            MPMediaItemPropertyTitle: shown.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: shown.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: shown.rate,
        ]
        if let artist = shown.artist { values[MPMediaItemPropertyArtist] = artist }
        if let album = shown.album { values[MPMediaItemPropertyAlbumTitle] = album }
        if let duration = shown.duration { values[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { values[MPMediaItemPropertyArtwork] = artwork }
        info.nowPlayingInfo = values
        info.playbackState = now.state == .playing ? .playing : .paused
    }

    /// Reads the cover from the Music app library, in memory, as the skins' `ArtworkLoader`
    /// does. It shows only if the song is still the shown one when the read ends.
    private func read(_ id: String) {
        guard let key = LibraryCover.parse(id) else { return }
        Task { [weak self] in
            let image = await AppleMusicArt.shared.image(key.persistentID, side: key.side)
            self?.arrived(id, image)
        }
    }

    private func arrived(_ id: String, _ image: AppleMusicArt.Image?) {
        guard active, cover.arrived(id, found: image != nil), let image else { return }
        let made = Self.artwork(image)
        artwork = made
        info.nowPlayingInfo?[MPMediaItemPropertyArtwork] = made
    }

    /// Made outside the main actor: MediaPlayer calls the handler on its own queue.
    private nonisolated static func artwork(_ image: AppleMusicArt.Image) -> MPMediaItemArtwork {
        let side = CGSize(width: image.cgImage.width, height: image.cgImage.height)
        return MPMediaItemArtwork(boundsSize: side) { size in NSImage(cgImage: image.cgImage, size: size) }
    }
}
