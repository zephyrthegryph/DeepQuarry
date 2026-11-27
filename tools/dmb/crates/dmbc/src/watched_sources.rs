//! Source texts of a hosted analysis session, kept between requests and revalidated through the daemon's directory watcher
//! (`fs_watch`), so a request after an edit re-reads only the files whose directory an event named (doc/retained_frontend.md,
//! "Front end edit floor").
//!
//! The compile path serves its sources from the request's input capture (session validation, prepared inputs, the query
//! database's change log). An analysis request has no such capture: it used to read every source through
//! `dm_preprocess::FileSystem`, 6.9k files and 65 MB on every request, and the planner then compared every file with the previous
//! plan to find the one that changed. This provider keeps every text it served, and at the start of a request:
//!
//! * with a healthy watcher, re-checks only the files in a directory an event named since the last request (plus any file the
//!   watcher does not cover: outside the watched root, or behind a link): their bytes are read again and compared;
//! * without one (`DMB_WATCH=0`, a lost event), stats every file and re-reads the ones whose size or modification time moved.
//!
//! What changed is logged per revision, so the planner asks `changes_since(token)` and re-plans only the subtrees of the files
//! that changed (`dm_preprocess::regions::plan_patch`), and a request that changed nothing is recognised by its token.
use std::collections::{BTreeSet, HashMap, VecDeque};
use std::path::{Path, PathBuf};
use dm_preprocess::regions::prepared_source::PreparedSource;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime};

/// What a file looked like when it was last read: its decoded and lexically prepared text (or the read error) and its stamp.
/// The prepared source is served as is (`SourceProvider::prepared_source`), so the planner sees the same allocation as last
/// time for an unchanged file and adopts its include subtree without comparing text.
#[derive(Clone)]
struct Entry {
    text: Result<Arc<PreparedSource>, String>,
    stamp: Option<(u64, SystemTime)>,
}

fn stamp(path: &Path) -> Option<(u64, SystemTime)> {
    let meta = std::fs::metadata(path).ok()?;
    Some((meta.len(), meta.modified().ok()?))
}

fn read_entry(path: &Path) -> Entry {
    // The stamp is taken before the bytes: a write between the two leaves a stamp older than the text, so a later stat sweep
    // reads the file again rather than keeping a text older than its stamp.
    let stamp = stamp(path);
    let text = dm_preprocess::read_source_file(path)
        .map(|text| dm_preprocess::regions::prepared_source::shared_prepared(text.into()))
        .map_err(|error| error.to_string());
    Entry { text, stamp }
}

fn same_text(a: &Entry, b: &Entry) -> bool {
    match (&a.text, &b.text) {
        (Ok(a), Ok(b)) => Arc::ptr_eq(a, b) || a.original().as_str() == b.original().as_str(),
        (Err(_), Err(_)) => true,
        _ => false,
    }
}

/// One request's revalidation, for the trace.
#[derive(Clone, Copy, Debug, Default)]
pub struct Refresh {
    /// How the candidates were found: `watch` (events since the last request), `sweep` (every file stat'ed) or `first`.
    pub mode: &'static str,
    pub files: usize,
    /// Files stat'ed or read again.
    pub checked: usize,
    pub changed: usize,
    /// The watcher's sync cookie (every write before the request has been seen once it returns).
    pub sync: Duration,
    pub elapsed: Duration,
}

struct State {
    files: HashMap<PathBuf, Entry>,
    watch: Option<crate::fs_watch::WatchToken>,
    revision: u64,
    /// `(revision before, revision after, paths)` of the recent revisions that changed something.
    log: VecDeque<(u64, u64, Arc<Vec<PathBuf>>)>,
}

/// Revisions kept in the change log; a consumer older than this re-plans by comparing every file (the planner's adoption).
const LOG: usize = 64;
/// Bits of a token that hold the revision; the rest name the instance, so a token of another session is never answered.
const TOKEN_REVISION_BITS: u32 = 40;

pub struct WatchedSources {
    id: u64,
    state: Mutex<State>,
}

impl Default for WatchedSources {
    fn default() -> Self {
        // Ids start high so a token never equals a query database's (`query_db`, ids from 1) even when compared directly.
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1 << 23);
        Self {
            id: NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
            state: Mutex::new(State { files: HashMap::new(), watch: None, revision: 0, log: VecDeque::new() }),
        }
    }
}

impl WatchedSources {
    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// The token naming the texts this provider serves now (what `SourceProvider::revision` returns).
    pub fn token(&self) -> u64 {
        (self.id << TOKEN_REVISION_BITS) | self.lock().revision
    }

    /// Brings every kept text up to date with the disk under `root` (the watched project directory) and starts a new revision
    /// when one changed. Call once at the start of a request, before the front end reads.
    pub fn refresh(&self, root: &Path) -> Refresh {
        /// Fewer candidates than this are checked on the calling thread.
        const SERIAL_CHECKS: usize = 64;
        let started = Instant::now();
        crate::fs_watch::arm(root);
        crate::fs_watch::sync(root);
        let sync = started.elapsed();
        let now = crate::fs_watch::token();
        let mut state = self.lock();
        let changes = match (state.watch, now) {
            (Some(since), Some(now)) => crate::fs_watch::changes_since(since, now),
            _ => None,
        };
        let mode = if state.files.is_empty() {
            "first"
        } else if changes.is_some() {
            "watch"
        } else {
            "sweep"
        };
        // The candidates: with the watcher, files in a directory an event named (or one it does not cover); without it, every
        // file. A candidate is read again only when its stamp (size, modification time) moved, and its text compared.
        let candidates: Vec<(&PathBuf, &Entry)> = state
            .files
            .iter()
            .filter(|(path, _)| match &changes {
                Some(changes) => path.parent().is_none_or(|dir| !changes.clean(dir)),
                None => true,
            })
            .collect();
        let checked = candidates.len();
        // (path, new entry, whether its text changed)
        let check = |(path, old): (&PathBuf, &Entry)| {
            if old.stamp.is_some() && stamp(path) == old.stamp {
                return None;
            }
            let fresh = read_entry(path);
            if same_text(&fresh, old) {
                // The same bytes under a new stamp: keep the text, remember the stamp.
                return (fresh.stamp != old.stamp)
                    .then(|| (path.clone(), Entry { text: old.text.clone(), stamp: fresh.stamp }, false));
            }
            Some((path.clone(), fresh, true))
        };
        // The watcher names a few files after an edit: checking them here costs less than waking the pool (which a loaded
        // machine makes slow); a sweep or a first request checks thousands in parallel.
        let updated: Vec<(PathBuf, Entry, bool)> = if candidates.len() < SERIAL_CHECKS {
            candidates.into_iter().filter_map(check).collect()
        } else {
            use rayon::prelude::*;
            candidates.into_par_iter().filter_map(check).collect()
        };
        let mut changed_paths = Vec::new();
        for (path, entry, changed) in updated {
            if changed {
                changed_paths.push(path.clone());
            }
            state.files.insert(path, entry);
        }
        changed_paths.sort();
        let changed = changed_paths.len();
        if changed > 0 {
            let before = state.revision;
            state.revision += 1;
            let after = state.revision;
            state.log.push_back((before, after, Arc::new(changed_paths)));
            while state.log.len() > LOG {
                state.log.pop_front();
            }
        }
        state.watch = now;
        Refresh { mode, files: state.files.len(), checked, changed, sync, elapsed: started.elapsed() }
    }

    /// Reads, in parallel, every file the manifest `dme` includes directly, under the path the planner asks for it by
    /// (`canonical_path` of the including file's directory joined with the operand), when nothing is kept yet. The planner
    /// reads its files one at a time, in include order; on a first request that is thousands of serial disk reads. A file
    /// read here and never asked for is only kept (and revalidated like any other). Returns how many files were read.
    pub fn prefetch_manifest(&self, dme: &Path) -> usize {
        if !self.lock().files.is_empty() {
            return 0;
        }
        let manifest = dm_preprocess::regions::canonical_path(dme);
        let Ok(text) = dm_preprocess::read_source_file(&manifest) else {
            return 0;
        };
        let directory = manifest.parent().map(Path::to_path_buf).unwrap_or_default();
        let mut paths: Vec<PathBuf> = text
            .lines()
            .filter_map(|line| line.trim_start().strip_prefix("#include"))
            .filter_map(|rest| dm_preprocess::regions::literal_include_path(rest.trim()))
            .map(|relative| dm_preprocess::regions::canonical_path(&directory.join(relative)))
            .filter(|path| {
                path.extension()
                    .and_then(|extension| extension.to_str())
                    .is_some_and(|extension| extension.eq_ignore_ascii_case("dm") || extension.eq_ignore_ascii_case("dme"))
            })
            .collect();
        paths.push(manifest);
        paths.sort();
        paths.dedup();
        let entries: Vec<(PathBuf, Entry)> = {
            use rayon::prelude::*;
            paths.into_par_iter().map(|path| {
                let entry = read_entry(&path);
                (path, entry)
            }).collect()
        };
        let read = entries.len();
        let mut state = self.lock();
        for (path, entry) in entries {
            state.files.entry(path).or_insert(entry);
        }
        read
    }

    /// The provider the front end reads this request's sources through.
    pub fn provider(&self) -> Provider<'_> {
        Provider { sources: self }
    }
}

/// `SourceProvider` over a [`WatchedSources`]: kept texts, and a disk read (kept from then on) for a file not seen before.
pub struct Provider<'a> {
    sources: &'a WatchedSources,
}

impl Provider<'_> {
    fn entry(&self, path: &Path) -> Result<Arc<PreparedSource>, String> {
        if let Some(entry) = self.sources.lock().files.get(path) {
            return entry.text.clone();
        }
        let entry = read_entry(path);
        // A file first read in this revision is part of it: its later edits are what the next refresh reports.
        self.sources.lock().files.entry(path.to_path_buf()).or_insert(entry).text.clone()
    }
}

impl dm_preprocess::SourceProvider for Provider<'_> {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.entry(path).map(|prepared| prepared.original().as_str().to_owned())
    }

    fn prepared_source(&self, path: &Path) -> Option<Arc<PreparedSource>> {
        // An unreadable file is reported through `read`, which the planner asks when this declines.
        self.entry(path).ok()
    }

    fn revision(&self) -> Option<u64> {
        Some(self.sources.token())
    }

    fn changes_since(&self, token: u64) -> Option<Arc<BTreeSet<PathBuf>>> {
        if token >> TOKEN_REVISION_BITS != self.sources.id {
            return None;
        }
        let revision = token & ((1 << TOKEN_REVISION_BITS) - 1);
        let state = self.sources.lock();
        if revision > state.revision {
            return None;
        }
        let mut changed = BTreeSet::new();
        if revision == state.revision {
            return Some(Arc::new(changed));
        }
        let mut entries = state.log.iter().skip_while(|(_, after, _)| *after <= revision);
        let (before, _, paths) = entries.next()?;
        // The log must reach back to `revision`.
        if *before > revision {
            return None;
        }
        changed.extend(paths.iter().cloned());
        for (_, _, paths) in entries {
            changed.extend(paths.iter().cloned());
        }
        Some(Arc::new(changed))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_preprocess::SourceProvider;

    fn scratch(label: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("dmbc-watched-{label}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn a_sweep_reports_exactly_the_files_whose_bytes_changed() {
        let dir = scratch("sweep");
        let (a, b) = (dir.join("a.dm"), dir.join("b.dm"));
        std::fs::write(&a, "/a\n").unwrap();
        std::fs::write(&b, "/b\n").unwrap();
        let sources = WatchedSources::default();
        sources.refresh(&dir);
        let provider = sources.provider();
        assert_eq!(provider.read(&a).unwrap(), "/a\n");
        assert_eq!(provider.read(&b).unwrap(), "/b\n");
        let first = provider.revision().unwrap();
        // Nothing changed: same token, an empty change set.
        let refresh = sources.refresh(&dir);
        assert_eq!(refresh.changed, 0);
        assert_eq!(sources.provider().revision(), Some(first));
        assert!(sources.provider().changes_since(first).unwrap().is_empty());
        // One file rewritten with other bytes (and a stamp that moved), the other rewritten with the same bytes.
        std::thread::sleep(Duration::from_millis(20));
        std::fs::write(&a, "/a\n/a/var/x = 1\n").unwrap();
        std::fs::write(&b, "/b\n").unwrap();
        let refresh = sources.refresh(&dir);
        assert_eq!(refresh.changed, 1, "{refresh:?}");
        let provider = sources.provider();
        assert_eq!(provider.read(&a).unwrap(), "/a\n/a/var/x = 1\n");
        let changed = provider.changes_since(first).unwrap();
        assert_eq!(changed.iter().collect::<Vec<_>>(), vec![&a]);
        // A removed file is a change too, and reads as an error.
        std::fs::remove_file(&b).unwrap();
        assert_eq!(sources.refresh(&dir).changed, 1);
        assert!(sources.provider().read(&b).is_err());
        assert_eq!(sources.provider().changes_since(first).unwrap().len(), 2);
        // A token of another instance is never answered.
        assert!(WatchedSources::default().provider().changes_since(first).is_none());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_first_request_prefetches_the_manifest_includes_under_the_planner_path() {
        let dir = scratch("prefetch");
        std::fs::create_dir_all(dir.join("code")).unwrap();
        std::fs::write(dir.join("code").join("a.dm"), "/a\n").unwrap();
        std::fs::write(dir.join("p.dme"), "// x\n#include \"code\\a.dm\"\n#include \"missing.dm\"\n#include \"maps\\x.dmm\"\n").unwrap();
        let sources = WatchedSources::default();
        sources.refresh(&dir);
        assert_eq!(sources.prefetch_manifest(&dir.join("p.dme")), 3, "the manifest, a.dm and the missing file");
        let planner_path = dm_preprocess::regions::canonical_path(&dir.join("code").join("a.dm"));
        assert!(sources.lock().files.contains_key(&planner_path));
        assert_eq!(sources.provider().read(&planner_path).unwrap(), "/a\n");
        // Only when nothing is kept yet.
        assert_eq!(sources.prefetch_manifest(&dir.join("p.dme")), 0);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
