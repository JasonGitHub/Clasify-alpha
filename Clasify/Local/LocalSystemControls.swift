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
    }

    /// On macOS the state must follow every change, or the keys do not come to myPod.
    /// The words and the length come from the library read; no file is opened for them, and no cover is shown.
    func show(_ now: LocalNowPlaying) {
        guard active else { return }
        guard let shown = now.info else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
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
        info.nowPlayingInfo = values
        info.playbackState = now.state == .playing ? .playing : .paused
    }
}
