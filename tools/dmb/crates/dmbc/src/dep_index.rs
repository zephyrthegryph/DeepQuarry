//! Persisted dependency index: which stored lowering records were proven current under which
//! world, so a fresh session accepts them without replaying their reads.
//!
//! A disk lowering record carries the `(Tree, version)` receipt of the world it was written
//! under. A record admitted later under a different world has to replay every read against the
//! current tree, in every new process, because nothing remembered that the replay had passed.
//! The index remembers it: per world (the content-derived `Tree` domain version of the request's
//! resolver: declarations, scalar answers and procedure statics) it holds the set of record ids
//! (hash of the record key and its recorded reads) whose `Tree` reads were checked equal. A
//! later request under the same world treats such a record as if it carried that world's receipt.
//!
//! Storage is one record per world in the shared compiler cache (`dm_cache`), so the cache's
//! size and age caps (`daemon::cache_gc`) bound it and a segment that served an index is touched
//! like any other. The record holds the whole set (loaded plus new ids); a request that adds
//! nothing writes nothing. Everything here is a hint: an unreadable, missing or foreign record
//! only costs the replay it would have saved, and `DMB_DEP_INDEX=0` turns it off.
use dm_ir::{ReadDomain, ResolveQuery, Resolver};
use std::{
    collections::{HashMap, HashSet},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
};

/// Cache stage number of an index record (ABI uses 9 and 10, lowering 2).
const STAGE: u32 = 31;
const VERSION: u32 = 1;
const MAGIC: &[u8; 8] = b"dmbdepx1";
/// A world's set never grows past this many ids (16 bytes each); further ids are not recorded.
const MAX_IDS: usize = 1 << 21;

/// Counters shown on the lowering memo summary line.
#[derive(Default)]
pub struct IndexCounts {
    /// Records admitted by the index without replaying their `Tree` reads.
    pub certified: AtomicU64,
    /// Records whose reads were replayed and passed, newly noted for the next session.
    pub noted: AtomicU64,
    /// Ids loaded from disk for the worlds this request used.
    pub loaded: AtomicU64,
    /// Records offered to `adopt`, and why the index did not decide them.
    pub offered: AtomicU64,
    pub no_world: AtomicU64,
    pub already_current: AtomicU64,
    pub roster_full: AtomicU64,
    /// Certified records whose reads then differed: a certificate that should have held.
    pub contradicted: AtomicU64,
}

/// What one stage did with the records it offered the index.
#[derive(Default)]
pub struct StageCounts {
    /// Records taken as current without resolving the reads the world fixes.
    pub certified: AtomicU64,
    /// Records whose reads were all replayed and passed.
    pub replayed: AtomicU64,
    /// Certified records whose stored answers a replay then contradicted.
    pub contradicted: AtomicU64,
    /// Reads of a certified record answered by the typed sidecar, and reads that had none.
    pub typed: AtomicU64,
    pub untyped: AtomicU64,
    /// Records computed (not replayed) this request and noted as current when they were staged.
    pub staged: AtomicU64,
    /// Untyped reads by query kind and the answer's kind (`DMB_DEP_INDEX_KINDS=1`).
    kinds: Mutex<std::collections::BTreeMap<(String, &'static str), u64>>,
}

struct WorldSet {
    key: dm_cache::RecordKey,
    loaded: HashSet<u128>,
    fresh: Mutex<HashSet<u128>>,
}

pub struct DepIndex {
    disk: Arc<crate::runner_disk::LazyDisk>,
    policy: u128,
    worlds: Mutex<HashMap<u128, Arc<WorldSet>>>,
    pub counts: IndexCounts,
    abi: StageCounts,
    initializer: StageCounts,
}

/// `DMB_DEP_INDEX_VERIFY=1`: certified ABI and initializer records are replayed anyway and a
/// read that differs from its stored answer is counted as a contradiction.
pub fn verify() -> bool {
    static VERIFY: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *VERIFY.get_or_init(|| std::env::var_os("DMB_DEP_INDEX_VERIFY").is_some_and(|value| value == "1"))
}

/// `DMB_DEP_INDEX_KINDS=1`: break the reads without a portable answer down by query and answer kind.
fn kinds_enabled() -> bool {
    static KINDS: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *KINDS.get_or_init(|| std::env::var_os("DMB_DEP_INDEX_KINDS").is_some_and(|value| value == "1"))
}

/// Disabled by `DMB_DEP_INDEX=0`.
pub fn enabled() -> bool {
    static ENABLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ENABLED.get_or_init(|| std::env::var_os("DMB_DEP_INDEX").is_none_or(|value| value != "0"))
}

/// The id of one stored lowering record: its full key and every recorded read, exactly as stored.
pub fn record_id<'a>(
    key: &[u8],
    reads: impl IntoIterator<Item = (&'a ResolveQuery, &'a [u8])>,
) -> u128 {
    record_id_in(Scope::Lowering, key, reads)
}

/// Which stage's records an id names. A stage's key bytes never collide with another's, but the
/// ids share one set per world, so each stage hashes its own tag into them.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Scope {
    Lowering,
    Abi,
    Initializer,
}
impl Scope {
    fn tag(self) -> &'static [u8] {
        match self {
            // Lowering ids predate scopes; they keep their original bytes.
            Scope::Lowering => b"",
            Scope::Abi => b"abi\0",
            Scope::Initializer => b"initializer\0",
        }
    }
}

/// `record_id` for a record of `scope`.
pub fn record_id_in<'a>(
    scope: Scope,
    key: &[u8],
    reads: impl IntoIterator<Item = (&'a ResolveQuery, &'a [u8])>,
) -> u128 {
    use std::hash::{Hash, Hasher};
    let mut hasher = xxhash_rust::xxh3::Xxh3::new();
    hasher.update(b"dm-dep-index-record-v1\0");
    hasher.update(scope.tag());
    hasher.update(&(key.len() as u64).to_le_bytes());
    hasher.update(key);
    for (query, answer) in reads {
        let mut low = std::collections::hash_map::DefaultHasher::new();
        (0u8, query).hash(&mut low);
        let mut high = std::collections::hash_map::DefaultHasher::new();
        (1u8, query).hash(&mut high);
        hasher.update(&low.finish().to_le_bytes());
        hasher.update(&high.finish().to_le_bytes());
        hasher.update(&(answer.len() as u64).to_le_bytes());
        hasher.update(answer);
    }
    hasher.digest128()
}

/// Whether a read in `domain` is fixed by the world: declarations, scalar answers and procedure
/// statics (the `Tree` domain version and everything issued over it). Engine catalogs and the
/// filesystem are not, so those reads are always checked.
pub fn world_determines(domain: ReadDomain) -> bool {
    !matches!(
        domain,
        ReadDomain::ResourceSearch
            | ReadDomain::PredefinedCatalog(_)
            | ReadDomain::RuntimeCatalog(_)
    )
}

/// Replay the stored reads of an ABI or initializer record against `provider` and return the
/// current answers it holds under, or `None` when one differs.
///
/// A record whose id the index holds for the provider's world (and `DMB_DEP_INDEX_VERIFY` is not
/// set) takes the typed sidecar answer of every read the world fixes, so those reads resolve no
/// query and issue no domain version. Every other read resolves and compares its canonical bytes
/// exactly as a replay without an index does. A record that passes unrecorded is noted so the
/// next session certifies it. `typed` may be shorter than `reads` (an untyped read resolves).
pub fn replay_reads(
    index: Option<&DepIndex>,
    scope: Scope,
    provider: &dyn Resolver,
    key: &[u8],
    reads: &[(ResolveQuery, Vec<u8>)],
    typed: &[Option<dm_ir::PortableResolvedAnswer>],
) -> Option<Vec<crate::lowering_memo::ResolverRead>> {
    let certificate = index.and_then(|index| {
        let world = DepIndex::world_of(provider)?;
        let id = record_id_in(
            scope,
            key,
            reads.iter().map(|(query, answer)| (query, answer.as_slice())),
        );
        Some((index, world, id, index.certified(world, id)))
    });
    let known = certificate.is_some_and(|(_, _, _, known)| known);
    let trusted = known && !verify();
    let mut current = Vec::with_capacity(reads.len());
    for (position, (query, expected)) in reads.iter().enumerate() {
        let domain = query.domain();
        let mut counted_untyped: Option<&DepIndex> = None;
        if trusted && world_determines(domain) {
            let answer = typed
                .get(position)
                .and_then(Option::as_ref)
                .and_then(dm_ir::PortableResolvedAnswer::restore)
                .filter(|answer| answer.canonical_bytes() == *expected);
            if let Some(answer) = answer {
                if let Some((index, ..)) = certificate {
                    index.stage(scope).typed.fetch_add(1, Ordering::Relaxed);
                }
                current.push(crate::lowering_memo::ResolverRead {
                    query: *query,
                    domain,
                    answer,
                });
                continue;
            }
            if let Some((index, ..)) = certificate {
                index.stage(scope).untyped.fetch_add(1, Ordering::Relaxed);
                counted_untyped = Some(index);
            }
        }
        let answer = provider.resolve(*query);
        if let Some(index) = counted_untyped.take().filter(|_| kinds_enabled()) {
            index.stage(scope).note_kind(query, &answer);
        }
        if !crate::lowering_memo_wire::initializer::portable(&answer)
            || answer.canonical_bytes() != *expected
        {
            if let Some((index, ..)) = certificate.filter(|_| known && world_determines(domain)) {
                index.contradicts(scope, query);
            }
            return None;
        }
        current.push(crate::lowering_memo::ResolverRead {
            query: *query,
            domain,
            answer,
        });
    }
    if let Some((index, world, id, known)) = certificate {
        if trusted {
            index.stage(scope).certified.fetch_add(1, Ordering::Relaxed);
        } else if known {
            index.stage(scope).replayed.fetch_add(1, Ordering::Relaxed);
        } else {
            index.passed(scope, world, id);
        }
    }
    Some(current)
}

/// A record of `scope` was just computed by resolving through `provider`, so its reads are
/// current under the provider's world: note it now, and the very next session certifies it
/// instead of waiting for a replay to pass first.
pub fn staged(
    index: Option<&DepIndex>,
    scope: Scope,
    provider: Option<&dyn Resolver>,
    key: &[u8],
    reads: &[(ResolveQuery, Vec<u8>)],
) {
    let (Some(index), Some(provider)) = (index, provider) else {
        return;
    };
    let Some(world) = DepIndex::world_of(provider) else {
        return;
    };
    let id = record_id_in(
        scope,
        key,
        reads.iter().map(|(query, answer)| (query, answer.as_slice())),
    );
    index.stage(scope).staged.fetch_add(1, Ordering::Relaxed);
    index.note(world, id);
}

/// What `adopt` decided about one record.
pub enum Adoption {
    /// Nothing to do: no world, already carrying the world's receipt, or no room for one.
    None,
    /// The index certified the record; its receipt now names this (the current) world.
    Certified { world: u128 },
    /// Not certified: if its reads pass, `DepIndex::note` records it.
    Pending { world: u128, id: u128 },
}

impl StageCounts {
    fn note_kind(&self, query: &ResolveQuery, answer: &dm_ir::ResolvedMeaning) {
        use dm_ir::ResolvedMeaning as M;
        let text = format!("{query:?}");
        let end = text
            .find(|c: char| c == '(' || c == ' ' || c == '{')
            .unwrap_or(text.len());
        let answer = match answer {
            M::ProcedureStatic(_) => "ProcedureStatic",
            M::Unsupported(_) => "Unsupported",
            M::Missing => "Missing",
            M::Presence(_) => "Presence",
            M::DeclaredType(_) => "DeclaredType",
            M::InstanceField { .. } => "InstanceField",
            M::Value(_) => "Value",
            M::Slot { .. } => "Slot",
            M::Symbol(_) => "Symbol",
            M::Symbols(_) => "Symbols",
            M::Members(_) => "Members",
            M::IntrinsicProc { .. } => "IntrinsicProc",
            M::RetainedProc { .. } => "RetainedProc",
            M::Member { .. } => "Member",
            M::Resource { .. } => "Resource",
            M::Declaration { .. } => "Declaration",
        };
        let mut kinds = self.kinds.lock().unwrap_or_else(|error| error.into_inner());
        *kinds.entry((text[..end].to_owned(), answer)).or_default() += 1;
    }
}

impl DepIndex {
    pub fn new(disk: Arc<crate::runner_disk::LazyDisk>, policy: u128) -> Self {
        Self {
            disk,
            policy,
            worlds: Mutex::new(HashMap::new()),
            counts: IndexCounts::default(),
            abi: StageCounts::default(),
            initializer: StageCounts::default(),
        }
    }
    /// The counters of an ABI or initializer stage.
    pub fn stage(&self, scope: Scope) -> &StageCounts {
        match scope {
            Scope::Abi => &self.abi,
            _ => &self.initializer,
        }
    }
    /// The world a request's reads are judged under: the resolver's answer world.
    pub fn world_of(resolver: &dyn Resolver) -> Option<u128> {
        resolver.answer_world()
    }
    /// A stored ABI or initializer record's reads were replayed and passed under `world`:
    /// remember it for the next session (nothing to do for a record already known).
    pub fn passed(&self, scope: Scope, world: u128, id: u128) {
        self.stage(scope).replayed.fetch_add(1, Ordering::Relaxed);
        self.note(world, id);
    }
    /// A certified ABI or initializer record's stored answer differed from the current one.
    pub fn contradicts(&self, scope: Scope, query: &ResolveQuery) {
        if self
            .stage(scope)
            .contradicted
            .fetch_add(1, Ordering::Relaxed)
            < 8
        {
            crate::daemon_eprintln!(
                "native dependency index: certified {scope:?} record contradicted by {query:?}"
            );
        }
    }
    fn record_key(&self, world: u128) -> dm_cache::RecordKey {
        let mut locator = Vec::with_capacity(32);
        locator.extend_from_slice(&self.policy.to_le_bytes());
        locator.extend_from_slice(&world.to_le_bytes());
        dm_cache::RecordKey {
            stage: STAGE,
            version: VERSION,
            content: xxhash_rust::xxh3::xxh3_128(&locator),
        }
    }
    fn world(&self, world: u128) -> Arc<WorldSet> {
        let mut worlds = self
            .worlds
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(set) = worlds.get(&world) {
            return Arc::clone(set);
        }
        let key = self.record_key(world);
        let loaded = self.load(key, world);
        self.counts
            .loaded
            .fetch_add(loaded.len() as u64, Ordering::Relaxed);
        let set = Arc::new(WorldSet {
            key,
            loaded,
            fresh: Mutex::new(HashSet::new()),
        });
        worlds.insert(world, Arc::clone(&set));
        set
    }
    fn load(&self, key: dm_cache::RecordKey, world: u128) -> HashSet<u128> {
        let ids = std::cell::RefCell::new(HashSet::new());
        if let Some(snapshot) = self.disk.snapshot() {
            snapshot.get_candidate(key, |bytes, symbols| {
                if !symbols.is_empty() {
                    return Err("dependency index spelling sidecar".into());
                }
                let mut found = HashSet::new();
                for variant in dm_cache::decode_variants(bytes)? {
                    // The world and policy are in the payload too: a hash collision on the
                    // bucket locator must not certify another world's records.
                    let rest = variant
                        .strip_prefix(MAGIC.as_slice())
                        .and_then(|rest| rest.strip_prefix(self.policy.to_le_bytes().as_slice()))
                        .and_then(|rest| rest.strip_prefix(world.to_le_bytes().as_slice()))
                        .ok_or("dependency index header")?;
                    if rest.len() % 16 != 0 || rest.len() / 16 > MAX_IDS {
                        return Err("dependency index size".into());
                    }
                    found.extend(
                        rest.chunks_exact(16)
                            .map(|chunk| u128::from_le_bytes(chunk.try_into().expect("16 bytes"))),
                    );
                }
                *ids.borrow_mut() = found;
                Ok(true)
            });
        }
        ids.into_inner()
    }
    /// Whether `id` was proven current under `world` by this or an earlier session.
    pub fn certified(&self, world: u128, id: u128) -> bool {
        let set = self.world(world);
        set.loaded.contains(&id)
            || set
                .fresh
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .contains(&id)
    }
    /// Remember that `id`'s reads passed under `world`.
    pub fn note(&self, world: u128, id: u128) {
        let set = self.world(world);
        if set.loaded.contains(&id) {
            return;
        }
        let mut fresh = set.fresh.lock().unwrap_or_else(|error| error.into_inner());
        if set.loaded.len() + fresh.len() < MAX_IDS && fresh.insert(id) {
            self.counts.noted.fetch_add(1, Ordering::Relaxed);
        }
    }
    /// Decide how a stored record with `versions` and `id` meets the current `host`.
    /// `versions` is the record's receipt list; on `Certified` the `Tree` entry is set to the
    /// current world's version, so every later check treats the record as written under it.
    pub fn adopt<R: Resolver>(
        &self,
        host: &R,
        versions: &mut Vec<(ReadDomain, u128)>,
        id: impl FnOnce() -> u128,
    ) -> Adoption {
        self.counts.offered.fetch_add(1, Ordering::Relaxed);
        let Some(world) = host.answer_world() else {
            self.counts.no_world.fetch_add(1, Ordering::Relaxed);
            return Adoption::None;
        };
        let slot = versions
            .iter()
            .position(|(domain, _)| *domain == ReadDomain::Tree);
        if slot.is_some_and(|slot| versions[slot].1 == world) {
            self.counts.already_current.fetch_add(1, Ordering::Relaxed);
            return Adoption::None;
        }
        if slot.is_none() && versions.len() >= 2 {
            self.counts.roster_full.fetch_add(1, Ordering::Relaxed);
            return Adoption::None;
        }
        let id = id();
        if self.certified(world, id) {
            match slot {
                Some(slot) => versions[slot].1 = world,
                None => versions.push((ReadDomain::Tree, world)),
            }
            self.counts.certified.fetch_add(1, Ordering::Relaxed);
            return Adoption::Certified { world };
        }
        Adoption::Pending { world, id }
    }
    /// Persist the ids this request added, per world. Called once after a successful compile.
    pub fn flush(&self) {
        let worlds: Vec<(u128, Arc<WorldSet>)> = self
            .worlds
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .iter()
            .map(|(world, set)| (*world, Arc::clone(set)))
            .collect();
        let mut records = Vec::new();
        for (world, set) in worlds {
            let fresh = set.fresh.lock().unwrap_or_else(|error| error.into_inner());
            if fresh.is_empty() {
                continue;
            }
            let mut ids: Vec<u128> = set.loaded.iter().chain(fresh.iter()).copied().collect();
            ids.sort_unstable();
            let mut payload = Vec::with_capacity(MAGIC.len() + 32 + ids.len() * 16);
            payload.extend_from_slice(MAGIC);
            payload.extend_from_slice(&self.policy.to_le_bytes());
            payload.extend_from_slice(&world.to_le_bytes());
            for id in &ids {
                payload.extend_from_slice(&id.to_le_bytes());
            }
            let Ok(bytes) = dm_cache::encode_variants(&[payload]) else {
                continue;
            };
            records.push(dm_cache::Record {
                key: set.key,
                symbols: Vec::new(),
                payload: bytes.into(),
            });
        }
        if records.is_empty() {
            return;
        }
        if let Err(error) = self.disk.append_records(records) {
            crate::daemon_eprintln!("native dependency index not stored: {error}");
        }
    }
    /// A certified record failed a read check: count it and name the first few queries.
    pub fn contradicted(&self, query: &ResolveQuery) {
        if self.counts.contradicted.fetch_add(1, Ordering::Relaxed) < 8 {
            crate::daemon_eprintln!(
                "native dependency index: certified record contradicted by {query:?}"
            );
        }
    }
    pub fn summary(&self) -> String {
        let stage = |name: &str, counts: &StageCounts| {
            let kinds = counts
                .kinds
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .iter()
                .map(|((query, answer), count)| format!(" {query}->{answer}:{count}"))
                .collect::<String>();
            format!(
                " {name}[certified={} replayed={} contradicted={} typed={} untyped={} staged={}{kinds}]",
                counts.certified.load(Ordering::Relaxed),
                counts.replayed.load(Ordering::Relaxed),
                counts.contradicted.load(Ordering::Relaxed),
                counts.typed.load(Ordering::Relaxed),
                counts.untyped.load(Ordering::Relaxed),
                counts.staged.load(Ordering::Relaxed)
            )
        };
        format!(
            "offered={} certified={} noted={} loaded={} already_current={} no_world={} roster_full={} contradicted={}{}{}",
            self.counts.offered.load(Ordering::Relaxed),
            self.counts.certified.load(Ordering::Relaxed),
            self.counts.noted.load(Ordering::Relaxed),
            self.counts.loaded.load(Ordering::Relaxed),
            self.counts.already_current.load(Ordering::Relaxed),
            self.counts.no_world.load(Ordering::Relaxed),
            self.counts.roster_full.load(Ordering::Relaxed),
            self.counts.contradicted.load(Ordering::Relaxed),
            stage("abi", &self.abi),
            stage("initializer", &self.initializer)
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{ResolvedMeaning, SymbolId};

    struct Versioned(Option<u128>);
    impl Resolver for Versioned {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Unsupported(query)
        }
        fn answer_world(&self) -> Option<u128> {
            self.0
        }
    }
    fn scratch(label: &str) -> std::path::PathBuf {
        crate::test_scratch::dir(label)
    }
    fn persist(index: &DepIndex) {
        index.flush();
        index.disk.finish_batch().unwrap();
    }
    fn index(root: &std::path::Path) -> DepIndex {
        DepIndex::new(
            Arc::new(crate::runner_disk::LazyDisk::new(root.to_path_buf())),
            7,
        )
    }

    #[test]
    fn record_id_depends_on_key_queries_and_answers() {
        let q = ResolveQuery::Type(SymbolId::of("/obj"));
        let r = ResolveQuery::Type(SymbolId::of("/mob"));
        let a = record_id(b"k", [(&q, b"1".as_slice())]);
        assert_eq!(a, record_id(b"k", [(&q, b"1".as_slice())]));
        assert_ne!(a, record_id(b"j", [(&q, b"1".as_slice())]));
        assert_ne!(a, record_id(b"k", [(&r, b"1".as_slice())]));
        assert_ne!(a, record_id(b"k", [(&q, b"2".as_slice())]));
        assert_ne!(
            a,
            record_id(b"k", [(&q, b"1".as_slice()), (&r, b"1".as_slice())])
        );
    }

    #[test]
    fn noted_ids_persist_per_world_and_certify_in_a_new_session() {
        let root = scratch("dep-index-persist");
        let first = index(&root);
        let host = Versioned(Some(100));
        let mut versions = vec![(ReadDomain::Tree, 5)];
        let Adoption::Pending { world, id } = first.adopt(&host, &mut versions, || 42) else {
            panic!("an unknown record is pending");
        };
        assert_eq!(
            (world, id, versions[0].1),
            (100, 42, 5),
            "pending leaves the receipt alone"
        );
        first.note(world, id);
        persist(&first);
        drop(first);

        let second = index(&root);
        let mut versions = vec![(ReadDomain::Tree, 5)];
        assert!(matches!(
            second.adopt(&host, &mut versions, || 42),
            Adoption::Certified { .. }
        ));
        assert_eq!(versions, vec![(ReadDomain::Tree, 100)]);
        // Another record, another world, and a resolver without a version are never certified.
        let mut versions = vec![(ReadDomain::Tree, 5)];
        assert!(matches!(
            second.adopt(&host, &mut versions, || 43),
            Adoption::Pending { .. }
        ));
        assert!(matches!(
            second.adopt(&Versioned(Some(101)), &mut versions, || 42),
            Adoption::Pending { .. }
        ));
        assert!(matches!(
            second.adopt(&Versioned(None), &mut versions, || 42),
            Adoption::None
        ));
    }

    #[test]
    fn a_receipt_already_naming_the_world_and_a_full_roster_are_left_alone() {
        let root = scratch("dep-index-skip");
        let index = index(&root);
        let host = Versioned(Some(9));
        let mut same = vec![(ReadDomain::Tree, 9)];
        assert!(matches!(
            index.adopt(&host, &mut same, || 1),
            Adoption::None
        ));
        let mut full = vec![
            (ReadDomain::ResourceSearch, 1),
            (ReadDomain::OwnerHierarchy(SymbolId::of("/")), 2),
        ];
        assert!(matches!(
            index.adopt(&host, &mut full, || 1),
            Adoption::None
        ));
        assert_eq!(full.len(), 2);
    }

    #[test]
    fn a_receipt_without_a_tree_entry_gains_one_when_certified() {
        let root = scratch("dep-index-add");
        let first = index(&root);
        first.note(3, 77);
        persist(&first);
        let second = index(&root);
        let mut versions = vec![(ReadDomain::ResourceSearch, 1)];
        assert!(matches!(
            second.adopt(&Versioned(Some(3)), &mut versions, || 77),
            Adoption::Certified { .. }
        ));
        assert_eq!(
            versions,
            vec![(ReadDomain::ResourceSearch, 1), (ReadDomain::Tree, 3)]
        );
    }

    struct Counting {
        resolves: std::sync::atomic::AtomicUsize,
        answer: ResolvedMeaning,
    }
    impl Resolver for Counting {
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            self.resolves.fetch_add(1, Ordering::Relaxed);
            self.answer.clone()
        }
        fn answer_world(&self) -> Option<u128> {
            Some(11)
        }
    }
    fn counting(answer: ResolvedMeaning) -> Counting {
        Counting {
            resolves: Default::default(),
            answer,
        }
    }

    #[test]
    fn replay_reads_certifies_the_second_session_and_skips_the_world_fixed_resolves() {
        let root = scratch("dep-index-replay");
        let world_read = ResolveQuery::GlobalProc(SymbolId::of("absent"));
        let catalog_read = ResolveQuery::ResourceIn {
            path: SymbolId::of("a.dmi"),
            search_context: 0,
        };
        let reads = vec![
            (world_read, ResolvedMeaning::Missing.canonical_bytes()),
            (catalog_read, ResolvedMeaning::Missing.canonical_bytes()),
        ];
        let typed = vec![Some(dm_ir::PortableResolvedAnswer::Missing); 2];
        let provider = counting(ResolvedMeaning::Missing);

        let first = index(&root);
        let current =
            replay_reads(Some(&first), Scope::Abi, &provider, b"k", &reads, &typed).unwrap();
        assert_eq!(current.len(), 2);
        assert_eq!(provider.resolves.load(Ordering::Relaxed), 2, "unknown record replays");
        persist(&first);
        drop(first);

        let second = index(&root);
        let current =
            replay_reads(Some(&second), Scope::Abi, &provider, b"k", &reads, &typed).unwrap();
        assert_eq!(current[0].answer, ResolvedMeaning::Missing);
        assert_eq!(current[0].domain, world_read.domain());
        // The world-fixed read came from the sidecar; the resource read resolved again.
        assert_eq!(provider.resolves.load(Ordering::Relaxed), 3);
        assert_eq!(second.stage(Scope::Abi).certified.load(Ordering::Relaxed), 1);
        // Another scope's id is a different record: it replays everything.
        replay_reads(Some(&second), Scope::Initializer, &provider, b"k", &reads, &typed).unwrap();
        assert_eq!(provider.resolves.load(Ordering::Relaxed), 5);
        // A sidecar that disagrees with the stored bytes is not trusted.
        let wrong = vec![Some(dm_ir::PortableResolvedAnswer::Presence(true)); 2];
        replay_reads(Some(&second), Scope::Abi, &provider, b"k", &reads, &wrong).unwrap();
        assert_eq!(provider.resolves.load(Ordering::Relaxed), 7);
        assert_eq!(second.stage(Scope::Abi).untyped.load(Ordering::Relaxed), 1);
        // A changed answer fails whatever the index holds, and a certified world read that
        // is resolved and differs is counted as a contradiction.
        let changed = counting(ResolvedMeaning::Presence(true));
        assert!(replay_reads(Some(&second), Scope::Abi, &changed, b"k", &reads, &[]).is_none());
        assert_eq!(second.stage(Scope::Abi).contradicted.load(Ordering::Relaxed), 1);
        assert!(replay_reads(None, Scope::Abi, &changed, b"k", &reads, &typed).is_none());
    }

    #[test]
    fn a_policy_change_or_a_corrupt_record_certifies_nothing() {
        let root = scratch("dep-index-foreign");
        let first = index(&root);
        first.note(3, 77);
        persist(&first);
        let other = DepIndex::new(Arc::new(crate::runner_disk::LazyDisk::new(root.clone())), 8);
        assert!(!other.certified(3, 77));
    }
}
