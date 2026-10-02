//! Worktree/configuration-local frontend retention with one aggregate budget.
//! Immutable disk artifacts survive lexical trimming and whole-session eviction.
use crate::{project_discovery::DiscoveryCache, SessionKey};
use dm_compiler::frontend::OutlineSession;
use sha2::{Digest, Sha256};
use std::{collections::HashMap, path::PathBuf};

#[derive(Clone, Copy, Debug)]
pub struct FrontendPoolLimits {
    pub max_sessions: usize,
    pub max_bytes: usize,
}

impl Default for FrontendPoolLimits {
    fn default() -> Self {
        let baseline = 512 * 1024 * 1024;
        Self {
            max_sessions: 6,
            max_bytes: std::env::var("DM_FRONTEND_POOL_BYTES")
                .ok()
                .and_then(|s| s.parse::<usize>().ok())
                .unwrap_or(baseline)
                .max(baseline),
        }
    }
}
#[derive(Clone, Copy, Debug, Default)]
pub struct FrontendPoolStats {
    pub hits: usize,
    pub misses: usize,
    pub discovery_hits: usize,
    pub discovery_misses: usize,
    pub source_trims: usize,
    pub discovery_trims: usize,
    pub expansion_trims: usize,
    pub body_compactions: usize,
    pub snapshot_trims: usize,
    pub payload_trims: usize,
    pub prepared_trims: usize,
    pub skeleton_trims: usize,
    pub evictions: usize,
    pub sessions: usize,
    pub bytes: usize,
    /// Known retained footprints currently checked out, before active growth.
    pub active_bytes: usize,
}
#[derive(Default)]
struct Entry {
    frontend: Option<OutlineSession>,
    discovery: Option<DiscoveryCache>,
    active_frontend: Option<usize>,
    active_discovery: Option<usize>,
    touched: u64,
}

impl Entry {
    fn active(&self) -> bool {
        self.active_frontend.is_some() || self.active_discovery.is_some()
    }
    fn resident_bytes(&self) -> usize {
        self.frontend
            .as_ref()
            .map_or(0, OutlineSession::retained_bytes)
            .saturating_add(
                self.discovery
                    .as_ref()
                    .map_or(0, DiscoveryCache::resident_bytes),
            )
    }
    #[cfg(test)]
    fn source_bytes(&self) -> usize {
        self.frontend
            .as_ref()
            .map_or(0, OutlineSession::resident_bytes)
            .saturating_add(
                self.discovery
                    .as_ref()
                    .map_or(0, DiscoveryCache::source_resident_bytes),
            )
    }
}

/// One owner for frontend and prepared input state per worktree/configuration.
/// Components can be checked out separately without discarding each other.
/// One aggregate budget includes idle state and known checked-out footprints;
/// active growth is managed by the compiler's separate stage/window budgets.
pub struct FrontendPool {
    entries: HashMap<SessionKey, Entry>,
    limits: FrontendPoolLimits,
    clock: u64,
    stats: FrontendPoolStats,
    external_bytes: usize,
}
impl Default for FrontendPool {
    fn default() -> Self {
        Self::new(FrontendPoolLimits::default())
    }
}
impl FrontendPool {
    pub fn new(limits: FrontendPoolLimits) -> Self {
        Self {
            entries: HashMap::new(),
            limits,
            clock: 0,
            stats: FrontendPoolStats::default(),
            external_bytes: 0,
        }
    }
    /// Account for coordinator-owned derived output caches in the same retention budget.
    pub fn set_external_bytes(&mut self, bytes: usize) {
        self.external_bytes = bytes;
        self.trim(0);
    }
    pub fn configuration_identity(key: &SessionKey) -> String {
        let encoded = serde_json::to_vec(&(
            &key.target,
            &key.defines,
            &key.build_mode,
            &key.compiler_version,
        ))
        .expect("session configuration is serializable");
        format!("{:x}", Sha256::digest(encoded))
    }
    pub fn take_or_insert(&mut self, key: &SessionKey, cache_root: PathBuf) -> OutlineSession {
        let entry = self.entries.entry(key.clone()).or_default();
        assert!(
            entry.active_frontend.is_none(),
            "frontend already checked out"
        );
        let mut frontend = if let Some(frontend) = entry.frontend.take() {
            self.stats.hits += 1;
            frontend
        } else {
            self.stats.misses += 1;
            OutlineSession::new(Some(cache_root))
        };
        frontend.set_project_configuration(&key.project, &Self::configuration_identity(key));
        self.entries.get_mut(key).unwrap().active_frontend = Some(frontend.retained_bytes());
        self.trim(0);
        frontend
    }
    pub fn put(&mut self, key: SessionKey, frontend: OutlineSession) {
        self.clock = self.clock.wrapping_add(1);
        let entry = self.entries.entry(key.clone()).or_default();
        entry.frontend = Some(frontend);
        entry.active_frontend = None;
        entry.touched = self.clock;
        self.trace_entry("frontend returned", &key);
        self.trim(0);
    }
    pub fn take_discovery(&mut self, key: &SessionKey, cache_root: PathBuf) -> DiscoveryCache {
        let entry = self.entries.entry(key.clone()).or_default();
        assert!(
            entry.active_discovery.is_none(),
            "discovery already checked out"
        );
        let discovery = if let Some(discovery) = entry.discovery.take() {
            self.stats.discovery_hits += 1;
            discovery
        } else {
            self.stats.discovery_misses += 1;
            DiscoveryCache::load_with_cache_root(&key.project, cache_root)
        };
        self.entries.get_mut(key).unwrap().active_discovery = Some(discovery.resident_bytes());
        self.trim(0);
        discovery
    }
    pub fn put_discovery(&mut self, key: SessionKey, discovery: DiscoveryCache) {
        self.clock = self.clock.wrapping_add(1);
        let entry = self.entries.entry(key.clone()).or_default();
        entry.discovery = Some(discovery);
        entry.active_discovery = None;
        entry.touched = self.clock;
        self.trace_entry("discovery returned", &key);
        self.trim(0);
    }
    pub fn stats(&self) -> FrontendPoolStats {
        let mut stats = self.stats;
        stats.sessions = self.entries.len();
        stats.bytes = self.bytes();
        stats.active_bytes = self.active_bytes();
        stats
    }
    fn bytes(&self) -> usize {
        self.entries.iter().fold(0usize, |n, (key, entry)| {
            n.saturating_add(entry.resident_bytes())
                .saturating_add(key.worktree.as_os_str().len() * 2)
                .saturating_add(key.project.as_os_str().len() * 2)
                .saturating_add(
                    key.target.len() + key.build_mode.len() + key.compiler_version.len() + 512,
                )
                .saturating_add(
                    key.defines
                        .iter()
                        .map(|(name, value)| name.len() + value.len() + 64)
                        .sum::<usize>(),
                )
        })
    }
    fn active_bytes(&self) -> usize {
        self.entries.values().fold(0usize, |bytes, entry| {
            bytes
                .saturating_add(entry.active_frontend.unwrap_or(0))
                .saturating_add(entry.active_discovery.unwrap_or(0))
        })
    }
    fn oldest(&self, filter: impl Fn(&Entry) -> bool) -> Option<SessionKey> {
        self.entries
            .iter()
            .filter(|(_, entry)| filter(entry))
            .min_by_key(|(_, entry)| entry.touched)
            .map(|(key, _)| key.clone())
    }
    fn trace_entry(&self, action: &str, key: &SessionKey) {
        if std::env::var_os("DM_BUILD_TRACE").is_none() {
            return;
        }
        if let Some(entry) = self.entries.get(key) {
            eprintln!("DM_BUILD_TRACE frontend pool {action}: project {}, idle {} active {} limit {} bytes; frontend {:?}; discovery {:?}",
                key.project.display(), self.bytes(), self.active_bytes(), self.limits.max_bytes,
                entry.frontend.as_ref().map(OutlineSession::retention_footprint),
                entry.discovery.as_ref().map(DiscoveryCache::retention_footprint));
        }
    }
    fn trim(&mut self, active_bytes: usize) {
        let budget = self.limits.max_bytes.saturating_sub(
            self.active_bytes()
                .saturating_add(active_bytes)
                .saturating_add(self.external_bytes),
        );
        let mut ordered: Vec<_> = self
            .entries
            .iter()
            .map(|(key, entry)| (entry.touched, key.clone()))
            .collect();
        ordered.sort_by_key(|(touched, _)| *touched);
        // Reclaim disposable/duplicated values before discarding the inputs and
        // identities needed for the next body edit. All steps preserve context.
        for (_, key) in &ordered {
            let excess = self.bytes().saturating_sub(budget);
            if excess == 0 {
                break;
            }
            self.trace_entry("before expansion trim", key);
            if let Some(discovery) = self.entries.get_mut(key).unwrap().discovery.as_mut() {
                let target = discovery
                    .retention_footprint()
                    .expansions
                    .saturating_sub(excess);
                if discovery.trim_expansions_to(target) != 0 {
                    self.stats.expansion_trims += 1;
                }
            }
            self.trace_entry("after expansion trim", key);
        }
        for (_, key) in &ordered {
            if self.bytes() <= budget {
                break;
            }
            self.trace_entry("before body compaction", key);
            if let Some(frontend) = self.entries.get_mut(key).unwrap().frontend.as_mut() {
                if frontend.compact_source_frames() != 0 {
                    self.stats.body_compactions += 1;
                }
            }
            self.trace_entry("after body compaction", key);
        }
        for (_, key) in &ordered {
            if self.bytes() <= budget {
                break;
            }
            self.trace_entry("before encoded snapshot trim", key);
            let before = self.bytes();
            if let Some(frontend) = self.entries.get_mut(key).unwrap().frontend.as_mut() {
                frontend.release_encoded_snapshot();
            }
            if self.bytes() != before {
                self.stats.snapshot_trims += 1;
            }
            self.trace_entry("after encoded snapshot trim", key);
        }
        for (_, key) in &ordered {
            let excess = self.bytes().saturating_sub(budget);
            if excess == 0 {
                break;
            }
            self.trace_entry("before decoded payload trim", key);
            if let Some(frontend) = self.entries.get_mut(key).unwrap().frontend.as_mut() {
                let target = frontend
                    .retention_footprint()
                    .graph_decoded
                    .saturating_sub(excess);
                if frontend.trim_decoded_to(target) != 0 {
                    self.stats.payload_trims += 1;
                }
            }
            self.trace_entry("after decoded payload trim", key);
        }
        for (_, key) in &ordered {
            if self.bytes() <= budget {
                break;
            }
            self.trace_entry("before authored payload trim", key);
            if let Some(discovery) = self.entries.get_mut(key).unwrap().discovery.as_mut() {
                discovery.trim_authored_payloads();
            }
            self.trace_entry("after authored payload trim", key);
            if self.bytes() <= budget {
                break;
            }
            self.trace_entry("before expanded input trim", key);
            if let Some(frontend)=self.entries.get_mut(key).unwrap().frontend.as_mut() {frontend.evict_segmented_payloads();}
            if let Some(discovery) = self.entries.get_mut(key).unwrap().discovery.as_mut() {
                if discovery.release_prepared_snapshot() != 0 {
                    self.stats.prepared_trims += 1;
                }
            }
            self.trace_entry("after expanded input trim", key);
        }
        for (_, key) in &ordered {
            if self.bytes() <= budget {
                break;
            }
            self.trace_entry("before skeleton trim", key);
            if let Some(frontend) = self.entries.get_mut(key).unwrap().frontend.as_mut() {
                if frontend.release_skeleton() != 0 {
                    self.stats.skeleton_trims += 1;
                }
            }
            self.trace_entry("after skeleton trim", key);
        }
        // Last component fallback: source state can be replayed while the live
        // semantic graph/configuration survives. Whole entry eviction is later.
        for (_, key) in &ordered {
            if self.bytes() <= budget {
                break;
            }
            self.trace_entry("before source release", key);
            let entry = self.entries.get_mut(key).unwrap();
            if let Some(frontend) = entry.frontend.as_mut().filter(|f| f.resident_bytes() != 0) {
                frontend.release_source_frames();
                self.stats.source_trims += 1;
            }
            if let Some(discovery) = entry
                .discovery
                .as_mut()
                .filter(|d| d.source_resident_bytes() != 0)
            {
                discovery.release_source_frames();
                self.stats.discovery_trims += 1;
            }
            self.trace_entry("after source release", key);
        }
        // Preserve compact input/layout handles while reclaiming a cold
        // frontend's larger semantic indexes. Those indexes restore by exact
        // disk keys; discovery can still directly splice the next source edit.
        while self.bytes()>budget {
            let Some(key)=self.oldest(|entry|!entry.active() && entry.frontend.is_some()) else {break;};
            self.trace_entry("idle semantic frontend eviction",&key);
            self.entries.get_mut(&key).unwrap().frontend=None;
            self.stats.evictions+=1;
        }
        // The aggregate bound remains hard for retained idle state. If even
        // compact discovery metadata does not fit, its persisted manifest is
        // the bounded fallback; never retain arbitrarily many oversized roots.
        while self.entries.len()>self.limits.max_sessions || self.bytes()>budget {
            let Some(key)=self.oldest(|entry|!entry.active()) else {break;};
            self.trace_entry("whole idle entry eviction",&key);
            self.entries.remove(&key);
            self.stats.evictions+=1;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        fs,
        sync::atomic::{AtomicU64, Ordering},
    };

    static SEQUENCE: AtomicU64 = AtomicU64::new(0);
    const SOURCE: &str = "/proc/answer()\n\treturn 1\n";

    struct Fixture(PathBuf);
    impl Fixture {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "dm-frontend-pool-{}-{}",
                std::process::id(),
                SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path.canonicalize().unwrap())
        }
        fn key(&self, index: usize) -> SessionKey {
            let worktree = self.0.join(format!("worktree-{index}"));
            fs::create_dir_all(&worktree).unwrap();
            let project = worktree.join("project.dme");
            fs::write(&project, SOURCE).unwrap();
            SessionKey::new(worktree, project, "516.1687", Vec::new(), "canonical").unwrap()
        }
        fn cache(&self) -> PathBuf {
            self.0.join("shared-cache")
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn six_worktrees_share_disk_syntax_without_cross_session_edits() {
        let fixture = Fixture::new();
        let keys: Vec<_> = (0..6).map(|index| fixture.key(index)).collect();
        let mut pool = FrontendPool::new(FrontendPoolLimits {
            max_sessions: 6,
            max_bytes: 4 * 1024 * 1024,
        });
        for (index, key) in keys.iter().enumerate() {
            let mut frontend = pool.take_or_insert(key, fixture.cache());
            let outline = frontend.update_source(SOURCE).unwrap();
            assert!(outline.procedures["/proc/answer"]
                .source
                .contains("return 1"));
            if index == 0 {
                assert!(frontend.stats().parsed_chunks > 0);
            } else {
                assert!(frontend.stats().disk_hits > 0);
                assert_eq!(frontend.stats().parsed_chunks, 0);
            }
            pool.put(key.clone(), frontend);
        }
        assert_eq!(pool.stats().sessions, 6);
        assert_eq!(pool.stats().misses, 6);
        assert!(pool.stats().bytes <= pool.limits.max_bytes);
        assert!(keys.iter().all(|key| {
            FrontendPool::configuration_identity(key)
                == FrontendPool::configuration_identity(&keys[0])
        }));

        let edited = SOURCE.replace("return 1", "return 22");
        let mut changed = pool.take_or_insert(&keys[0], fixture.cache());
        let edited_outline = changed.update_source(&edited).unwrap();
        let edited_body = edited_outline.procedures["/proc/answer"].source.clone();
        assert!(edited_body.contains("return 22"));
        assert!(changed.stats().parsed_chunks > 0);
        pool.put(keys[0].clone(), changed);

        for key in &keys[1..] {
            let mut unchanged = pool.take_or_insert(key, fixture.cache());
            let outline = unchanged.update_source(SOURCE).unwrap();
            assert!(outline.procedures["/proc/answer"]
                .source
                .contains("return 1"));
            assert_eq!(unchanged.stats().parsed_chunks, 0);
            assert!(unchanged.stats().memory_hits > 0);
            pool.put(key.clone(), unchanged);
        }
        let mut changed = pool.take_or_insert(&keys[0], fixture.cache());
        let retained = changed.update_source(&edited).unwrap();
        assert!(std::sync::Arc::ptr_eq(
            &edited_body,
            &retained.procedures["/proc/answer"].source
        ));
        assert_eq!(changed.stats().parsed_chunks, 0);
        pool.put(keys[0].clone(), changed);

        // A configuration change gets a separate mutable session even in the
        // same worktree. Pure lexical shards remain reusable across both.
        let mut configured = keys[0].clone();
        configured
            .defines
            .push(("DIFFERENT_MODE".into(), "1".into()));
        assert_ne!(
            FrontendPool::configuration_identity(&configured),
            FrontendPool::configuration_identity(&keys[0])
        );
        let mut frontend = pool.take_or_insert(&configured, fixture.cache());
        frontend.update_source(SOURCE).unwrap();
        assert!(frontend.stats().disk_hits > 0);
        assert_eq!(frontend.stats().parsed_chunks, 0);
        pool.put(configured.clone(), frontend);
        assert_eq!(pool.stats().misses, 7);
        assert_eq!(pool.stats().sessions, 6);
        assert_eq!(pool.stats().evictions, 1);
        assert!(pool.entries.contains_key(&keys[0]));
        assert!(pool.entries.contains_key(&configured));
        assert!(!pool.entries.contains_key(&keys[1]));
    }

    #[test]
    fn six_session_budget_releases_source_frames_and_restores_disk_syntax() {
        let fixture = Fixture::new();
        let keys: Vec<_> = (0..6).map(|index| fixture.key(index)).collect();
        let mut pool = FrontendPool::new(FrontendPoolLimits {
            max_sessions: 6,
            max_bytes: 4 * 1024 * 1024,
        });
        for key in &keys {
            let mut frontend = pool.take_or_insert(key, fixture.cache());
            frontend.update_source(SOURCE).unwrap();
            pool.put(key.clone(), frontend);
        }
        assert!(pool.stats().bytes > 0);
        pool.limits.max_bytes = 0;
        pool.trim(0);
        assert_eq!(pool.stats().bytes, 0);
        assert_eq!(pool.stats().source_trims, 6);
        assert!(pool.entries.values().all(|entry| {
            entry
                .frontend
                .as_ref()
                .is_none_or(|frontend| frontend.resident_bytes() == 0)
        }));

        pool.limits.max_bytes = 4 * 1024 * 1024;
        let mut restored = pool.take_or_insert(&keys[0], fixture.cache());
        let outline = restored.update_source(SOURCE).unwrap();
        assert!(outline.procedures["/proc/answer"]
            .source
            .contains("return 1"));
        assert!(restored.stats().disk_hits > 0);
        assert_eq!(restored.stats().parsed_chunks, 0);
        pool.put(keys[0].clone(), restored);
        assert!(pool.stats().bytes <= pool.limits.max_bytes);
    }

    #[test]
    fn six_prepared_source_sessions_switch_without_reload_or_cross_worktree_edits() {
        let fixture = Fixture::new();
        let keys: Vec<_> = (0..6)
            .map(|index| {
                let mut key = fixture.key(index);
                key.defines.push(("ANSWER".into(), "1".into()));
                fs::write(&key.project, "#include \"answer.dm\"\n").unwrap();
                fs::write(
                    key.worktree.join("answer.dm"),
                    "/proc/answer()\n\treturn ANSWER\n",
                )
                .unwrap();
                key
            })
            .collect();
        let mut pool = FrontendPool::new(FrontendPoolLimits {
            max_sessions: 6,
            max_bytes: 4 * 1024 * 1024,
        });
        let mut originals = Vec::new();
        for key in &keys {
            let mut discovery = pool.take_discovery(key, fixture.cache());
            let prepared = discovery
                .prepare(&key.project, &key.defines.iter().cloned().collect())
                .unwrap();
            let mut frontend = pool.take_or_insert(key, fixture.cache());
            frontend.update(&prepared.project).unwrap();
            pool.put(key.clone(), frontend);
            pool.put_discovery(key.clone(), discovery);
            assert!(prepared.project.text.contains("return 1"));
            assert!(prepared.project.origins.iter().any(|origin| {
                origin.path.as_ref() == &key.worktree.join("answer.dm") && origin.source_line == 2
            }));
            originals.push(prepared);
        }
        assert_eq!(pool.stats().sessions, 6);
        assert_eq!(pool.stats().discovery_misses, 6);
        assert_eq!(pool.stats().active_bytes, 0);

        fs::write(
            keys[0].worktree.join("answer.dm"),
            "/proc/answer()\n\treturn 22\n",
        )
        .unwrap();
        for (index, key) in keys.iter().enumerate() {
            let mut discovery = pool.take_discovery(key, fixture.cache());
            let prepared = discovery
                .prepare(&key.project, &key.defines.iter().cloned().collect())
                .unwrap();
            if index == 0 {
                assert!(prepared.project.text.contains("return 22"));
                assert!(prepared
                    .changes
                    .changed_sources
                    .contains(&key.worktree.join("answer.dm")));
            } else {
                assert!(prepared.stats.retained_hit);
                assert!(!prepared.stats.preprocessed);
                assert_eq!(prepared.stats.source_files_read, 0);
                assert!(std::sync::Arc::ptr_eq(
                    &originals[index].project,
                    &prepared.project
                ));
                assert!(prepared.project.text.contains("return 1"));
            }
            let mut frontend = pool.take_or_insert(key, fixture.cache());
            let outline = frontend.update(&prepared.project).unwrap();
            assert!(outline.procedures["/proc/answer"]
                .source
                .contains(if index == 0 { "return 22" } else { "return 1" }));
            pool.put_discovery(key.clone(), discovery);
            pool.put(key.clone(), frontend);
        }
        assert_eq!(pool.stats().discovery_hits, 6);
        assert_eq!(pool.stats().hits, 6);
        assert_eq!(pool.stats().evictions, 0);
        assert!(pool.stats().bytes <= pool.limits.max_bytes);
        assert_eq!(pool.stats().active_bytes, 0);

        // Prepared macro state and source presentation are configuration-local,
        // while returning one component never replaces the other component.
        let mut configured = keys[1].clone();
        configured.defines = vec![("ANSWER".into(), "7".into())];
        let mut discovery = pool.take_discovery(&configured, fixture.cache());
        let prepared = discovery
            .prepare(
                &configured.project,
                &configured.defines.iter().cloned().collect(),
            )
            .unwrap();
        assert!(prepared.project.text.contains("return 7"));
        pool.put_discovery(configured.clone(), discovery);
        assert_eq!(pool.stats().sessions, 6);
        assert_eq!(pool.stats().evictions, 1);
        assert!(pool.entries.contains_key(&keys[1]));
        assert!(pool.entries.contains_key(&configured));
        assert!(!pool.entries.contains_key(&keys[0]));
    }

    #[test]
    fn combined_budget_reserves_both_checkouts_and_trims_preparation_before_eviction() {
        let fixture = Fixture::new();
        let keys: Vec<_> = (0..6).map(|index| fixture.key(index)).collect();
        // Include expansions are cached; a root containing only one procedure
        // has no expansion entry to reclaim in this pressure scenario.
        for key in &keys {
            fs::write(key.project.parent().unwrap().join("body.dm"), SOURCE).unwrap();
            fs::write(&key.project, "#include \"body.dm\"\n").unwrap();
        }
        let mut pool = FrontendPool::new(FrontendPoolLimits {
            max_sessions: 6,
            max_bytes: 4 * 1024 * 1024,
        });
        for key in &keys {
            let mut discovery = pool.take_discovery(key, fixture.cache());
            discovery
                .prepare(&key.project, &Default::default())
                .unwrap();
            let mut frontend = pool.take_or_insert(key, fixture.cache());
            frontend.update_source(SOURCE).unwrap();
            pool.put_discovery(key.clone(), discovery);
            pool.put(key.clone(), frontend);
        }
        let discovery = pool.take_discovery(&keys[0], fixture.cache());
        let frontend = pool.take_or_insert(&keys[0], fixture.cache());
        assert_eq!(
            pool.stats().active_bytes,
            discovery.resident_bytes() + frontend.retained_bytes()
        );
        pool.put(keys[0].clone(), frontend);
        assert_eq!(pool.stats().active_bytes, discovery.resident_bytes());
        assert!(pool.entries[&keys[0]].frontend.is_some());
        assert!(pool.entries[&keys[0]].discovery.is_none());
        pool.put_discovery(keys[0].clone(), discovery);
        assert_eq!(pool.stats().active_bytes, 0);

        let original = pool
            .entries
            .get_mut(&keys[1])
            .unwrap()
            .discovery
            .as_mut()
            .unwrap()
            .prepare(&keys[1].project, &Default::default())
            .unwrap();
        let reclaimable = pool.entries[&keys[1]]
            .discovery
            .as_ref()
            .unwrap()
            .retention_footprint()
            .expansions;
        assert!(reclaimable > 0);
        pool.limits.max_bytes = pool.stats().bytes - reclaimable / 2;
        pool.trim(0);
        assert!(pool.stats().bytes <= pool.limits.max_bytes);
        assert_eq!(pool.stats().sessions, 6);
        assert_eq!(pool.stats().source_trims, 0);
        assert_eq!(pool.stats().discovery_trims, 0);
        assert_eq!(pool.stats().expansion_trims, 1);
        assert_eq!(pool.stats().evictions, 0);
        assert!(pool.entries[&keys[1]].source_bytes() > 0);

        pool.limits.max_bytes = 4 * 1024 * 1024;
        let mut restored = pool.take_discovery(&keys[1], fixture.cache());
        let prepared = restored
            .prepare(&keys[1].project, &Default::default())
            .unwrap();
        assert!(prepared.stats.retained_hit);
        assert!(!prepared.stats.preprocessed);
        assert!(std::sync::Arc::ptr_eq(&original.project, &prepared.project));
        assert!(prepared.project.text.contains("return 1"));
        pool.put_discovery(keys[1].clone(), restored);
        assert_eq!(pool.stats().active_bytes, 0);
    }

    #[test]
    fn oversized_latest_project_retains_preparation_and_compact_edit_layout() {
        let fixture = Fixture::new();
        let key = fixture.key(0);
        let source = format!(
            "/proc/answer()\n    return \"{}\"\n",
            "x".repeat(128 * 1024)
        );
        fs::write(&key.project, &source).unwrap();
        let mut pool = FrontendPool::new(FrontendPoolLimits {
            max_sessions: 6,
            max_bytes: 4 * 1024 * 1024,
        });
        let mut discovery = pool.take_discovery(&key, fixture.cache());
        let prepared = discovery
            .prepare(&key.project, &Default::default())
            .unwrap();
        let expansions = discovery.retention_footprint().expansions;
        let mut frontend = pool.take_or_insert(&key, fixture.cache());
        let original = frontend.update(&prepared.project).unwrap();
        pool.put_discovery(key.clone(), discovery);
        pool.put(key.clone(), frontend);
        pool.limits.max_bytes = pool.stats().bytes - expansions - source.len() / 2;
        pool.trim(0);
        assert!(pool.stats().bytes <= pool.limits.max_bytes);
        assert_eq!(pool.stats().sessions, 1);
        assert_eq!(pool.stats().evictions, 0);
        assert_eq!(pool.stats().body_compactions, 1);
        assert_eq!(pool.stats().source_trims, 0);
        assert_eq!(pool.stats().discovery_trims, 0);
        let mut discovery = pool.take_discovery(&key, fixture.cache());
        let retained = discovery
            .prepare(&key.project, &Default::default())
            .unwrap();
        assert!(retained.stats.retained_hit);
        assert!(std::sync::Arc::ptr_eq(&prepared.project, &retained.project));
        let mut frontend = pool.take_or_insert(&key, fixture.cache());
        let outline = frontend.update(&retained.project).unwrap();
        assert_eq!(
            outline.procedures["/proc/answer"].digest,
            original.procedures["/proc/answer"].digest
        );
        assert_eq!(frontend.stats().parsed_chunks, 0);
        let edited = source
            .replace("return \"", "return list(\"")
            .replace("\"\n", "\")\n");
        let outline = frontend.update_source(&edited).unwrap();
        assert_eq!(outline.abi_digest, original.abi_digest);
        assert_ne!(
            outline.procedures["/proc/answer"].digest,
            original.procedures["/proc/answer"].digest
        );
        assert_eq!(
            outline.procedures["/proc/answer"].digest,
            OutlineSession::default()
                .update_source(&edited)
                .unwrap()
                .procedures["/proc/answer"]
                .digest
        );
        pool.put_discovery(key.clone(), discovery);
        pool.put(key, frontend);
    }
}
