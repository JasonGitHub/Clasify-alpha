use super::*;

/// Test context: records the events that the callback receives.
#[derive(Default)]
struct Recorder {
    events: Mutex<Vec<Event>>,
}

extern "C" fn record_event(context: *mut c_void, event: *const LsbEvent) {
    let (recorder, event) = unsafe { (&*(context as *const Recorder), &*event) };
    let entry = Event {
        kind: event.kind,
        message: unsafe { read_str(event.message) }.map(str::to_owned),
    };
    recorder.events.lock().unwrap().push(entry);
}

#[test]
fn header_matches_rust() {
    let header = include_str!("../include/librespot_bridge.h");
    let constants = [
        ("LSB_OK", LSB_OK as u32),
        ("LSB_ERR_INVALID_ARGUMENT", LSB_ERR_INVALID_ARGUMENT as u32),
        ("LSB_ERR_NOT_LOGGED_IN", LSB_ERR_NOT_LOGGED_IN as u32),
        ("LSB_ERR_OAUTH", LSB_ERR_OAUTH as u32),
        ("LSB_ERR_READ", LSB_ERR_READ as u32),
        ("LSB_ERR_CONNECT", LSB_ERR_CONNECT as u32),
        ("LSB_COMMAND_PAUSE", LSB_COMMAND_PAUSE),
        ("LSB_COMMAND_RESUME", LSB_COMMAND_RESUME),
        ("LSB_COMMAND_NEXT", LSB_COMMAND_NEXT),
        ("LSB_COMMAND_PREV", LSB_COMMAND_PREV),
        ("LSB_EVENT_LOGGED_IN", LSB_EVENT_LOGGED_IN),
        ("LSB_EVENT_ERROR", LSB_EVENT_ERROR),
    ];
    for (name, value) in constants {
        let line = format!("#define {name} {value}\n");
        assert!(header.contains(&line), "header is missing: {line}");
    }
    for gone in [
        "lsb_load",
        "lsb_play",
        "LsbAudioCallback",
        "LSB_EVENT_PLAYING",
    ] {
        assert!(!header.contains(gone), "header still has {gone}");
    }
}

#[test]
fn bad_arguments_return_invalid_argument() {
    let recorder = Recorder::default();
    let context = &recorder as *const Recorder as *mut c_void;
    let null = std::ptr::null_mut();
    unsafe {
        assert_eq!(lsb_login(null, c"token".as_ptr()), LSB_ERR_INVALID_ARGUMENT);
        let bridge = lsb_new(Some(record_event), context);
        assert!(!bridge.is_null());
        assert_eq!(
            lsb_login(bridge, std::ptr::null()),
            LSB_ERR_INVALID_ARGUMENT
        );
        lsb_free(bridge);
        lsb_free(null);
    }
    assert!(lsb_new(None, context).is_null());
    assert!(recorder.events.lock().unwrap().is_empty());
}

#[test]
fn logout_ends_the_session() {
    let recorder = Recorder::default();
    let context = &recorder as *const Recorder as *mut c_void;
    unsafe {
        assert_eq!(lsb_logout(std::ptr::null_mut()), LSB_ERR_INVALID_ARGUMENT);
        let bridge = lsb_new(Some(record_event), context);
        // A logout without a session does nothing.
        assert_eq!(lsb_logout(bridge), LSB_OK);
        let before = (*bridge).latest_login.load(Ordering::SeqCst);
        assert_eq!(lsb_logout(bridge), LSB_OK);
        // A login that is still running can no longer publish its session.
        assert_eq!((*bridge).latest_login.load(Ordering::SeqCst), before + 1);
        assert!((*bridge).connected.lock().unwrap().is_none());
        lsb_free(bridge);
    }
    assert!(recorder.events.lock().unwrap().is_empty());
}

#[test]
fn emit_passes_the_event_to_the_callback() {
    let recorder = Recorder::default();
    let callbacks = Callbacks {
        on_event: record_event,
        context: &recorder as *const Recorder as *mut c_void,
    };
    let logged_in = Event {
        kind: LSB_EVENT_LOGGED_IN,
        message: Some("ja\0son".to_owned()),
    };
    callbacks.emit(&logged_in);
    callbacks.emit(&Event::default());
    let events = recorder.events.lock().unwrap();
    assert_eq!(events[0].message.as_deref(), Some("ja son"));
    assert_eq!(events[1], Event::default());
}

#[test]
fn event_layout_matches_c() {
    // Size and offset that a C compiler gives LsbEvent on 64-bit targets.
    assert_eq!(std::mem::size_of::<LsbEvent>(), 16);
    assert_eq!(std::mem::offset_of!(LsbEvent, message), 8);
}

#[test]
fn library_and_token_layouts_match_c() {
    // Sizes and offsets that a C compiler gives the header's structs on 64-bit targets.
    use std::mem::{offset_of, size_of};
    assert_eq!(size_of::<LsbToken>(), 32);
    let token = [
        offset_of!(LsbToken, expires_in_s),
        offset_of!(LsbToken, access_token),
        offset_of!(LsbToken, refresh_token),
        offset_of!(LsbToken, message),
    ];
    assert_eq!(token, [4, 8, 16, 24]);
    assert_eq!(size_of::<LsbPlaylist>(), 24);
    let playlist = [
        offset_of!(LsbPlaylist, name),
        offset_of!(LsbPlaylist, track_count),
    ];
    assert_eq!(playlist, [8, 16]);
    assert_eq!(size_of::<LsbTrack>(), 32);
    let track = [
        offset_of!(LsbTrack, title),
        offset_of!(LsbTrack, artist),
        offset_of!(LsbTrack, duration_ms),
    ];
    assert_eq!(track, [8, 16, 24]);
}

mod library_tests {
    use super::*;
    use crate::library::*;
    use crate::oauth::TokenResult;
    use librespot_protocol::context_page::ContextPage;
    use librespot_protocol::context_track::ContextTrack;
    use librespot_protocol::entity_extension_data::{
        EntityExtensionData, EntityExtensionDataHeader,
    };
    use librespot_protocol::extended_metadata::{
        BatchedExtensionResponse, EntityExtensionDataArray,
    };
    use librespot_protocol::extension_kind::ExtensionKind;
    use librespot_protocol::metadata::{Artist, Track as TrackMessage};
    use librespot_protocol::playlist4_external::{
        Item, ListAttributes, ListItems, MetaItem, SelectedListContent,
    };
    use protobuf::well_known_types::any::Any;
    use protobuf::{Message, MessageField};
    use std::collections::HashMap;
    use std::time::{Duration, Instant};

    fn block_on<F: std::future::Future>(future: F) -> F::Output {
        tokio::runtime::Runtime::new().unwrap().block_on(future)
    }

    fn item(uri: &str, name: &str, length: i32) -> (Item, MetaItem) {
        let item = Item {
            uri: Some(uri.to_owned()),
            ..Default::default()
        };
        let meta = MetaItem {
            attributes: MessageField::some(ListAttributes {
                name: Some(name.to_owned()),
                ..Default::default()
            }),
            length: Some(length),
            ..Default::default()
        };
        (item, meta)
    }

    #[test]
    fn rootlist_lists_playlists_and_flattens_folders() {
        let entries = [
            item("spotify:playlist:a", "Road trip", 12),
            item("spotify:start-group:f1:Folder", "", 0),
            item("spotify:playlist:b", "Focus", 3),
            item("spotify:end-group:f1", "", 0),
        ];
        let list = SelectedListContent {
            length: Some(10),
            contents: MessageField::some(ListItems {
                pos: Some(0),
                truncated: Some(false),
                items: entries.iter().map(|e| e.0.clone()).collect(),
                meta_items: entries.iter().map(|e| e.1.clone()).collect(),
                ..Default::default()
            }),
            ..Default::default()
        };
        let page = decode_rootlist(&list.write_to_bytes().unwrap()).unwrap();
        let playlist = |uri: &str, name: &str, track_count| Playlist {
            uri: uri.to_owned(),
            name: name.to_owned(),
            track_count,
        };
        assert_eq!(
            page,
            RootlistPage {
                playlists: vec![
                    playlist("spotify:playlist:a", "Road trip", 12),
                    playlist("spotify:playlist:b", "Focus", 3),
                ],
                items: 4,
                length: 10,
            }
        );
        assert!(decode_rootlist(b"not a protobuf").is_err());
    }

    fn page(tracks: &[&str], page_url: Option<&str>, next: Option<&str>) -> ContextPage {
        ContextPage {
            page_url: page_url.map(str::to_owned),
            next_page_url: next.map(str::to_owned),
            tracks: tracks
                .iter()
                .map(|uri| ContextTrack {
                    uri: Some(uri.to_string()),
                    ..Default::default()
                })
                .collect(),
            ..Default::default()
        }
    }

    /// Serves pages from memory and counts the page loads.
    struct FakePages {
        first: Vec<ContextPage>,
        pages: HashMap<&'static str, ContextPage>,
        loads: Mutex<Vec<String>>,
    }

    impl PageSource for FakePages {
        async fn context(&self, _uri: &str) -> Result<Vec<ContextPage>, String> {
            Ok(self.first.clone())
        }
        async fn page(&self, url: &str) -> Result<ContextPage, String> {
            self.loads.lock().unwrap().push(url.to_owned());
            self.pages.get(url).cloned().ok_or(format!("no page {url}"))
        }
    }

    fn fake(first: Vec<ContextPage>, pages: Vec<(&'static str, ContextPage)>) -> FakePages {
        FakePages {
            first,
            pages: pages.into_iter().collect(),
            loads: Mutex::default(),
        }
    }

    #[test]
    fn context_follows_every_page_in_order() {
        let source = fake(
            vec![
                page(
                    &["spotify:track:1", "spotify:episode:x"],
                    None,
                    Some("hm://p2"),
                ),
                page(&[], Some("hm://p4"), None),
            ],
            vec![
                ("hm://p2", page(&["spotify:track:2"], None, Some("hm://p3"))),
                (
                    "hm://p3",
                    page(&["spotify:local:a:b:c:1", "spotify:track:3"], None, None),
                ),
                ("hm://p4", page(&["spotify:track:4"], None, Some("hm://p5"))),
                (
                    "hm://p5",
                    page(&["spotify:track:5", "spotify:track:1"], None, Some("")),
                ),
            ],
        );
        let uris = block_on(context_track_uris(&source, "spotify:user:u:collection")).unwrap();
        let expected = ["1", "2", "3", "4", "5", "1"].map(|id| format!("spotify:track:{id}"));
        assert_eq!(uris, expected);
        assert_eq!(source.loads.lock().unwrap().len(), 4);
    }

    #[test]
    fn context_stops_a_page_chain_that_never_ends() {
        let source = fake(
            vec![page(&["spotify:track:1"], None, Some("hm://loop"))],
            vec![(
                "hm://loop",
                page(&["spotify:track:2"], None, Some("hm://loop")),
            )],
        );
        let error = block_on(context_track_uris(&source, "spotify:playlist:p")).unwrap_err();
        assert!(error.contains("more than 1000 pages"), "{error}");
    }

    #[test]
    fn context_reports_a_page_that_cannot_load() {
        let source = fake(
            vec![page(&["spotify:track:1"], None, Some("hm://gone"))],
            vec![],
        );
        let error = block_on(context_track_uris(&source, "spotify:playlist:p")).unwrap_err();
        assert_eq!(error, "no page hm://gone");
    }

    #[test]
    fn metadata_request_asks_for_track_details() {
        let uris = ["spotify:track:1".to_owned(), "spotify:track:2".to_owned()];
        let request = metadata_request(&uris);
        let asked: Vec<_> = request
            .entity_request
            .iter()
            .map(|r| &r.entity_uri)
            .collect();
        assert_eq!(asked, uris.iter().collect::<Vec<_>>());
        for entity in &request.entity_request {
            assert_eq!(entity.query.len(), 1);
            assert_eq!(
                entity.query[0].extension_kind.enum_value(),
                Ok(ExtensionKind::TRACK_V4)
            );
        }
    }

    fn details(
        uri: &str,
        status: i32,
        name: &str,
        artists: &[&str],
        ms: i32,
    ) -> EntityExtensionData {
        let track = TrackMessage {
            name: Some(name.to_owned()),
            artist: artists
                .iter()
                .map(|a| Artist {
                    name: Some(a.to_string()),
                    ..Default::default()
                })
                .collect(),
            duration: Some(ms),
            ..Default::default()
        };
        EntityExtensionData {
            header: MessageField::some(EntityExtensionDataHeader {
                status_code: status,
                ..Default::default()
            }),
            entity_uri: uri.to_owned(),
            extension_data: MessageField::some(Any {
                value: track.write_to_bytes().unwrap(),
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn metadata_keeps_request_order_and_drops_missing_tracks() {
        let response = BatchedExtensionResponse {
            extended_metadata: vec![EntityExtensionDataArray {
                extension_data: vec![
                    details("spotify:track:2", 200, "Two", &["B"], 2000),
                    details("spotify:track:3", 404, "Three", &["C"], 3000),
                    details("spotify:track:1", 200, "One", &["A", "A2"], 1000),
                ],
                ..Default::default()
            }],
            ..Default::default()
        };
        let uris = ["1", "2", "3", "4"].map(|id| format!("spotify:track:{id}"));
        let track = |id: &str, title: &str, artist: &str, duration_ms| Track {
            uri: format!("spotify:track:{id}"),
            title: title.to_owned(),
            artist: artist.to_owned(),
            duration_ms,
        };
        assert_eq!(
            decode_metadata(&response, &uris),
            vec![
                track("1", "One", "A, A2", 1000),
                track("2", "Two", "B", 2000)
            ]
        );
    }

    #[test]
    fn liked_songs_uses_the_collection_context() {
        assert_eq!(liked_songs_uri("31sq"), "spotify:user:31sq:collection");
    }

    #[test]
    fn oauth_asks_only_for_read_scopes() {
        for scope in OAUTH_SCOPES {
            assert!(!scope.contains("modify"), "{scope}");
        }
        assert!(OAUTH_SCOPES.contains(&"user-library-read"));
        assert!(OAUTH_SCOPES.contains(&"playlist-read-private"));
    }

    #[test]
    fn token_result_maps_success_and_failure() {
        let now = Instant::now();
        let token = |refresh: &str| librespot_oauth::OAuthToken {
            access_token: "access".to_owned(),
            refresh_token: refresh.to_owned(),
            expires_at: now + Duration::from_secs(3600),
            token_type: "Bearer".to_owned(),
            scopes: vec![],
        };
        let ok = TokenResult::new(Ok(token("refresh")), now);
        assert_eq!(ok.status, LSB_OK);
        assert_eq!(ok.expires_in_s, 3600);
        assert_eq!(ok.access_token.as_deref(), Some("access"));
        assert_eq!(ok.refresh_token.as_deref(), Some("refresh"));
        assert_eq!(TokenResult::new(Ok(token("")), now).refresh_token, None);
        let failed = TokenResult::new(Err("denied".to_owned()), now);
        assert_eq!(failed.status, LSB_ERR_OAUTH);
        assert_eq!((failed.access_token, failed.refresh_token), (None, None));
        assert_eq!(failed.message.as_deref(), Some("denied"));
    }

    type Delivered = Mutex<Vec<(i32, Option<String>, Vec<Vec<String>>)>>;

    extern "C" fn record_playlists(
        context: *mut c_void,
        status: i32,
        message: *const c_char,
        items: *const LsbPlaylist,
        count: usize,
    ) {
        let delivered = unsafe { &*(context as *const Delivered) };
        let read = |t| unsafe { read_str(t) }.unwrap_or("").to_owned();
        let items = if count == 0 {
            &[][..]
        } else {
            unsafe { std::slice::from_raw_parts(items, count) }
        };
        let rows = items
            .iter()
            .map(|p| vec![read(p.uri), read(p.name), p.track_count.to_string()])
            .collect();
        let message = unsafe { read_str(message) }.map(str::to_owned);
        delivered.lock().unwrap().push((status, message, rows));
    }

    extern "C" fn record_tracks(
        context: *mut c_void,
        status: i32,
        message: *const c_char,
        items: *const LsbTrack,
        count: usize,
    ) {
        let delivered = unsafe { &*(context as *const Delivered) };
        let read = |t| unsafe { read_str(t) }.unwrap_or("").to_owned();
        let items = if count == 0 {
            &[][..]
        } else {
            unsafe { std::slice::from_raw_parts(items, count) }
        };
        let rows = items
            .iter()
            .map(|t| {
                vec![
                    read(t.uri),
                    read(t.title),
                    read(t.artist),
                    t.duration_ms.to_string(),
                ]
            })
            .collect();
        let message = unsafe { read_str(message) }.map(str::to_owned);
        delivered.lock().unwrap().push((status, message, rows));
    }

    #[test]
    fn results_cross_the_ffi() {
        let delivered = Delivered::default();
        let context = &delivered as *const Delivered as *mut c_void;
        let playlist = Playlist {
            uri: "spotify:playlist:a".to_owned(),
            name: "Mix\0tape".to_owned(),
            track_count: 7,
        };
        deliver_playlists(record_playlists, context, Ok(vec![playlist]));
        deliver_playlists(record_playlists, context, Err("offline".to_owned()));
        let track = Track {
            uri: "spotify:track:1".to_owned(),
            title: "One".to_owned(),
            artist: "A".to_owned(),
            duration_ms: 1000,
        };
        deliver_tracks(record_tracks, context, Ok(vec![track]));
        deliver_tracks(record_tracks, context, Err("offline".to_owned()));
        let row = |items: &[&str]| items.iter().map(|i| i.to_string()).collect::<Vec<_>>();
        assert_eq!(
            *delivered.lock().unwrap(),
            vec![
                (
                    LSB_OK,
                    None,
                    vec![row(&["spotify:playlist:a", "Mix tape", "7"])]
                ),
                (LSB_ERR_READ, Some("offline".to_owned()), vec![]),
                (
                    LSB_OK,
                    None,
                    vec![row(&["spotify:track:1", "One", "A", "1000"])]
                ),
                (LSB_ERR_READ, Some("offline".to_owned()), vec![]),
            ]
        );
    }

    extern "C" fn ignore_token(_: *mut c_void, _: *const LsbToken) {}

    #[test]
    fn library_and_oauth_check_their_arguments() {
        let recorder = Recorder::default();
        let context = &recorder as *const Recorder as *mut c_void;
        let bridge = lsb_new(Some(record_event), context);
        let ctx = std::ptr::null_mut();
        let album = c"spotify:album:1";
        let playlist = c"spotify:playlist:1";
        unsafe {
            assert_eq!(
                lsb_read_playlists(bridge, Some(record_playlists), ctx),
                LSB_ERR_NOT_LOGGED_IN
            );
            assert_eq!(
                lsb_read_playlists(bridge, None, ctx),
                LSB_ERR_INVALID_ARGUMENT
            );
            let none = std::ptr::null();
            assert_eq!(
                lsb_read_tracks(bridge, none, Some(record_tracks), ctx),
                LSB_ERR_NOT_LOGGED_IN
            );
            let uri = playlist.as_ptr();
            assert_eq!(
                lsb_read_tracks(bridge, uri, Some(record_tracks), ctx),
                LSB_ERR_NOT_LOGGED_IN
            );
            let uri = album.as_ptr();
            assert_eq!(
                lsb_read_tracks(bridge, uri, Some(record_tracks), ctx),
                LSB_ERR_INVALID_ARGUMENT
            );
            assert_eq!(
                lsb_read_tracks(bridge, none, None, ctx),
                LSB_ERR_INVALID_ARGUMENT
            );
            let null = std::ptr::null_mut();
            assert_eq!(
                lsb_read_playlists(null, Some(record_playlists), ctx),
                LSB_ERR_INVALID_ARGUMENT
            );
            assert_eq!(
                lsb_oauth_refresh(none, Some(ignore_token), ctx),
                LSB_ERR_INVALID_ARGUMENT
            );
            assert_eq!(
                lsb_oauth_refresh(c"".as_ptr(), Some(ignore_token), ctx),
                LSB_ERR_INVALID_ARGUMENT
            );
            assert_eq!(
                lsb_oauth_refresh(c"r".as_ptr(), None, ctx),
                LSB_ERR_INVALID_ARGUMENT
            );
            lsb_free(bridge);
        }
        assert_eq!(lsb_oauth_login(None, ctx), LSB_ERR_INVALID_ARGUMENT);
        assert!(recorder.events.lock().unwrap().is_empty());
    }

    use crate::oauth::{stop_login, Login, LoginState, Phase};

    fn free_address() -> std::net::SocketAddr {
        // Bind, read the port, and let it go.
        std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
    }

    #[test]
    fn stop_login_waits_for_a_listener_that_binds_late() {
        let address = free_address();
        let handle = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(100));
            let listener = std::net::TcpListener::bind(address).unwrap();
            let (stream, _) = listener.accept().unwrap();
            let mut line = String::new();
            std::io::BufRead::read_line(&mut std::io::BufReader::new(stream), &mut line).unwrap();
            assert!(line.starts_with("GET /login?error=cancelled "), "{line}");
        });
        let state = LoginState::new();
        stop_login(
            Login {
                handle,
                state: state.clone(),
            },
            address,
        );
        assert_eq!(state.phase(), Phase::Cancelled);
        // The port is free again.
        std::net::TcpListener::bind(address).unwrap();
    }

    #[test]
    fn cancel_without_a_login_does_nothing() {
        assert_eq!(lsb_oauth_cancel(), LSB_OK);
    }

    #[test]
    fn stop_login_from_the_login_thread_returns_at_once() {
        let address = free_address();
        let (send_login, get_login) = std::sync::mpsc::channel::<Login>();
        let (send_done, done) = std::sync::mpsc::channel();
        let handle = std::thread::spawn(move || {
            // As a token callback that calls lsb_oauth_cancel or lsb_oauth_login.
            stop_login(get_login.recv().unwrap(), address);
            send_done.send(()).unwrap();
        });
        // The thread gets a handle to itself. Keep none here: it is detached.
        let state = LoginState::new();
        send_login.send(Login { handle, state }).unwrap();
        done.recv_timeout(Duration::from_secs(5))
            .expect("stop_login must not wait for its own thread");
    }

    #[test]
    fn stop_login_sends_nothing_once_the_login_stops_listening() {
        let address = free_address();
        let state = LoginState::new();
        let thread_state = state.clone();
        let handle = std::thread::spawn(move || {
            // The old login: it got the browser's code, so it no longer listens.
            let _ = thread_state.finish(Err("code consumed".to_owned()));
            // Its callback starts a new login on the same port and runs for a while.
            let new = std::net::TcpListener::bind(address).unwrap();
            new.set_nonblocking(true).unwrap();
            let end = Instant::now() + Duration::from_millis(300);
            while Instant::now() < end {
                assert!(new.accept().is_err(), "the new login got a stop request");
                std::thread::sleep(Duration::from_millis(10));
            }
        });
        // Let the old login stop listening first, as when the browser already sent the code.
        while state.is_listening() {
            std::thread::sleep(Duration::from_millis(5));
        }
        stop_login(Login { handle, state }, address);
    }

    fn token() -> librespot_oauth::OAuthToken {
        librespot_oauth::OAuthToken {
            access_token: "access".to_owned(),
            refresh_token: "refresh".to_owned(),
            expires_at: Instant::now(),
            token_type: "Bearer".to_owned(),
            scopes: vec![],
        }
    }

    #[test]
    fn a_login_cancelled_before_it_finishes_sends_no_token() {
        let state = LoginState::new();
        assert!(state.is_listening());
        state.cancel();
        let result = state.finish(Ok(token()));
        assert_eq!(result.unwrap_err(), "login cancelled");
        assert!(!state.is_listening());
        assert_eq!(state.phase(), Phase::Cancelled);
    }

    #[test]
    fn a_cancel_after_the_result_is_fixed_changes_nothing() {
        let state = LoginState::new();
        assert!(state.finish(Ok(token())).is_ok());
        state.cancel();
        assert_eq!(state.phase(), Phase::Decided);
        let failed = LoginState::new().finish(Err("denied".to_owned()));
        assert_eq!(failed.unwrap_err(), "denied");
    }
}

mod connect_tests {
    use super::*;
    use crate::connect::*;
    use librespot_protocol::connect::{Cluster, DeviceInfo};
    use librespot_protocol::devices::DeviceType;

    const PLAYLIST: &str = "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M";
    const TRACK: &str = "spotify:track:4uLU6hMCjMI75M1A2tKUQC";

    fn body(command: Command) -> (String, String, String) {
        let (method, path, body) = request(&command, "me", "app", "c1");
        (method.to_string(), path, body)
    }

    #[test]
    fn commands_build_spotify_requests() {
        let command = "/connect-state/v1/player/command/from/me/to/app";
        let simple = |endpoint: &str| {
            let body = format!(
                r#"{{"command":{{"logging_params":{{"command_id":"c1"}},"endpoint":"{endpoint}"}}}}"#
            );
            ("POST".to_owned(), command.to_owned(), body)
        };
        assert_eq!(body(Command::Pause), simple("pause"));
        assert_eq!(body(Command::Resume), simple("resume"));
        assert_eq!(body(Command::Next), simple("skip_next"));
        assert_eq!(body(Command::Prev), simple("skip_prev"));
        let seek = r#"{"command":{"value":61000,"logging_params":{"command_id":"c1"},"endpoint":"seek_to"}}"#;
        assert_eq!(body(Command::Seek(61000)).2, seek);
        let volume = body(Command::Volume(32768));
        let path = "/connect-state/v1/connect/volume/from/me/to/app";
        assert_eq!(
            volume,
            (
                "PUT".to_owned(),
                path.to_owned(),
                r#"{"volume":32768}"#.to_owned()
            )
        );
    }

    #[test]
    fn play_sends_the_context_and_the_start_track() {
        let play = |track: Option<&str>| {
            let context = PLAYLIST.to_owned();
            let track = track.map(str::to_owned);
            body(Command::Play { context, track }).2
        };
        let expected = |skip_to: &str| {
            format!(
                concat!(
                    r#"{{"command":{{"context":{{"uri":"{0}","url":"context://{0}","metadata":{{}}}},"#,
                    r#""play_origin":{{"feature_identifier":"harmony","feature_version":"4.11.0"}},"#,
                    r#""options":{{"license":"on-demand","skip_to":{1},"player_options_override":{{}}}},"#,
                    r#""logging_params":{{"command_id":"c1"}},"endpoint":"play"}}}}"#
                ),
                PLAYLIST, skip_to
            )
        };
        assert_eq!(play(None), expected("{}"));
        assert_eq!(
            play(Some(TRACK)),
            expected(&format!(r#"{{"track_uri":"{TRACK}"}}"#))
        );
        let liked = Command::Play {
            context: "spotify:user:a\"b:collection".to_owned(),
            track: None,
        };
        assert!(body(liked)
            .2
            .contains(r#""uri":"spotify:user:a\"b:collection""#));
    }

    #[test]
    fn only_safe_ids_and_uris_pass() {
        assert!(valid_device_id("a1B2-c_3"));
        for bad in ["", "a/b", "a?b", "../x", "a b", &"a".repeat(129)] {
            assert!(!valid_device_id(bad), "{bad}");
        }
        assert!(valid_context(PLAYLIST));
        assert!(valid_context("spotify:user:jason.w:collection"));
        for bad in [
            "spotify:playlist:",
            "spotify:playlist:a/b",
            "spotify:album:1",
            "spotify:user::collection",
            "spotify:user:a:b:collection",
            "spotify:user:a\nb:collection",
            TRACK,
        ] {
            assert!(!valid_context(bad), "{bad}");
        }
        assert!(valid_track(TRACK));
        assert!(!valid_track("spotify:track:a\"b") && !valid_track(PLAYLIST));
    }

    #[test]
    fn devices_leave_out_this_device() {
        let device = |id: &str, name: &str| DeviceInfo {
            device_id: id.to_owned(),
            name: name.to_owned(),
            device_type: DeviceType::COMPUTER.into(),
            device_software_version: "osx".to_owned(),
            ..Default::default()
        };
        let mut cluster = Cluster {
            active_device_id: "mac".to_owned(),
            ..Default::default()
        };
        for (id, name) in [("me", "Clasify"), ("phone", "Phone"), ("mac", "Mac")] {
            cluster.device.insert(id.to_owned(), device(id, name));
        }
        let found = devices(&cluster, "me");
        let names: Vec<_> = found.iter().map(|d| (d.id.as_str(), d.is_active)).collect();
        assert_eq!(names, [("mac", true), ("phone", false)]);
        assert_eq!(found[0].device_type, "COMPUTER");
        assert_eq!(found[0].software, "osx");
    }

    type Row = (i32, Option<String>, Vec<[String; 5]>);

    #[derive(Default)]
    struct Got(Mutex<Vec<Row>>);

    extern "C" fn record_devices(
        context: *mut c_void,
        status: i32,
        message: *const c_char,
        devices: *const LsbDevice,
        count: usize,
    ) {
        let got = unsafe { &*(context as *const Got) };
        let read = |text| unsafe { read_str(text) }.unwrap_or("").to_owned();
        let rows = if devices.is_null() {
            vec![]
        } else {
            unsafe { std::slice::from_raw_parts(devices, count) }
                .iter()
                .map(|d| {
                    let active = d.is_active.to_string();
                    [
                        read(d.id),
                        read(d.name),
                        read(d.device_type),
                        read(d.software),
                        active,
                    ]
                })
                .collect()
        };
        let message = unsafe { read_str(message) }.map(str::to_owned);
        got.0.lock().unwrap().push((status, message, rows));
    }

    extern "C" fn record_status(context: *mut c_void, status: i32, message: *const c_char) {
        let got = unsafe { &*(context as *const Got) };
        let message = unsafe { read_str(message) }.map(str::to_owned);
        got.0.lock().unwrap().push((status, message, vec![]));
    }

    #[test]
    fn connect_results_cross_the_ffi() {
        let got = Got::default();
        let context = &got as *const Got as *mut c_void;
        let device = ConnectDevice {
            id: "mac".to_owned(),
            name: "Mac\0Book".to_owned(),
            device_type: "COMPUTER".to_owned(),
            software: "osx".to_owned(),
            is_active: true,
        };
        deliver_devices(record_devices, context, Ok(vec![device]));
        deliver_devices(record_devices, context, Err("offline".to_owned()));
        deliver_status(record_status, context, Ok(()));
        deliver_status(record_status, context, Err("refused".to_owned()));
        let row = ["mac", "Mac Book", "COMPUTER", "osx", "true"].map(str::to_owned);
        let failed = |m: &str| (LSB_ERR_CONNECT, Some(m.to_owned()), vec![]);
        assert_eq!(
            *got.0.lock().unwrap(),
            vec![
                (LSB_OK, None, vec![row]),
                failed("offline"),
                (LSB_OK, None, vec![]),
                failed("refused"),
            ]
        );
    }

    #[test]
    fn device_layout_matches_c() {
        use std::mem::{offset_of, size_of};
        assert_eq!(size_of::<LsbDevice>(), 40);
        let offsets = [
            offset_of!(LsbDevice, name),
            offset_of!(LsbDevice, device_type),
            offset_of!(LsbDevice, software),
            offset_of!(LsbDevice, is_active),
        ];
        assert_eq!(offsets, [8, 16, 24, 32]);
    }

    #[test]
    fn connect_calls_check_arguments_and_login() {
        let recorder = Recorder::default();
        let context = &recorder as *const Recorder as *mut c_void;
        let bridge = lsb_new(Some(record_event), context);
        let (ctx, none) = (std::ptr::null_mut(), std::ptr::null());
        let (app, playlist, track) = (
            c"app".as_ptr(),
            c"spotify:playlist:1".as_ptr(),
            c"spotify:track:1".as_ptr(),
        );
        let status = Some(record_status as LsbCommandCallback);
        unsafe {
            let not_logged_in = [
                lsb_connect_devices(bridge, Some(record_devices), ctx),
                lsb_connect_play(bridge, app, playlist, none, status, ctx),
                lsb_connect_play(bridge, app, playlist, track, status, ctx),
                lsb_connect_command(bridge, app, LSB_COMMAND_PREV, status, ctx),
                lsb_connect_seek(bridge, app, 1000, status, ctx),
                lsb_connect_volume(bridge, app, 100, status, ctx),
            ];
            assert_eq!(not_logged_in, [LSB_ERR_NOT_LOGGED_IN; 6]);
            let invalid = [
                lsb_connect_devices(bridge, None, ctx),
                lsb_connect_devices(std::ptr::null_mut(), Some(record_devices), ctx),
                lsb_connect_play(bridge, c"a/b".as_ptr(), playlist, none, status, ctx),
                lsb_connect_play(bridge, none, playlist, none, status, ctx),
                lsb_connect_play(bridge, app, none, none, status, ctx),
                lsb_connect_play(bridge, app, track, none, status, ctx),
                lsb_connect_play(bridge, app, playlist, playlist, status, ctx),
                lsb_connect_play(bridge, app, playlist, none, None, ctx),
                lsb_connect_command(bridge, app, 4, status, ctx),
                lsb_connect_command(bridge, app, LSB_COMMAND_PAUSE, None, ctx),
                lsb_connect_seek(std::ptr::null_mut(), app, 0, status, ctx),
                lsb_connect_volume(bridge, c"".as_ptr(), 0, status, ctx),
            ];
            assert_eq!(invalid, [LSB_ERR_INVALID_ARGUMENT; 12]);
            lsb_free(bridge);
        }
        assert!(recorder.events.lock().unwrap().is_empty());
    }
}
