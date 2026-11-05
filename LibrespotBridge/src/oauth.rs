//! OAuth login and token refresh through librespot-oauth (PKCE), with librespot's
//! own client ID. The bridge stores no token. The app keeps the refresh token in
//! the Keychain.

use std::ffi::{c_char, c_void, CString};
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use librespot_core::SessionConfig;
use librespot_oauth::{OAuthClient, OAuthClientBuilder, OAuthToken};

use crate::{read_str, LSB_ERR_INVALID_ARGUMENT, LSB_ERR_OAUTH, LSB_ERR_REFUSED, LSB_OK};

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
                status: if is_refused(&message) {
                    LSB_ERR_REFUSED
                } else {
                    LSB_ERR_OAUTH
                },
                expires_in_s: 0,
                access_token: None,
                refresh_token: None,
                message: Some(message),
            },
        }
    }
}

/// Spotify rejected the grant, for example a revoked or replaced refresh token. The
/// oauth2 crate puts the OAuth error code `invalid_grant` in its error text. Any other
/// failure (offline, a timeout, a server error) can pass on a later try.
pub(crate) fn is_refused(message: &str) -> bool {
    message.contains("invalid_grant")
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

/// Where one login is. Only the login thread moves it to `Decided`, and only a stop
/// moves it to `Cancelled`. One lock makes the two choices exclusive.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) enum Phase {
    Running,
    Cancelled,
    /// The result is fixed and goes to the callback. A stop no longer changes it.
    Decided,
}

/// The shared state of one login.
#[derive(Debug)]
pub(crate) struct LoginState {
    /// True once the login stopped listening on port 8898: it got a request, or failed.
    listening_done: AtomicBool,
    phase: Mutex<Phase>,
}

impl LoginState {
    pub(crate) fn new() -> Arc<Self> {
        Arc::new(LoginState {
            listening_done: AtomicBool::new(false),
            phase: Mutex::new(Phase::Running),
        })
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Phase> {
        self.phase.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Called by the login thread when librespot-oauth returns. A cancelled login
    /// sends no token.
    pub(crate) fn finish(&self, result: Result<OAuthToken, String>) -> Result<OAuthToken, String> {
        self.listening_done.store(true, Ordering::SeqCst);
        let mut phase = self.lock();
        if *phase == Phase::Cancelled {
            return Err("login cancelled".to_owned());
        }
        *phase = Phase::Decided;
        result
    }

    /// Marks the login cancelled, unless its result is already fixed.
    pub(crate) fn cancel(&self) {
        let mut phase = self.lock();
        if *phase == Phase::Running {
            *phase = Phase::Cancelled;
        }
    }

    #[cfg(test)]
    pub(crate) fn phase(&self) -> Phase {
        *self.lock()
    }

    pub(crate) fn is_listening(&self) -> bool {
        !self.listening_done.load(Ordering::SeqCst)
    }
}

pub(crate) struct Login {
    pub handle: JoinHandle<()>,
    pub state: Arc<LoginState>,
}

fn start_login(target: Target) -> Login {
    let state = LoginState::new();
    let thread_state = state.clone();
    let handle = run(target, move || {
        // `finish` must run on every path, so that the login stops counting as listening.
        let result = client().and_then(|c| c.get_access_token().map_err(|e| e.to_string()));
        thread_state.finish(result)
    });
    Login { handle, state }
}

/// The newest `lsb_oauth_login`. The lock is never held while a login is stopped,
/// so a token callback can call `lsb_oauth_login` or `lsb_oauth_cancel` again.
static LOGIN: Mutex<Option<Login>> = Mutex::new(None);

/// Stops a login and waits until it has sent its result, so that port 8898 is free
/// again. librespot-oauth cannot be stopped directly, so this sends its listener a
/// request without a code. It sends it again while that login still listens,
/// because the thread may not listen yet. It stops sending as soon as the login no
/// longer listens, before its callback runs, so a new login that the callback starts
/// on the same port gets no stop request.
/// Called from the login thread itself (from its callback), it returns at once:
/// that thread no longer listens, and it ends when the callback returns.
pub(crate) fn stop_login(login: Login, address: SocketAddr) {
    login.state.cancel();
    if login.handle.thread().id() == std::thread::current().id() {
        return;
    }
    while !login.handle.is_finished() {
        if login.state.is_listening() {
            send_stop(address);
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    let _ = login.handle.join();
}

fn send_stop(address: SocketAddr) {
    if let Ok(mut stream) = TcpStream::connect_timeout(&address, Duration::from_secs(1)) {
        let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
        if stream
            .write_all(b"GET /login?error=cancelled HTTP/1.1\r\n\r\n")
            .is_ok()
        {
            // Wait for the answer, so that the listener has read the request.
            let _ = stream.read(&mut [0u8; 1]);
        }
    }
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

fn lock_login() -> std::sync::MutexGuard<'static, Option<Login>> {
    LOGIN.lock().unwrap_or_else(|e| e.into_inner())
}

fn take_login() -> Option<Login> {
    lock_login().take()
}

/// Stops the running login. Its callback gets LSB_ERR_OAUTH before this returns,
/// unless its result was already fixed. If no login runs, it does nothing.
#[no_mangle]
pub extern "C" fn lsb_oauth_cancel() -> i32 {
    if let Some(login) = take_login() {
        stop_login(login, listen_address());
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
