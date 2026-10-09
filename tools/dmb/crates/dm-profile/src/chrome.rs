//! Request-local, lossless Chrome tracing. The queue bound counts events, not bytes.
use serde::{ser::SerializeMap, Serialize, Serializer};
use serde_json::{Map, Value};
use std::{
    collections::HashMap,
    io::{BufWriter, Write},
    sync::{
        mpsc::{sync_channel, SyncSender},
        Arc, Mutex,
    },
    thread::{JoinHandle, ThreadId},
    time::Instant,
};
use tracing::{
    field::{Field, Visit},
    span::{Attributes, Id, Record},
    Event, Subscriber,
};
use tracing_subscriber::{layer::Context, registry::LookupSpan, Layer};

const QUEUE_EVENTS: usize = 4096;
enum Message {
    Event(Envelope),
    Finish,
}
enum Name {
    Static(&'static str),
    Shared(Arc<str>),
}
impl Name {
    fn as_str(&self) -> &str {
        match self {
            Self::Static(name) => name,
            Self::Shared(name) => name,
        }
    }
}
enum Envelope {
    Thread {
        tid: usize,
        name: String,
    },
    Record {
        phase: &'static str,
        timestamp: f64,
        tid: usize,
        name: Name,
        category: &'static str,
        location: Option<(&'static str, u32)>,
        args: Option<Arc<Map<String, Value>>>,
    },
}
impl Serialize for Envelope {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut map = serializer.serialize_map(None)?;
        map.serialize_entry("pid", &1)?;
        match self {
            Self::Thread { tid, name } => {
                map.serialize_entry("ph", "M")?;
                map.serialize_entry("name", "thread_name")?;
                map.serialize_entry("tid", tid)?;
                #[derive(Serialize)]
                struct ThreadName<'a> {
                    name: &'a str,
                }
                map.serialize_entry("args", &ThreadName { name })?;
            }
            Self::Record {
                phase,
                timestamp,
                tid,
                name,
                category,
                location,
                args,
            } => {
                map.serialize_entry("ph", phase)?;
                map.serialize_entry("ts", timestamp)?;
                map.serialize_entry("tid", tid)?;
                map.serialize_entry("name", name.as_str())?;
                map.serialize_entry("cat", category)?;
                if *phase == "i" {
                    map.serialize_entry("s", "t")?;
                }
                if let Some((file, line)) = location {
                    map.serialize_entry(".file", file)?;
                    map.serialize_entry(".line", line)?;
                }
                if let Some(args) = args {
                    if !args.is_empty() {
                        map.serialize_entry("args", args.as_ref())?;
                    }
                }
            }
        }
        map.end()
    }
}
#[derive(Default)]
struct Failure(Mutex<Option<String>>);
impl Failure {
    fn record(&self, error: impl ToString) {
        let mut slot = self.0.lock().unwrap_or_else(|e| e.into_inner());
        if slot.is_none() {
            *slot = Some(error.to_string());
        }
    }
    fn get(&self) -> Option<String> {
        self.0.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }
}
pub(super) struct ChromeLayer {
    sender: SyncSender<Message>,
    failure: Arc<Failure>,
    start: Instant,
    threads: Mutex<HashMap<ThreadId, usize>>,
}
pub(super) struct FlushGuard {
    sender: SyncSender<Message>,
    failure: Arc<Failure>,
    worker: Option<JoinHandle<()>>,
}
impl FlushGuard {
    pub(super) fn finish(mut self) -> Result<(), String> {
        self.drain();
        self.failure.get().map_or(Ok(()), Err)
    }
    fn drain(&mut self) {
        if let Some(worker) = self.worker.take() {
            if self.sender.send(Message::Finish).is_err() {
                self.failure.record("Chrome trace writer disconnected");
            }
            if worker.join().is_err() {
                self.failure.record("Chrome trace writer panicked");
            }
        }
    }
}
impl Drop for FlushGuard {
    fn drop(&mut self) {
        self.drain();
    }
}
pub(super) fn layer(
    writer: impl Write + Send + 'static,
) -> Result<(ChromeLayer, FlushGuard), String> {
    build(writer, QUEUE_EVENTS)
}
fn build(
    writer: impl Write + Send + 'static,
    capacity: usize,
) -> Result<(ChromeLayer, FlushGuard), String> {
    let (sender, receiver) = sync_channel(capacity);
    let failure = Arc::new(Failure::default());
    let errors = Arc::clone(&failure);
    let worker = std::thread::Builder::new()
        .name("profile-chrome-writer".into())
        .spawn(move || {
            let result = (|| -> std::io::Result<()> {
                let mut writer = BufWriter::new(writer);
                writer.write_all(b"[\n")?;
                let mut first = true;
                while let Ok(message) = receiver.recv() {
                    match message {
                        Message::Event(event) => {
                            if !first {
                                writer.write_all(b",\n")?;
                            }
                            serde_json::to_writer(&mut writer, &event)?;
                            first = false;
                        }
                        Message::Finish => break,
                    }
                }
                writer.write_all(b"\n]")?;
                writer.flush()
            })();
            if let Err(error) = result {
                errors.record(error);
            }
        })
        .map_err(|e| e.to_string())?;
    Ok((
        ChromeLayer {
            sender: sender.clone(),
            failure: Arc::clone(&failure),
            start: Instant::now(),
            threads: Mutex::new(HashMap::new()),
        },
        FlushGuard {
            sender,
            failure,
            worker: Some(worker),
        },
    ))
}
#[derive(Default)]
struct Fields(Map<String, Value>);
impl Visit for Fields {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        self.0
            .insert(field.name().to_owned(), format!("{value:?}").into());
    }
}
struct Arguments {
    name: Name,
    fields: Arc<Map<String, Value>>,
}
impl ChromeLayer {
    fn send(&self, event: Envelope) {
        if self.sender.send(Message::Event(event)).is_err() {
            self.failure.record("Chrome trace writer disconnected");
        }
    }
    fn thread(&self) -> usize {
        let current = std::thread::current();
        let mut threads = self.threads.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(id) = threads.get(&current.id()) {
            return *id;
        }
        let id = threads.len();
        threads.insert(current.id(), id);
        // Enqueue metadata before exposing the new ID to another callback.
        self.send(Envelope::Thread {
            tid: id,
            name: current
                .name()
                .map(str::to_owned)
                .unwrap_or_else(|| id.to_string()),
        });
        id
    }
    fn event(
        &self,
        phase: &'static str,
        name: Name,
        metadata: &'static tracing::Metadata<'static>,
        args: Option<Arc<Map<String, Value>>>,
    ) {
        let target = metadata.target();
        let timestamp = self.start.elapsed().as_nanos() as f64 / 1000.;
        let tid = self.thread();
        self.send(Envelope::Record {
            phase,
            timestamp,
            tid,
            name,
            category: target,
            location: metadata.file().zip(metadata.line()),
            args,
        });
    }

    fn span<S>(&self, id: &Id, context: Context<'_, S>, phase: &'static str)
    where
        S: Subscriber + for<'a> LookupSpan<'a>,
    {
        if let Some(span) = context.span(id) {
            let extensions = span.extensions();
            let (name, args) = extensions
                .get::<Arguments>()
                .map(|a| {
                    let name = match &a.name {
                        Name::Static(name) => Name::Static(name),
                        Name::Shared(name) => Name::Shared(Arc::clone(name)),
                    };
                    (name, Some(Arc::clone(&a.fields)))
                })
                .unwrap_or_else(|| (Name::Static(span.metadata().name()), None));
            self.event(phase, name, span.metadata(), args);
        }
    }
}
impl<S> Layer<S> for ChromeLayer
where
    S: Subscriber + for<'a> LookupSpan<'a>,
{
    fn on_new_span(&self, attributes: &Attributes<'_>, id: &Id, context: Context<'_, S>) {
        let mut fields = Fields::default();
        attributes.record(&mut fields);
        if let Some(span) = context.span(id) {
            let name = span
                .extensions()
                .get::<super::names::StageName>()
                .map(|name| Name::Shared(Arc::from(name.0.as_str())))
                .unwrap_or_else(|| Name::Static(span.metadata().name()));
            span.extensions_mut().insert(Arguments {
                name,
                fields: Arc::new(fields.0),
            });
        }
    }
    fn on_record(&self, id: &Id, record: &Record<'_>, context: Context<'_, S>) {
        if let Some(span) = context.span(id) {
            let mut extensions = span.extensions_mut();
            if let Some(args) = extensions.get_mut::<Arguments>() {
                let mut fields = Fields(std::mem::take(Arc::make_mut(&mut args.fields)));
                record.record(&mut fields);
                *Arc::make_mut(&mut args.fields) = fields.0;
            }
        }
    }
    fn on_enter(&self, id: &Id, context: Context<'_, S>) {
        self.span(id, context, "B");
    }
    fn on_exit(&self, id: &Id, context: Context<'_, S>) {
        self.span(id, context, "E");
    }
    fn on_event(&self, event: &Event<'_>, _: Context<'_, S>) {
        let mut fields = Fields::default();
        event.record(&mut fields);
        self.event(
            "i",
            Name::Static(event.metadata().name()),
            event.metadata(),
            Some(Arc::new(fields.0)),
        );
    }
}
#[cfg(test)]
#[path = "chrome_tests.rs"]
mod tests;
