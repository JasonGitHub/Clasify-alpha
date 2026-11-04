//! Spotify Connect commands through librespot's session. Clasify plays no audio: it
//! registers itself as a Connect device that cannot play, then tells the Spotify app's
//! device what to do. Only the requests that `request` builds can be sent. The app
//! cannot pass an endpoint path.

use std::ffi::{c_char, c_void};

use futures_util::StreamExt;
use http::header::{HeaderValue, CONTENT_TYPE};
use http::{HeaderMap, Method};
use librespot_core::Session;
use librespot_protocol::connect::{
    Capabilities, Cluster, Device, DeviceInfo, MemberType, PutStateReason, PutStateRequest,
};
use librespot_protocol::devices::DeviceType;
use protobuf::Message;
use tokio::sync::mpsc::{unbounded_channel, UnboundedSender};

use crate::library::{c_text, session, Context};
use crate::{read_str, LSB_ERR_CONNECT, LSB_ERR_INVALID_ARGUMENT, LSB_OK};

pub const LSB_COMMAND_PAUSE: u32 = 0;
pub const LSB_COMMAND_RESUME: u32 = 1;
pub const LSB_COMMAND_NEXT: u32 = 2;
pub const LSB_COMMAND_PREV: u32 = 3;

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

/// Starts the dealer once per session, then sends a NEW_DEVICE state. The reply is
/// the account's cluster, with all its devices.
async fn register(session: &Session) -> Result<Cluster, String> {
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
            .map_err(|e| format!("cannot listen to Spotify Connect: {e}"))?;
        session
            .dealer()
            .start()
            .await
            .map_err(|e| format!("cannot start Spotify Connect: {e}"))?;
        let id = tokio::time::timeout(std::time::Duration::from_secs(10), ids.next())
            .await
            .map_err(|_| "no Spotify Connect connection ID within 10 s".to_owned())?
            .ok_or("Spotify Connect closed".to_owned())?
            .map_err(|e| format!("bad Spotify Connect connection ID: {e}"))?;
        session.set_connection_id(&id);
    }
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
    Cluster::parse_from_bytes(&bytes).map_err(|e| format!("cannot decode the device list: {e}"))
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
pub(crate) fn spawn_worker(runtime: &tokio::runtime::Runtime) -> UnboundedSender<Job> {
    let (jobs, mut queue) = unbounded_channel::<Job>();
    runtime.spawn(async move {
        // The device ID of the session that is registered. A new login makes a new
        // session with a new device ID, which registers again at its first call.
        let mut registered: Option<String> = None;
        while let Some(job) = queue.recv().await {
            match job {
                Job::Devices {
                    session,
                    callback,
                    context,
                } => {
                    let result = register(&session).await;
                    if result.is_ok() {
                        registered = Some(session.device_id().to_owned());
                    }
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
                    let fresh = registered.as_deref() != Some(session.device_id());
                    let mut result = Ok(());
                    if fresh {
                        result = register(&session).await.map(|_| ());
                    }
                    if result.is_ok() {
                        result = send(&session, &command, &to).await;
                    }
                    // The registration can go stale, for example after sleep or a network
                    // change. Then register again once and send the command once more. Next and
                    // prev are not retried: if the first one did arrive, the retry skips twice.
                    let retry = result.is_err() && !fresh && command.can_retry();
                    if retry && register(&session).await.is_ok() {
                        result = send(&session, &command, &to).await;
                    }
                    registered = result.is_ok().then(|| session.device_id().to_owned());
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
