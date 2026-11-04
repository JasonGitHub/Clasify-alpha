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

No Xcode project yet. Swift 6, Xcode + Swift Package Manager; librespot (Rust) builds with cargo. Minimum macOS is 14.

- `ClasifyCore/` (store and reducer) is plain Swift with no Apple UI frameworks. It builds and tests on Linux: `cd ClasifyCore && swift build -Xswiftc -warnings-as-errors && swift test -Xswiftc -warnings-as-errors`. CI runs the same on Linux (`.github/workflows/core.yml`).
- The app itself builds on GitHub Actions macOS runners. Cloud sessions run on Linux and cannot run `xcodebuild`, so say in the PR when an app change was not built or tested locally.

## Hard constraints

- IMPORTANT: no dependencies beyond Apple frameworks and librespot. Don't add a Swift package, CocoaPod or Rust crate without asking first.
- Swift 6 language mode, strict concurrency on, zero compiler warnings. Don't silence concurrency errors with `@unchecked Sendable` or `nonisolated(unsafe)` without a comment saying why it is safe.
- Network calls go only to Spotify and to the GitHub Releases API for the update check. No analytics. No crash reporting in 1.0.
- Tokens go in the Keychain, settings in UserDefaults. Write nothing else to disk. Run librespot with no credentials cache and no audio cache. Write no log files.
- librespot streams the current track to a temp file in the system temp folder and deletes it after the track. This is the only exception to the disk rule.
- The library is read-only. Never call Spotify endpoints that modify playlists or Liked Songs.
- librespot is linked as a static Rust library over a C FFI, not run as a spotifyd helper process.
- 1.0 ships only the built-in librespot engine. The Spotify-app engine is out of 1.0: don't build it or show its setting, but keep playback behind the `Player` protocol so it can be added later.
- Two questions are still open. Don't settle them in code; ask Jason: whether library reads need a Web API fallback, and SwiftUI vs AppKit for the skinned window.

## Architecture

- One store holds all app state. Only the reducer changes it. The reducer is plain Swift with no UI or engine imports.
- Skins send input actions (wheel, select, menu, play, next, prev) and render state. No logic in skins.
- All playback goes through the `Player` protocol. Code above it must not know which engine is playing. librespot is pinned to one version.
- Audio out and EQ: AVAudioEngine + AVAudioUnitEQ. Spectrum: Accelerate vDSP. Media keys: MPRemoteCommandCenter. Update check: URLSession, not Sparkle.

## Testing

- Swift Testing, not XCTest.
- Every `Action` case gets a unit test.
- Tests use a fake `Player`. They never touch Spotify or the network.
- Skins get snapshot tests of their main screens, made with Apple APIs only: `ImageRenderer` for SwiftUI views, `NSView.cacheDisplay(in:to:)` for AppKit views. No snapshot-testing package. These run on macOS CI only.

## Pocket skin mockup

`Pocket-Full.dc.html` (from Clasify.zip in the project files) is the spec for 1.0 screens, actions and edge cases: login, browse, play, settings, offline, expired session. Copy its colors, fonts, sizes, spacing and radii from the inline styles into native views; don't port its HTML or JS. Its strings say "Mixtape", the old name. Use "Clasify".

## Communication

When you reply to Jason or explain something, make readability the first priority. Follow ASD-STE100 Simplified Technical English about 80% of the way:

- Keep sentences short: about 20 words for instructions and 25 for descriptions.
- Use active voice. Give one instruction per sentence.
- Use common words, and use one term for one thing. Avoid idioms and long noun stacks.
- Use exact code names, commands and technical terms as they are. Don't simplify them away.

## Pull requests

- One fix or feature per PR, ideally under 200 changed lines, with a description of what changed and why.
- PR titles become CHANGELOG lines, so write each title as a one-line changelog entry.
- CI must be green (build with zero warnings, all tests pass) before merging.

## Code review with Codex

When a PR is ready to merge, comment `@codex review` on it. Then work through what Codex reports:

- Fix significant findings: bugs, data loss, security problems, or a mismatch with the design doc or mockup. Verify each finding against the code before you change anything.
- Don't push only for style nits. Answer them in their thread.
- If you decline a finding, say why in its thread.
- After a fix, push and comment `@codex review` again. Stop when a review has no significant findings.
- After 3 rounds that still have significant findings, stop and ask the CTO thread. The CTO decides whether to merge, fix more, or escalate to Jason.

## Merging

A thread squash-merges its own PR only when all of these are true. Otherwise it asks Jason.

- CI is green on the latest commit.
- The Codex loop has ended with no significant findings on the latest commit, or the CTO thread decided to merge after 3 rounds.
- The CTO thread has approved the latest commit. A rebase that does not change the PR's diff keeps the approval.
- No question for Jason is open, such as a new dependency, a product choice, or a step that needs his Mac.
- Every PR it depends on has merged.

The CTO thread can escalate any PR to Jason. An escalated PR waits for Jason to merge it.
