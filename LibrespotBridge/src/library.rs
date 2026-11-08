//! Read-only library reads through librespot's own session (spclient), not the Web API:
//! the playlist list (rootlist), and the tracks of a playlist or of Liked Songs.

use std::collections::{HashMap, VecDeque};
use std::ffi::{c_char, c_void, CString};

use librespot_core::{FileId, Session, SpotifyId};
use librespot_protocol::context_page::ContextPage;
use librespot_protocol::extended_metadata::{
    BatchedEntityRequest, BatchedExtensionResponse, EntityRequest, ExtensionQuery,
};
use librespot_protocol::extension_kind::ExtensionKind;
use librespot_protocol::metadata::{image::Size, Image, Track as TrackMessage};
use librespot_protocol::playlist4_external::SelectedListContent;
use protobuf::{EnumOrUnknown, Message};

use crate::{
    read_str, with_session, LSB_ERR_INVALID_ARGUMENT, LSB_ERR_NOT_LOGGED_IN, LSB_ERR_READ, LSB_OK,
};

/// Rootlist items to ask for in one request.
const ROOTLIST_PAGE: usize = 500;
/// Tracks to ask for in one extended-metadata request.
const METADATA_BATCH: usize = 100;
/// Stops a page chain that never ends.
const MAX_PAGES: usize = 1000;

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Playlist {
    pub uri: String,
    pub name: String,
    pub track_count: u32,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub(crate) struct Track {
    pub uri: String,
    pub title: String,
    pub artist: String,
    /// The album cover's image file ID in lowercase hex, or empty when there is none.
    pub cover_id: String,
    /// Like `spotify:album:<id>`, or empty when the track has no album.
    pub album_uri: String,
    pub album_name: String,
    /// The album's artists, joined with ", ". Empty when Spotify gives none.
    pub album_artist: String,
    pub duration_ms: u32,
    /// The disc and the track's place on it, from 1. 0 when Spotify does not give it.
    pub disc_number: u32,
    pub track_number: u32,
}

/// One decoded rootlist page.
#[derive(Debug, PartialEq)]
pub(crate) struct RootlistPage {
    pub playlists: Vec<Playlist>,
    /// Items in this page, folder markers included. The next page starts after them.
    pub items: usize,
    /// Items in the whole rootlist.
    pub length: usize,
}

/// Decodes a decorated rootlist. Folder markers (`spotify:start-group:...` and
/// `spotify:end-group:...`) are skipped, so folders come out flat.
pub(crate) fn decode_rootlist(bytes: &[u8]) -> Result<RootlistPage, String> {
    let list = SelectedListContent::parse_from_bytes(bytes)
        .map_err(|e| format!("cannot decode the playlist list: {e}"))?;
    let contents = &list.contents;
    let playlists = contents
        .items
        .iter()
        .enumerate()
        .filter(|(_, item)| item.uri().starts_with("spotify:playlist:"))
        .map(|(index, item)| {
            let meta = contents.meta_items.get(index);
            Playlist {
                uri: item.uri().to_owned(),
                name: meta.map_or("", |m| m.attributes.name()).to_owned(),
                track_count: meta.map_or(0, |m| m.length().max(0) as u32),
            }
        })
        .collect();
    Ok(RootlistPage {
        playlists,
        items: contents.items.len(),
        length: list.length().max(0) as usize,
    })
}

pub(crate) async fn read_playlists(session: &Session) -> Result<Vec<Playlist>, String> {
    let mut playlists = Vec::new();
    let mut from = 0;
    loop {
        let bytes = session
            .spclient()
            .get_rootlist(from, Some(ROOTLIST_PAGE))
            .await
            .map_err(|e| format!("cannot read the playlist list: {e}"))?;
        let page = decode_rootlist(&bytes)?;
        playlists.extend(page.playlists);
        from += page.items;
        if page.items == 0 || from >= page.length {
            return Ok(playlists);
        }
    }
}

/// Where context pages come from. Tests use a fake.
pub(crate) trait PageSource {
    async fn context(&self, uri: &str) -> Result<Vec<ContextPage>, String>;
    async fn page(&self, url: &str) -> Result<ContextPage, String>;
}

struct SessionPages<'a>(&'a Session);

impl PageSource for SessionPages<'_> {
    async fn context(&self, uri: &str) -> Result<Vec<ContextPage>, String> {
        let context = self.0.spclient().get_context(uri).await;
        Ok(context
            .map_err(|e| format!("cannot read {uri}: {e}"))?
            .pages)
    }

    async fn page(&self, url: &str) -> Result<ContextPage, String> {
        let bytes = self.0.spclient().get_next_page(url).await;
        let bytes = bytes.map_err(|e| format!("cannot read a page: {e}"))?;
        let json = String::from_utf8_lossy(&bytes);
        protobuf_json_mapping::parse_from_str_with_options(&json, &IGNORE_UNKNOWN)
            .map_err(|e| format!("cannot decode a page: {e}"))
    }
}

const IGNORE_UNKNOWN: protobuf_json_mapping::ParseOptions = protobuf_json_mapping::ParseOptions {
    ignore_unknown_fields: true,
    _future_options: (),
};

fn url(text: &Option<String>) -> Option<&str> {
    text.as_deref().filter(|t| !t.is_empty())
}

/// All track URIs of a context, in order. It follows every page: a page that holds
/// only a `page_url` is loaded, and each `next_page_url` is followed. Items that are
/// not Spotify tracks (episodes, local files) are skipped.
pub(crate) async fn context_track_uris(
    source: &impl PageSource,
    uri: &str,
) -> Result<Vec<String>, String> {
    let mut queue: VecDeque<ContextPage> = source.context(uri).await?.into();
    let mut uris = Vec::new();
    let mut loads = 0;
    let mut load = |url: String| {
        loads += 1;
        let too_many = loads > MAX_PAGES;
        async move {
            if too_many {
                return Err(format!("{uri} has more than {MAX_PAGES} pages"));
            }
            source.page(&url).await
        }
    };
    while let Some(page) = queue.pop_front() {
        if page.tracks.is_empty() {
            if let Some(page_url) = url(&page.page_url) {
                let mut loaded = load(page_url.to_owned()).await?;
                if url(&loaded.next_page_url).is_none() {
                    loaded.next_page_url = page.next_page_url;
                }
                if loaded.tracks.is_empty() && url(&loaded.page_url).is_some() {
                    loaded.page_url = None; // A page that only points on again is empty.
                }
                queue.push_front(loaded);
                continue;
            }
        }
        let tracks = page.tracks.iter().map(|t| t.uri());
        uris.extend(
            tracks
                .filter(|u| u.starts_with("spotify:track:"))
                .map(str::to_owned),
        );
        if let Some(next) = url(&page.next_page_url) {
            queue.push_front(load(next.to_owned()).await?);
        }
    }
    Ok(uris)
}

pub(crate) fn metadata_request(uris: &[String]) -> BatchedEntityRequest {
    let query = ExtensionQuery {
        extension_kind: EnumOrUnknown::new(ExtensionKind::TRACK_V4),
        ..Default::default()
    };
    BatchedEntityRequest {
        entity_request: uris
            .iter()
            .map(|uri| EntityRequest {
                entity_uri: uri.clone(),
                query: vec![query.clone()],
                ..Default::default()
            })
            .collect(),
        ..Default::default()
    }
}

/// Widest cover to take when the DEFAULT size is missing.
const MAX_COVER_WIDTH: i32 = 640;

/// The hex file ID of the album cover to show: the DEFAULT size (about 300 px), else the
/// widest image under 640 px, else the narrowest image, else empty. The image is at https://i.scdn.co/image/<hex>.
pub(crate) fn cover_id(track: &TrackMessage) -> String {
    let Some(album) = track.album.as_ref() else {
        return String::new();
    };
    let images = if album.cover_group.image.is_empty() {
        &album.cover
    } else {
        &album.cover_group.image
    };
    let usable = || images.iter().filter(|i| !i.file_id().is_empty());
    let default = usable().find(|i| i.has_size() && i.size() == Size::DEFAULT);
    let small = || {
        usable()
            .filter(|i| i.width() < MAX_COVER_WIDTH)
            .max_by_key(|i| i.width())
    };
    let narrowest = || usable().min_by_key(|i| i.width());
    default
        .or_else(small)
        .or_else(narrowest)
        .map(|i: &Image| FileId::from(i).to_base16().unwrap_or_default())
        .unwrap_or_default()
}

/// The album's URI, like `spotify:album:<id>`, or empty when the track has no album ID.
pub(crate) fn album_uri(track: &TrackMessage) -> String {
    track
        .album
        .as_ref()
        .and_then(|album| SpotifyId::from_raw(album.gid()).ok())
        .and_then(|id| id.to_base62().ok())
        .map(|id| format!("spotify:album:{id}"))
        .unwrap_or_default()
}

/// The tracks for `uris`, in the same order. A track without metadata is left out.
pub(crate) fn decode_metadata(response: &BatchedExtensionResponse, uris: &[String]) -> Vec<Track> {
    let mut found: HashMap<&str, Track> = HashMap::new();
    for data in response
        .extended_metadata
        .iter()
        .flat_map(|array| &array.extension_data)
    {
        let ok = data.header.status_code == 0 || data.header.status_code == 200;
        let Some(any) = data.extension_data.as_ref().filter(|_| ok) else {
            continue;
        };
        let Ok(track) = TrackMessage::parse_from_bytes(&any.value) else {
            continue;
        };
        let artists: Vec<&str> = track.artist.iter().map(|a| a.name()).collect();
        let album = track.album.as_ref();
        let album_artists: Vec<&str> = album
            .map(|a| a.artist.iter().map(|a| a.name()).collect())
            .unwrap_or_default();
        let track = Track {
            uri: data.entity_uri.clone(),
            title: track.name().to_owned(),
            artist: artists.join(", "),
            cover_id: cover_id(&track),
            album_uri: album_uri(&track),
            album_name: album.map_or("", |a| a.name()).to_owned(),
            album_artist: album_artists.join(", "),
            duration_ms: track.duration().max(0) as u32,
            disc_number: track.disc_number().max(0) as u32,
            track_number: track.number().max(0) as u32,
        };
        found.insert(data.entity_uri.as_str(), track);
    }
    uris.iter()
        .filter_map(|uri| found.get(uri.as_str()).cloned())
        .collect()
}

pub(crate) async fn read_tracks(session: &Session, uri: &str) -> Result<Vec<Track>, String> {
    let uris = context_track_uris(&SessionPages(session), uri).await?;
    read_metadata(session, &uris).await
}

/// The details of `uris`, in the same order, in batches of `METADATA_BATCH`.
async fn read_metadata(session: &Session, uris: &[String]) -> Result<Vec<Track>, String> {
    let mut tracks = Vec::with_capacity(uris.len());
    for chunk in uris.chunks(METADATA_BATCH) {
        let response = session
            .spclient()
            .get_extended_metadata(metadata_request(chunk))
            .await
            .map_err(|e| format!("cannot read track details: {e}"))?;
        tracks.extend(decode_metadata(&response, chunk));
    }
    Ok(tracks)
}

/// A track URI that `lsb_read_track` accepts: `spotify:track:` and a base-62 ID.
pub(crate) fn valid_track_uri(uri: &str) -> bool {
    uri.strip_prefix("spotify:track:")
        .is_some_and(|id| !id.is_empty() && id.bytes().all(|b| b.is_ascii_alphanumeric()))
}

/// The Liked Songs context of the logged-in user.
pub(crate) fn liked_songs_uri(username: &str) -> String {
    format!("spotify:user:{username}:collection")
}

/// Matches `LsbPlaylist` in the header.
#[repr(C)]
pub struct LsbPlaylist {
    pub uri: *const c_char,
    pub name: *const c_char,
    pub track_count: u32,
}

/// Matches `LsbTrack` in the header.
#[repr(C)]
pub struct LsbTrack {
    pub uri: *const c_char,
    pub title: *const c_char,
    pub artist: *const c_char,
    pub cover_id: *const c_char,
    pub album_uri: *const c_char,
    pub album_name: *const c_char,
    pub album_artist: *const c_char,
    pub duration_ms: u32,
    pub disc_number: u32,
    pub track_number: u32,
}

pub type LsbPlaylistsCallback = extern "C" fn(
    context: *mut c_void,
    status: i32,
    message: *const c_char,
    playlists: *const LsbPlaylist,
    count: usize,
);
pub type LsbTracksCallback = extern "C" fn(
    context: *mut c_void,
    status: i32,
    message: *const c_char,
    tracks: *const LsbTrack,
    count: usize,
);

pub(crate) struct Context(pub *mut c_void);

// SAFETY: the header requires that `context` and the callback are safe to call
// from any thread. The bridge never reads through `context` itself.
unsafe impl Send for Context {}

pub(crate) fn c_text(text: &str) -> CString {
    CString::new(text.replace('\0', " ")).unwrap_or_default()
}

/// The status of a failed read: LSB_ERR_NOT_LOGGED_IN when the session dropped, so the
/// app logs in again, else LSB_ERR_READ (for example, a deleted playlist), so it does not.
pub(crate) fn read_error(dropped: bool) -> i32 {
    if dropped {
        LSB_ERR_NOT_LOGGED_IN
    } else {
        LSB_ERR_READ
    }
}

pub(crate) fn deliver_playlists(
    callback: LsbPlaylistsCallback,
    context: *mut c_void,
    result: Result<Vec<Playlist>, String>,
    dropped: bool,
) {
    match result {
        Ok(playlists) => {
            let texts: Vec<_> = playlists
                .iter()
                .map(|p| (c_text(&p.uri), c_text(&p.name)))
                .collect();
            let raw: Vec<_> = playlists
                .iter()
                .zip(&texts)
                .map(|(p, (uri, name))| LsbPlaylist {
                    uri: uri.as_ptr(),
                    name: name.as_ptr(),
                    track_count: p.track_count,
                })
                .collect();
            callback(context, LSB_OK, std::ptr::null(), raw.as_ptr(), raw.len());
        }
        Err(message) => {
            let message = c_text(&message);
            let status = read_error(dropped);
            callback(context, status, message.as_ptr(), std::ptr::null(), 0);
        }
    }
}

pub(crate) fn deliver_tracks(
    callback: LsbTracksCallback,
    context: *mut c_void,
    result: Result<Vec<Track>, String>,
    dropped: bool,
) {
    match result {
        Ok(tracks) => {
            let texts: Vec<_> = tracks
                .iter()
                .map(|t| {
                    let text = [
                        &t.uri,
                        &t.title,
                        &t.artist,
                        &t.cover_id,
                        &t.album_uri,
                        &t.album_name,
                        &t.album_artist,
                    ];
                    text.map(|t| c_text(t))
                })
                .collect();
            let raw: Vec<_> = tracks
                .iter()
                .zip(&texts)
                .map(
                    |(t, [uri, title, artist, cover_id, album_uri, album_name, album_artist])| {
                        LsbTrack {
                            uri: uri.as_ptr(),
                            title: title.as_ptr(),
                            artist: artist.as_ptr(),
                            cover_id: cover_id.as_ptr(),
                            album_uri: album_uri.as_ptr(),
                            album_name: album_name.as_ptr(),
                            album_artist: album_artist.as_ptr(),
                            duration_ms: t.duration_ms,
                            disc_number: t.disc_number,
                            track_number: t.track_number,
                        }
                    },
                )
                .collect();
            callback(context, LSB_OK, std::ptr::null(), raw.as_ptr(), raw.len());
        }
        Err(message) => {
            let message = c_text(&message);
            let status = read_error(dropped);
            callback(context, status, message.as_ptr(), std::ptr::null(), 0);
        }
    }
}

/// The current session. A session that dropped counts as no login.
pub(crate) unsafe fn session(bridge: *mut crate::LsbBridge) -> Result<Session, i32> {
    let mut session = None;
    let status = with_session(bridge, |s| session = Some(s.clone()));
    match session {
        Some(session) if session.is_invalid() => Err(LSB_ERR_NOT_LOGGED_IN),
        Some(session) => Ok(session),
        None => Err(status),
    }
}

/// Reads the user's playlists. The result comes once through `on_result`, on a
/// bridge thread. Needs a login.
///
/// # Safety
/// `bridge` must be valid. `context` and `on_result` must be safe to call from any thread.
#[no_mangle]
pub unsafe extern "C" fn lsb_read_playlists(
    bridge: *mut crate::LsbBridge,
    on_result: Option<LsbPlaylistsCallback>,
    context: *mut c_void,
) -> i32 {
    let Some(callback) = on_result else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let session = match session(bridge) {
        Ok(session) => session,
        Err(status) => return status,
    };
    let context = Context(context);
    (*bridge).runtime.spawn(async move {
        let context = context;
        let result = read_playlists(&session).await;
        deliver_playlists(callback, context.0, result, session.is_invalid());
    });
    LSB_OK
}

/// Reads all tracks of a playlist, or of Liked Songs when `playlist_uri` is NULL.
/// The result comes once through `on_result`, on a bridge thread. Needs a login.
///
/// # Safety
/// `bridge` must be valid. `playlist_uri` must be NULL or a NUL-terminated string.
/// `context` and `on_result` must be safe to call from any thread.
#[no_mangle]
pub unsafe extern "C" fn lsb_read_tracks(
    bridge: *mut crate::LsbBridge,
    playlist_uri: *const c_char,
    on_result: Option<LsbTracksCallback>,
    context: *mut c_void,
) -> i32 {
    let Some(callback) = on_result else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    let uri = match read_str(playlist_uri) {
        Some(uri) if uri.starts_with("spotify:playlist:") => Some(uri.to_owned()),
        Some(_) => return LSB_ERR_INVALID_ARGUMENT,
        None if !playlist_uri.is_null() => return LSB_ERR_INVALID_ARGUMENT,
        None => None,
    };
    let session = match session(bridge) {
        Ok(session) => session,
        Err(status) => return status,
    };
    let context = Context(context);
    (*bridge).runtime.spawn(async move {
        let context = context;
        let uri = uri.unwrap_or_else(|| liked_songs_uri(&session.username()));
        let result = read_tracks(&session, &uri).await;
        deliver_tracks(callback, context.0, result, session.is_invalid());
    });
    LSB_OK
}

/// Reads the details of one track, for a track that Spotify plays from outside the library.
/// The result comes once through `on_result`, on a bridge thread: one track, or none when
/// Spotify has no details for it. Needs a login.
///
/// # Safety
/// `bridge` must be valid. `track_uri` must be a NUL-terminated string.
/// `context` and `on_result` must be safe to call from any thread.
#[no_mangle]
pub unsafe extern "C" fn lsb_read_track(
    bridge: *mut crate::LsbBridge,
    track_uri: *const c_char,
    on_result: Option<LsbTracksCallback>,
    context: *mut c_void,
) -> i32 {
    let (Some(callback), Some(uri)) = (on_result, read_str(track_uri)) else {
        return LSB_ERR_INVALID_ARGUMENT;
    };
    if !valid_track_uri(uri) {
        return LSB_ERR_INVALID_ARGUMENT;
    }
    let uri = uri.to_owned();
    let session = match session(bridge) {
        Ok(session) => session,
        Err(status) => return status,
    };
    let context = Context(context);
    (*bridge).runtime.spawn(async move {
        let context = context;
        let result = read_metadata(&session, &[uri]).await;
        deliver_tracks(callback, context.0, result, session.is_invalid());
    });
    LSB_OK
}
