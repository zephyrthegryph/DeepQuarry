//! Bounded process-local candidates. Authority remains in the ordinary consumers.
use dm_preprocess::regions::{DirectiveRecord, ExpansionMemo, ExpansionRecord, FragmentRecord};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};
// Sized to hold every directive interval, expansion region and fragment of
// the DeepQuarry tree (about 5.6k intervals, 11k regions, 6.6k chunks), so an
// edit replays from memory instead of decoding every record from disk.
const LIMIT: usize = 32 * 1024;
const KIND_BUDGET: usize = 4096 * 1024 * 1024;
const TOTAL_BUDGET: usize = 8192 * 1024 * 1024;
/// Diagnostic directive lookup split (`DMB_TIMINGS_DETAIL=1`).
pub(crate) struct LookupCounters {
    resident_hits: std::sync::atomic::AtomicU64,
    resident_misses: std::sync::atomic::AtomicU64,
    resident_ns: std::sync::atomic::AtomicU64,
    disk_ns: std::sync::atomic::AtomicU64,
}
impl LookupCounters {
    fn record(&self, hit: bool, elapsed: std::time::Duration) {
        use std::sync::atomic::Ordering::Relaxed;
        if hit { &self.resident_hits } else { &self.resident_misses }.fetch_add(1, Relaxed);
        self.resident_ns.fetch_add(elapsed.as_nanos() as u64, Relaxed);
    }
    fn record_disk(&self, elapsed: std::time::Duration) {
        self.disk_ns
            .fetch_add(elapsed.as_nanos() as u64, std::sync::atomic::Ordering::Relaxed);
    }
    pub(crate) fn report(&self) -> String {
        use std::sync::atomic::Ordering::Relaxed;
        format!(
            "resident_hits={} resident_misses={} resident={:.3}s disk={:.3}s",
            self.resident_hits.swap(0, Relaxed),
            self.resident_misses.swap(0, Relaxed),
            self.resident_ns.swap(0, Relaxed) as f64 / 1e9,
            self.disk_ns.swap(0, Relaxed) as f64 / 1e9,
        )
    }
}
pub(crate) static DIRECTIVE_LOOKUPS: LookupCounters = LookupCounters {
    resident_hits: std::sync::atomic::AtomicU64::new(0),
    resident_misses: std::sync::atomic::AtomicU64::new(0),
    resident_ns: std::sync::atomic::AtomicU64::new(0),
    disk_ns: std::sync::atomic::AtomicU64::new(0),
};
#[derive(Clone)]
enum Record {
    Expansion(Arc<ExpansionRecord>),
    Directive(Arc<DirectiveRecord>),
    Fragment(Arc<FragmentRecord>),
}
impl Record {
    fn kind(&self) -> usize {
        match self {
            Self::Expansion(_) => 0,
            Self::Directive(_) => 1,
            Self::Fragment(_) => 2,
        }
    }
    fn key(&self) -> u128 {
        match self {
            Self::Expansion(r) => r.key(),
            Self::Directive(r) => r.key(),
            Self::Fragment(r) => r.key(),
        }
    }
    fn bytes(&self) -> usize {
        match self {
            Self::Expansion(r) => r.retained_size_bytes(),
            Self::Directive(r) => r.retained_size_bytes(),
            Self::Fragment(r) => r.retained_size_bytes(),
        }
    }
    fn replaces(&self, old: &Self) -> bool {
        match (self, old) {
            (Self::Expansion(a), Self::Expansion(b)) => a.same_expansion(b),
            (Self::Directive(a), Self::Directive(b)) => a.same_plan(b),
            // Independent fragment identity includes exact source and payload, not its key alone.
            (Self::Fragment(a), Self::Fragment(b)) => a == b,
            _ => false,
        }
    }
}
// Conservative metadata charges include two FIFO BTree nodes, variant slots,
// allocator alignment and key-map nodes. Payload accounting is cached once.
const RECORD_OVERHEAD: usize = 1024;
const KEY_OVERHEAD: usize = 2048;
struct Stored {
    record: Record,
    sequence: u64,
    charge: usize,
}
#[derive(Default)]
struct Store {
    records: BTreeMap<(usize, u128), Vec<Stored>>,
    fifo: BTreeMap<u64, (usize, u128)>,
    kind_fifo: [BTreeMap<u64, u128>; 3],
    sizes: [usize; 3],
    total: usize,
    count: usize,
    next: u64,
}
impl Store {
    fn remove(&mut self, sequence: u64) {
        let (kind, key) = self.fifo.remove(&sequence).expect("stored FIFO entry");
        self.kind_fifo[kind].remove(&sequence);
        let variants = self.records.get_mut(&(kind, key)).expect("stored variants");
        let index = variants
            .iter()
            .position(|v| v.sequence == sequence)
            .expect("stored variant");
        let charge = variants.remove(index).charge;
        self.sizes[kind] -= charge;
        self.total -= charge;
        self.count -= 1;
        if variants.is_empty() {
            self.records.remove(&(kind, key));
            self.sizes[kind] -= KEY_OVERHEAD;
            self.total -= KEY_OVERHEAD;
        }
    }
    fn insert(&mut self, record: Record) {
        let charge = record.bytes().saturating_add(RECORD_OVERHEAD);
        let kind = record.kind();
        let key = record.key();
        if charge.saturating_add(KEY_OVERHEAD) > KIND_BUDGET
            || charge.saturating_add(KEY_OVERHEAD) > TOTAL_BUDGET
        {
            return;
        }
        // Sequence exhaustion drops hints; it cannot overwrite an existing FIFO key.
        if self.next == u64::MAX {
            *self = Self::default();
        }
        if let Some(sequence) = self.records.get(&(kind, key)).and_then(|variants| {
            variants
                .iter()
                .find(|old| record.replaces(&old.record))
                .map(|old| old.sequence)
        }) {
            self.remove(sequence);
        }
        if let Some(sequence) = self
            .records
            .get(&(kind, key))
            .filter(|v| v.len() == 4)
            .map(|v| v[0].sequence)
        {
            self.remove(sequence);
        }
        loop {
            let extra = if self.records.contains_key(&(kind, key)) {
                0
            } else {
                KEY_OVERHEAD
            };
            if self.sizes[kind]
                .saturating_add(charge)
                .saturating_add(extra)
                > KIND_BUDGET
            {
                let sequence = *self.kind_fifo[kind]
                    .first_key_value()
                    .expect("kind budget has entries")
                    .0;
                self.remove(sequence);
                continue;
            }
            if self.total.saturating_add(charge).saturating_add(extra) > TOTAL_BUDGET
                || self.count == LIMIT
            {
                let sequence = *self
                    .fifo
                    .first_key_value()
                    .expect("total budget has entries")
                    .0;
                self.remove(sequence);
                continue;
            }
            if extra != 0 {
                self.records.insert((kind, key), Vec::with_capacity(4));
                self.sizes[kind] += extra;
                self.total += extra;
            }
            break;
        }
        let sequence = self.next;
        self.next += 1;
        self.records.get_mut(&(kind, key)).unwrap().push(Stored {
            record,
            sequence,
            charge,
        });
        self.fifo.insert(sequence, (kind, key));
        self.kind_fifo[kind].insert(sequence, key);
        self.sizes[kind] += charge;
        self.total += charge;
        self.count += 1;
    }
}
#[derive(Default)]
pub(super) struct ResidentMemo {
    inputs: dm_preprocess::regions::ExpansionInputs,
    store: Mutex<Store>,
}
impl ResidentMemo {
    pub(super) fn input_census(&self) -> crate::heap_census::HeapCensusReport {
        crate::heap_census::expansion_input_census(&self.inputs)
    }
    fn records(&self, kind: usize, key: u128) -> Vec<Record> {
        self.store
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .records
            .get(&(kind, key))
            .map_or_else(Vec::new, |variants| {
                variants.iter().map(|v| v.record.clone()).collect()
            })
    }

    fn insert(&self, record: Record) {
        self.store
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(record);
    }
    pub(super) fn with_disk<'a>(&'a self, disk: Option<&'a dyn ExpansionMemo>) -> MemoView<'a> {
        MemoView {
            resident: Some(self),
            disk,
            skipped: Default::default(),
            resident_only: RESIDENT_ONLY_MISSES,
        }
    }
}
pub(crate) struct MemoView<'a> {
    resident: Option<&'a ResidentMemo>,
    disk: Option<&'a dyn ExpansionMemo>,
    /// Resident misses that skipped the disk store in this request.
    skipped: std::sync::atomic::AtomicUsize,
    resident_only: usize,
}
/// A resident daemon holds every record it has computed or accepted, so a handful of misses in one
/// request is an edit: the changed files' keys cannot be on disk. Opening the disk snapshot to
/// confirm that costs about 2 s, so up to this many misses recompute without consulting it. A request
/// with more misses (a cold daemon, another branch) reaches the disk store as before.
const RESIDENT_ONLY_MISSES: usize = 64;
impl<'a> MemoView<'a> {
    pub(super) fn disk_only(disk: &'a dyn ExpansionMemo) -> Self {
        Self {
            resident: None,
            disk: Some(disk),
            skipped: Default::default(),
            resident_only: 0,
        }
    }
    fn records(&self, kind: usize, key: u128) -> Vec<Record> {
        self.resident
            .map_or_else(Vec::new, |r| r.records(kind, key))
    }
    /// Whether a resident miss may consult the disk store.
    fn disk_allowed(&self) -> bool {
        self.resident.is_none()
            || self
                .skipped
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed)
                >= self.resident_only
    }
    #[cfg(test)]
    fn with_resident_only(mut self, misses: usize) -> Self {
        self.resident_only = misses;
        self
    }
    fn retain(&self, record: Record) {
        if let Some(resident) = self.resident {
            resident.insert(record);
        }
    }
}
impl ExpansionMemo for MemoView<'_> {
    fn input_admissions(&self) -> Option<&dm_preprocess::regions::ExpansionInputs> {
        self.resident.map(|resident| &resident.inputs)
    }
    fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>> {
        let mut result = self.disk.map_or_else(Vec::new, |d| d.candidates(key));
        result.extend(self.records(0, key).into_iter().filter_map(|r| {
            if let Record::Expansion(r) = r {
                Some(r)
            } else {
                None
            }
        }));
        result
    }
    fn directive_candidates(&self, key: u128) -> Vec<Arc<DirectiveRecord>> {
        let mut result = self
            .disk
            .map_or_else(Vec::new, |d| d.directive_candidates(key));
        result.extend(self.records(1, key).into_iter().filter_map(|r| {
            if let Record::Directive(r) = r {
                Some(r)
            } else {
                None
            }
        }));
        result
    }
    fn fragment_candidates(&self, key: u128) -> Vec<Arc<FragmentRecord>> {
        let mut result = self
            .disk
            .map_or_else(Vec::new, |d| d.fragment_candidates(key));
        result.extend(self.records(2, key).into_iter().filter_map(|r| {
            if let Record::Fragment(r) = r {
                Some(r)
            } else {
                None
            }
        }));
        result
    }
    fn visit_candidates(
        &self,
        key: u128,
        accept: &mut dyn FnMut(&Arc<ExpansionRecord>) -> bool,
    ) -> bool {
        self.records(0, key).iter().rev().any(|r| match r {
            Record::Expansion(r) => accept(r),
            _ => false,
        }) || self.disk.filter(|_| self.disk_allowed()).is_some_and(|d| {
            d.visit_candidates(key, &mut |record| {
                if !accept(record) {
                    return false;
                }
                self.retain(Record::Expansion(Arc::clone(record)));
                true
            })
        })
    }
    fn visit_directive_candidates(
        &self,
        key: u128,
        accept: &mut dyn FnMut(&Arc<DirectiveRecord>) -> bool,
    ) -> bool {
        let started = std::time::Instant::now();
        let resident = self.records(1, key).iter().rev().any(|r| match r {
            Record::Directive(r) => accept(r),
            _ => false,
        });
        DIRECTIVE_LOOKUPS.record(resident, started.elapsed());
        resident || self.disk.filter(|_| self.disk_allowed()).is_some_and(|d| {
            let started = std::time::Instant::now();
            let result = d.visit_directive_candidates(key, &mut |record| {
                if !accept(record) {
                    return false;
                }
                self.retain(Record::Directive(Arc::clone(record)));
                true
            });
            DIRECTIVE_LOOKUPS.record_disk(started.elapsed());
            result
        })
    }
    fn visit_fragment_candidates(
        &self,
        key: u128,
        accept: &mut dyn FnMut(&Arc<FragmentRecord>) -> bool,
    ) -> bool {
        self.records(2, key).iter().rev().any(|r| match r {
            Record::Fragment(r) => accept(r),
            _ => false,
        }) || self.disk.filter(|_| self.disk_allowed()).is_some_and(|d| {
            d.visit_fragment_candidates(key, &mut |record| {
                if !accept(record) {
                    return false;
                }
                self.retain(Record::Fragment(Arc::clone(record)));
                true
            })
        })
    }
    fn insert(&self, r: Arc<ExpansionRecord>) {
        self.retain(Record::Expansion(Arc::clone(&r)));
        if let Some(d) = self.disk {
            d.insert(r)
        }
    }
    fn insert_directive(&self, r: Arc<DirectiveRecord>) {
        self.retain(Record::Directive(Arc::clone(&r)));
        if let Some(d) = self.disk {
            d.insert_directive(r)
        }
    }
    fn insert_fragment(&self, r: Arc<FragmentRecord>) {
        self.retain(Record::Fragment(Arc::clone(&r)));
        if let Some(d) = self.disk {
            d.insert_fragment(r)
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    struct Disk {
        record: Arc<FragmentRecord>,
        reads: AtomicUsize,
    }
    impl ExpansionMemo for Disk {
        fn candidates(&self, _: u128) -> Vec<Arc<ExpansionRecord>> {
            Vec::new()
        }
        fn insert(&self, _: Arc<ExpansionRecord>) {}
        fn fragment_candidates(&self, _: u128) -> Vec<Arc<FragmentRecord>> {
            self.reads.fetch_add(1, Ordering::Relaxed);
            vec![Arc::clone(&self.record)]
        }
    }
    fn fragment(payload: &[u8]) -> Arc<FragmentRecord> {
        Arc::new(FragmentRecord::new(1, "exact source", Arc::from(payload)).unwrap())
    }
    #[test]
    fn disk_only_visits_do_not_promote_into_resident_storage() {
        let disk = Disk {
            record: fragment(b"valid"),
            reads: AtomicUsize::new(0),
        };
        let view = MemoView::disk_only(&disk);
        for _ in 0..2 {
            assert!(view
                .visit_fragment_candidates(disk.record.key(), &mut |record| record.payload()
                    == b"valid"));
        }
        assert_eq!(disk.reads.load(Ordering::Relaxed), 2);
        assert!(view.resident.is_none());
    }
    #[test]
    fn authoritative_rejection_reaches_disk_and_accepted_memory_does_not_read_disk() {
        let resident = ResidentMemo::default();
        let bad = fragment(b"invalid parser payload");
        resident.insert(Record::Fragment(Arc::clone(&bad)));
        let disk = Disk {
            record: fragment(b"accepted parser payload"),
            reads: AtomicUsize::new(0),
        };
        let view = resident.with_disk(Some(&disk)).with_resident_only(0);
        let mut accepted = None;
        assert!(view.visit_fragment_candidates(bad.key(), &mut |record| {
            let valid =
                record.matches(1, "exact source") && record.payload() == b"accepted parser payload";
            if valid {
                accepted = Some(Arc::clone(record));
            }
            valid
        }));
        assert!(Arc::ptr_eq(&accepted.unwrap(), &disk.record));
        assert_eq!(disk.reads.load(Ordering::Relaxed), 1);
        // A validated disk answer is promoted without publication.
        assert!(
            view.visit_fragment_candidates(bad.key(), &mut |record| record.payload()
                == b"accepted parser payload")
        );
        assert_eq!(disk.reads.load(Ordering::Relaxed), 1);
    }
    #[test]
    fn few_resident_misses_skip_the_disk_and_many_reach_it() {
        let resident = ResidentMemo::default();
        let disk = Disk {
            record: fragment(b"on disk"),
            reads: AtomicUsize::new(0),
        };
        let view = resident.with_disk(Some(&disk)).with_resident_only(2);
        let key = disk.record.key();
        for _ in 0..2 {
            assert!(!view.visit_fragment_candidates(key, &mut |_| true));
        }
        assert_eq!(disk.reads.load(Ordering::Relaxed), 0);
        assert!(view.visit_fragment_candidates(key, &mut |_| true));
        assert_eq!(disk.reads.load(Ordering::Relaxed), 1);
    }
    #[test]
    fn oversized_record_preserves_existing_candidates_and_variant_order_is_bounded() {
        let mut store = Store::default();
        let small = fragment(b"small");
        store.insert(Record::Fragment(Arc::clone(&small)));
        let large = fragment(&vec![0; KIND_BUDGET]);
        store.insert(Record::Fragment(large));
        assert_eq!(store.count, 1);
        for index in 0..8u8 {
            store.insert(Record::Fragment(fragment(&[index])));
        }
        assert_eq!(store.count, 4);
        let payloads = store
            .records
            .values()
            .flatten()
            .map(|stored| match &stored.record {
                Record::Fragment(r) => r.payload()[0],
                _ => unreachable!(),
            })
            .collect::<Vec<_>>();
        assert_eq!(payloads, [4, 5, 6, 7]);
        assert!(store.total <= TOTAL_BUDGET);
        assert!(store.sizes.iter().all(|bytes| *bytes <= KIND_BUDGET));
    }
}
