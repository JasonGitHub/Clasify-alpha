//! OAuth login and token refresh through librespot-oauth (PKCE), with librespot's
//! own client ID. The bridge stores no token. The app keeps the refresh token in
//! the Keychain.

use std::ffi::{c_char, c_void, CString};
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use librespot_core::SessionConfig;
use librespot_oauth::{OAuthClient, OAuthClientBuilder, OAuthToken};

use crate::{read_str, LSB_ERR_INVALID_ARGUMENT, LSB_ERR_OAUTH, LSB_OK};

/// The loopback redirect URI. librespot's CLI uses `http://127.0.0.1:<port>/login`,
/// and the keymaster client ID accepts it. The spike confirmed port 8898.
pub const OAUTH_REDIRECT_URI: &str = "http://127.0.0.1:8898/login";
const OAUTH_LISTEN_ADDRESS: &str = "127.0.0.1:8898";

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
    "<!doctype html><html><body><h1>You are logged in. Go back to Clasify.</h1></body></html>";

/// Matches `LsbToken` in the header. The strings are valid only during the callback.
#[repr(C)]
pub struct LsbToken {
    pub status: i32,
    pub expires_in_s: u32,
    pub access_token: *const c_char,
    pub refresh_token: *const c_char,
    pub message: *const c_char,
}
pub type LsbTokenCallback = extern "C" fn(context: *mut c_void, result: *const LsbToken);

struct Target {
    callback: LsbTokenCallback,
    context: *mut c_void,
}

// SAFETY: the header requires that `context` and the callback are safe to call
// from any thread. The bridge never reads through `context` itself.
unsafe impl Send for Target {}

fn client() -> Result<OAuthClient, String> {
    // librespot's CLI uses the session's default client ID for OAuth.
    let client_id = SessionConfig::default().client_id;
    OAuthClientBuilder::new(&client_id, OAUTH_REDIRECT_URI, OAUTH_SCOPES.to_vec())
        .open_in_browser()
        .with_custom_message(OAUTH_PAGE)
        .build()
        .map_err(|error| error.to_string())
}

/// A token result before it crosses the FFI.
#[derive(Debug, PartialEq)]
pub(crate) struct TokenResult {
    pub status: i32,
    pub expires_in_s: u32,
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    pub message: Option<String>,
}

impl TokenResult {
    pub(crate) fn new(result: Result<OAuthToken, String>, now: Instant) -> Self {
        match result {
            Ok(token) => TokenResult {
                status: LSB_OK,
                expires_in_s: seconds_until(token.expires_at, now),
                access_token: Some(token.access_token),
                // Spotify can leave out the refresh token on a refresh.
                refresh_token: Some(token.refresh_token).filter(|t| !t.is_empty()),
                message: None,
            },
            Err(message) => TokenResult {
                status: LSB_ERR_OAUTH,
                expires_in_s: 0,
                access_token: None,
                refresh_token: None,
                message: Some(message),
            },
        }
    }
}

fn seconds_until(time: Instant, now: Instant) -> u32 {
    let seconds = time.saturating_duration_since(now).as_secs();
    u32::try_from(seconds).unwrap_or(u32::MAX)
}

fn deliver(target: Target, result: TokenResult) {
    let text = |t: &Option<String>| {
        t.as_ref()
            .map(|t| CString::new(t.replace('\0', " ")).unwrap_or_default())
    };
    let (access, refresh, message) = (
        text(&result.access_token),
        text(&result.refresh_token),
        text(&result.message),
    );
    let ptr = |t: &Option<CString>| t.as_ref().map_or(std::ptr::null(), |t| t.as_ptr());
    let raw = LsbToken {
        status: result.status,
        expires_in_s: result.expires_in_s,
        access_token: ptr(&access),
        refresh_token: ptr(&refresh),
        message: ptr(&message),
    };
    (target.callback)(target.context, &raw);
}

fn run(
    target: Target,
    work: impl FnOnce() -> Result<OAuthToken, String> + Send + 'static,
) -> JoinHandle<()> {
    std::thread::spawn(move || {
        let result = work();
        deliver(target, TokenResult::new(result, Instant::now()));
    })
}

/// The id of the login that may still send a token. 0 when none may: a cancelled
/// login that already got the code from the browser must not send a token.
static ACTIVE_LOGIN: AtomicU64 = AtomicU64::new(0);
static NEXT_LOGIN: AtomicU64 = AtomicU64::new(1);

/// A login's result, or a failure if it was cancelled after it started.
pub(crate) fn login_outcome(
    result: Result<OAuthToken, String>,
    login: u64,
    active: u64,
) -> Result<OAuthToken, String> {
    if login == active {
        result
    } else {
        Err("login cancelled".to_owned())
    }
}

fn start_login(target: Target) -> JoinHandle<()> {
    let login = NEXT_LOGIN.fetch_add(1, Ordering::SeqCst);
    ACTIVE_LOGIN.store(login, Ordering::SeqCst);
    run(target, move || {
        let result = client()?.get_access_token().map_err(|e| e.to_string());
        login_outcome(result, login, ACTIVE_LOGIN.load(Ordering::SeqCst))
    })
}

/// The thread of the newest `lsb_oauth_login`. The lock is never held while a
/// thread is stopped, so a token callback can call `lsb_oauth_login` or
/// `lsb_oauth_cancel` again.
static LOGIN: Mutex<Option<JoinHandle<()>>> = Mutex::new(None);

/// Stops a login thread and waits until it has sent its result, so that port 8898
/// is free again. librespot-oauth cannot be stopped directly, so this sends its
/// listener a request without a code. It sends it again until a listener answers,
/// because the thread may not listen yet. After an answer it sends no more, so that
/// a new login that listens on the same port is not stopped too. A thread that
/// already got the code from the browser does not listen; then this only waits.
/// Called from the login thread itself (from its callback), it returns at once:
/// that thread no longer listens, and it ends when the callback returns.
pub(crate) fn stop_login(handle: JoinHandle<()>, address: SocketAddr) {
    if handle.thread().id() == std::thread::current().id() {
        return;
    }
    let mut answered = false;
    while !handle.is_finished() {
        if !answered {
            answered = send_stop(address);
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    let _ = handle.join();
}

/// True when a listener read the stop request and answered it.
fn send_stop(address: SocketAddr) -> bool {
    let Ok(mut stream) = TcpStream::connect_timeout(&address, Duration::from_secs(1)) else {
        return false;
    };
    let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
    let sent = stream.write_all(b"GET /login?error=cancelled HTTP/1.1\r\n\r\n");
    let mut answer = [0u8; 1];
    sent.is_ok() && matches!(stream.read(&mut answer), Ok(n) if n > 0)
}

fn listen_address() -> SocketAddr {
    OAUTH_LISTEN_ADDRESS.parse().expect("valid address")
}

/// Opens the Spotify login page in the browser and waits on the loopback redirect,
/// on a new thread. The result comes once through `on_result`. A login that still
/// runs is stopped first, as with `lsb_oauth_cancel`.
///
/// # Safety
/// `context` and `on_result` must be safe to call from any thread.
#[no_mangle]
pub extern "C" fn lsb_oauth_login(
    on_result: Option<LsbTokenCallback>,
    context: *mut c_void,
) -> i32 {
    let Some(callback) = on_result else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    loop {
        ACTIVE_LOGIN.store(0, Ordering::SeqCst);
        if let Some(older) = take_login() {
            stop_login(older, listen_address());
        }
        let mut login = lock_login();
        // Another call can start a login while the older one stops. Then stop that too.
        if login.is_none() {
            *login = Some(start_login(Target { callback, context }));
            return LSB_OK;
        }
    }
}

fn lock_login() -> std::sync::MutexGuard<'static, Option<JoinHandle<()>>> {
    LOGIN.lock().unwrap_or_else(|e| e.into_inner())
}

fn take_login() -> Option<JoinHandle<()>> {
    lock_login().take()
}

/// Stops a login that waits for the browser. Its callback then gets LSB_ERR_OAUTH,
/// before this returns. If no login runs, it does nothing.
#[no_mangle]
pub extern "C" fn lsb_oauth_cancel() -> i32 {
    ACTIVE_LOGIN.store(0, Ordering::SeqCst);
    if let Some(handle) = take_login() {
        stop_login(handle, listen_address());
    }
    LSB_OK
}

/// Gets a new access token for a refresh token, on a new thread. The result comes
/// once through `on_result`. Its `refresh_token` is NULL when Spotify keeps the old one.
///
/// # Safety
/// `refresh_token` must be a NUL-terminated string. `context` and `on_result` must be
/// safe to call from any thread.
#[no_mangle]
pub unsafe extern "C" fn lsb_oauth_refresh(
    refresh_token: *const c_char,
    on_result: Option<LsbTokenCallback>,
    context: *mut c_void,
) -> i32 {
    let (Some(callback), Some(token)) = (on_result, read_str(refresh_token)) else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    if token.is_empty() {
        return LSB_ERR_INVALID_ARGUMENT;
    }
    let token = token.to_owned();
    run(Target { callback, context }, move || {
        client()?.refresh_token(&token).map_err(|e| e.to_string())
    });
    LSB_OK
}
