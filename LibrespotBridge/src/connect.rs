//! Spotify Connect commands through librespot's session. Clasify plays no audio: it
//! registers itself as a Connect device that cannot play, then tells the Spotify app's
//! device what to do. Only the requests that `request` builds can be sent. The app
//! cannot pass an endpoint path.

use std::ffi::{c_char, c_void};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, RwLock};

use futures_util::StreamExt;
use http::header::{HeaderValue, CONTENT_TYPE};
use http::{HeaderMap, Method};
use librespot_core::dealer::protocol::Message as DealerMessage;
use librespot_core::Session;
use librespot_protocol::connect::{
    Capabilities, Cluster, ClusterUpdate, Device, DeviceInfo, MemberType, PutStateReason,
    PutStateRequest,
};
use librespot_protocol::devices::DeviceType;
use protobuf::Message;
use tokio::sync::mpsc::{unbounded_channel, UnboundedSender};
use tokio::sync::watch;

use crate::library::{c_text, session, Context};
use crate::{read_str, LSB_ERR_CONNECT, LSB_ERR_INVALID_ARGUMENT, LSB_OK};

pub const LSB_COMMAND_PAUSE: u32 = 0;
pub const LSB_COMMAND_RESUME: u32 = 1;
pub const LSB_COMMAND_NEXT: u32 = 2;
pub const LSB_COMMAND_PREV: u32 = 3;

pub const LSB_OPTION_SHUFFLE: u32 = 0;
pub const LSB_OPTION_REPEAT_CONTEXT: u32 = 1;
pub const LSB_OPTION_REPEAT_TRACK: u32 = 2;

const DEVICE_NAME: &str = "Clasify";

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Command {
    Play {
        context: String,
        track: Option<String>,
    },
    Pause,
    Resume,
    Next,
    Prev,
    Seek(u32),
    /// 0 to 65535.
    Volume(u16),
    Shuffle(bool),
    RepeatContext(bool),
    RepeatTrack(bool),
}

impl Command {
    /// True when sending it twice has the same result as sending it once.
    pub(crate) fn can_retry(&self) -> bool {
        !matches!(self, Command::Next | Command::Prev)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct ConnectDevice {
    pub id: String,
    pub name: String,
    pub device_type: String,
    pub software: String,
    pub is_active: bool,
}

/// A device ID goes into the URL path, so it may hold only letters, digits, `-` and `_`.
pub(crate) fn valid_device_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

fn is_base62(id: &str) -> bool {
    !id.is_empty() && id.bytes().all(|b| b.is_ascii_alphanumeric())
}

/// A playlist, or Liked Songs ("spotify:user:<name>:collection").
pub(crate) fn valid_context(uri: &str) -> bool {
    if let Some(id) = uri.strip_prefix("spotify:playlist:") {
        return is_base62(id);
    }
    let user = uri
        .strip_prefix("spotify:user:")
        .and_then(|rest| rest.strip_suffix(":collection"));
    user.is_some_and(|u| !u.is_empty() && !u.contains(':') && !u.chars().any(char::is_control))
}

pub(crate) fn valid_track(uri: &str) -> bool {
    uri.strip_prefix("spotify:track:").is_some_and(is_base62)
}

/// A JSON string literal.
fn json(text: &str) -> String {
    let mut out = String::from("\"");
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// The method, path and JSON body that send `command` from this device to device `to`.
/// These are the bodies that Spotify's own clients send.
pub(crate) fn request(
    command: &Command,
    from: &str,
    to: &str,
    command_id: &str,
) -> (Method, String, String) {
    if let Command::Volume(volume) = command {
        let path = format!("/connect-state/v1/connect/volume/from/{from}/to/{to}");
        return (Method::PUT, path, format!(r#"{{"volume":{volume}}}"#));
    }
    let logging = format!(r#""logging_params":{{"command_id":{}}}"#, json(command_id));
    let simple = |endpoint: &str| format!(r#"{{"command":{{{logging},"endpoint":"{endpoint}"}}}}"#);
    let option = |endpoint: &str, on: bool| {
        format!(r#"{{"command":{{"value":{on},{logging},"endpoint":"{endpoint}"}}}}"#)
    };
    let body = match command {
        Command::Play { context, track } => {
            let skip_to = match track {
                Some(track) => format!(r#"{{"track_uri":{}}}"#, json(track)),
                None => "{}".to_owned(),
            };
            let uri = json(context);
            let url = json(&format!("context://{context}"));
            format!(
                concat!(
                    r#"{{"command":{{"context":{{"uri":{},"url":{},"metadata":{{}}}},"#,
                    r#""play_origin":{{"feature_identifier":"harmony","feature_version":"4.11.0"}},"#,
                    r#""options":{{"license":"on-demand","skip_to":{},"player_options_override":{{}}}},"#,
                    r#"{},"endpoint":"play"}}}}"#
                ),
                uri, url, skip_to, logging
            )
        }
        Command::Pause => simple("pause"),
        Command::Resume => simple("resume"),
        Command::Next => simple("skip_next"),
        Command::Prev => simple("skip_prev"),
        Command::Shuffle(on) => option("set_shuffling_context", *on),
        Command::RepeatContext(on) => option("set_repeating_context", *on),
        Command::RepeatTrack(on) => option("set_repeating_track", *on),
        Command::Seek(ms) => {
            format!(r#"{{"command":{{"value":{ms},{logging},"endpoint":"seek_to"}}}}"#)
        }
        Command::Volume(_) => unreachable!("handled above"),
    };
    let path = format!("/connect-state/v1/player/command/from/{from}/to/{to}");
    (Method::POST, path, body)
}

/// The account's devices in a cluster, without this device, sorted by name.
pub(crate) fn devices(cluster: &Cluster, own_id: &str) -> Vec<ConnectDevice> {
    let mut list: Vec<ConnectDevice> = cluster
        .device
        .values()
        .filter(|d| d.device_id != own_id)
        .map(|d| ConnectDevice {
            id: d.device_id.clone(),
            name: d.name.clone(),
            device_type: format!("{:?}", d.device_type.enum_value_or_default()),
            software: d.device_software_version.clone(),
            is_active: d.device_id == cluster.active_device_id,
        })
        .collect();
    list.sort_by(|a, b| (&a.name, &a.id).cmp(&(&b.name, &b.id)));
    list
}

/// The Spotify app's player, as a cluster reports it.
#[derive(Debug, Clone, Default, PartialEq)]
pub(crate) struct SpotifyState {
    pub active_device_id: String,
    pub track_uri: String,
    pub context_uri: String,
    pub position_ms: u32,
    pub duration_ms: u32,
    pub is_playing: bool,
    pub is_paused: bool,
    pub shuffle: bool,
    pub repeat_context: bool,
    pub repeat_track: bool,
}

/// The player state of a cluster at `now_ms` (Spotify's clock, Unix time in ms). Spotify
/// gives the position at its own timestamp, so a running track's position moves on
/// by the time since then, up to the track's duration.
pub(crate) fn spotify_state(cluster: &Cluster, now_ms: i64) -> SpotifyState {
    let player = &*cluster.player_state;
    let running = player.is_playing && !player.is_paused;
    let duration = player.duration.max(0);
    let mut position = player.position_as_of_timestamp.max(0);
    if running && player.timestamp > 0 {
        position += (now_ms - player.timestamp).max(0);
    }
    if duration > 0 {
        position = position.min(duration);
    }
    let ms = |value: i64| u32::try_from(value).unwrap_or(u32::MAX);
    SpotifyState {
        active_device_id: cluster.active_device_id.clone(),
        track_uri: player.track.uri.clone(),
        context_uri: player.context_uri.clone(),
        position_ms: ms(position),
        duration_ms: ms(duration),
        is_playing: player.is_playing,
        is_paused: player.is_paused,
        shuffle: player.options.shuffling_context,
        repeat_context: player.options.repeating_context,
        repeat_track: player.options.repeating_track,
    }
}

/// Now on Spotify's clock. `time_delta_s` is `Session::time_delta()`: Spotify's time
/// minus the Mac's time, in seconds. Spotify's player timestamps use Spotify's clock.
pub(crate) fn spotify_now_ms(time_delta_s: i64) -> i64 {
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH);
    let local = now.map_or(0, |d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX));
    local.saturating_add(time_delta_s.saturating_mul(1000))
}

/// Matches `LsbPlayerState` in the header.
#[repr(C)]
pub struct LsbPlayerState {
    pub active_device_id: *const c_char,
    pub track_uri: *const c_char,
    pub context_uri: *const c_char,
    pub position_ms: u32,
    pub duration_ms: u32,
    pub is_playing: bool,
    pub is_paused: bool,
    pub shuffle: bool,
    pub repeat_context: bool,
    pub repeat_track: bool,
}

pub type LsbStateCallback = extern "C" fn(context: *mut c_void, state: *const LsbPlayerState);

#[derive(Clone, Copy)]
pub(crate) struct StateSink {
    pub(crate) callback: LsbStateCallback,
    pub(crate) context: *mut c_void,
}

// SAFETY: the header requires that `context` and the callback are safe to call
// from any thread. The bridge never reads through `context` itself.
unsafe impl Send for StateSink {}
// SAFETY: the bridge only copies the two values and never reads through `context`.
// Two deliveries can run at once on two bridge threads; the header requires that the
// callback is safe to call from any thread at once. It should copy the state and return.
unsafe impl Sync for StateSink {}

/// The state callback that `lsb_connect_watch` set, if any. A delivery holds the read
/// lock while the callback runs. `lsb_connect_watch` and `lsb_free` take the write lock,
/// so they wait for a running callback, and the old context is not used after they return.
pub(crate) type SharedSink = Arc<RwLock<Option<StateSink>>>;

/// Sets or clears the callback. It waits until no callback runs.
pub(crate) fn set_sink(sink: &SharedSink, value: Option<StateSink>) {
    // A poisoned lock still holds a valid Option. A panic here would abort the app.
    *sink.write().unwrap_or_else(|e| e.into_inner()) = value;
}

pub(crate) fn deliver_state(sink: &SharedSink, state: &SpotifyState) {
    let guard = sink.read().unwrap_or_else(|e| e.into_inner());
    let Some(sink) = *guard else {
        return;
    };
    let texts = [
        &state.active_device_id,
        &state.track_uri,
        &state.context_uri,
    ]
    .map(|t| c_text(t));
    let raw = LsbPlayerState {
        active_device_id: texts[0].as_ptr(),
        track_uri: texts[1].as_ptr(),
        context_uri: texts[2].as_ptr(),
        position_ms: state.position_ms,
        duration_ms: state.duration_ms,
        is_playing: state.is_playing,
        is_paused: state.is_paused,
        shuffle: state.shuffle,
        repeat_context: state.repeat_context,
        repeat_track: state.repeat_track,
    };
    (sink.callback)(sink.context, &raw);
    drop(guard);
}

/// A random ID for the command's logging parameters. It is not a secret.
fn command_id() -> String {
    use std::hash::{BuildHasher, Hasher};
    let half = || {
        let mut hasher = std::collections::hash_map::RandomState::new().build_hasher();
        hasher.write_u64(std::process::id().into());
        hasher.finish()
    };
    format!("{:016x}{:016x}", half(), half())
}

/// The dealer of one session, and the newest connection ID it sent.
pub(crate) struct Dealer {
    device_id: String,
    connection_id: watch::Receiver<String>,
    /// The session's newest `time_delta()`, for the cluster task, which holds no session.
    time_delta: Arc<AtomicI64>,
}

/// Starts the session's dealer. A task keeps reading the dealer's connection IDs: the
/// dealer reconnects after sleep or a network change and then sends a new ID. The task
/// holds no `Session`, and it ends when the dealer closes or the worker drops `Dealer`.
async fn start_dealer(session: &Session, sink: &SharedSink) -> Result<Dealer, String> {
    let mut updates = session
        .dealer()
        .listen_for(
            "hm://connect-state/v1/cluster",
            DealerMessage::from_raw::<ClusterUpdate>,
        )
        .map_err(|e| format!("cannot listen to Spotify Connect: {e}"))?;
    let mut ids = session
        .dealer()
        .listen_for("hm://pusher/v1/connections/", |message| {
            Ok(message
                .headers
                .get("Spotify-Connection-Id")
                .cloned()
                .unwrap_or_default())
        })
        .map_err(|e| format!("cannot listen to Spotify Connect: {e}"))?;
    session
        .dealer()
        .start()
        .await
        .map_err(|e| format!("cannot start Spotify Connect: {e}"))?;
    let sink = sink.clone();
    let time_delta = Arc::new(AtomicI64::new(session.time_delta()));
    let delta = time_delta.clone();
    tokio::spawn(async move {
        while let Some(update) = updates.next().await {
            // A message that does not decode is skipped. The next one has the full state.
            if let Ok(update) = update {
                let now = spotify_now_ms(delta.load(Ordering::Relaxed));
                deliver_state(&sink, &spotify_state(&update.cluster, now));
            }
        }
    });
    let (sender, connection_id) = watch::channel(String::new());
    tokio::spawn(async move {
        while let Some(id) = ids.next().await {
            let id = id.unwrap_or_default();
            if !id.is_empty() && sender.send(id).is_err() {
                return; // The worker dropped this dealer.
            }
        }
    });
    Ok(Dealer {
        device_id: session.device_id().to_owned(),
        connection_id,
        time_delta,
    })
}

/// Starts the dealer once per session, then sends a NEW_DEVICE state with the newest
/// connection ID. The reply is the account's cluster, with all its devices.
async fn register(
    session: &Session,
    dealer: &mut Option<Dealer>,
    sink: &SharedSink,
) -> Result<Cluster, String> {
    if dealer.as_ref().map(|d| d.device_id.as_str()) != Some(session.device_id()) {
        *dealer = Some(start_dealer(session, sink).await?);
    }
    let ids = &mut dealer.as_mut().expect("set above").connection_id;
    let wait = ids.wait_for(|id| !id.is_empty());
    let id = tokio::time::timeout(std::time::Duration::from_secs(10), wait)
        .await
        .map_err(|_| "no Spotify Connect connection ID within 10 s".to_owned())?
        .map_err(|_| "Spotify Connect closed".to_owned())?
        .clone();
    session.set_connection_id(&id);
    // `can_play: true` with `can_be_player: false` is the registration that spike
    // build 7 proved: Spotify accepted it and the commands reached the Spotify app.
    // Clasify still never plays: no player listens for audio. Try `can_play: false`
    // in a spike build before changing it.
    let info = DeviceInfo {
        can_play: true,
        volume: 65535,
        name: DEVICE_NAME.to_owned(),
        device_id: session.device_id().to_owned(),
        device_type: DeviceType::COMPUTER.into(),
        device_software_version: DEVICE_NAME.to_owned(),
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
        .map_err(|e| format!("cannot register with Spotify Connect: {e}"))?;
    let cluster = Cluster::parse_from_bytes(&bytes)
        .map_err(|e| format!("cannot decode the device list: {e}"))?;
    deliver_state(
        sink,
        &spotify_state(&cluster, spotify_now_ms(session.time_delta())),
    );
    Ok(cluster)
}

async fn send(session: &Session, command: &Command, to: &str) -> Result<(), String> {
    let (method, path, body) = request(command, session.device_id(), to, &command_id());
    let mut headers = HeaderMap::new();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
    let result = session
        .spclient()
        .request(&method, &path, Some(headers), Some(body.as_bytes()));
    result
        .await
        .map(|_| ())
        .map_err(|e| format!("Spotify Connect command failed: {e}"))
}

/// Matches `LsbDevice` in the header.
#[repr(C)]
pub struct LsbDevice {
    pub id: *const c_char,
    pub name: *const c_char,
    pub device_type: *const c_char,
    pub software: *const c_char,
    pub is_active: bool,
}

pub type LsbDevicesCallback = extern "C" fn(
    context: *mut c_void,
    status: i32,
    message: *const c_char,
    devices: *const LsbDevice,
    count: usize,
);
pub type LsbCommandCallback =
    extern "C" fn(context: *mut c_void, status: i32, message: *const c_char);

pub(crate) fn deliver_devices(
    callback: LsbDevicesCallback,
    context: *mut c_void,
    result: Result<Vec<ConnectDevice>, String>,
) {
    match result {
        Ok(devices) => {
            let texts: Vec<_> = devices
                .iter()
                .map(|d| [&d.id, &d.name, &d.device_type, &d.software].map(|t| c_text(t)))
                .collect();
            let raw: Vec<_> = devices
                .iter()
                .zip(&texts)
                .map(|(d, [id, name, device_type, software])| LsbDevice {
                    id: id.as_ptr(),
                    name: name.as_ptr(),
                    device_type: device_type.as_ptr(),
                    software: software.as_ptr(),
                    is_active: d.is_active,
                })
                .collect();
            callback(context, LSB_OK, std::ptr::null(), raw.as_ptr(), raw.len());
        }
        Err(message) => {
            let message = c_text(&message);
            callback(
                context,
                LSB_ERR_CONNECT,
                message.as_ptr(),
                std::ptr::null(),
                0,
            );
        }
    }
}

pub(crate) fn deliver_status(
    callback: LsbCommandCallback,
    context: *mut c_void,
    result: Result<(), String>,
) {
    match result {
        Ok(()) => callback(context, LSB_OK, std::ptr::null()),
        Err(message) => {
            let message = c_text(&message);
            callback(context, LSB_ERR_CONNECT, message.as_ptr());
        }
    }
}

/// One Connect call. The worker runs them one at a time, in call order.
pub(crate) enum Job {
    Devices {
        session: Session,
        callback: LsbDevicesCallback,
        context: Context,
    },
    Command {
        session: Session,
        command: Command,
        to: String,
        callback: LsbCommandCallback,
        context: Context,
    },
}

/// Starts the worker that runs Connect calls in order, so a pause can't overtake a play.
pub(crate) fn spawn_worker(
    runtime: &tokio::runtime::Runtime,
    sink: SharedSink,
) -> UnboundedSender<Job> {
    let (jobs, mut queue) = unbounded_channel::<Job>();
    runtime.spawn(async move {
        // The dealer of the newest session that called, and the connection ID that it
        // last registered with. A new login makes a new session, and a dealer reconnect
        // makes a new connection ID. Either one registers again at the next command.
        let mut dealer: Option<Dealer> = None;
        let mut registered: Option<String> = None;
        while let Some(job) = queue.recv().await {
            match job {
                Job::Devices {
                    session,
                    callback,
                    context,
                } => {
                    let result = register(&session, &mut dealer, &sink).await;
                    registered = result.is_ok().then(|| session.connection_id());
                    let result = result.map(|cluster| devices(&cluster, session.device_id()));
                    deliver_devices(callback, context.0, result);
                }
                Job::Command {
                    session,
                    command,
                    to,
                    callback,
                    context,
                } => {
                    if let Some(d) = &dealer {
                        // The session updates its time delta at each keep-alive ping.
                        d.time_delta.store(session.time_delta(), Ordering::Relaxed);
                    }
                    let current = dealer.as_ref().is_some_and(|d| {
                        d.device_id == session.device_id()
                            && registered.as_deref() == Some(d.connection_id.borrow().as_str())
                    });
                    let mut result = Ok(());
                    if !current {
                        result = register(&session, &mut dealer, &sink).await.map(|_| ());
                    }
                    if result.is_ok() {
                        result = send(&session, &command, &to).await;
                    }
                    // The registration can go stale, for example after sleep or a network
                    // change. Then register again once, with the newest connection ID, and
                    // send the command once more. Next and prev are not retried: if the
                    // first one did arrive, the retry skips twice.
                    if result.is_err() && command.can_retry() {
                        result = register(&session, &mut dealer, &sink).await.map(|_| ());
                        if result.is_ok() {
                            result = send(&session, &command, &to).await;
                        }
                    }
                    registered = result.is_ok().then(|| session.connection_id());
                    deliver_status(callback, context.0, result);
                }
            }
        }
    });
    jobs
}

unsafe fn queue(bridge: *mut crate::LsbBridge, job: impl FnOnce(Session) -> Job) -> i32 {
    let session = match session(bridge) {
        Ok(session) => session,
        Err(status) => return status,
    };
    // The worker stops only when the bridge is freed, so a send can't fail here.
    let _ = (*bridge).connect.send(job(session));
    LSB_OK
}

unsafe fn queue_command(
    bridge: *mut crate::LsbBridge,
    device_id: *const c_char,
    command: Option<Command>,
    on_result: Option<LsbCommandCallback>,
    context: *mut c_void,
) -> i32 {
    let (Some(callback), Some(command)) = (on_result, command) else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let Some(to) = read_str(device_id).filter(|id| valid_device_id(id)) else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let to = to.to_owned();
    let context = Context(context);
    queue(bridge, |session| Job::Command {
        session,
        command,
        to,
        callback,
        context,
    })
}

/// Registers this session as a Connect device and lists the account's other devices.
///
/// # Safety
/// `bridge` must be valid. `context` and `on_result` must be safe to call from any thread.
#[no_mangle]
pub unsafe extern "C" fn lsb_connect_devices(
    bridge: *mut crate::LsbBridge,
    on_result: Option<LsbDevicesCallback>,
    context: *mut c_void,
) -> i32 {
    let Some(callback) = on_result else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let context = Context(context);
    queue(bridge, |session| Job::Devices {
        session,
        callback,
        context,
    })
}

/// Plays a playlist or Liked Songs on a device, from a track or from the start.
///
/// # Safety
/// `bridge` must be valid. The strings must be NUL-terminated, and `track_uri` may be
/// NULL. `context` and `on_result` must be safe to call from any thread.
#[no_mangle]
pub unsafe extern "C" fn lsb_connect_play(
    bridge: *mut crate::LsbBridge,
    device_id: *const c_char,
    context_uri: *const c_char,
    track_uri: *const c_char,
    on_result: Option<LsbCommandCallback>,
    context: *mut c_void,
) -> i32 {
    let track = match read_str(track_uri) {
        Some(uri) if valid_track(uri) => Some(uri.to_owned()),
        None if track_uri.is_null() => None,
        _ => return LSB_ERR_INVALID_ARGUMENT,
    };
    let command = read_str(context_uri)
        .filter(|uri| valid_context(uri))
        .map(|uri| Command::Play {
            context: uri.to_owned(),
            track,
        });
    queue_command(bridge, device_id, command, on_result, context)
}

/// Sends one of `LSB_COMMAND_*` to a device.
///
/// # Safety
/// `bridge` must be valid. `device_id` must be NUL-terminated. `context` and
/// `on_result` must be safe to call from any thread.
#[no_mangle]
pub unsafe extern "C" fn lsb_connect_command(
    bridge: *mut crate::LsbBridge,
    device_id: *const c_char,
    command: u32,
    on_result: Option<LsbCommandCallback>,
    context: *mut c_void,
) -> i32 {
    let command = match command {
        LSB_COMMAND_PAUSE => Some(Command::Pause),
        LSB_COMMAND_RESUME => Some(Command::Resume),
        LSB_COMMAND_NEXT => Some(Command::Next),
        LSB_COMMAND_PREV => Some(Command::Prev),
        _ => None,
    };
    queue_command(bridge, device_id, command, on_result, context)
}

/// # Safety
/// As for `lsb_connect_command`.
#[no_mangle]
pub unsafe extern "C" fn lsb_connect_seek(
    bridge: *mut crate::LsbBridge,
    device_id: *const c_char,
    position_ms: u32,
    on_result: Option<LsbCommandCallback>,
    context: *mut c_void,
) -> i32 {
    let command = Some(Command::Seek(position_ms));
    queue_command(bridge, device_id, command, on_result, context)
}

/// Sets the device's volume from 0 to 65535.
///
/// # Safety
/// As for `lsb_connect_command`.
#[no_mangle]
pub unsafe extern "C" fn lsb_connect_volume(
    bridge: *mut crate::LsbBridge,
    device_id: *const c_char,
    volume: u16,
    on_result: Option<LsbCommandCallback>,
    context: *mut c_void,
) -> i32 {
    let command = Some(Command::Volume(volume));
    queue_command(bridge, device_id, command, on_result, context)
}

/// Turns Spotify's shuffle or one of its repeat modes on or off on a device.
/// `option` is one of `LSB_OPTION_*`.
///
/// # Safety
/// As for `lsb_connect_command`.
#[no_mangle]
pub unsafe extern "C" fn lsb_connect_set_option(
    bridge: *mut crate::LsbBridge,
    device_id: *const c_char,
    option: u32,
    on: bool,
    on_result: Option<LsbCommandCallback>,
    context: *mut c_void,
) -> i32 {
    let command = match option {
        LSB_OPTION_SHUFFLE => Some(Command::Shuffle(on)),
        LSB_OPTION_REPEAT_CONTEXT => Some(Command::RepeatContext(on)),
        LSB_OPTION_REPEAT_TRACK => Some(Command::RepeatTrack(on)),
        _ => None,
    };
    queue_command(bridge, device_id, command, on_result, context)
}

/// Sets the callback for the Spotify app's player state, or clears it when
/// `on_state` is NULL. It runs for each cluster update after the first Connect call.
///
/// # Safety
/// `bridge` must be valid. `context` and `on_state` must be safe to call from any thread.
#[no_mangle]
pub unsafe extern "C" fn lsb_connect_watch(
    bridge: *mut crate::LsbBridge,
    on_state: Option<LsbStateCallback>,
    context: *mut c_void,
) -> i32 {
    let Some(bridge) = bridge.as_ref() else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let sink = on_state.map(|callback| StateSink { callback, context });
    set_sink(&bridge.state_sink, sink);
    LSB_OK
}
