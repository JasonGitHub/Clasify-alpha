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
        login_id: event.login_id,
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
        ("LSB_ERR_REFUSED", LSB_ERR_REFUSED as u32),
        ("LSB_COMMAND_PAUSE", LSB_COMMAND_PAUSE),
        ("LSB_COMMAND_RESUME", LSB_COMMAND_RESUME),
        ("LSB_COMMAND_NEXT", LSB_COMMAND_NEXT),
        ("LSB_COMMAND_PREV", LSB_COMMAND_PREV),
        ("LSB_OPTION_SHUFFLE", LSB_OPTION_SHUFFLE),
        ("LSB_OPTION_REPEAT_CONTEXT", LSB_OPTION_REPEAT_CONTEXT),
        ("LSB_OPTION_REPEAT_TRACK", LSB_OPTION_REPEAT_TRACK),
        ("LSB_EVENT_LOGGED_IN", LSB_EVENT_LOGGED_IN),
        ("LSB_EVENT_ERROR", LSB_EVENT_ERROR),
    ];
    for (name, value) in constants {
        let line = format!("#define {name} {value}\n");
        assert!(header.contains(&line), "header is missing: {line}");
    }
    // The C layout and signature that Swift reads. event_layout_matches_c checks the Rust side.
    for line in [
        "    uint64_t login_id;",
        "int32_t lsb_login(LsbBridge *bridge, const char *access_token, uint64_t login_id);",
        "int32_t lsb_session_status(LsbBridge *bridge);",
    ] {
        assert!(header.contains(line), "header is missing: {line}");
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
        assert_eq!(
            lsb_login(null, c"token".as_ptr(), 1),
            LSB_ERR_INVALID_ARGUMENT
        );
        let bridge = lsb_new(Some(record_event), context);
        assert!(!bridge.is_null());
        assert_eq!(
            lsb_login(bridge, std::ptr::null(), 1),
            LSB_ERR_INVALID_ARGUMENT
        );
        lsb_free(bridge);
        lsb_free(null);
    }
    assert!(lsb_new(None, context).is_null());
    assert!(recorder.events.lock().unwrap().is_empty());
}

#[test]
fn session_status_reports_a_dropped_session() {
    let recorder = Recorder::default();
    let context = &recorder as *const Recorder as *mut c_void;
    unsafe {
        assert_eq!(
            lsb_session_status(std::ptr::null_mut()),
            LSB_ERR_INVALID_ARGUMENT
        );
        let bridge = lsb_new(Some(record_event), context);
        assert_eq!(lsb_session_status(bridge), LSB_ERR_NOT_LOGGED_IN);
        // A session that is not connected is enough: the status reads only the flag.
        let session = {
            let _guard = (*bridge).runtime.enter();
            Session::new(SessionConfig::default(), None)
        };
        *(*bridge).connected.lock().unwrap() = Some(Connected {
            session: session.clone(),
        });
        assert_eq!(lsb_session_status(bridge), LSB_OK);
        {
            let _guard = (*bridge).runtime.enter();
            session.shutdown(); // what librespot does when the connection drops
        }
        assert_eq!(lsb_session_status(bridge), LSB_ERR_NOT_LOGGED_IN);
        lsb_free(bridge);
    }
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
        login_id: 7,
    };
    callbacks.emit(&logged_in);
    callbacks.emit(&Event::default());
    let events = recorder.events.lock().unwrap();
    assert_eq!(events[0].message.as_deref(), Some("ja son"));
    assert_eq!(events[0].login_id, 7);
    assert_eq!(events[1], Event::default());
}

#[test]
fn event_layout_matches_c() {
    // Size and offset that a C compiler gives LsbEvent on 64-bit targets.
    assert_eq!(std::mem::size_of::<LsbEvent>(), 24);
    assert_eq!(std::mem::offset_of!(LsbEvent, message), 8);
    assert_eq!(std::mem::offset_of!(LsbEvent, login_id), 16);
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
    assert_eq!(size_of::<LsbTrack>(), 72);
    let track = [
        offset_of!(LsbTrack, title),
        offset_of!(LsbTrack, artist),
        offset_of!(LsbTrack, cover_id),
        offset_of!(LsbTrack, album_uri),
        offset_of!(LsbTrack, album_name),
        offset_of!(LsbTrack, album_artist),
        offset_of!(LsbTrack, duration_ms),
        offset_of!(LsbTrack, disc_number),
        offset_of!(LsbTrack, track_number),
    ];
    assert_eq!(track, [8, 16, 24, 32, 40, 48, 56, 60, 64]);
}

mod library_tests {
    use super::*;
    use crate::library::*;
    use crate::oauth::TokenResult;
    use librespot_core::FileId;
    use librespot_protocol::context_page::ContextPage;
    use librespot_protocol::context_track::ContextTrack;
    use librespot_protocol::entity_extension_data::{
        EntityExtensionData, EntityExtensionDataHeader,
    };
    use librespot_protocol::extended_metadata::{
        BatchedExtensionResponse, EntityExtensionDataArray,
    };
    use librespot_protocol::extension_kind::ExtensionKind;
    use librespot_protocol::metadata::{
        image::Size, Album, Artist, Image, ImageGroup, Track as TrackMessage,
    };
    use librespot_protocol::playlist4_external::{
        Item, ListAttributes, ListItems, MetaItem, SelectedListContent,
    };
    use protobuf::well_known_types::any::Any;
    use protobuf::{EnumOrUnknown, Message, MessageField};
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
            ..Default::default()
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
    fn metadata_keeps_the_album_and_the_place_on_it() {
        let mut gid = vec![0u8; 16];
        gid[15] = 1; // base 62: 21 zeros, then "1"
        let message = TrackMessage {
            name: Some("Song".to_owned()),
            number: Some(7),
            disc_number: Some(2),
            album: MessageField::some(Album {
                gid: Some(gid),
                name: Some("Record".to_owned()),
                artist: ["X", "Y"]
                    .map(|a| Artist {
                        name: Some(a.to_owned()),
                        ..Default::default()
                    })
                    .to_vec(),
                ..Default::default()
            }),
            ..Default::default()
        };
        let mut data = details("spotify:track:9", 200, "", &[], 0);
        data.extension_data = MessageField::some(Any {
            value: message.write_to_bytes().unwrap(),
            ..Default::default()
        });
        let response = BatchedExtensionResponse {
            extended_metadata: vec![EntityExtensionDataArray {
                extension_data: vec![data],
                ..Default::default()
            }],
            ..Default::default()
        };
        let tracks = decode_metadata(&response, &["spotify:track:9".to_owned()]);
        let track = &tracks[0];
        assert_eq!(
            track.album_uri,
            format!("spotify:album:{}1", "0".repeat(21))
        );
        assert_eq!(track.album_name, "Record");
        assert_eq!(track.album_artist, "X, Y");
        assert_eq!((track.disc_number, track.track_number), (2, 7));
        // No album and no numbers: empty and 0, so the app can tell they are missing.
        let none = TrackMessage::default();
        assert_eq!(album_uri(&none), "");
        let mut short = none.clone();
        short.album = MessageField::some(Album {
            gid: Some(vec![1, 2]),
            ..Default::default()
        });
        assert_eq!(album_uri(&short), ""); // a gid that is not 16 bytes
    }

    fn image(id: u8, size: Option<Size>, width: i32) -> Image {
        Image {
            file_id: Some(vec![id; 20]),
            size: size.map(EnumOrUnknown::new),
            width: Some(width),
            ..Default::default()
        }
    }

    fn with_covers(group: Vec<Image>, cover: Vec<Image>) -> TrackMessage {
        TrackMessage {
            album: MessageField::some(Album {
                cover_group: MessageField::some(ImageGroup {
                    image: group,
                    ..Default::default()
                }),
                cover,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn cover_is_the_default_size_else_the_widest_under_640_else_the_narrowest() {
        let small = image(1, Some(Size::SMALL), 64);
        let default = image(2, Some(Size::DEFAULT), 300);
        let large = image(3, Some(Size::LARGE), 640);
        let track = with_covers(vec![small.clone(), large.clone(), default], vec![]);
        assert_eq!(cover_id(&track), "02".repeat(20));
        let track = with_covers(vec![large.clone(), small.clone()], vec![]);
        assert_eq!(cover_id(&track), "01".repeat(20));
        // An empty cover group falls back to the album's old cover list.
        let track = with_covers(vec![], vec![image(4, None, 300)]);
        assert_eq!(cover_id(&track), "04".repeat(20));
        // With only large images, the narrowest one is better than no cover.
        let xlarge = image(5, Some(Size::XLARGE), 1280);
        assert_eq!(
            cover_id(&with_covers(vec![xlarge, large], vec![])),
            "03".repeat(20)
        );
        assert_eq!(cover_id(&TrackMessage::default()), "");
    }

    #[test]
    fn cover_id_is_lowercase_hex_like_librespot_file_ids() {
        let bytes: Vec<u8> = (0xa0..0xb4).collect();
        let expected = "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3";
        assert_eq!(FileId::from(&bytes[..]).to_base16().unwrap(), expected);
        let image = Image {
            file_id: Some(bytes),
            size: Some(EnumOrUnknown::new(Size::DEFAULT)),
            ..Default::default()
        };
        assert_eq!(cover_id(&with_covers(vec![image], vec![])), expected);
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
        // The text that librespot-oauth makes from Spotify's answer to a revoked token.
        let revoked = "Failed to exchange code for access token \
            (Server returned error response: invalid_grant: Invalid refresh token)";
        assert_eq!(
            TokenResult::refreshed(Err(revoked.to_owned()), now).status,
            LSB_ERR_REFUSED
        );
        let offline = "Failed to exchange code for access token (Request failed)";
        assert_eq!(
            TokenResult::refreshed(Err(offline.to_owned()), now).status,
            LSB_ERR_OAUTH
        );
        // In a browser login, `invalid_grant` is about the code, not a saved token.
        assert_eq!(
            TokenResult::new(Err(revoked.to_owned()), now).status,
            LSB_ERR_OAUTH
        );
        assert_eq!(TokenResult::refreshed(Ok(token("r")), now).status, LSB_OK);
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
                    read(t.cover_id),
                    read(t.album_uri),
                    read(t.album_name),
                    read(t.album_artist),
                    t.duration_ms.to_string(),
                    t.disc_number.to_string(),
                    t.track_number.to_string(),
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
        deliver_playlists(record_playlists, context, Ok(vec![playlist]), false);
        deliver_playlists(record_playlists, context, Err("offline".to_owned()), false);
        let track = Track {
            uri: "spotify:track:1".to_owned(),
            title: "One".to_owned(),
            artist: "A".to_owned(),
            cover_id: "ab67".to_owned(),
            album_uri: "spotify:album:a".to_owned(),
            album_name: "Al\0bum".to_owned(),
            album_artist: "B".to_owned(),
            duration_ms: 1000,
            disc_number: 1,
            track_number: 3,
        };
        deliver_tracks(record_tracks, context, Ok(vec![track]), false);
        deliver_tracks(record_tracks, context, Err("offline".to_owned()), false);
        deliver_tracks(record_tracks, context, Err("dropped".to_owned()), true);
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
                    vec![row(&[
                        "spotify:track:1",
                        "One",
                        "A",
                        "ab67",
                        "spotify:album:a",
                        "Al bum",
                        "B",
                        "1000",
                        "1",
                        "3"
                    ])]
                ),
                (LSB_ERR_READ, Some("offline".to_owned()), vec![]),
                (LSB_ERR_NOT_LOGGED_IN, Some("dropped".to_owned()), vec![]),
            ]
        );
    }

    #[test]
    fn only_a_track_uri_reads_one_track() {
        assert!(valid_track_uri("spotify:track:4uLU6hMCjMI75M1A2tKUQC"));
        for bad in [
            "",
            "spotify:track:",
            "spotify:episode:4uLU6hMCjMI75M1A2tKUQC",
            "spotify:track:4uLU/../x",
            "spotify:track:4uLU 6h",
        ] {
            assert!(!valid_track_uri(bad), "{bad}");
        }
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
            let track = c"spotify:track:4uLU6hMCjMI75M1A2tKUQC";
            assert_eq!(
                lsb_read_track(bridge, track.as_ptr(), Some(record_tracks), ctx),
                LSB_ERR_NOT_LOGGED_IN
            );
            for bad in [none, playlist.as_ptr(), c"spotify:track:".as_ptr()] {
                assert_eq!(
                    lsb_read_track(bridge, bad, Some(record_tracks), ctx),
                    LSB_ERR_INVALID_ARGUMENT
                );
            }
            assert_eq!(
                lsb_read_track(bridge, track.as_ptr(), None, ctx),
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

    #[test]
    fn cluster_gives_the_player_state() {
        use librespot_protocol::player::{ContextPlayerOptions, PlayerState, ProvidedTrack};
        let state = |is_paused: bool, now_ms: i64| {
            let player = PlayerState {
                timestamp: 1_000_000,
                context_uri: PLAYLIST.to_owned(),
                track: protobuf::MessageField::some(ProvidedTrack {
                    uri: TRACK.to_owned(),
                    ..Default::default()
                }),
                position_as_of_timestamp: 10_000,
                duration: 200_000,
                is_playing: true,
                is_paused,
                options: protobuf::MessageField::some(ContextPlayerOptions {
                    shuffling_context: true,
                    repeating_track: true,
                    ..Default::default()
                }),
                ..Default::default()
            };
            let cluster = Cluster {
                active_device_id: "mac".to_owned(),
                player_state: protobuf::MessageField::some(player),
                ..Default::default()
            };
            spotify_state(&cluster, now_ms)
        };
        let playing = state(false, 1_002_500);
        let expected = SpotifyState {
            active_device_id: "mac".to_owned(),
            track_uri: TRACK.to_owned(),
            context_uri: PLAYLIST.to_owned(),
            position_ms: 12_500,
            duration_ms: 200_000,
            dealer_reconnects: 0,
            is_playing: true,
            is_paused: false,
            shuffle: true,
            repeat_context: false,
            repeat_track: true,
        };
        assert_eq!(playing, expected);
        assert_eq!(state(true, 1_002_500).position_ms, 10_000); // paused: no move
        assert_eq!(state(false, 9_000_000).position_ms, 200_000); // not past the end
        assert_eq!(state(false, 0).position_ms, 10_000); // clock behind Spotify's
        assert_eq!(
            spotify_state(&Cluster::default(), 5),
            SpotifyState::default()
        );
    }

    #[derive(Default)]
    struct States(Mutex<Vec<(String, u32, u32, bool)>>);

    extern "C" fn record_state(context: *mut c_void, state: *const LsbPlayerState) {
        let (states, state) = unsafe { (&*(context as *const States), &*state) };
        let track = unsafe { read_str(state.track_uri) }
            .unwrap_or("?")
            .to_owned();
        let entry = (
            track,
            state.position_ms,
            state.dealer_reconnects,
            state.repeat_track,
        );
        states.0.lock().unwrap().push(entry);
    }

    #[test]
    fn state_reaches_the_watch_callback() {
        let states = States::default();
        let context = &states as *const States as *mut c_void;
        let state = SpotifyState {
            track_uri: TRACK.to_owned(),
            position_ms: 7,
            dealer_reconnects: 2,
            repeat_track: true,
            ..Default::default()
        };
        let recorder = Recorder::default();
        let events = &recorder as *const Recorder as *mut c_void;
        let bridge = lsb_new(Some(record_event), events);
        unsafe {
            assert_eq!(
                lsb_connect_watch(bridge, Some(record_state), context),
                LSB_OK
            );
            deliver_state(&(*bridge).state_sink, &state);
            assert_eq!(lsb_connect_watch(bridge, None, context), LSB_OK);
            deliver_state(&(*bridge).state_sink, &state); // cleared: no call
            let null = std::ptr::null_mut();
            assert_eq!(
                lsb_connect_watch(null, Some(record_state), context),
                LSB_ERR_INVALID_ARGUMENT
            );
            lsb_free(bridge);
        }
        assert_eq!(
            *states.0.lock().unwrap(),
            vec![(TRACK.to_owned(), 7, 2, true)]
        );
    }

    /// A slow callback that marks when it ends.
    extern "C" fn slow_state(context: *mut c_void, _state: *const LsbPlayerState) {
        let done = unsafe { &*(context as *const std::sync::atomic::AtomicBool) };
        std::thread::sleep(std::time::Duration::from_millis(200));
        done.store(true, std::sync::atomic::Ordering::SeqCst);
    }

    #[test]
    fn clearing_the_watch_waits_for_a_running_callback() {
        use std::sync::atomic::{AtomicBool, Ordering};
        let done = Box::leak(Box::new(AtomicBool::new(false)));
        let context = done as *const AtomicBool as *mut c_void;
        let sink: SharedSink = SharedSink::default();
        set_sink(
            &sink,
            Some(StateSink {
                callback: slow_state,
                context,
            }),
        );
        let delivering = sink.clone();
        let thread = std::thread::spawn(move || {
            deliver_state(&delivering, &SpotifyState::default());
        });
        std::thread::sleep(std::time::Duration::from_millis(50));
        set_sink(&sink, None);
        // The clear returned, so the callback has ended.
        assert!(done.load(Ordering::SeqCst));
        thread.join().unwrap();
    }

    #[test]
    fn spotify_clock_adds_the_session_time_delta() {
        let local = spotify_now_ms(0);
        let ahead = spotify_now_ms(3);
        assert!((2_900..=3_500).contains(&(ahead - local)));
    }

    #[test]
    fn player_state_layout_matches_c() {
        use std::mem::{offset_of, size_of};
        assert_eq!(size_of::<LsbPlayerState>(), 48);
        let offsets = [
            offset_of!(LsbPlayerState, track_uri),
            offset_of!(LsbPlayerState, context_uri),
            offset_of!(LsbPlayerState, position_ms),
            offset_of!(LsbPlayerState, duration_ms),
            offset_of!(LsbPlayerState, dealer_reconnects),
            offset_of!(LsbPlayerState, is_playing),
            offset_of!(LsbPlayerState, repeat_track),
        ];
        assert_eq!(offsets, [8, 16, 24, 28, 32, 36, 40]);
    }

    #[test]
    fn set_option_checks_its_arguments() {
        let recorder = Recorder::default();
        let context = &recorder as *const Recorder as *mut c_void;
        let bridge = lsb_new(Some(record_event), context);
        let (app, ctx) = (c"app".as_ptr(), std::ptr::null_mut());
        let status = Some(record_status as LsbCommandCallback);
        unsafe {
            let shuffle =
                lsb_connect_set_option(bridge, app, LSB_OPTION_SHUFFLE, true, status, ctx);
            assert_eq!(shuffle, LSB_ERR_NOT_LOGGED_IN);
            let bad = lsb_connect_set_option(bridge, app, 3, true, status, ctx);
            assert_eq!(bad, LSB_ERR_INVALID_ARGUMENT);
            let none =
                lsb_connect_set_option(bridge, app, LSB_OPTION_REPEAT_TRACK, false, None, ctx);
            assert_eq!(none, LSB_ERR_INVALID_ARGUMENT);
            lsb_free(bridge);
        }
    }

    #[test]
    fn transfer_checks_its_arguments_and_keeps_the_play_state() {
        let recorder = Recorder::default();
        let context = &recorder as *const Recorder as *mut c_void;
        let bridge = lsb_new(Some(record_event), context);
        let (phone, app, ctx) = (c"phone-1".as_ptr(), c"app".as_ptr(), std::ptr::null_mut());
        let status = Some(record_status as LsbCommandCallback);
        unsafe {
            let ok = lsb_connect_transfer(bridge, phone, app, status, ctx);
            assert_eq!(ok, LSB_ERR_NOT_LOGGED_IN);
            let (none, slash) = (std::ptr::null(), c"a/b".as_ptr());
            let invalid = [
                lsb_connect_transfer(bridge, none, app, status, ctx),
                lsb_connect_transfer(bridge, phone, none, status, ctx),
                lsb_connect_transfer(bridge, slash, app, status, ctx),
                lsb_connect_transfer(bridge, phone, slash, status, ctx),
                lsb_connect_transfer(bridge, phone, app, None, ctx),
                lsb_connect_transfer(std::ptr::null_mut(), phone, app, status, ctx),
            ];
            assert_eq!(invalid, [LSB_ERR_INVALID_ARGUMENT; 6]);
            lsb_free(bridge);
        }
        let options = transfer_request().transfer_options;
        assert_eq!(options.restore_paused.as_deref(), Some("restore"));
        assert!(options.restore_position.is_none() && options.restore_track.is_none());
        assert!(options.retain_session.is_none());
        let transfer = Command::Transfer {
            from: "phone-1".to_owned(),
        };
        assert!(transfer.can_retry());
    }
}
