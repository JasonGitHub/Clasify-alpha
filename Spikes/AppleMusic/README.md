# Apple Music spike (never merge)

Tests three ways for Clasify to play Apple Music on macOS 14+ with no other app window on screen.

- **A.** Native MusicKit: `MusicAuthorization`, `MusicLibraryRequest<Playlist>`, `ApplicationMusicPlayer`. Needs a Developer ID signature and the MusicKit service on the App ID `app.clasify.AppleMusicSpike`.
- **B.** Music.app launched hidden (`NSWorkspace.OpenConfiguration.hides`), driven with AppleScript. Playlists from `iTunesLibrary.framework` or AppleScript. `SystemMusicPlayer` is not available on native macOS.
- **C.** MusicKit JS v3 in a 1x1 `WKWebView`. Needs a developer token that Jason makes and pastes. The app keeps it in the Keychain only. Also logs whether FairPlay EME (`com.apple.fps`) is available.

The flash watcher polls on-screen windows every 50 ms. It logs any window of Music.app (or any process named like "Music"), any app activation, and Music's Dock and hidden state. Lines with `FLASH?` need a look.

Spike exceptions to CLAUDE.md, for this branch only: network calls go to Apple, and the build is a SwiftPM executable wrapped by the workflow.
