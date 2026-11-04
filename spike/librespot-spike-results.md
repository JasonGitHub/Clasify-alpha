# Playback spike results

Spike only. Draft PR #9, never merge. Tests ran on Jason's MacBook Air (M4, macOS 27.0.1, arm64) with a Premium Family account, on 2026-11-04 (JST).

## Summary

1.0 plays through the Spotify desktop app. Clasify starts the app hidden and drives it only with Spotify Connect commands, sent through the librespot session. No AppleScript.

| Route | Result |
|---|---|
| OAuth (librespot client ID, PKCE, loopback redirect) | Works. Refresh token returned. |
| Library reads through librespot (spclient) | Work: 107 playlists, 455 Liked Songs. No Web API needed. |
| Web API with the librespot client ID | 429 QUOTA_EXCEEDED. Unusable. |
| librespot playback (builds 1-3) | Audio key refused (librespot #1649). Closed. |
| Spotify app through AppleScript (builds 4-5) | Window flashes on each play. Ruled out (no-flash rule). |
| go-librespot 0.10.5 (build 6) | Audio key refused. Closed. |
| Web Playback SDK | Parked by Jason. Not tested. |
| Spotify app through Connect commands (builds 7-10) | Works with no flash. Chosen. |

## Connect route: how it works

1. Start the librespot dealer. Take the connection ID from the `Spotify-Connection-Id` header on `hm://pusher/v1/connections/`.
2. PUT a connect-state `PutStateRequest` (NEW_DEVICE). The response Cluster lists the devices. Pick the Spotify app: type COMPUTER, not our own device.
3. Commands: POST `/connect-state/v1/player/command/from/{self}/to/{device}` with endpoint `play` (with a context), `pause`, `resume`, `skip_next`, `skip_prev` or `seek_to` (value in ms).
4. Volume: PUT `/connect-state/v1/connect/volume/from/{self}/to/{device}` with `{"volume":0-65535}`.
5. State and track end: listen to `hm://connect-state/v1/cluster` (ClusterUpdate).

## Build 9 (commit 4038aa3)

- Spotify already running, its window open behind Clasify: play and next caused no window and no activation.
- Controls, latency until the cluster shows the change: pause 909 ms, resume 187, next 683, prev 415, seek 481, volume 184.
- Track end: the next track shows in the cluster about 0.8 s after the end.
- Cold start with NSWorkspace (hides=true, activates=false, no arguments) or `open -g -j`: FAIL. The Spotify window showed and became frontmost about 0.4 s after launch.

## Build 10 (commit ff524ed, Spotify 1.3.6.1921)

- Cold start with NSWorkspace, hides=true, activates=false and arguments:
  - `--minimized`: 0 windows, never active or frontmost. Device in the cluster after 2.6 s, playing at 3.2 s.
  - `--autostart --minimized`: 0 windows, never active or frontmost. Device in the cluster after 1.3 s, playing at 1.7 s. **Use this.**
- Controls again had no window change: pause 408 ms, resume 185, next 371, prev 596, seek 416.
- Liked Songs: play context `spotify:user:<id>:collection` works, and the tracks are from Liked Songs. The cluster reports the context as a playlist URI (`spotify:playlist:37i9dQZF1F5p3rmiWPIYgZ`), not the collection URI. **Match by track, not by context.** `skip_to` with the first track plays that track first.
- Never use `spotify:collection:tracks` as a context: 403 Forbidden, and playback stops.
- Volume showed no cluster update only because the volume was already 32768. This is a test artifact.

## Costs accepted

The Spotify app must be installed and running. It stays in the Dock and uses about 1.5 GB. Connect commands are not a public API.
