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
            Loading {
                play_request_id: id,
                track_id: t(),
                position_ms: 4,
            },
            expected(LSB_EVENT_PLAY_REQUEST, id, 4),
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
