//! Observe Chrome worker CPU from first underlying I/O through final drop.
use crate::{internal_observer::InternalThreadObserver, State};
use std::io::{self, Write};
use std::sync::Arc;

pub(crate) struct ObservedWriter<W> {
    inner: W,
    state: Arc<State>,
    observer: Option<InternalThreadObserver>,
}
impl<W> ObservedWriter<W> {
    pub(crate) fn new(inner: W, state: Arc<State>) -> Self {
        Self {
            inner,
            state,
            observer: None,
        }
    }
    fn observe(&mut self) {
        // Construction occurs on the main thread; first I/O occurs after the
        // writer has moved into tracing-chrome's dedicated worker thread. Its
        // initial BufWriter-only serialization before this boundary is unobserved.
        if self.observer.is_none() {
            self.observer = Some(InternalThreadObserver::new(
                Arc::clone(&self.state),
                "profile.chrome_writer",
            ));
        }
    }
}
impl<W: Write> Write for ObservedWriter<W> {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.observe();
        self.inner.write(bytes)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.observe();
        self.inner.flush()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use std::sync::Mutex;

    #[test]
    fn moved_writer_records_one_actual_worker_receipt_after_join() {
        let state = Arc::new(State {
            calibration: crate::clock::calibrate(),
            io_wait: crate::io_wait::Ledger::default(),
            entries: Mutex::new(BTreeMap::new()),
            folded: Mutex::new(BTreeMap::new()),
            wall_folded: Mutex::new(BTreeMap::new()),
            finished: std::sync::atomic::AtomicBool::new(false),
            workers: std::sync::atomic::AtomicUsize::new(0),
            bindings: std::sync::atomic::AtomicUsize::new(0),
            dispatch: Mutex::new(None),
        });
        let writer = ObservedWriter::new(Vec::<u8>::new(), Arc::clone(&state));
        assert!(state.entries.lock().unwrap().is_empty());
        let worker = std::thread::spawn(move || {
            let thread = format!("{:?}", std::thread::current().id());
            let mut writer = writer;
            writer.write_all(b"first").unwrap();
            writer.write_all(b"second").unwrap();
            writer.flush().unwrap();
            drop(writer);
            thread
        });
        let thread = worker.join().unwrap();
        let entries = state.entries.lock().unwrap();
        let entry = &entries["profile.chrome_writer"];
        assert_eq!(entry.report.calls, 1);
        assert_eq!(
            entry.intervals.len() + usize::from(entry.interval_missing),
            1
        );
        if !entry.interval_missing {
            assert_eq!(entry.intervals[&thread].len(), 1);
        }
    }
}
