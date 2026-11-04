//! C FFI over librespot. The C header is `include/librespot_bridge.h`.
//! Keep the two in sync: the `header_matches_rust` test checks the constants.
//! The bridge plays no audio. It logs in, reads the library, and sends Spotify
//! Connect commands to the Spotify app.

use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use librespot_core::{authentication::Credentials, Session, SessionConfig};

mod connect;
mod library;
mod oauth;
pub use connect::{
    lsb_connect_command, lsb_connect_devices, lsb_connect_play, lsb_connect_seek,
    lsb_connect_set_option, lsb_connect_volume, lsb_connect_watch, LsbCommandCallback, LsbDevice,
    LsbDevicesCallback, LsbPlayerState, LsbStateCallback, LSB_COMMAND_NEXT, LSB_COMMAND_PAUSE,
    LSB_COMMAND_PREV, LSB_COMMAND_RESUME, LSB_OPTION_REPEAT_CONTEXT, LSB_OPTION_REPEAT_TRACK,
    LSB_OPTION_SHUFFLE,
};
pub use library::{
    lsb_read_playlists, lsb_read_tracks, LsbPlaylist, LsbPlaylistsCallback, LsbTrack,
    LsbTracksCallback,
};
pub use oauth::{
    lsb_oauth_cancel, lsb_oauth_login, lsb_oauth_refresh, LsbToken, LsbTokenCallback,
    OAUTH_REDIRECT_URI, OAUTH_SCOPES,
};

pub const LSB_OK: i32 = 0;
pub const LSB_ERR_INVALID_ARGUMENT: i32 = 1;
pub const LSB_ERR_NOT_LOGGED_IN: i32 = 2;
pub const LSB_ERR_OAUTH: i32 = 3;
pub const LSB_ERR_READ: i32 = 4;
pub const LSB_ERR_CONNECT: i32 = 5;

pub const LSB_EVENT_LOGGED_IN: u32 = 0;
pub const LSB_EVENT_ERROR: u32 = 1;

/// Matches `LsbEvent` in the header. The message is valid only during the callback.
#[repr(C)]
pub struct LsbEvent {
    pub kind: u32,
    pub message: *const c_char,
}
pub type LsbEventCallback = extern "C" fn(context: *mut c_void, event: *const LsbEvent);

#[derive(Clone, Copy)]
struct Callbacks {
    on_event: LsbEventCallback,
    context: *mut c_void,
}

// SAFETY: the header requires that `context` and the callback are safe to
// call from any thread. The bridge never reads through `context` itself.
unsafe impl Send for Callbacks {}
unsafe impl Sync for Callbacks {}

/// One event before it crosses the FFI.
#[derive(Debug, Default, PartialEq)]
struct Event {
    kind: u32,
    message: Option<String>,
}

impl Callbacks {
    fn emit(&self, event: &Event) {
        let message = event
            .message
            .as_ref()
            .map(|t| CString::new(t.replace('\0', " ")).unwrap_or_default());
        let raw = LsbEvent {
            kind: event.kind,
            message: message.as_ref().map_or(std::ptr::null(), |t| t.as_ptr()),
        };
        (self.on_event)(self.context, &raw);
    }
}

struct Connected {
    /// For the library reads and the Connect commands.
    session: Session,
}

pub struct LsbBridge {
    runtime: tokio::runtime::Runtime,
    callbacks: Callbacks,
    connected: Arc<Mutex<Option<Connected>>>,
    /// Counts `lsb_login` calls. Only the newest login may publish its result.
    latest_login: Arc<AtomicU64>,
    /// Spotify Connect calls, run one at a time in call order.
    connect: tokio::sync::mpsc::UnboundedSender<connect::Job>,
    /// The callback for the Spotify app's player state.
    state_sink: connect::SharedSink,
}

#[no_mangle]
pub extern "C" fn lsb_new(
    on_event: Option<LsbEventCallback>,
    context: *mut c_void,
) -> *mut LsbBridge {
    let Some(on_event) = on_event else {
        return std::ptr::null_mut();
    };
    let Ok(runtime) = tokio::runtime::Runtime::new() else {
        return std::ptr::null_mut();
    };
    let callbacks = Callbacks { on_event, context };
    let connected = Arc::new(Mutex::new(None));
    let state_sink = connect::SharedSink::default();
    let connect = connect::spawn_worker(&runtime, state_sink.clone());
    Box::into_raw(Box::new(LsbBridge {
        runtime,
        callbacks,
        connected,
        latest_login: Arc::new(AtomicU64::new(0)),
        connect,
        state_sink,
    }))
}

/// # Safety
/// `bridge` must come from `lsb_new` and must not be used again.
#[no_mangle]
pub unsafe extern "C" fn lsb_free(bridge: *mut LsbBridge) {
    if !bridge.is_null() {
        // Wait for a running state callback, and stop new ones, before the caller
        // frees the watch context.
        connect::set_sink(&(*bridge).state_sink, None);
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
/// No credentials are cached on disk.
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
                callbacks.emit(&Event {
                    kind: LSB_EVENT_ERROR,
                    message: Some(error.to_string()),
                });
            }
            return;
        }
        let replaced = {
            let mut slot = connected.lock().unwrap();
            if !is_latest() {
                return; // A newer login replaced this one.
            }
            slot.replace(Connected {
                session: session.clone(),
            })
        };
        // Drop the old session outside the lock.
        drop(replaced);
        // Not under the lock, so a callback can call back into the bridge.
        // A login that starts right now can still follow this event.
        if is_latest() {
            callbacks.emit(&Event {
                kind: LSB_EVENT_LOGGED_IN,
                message: Some(session.username()),
            });
        }
    });
    LSB_OK
}

/// Runs `action` with the logged-in session.
unsafe fn with_session(bridge: *mut LsbBridge, action: impl FnOnce(&Session)) -> i32 {
    let Some(bridge) = bridge.as_ref() else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    match bridge.connected.lock().unwrap().as_ref() {
        Some(connected) => {
            action(&connected.session);
            LSB_OK
        }
        None => LSB_ERR_NOT_LOGGED_IN,
    }
}

#[cfg(test)]
mod tests;
