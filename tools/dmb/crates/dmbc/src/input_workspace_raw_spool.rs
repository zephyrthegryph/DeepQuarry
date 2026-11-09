use super::*;
use crate::{
    query_db::{NativeQueryOwnerIdentity, QueryDb},
    runner_host::workspace_discovery::DiscoveryReceipt,
    selected_report_spool::{Sealed, Stage},
};
use dq_analyze::captured_generator_budget::Budget;
use std::{io::{Read, Write}, ops::Range, sync::{Arc, Mutex, Weak}};

const HEADER: &[u8] = b"DQ-RAW-WORKSPACE\x01";
const FILE: u8 = 1;

struct Entry {
    ordinal: usize,
    frame: Range<u64>,
    stamp: Stamp,
    content: u128,
}

pub(crate) struct WorkspaceRawSpoolBuilder {
    discovery: Arc<DiscoveryReceipt>,
    recorder: Arc<()>,
    queries: NativeQueryOwnerIdentity,
    entries: Vec<Entry>,
    spool: Stage,
}

pub(crate) struct WorkspaceRawSpool {
    discovery: Arc<DiscoveryReceipt>,
    recorder: Arc<()>,
    queries: NativeQueryOwnerIdentity,
    entries: Vec<Entry>,
    spool: Mutex<Sealed>,
}

#[derive(Clone)]
pub(crate) struct WorkspaceRawSpoolIdentity {
    // Weak is the real sealed owner, never an invented SharedBytes or source lease.
    owner: Weak<WorkspaceRawSpool>,
    ordinal: usize,
}

impl WorkspaceRawSpoolIdentity {
    pub(crate) fn same_live(&self, other: &Self) -> bool {
        self.ordinal == other.ordinal && self.owner.ptr_eq(&other.owner)
            && self.owner.strong_count() != 0
    }

    pub(crate) fn metadata_charge(&self) -> usize {
        std::mem::size_of::<WorkspaceRawSpool>() + 2 * std::mem::size_of::<usize>()
    }
}

impl WorkspaceRawSpoolBuilder {
    /// Private Full Registry capture only, under the existing source gate.
    /// The budget pays the exact maximum frame directory before allocation.
    pub(crate) fn new<P: SnapshotProvider>(
        inputs: &RecordingInputs<P>, discovery: Arc<DiscoveryReceipt>, queries: &QueryDb,
        capacity: usize, budget: &Budget, cache: &Path,
    ) -> io::Result<Self> {
        discovery.validate_recording(inputs)?;
        let bytes = capacity.checked_mul(std::mem::size_of::<Entry>())
            .and_then(|n| n.checked_add(Self::capture_fixed()))
            .ok_or(io::ErrorKind::OutOfMemory)?;
        budget.charge(bytes).map_err(quota)?;
        let mut spool = Stage::new(cache)?;
        spool.write_all(HEADER)?;
        Ok(Self {
            discovery, recorder: Arc::clone(&inputs.source_issuer),
            queries: queries.native_query_owner_identity(),
            entries: exact_vec(capacity)?, spool,
        })
    }

    /// The caller already made the existing path/alias/noncompiled decision.
    /// Fixed roles and the UI dispatcher stay on their existing accessors.
    /// Recorder fact coordination is funded/settled by the surrounding capture.
    pub(crate) fn append_actual<P: SnapshotProvider>(
        &mut self, inputs: &RecordingInputs<P>, ordinal: usize, budget: &Arc<Budget>,
    ) -> io::Result<Option<FileInput>> {
        if !Arc::ptr_eq(&self.recorder, &inputs.source_issuer) {
            return Err(invalid("raw workspace spool belongs to another recorder"));
        }
        if self.entries.len() == self.entries.capacity()
            || self.entries.last().is_some_and(|entry| entry.ordinal >= ordinal)
        {
            return Err(invalid("raw workspace spool entry exceeds its exact selected roster"));
        }
        let path = self.discovery.files().get(ordinal)
            .ok_or_else(|| invalid("raw workspace spool ordinal absent from actual discovery"))?;
        let raw = Budget::scoped_temporaries(budget).map_err(quota)?;
        let result = inputs.read_policy_vec_admitted(path, budget.remaining(),
            &mut |capacity| raw.charge(capacity).map_err(quota));
        let Some(bytes) = result? else { return Ok(None); };
        let fact = inputs.recorded_file_fact(path)?;
        if fact.stamp.size != bytes.len() as u64
            || fact.content != xxhash_rust::xxh3::xxh3_128(&bytes)
        {
            return Err(invalid("raw workspace spool file fact differs from actual read"));
        }
        let start = self.spool.length();
        self.spool.write_all(&[FILE])?;
        self.spool.write_all(&bytes)?;
        let end = self.spool.length();
        self.entries.push(Entry {
            ordinal, frame: start..end, stamp: fact.stamp.clone(), content: fact.content,
        });
        drop((bytes, raw));
        Ok(Some(fact))
    }

    fn capture_fixed() -> usize {
        // The live builder has a streaming hash while the sealed owner does
        // not. Prepay both controls through the one-way seal handoff.
        std::mem::size_of::<Self>() + std::mem::size_of::<WorkspaceRawSpool>()
            + 2 * std::mem::size_of::<usize>()
    }

    pub(crate) fn live_capture_bytes(&self) -> usize {
        Self::capture_fixed() + self.entries.capacity() * std::mem::size_of::<Entry>()
    }

    pub(crate) fn seal(self) -> io::Result<Arc<WorkspaceRawSpool>> {
        let spool = self.spool.seal()?;
        Ok(Arc::new(WorkspaceRawSpool {
            discovery: self.discovery, recorder: self.recorder, queries: self.queries,
            entries: self.entries, spool: Mutex::new(spool),
        }))
    }
}

impl WorkspaceRawSpool {
    pub(crate) fn require_recording<P: SnapshotProvider>(
        &self, inputs: &RecordingInputs<P>, discovery: &Arc<DiscoveryReceipt>, queries: &QueryDb,
    ) -> io::Result<()> {
        if !Arc::ptr_eq(&self.recorder, &inputs.source_issuer)
            || !Arc::ptr_eq(&self.discovery, discovery) || !self.queries.matches(queries)
        {
            return Err(invalid("raw workspace spool belongs to another source/query discovery"));
        }
        self.discovery.validate_recording(inputs)
    }

    pub(crate) fn retained_bytes(&self) -> usize {
        std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>()
            + self.entries.capacity() * std::mem::size_of::<Entry>()
    }

    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        let fixed = std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>();
        visit(self as *const Self as usize, fixed, fixed);
        if self.entries.capacity() != 0 {
            visit(self.entries.as_ptr() as usize, std::mem::size_of_val(self.entries.as_slice()),
                self.entries.capacity() * std::mem::size_of::<Entry>());
        }
    }

    pub(crate) fn identity(self: &Arc<Self>, ordinal: usize, fact: &FileInput)
        -> io::Result<WorkspaceRawSpoolIdentity>
    {
        self.entry(ordinal, fact)?;
        Ok(WorkspaceRawSpoolIdentity { owner: Arc::downgrade(self), ordinal })
    }

    fn entry(&self, ordinal: usize, fact: &FileInput) -> io::Result<&Entry> {
        if self.discovery.files().get(ordinal) != Some(&fact.path) {
            return Err(invalid("raw workspace spool original path differs"));
        }
        let index = self.entries.binary_search_by_key(&ordinal, |entry| entry.ordinal)
            .map_err(|_| invalid("raw workspace spool omitted actual ordinal"))?;
        let entry = &self.entries[index];
        if entry.stamp != fact.stamp || entry.content != fact.content {
            return Err(invalid("raw workspace spool original fact differs"));
        }
        Ok(entry)
    }

    /// Called only behind the matching NativeReadGuard. Source freshness is
    /// supplied by its current capture closure, not by the spool digest.
    /// Read one immutable private frame and release its raw copy before the
    /// normalized page owner crosses the callback.
    pub(crate) fn normalized(
        &self, ordinal: usize, fact: &FileInput, available: usize,
    ) -> io::Result<Option<dm_preprocess::SourceText>> {
        let entry = self.entry(ordinal, fact)?;
        let n = usize::try_from(entry.stamp.size).map_err(|_| io::ErrorKind::OutOfMemory)?;
        if entry.frame.end.checked_sub(entry.frame.start) != entry.stamp.size.checked_add(1) {
            return Err(invalid("raw workspace spool file width differs"));
        }
        // Includes the live raw Vec, its short SharedBytes control and the
        // ordinary normalize helper's measured input-dependent peak.
        let fixed = n.checked_add(8192).ok_or(io::ErrorKind::OutOfMemory)?;
        if fixed > available {
            return Ok(None);
        }
        let mut bytes = exact_vec(n)?;
        bytes.resize(n, 0);
        self.spool.lock().map_err(|_| invalid("raw workspace spool poisoned"))?
            .with_private_frame(entry.frame.start, entry.frame.end, |input| {
                let mut tag = [0];
                input.read_exact(&mut tag)?;
                if tag != [FILE] { return Err(invalid("raw workspace spool file tag differs")); }
                input.read_exact(&mut bytes)
            })?;
        if xxhash_rust::xxh3::xxh3_128(&bytes) != entry.content {
            return Err(invalid("raw workspace spool actual file bytes differ"));
        }
        let normalized = dq_analyze::captured_raw_file::analyze_raw_len(&bytes).map_err(io::Error::other)?;
        let peak = normalized.checked_mul(4).and_then(|size| size.checked_add(fixed))
            .ok_or(io::ErrorKind::OutOfMemory)?;
        if peak > available {
            return Ok(None);
        }
        let bytes: dm_resources::SharedBytes = bytes.into();
        let text = crate::input_snapshot::normalize_recorded_policy_original(
            &RecordedSourceOriginal::Bytes(&bytes));
        drop(bytes);
        Ok(Some(text))
    }
}

fn quota(message: String) -> io::Error { io::Error::new(io::ErrorKind::OutOfMemory, message) }
fn exact_vec<T>(n: usize) -> io::Result<Vec<T>> {
    if n == 0 { return Ok(Vec::new()); }
    let layout = std::alloc::Layout::array::<T>(n).map_err(|_| io::ErrorKind::OutOfMemory)?;
    assert_ne!(layout.size(), 0);
    // SAFETY: one exact nonzero Global allocation, initialized by the caller.
    let ptr = std::ptr::NonNull::new(unsafe { std::alloc::alloc(layout) }.cast::<T>())
        .ok_or(io::ErrorKind::OutOfMemory)?;
    Ok(unsafe { Vec::from_raw_parts(ptr.as_ptr(), 0, n) })
}


#[cfg(test)]
mod tests {
    use super::*;
    use crate::runner_host::workspace_discovery::{discover_check_grep, DiscoveryContract};

    #[test]
    fn sealed_workspace_raw_replays_original_without_reopening_and_rejects_foreign_facts() {
        let root = crate::test_scratch::dir("workspace-raw-spool-actual-root");
        for dir in ["code", "maps", "tgui/packages/tgui/interfaces"] {
            std::fs::create_dir_all(root.join(dir)).unwrap();
        }
        let path = root.join("tgui/packages/tgui/interfaces/Probe.tsx");
        std::fs::write(&path, b"original\r\n\xff\r").unwrap();
        let inputs = RecordingInputs::new(FileSystemInputs, 0);
        let discovery = Arc::new(discover_check_grep(&inputs, DiscoveryContract {
            root: root.clone(),
            recursive_roots: ["code", "maps", "tgui"].map(|dir| root.join(dir)).to_vec(),
        }).unwrap());
        let ordinal = discovery.files().iter().position(|source| source.file_name() == path.file_name()).unwrap();
        let queries = QueryDb::default();
        let budget = Budget::new(1 << 20).unwrap();
        let cache = crate::test_scratch::dir("workspace-raw-spool-actual-scratch");
        let mut build = WorkspaceRawSpoolBuilder::new(&inputs, Arc::clone(&discovery), &queries, 1, &budget, &cache).unwrap();
        let fact = build.append_actual(&inputs, ordinal, &budget).unwrap().unwrap();
        let spool = build.seal().unwrap();
        spool.require_recording(&inputs, &discovery, &queries).unwrap();
        let other = RecordingInputs::new(FileSystemInputs, 0);
        assert!(spool.require_recording(&other, &discovery, &queries).is_err());
        let before = spool.identity(ordinal, &fact).unwrap();
        assert!(before.same_live(&spool.identity(ordinal, &fact).unwrap()));
        assert!(spool.normalized(ordinal, &fact, 10).unwrap().is_none());

        // A replay is from the immutable issued spool. The existing final
        // live restat is independently responsible for refusing publication.
        std::fs::remove_file(&path).unwrap();
        for _ in 0..2 {
            let text = spool.normalized(ordinal, &fact, 1 << 20).unwrap().unwrap();
            assert_eq!(text.as_str(), "original\n\u{fffd}\n");
        }
        let mut changed = fact.clone();
        changed.content ^= 1;
        assert!(spool.normalized(ordinal, &changed, 1 << 20).is_err());
        drop(spool);
        assert!(!before.same_live(&before));
    }
}
