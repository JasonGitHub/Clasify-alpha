//! C FFI over librespot. The C header is `include/librespot_bridge.h`.
//! Keep the two in sync: the `header_matches_rust` test checks the constants.

use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use librespot_core::{authentication::Credentials, Session, SessionConfig, SpotifyUri};
use librespot_oauth::OAuthClientBuilder;
use librespot_playback::audio_backend::{Sink, SinkResult};
use librespot_playback::config::PlayerConfig;
use librespot_playback::convert::Converter;
use librespot_playback::decoder::AudioPacket;
use librespot_playback::mixer::{softmixer::SoftMixer, Mixer, MixerConfig};
use librespot_playback::player::{Player, PlayerEvent};

pub const LSB_OK: i32 = 0;
pub const LSB_ERR_INVALID_ARGUMENT: i32 = 1;
pub const LSB_ERR_NOT_LOGGED_IN: i32 = 2;
pub const LSB_ERR_OAUTH: i32 = 3;

pub const LSB_EVENT_LOGGED_IN: u32 = 0;
pub const LSB_EVENT_PLAYING: u32 = 1;
pub const LSB_EVENT_PAUSED: u32 = 2;
pub const LSB_EVENT_POSITION: u32 = 3;
pub const LSB_EVENT_TRACK_ENDED: u32 = 4;
pub const LSB_EVENT_UNAVAILABLE: u32 = 5;
pub const LSB_EVENT_VOLUME: u32 = 6;
pub const LSB_EVENT_ERROR: u32 = 7;
pub const LSB_EVENT_PLAY_REQUEST: u32 = 8;
pub const LSB_EVENT_LOG: u32 = 9;
pub const LSB_EVENT_LIBRARY: u32 = 10;
pub const LSB_EVENT_CONTEXT: u32 = 11;
pub const LSB_EVENT_CONNECT: u32 = 12;
pub const LSB_EVENT_CLUSTER: u32 = 13;

/// Matches `LsbEvent` in the header. The strings are valid only during the callback.
#[repr(C)]
pub struct LsbEvent {
    pub kind: u32,
    pub position_ms: u32,
    pub play_request_id: u64,
    pub volume: u16,
    pub track_uri: *const c_char,
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

/// One event before it crosses the FFI. Fields that do not apply stay at their defaults.
#[derive(Debug, Default, PartialEq)]
struct Event {
    kind: u32,
    position_ms: u32,
    play_request_id: u64,
    volume: u16,
    track_uri: Option<String>,
    message: Option<String>,
}

impl Event {
    fn new(kind: u32) -> Self {
        Event {
            kind,
            ..Event::default()
        }
    }

    fn error(message: &str) -> Self {
        Event {
            message: Some(message.to_owned()),
            ..Event::new(LSB_EVENT_ERROR)
        }
    }

    fn track(kind: u32, play_request_id: u64, track: &SpotifyUri, position_ms: u32) -> Self {
        Event {
            play_request_id,
            position_ms,
            track_uri: track.to_uri().ok(),
            ..Event::new(kind)
        }
    }
}

fn c_string(text: &Option<String>) -> Option<CString> {
    text.as_ref()
        .map(|t| CString::new(t.replace('\0', " ")).unwrap_or_default())
}

impl Callbacks {
    fn emit(&self, event: &Event) {
        let (track_uri, message) = (c_string(&event.track_uri), c_string(&event.message));
        let as_ptr = |t: &Option<CString>| t.as_ref().map_or(std::ptr::null(), |t| t.as_ptr());
        let raw = LsbEvent {
            kind: event.kind,
            position_ms: event.position_ms,
            play_request_id: event.play_request_id,
            volume: event.volume,
            track_uri: as_ptr(&track_uri),
            message: as_ptr(&message),
        };
        (self.on_event)(self.context, &raw);
    }
}

/// Maps a librespot event to a bridge event. Other events are dropped.
fn map_event(event: &PlayerEvent) -> Option<Event> {
    use PlayerEvent::*;
    Some(match event {
        // librespot sends this at the start of every load, also for loads that skip
        // `Loading` (reload of the current track, or repeat after end of track).
        PlayRequestIdChanged { play_request_id } => Event {
            play_request_id: *play_request_id,
            ..Event::new(LSB_EVENT_PLAY_REQUEST)
        },
        Playing {
            play_request_id: id,
            track_id,
            position_ms,
        } => Event::track(LSB_EVENT_PLAYING, *id, track_id, *position_ms),
        Paused {
            play_request_id: id,
            track_id,
            position_ms,
        } => Event::track(LSB_EVENT_PAUSED, *id, track_id, *position_ms),
        PositionChanged {
            play_request_id: id,
            track_id,
            position_ms,
        }
        | PositionCorrection {
            play_request_id: id,
            track_id,
            position_ms,
        }
        | Seeked {
            play_request_id: id,
            track_id,
            position_ms,
        } => Event::track(LSB_EVENT_POSITION, *id, track_id, *position_ms),
        EndOfTrack {
            play_request_id: id,
            track_id,
        } => Event::track(LSB_EVENT_TRACK_ENDED, *id, track_id, 0),
        Unavailable {
            play_request_id: id,
            track_id,
        } => Event::track(LSB_EVENT_UNAVAILABLE, *id, track_id, 0),
        VolumeChanged { volume } => Event {
            volume: *volume,
            ..Event::new(LSB_EVENT_VOLUME)
        },
        _ => return None,
    })
}

/// False for a repeated PLAY_REQUEST. A seek during loading restarts the load with
/// the same id, so this keeps the app at exactly one PLAY_REQUEST per lsb_load.
fn is_new(event: &Event, last_play_request: &mut Option<u64>) -> bool {
    if event.kind != LSB_EVENT_PLAY_REQUEST {
        return true;
    }
    let id = Some(event.play_request_id);
    let is_new = *last_play_request != id;
    *last_play_request = id;
    is_new
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

/// Forwards librespot's log messages (info and above) to the newest bridge as
/// LSB_EVENT_LOG events. Nothing is written to disk. librespot_oauth is left out,
/// because its trace output holds the token, and other crates are left out as noise.
struct EventLogger;

static LOG_SINK: Mutex<Option<Callbacks>> = Mutex::new(None);

impl log::Log for EventLogger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        let target = metadata.target();
        if !target.starts_with("librespot") || target.starts_with("librespot_oauth") {
            return false;
        }
        let verbose =
            target.starts_with("librespot_playback") || target.starts_with("librespot_core");
        metadata.level()
            <= if verbose {
                log::Level::Debug
            } else {
                log::Level::Warn
            }
    }

    fn log(&self, record: &log::Record) {
        if !self.enabled(record.metadata()) {
            return;
        }
        let sink = *LOG_SINK.lock().unwrap();
        if let Some(callbacks) = sink {
            let text = scrub(&format!(
                "{} {}: {}",
                record.level(),
                record.target(),
                record.args()
            ));
            callbacks.emit(&Event {
                message: Some(text),
                ..Event::new(LSB_EVENT_LOG)
            });
        }
    }

    fn flush(&self) {}
}

/// Hides any log line that might carry a credential.
fn scrub(text: &str) -> String {
    let lower = text.to_lowercase();
    let secret = [
        "bearer",
        "access_token",
        "token=",
        "authorization",
        "password",
        "auth_data",
    ];
    if secret.iter().any(|word| lower.contains(word)) {
        let head = text.split_once(": ").map_or("", |(head, _)| head);
        return format!("{head}: [hidden: may hold a credential]");
    }
    text.to_owned()
}

static LOGGER: EventLogger = EventLogger;

struct Connected {
    /// The `lsb_login` call that made this player. Its event loop stops when replaced.
    login_id: u64,
    session: Session,
    player: Arc<Player>,
    mixer: Arc<SoftMixer>,
}

pub struct LsbBridge {
    runtime: tokio::runtime::Runtime,
    callbacks: Callbacks,
    connected: Arc<Mutex<Option<Connected>>>,
    /// Counts `lsb_login` calls. Only the newest login may publish its result.
    latest_login: Arc<AtomicU64>,
    /// `SessionConfig::ap_port` for the next login. 0 means librespot's default.
    ap_port: std::sync::atomic::AtomicU16,
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
    if log::set_logger(&LOGGER).is_ok() {
        log::set_max_level(log::LevelFilter::Debug);
    }
    *LOG_SINK.lock().unwrap() = Some(callbacks);
    Box::into_raw(Box::new(LsbBridge {
        runtime,
        callbacks,
        connected,
        latest_login: Arc::new(AtomicU64::new(0)),
        ap_port: std::sync::atomic::AtomicU16::new(0),
    }))
}

/// # Safety
/// `bridge` must come from `lsb_new` and must not be used again.
#[no_mangle]
pub unsafe extern "C" fn lsb_free(bridge: *mut LsbBridge) {
    if !bridge.is_null() {
        let mut sink = LOG_SINK.lock().unwrap();
        if sink.map(|c| c.context) == Some((*bridge).callbacks.context) {
            *sink = None;
        }
        drop(sink);
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
    let ap_port = bridge.ap_port.load(Ordering::SeqCst);
    let config = SessionConfig {
        ap_port: (ap_port != 0).then_some(ap_port),
        ..SessionConfig::default()
    };
    let session = Session::new(config, None);
    bridge.runtime.spawn(async move {
        if let Err(error) = session.connect(credentials, false).await {
            if is_latest() {
                callbacks.emit(&Event::error(&error.to_string()));
            }
            return;
        }
        let Ok(mixer) = SoftMixer::open(MixerConfig::default()) else {
            if is_latest() {
                callbacks.emit(&Event::error("cannot open mixer"));
            }
            return;
        };
        let mixer = Arc::new(mixer);
        let config = PlayerConfig {
            position_update_interval: Some(std::time::Duration::from_millis(500)),
            ..PlayerConfig::default()
        };
        let sink = move || Box::new(CallbackSink(callbacks)) as Box<dyn Sink>;
        let player = Player::new(config, session.clone(), mixer.get_soft_volume(), sink);
        let mut events = player.get_player_event_channel();
        let replaced = {
            let mut slot = connected.lock().unwrap();
            if !is_latest() {
                return; // A newer login replaced this one.
            }
            slot.replace(Connected {
                login_id,
                session,
                player,
                mixer,
            })
        };
        // Drop the old player outside the lock: dropping it joins its thread,
        // and that thread may be in the audio callback, waiting for the lock.
        drop(replaced);
        // Not under the lock, so a callback can call back into the bridge.
        // A login that starts right now can still follow this event.
        if is_latest() {
            callbacks.emit(&Event::new(LSB_EVENT_LOGGED_IN));
        }
        let mut last_play_request = None;
        while let Some(event) = events.recv().await {
            let slot = connected.lock().unwrap();
            if slot.as_ref().map(|c| c.login_id) != Some(login_id) {
                return; // This player was replaced.
            }
            drop(slot);
            let Some(event) = map_event(&event) else {
                continue;
            };
            if is_new(&event, &mut last_play_request) {
                callbacks.emit(&event);
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

/// Sets the access point port filter for the next `lsb_login`. 0 means no filter.
/// librespot then only uses access points from apresolve with that port.
///
/// # Safety
/// `bridge` must be valid.
#[no_mangle]
pub unsafe extern "C" fn lsb_set_ap_port(bridge: *mut LsbBridge, port: u16) -> i32 {
    let Some(bridge) = bridge.as_ref() else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    bridge.ap_port.store(port, Ordering::SeqCst);
    LSB_OK
}

/// Reads the library through librespot's own session (spclient), not the Web API.
/// Results come as LSB_EVENT_LIBRARY events: one for the rootlist, one for Liked Songs.
///
/// # Safety
/// `bridge` must be valid.
#[no_mangle]
pub unsafe extern "C" fn lsb_read_library(bridge: *mut LsbBridge) -> i32 {
    let Some(bridge_ref) = bridge.as_ref() else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let mut session = None;
    let status = with_player(bridge, |c| session = Some(c.session.clone()));
    let Some(session) = session else {
        return status;
    };
    let callbacks = bridge_ref.callbacks;
    bridge_ref.runtime.spawn(async move {
        let library = |message: String, track_uri: Option<String>| Event {
            message: Some(message),
            track_uri,
            ..Event::new(LSB_EVENT_LIBRARY)
        };
        let (message, first_playlist) = read_rootlist(&session).await;
        callbacks.emit(&library(message, first_playlist));
        let (message, first) = read_liked_songs(&session).await;
        callbacks.emit(&library(message, first));
        let liked = format!("spotify:user:{}:collection", session.username());
        callbacks.emit(&read_context(&session, &liked).await);
    });
    LSB_OK
}

/// Spike: reads the tracks of a context (a playlist, or Liked Songs as
/// `spotify:user:<name>:collection`) through librespot. The result comes as one
/// LSB_EVENT_CONTEXT event.
///
/// # Safety
/// `bridge` must be valid. `context_uri` must be a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn lsb_read_context(
    bridge: *mut LsbBridge,
    context_uri: *const c_char,
) -> i32 {
    let (Some(bridge_ref), Some(uri)) = (bridge.as_ref(), read_str(context_uri)) else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let uri = uri.to_owned();
    let mut session = None;
    let status = with_player(bridge, |c| session = Some(c.session.clone()));
    let Some(session) = session else {
        return status;
    };
    let callbacks = bridge_ref.callbacks;
    bridge_ref.runtime.spawn(async move {
        callbacks.emit(&read_context(&session, &uri).await);
    });
    LSB_OK
}

/// Spike: sends a POST to a Spotify Connect endpoint through spclient. Only paths under
/// `/connect-state/v1/` are allowed, so it cannot reach any library endpoint.
/// Sends one LSB_EVENT_CONNECT: `track_uri` is the path, `message` is
/// "OK <body>" or "ERROR <text>", plus this session's device ID.
///
/// # Safety
/// `bridge` must come from `lsb_new`. `path` and `json_body` must be valid C strings
/// or null (`json_body` only).
#[no_mangle]
pub unsafe extern "C" fn lsb_connect_post(
    bridge: *mut LsbBridge,
    path: *const c_char,
    json_body: *const c_char,
) -> i32 {
    lsb_connect_request(bridge, c"POST".as_ptr(), path, json_body)
}

/// Spike: like `lsb_connect_post`, with `method` "POST" or "PUT" (PUT is for the
/// Connect volume endpoint).
///
/// # Safety
/// As for `lsb_connect_post`. `method` must be a valid C string.
#[no_mangle]
pub unsafe extern "C" fn lsb_connect_request(
    bridge: *mut LsbBridge,
    method: *const c_char,
    path: *const c_char,
    json_body: *const c_char,
) -> i32 {
    let (Some(bridge_ref), Some(path)) = (bridge.as_ref(), read_str(path)) else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let method = match read_str(method) {
        Some("POST") => http::Method::POST,
        Some("PUT") => http::Method::PUT,
        _ => return LSB_ERR_INVALID_ARGUMENT,
    };
    if !path.starts_with("/connect-state/v1/") {
        return LSB_ERR_INVALID_ARGUMENT;
    }
    let path = path.to_owned();
    let body = read_str(json_body).map(str::to_owned);
    let mut session = None;
    let status = with_player(bridge, |c| session = Some(c.session.clone()));
    let Some(session) = session else {
        return status;
    };
    let callbacks = bridge_ref.callbacks;
    bridge_ref.runtime.spawn(async move {
        let path = path.replace("{self}", session.device_id());
        let mut headers = http::HeaderMap::new();
        headers.insert(
            http::header::CONTENT_TYPE,
            http::HeaderValue::from_static("application/json"),
        );
        let result = session
            .spclient()
            .request(
                &method,
                &path,
                Some(headers),
                body.as_deref().map(str::as_bytes),
            )
            .await;
        let text = match result {
            Ok(bytes) => {
                let body = String::from_utf8_lossy(&bytes);
                format!("OK {}", body.chars().take(500).collect::<String>())
            }
            Err(error) => format!("ERROR {error}"),
        };
        callbacks.emit(&Event {
            track_uri: Some(path),
            message: Some(format!("{text} (session device {})", session.device_id())),
            ..Event::new(LSB_EVENT_CONNECT)
        });
    });
    LSB_OK
}

/// Spike: registers this session as a Connect device (dealer + connect-state PUT) and
/// lists the devices in the returned cluster. Sends one LSB_EVENT_CONNECT with
/// `track_uri` = "devices" and `message` = one "id|name|type|software|active" line per
/// device, or "ERROR <text>".
///
/// # Safety
/// `bridge` must come from `lsb_new`.
#[no_mangle]
pub unsafe extern "C" fn lsb_connect_devices(bridge: *mut LsbBridge) -> i32 {
    let Some(bridge_ref) = bridge.as_ref() else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let mut session = None;
    let status = with_player(bridge, |c| session = Some(c.session.clone()));
    let Some(session) = session else {
        return status;
    };
    let callbacks = bridge_ref.callbacks;
    bridge_ref.runtime.spawn(async move {
        let message = match connect_devices(&session, callbacks).await {
            Ok(lines) => lines,
            Err(error) => format!("ERROR {error}"),
        };
        callbacks.emit(&Event {
            track_uri: Some("devices".to_owned()),
            message: Some(message),
            ..Event::new(LSB_EVENT_CONNECT)
        });
    });
    LSB_OK
}

async fn connect_devices(session: &Session, callbacks: Callbacks) -> Result<String, String> {
    use futures_util::StreamExt;
    use librespot_protocol::connect::{
        Capabilities, Cluster, Device, DeviceInfo, MemberType, PutStateReason, PutStateRequest,
    };
    use librespot_protocol::devices::DeviceType;
    use protobuf::Message;

    if session.connection_id().is_empty() {
        let mut ids = session
            .dealer()
            .listen_for("hm://pusher/v1/connections/", |message| {
                Ok(message
                    .headers
                    .get("Spotify-Connection-Id")
                    .cloned()
                    .unwrap_or_default())
            })
            .map_err(|e| format!("dealer listen: {e}"))?;
        let mut clusters = session
            .dealer()
            .listen_for(
                "hm://connect-state/v1/cluster",
                librespot_core::dealer::protocol::Message::from_raw::<
                    librespot_protocol::connect::ClusterUpdate,
                >,
            )
            .map_err(|e| format!("dealer listen cluster: {e}"))?;
        tokio::spawn(async move {
            while let Some(update) = clusters.next().await {
                let message = match update {
                    Ok(update) => cluster_summary(&update),
                    Err(error) => format!("ERROR {error}"),
                };
                callbacks.emit(&Event {
                    message: Some(message),
                    ..Event::new(LSB_EVENT_CLUSTER)
                });
            }
        });
        session
            .dealer()
            .start()
            .await
            .map_err(|e| format!("dealer start: {e}"))?;
        let id = tokio::time::timeout(std::time::Duration::from_secs(10), ids.next())
            .await
            .map_err(|_| "no connection ID within 10 s".to_owned())?
            .ok_or("dealer closed".to_owned())?
            .map_err(|e| format!("connection ID: {e}"))?;
        session.set_connection_id(&id);
    }

    let info = DeviceInfo {
        can_play: true,
        volume: 65535,
        name: "Clasify spike".to_owned(),
        device_id: session.device_id().to_owned(),
        device_type: DeviceType::COMPUTER.into(),
        device_software_version: "Clasify spike".to_owned(),
        spirc_version: "3.2.6".to_owned(),
        client_id: session.client_id(),
        capabilities: protobuf::MessageField::some(Capabilities {
            can_be_player: false,
            is_observable: true,
            volume_steps: 64,
            ..Default::default()
        }),
        ..Default::default()
    };
    let request = PutStateRequest {
        member_type: MemberType::CONNECT_STATE.into(),
        put_state_reason: PutStateReason::NEW_DEVICE.into(),
        device: protobuf::MessageField::some(Device {
            device_info: protobuf::MessageField::some(info),
            ..Default::default()
        }),
        ..Default::default()
    };
    let bytes = session
        .spclient()
        .put_connect_state_request(&request)
        .await
        .map_err(|e| format!("put state: {e}"))?;
    let cluster = Cluster::parse_from_bytes(&bytes).map_err(|e| format!("cluster decode: {e}"))?;
    let lines: Vec<String> = cluster
        .device
        .values()
        .map(|d| {
            format!(
                "{}|{}|{:?}|{}|{}",
                d.device_id,
                d.name,
                d.device_type.enum_value_or_default(),
                d.device_software_version,
                d.device_id == cluster.active_device_id
            )
        })
        .collect();
    Ok(lines.join("\n"))
}

/// One line: reason|active device|playing|paused|buffering|track|position as of
/// timestamp|timestamp|duration|context|active device volume|server timestamp.
fn cluster_summary(update: &librespot_protocol::connect::ClusterUpdate) -> String {
    let cluster = &update.cluster;
    let state = &cluster.player_state;
    let volume = cluster
        .device
        .get(&cluster.active_device_id)
        .map(|d| d.volume)
        .unwrap_or_default();
    format!(
        "{:?}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}",
        update.update_reason.enum_value_or_default(),
        cluster.active_device_id,
        state.is_playing,
        state.is_paused,
        state.is_buffering,
        state.track.uri,
        state.position_as_of_timestamp,
        state.timestamp,
        state.duration,
        state.context_uri,
        volume,
        cluster.server_timestamp_ms
    )
}

/// `track_uri` is the context URI. `message` is the track URIs of the loaded pages,
/// one per line, or "ERROR <text>".
async fn read_context(session: &Session, uri: &str) -> Event {
    let message = match session.spclient().get_context(uri).await {
        Ok(context) => context
            .pages
            .iter()
            .flat_map(|p| p.tracks.iter())
            .filter_map(|t| t.uri.clone())
            .collect::<Vec<_>>()
            .join("\n"),
        Err(error) => format!("ERROR {error}"),
    };
    Event {
        track_uri: Some(uri.to_owned()),
        message: Some(message),
        ..Event::new(LSB_EVENT_CONTEXT)
    }
}

async fn read_rootlist(session: &Session) -> (String, Option<String>) {
    use protobuf::Message;
    type ListMessage = <librespot_metadata::Playlist as librespot_metadata::Metadata>::Message;
    let bytes = match session.spclient().get_rootlist(0, Some(1000)).await {
        Ok(bytes) => bytes,
        Err(error) => return (format!("FAIL rootlist: {error}"), None),
    };
    // Decode the protobuf directly. librespot-metadata's conversion fails on items whose
    // URI is not a Spotify ID, such as folder markers.
    let list = match ListMessage::parse_from_bytes(&bytes) {
        Ok(list) => list,
        Err(error) => {
            let message = format!(
                "FAIL rootlist: {} bytes, cannot decode: {error}",
                bytes.len()
            );
            return (message, None);
        }
    };
    let uris: Vec<&str> = list.contents.items.iter().map(|i| i.uri()).collect();
    let count = |prefix: &str| uris.iter().filter(|u| u.starts_with(prefix)).count();
    let (playlists, folders) = (count("spotify:playlist:"), count("spotify:start-group:"));
    let ends = count("spotify:end-group:");
    let other: Vec<&str> = uris
        .iter()
        .filter(|u| {
            ![
                "spotify:playlist:",
                "spotify:start-group:",
                "spotify:end-group:",
            ]
            .iter()
            .any(|p| u.starts_with(p))
        })
        .map(|u| u.split(':').take(2).last().unwrap_or(""))
        .collect();
    let first_playlist = uris
        .iter()
        .find(|u| u.starts_with("spotify:playlist:"))
        .map(|u| u.to_string());
    let message = format!(
        "PASS rootlist: {} items: {playlists} playlists, {folders} folder starts, {ends} folder ends, {} other {:?}, length {}",
        uris.len(),
        other.len(),
        other.iter().take(5).collect::<Vec<_>>(),
        list.length()
    );
    (message, first_playlist)
}

async fn read_liked_songs(session: &Session) -> (String, Option<String>) {
    let uri = format!("spotify:user:{}:collection", session.username());
    match session.spclient().get_context(&uri).await {
        Ok(context) => {
            let tracks: Vec<_> = context.pages.iter().flat_map(|p| p.tracks.iter()).collect();
            let more = context.pages.iter().any(|p| p.next_page_url.is_some());
            let first = tracks.iter().find_map(|t| t.uri.clone());
            let message = format!(
                "PASS liked songs: {} pages, {} tracks in loaded pages, more pages: {more}",
                context.pages.len(),
                tracks.len()
            );
            (message, first)
        }
        Err(error) => (format!("FAIL liked songs: {error}"), None),
    }
}

/// The redirect URI for `lsb_oauth_login`. librespot 0.8.0's CLI uses
/// `http://127.0.0.1:<--oauth-port>/login`; 8898 is the port of librespot-oauth's example.
pub const OAUTH_REDIRECT_URI: &str = "http://127.0.0.1:8898/login";

/// Read-only scopes. librespot's CLI asks for more, including scopes that modify
/// the library, which Clasify must never do.
pub const OAUTH_SCOPES: &[&str] = &[
    "streaming",
    "user-read-private",
    "playlist-read-private",
    "playlist-read-collaborative",
    "user-library-read",
];

const OAUTH_PAGE: &str =
    "<!doctype html><html><body><h1>Logged in. Go back to Clasify.</h1></body></html>";

/// Matches `LsbOAuthResult` in the header. The strings are valid only during the callback.
#[repr(C)]
pub struct LsbOAuthResult {
    pub status: i32,
    pub expires_in_s: u32,
    pub has_refresh_token: bool,
    pub access_token: *const c_char,
    pub scopes: *const c_char,
    pub client_id: *const c_char,
    pub redirect_uri: *const c_char,
    pub message: *const c_char,
}
pub type LsbOAuthCallback = extern "C" fn(context: *mut c_void, result: *const LsbOAuthResult);

struct OAuthCallback {
    callback: LsbOAuthCallback,
    context: *mut c_void,
}

// SAFETY: the header requires that `context` and the callback are safe to call
// from any thread. The bridge never reads through `context` itself.
unsafe impl Send for OAuthCallback {}

fn run_oauth(client_id: &str) -> Result<librespot_oauth::OAuthToken, String> {
    OAuthClientBuilder::new(client_id, OAUTH_REDIRECT_URI, OAUTH_SCOPES.to_vec())
        .open_in_browser()
        .with_custom_message(OAUTH_PAGE)
        .build()
        .and_then(|client| client.get_access_token())
        .map_err(|error| error.to_string())
}

/// Opens the Spotify login page in the browser and waits on the loopback redirect
/// on a new thread. The result comes once through `on_result`. The token is not
/// stored anywhere by the bridge.
///
/// # Safety
/// `context` and `on_result` must be safe to call from any thread.
#[no_mangle]
pub extern "C" fn lsb_oauth_login(
    on_result: Option<LsbOAuthCallback>,
    context: *mut c_void,
) -> i32 {
    let Some(callback) = on_result else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let target = OAuthCallback { callback, context };
    std::thread::spawn(move || {
        let target = target;
        // librespot's CLI uses the session's default client ID for OAuth.
        let client_id = SessionConfig::default().client_id;
        let result = run_oauth(&client_id);
        let text = |t: &str| CString::new(t.replace('\0', " ")).unwrap_or_default();
        let (client_id, redirect_uri) = (text(&client_id), text(OAUTH_REDIRECT_URI));
        let (token, scopes, message, expires_in_s, has_refresh_token, status) = match &result {
            Ok(t) => (
                text(&t.access_token),
                text(&t.scopes.join(" ")),
                None,
                t.expires_at
                    .saturating_duration_since(std::time::Instant::now())
                    .as_secs() as u32,
                !t.refresh_token.is_empty(),
                LSB_OK,
            ),
            Err(e) => (text(""), text(""), Some(text(e)), 0, false, LSB_ERR_OAUTH),
        };
        let raw = LsbOAuthResult {
            status,
            expires_in_s,
            has_refresh_token,
            access_token: if status == LSB_OK {
                token.as_ptr()
            } else {
                std::ptr::null()
            },
            scopes: scopes.as_ptr(),
            client_id: client_id.as_ptr(),
            redirect_uri: redirect_uri.as_ptr(),
            message: message.as_ref().map_or(std::ptr::null(), |m| m.as_ptr()),
        };
        (target.callback)(target.context, &raw);
    });
    LSB_OK
}

#[cfg(test)]
mod tests;
