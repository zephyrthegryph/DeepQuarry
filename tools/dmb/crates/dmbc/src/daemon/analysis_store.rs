//! The daemon's `analysis_results` owner (doc/rewrite/proposals/analysis_queries.md, steps 1-5, groups A/B).
//!
//! Hosted `analyze` runs register this as `dq_analyze::incr::Provider`, so `incr::facts/keyed/two_phase/cached` and the per-lint
//! `LintCache`s read and write here instead of `data/analyze-cache/{incr,lint}-*.bin` and the machine-wide `shared.rs` copy.
//! One store per daemon: every worktree session shares it (its usage is reported with the shared store, `shared_store.rs`).
//!
//! * Receipts. An entry is adopted only when its whole key matches: the store (one per lint and phase), the stamp (for a lint's
//!   `LintCache`, that lint's own version from `cache::lint_version`, the scope list hash and the parse flavor; for `incr` stores,
//!   the run stamp), the context key the lint computed from every file's facts and the item's content key. A session asking with
//!   its own inputs gets a value only when those inputs equal the producer's, so sharing changes memory, never output.
//! * Clean results are entries with no bytes (the clean bitmap).
//! * Leases. Each project root holds a lease bit on every entry its latest request used; a new request from that root first drops
//!   its bit everywhere. Past the byte budget (`DMB_ANALYSIS_BUDGET_MB`, default 768) unleased entries go first, oldest first, then
//!   leased ones oldest first.
//! * Persistence. Each changed (store, stamp) slot is written after a request to `E:/dq-cache/analysis/<slot>.bin`
//!   (`DMB_ANALYSIS_DIR`, `off` for none; `[cache.analysis]` in tools/ci/disk_budget.toml bounds it) and read back on the first
//!   look of a new process, so a restarted daemon starts warm. A file whose header names another slot is a miss.
//!
//! `DMB_ANALYSIS_STORE=0` turns it off (the hosted run then uses the disk caches as the standalone path does).
use dq_analyze::incr::{Entry, Provider};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

type Hash = u128;

struct Item {
    bytes: Option<Arc<[u8]>>,
    seen: u64,
    /// One bit per project root whose latest request used this entry.
    leases: u64,
}

#[derive(Default)]
struct Slot {
    items: HashMap<(Hash, Hash), Item>,
    dirty: bool,
    /// The disk copy was looked for (once per process).
    loaded: bool,
}

#[derive(Default)]
struct Counters {
    served: u64,
    computed: u64,
}

#[derive(Serialize, Deserialize)]
struct SlotFile {
    store: String,
    stamp: String,
    items: Vec<(Hash, Hash, Option<Vec<u8>>)>,
}

#[derive(Default)]
pub struct AnalysisStore {
    /// (store, stamp) -> entries keyed by (context, content key).
    slots: Mutex<HashMap<(String, String), Slot>>,
    counters: Mutex<HashMap<String, Counters>>,
    /// Project roots by lease bit.
    roots: Mutex<Vec<PathBuf>>,
    bytes: AtomicU64,
    generation: AtomicU64,
    /// The lease bit of the request in flight (requests run one at a time).
    lease: AtomicU64,
    dir: Option<PathBuf>,
}

const ENTRY_OVERHEAD: u64 = 48;

fn budget() -> u64 {
    std::env::var("DMB_ANALYSIS_BUDGET_MB").ok().and_then(|v| v.parse::<u64>().ok()).unwrap_or(768) << 20
}

fn slot_file(dir: &Path, store: &str, stamp: &str) -> PathBuf {
    let h = xxhash_rust::xxh3::xxh3_128(format!("{store}\u{0}{stamp}").as_bytes());
    dir.join(format!("{h:032x}.bin"))
}

impl AnalysisStore {
    fn with_dir(dir: Option<PathBuf>) -> Self {
        Self { dir, ..Default::default() }
    }
    fn load_slot(&self, slot: &mut Slot, store: &str, stamp: &str) {
        slot.loaded = true;
        let Some(dir) = &self.dir else { return };
        let Some(file) = std::fs::read(slot_file(dir, store, stamp)).ok().and_then(|b| dq_analyze::incr::de::<SlotFile>(&b).ok()) else {
            return;
        };
        if file.store != store || file.stamp != stamp {
            return;
        }
        let g = self.generation.load(Ordering::Relaxed);
        for (ctx, key, bytes) in file.items {
            let bytes: Option<Arc<[u8]>> = bytes.map(Into::into);
            if let Some(b) = &bytes {
                self.bytes.fetch_add(b.len() as u64 + ENTRY_OVERHEAD, Ordering::Relaxed);
            }
            slot.items.entry((ctx, key)).or_insert(Item { bytes, seen: g.saturating_sub(1), leases: 0 });
        }
    }
}

impl Provider for AnalysisStore {
    fn get(&self, store: &str, stamp: &str, ctx: Hash, key: Hash) -> Option<Entry> {
        let g = self.generation.load(Ordering::Relaxed);
        let lease = self.lease.load(Ordering::Relaxed);
        let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
        let slot = slots.entry((store.to_string(), stamp.to_string())).or_default();
        if !slot.loaded {
            self.load_slot(slot, store, stamp);
        }
        let item = slot.items.get_mut(&(ctx, key))?;
        item.seen = g;
        item.leases |= lease;
        Some(match &item.bytes {
            None => Entry::Clean,
            Some(b) => Entry::Bytes(Arc::clone(b)),
        })
    }
    fn put(&self, store: &str, stamp: &str, ctx: Hash, key: Hash, entry: Entry) {
        let g = self.generation.load(Ordering::Relaxed);
        let lease = self.lease.load(Ordering::Relaxed);
        let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
        let slot = slots.entry((store.to_string(), stamp.to_string())).or_default();
        slot.dirty = true;
        let bytes = match entry {
            Entry::Clean => None,
            Entry::Bytes(b) => {
                self.bytes.fetch_add(b.len() as u64 + ENTRY_OVERHEAD, Ordering::Relaxed);
                Some(b)
            }
        };
        if let Some(old) = slot.items.insert((ctx, key), Item { bytes, seen: g, leases: lease }) {
            if let Some(b) = old.bytes {
                self.bytes.fetch_sub(b.len() as u64 + ENTRY_OVERHEAD, Ordering::Relaxed);
            }
        }
    }
    fn finished(&self, store: &str, served: usize, computed: usize) {
        let mut c = self.counters.lock().unwrap_or_else(|e| e.into_inner());
        let e = c.entry(store.to_string()).or_default();
        e.served += served as u64;
        e.computed += computed as u64;
    }
}

impl AnalysisStore {
    /// One hosted request from `root` starts: a new generation, counters from zero, and the root's lease renewed (its bit is
    /// dropped everywhere; what this request uses claims it again).
    pub fn begin(&self, root: &Path) {
        self.generation.fetch_add(1, Ordering::Relaxed);
        self.counters.lock().unwrap_or_else(|e| e.into_inner()).clear();
        let bit = {
            let mut roots = self.roots.lock().unwrap_or_else(|e| e.into_inner());
            let i = match roots.iter().position(|r| r == root) {
                Some(i) => i,
                None => {
                    if roots.len() >= 64 {
                        roots.remove(0);
                    }
                    roots.push(root.to_path_buf());
                    roots.len() - 1
                }
            };
            1u64 << i
        };
        self.lease.store(bit, Ordering::Relaxed);
        let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
        for s in slots.values_mut() {
            for it in s.items.values_mut() {
                it.leases &= !bit;
            }
        }
    }
    /// One hosted request ended: evict past the budget, persist changed slots, and return the memory mark with the recompute
    /// counters (`store=recomputed/asked` for every store that recomputed anything).
    pub fn end(&self) -> String {
        self.evict(budget());
        let written = self.persist();
        let (entries, bytes) = self.usage();
        let slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
        let clean: usize = slots.values().map(|s| s.items.values().filter(|i| i.bytes.is_none()).count()).sum();
        drop(slots);
        let c = self.counters.lock().unwrap_or_else(|e| e.into_inner());
        let mut rows: Vec<String> =
            c.iter().filter(|(_, v)| v.computed > 0).map(|(k, v)| format!("{}={}/{}", k, v.computed, v.computed + v.served)).collect();
        rows.sort();
        let computed: u64 = c.values().map(|v| v.computed).sum();
        let served: u64 = c.values().map(|v| v.served).sum();
        format!(
            "analysis store: {:.1} MB, {} valued, {} clean, {} slots written; recomputed {} of {} [{}]",
            bytes as f64 / (1u64 << 20) as f64,
            entries - clean,
            clean,
            written,
            computed,
            computed + served,
            rows.join(" ")
        )
    }
    /// (entries, value bytes) held, for the shared store report.
    pub fn usage(&self) -> (usize, u64) {
        let slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
        (slots.values().map(|s| s.items.len()).sum(), self.bytes.load(Ordering::Relaxed))
    }
    fn persist(&self) -> usize {
        let Some(dir) = &self.dir else { return 0 };
        let mut todo = Vec::new();
        {
            let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
            for ((store, stamp), s) in slots.iter_mut() {
                if !s.dirty {
                    continue;
                }
                s.dirty = false;
                let items: Vec<(Hash, Hash, Option<Vec<u8>>)> =
                    s.items.iter().map(|((c, k), i)| (*c, *k, i.bytes.as_ref().map(|b| b.to_vec()))).collect();
                todo.push(SlotFile { store: store.clone(), stamp: stamp.clone(), items });
            }
        }
        if todo.is_empty() {
            return 0;
        }
        let _ = std::fs::create_dir_all(dir);
        let mut written = 0;
        for f in &todo {
            let path = slot_file(dir, &f.store, &f.stamp);
            if let Ok(bytes) = dq_analyze::incr::ser(f) {
                let tmp = path.with_extension(format!("tmp{}", std::process::id()));
                if std::fs::write(&tmp, &bytes).is_ok() && std::fs::rename(&tmp, &path).is_ok() {
                    written += 1;
                } else {
                    let _ = std::fs::remove_file(&tmp);
                }
            }
        }
        written
    }
    fn evict(&self, budget: u64) {
        if self.bytes.load(Ordering::Relaxed) <= budget {
            return;
        }
        let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
        for leased_pass in [false, true] {
            let gens: BTreeSet<u64> =
                slots.values().flat_map(|s| s.items.values().filter(|i| (i.leases != 0) == leased_pass).map(|i| i.seen)).collect();
            for g in gens {
                if self.bytes.load(Ordering::Relaxed) <= budget {
                    return;
                }
                for s in slots.values_mut() {
                    let before = s.items.len();
                    s.items.retain(|_, i| {
                        if i.seen == g && (i.leases != 0) == leased_pass {
                            if let Some(b) = &i.bytes {
                                self.bytes.fetch_sub(b.len() as u64 + ENTRY_OVERHEAD, Ordering::Relaxed);
                            }
                            false
                        } else {
                            true
                        }
                    });
                    s.dirty |= s.items.len() != before;
                }
            }
        }
    }
}

/// The daemon-wide store, registered with dq-analyze on first use.
pub fn store() -> &'static Arc<AnalysisStore> {
    static STORE: OnceLock<Arc<AnalysisStore>> = OnceLock::new();
    STORE.get_or_init(|| {
        let dir = match std::env::var("DMB_ANALYSIS_DIR") {
            Ok(v) if v == "off" => None,
            Ok(v) => Some(PathBuf::from(v)),
            Err(_) => Some(PathBuf::from("E:/dq-cache/analysis")).filter(|p| p.parent().is_some_and(|d| d.is_dir())),
        };
        // The stamps name the analyzer's sources, not the dmbc front end that builds its model (`parse=dmbc`): a persisted slot
        // is valid only for the binary that wrote it, so each binary image keeps its own directory.
        let dir = dir.map(|d| d.join(image_id()));
        let s = Arc::new(AnalysisStore::with_dir(dir));
        if std::env::var("DMB_ANALYSIS_STORE").as_deref() != Ok("0") {
            dq_analyze::incr::set_provider(Some(s.clone() as Arc<dyn Provider>));
        }
        s
    })
}

/// A content hash of this executable (read once per process).
fn image_id() -> String {
    let bytes = std::env::current_exe().and_then(std::fs::read).unwrap_or_default();
    format!("{:032x}", xxhash_rust::xxh3::xxh3_128(&bytes))
}

/// The store's usage when it exists, for `SharedStore::report`.
pub(crate) fn report_line() -> Option<String> {
    static_store().map(|s| {
        let (entries, bytes) = s.usage();
        format!("; analysis_results: entries={entries} ({bytes} B)")
    })
}

fn static_store() -> Option<&'static Arc<AnalysisStore>> {
    STARTED.get().map(|_| store())
}

static STARTED: OnceLock<()> = OnceLock::new();

/// Marks the store as in use (the first hosted request), so the report names it.
pub fn started() -> &'static Arc<AnalysisStore> {
    let _ = STARTED.set(());
    store()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn entries_match_whole_key_and_evict_unleased_first() {
        let s = AnalysisStore::default();
        s.begin(Path::new("a"));
        s.put("a", "st", 1, 2, Entry::Bytes(vec![0u8; 100].into()));
        s.put("a", "st", 1, 3, Entry::Clean);
        assert!(matches!(s.get("a", "st", 1, 2), Some(Entry::Bytes(_))));
        assert!(matches!(s.get("a", "st", 1, 3), Some(Entry::Clean)));
        assert!(s.get("a", "other", 1, 2).is_none());
        assert!(s.get("a", "st", 9, 2).is_none());
        assert!(s.get("b", "st", 1, 2).is_none());
        // Root b claims two newer entries; root a's next request drops its claim on entry 2, which is then unleased and oldest.
        s.begin(Path::new("b"));
        s.put("a", "st", 1, 4, Entry::Bytes(vec![0u8; 100].into()));
        s.put("a", "st", 1, 5, Entry::Bytes(vec![0u8; 100].into()));
        s.begin(Path::new("a"));
        s.evict(2 * (100 + ENTRY_OVERHEAD));
        assert!(s.get("a", "st", 1, 2).is_none());
        assert!(s.get("a", "st", 1, 4).is_some());
    }

    #[test]
    fn persisted_slot_reloads_in_a_new_store() {
        let dir = crate::test_scratch::dir("analysis-store");
        let s = AnalysisStore::with_dir(Some(dir.clone()));
        s.begin(Path::new("a"));
        s.put("lint:x", "v1", 7, 8, Entry::Bytes(vec![1, 2, 3].into()));
        s.put("lint:x", "v1", 7, 9, Entry::Clean);
        assert_eq!(s.persist(), 1);
        let t = AnalysisStore::with_dir(Some(dir));
        t.begin(Path::new("b"));
        assert!(matches!(t.get("lint:x", "v1", 7, 8), Some(Entry::Bytes(b)) if &*b == [1, 2, 3]));
        assert!(matches!(t.get("lint:x", "v1", 7, 9), Some(Entry::Clean)));
        assert!(t.get("lint:x", "v2", 7, 8).is_none());
    }
}
