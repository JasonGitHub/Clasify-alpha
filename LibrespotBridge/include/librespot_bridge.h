// C interface to the librespot bridge (Rust static library).
// Keep in sync with src/lib.rs. The `header_matches_rust` test checks the constants.
//
// Threads: callbacks run on bridge threads, not the main thread. `context`
// and both callbacks must be safe to call from any thread.
// Login, load, play, pause, seek and volume return at once. Results come as events.
// Do not call lsb_free from inside a callback. That drops the bridge's tokio
// runtime on its own thread, which panics, and a panic in an extern "C" function aborts.

#ifndef LIBRESPOT_BRIDGE_H
#define LIBRESPOT_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define LSB_OK 0
#define LSB_ERR_INVALID_ARGUMENT 1
#define LSB_ERR_NOT_LOGGED_IN 2
#define LSB_ERR_OAUTH 3

#define LSB_EVENT_LOGGED_IN 0
#define LSB_EVENT_PLAYING 1
#define LSB_EVENT_PAUSED 2
#define LSB_EVENT_POSITION 3
#define LSB_EVENT_TRACK_ENDED 4
#define LSB_EVENT_UNAVAILABLE 5
#define LSB_EVENT_VOLUME 6
#define LSB_EVENT_ERROR 7
#define LSB_EVENT_PLAY_REQUEST 8
// A librespot log message (info and above) in `message`.
#define LSB_EVENT_LOG 9
// A library read result in `message`. Liked Songs also sets `track_uri` to its first track.
#define LSB_EVENT_LIBRARY 10

typedef struct LsbBridge LsbBridge;

typedef struct LsbEvent {
    uint32_t kind;             // One of LSB_EVENT_*.
    uint32_t position_ms;      // PLAYING, PAUSED, POSITION.
    uint64_t play_request_id;  // PLAY_REQUEST and track events, else 0.
    uint16_t volume;           // VOLUME. 0 to 65535.
    const char *track_uri;     // Track events, else NULL. Like "spotify:track:<id>".
    const char *message;       // ERROR, LOG and LIBRARY only, else NULL.
    // The strings are valid only during the callback.
    // Track events: PLAYING, PAUSED, POSITION, TRACK_ENDED, UNAVAILABLE.
    // PLAY_REQUEST comes once for each lsb_load, in call order, with only the
    // play_request_id that later track events for that load carry. Match it to
    // your loads in order, not by URI: the same URI can be loaded twice.
} LsbEvent;

typedef void (*LsbEventCallback)(void *context, const LsbEvent *event);
// Interleaved stereo float samples at 44.1 kHz. `count` is the number of floats.
// The callback must block until it has room for the samples, for example in a
// bounded ring buffer that AVAudioEngine drains. librespot paces playback by this
// blocking. If the callback returns at once, librespot decodes the whole track in
// seconds, and the position and track-ended events come too early.
// lsb_free joins the playback thread. Before you call it, make the audio
// callback stop blocking (keep draining, or return at once), or lsb_free hangs.
typedef void (*LsbAudioCallback)(void *context, const float *samples, size_t count);

// Returns NULL if a callback is NULL or the bridge cannot start.
LsbBridge *lsb_new(LsbEventCallback on_event, LsbAudioCallback on_audio, void *context);
void lsb_free(LsbBridge *bridge);

// Sends LSB_EVENT_LOGGED_IN or LSB_EVENT_ERROR. Stores no credentials on disk.
// Calling it again replaces the session and player when the new login succeeds.
// A superseded login sends no result, except in a narrow race: if lsb_login is
// called again just as an earlier login succeeds, both can send LOGGED_IN.
// If the newer login succeeds, it still replaces the older one.
// A replaced player sends no more events.
int32_t lsb_login(LsbBridge *bridge, const char *access_token);
// `track_uri` is like "spotify:track:<id>".
int32_t lsb_load(LsbBridge *bridge, const char *track_uri, bool start_playing, uint32_t position_ms);
int32_t lsb_play(LsbBridge *bridge);
int32_t lsb_pause(LsbBridge *bridge);
int32_t lsb_seek(LsbBridge *bridge, uint32_t position_ms);
int32_t lsb_set_volume(LsbBridge *bridge, uint16_t volume);
// Reads the playlists (rootlist) and Liked Songs through librespot, not the Web API.
// Sends two LSB_EVENT_LIBRARY events. Needs a login.
int32_t lsb_read_library(LsbBridge *bridge);

// OAuth login with PKCE through librespot-oauth, with librespot's own client ID.
// Opens the Spotify login page in the browser and listens on the loopback
// redirect http://127.0.0.1:8898/login. The result comes once, on a bridge thread.
// Asks only for read-only scopes. The bridge stores no token.
typedef struct LsbOAuthResult {
    int32_t status;             // LSB_OK or LSB_ERR_OAUTH.
    uint32_t expires_in_s;      // Seconds until the access token expires.
    bool has_refresh_token;
    const char *access_token;   // LSB_OK only, else NULL. Never log or store it.
    const char *scopes;         // Granted scopes, space-separated.
    const char *client_id;
    const char *redirect_uri;
    const char *message;        // LSB_ERR_OAUTH only, else NULL.
    // The strings are valid only during the callback.
} LsbOAuthResult;

typedef void (*LsbOAuthCallback)(void *context, const LsbOAuthResult *result);
int32_t lsb_oauth_login(LsbOAuthCallback on_result, void *context);

#endif
