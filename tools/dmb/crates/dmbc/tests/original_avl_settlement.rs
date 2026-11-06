//! Actual Original file opens and their independently retained fact grants.
#[path = "../../../shared/test_scratch.rs"]
mod test_scratch;

use dm_preprocess::source_arena_credit::{
    read_original_source_open_using, SourceArenaCredit, SourceArenaWork,
};
use dm_preprocess::{
    InitialEnvironment, OriginalRawOpenDecision as Decision, OriginalRawReadOutcome as Outcome,
    SourceAcquisitionLease, SourceProvider,
};
use dmbc::{
    input_snapshot::{FileSystemInputs, RecordingInputs},
    query_db::QueryDb,
};
use std::{io, path::Path, sync::Mutex};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Event {
    Reserve { grant: usize, bytes: usize },
    Shrink { grant: usize, before: usize, after: usize },
}

/// Observes actual issuer grants without owning another source, an allocation
/// credit, or a second budget. Identity is local to the one observed read.
#[derive(Default)]
struct Work {
    db: QueryDb,
    events: Mutex<Vec<Event>>,
}

fn grant(credit: &SourceArenaCredit) -> usize {
    std::ptr::from_ref(credit.owner()).cast::<()>() as usize
}

impl Work {
    fn take_events(&self) -> Vec<Event> {
        std::mem::take(&mut *self.events.lock().unwrap())
    }
}

impl SourceArenaWork for Work {
    fn original_read_bookkeeping_bytes(&self) -> io::Result<usize> {
        self.db.original_read_bookkeeping_bytes()
    }

    fn adopt_original_read(
        &self,
        credit: &mut SourceArenaCredit,
        source: &SourceAcquisitionLease,
    ) -> io::Result<()> {
        self.db.adopt_original_read(credit, source)
    }

    fn checkpoint(&self) -> io::Result<()> {
        self.db.checkpoint()
    }

    fn reserve(&self, bytes: usize) -> io::Result<SourceArenaCredit> {
        let credit = self.db.reserve(bytes)?;
        assert_eq!(credit.reserved_bytes(), bytes);
        self.events.lock().unwrap().push(Event::Reserve { grant: grant(&credit), bytes });
        Ok(credit)
    }

    fn grow(&self, credit: &mut SourceArenaCredit, bytes: usize) -> io::Result<()> {
        self.db.grow(credit, bytes)
    }

    fn shrink(&self, credit: &mut SourceArenaCredit, bytes: usize) -> io::Result<()> {
        let before = credit.reserved_bytes();
        self.db.shrink(credit, bytes)?;
        let after = credit.reserved_bytes();
        assert_eq!(before.checked_sub(after), Some(bytes));
        self.events.lock().unwrap().push(Event::Shrink { grant: grant(credit), before, after });
        Ok(())
    }
}

fn reserve_at(events: &[Event], index: usize) -> (usize, usize) {
    let Event::Reserve { grant, bytes } = events[index] else {
        panic!("expected actual pre-open reserve at {index}, got {events:?}")
    };
    (grant, bytes)
}

fn settlement(events: &[Event], reserved: (usize, usize)) -> (usize, usize) {
    let matches: Vec<_> = events.iter().enumerate().filter_map(|(index, event)| match *event {
        Event::Shrink { grant, before, after } if grant == reserved.0 => Some((index, before, after)),
        _ => None,
    }).collect();
    let &[(index, before, after)] = matches.as_slice() else {
        panic!("one settlement for the actual grant {reserved:?}, got {events:?}")
    };
    assert_eq!(before, reserved.1);
    assert!(after > 0 && after < before, "{reserved:?} did not settle: {events:?}");
    (index, after)
}

fn read(
    inputs: &RecordingInputs<FileSystemInputs>,
    path: &Path,
    work: &Work,
    decision: Decision,
    observed_open: &mut Option<usize>,
) -> io::Result<Outcome> {
    read_original_source_open_using(inputs, path, 1024, work, &mut || {
        assert!(observed_open.replace(work.events.lock().unwrap().len()).is_none());
        Ok(decision)
    })
}

#[test]
fn actual_open_and_payload_grants_settle_independently_before_snapshot_publication() {
    let root = test_scratch::dir("original-avl-settlement");
    let inputs = RecordingInputs::new(FileSystemInputs, 0)
        .with_initial_environment(InitialEnvironment::OriginalChecker0290);
    let work = Work::default();
    let mut prefix = None;
    let mut last_path = None;
    let mut released = [0usize; 2];
    for index in 0..16 {
        let path = root.join(format!("actual-{:02}.dm", index * 7 % 16));
        std::fs::write(&path, b"/datum/probe\n").unwrap();
        let mut observed_open = None;
        let Outcome::Acquired(source) = read(&inputs, &path, &work, Decision::Read, &mut observed_open).unwrap() else {
            panic!("actual file was not read")
        };
        assert_eq!(inputs.original_source_bytes(&source).unwrap().unwrap(), b"/datum/probe\n");
        let events = work.take_events();
        let (bookkeeping, open, payload) = (reserve_at(&events, 0), reserve_at(&events, 1), reserve_at(&events, 2));
        assert_ne!(bookkeeping.0, open.0);
        assert_ne!(bookkeeping.0, payload.0);
        assert_ne!(open.0, payload.0);
        let (open_index, open_after) = settlement(&events, open);
        let (payload_index, payload_after) = settlement(&events, payload);
        let open_callback = observed_open.unwrap();
        assert!(open_index < open_callback && open_callback <= payload_index);
        released[0] += open.1 - open_after;
        released[1] += payload.1 - payload_after;
        if index == 3 {
            prefix = Some(inputs.snapshot().unwrap());
        }
        last_path = Some(path);
    }

    assert!(released.into_iter().all(|bytes| bytes > 16 * 1024));
    let prefix = prefix.unwrap();
    let last = inputs.snapshot().unwrap();
    drop(inputs);
    assert_eq!(prefix.restat(&FileSystemInputs).unwrap().rehashed, 4);
    assert_eq!(last.restat(&FileSystemInputs).unwrap().rehashed, 16);
    let last_path = last_path.unwrap();
    std::fs::write(&last_path, b"/datum/changed\n").unwrap();
    assert!(prefix.restat(&FileSystemInputs).unwrap().unchanged());
    assert_eq!(last.restat(&FileSystemInputs).unwrap().changed, [last_path]);
}

#[test]
fn actual_missing_open_settles_no_payload_grant_and_keeps_the_negative_fact() {
    let root = test_scratch::dir("original-avl-missing");
    let path = root.join("missing.dm");
    let inputs = RecordingInputs::new(FileSystemInputs, 0)
        .with_initial_environment(InitialEnvironment::OriginalChecker0290);
    let work = Work::default();
    let mut observed_open = None;
    let Outcome::SourceOpenFailed(error) = read(&inputs, &path, &work, Decision::Read, &mut observed_open).unwrap() else {
        panic!("a real missing path must keep its failed open")
    };
    assert_eq!(error.kind(), io::ErrorKind::NotFound);
    assert!(observed_open.is_none());
    let events = work.take_events();
    let open = reserve_at(&events, 1);
    let payload = reserve_at(&events, 2);
    settlement(&events, open);
    assert!(!events.iter().any(|event| matches!(event, Event::Shrink { grant, .. } if *grant == payload.0)));

    let snapshot = inputs.snapshot().unwrap();
    let report = snapshot.restat(&FileSystemInputs).unwrap();
    assert!(report.unchanged());
    assert_eq!(report.rehashed, 0);
    std::fs::write(&path, b"/datum/new\n").unwrap();
    assert_eq!(snapshot.restat(&FileSystemInputs).unwrap().changed, [path]);
}

#[test]
fn original_avl_actual_frozen_source_and_weak_pressure_keep_exact_input_admission() {
    let root = test_scratch::dir("original-avl-fast-admission");
    let path = root.join("actual.dm");
    let raw = b"/datum/probe/actual\n";
    std::fs::write(&path, raw).unwrap();
    let inputs = RecordingInputs::new(FileSystemInputs, 0)
        .with_initial_environment(InitialEnvironment::OriginalChecker0290);
    let db = QueryDb::default();
    let Outcome::Acquired(lease) = read_original_source_open_using(
        &inputs, &path, 1024, &db, &mut || Ok(Decision::Read),
    ).unwrap() else { panic!("expected the actual physical source") };
    let source = lease.source_text();
    for end in 1..=raw.len() {
        assert_eq!(source.span_fingerprint(0..end), Some(xxhash_rust::xxh3::xxh3_128(&raw[..end])));
    }
    source.visit_fingerprint_storage(|_, _, bytes| assert_eq!(bytes, 0));

    // Calibrate the existing family's headroom through the real grant API,
    // without creating an artificial family ceiling or allocating that much.
    let mut probe = db.reserve(0).unwrap();
    for bit in (0..usize::BITS).rev() {
        if let Err(error) = db.grow(&mut probe, 1usize << bit) {
            assert_eq!(error.kind(), io::ErrorKind::OutOfMemory);
        }
    }
    let near_ceiling = probe.reserved_bytes();
    assert!(near_ceiling > 64 * 1024);
    drop(probe);
    let held = db.reserve(64 * 1024).unwrap();
    let buffer = vec![1u8; held.reserved_bytes()];
    assert_eq!(buffer.capacity(), held.reserved_bytes());
    assert_eq!(db.reserve(near_ceiling).err().unwrap().kind(), io::ErrorKind::OutOfMemory);
    drop((buffer, held));
    // No census call after the release. Cached headroom cannot reject a
    // grant that the exact pressure sweep now admits.
    let admitted = db.reserve(near_ceiling).unwrap();
    assert_eq!(admitted.reserved_bytes(), near_ceiling);
    assert_eq!(inputs.original_source_bytes(&lease).unwrap().unwrap(), raw);
}
