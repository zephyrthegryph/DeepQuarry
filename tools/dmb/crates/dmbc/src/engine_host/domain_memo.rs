//! Per-host memo of issued domain versions.
//!
//! A configured `EngineResolverHost` is immutable: every builder that changes an
//! input resets this memo (beside `answer_domain`). Within that lifetime a
//! domain's issued version is a pure function of the host, so each domain is
//! computed once instead of on every memo-hit check (`versions`, `accepted`,
//! the receipt observer and `changed_read` each asked again, and each issue
//! re-resolved the query). `DMB_DOMAIN_MEMO_VERIFY=1` recomputes every hit and
//! panics on a mismatch. Cloning yields an empty memo.
use dm_ir::ReadDomain;
use std::collections::HashMap;
use std::hash::{BuildHasher, Hash, Hasher};
use std::sync::atomic::{AtomicU64, Ordering::Relaxed};
use std::sync::Mutex;

const SHARDS: usize = 64;
static REQUEST_HITS: AtomicU64 = AtomicU64::new(0);
static REQUEST_MISSES: AtomicU64 = AtomicU64::new(0);
static REQUEST_ISSUE_NANOS: AtomicU64 = AtomicU64::new(0);
/// Process-wide counts since the last call (one request at a time): memo hits,
/// issued domains, host issue seconds, tree issue calls and tree issue seconds.
pub fn take_request_counts() -> String {
    let tree_calls = dm_tree::TREE_DOMAIN_VERSION_CALLS.swap(0, Relaxed);
    let tree_nanos = dm_tree::TREE_DOMAIN_VERSION_NANOS.swap(0, Relaxed);
    format!(
        "hits={} issued={} issue_s={:.3} tree_calls={} tree_s={:.3}",
        REQUEST_HITS.swap(0, Relaxed),
        REQUEST_MISSES.swap(0, Relaxed),
        REQUEST_ISSUE_NANOS.swap(0, Relaxed) as f64 / 1e9,
        tree_calls,
        tree_nanos as f64 / 1e9
    )
}

pub(crate) struct DomainMemo {
    shards: Box<[Mutex<HashMap<ReadDomain, Option<u128>>>]>,
    hasher: std::collections::hash_map::RandomState,
    hits: AtomicU64,
    misses: AtomicU64,
}

impl Default for DomainMemo {
    fn default() -> Self {
        Self {
            shards: (0..SHARDS).map(|_| Mutex::new(HashMap::new())).collect(),
            hasher: Default::default(),
            hits: AtomicU64::new(0),
            misses: AtomicU64::new(0),
        }
    }
}
impl Clone for DomainMemo {
    fn clone(&self) -> Self {
        Self::default()
    }
}
impl std::fmt::Debug for DomainMemo {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DomainMemo")
            .field("hits", &self.hits.load(Relaxed))
            .field("misses", &self.misses.load(Relaxed))
            .finish()
    }
}

fn verify_enabled() -> bool {
    static VERIFY: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *VERIFY.get_or_init(|| std::env::var_os("DMB_DOMAIN_MEMO_VERIFY").is_some_and(|v| v == "1"))
}

impl DomainMemo {
    pub(crate) fn get_or_issue(
        &self,
        domain: ReadDomain,
        issue: impl FnOnce() -> Option<u128>,
    ) -> Option<u128> {
        let mut hasher = self.hasher.build_hasher();
        domain.hash(&mut hasher);
        let shard = &self.shards[(hasher.finish() as usize) % SHARDS];
        let cached = shard
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .get(&domain)
            .copied();
        if let Some(version) = cached {
            self.hits.fetch_add(1, Relaxed);
            REQUEST_HITS.fetch_add(1, Relaxed);
            if verify_enabled() {
                let fresh = issue();
                assert_eq!(fresh, version, "domain memo diverged for {domain:?}");
            }
            return version;
        }
        self.misses.fetch_add(1, Relaxed);
        REQUEST_MISSES.fetch_add(1, Relaxed);
        // Issue outside the lock: issuance resolves through the tree and may
        // recurse into this host for another domain.
        let started = std::time::Instant::now();
        let version = issue();
        REQUEST_ISSUE_NANOS.fetch_add(started.elapsed().as_nanos() as u64, Relaxed);
        shard
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .insert(domain, version);
        version
    }
    pub(crate) fn counts(&self) -> (u64, u64) {
        (self.hits.load(Relaxed), self.misses.load(Relaxed))
    }
}
