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
#define LSB_ERR_READ 4

#define LSB_EVENT_LOGGED_IN 0
#define LSB_EVENT_PLAYING 1
#define LSB_EVENT_PAUSED 2
#define LSB_EVENT_POSITION 3
#define LSB_EVENT_TRACK_ENDED 4
#define LSB_EVENT_UNAVAILABLE 5
#define LSB_EVENT_VOLUME 6
#define LSB_EVENT_ERROR 7
#define LSB_EVENT_PLAY_REQUEST 8

typedef struct LsbBridge LsbBridge;

typedef struct LsbEvent {
    uint32_t kind;             // One of LSB_EVENT_*.
    uint32_t position_ms;      // PLAYING, PAUSED, POSITION.
    uint64_t play_request_id;  // PLAY_REQUEST and track events, else 0.
    uint16_t volume;           // VOLUME. 0 to 65535.
    const char *track_uri;     // Track events, else NULL. Like "spotify:track:<id>".
    const char *message;       // ERROR: the error. LOGGED_IN: the canonical username. Else NULL.
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

// OAuth with PKCE through librespot-oauth, with librespot's own client ID and
// read-only scopes. The bridge stores no token: keep the refresh token in the Keychain.
// Never log or store the access token.
typedef struct LsbToken {
    int32_t status;              // LSB_OK or LSB_ERR_OAUTH.
    uint32_t expires_in_s;       // LSB_OK: seconds until the access token expires.
    const char *access_token;    // LSB_OK only, else NULL.
    const char *refresh_token;   // LSB_OK and Spotify sent one, else NULL.
    const char *message;         // LSB_ERR_OAUTH only, else NULL.
    // The strings are valid only during the callback.
} LsbToken;

typedef void (*LsbTokenCallback)(void *context, const LsbToken *result);
// Opens the Spotify login page in the browser and waits for the redirect to
// http://127.0.0.1:8898/login. The result comes once, on a bridge thread.
// A login that still runs is stopped first, as with lsb_oauth_cancel.
int32_t lsb_oauth_login(LsbTokenCallback on_result, void *context);
// Stops the running lsb_oauth_login. Its callback sends LSB_ERR_OAUTH before this
// returns, also when the browser already sent the code, and port 8898 is free again.
// Only a login whose token exchange had already finished still sends its token. Does nothing if no login runs.
// lsb_oauth_login and lsb_oauth_cancel wait for the old login's callback, so they
// can block. Call them off the main thread. The token callback may call them, but
// it must not wait for the thread that calls them (no sync hop to it).
int32_t lsb_oauth_cancel(void);
// Gets a new access token. The result comes once, on a bridge thread. Its
// refresh_token is NULL when Spotify keeps the old one.
int32_t lsb_oauth_refresh(const char *refresh_token, LsbTokenCallback on_result, void *context);

// Library reads through librespot's session, not the Web API. They only read.
// Each needs a login (else LSB_ERR_NOT_LOGGED_IN) and sends its result once, on a
// bridge thread: LSB_OK with the items, or LSB_ERR_READ with a message and no items.
// lsb_free drops reads that have not finished, and their callbacks never come.
// The strings and arrays are valid only during the callback.
typedef struct LsbPlaylist {
    const char *uri;             // Like "spotify:playlist:<id>".
    const char *name;
    uint32_t track_count;
} LsbPlaylist;

typedef struct LsbTrack {
    const char *uri;             // Like "spotify:track:<id>".
    const char *title;
    const char *artist;          // All artists, joined with ", ".
    uint32_t duration_ms;
} LsbTrack;

typedef void (*LsbPlaylistsCallback)(void *context, int32_t status, const char *message,
                                     const LsbPlaylist *playlists, size_t count);
typedef void (*LsbTracksCallback)(void *context, int32_t status, const char *message,
                                  const LsbTrack *tracks, size_t count);
// The playlists in the user's list, in order. Folders are flattened.
int32_t lsb_read_playlists(LsbBridge *bridge, LsbPlaylistsCallback on_result, void *context);
// All tracks of a playlist ("spotify:playlist:<id>"), or of Liked Songs when
// playlist_uri is NULL, in order and over all pages. Episodes, local files and
// tracks without details are left out.
int32_t lsb_read_tracks(LsbBridge *bridge, const char *playlist_uri,
                        LsbTracksCallback on_result, void *context);

#endif
