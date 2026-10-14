use super::*;
fn envelope(index: usize) -> Envelope {
    Envelope::Thread {
        tid: index,
        name: index.to_string(),
    }
}
use tracing_subscriber::prelude::*;
#[derive(Clone, Default)]
struct Buffer(Arc<Mutex<Vec<u8>>>);
impl Write for Buffer {
    fn write(&mut self, data: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(data);
        Ok(data.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
fn dispatch(output: Buffer) -> (tracing::Dispatch, FlushGuard) {
    let (layer, guard) = build(output, 2).unwrap();
    (
        tracing::Dispatch::new(tracing_subscriber::registry().with(layer)),
        guard,
    )
}
#[test]
fn persistent_thread_uses_each_exact_request_layer() {
    let first = Buffer::default();
    let second = Buffer::default();
    let (a, ga) = dispatch(first.clone());
    let (b, gb) = dispatch(second.clone());
    let worker = std::thread::spawn(move || {
        tracing::dispatcher::with_default(&a, || {
            let span = tracing::info_span!("first-span", value = 7);
            let _entered = span.enter();
            tracing::info!(marker = "first-only");
        });
        tracing::dispatcher::with_default(&b, || {
            let span = tracing::info_span!("second-span", value = 9);
            let _entered = span.enter();
            tracing::info!(marker = "second-only");
        });
    });
    worker.join().unwrap();
    ga.finish().unwrap();
    gb.finish().unwrap();
    for (buffer, present, absent) in [
        (first, "first-only", "second-only"),
        (second, "second-only", "first-only"),
    ] {
        let bytes = buffer.0.lock().unwrap();
        let text = std::str::from_utf8(&bytes).unwrap();
        assert!(text.contains(present));
        assert!(!text.contains(absent));
        let events: Vec<Value> = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(events.len(), 4);
        assert_eq!(events[0]["ph"], "M");
        assert_eq!(events[1]["ph"], "B");
        assert!(events[1][".file"]
            .as_str()
            .unwrap()
            .ends_with("chrome_tests.rs"));
        assert!(events[1][".line"].as_u64().unwrap() > 0);
        assert_eq!(events[2]["ph"], "i");
        assert_eq!(events[3]["ph"], "E");
    }
}
#[test]
fn bounded_queue_drains_every_event() {
    let buffer = Buffer::default();
    let (layer, guard) = build(buffer.clone(), 1).unwrap();
    for index in 0..10000 {
        layer.send(envelope(index));
    }
    guard.finish().unwrap();
    let values: Vec<Value> = serde_json::from_slice(&buffer.0.lock().unwrap()).unwrap();
    assert_eq!(values.len(), 10000);
    for (index, value) in values.iter().enumerate() {
        assert_eq!(value["tid"], index);
    }
}
struct FailedWriter;
impl Write for FailedWriter {
    fn write(&mut self, _: &[u8]) -> std::io::Result<usize> {
        Err(std::io::Error::other("injected Chrome write failure"))
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
#[test]
fn failed_writer_is_reported_after_join() {
    let (layer, guard) = build(FailedWriter, 1).unwrap();
    layer.send(envelope(0));
    assert!(guard
        .finish()
        .unwrap_err()
        .contains("injected Chrome write failure"));
}
#[test]
fn queue_backpressure_blocks_until_receiver_consumes() {
    let (sender, receiver) = sync_channel(1);
    sender.send(Message::Event(envelope(1))).unwrap();
    let (started_tx, started_rx) = std::sync::mpsc::channel();
    let (done_tx, done_rx) = std::sync::mpsc::channel();
    let worker = std::thread::spawn(move || {
        started_tx.send(()).unwrap();
        sender.send(Message::Event(envelope(2))).unwrap();
        done_tx.send(()).unwrap();
    });
    started_rx.recv().unwrap();
    assert!(done_rx.try_recv().is_err());
    assert!(matches!(receiver.recv().unwrap(), Message::Event(_)));
    done_rx.recv().unwrap();
    assert!(matches!(receiver.recv().unwrap(), Message::Event(_)));
    worker.join().unwrap();
}
#[test]
fn queued_argument_snapshots_preserve_record_updates() {
    let buffer = Buffer::default();
    let (dispatch, guard) = dispatch(buffer.clone());
    tracing::dispatcher::with_default(&dispatch, || {
        let span = tracing::info_span!("recorded", value = 7);
        let entered = span.enter();
        span.record("value", 9);
        drop(entered);
    });
    guard.finish().unwrap();
    let events: Vec<Value> = serde_json::from_slice(&buffer.0.lock().unwrap()).unwrap();
    assert_eq!(events[1]["args"]["value"], "7");
    assert_eq!(events[2]["args"]["value"], "9");
    assert_eq!(events[1]["cat"], events[2]["cat"]);
    assert_eq!(events[1][".file"], events[2][".file"]);
}
#[test]
fn dynamic_stage_label_has_one_shared_owner_and_exact_trace_text() {
    struct Check(Arc<Mutex<Vec<bool>>>);
    impl<S> Layer<S> for Check
    where
        S: Subscriber + for<'a> LookupSpan<'a>,
    {
        fn on_new_span(&self, _: &Attributes<'_>, id: &Id, context: Context<'_, S>) {
            let span = context.span(id).unwrap();
            let extensions = span.extensions();
            let stage = extensions.get::<crate::names::StageName>().unwrap();
            let arguments = extensions.get::<Arguments>().unwrap();
            let Name::Shared(name) = &arguments.name else {
                panic!("dynamic name must be shared")
            };
            self.0.lock().unwrap().push(Arc::ptr_eq(&stage.0, name));
        }
    }
    let output = Buffer::default();
    let shared = Arc::new(Mutex::new(Vec::new()));
    let (chrome, guard) = build(output.clone(), 2).unwrap();
    let subscriber = tracing_subscriber::registry()
        .with(crate::names::Names)
        .with(chrome)
        .with(Check(Arc::clone(&shared)));
    tracing::subscriber::with_default(subscriber, || {
        let stage = "dynamic λ stage".to_owned();
        let span = tracing::info_span!("compiler_stage", stage = stage.as_str());
        let _entered = span.enter();
    });
    guard.finish().unwrap();
    assert_eq!(*shared.lock().unwrap(), vec![true]);
    let events: Vec<Value> = serde_json::from_slice(&output.0.lock().unwrap()).unwrap();
    assert_eq!(events[1]["name"], "dynamic λ stage");
    assert_eq!(events[2]["name"], "dynamic λ stage");
    assert_eq!(events[1]["args"]["stage"], "\"dynamic λ stage\"");
}
