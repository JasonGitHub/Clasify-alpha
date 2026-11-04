use super::*;

/// kind, position_ms, volume, message
type Recorded = (u32, u32, u16, Option<String>);

/// Test context: records what the callbacks receive.
#[derive(Default)]
struct Recorder {
    events: Mutex<Vec<Recorded>>,
    samples: Mutex<Vec<f32>>,
}

extern "C" fn record_event(context: *mut c_void, event: *const LsbEvent) {
    let (recorder, event) = unsafe { (&*(context as *const Recorder), &*event) };
    let message = unsafe { read_str(event.message) }.map(str::to_owned);
    let entry = (event.kind, event.position_ms, event.volume, message);
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

fn track() -> SpotifyUri {
    SpotifyUri::from_uri("spotify:track:4uLU6hMCjMI75M1A2tKUQC").unwrap()
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
    let bridge = lsb_new(record_event, record_audio, context);
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
        let bridge = lsb_new(record_event, record_audio, context);
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
}

#[test]
fn player_events_map_to_bridge_events() {
    let id = 1;
    let cases = [
        (
            PlayerEvent::Playing {
                play_request_id: id,
                track_id: track(),
                position_ms: 5,
            },
            Some((LSB_EVENT_PLAYING, 5, 0)),
        ),
        (
            PlayerEvent::Paused {
                play_request_id: id,
                track_id: track(),
                position_ms: 6,
            },
            Some((LSB_EVENT_PAUSED, 6, 0)),
        ),
        (
            PlayerEvent::PositionChanged {
                play_request_id: id,
                track_id: track(),
                position_ms: 7,
            },
            Some((LSB_EVENT_POSITION, 7, 0)),
        ),
        (
            PlayerEvent::Seeked {
                play_request_id: id,
                track_id: track(),
                position_ms: 8,
            },
            Some((LSB_EVENT_POSITION, 8, 0)),
        ),
        (
            PlayerEvent::EndOfTrack {
                play_request_id: id,
                track_id: track(),
            },
            Some((LSB_EVENT_TRACK_ENDED, 0, 0)),
        ),
        (
            PlayerEvent::Unavailable {
                play_request_id: id,
                track_id: track(),
            },
            Some((LSB_EVENT_UNAVAILABLE, 0, 0)),
        ),
        (
            PlayerEvent::VolumeChanged { volume: 300 },
            Some((LSB_EVENT_VOLUME, 0, 300)),
        ),
        (PlayerEvent::Preloading { track_id: track() }, None),
    ];
    for (event, expected) in cases {
        assert_eq!(map_event(&event), expected, "{event:?}");
    }
}

#[test]
fn emit_passes_message_to_callback() {
    let recorder = Recorder::default();
    let callbacks = callbacks(&recorder);
    callbacks.emit(LSB_EVENT_ERROR, 0, 0, Some("bad\0token"));
    callbacks.emit(LSB_EVENT_LOGGED_IN, 0, 0, None);
    let events = recorder.events.lock().unwrap();
    assert_eq!(
        events[0],
        (LSB_EVENT_ERROR, 0, 0, Some("bad token".to_owned()))
    );
    assert_eq!(events[1], (LSB_EVENT_LOGGED_IN, 0, 0, None));
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
