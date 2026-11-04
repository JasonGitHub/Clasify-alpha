// C interface to the librespot bridge (Rust static library).
// Keep in sync with src/lib.rs. The `header_matches_rust` test checks the constants.
// The bridge plays no audio. It logs in, reads the library, and sends Spotify
// Connect commands to the Spotify app.
//
// Threads: callbacks run on bridge threads, not the main thread. `context`
// and the callbacks must be safe to call from any thread.
// The calls return at once. Results come through callbacks.
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
#define LSB_ERR_CONNECT 5

#define LSB_EVENT_LOGGED_IN 0
#define LSB_EVENT_ERROR 1

typedef struct LsbBridge LsbBridge;

typedef struct LsbEvent {
    uint32_t kind;             // One of LSB_EVENT_*.
    const char *message;       // LOGGED_IN: the canonical username. ERROR: the error.
    // The message is valid only during the callback.
} LsbEvent;

typedef void (*LsbEventCallback)(void *context, const LsbEvent *event);

// Returns NULL if on_event is NULL or the bridge cannot start.
LsbBridge *lsb_new(LsbEventCallback on_event, void *context);
void lsb_free(LsbBridge *bridge);

// Sends LSB_EVENT_LOGGED_IN or LSB_EVENT_ERROR. Stores no credentials on disk.
// Calling it again replaces the session when the new login succeeds.
// A superseded login sends no result, except in a narrow race: if lsb_login is
// called again just as an earlier login succeeds, both can send LOGGED_IN.
// If the newer login succeeds, it still replaces the older one.
int32_t lsb_login(LsbBridge *bridge, const char *access_token);

// Ends the session, so reads and Connect calls return LSB_ERR_NOT_LOGGED_IN.
// A login that has not finished sends no event. Returns LSB_OK even with no session.
int32_t lsb_logout(LsbBridge *bridge);

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

// Spotify Connect. Clasify plays no audio: it tells the Spotify app's Connect device
// what to play. Before the first call of each login, the bridge registers this session
// as a Connect device named "Clasify". It is not a player (can_be_player is false)
// and plays no audio. If a command other than next or prev fails, the bridge registers
// again once and sends it once more. Only the requests below can be sent. There is no
// call that takes an endpoint path.
// Each call needs a login (else LSB_ERR_NOT_LOGGED_IN). The calls run one at a time, in
// call order, and each sends its result once, on a bridge thread: LSB_OK, or
// LSB_ERR_CONNECT with a message. lsb_free drops calls that have not finished, and
// their callbacks never come. The strings and arrays are valid only during the callback.
#define LSB_COMMAND_PAUSE 0
#define LSB_COMMAND_RESUME 1
#define LSB_COMMAND_NEXT 2
#define LSB_COMMAND_PREV 3

#define LSB_OPTION_SHUFFLE 0
#define LSB_OPTION_REPEAT_CONTEXT 1
#define LSB_OPTION_REPEAT_TRACK 2

typedef struct LsbDevice {
    const char *id;
    const char *name;
    const char *device_type;     // Like "COMPUTER" or "SMARTPHONE".
    const char *software;        // The device's software version.
    bool is_active;              // The device that plays now.
} LsbDevice;

typedef void (*LsbDevicesCallback)(void *context, int32_t status, const char *message,
                                   const LsbDevice *devices, size_t count);
typedef void (*LsbCommandCallback)(void *context, int32_t status, const char *message);
// Registers this session again and lists the account's other Connect devices, by name.
int32_t lsb_connect_devices(LsbBridge *bridge, LsbDevicesCallback on_result, void *context);
// Plays context_uri on device_id, from track_uri, or from the start when track_uri is
// NULL. context_uri is "spotify:playlist:<id>" or, for Liked Songs,
// "spotify:user:<username>:collection" with the username from LSB_EVENT_LOGGED_IN.
// track_uri is "spotify:track:<id>". device_id has only letters, digits, '-' and '_'.
int32_t lsb_connect_play(LsbBridge *bridge, const char *device_id, const char *context_uri,
                         const char *track_uri, LsbCommandCallback on_result, void *context);
// command is one of LSB_COMMAND_*.
int32_t lsb_connect_command(LsbBridge *bridge, const char *device_id, uint32_t command,
                            LsbCommandCallback on_result, void *context);
int32_t lsb_connect_seek(LsbBridge *bridge, const char *device_id, uint32_t position_ms,
                         LsbCommandCallback on_result, void *context);
// volume is 0 to 65535.
int32_t lsb_connect_volume(LsbBridge *bridge, const char *device_id, uint16_t volume,
                           LsbCommandCallback on_result, void *context);

// Turns Spotify's shuffle, repeat of the context, or repeat of one track on or off.
// option is one of LSB_OPTION_*.
int32_t lsb_connect_set_option(LsbBridge *bridge, const char *device_id, uint32_t option,
                               bool on, LsbCommandCallback on_result, void *context);

// The Spotify app's player, from the account's Connect cluster. The strings are ""
// when there is no value. The context of Liked Songs can come back as a playlist
// URI, so match the playing track, not the context.
typedef struct LsbPlayerState {
    const char *active_device_id; // The device that plays now.
    const char *track_uri;
    const char *context_uri;
    uint32_t position_ms;         // At the time of the callback.
    uint32_t duration_ms;
    bool is_playing;              // A track is loaded. It can be paused.
    bool is_paused;
    bool shuffle;
    bool repeat_context;
    bool repeat_track;
    // The strings are valid only during the callback.
} LsbPlayerState;

typedef void (*LsbStateCallback)(void *context, const LsbPlayerState *state);
// Sets the callback for player state, or clears it when on_state is NULL. The state
// comes after each registration and each cluster update, on a bridge thread. Updates
// start with the first Connect call of a login. When lsb_connect_watch or lsb_free
// returns, the old callback is not running and does not run again, so the caller can
// then free the old context. Do not call lsb_connect_watch or lsb_free from inside
// the callback: they wait for it to return. Keep the callback short.
int32_t lsb_connect_watch(LsbBridge *bridge, LsbStateCallback on_state, void *context);

#endif
