<!--
Maintainer notes (stripped before Claude sees this file):
- Keep this file under ~100 lines. For each line, ask: would Claude make a mistake without it? If not, cut it.
- Product scope, rationale and trade-offs live in the design doc, not here. Link, don't copy.
- Add the Build and test section as soon as the Xcode project exists.
- Move rules that only apply to one area (e.g. a skin, the librespot bridge) into .claude/rules/ with `paths:` frontmatter.
- Turn multi-step procedures (e.g. cutting a release) into skills under .claude/skills/.
-->

# Clasify

Native macOS player for Spotify playlists and Liked Songs, styled after early-2000s pocket players. Free, open source, MIT.

Design doc (scope, decisions, open questions): https://claude.ai/artifact/HaQUjogMQiJGJjKdAjpoY8

## Build and test

No Xcode project yet. Swift 6, Xcode + Swift Package Manager; librespot (Rust) builds with cargo.

Cloud sessions run on Linux and cannot run `xcodebuild`. Verify Swift changes through CI on GitHub Actions macOS runners, and say so in the PR when a change was not built or tested locally.

## Hard constraints

- IMPORTANT: no dependencies beyond Apple frameworks and librespot. Don't add a Swift package, CocoaPod or Rust crate without asking first.
- Swift 6 language mode, strict concurrency on, zero compiler warnings. Don't silence concurrency errors with `@unchecked Sendable` or `nonisolated(unsafe)` without a comment saying why it is safe.
- Network calls go only to Spotify and to the GitHub Releases API for the update check. No analytics. Crash reporting is opt-in.
- Tokens go in the Keychain, settings in UserDefaults. Write nothing else to disk.
- The library is read-only. Never call Spotify endpoints that modify playlists or Liked Songs.
- Don't resolve the design doc's open questions (librespot linking, Web API fallback, minimum macOS, SwiftUI vs AppKit) in code. Ask Jason.

## Architecture

- One store holds all app state. Only the reducer changes it. The reducer is plain Swift with no UI or engine imports.
- Skins send input actions (wheel, select, menu, play, next, prev) and render state. No logic in skins.
- All playback goes through the `Player` protocol. Code above it must not know which engine (librespot or the Spotify app) is playing. librespot is pinned to one version.
- Audio out and EQ: AVAudioEngine + AVAudioUnitEQ. Spectrum: Accelerate vDSP. Media keys: MPRemoteCommandCenter. Update check: URLSession, not Sparkle.

## Testing

- Swift Testing, not XCTest.
- Every reducer action gets a unit test: wheel, select, menu, play, next, prev, tick, offline, expire.
- Tests use a fake `Player`. They never touch Spotify or the network.
- Skins get snapshot tests of their main screens.

## Pocket skin mockup

`Pocket-Full.dc.html` (from Clasify.zip in the project files) is the spec for 1.0 screens, actions and edge cases: login, browse, play, settings, offline, expired session. Copy its colors, fonts, sizes, spacing and radii from the inline styles into native views; don't port its HTML or JS. Its strings say "Mixtape", the old name. Use "Clasify".

## Pull requests

- One fix or feature per PR, ideally under 200 changed lines, with a description of what changed and why.
- PR titles become CHANGELOG lines, so write each title as a one-line changelog entry.
- CI must be green (build with zero warnings, all tests pass) before merging.
