use super::*;

/// Test context: records what the callbacks receive.
#[derive(Default)]
struct Recorder {
    events: Mutex<Vec<Event>>,
    samples: Mutex<Vec<f32>>,
}

extern "C" fn record_event(context: *mut c_void, event: *const LsbEvent) {
    let (recorder, event) = unsafe { (&*(context as *const Recorder), &*event) };
    let read = |text| unsafe { read_str(text) }.map(str::to_owned);
    let entry = Event {
        kind: event.kind,
        position_ms: event.position_ms,
        play_request_id: event.play_request_id,
        volume: event.volume,
        track_uri: read(event.track_uri),
        message: read(event.message),
    };
    recorder.events.lock().unwrap().push(entry);
}

extern "C" fn record_audio(context: *mut c_void, samples: *const f32, count: usize) {
    let recorder = unsafe { &*(context as *const Recorder) };
    let samples = unsafe { std::slice::from_raw_parts(samples, count) };
    recorder.samples.lock().unwrap().extend_from_slice(samples);
}

fn callbacks(recorder: &Recorder) -> Callbacks {
    let context = recorder as *const Recorder as *mut c_void;
    Callbacks {
        on_event: record_event,
        on_audio: record_audio,
        context,
    }
}

const URI: &str = "spotify:track:4uLU6hMCjMI75M1A2tKUQC";

fn track() -> SpotifyUri {
    SpotifyUri::from_uri(URI).unwrap()
}

/// The bridge event expected for a track event.
fn expected(kind: u32, play_request_id: u64, position_ms: u32) -> Option<Event> {
    let track_uri = Some(URI.to_owned());
    Some(Event {
        kind,
        play_request_id,
        position_ms,
        track_uri,
        ..Event::default()
    })
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
        ("LSB_EVENT_LOGGED_IN", LSB_EVENT_LOGGED_IN),
        ("LSB_EVENT_PLAYING", LSB_EVENT_PLAYING),
        ("LSB_EVENT_PAUSED", LSB_EVENT_PAUSED),
        ("LSB_EVENT_POSITION", LSB_EVENT_POSITION),
        ("LSB_EVENT_TRACK_ENDED", LSB_EVENT_TRACK_ENDED),
        ("LSB_EVENT_UNAVAILABLE", LSB_EVENT_UNAVAILABLE),
        ("LSB_EVENT_VOLUME", LSB_EVENT_VOLUME),
        ("LSB_EVENT_ERROR", LSB_EVENT_ERROR),
        ("LSB_EVENT_PLAY_REQUEST", LSB_EVENT_PLAY_REQUEST),
    ];
    for (name, value) in constants {
        let line = format!("#define {name} {value}\n");
        assert!(header.contains(&line), "header is missing: {line}");
    }
}

#[test]
fn playback_before_login_returns_not_logged_in() {
    let recorder = Recorder::default();
    let context = &recorder as *const Recorder as *mut c_void;
    let bridge = lsb_new(Some(record_event), Some(record_audio), context);
    assert!(!bridge.is_null());
    let uri = c"spotify:track:4uLU6hMCjMI75M1A2tKUQC";
    unsafe {
        assert_eq!(
            lsb_load(bridge, uri.as_ptr(), true, 0),
            LSB_ERR_NOT_LOGGED_IN
        );
        assert_eq!(lsb_play(bridge), LSB_ERR_NOT_LOGGED_IN);
        assert_eq!(lsb_pause(bridge), LSB_ERR_NOT_LOGGED_IN);
        assert_eq!(lsb_seek(bridge, 1000), LSB_ERR_NOT_LOGGED_IN);
        assert_eq!(lsb_set_volume(bridge, 100), LSB_ERR_NOT_LOGGED_IN);
        lsb_free(bridge);
    }
    assert!(recorder.events.lock().unwrap().is_empty());
}

#[test]
fn bad_arguments_return_invalid_argument() {
    let recorder = Recorder::default();
    let context = &recorder as *const Recorder as *mut c_void;
    let null = std::ptr::null_mut();
    unsafe {
        assert_eq!(lsb_play(null), LSB_ERR_INVALID_ARGUMENT);
        assert_eq!(lsb_login(null, c"token".as_ptr()), LSB_ERR_INVALID_ARGUMENT);
        let bridge = lsb_new(Some(record_event), Some(record_audio), context);
        assert_eq!(
            lsb_login(bridge, std::ptr::null()),
            LSB_ERR_INVALID_ARGUMENT
        );
        assert_eq!(
            lsb_load(bridge, std::ptr::null(), true, 0),
            LSB_ERR_INVALID_ARGUMENT
        );
        assert_eq!(
            lsb_load(bridge, c"not a uri".as_ptr(), true, 0),
            LSB_ERR_INVALID_ARGUMENT
        );
        lsb_free(bridge);
        lsb_free(null);
    }
    assert!(lsb_new(None, Some(record_audio), context).is_null());
    assert!(lsb_new(Some(record_event), None, context).is_null());
}

#[test]
fn player_events_map_to_bridge_events() {
    use PlayerEvent::*;
    let (id, t) = (7, track);
    let volume = Some(Event {
        volume: 300,
        ..Event::new(LSB_EVENT_VOLUME)
    });
    let cases = [
        (
            PlayRequestIdChanged {
                play_request_id: id,
            },
            Some(Event {
                play_request_id: id,
                ..Event::new(LSB_EVENT_PLAY_REQUEST)
            }),
        ),
        (
            Playing {
                play_request_id: id,
                track_id: t(),
                position_ms: 5,
            },
            expected(LSB_EVENT_PLAYING, id, 5),
        ),
        (
            Paused {
                play_request_id: id,
                track_id: t(),
                position_ms: 6,
            },
            expected(LSB_EVENT_PAUSED, id, 6),
        ),
        (
            PositionChanged {
                play_request_id: id,
                track_id: t(),
                position_ms: 7,
            },
            expected(LSB_EVENT_POSITION, id, 7),
        ),
        (
            Seeked {
                play_request_id: id,
                track_id: t(),
                position_ms: 8,
            },
            expected(LSB_EVENT_POSITION, id, 8),
        ),
        (
            EndOfTrack {
                play_request_id: id,
                track_id: t(),
            },
            expected(LSB_EVENT_TRACK_ENDED, id, 0),
        ),
        (
            Unavailable {
                play_request_id: id,
                track_id: t(),
            },
            expected(LSB_EVENT_UNAVAILABLE, id, 0),
        ),
        (VolumeChanged { volume: 300 }, volume),
        (Preloading { track_id: t() }, None),
    ];
    for (event, expected) in cases {
        assert_eq!(map_event(&event), expected, "{event:?}");
    }
}

#[test]
fn emit_passes_all_fields_to_callback() {
    let recorder = Recorder::default();
    let callbacks = callbacks(&recorder);
    let track_event = Event {
        volume: 9,
        ..expected(LSB_EVENT_PAUSED, 42, 1234).unwrap()
    };
    callbacks.emit(&Event::error("bad\0token"));
    callbacks.emit(&Event::new(LSB_EVENT_LOGGED_IN));
    callbacks.emit(&track_event);
    let events = recorder.events.lock().unwrap();
    assert_eq!(events[0], Event::error("bad token"));
    assert_eq!(events[1], Event::new(LSB_EVENT_LOGGED_IN));
    assert_eq!(events[2], track_event);
}

#[test]
fn sink_forwards_samples_as_f32() {
    let recorder = Recorder::default();
    let mut sink = CallbackSink(callbacks(&recorder));
    let mut converter = Converter::new(None);
    let packet = AudioPacket::Samples(vec![0.5, -0.25, 1.0]);
    sink.write(packet, &mut converter).unwrap();
    assert_eq!(*recorder.samples.lock().unwrap(), vec![0.5f32, -0.25, 1.0]);
}

#[test]
fn event_layout_matches_c() {
    // Sizes and offsets that a C compiler gives the header's LsbEvent on 64-bit targets.
    use std::mem::{offset_of, size_of};
    assert_eq!(size_of::<LsbEvent>(), 40);
    let offsets = [
        offset_of!(LsbEvent, position_ms),
        offset_of!(LsbEvent, play_request_id),
        offset_of!(LsbEvent, volume),
        offset_of!(LsbEvent, track_uri),
        offset_of!(LsbEvent, message),
    ];
    assert_eq!(offsets, [4, 8, 16, 24, 32]);
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

#[test]
fn repeated_play_request_is_sent_once() {
    let request = |id| Event {
        play_request_id: id,
        ..Event::new(LSB_EVENT_PLAY_REQUEST)
    };
    let mut last = None;
    assert!(is_new(&request(1), &mut last));
    assert!(!is_new(&request(1), &mut last));
    assert!(is_new(&Event::new(LSB_EVENT_PLAYING), &mut last));
    assert!(!is_new(&request(1), &mut last));
    assert!(is_new(&request(2), &mut last));
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
        let bridge = lsb_new(Some(record_event), Some(record_audio), context);
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
}
