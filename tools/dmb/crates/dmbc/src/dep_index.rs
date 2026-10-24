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
}

/// Disabled by `DMB_DEP_INDEX=0`.
pub fn enabled() -> bool {
    static ENABLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ENABLED.get_or_init(|| std::env::var_os("DMB_DEP_INDEX").is_none_or(|value| value != "0"))
}

/// The id of one stored record: its full key and every recorded read, exactly as stored.
pub fn record_id<'a>(
    key: &[u8],
    reads: impl IntoIterator<Item = (&'a ResolveQuery, &'a [u8])>,
) -> u128 {
    use std::hash::{Hash, Hasher};
    let mut hasher = xxhash_rust::xxh3::Xxh3::new();
    hasher.update(b"dm-dep-index-record-v1\0");
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

/// What `adopt` decided about one record.
pub enum Adoption {
    /// Nothing to do: no world, already carrying the world's receipt, or no room for one.
    None,
    /// The index certified the record; its receipt now names this (the current) world.
    Certified { world: u128 },
    /// Not certified: if its reads pass, `DepIndex::note` records it.
    Pending { world: u128, id: u128 },
}

impl DepIndex {
    pub fn new(disk: Arc<crate::runner_disk::LazyDisk>, policy: u128) -> Self {
        Self {
            disk,
            policy,
            worlds: Mutex::new(HashMap::new()),
            counts: IndexCounts::default(),
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
        let Some(world) = host.domain_version(ReadDomain::Tree) else {
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
        format!(
            "offered={} certified={} noted={} loaded={} already_current={} no_world={} roster_full={} contradicted={}",
            self.counts.offered.load(Ordering::Relaxed),
            self.counts.certified.load(Ordering::Relaxed),
            self.counts.noted.load(Ordering::Relaxed),
            self.counts.loaded.load(Ordering::Relaxed),
            self.counts.already_current.load(Ordering::Relaxed),
            self.counts.no_world.load(Ordering::Relaxed),
            self.counts.roster_full.load(Ordering::Relaxed),
            self.counts.contradicted.load(Ordering::Relaxed)
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
        fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
            (domain == ReadDomain::Tree).then_some(self.0).flatten()
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
