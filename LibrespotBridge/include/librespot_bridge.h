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

#define LSB_EVENT_LOGGED_IN 0
#define LSB_EVENT_PLAYING 1
#define LSB_EVENT_PAUSED 2
#define LSB_EVENT_POSITION 3
#define LSB_EVENT_TRACK_ENDED 4
#define LSB_EVENT_UNAVAILABLE 5
#define LSB_EVENT_VOLUME 6
#define LSB_EVENT_ERROR 7

typedef struct LsbBridge LsbBridge;

typedef struct LsbEvent {
    uint32_t kind;          // One of LSB_EVENT_*.
    uint32_t position_ms;   // PLAYING, PAUSED, POSITION.
    uint16_t volume;        // VOLUME. 0 to 65535.
    const char *message;    // ERROR only, else NULL. Valid only during the callback.
} LsbEvent;

typedef void (*LsbEventCallback)(void *context, const LsbEvent *event);
// Interleaved stereo float samples at 44.1 kHz. `count` is the number of floats.
// The callback must block until it has room for the samples, for example in a
// bounded ring buffer that AVAudioEngine drains. librespot paces playback by this
// blocking. If the callback returns at once, librespot decodes the whole track in
// seconds, and the position and track-ended events come too early.
typedef void (*LsbAudioCallback)(void *context, const float *samples, size_t count);

// Returns NULL if the bridge cannot start.
LsbBridge *lsb_new(LsbEventCallback on_event, LsbAudioCallback on_audio, void *context);
void lsb_free(LsbBridge *bridge);

// Sends LSB_EVENT_LOGGED_IN or LSB_EVENT_ERROR. Stores no credentials on disk.
// Calling it again replaces the session and player when the new login succeeds.
int32_t lsb_login(LsbBridge *bridge, const char *access_token);
// `track_uri` is like "spotify:track:<id>".
int32_t lsb_load(LsbBridge *bridge, const char *track_uri, bool start_playing, uint32_t position_ms);
int32_t lsb_play(LsbBridge *bridge);
int32_t lsb_pause(LsbBridge *bridge);
int32_t lsb_seek(LsbBridge *bridge, uint32_t position_ms);
int32_t lsb_set_volume(LsbBridge *bridge, uint16_t volume);

#endif
