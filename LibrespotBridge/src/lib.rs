//! C FFI over librespot. The C header is `include/librespot_bridge.h`.
//! Keep the two in sync: the `header_matches_rust` test checks the constants.

use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use librespot_core::{authentication::Credentials, Session, SessionConfig, SpotifyUri};
use librespot_playback::audio_backend::{Sink, SinkResult};
use librespot_playback::config::PlayerConfig;
use librespot_playback::convert::Converter;
use librespot_playback::decoder::AudioPacket;
use librespot_playback::mixer::{softmixer::SoftMixer, Mixer, MixerConfig};
use librespot_playback::player::{Player, PlayerEvent};

pub const LSB_OK: i32 = 0;
pub const LSB_ERR_INVALID_ARGUMENT: i32 = 1;
pub const LSB_ERR_NOT_LOGGED_IN: i32 = 2;

pub const LSB_EVENT_LOGGED_IN: u32 = 0;
pub const LSB_EVENT_PLAYING: u32 = 1;
pub const LSB_EVENT_PAUSED: u32 = 2;
pub const LSB_EVENT_POSITION: u32 = 3;
pub const LSB_EVENT_TRACK_ENDED: u32 = 4;
pub const LSB_EVENT_UNAVAILABLE: u32 = 5;
pub const LSB_EVENT_VOLUME: u32 = 6;
pub const LSB_EVENT_ERROR: u32 = 7;

/// Matches `LsbEvent` in the header. `message` is valid only during the callback.
#[repr(C)]
pub struct LsbEvent {
    pub kind: u32,
    pub position_ms: u32,
    pub volume: u16,
    pub message: *const c_char,
}

pub type LsbEventCallback = extern "C" fn(context: *mut c_void, event: *const LsbEvent);
/// Interleaved stereo f32 samples at 44.1 kHz.
pub type LsbAudioCallback = extern "C" fn(context: *mut c_void, samples: *const f32, count: usize);

#[derive(Clone, Copy)]
struct Callbacks {
    on_event: LsbEventCallback,
    on_audio: LsbAudioCallback,
    context: *mut c_void,
}

// SAFETY: the header requires that `context` and both callbacks are safe to
// call from any thread. The bridge never reads through `context` itself.
unsafe impl Send for Callbacks {}
unsafe impl Sync for Callbacks {}

impl Callbacks {
    fn emit(&self, kind: u32, position_ms: u32, volume: u16, message: Option<&str>) {
        let text = message.map(|m| CString::new(m.replace('\0', " ")).unwrap_or_default());
        let event = LsbEvent {
            kind,
            position_ms,
            volume,
            message: text.as_ref().map_or(std::ptr::null(), |t| t.as_ptr()),
        };
        (self.on_event)(self.context, &event);
    }
}

/// Maps a librespot event to (kind, position_ms, volume). Other events are dropped.
fn map_event(event: &PlayerEvent) -> Option<(u32, u32, u16)> {
    match event {
        PlayerEvent::Playing { position_ms, .. } => Some((LSB_EVENT_PLAYING, *position_ms, 0)),
        PlayerEvent::Paused { position_ms, .. } => Some((LSB_EVENT_PAUSED, *position_ms, 0)),
        PlayerEvent::PositionChanged { position_ms, .. }
        | PlayerEvent::PositionCorrection { position_ms, .. }
        | PlayerEvent::Seeked { position_ms, .. } => Some((LSB_EVENT_POSITION, *position_ms, 0)),
        PlayerEvent::EndOfTrack { .. } => Some((LSB_EVENT_TRACK_ENDED, 0, 0)),
        PlayerEvent::Unavailable { .. } => Some((LSB_EVENT_UNAVAILABLE, 0, 0)),
        PlayerEvent::VolumeChanged { volume } => Some((LSB_EVENT_VOLUME, 0, *volume)),
        _ => None,
    }
}

/// Sends decoded audio to the app, which plays it through AVAudioEngine.
struct CallbackSink(Callbacks);

impl Sink for CallbackSink {
    fn write(&mut self, packet: AudioPacket, converter: &mut Converter) -> SinkResult<()> {
        if let AudioPacket::Samples(samples) = packet {
            let samples = converter.f64_to_f32(&samples);
            (self.0.on_audio)(self.0.context, samples.as_ptr(), samples.len());
        }
        Ok(())
    }
}

struct Connected {
    /// The `lsb_login` call that made this player. Its event loop stops when replaced.
    login_id: u64,
    player: Arc<Player>,
    mixer: Arc<SoftMixer>,
}

pub struct LsbBridge {
    runtime: tokio::runtime::Runtime,
    callbacks: Callbacks,
    connected: Arc<Mutex<Option<Connected>>>,
    /// Counts `lsb_login` calls. Only the newest login may publish its result.
    latest_login: Arc<AtomicU64>,
}

#[no_mangle]
pub extern "C" fn lsb_new(
    on_event: Option<LsbEventCallback>,
    on_audio: Option<LsbAudioCallback>,
    context: *mut c_void,
) -> *mut LsbBridge {
    let (Some(on_event), Some(on_audio)) = (on_event, on_audio) else {
        return std::ptr::null_mut();
    };
    let Ok(runtime) = tokio::runtime::Runtime::new() else {
        return std::ptr::null_mut();
    };
    let callbacks = Callbacks {
        on_event,
        on_audio,
        context,
    };
    let connected = Arc::new(Mutex::new(None));
    Box::into_raw(Box::new(LsbBridge {
        runtime,
        callbacks,
        connected,
        latest_login: Arc::new(AtomicU64::new(0)),
    }))
}

/// # Safety
/// `bridge` must come from `lsb_new` and must not be used again.
#[no_mangle]
pub unsafe extern "C" fn lsb_free(bridge: *mut LsbBridge) {
    if !bridge.is_null() {
        drop(Box::from_raw(bridge));
    }
}

unsafe fn read_str<'a>(text: *const c_char) -> Option<&'a str> {
    if text.is_null() {
        return None;
    }
    CStr::from_ptr(text).to_str().ok()
}

/// Starts login with a Spotify access token. The result comes as an event.
/// No credentials or audio are cached on disk.
///
/// # Safety
/// `bridge` must be valid. `access_token` must be a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn lsb_login(bridge: *mut LsbBridge, access_token: *const c_char) -> i32 {
    let (Some(bridge), Some(token)) = (bridge.as_ref(), read_str(access_token)) else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let credentials = Credentials::with_access_token(token);
    let callbacks = bridge.callbacks;
    let connected = bridge.connected.clone();
    let latest_login = bridge.latest_login.clone();
    let login_id = latest_login.fetch_add(1, Ordering::SeqCst) + 1;
    let is_latest = move || latest_login.load(Ordering::SeqCst) == login_id;
    let _guard = bridge.runtime.enter();
    let session = Session::new(SessionConfig::default(), None);
    bridge.runtime.spawn(async move {
        if let Err(error) = session.connect(credentials, false).await {
            if is_latest() {
                callbacks.emit(LSB_EVENT_ERROR, 0, 0, Some(&error.to_string()));
            }
            return;
        }
        let Ok(mixer) = SoftMixer::open(MixerConfig::default()) else {
            callbacks.emit(LSB_EVENT_ERROR, 0, 0, Some("cannot open mixer"));
            return;
        };
        let mixer = Arc::new(mixer);
        let config = PlayerConfig {
            position_update_interval: Some(std::time::Duration::from_millis(500)),
            ..PlayerConfig::default()
        };
        let sink = move || Box::new(CallbackSink(callbacks)) as Box<dyn Sink>;
        let player = Player::new(config, session, mixer.get_soft_volume(), sink);
        let mut events = player.get_player_event_channel();
        {
            let mut slot = connected.lock().unwrap();
            if !is_latest() {
                return; // A newer login replaced this one.
            }
            *slot = Some(Connected {
                login_id,
                player,
                mixer,
            });
        }
        callbacks.emit(LSB_EVENT_LOGGED_IN, 0, 0, None);
        while let Some(event) = events.recv().await {
            let slot = connected.lock().unwrap();
            if slot.as_ref().map(|c| c.login_id) != Some(login_id) {
                return; // This player was replaced.
            }
            drop(slot);
            if let Some((kind, position_ms, volume)) = map_event(&event) {
                callbacks.emit(kind, position_ms, volume, None);
            }
        }
    });
    LSB_OK
}

unsafe fn with_player(bridge: *mut LsbBridge, action: impl FnOnce(&Connected)) -> i32 {
    let Some(bridge) = bridge.as_ref() else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    match bridge.connected.lock().unwrap().as_ref() {
        Some(connected) => {
            action(connected);
            LSB_OK
        }
        None => LSB_ERR_NOT_LOGGED_IN,
    }
}

/// Loads a track by URI, for example `spotify:track:...`.
///
/// # Safety
/// `bridge` must be valid. `track_uri` must be a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn lsb_load(
    bridge: *mut LsbBridge,
    track_uri: *const c_char,
    start_playing: bool,
    position_ms: u32,
) -> i32 {
    let Some(uri) = read_str(track_uri).and_then(|u| SpotifyUri::from_uri(u).ok()) else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    with_player(bridge, |c| c.player.load(uri, start_playing, position_ms))
}

/// # Safety
/// `bridge` must be valid.
#[no_mangle]
pub unsafe extern "C" fn lsb_play(bridge: *mut LsbBridge) -> i32 {
    with_player(bridge, |c| c.player.play())
}

/// # Safety
/// `bridge` must be valid.
#[no_mangle]
pub unsafe extern "C" fn lsb_pause(bridge: *mut LsbBridge) -> i32 {
    with_player(bridge, |c| c.player.pause())
}

/// # Safety
/// `bridge` must be valid.
#[no_mangle]
pub unsafe extern "C" fn lsb_seek(bridge: *mut LsbBridge, position_ms: u32) -> i32 {
    with_player(bridge, |c| c.player.seek(position_ms))
}

/// Sets volume from 0 to 65535.
///
/// # Safety
/// `bridge` must be valid.
#[no_mangle]
pub unsafe extern "C" fn lsb_set_volume(bridge: *mut LsbBridge, volume: u16) -> i32 {
    with_player(bridge, |c| {
        c.mixer.set_volume(volume);
        c.player.emit_volume_changed_event(volume);
    })
}

#[cfg(test)]
mod tests;
