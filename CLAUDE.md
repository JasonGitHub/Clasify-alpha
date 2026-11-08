<!--
Maintainer notes (stripped before Claude sees this file):
- Keep this file under ~100 lines. For each line, ask: would Claude make a mistake without it? If not, cut it.
- Product scope, rationale and trade-offs live in the design doc, not here. Link, don't copy.
- Add the Build and test section as soon as the Xcode project exists.
- Move rules that only apply to one area (e.g. a skin, the librespot bridge) into .claude/rules/ with `paths:` frontmatter.
- Turn multi-step procedures (e.g. cutting a release) into skills under .claude/skills/.
-->

# Clasify

Native macOS player for Spotify playlists and Liked Songs, styled after early-2000s pocket players.

Design doc (scope, decisions, open questions): https://claude.ai/artifact/HaQUjogMQiJGJjKdAjpoY8

## Build and test

Swift 6, Xcode + Swift Package Manager; librespot (Rust) builds with cargo. Minimum macOS is 14. It may move to 15 for the plain window style after Jason tests the app.

- `ClasifyCore/` (store and reducer) is plain Swift with no Apple UI frameworks. It builds and tests on Linux: `cd ClasifyCore && swift build -Xswiftc -warnings-as-errors && swift test -Xswiftc -warnings-as-errors`. CI runs the same on Linux (`.github/workflows/core.yml`).
- `LibrespotBridge/` is the librespot static library with its C header: `cd LibrespotBridge && cargo fmt --check && cargo clippy --locked --all-targets -- -D warnings && cargo test --locked`. CI: `.github/workflows/bridge.yml`.
- `ClasifySkins/` holds the SwiftUI skins. They depend on ClasifyCore only, never on the player or the library. It builds and tests on macOS only: `cd ClasifySkins && swift build -Xswiftc -warnings-as-errors && swift test -Xswiftc -warnings-as-errors`. Set `SNAPSHOT_DIR` to save the snapshot PNGs. CI: `.github/workflows/app.yml`, which uploads them as the `skin-snapshots` artifact.
- `Clasify.xcodeproj` builds the app from the `Clasify/` folder. New Swift files there need no project edits. CI: `.github/workflows/app.yml` on macOS runners.
- The app builds only on macOS. Cloud sessions run on Linux and cannot run `xcodebuild`, so say in the PR when an app change was not built or tested locally.

## Hard constraints

- IMPORTANT: no dependencies beyond Apple frameworks and librespot. Don't add a Swift package, CocoaPod or Rust crate without asking first.
- Swift 6 language mode, strict concurrency on, zero compiler warnings. Don't silence concurrency errors with `@unchecked Sendable` or `nonisolated(unsafe)` without a comment saying why it is safe.
- Network calls go only to Spotify and to the GitHub Releases API for the update check. No analytics. No crash reporting in 1.0.
- Album covers come only from Spotify's image CDN, `https://i.scdn.co/image/<coverID>`. `ArtworkLoader` keeps them in memory only: an NSCache and a URLSession with no URL cache. Never write a cover to disk. Skins get covers through the `artwork` environment value and never load them.
- Tokens go in the Keychain, settings in UserDefaults. Write nothing else to disk. Run librespot with no credentials cache and no audio cache. Write no log files.
- The library is read-only. Never call Spotify endpoints that modify playlists or Liked Songs.
- librespot is linked as a static Rust library over a C FFI, not run as a separate helper process.
- 1.0 plays through the Spotify desktop app, behind the `Player` protocol. Clasify starts and controls playback with Spotify Connect commands sent through the librespot session. AppleScript must never start playback or activate Spotify. Launch Spotify hidden.
- librespot is used for login, library reads and Spotify Connect commands, not for audio. Spotify refuses audio keys to librespot (librespot#1649). No PlayPlay or other DRM work.
- Library reads use librespot, with no Web API fallback. The shared Web API client ID is quota-blocked.
- Skins are SwiftUI (Jason decided, 2026-11-04 22:58 JST). Use small AppKit wrappers only where SwiftUI cannot do the job.

## Architecture

- One store holds all app state. Only the reducer changes it. The reducer is plain Swift with no UI or engine imports.
- Skins send input actions (wheel, select, menu, play, next, prev) and render state. No logic in skins.
- All playback goes through the `Player` protocol. Code above it must not know which engine is playing. librespot is pinned to one version.
- EQ and spectrum are out of 1.0, because the audio does not pass through Clasify. Don't show the EQ setting. Media keys: none in Clasify; the hidden Spotify app handles them (Jason tested 2026-11-08, CLA-42 canceled). Update check: URLSession, not Sparkle.

## Testing

- Swift Testing, not XCTest.
- Every `Action` case gets a unit test.
- Tests use a fake `Player` and a fake `Library`. They never touch Spotify or the network.
- Skins get snapshot tests of their main screens, made with Apple APIs only: `ImageRenderer` for SwiftUI views, `NSView.cacheDisplay(in:to:)` for AppKit views. No snapshot-testing package. These run on macOS CI only.

## Pocket skin mockup

`project/Pocket-Full.dc.html` in Jason's design artifact (https://claude.ai/artifact/7TnGYuahnpRDkR2FFkwTHy) is the spec for 1.0 screens, actions and edge cases: login, browse, play, settings, offline, expired session. It replaces the copy in Clasify.zip. `project/Pocket-Compare.dc.html` and `project/Pocket-Compare-2.dc.html` there list the changes from the old copy, as numbered before-and-after cards. Copy its colors, fonts, sizes, spacing and radii from the inline styles into native views; don't port its HTML or JS. Keep Settings to Shuffle, Repeat, Album Art, Clicker, About and Log out: its EQ, Skin and Playback rows are not in 1.0. If its strings say "Mixtape", the old name, use "Clasify".

## Communication

When you reply to Jason or explain something, make readability the first priority. Follow ASD-STE100 Simplified Technical English about 80% of the way:

- Keep sentences short: about 20 words for instructions and 25 for descriptions.
- Use active voice. Give one instruction per sentence.
- Use common words, and use one term for one thing. Avoid idioms and long noun stacks.
- Use exact code names, commands and technical terms as they are. Don't simplify them away.
- Give times in Japan time (JST, UTC+9), for example "18:22 JST". Convert UTC times from GitHub and CI.

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
