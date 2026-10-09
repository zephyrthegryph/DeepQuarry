//! Fixed-file output eviction under the same store lock as acquisition.
//! Never change inode attributes: resource files can have surviving hardlinks.
use super::{invalid, OutputPair, PairStore};
use std::{
    collections::BTreeSet,
    fs,
    io::{self, Read},
    path::{Path, PathBuf},
    time::{Duration, SystemTime},
};
#[derive(Debug, Default)]
pub struct EvictionResult {
    pub pairs: usize,
    pub resources: usize,
    pub protected_pairs: usize,
    pub deferred: Vec<PathBuf>,
}
impl PairStore {
    /// DESIGN's seven-day retention is supplied by the host, with an explicit
    /// clock for deterministic tests. Every session's last three pairs are roots.
    pub fn evict(&self, now: SystemTime, retention: Duration) -> io::Result<EvictionResult> {
        let _lock = self.lock()?;
        let mut roots = BTreeSet::new();
        for entry in fs::read_dir(self.root.join("sessions"))? {
            let entry = entry?;
            if !entry.file_type()?.is_file()
                || entry.path().extension().is_none_or(|ext| ext != "json")
            {
                continue;
            }
            let ids: Vec<u128> =
                serde_json::from_slice(&read_small(&entry.path())?).map_err(invalid)?;
            if ids.len() > 3 {
                return Err(invalid(
                    "pair session root count exceeds last-three contract",
                ));
            }
            roots.extend(ids);
        }
        // Preflight all manifests before deleting anything. An unreadable root
        // or manifest aborts maintenance, preserving potentially live outputs.
        let mut pairs = Vec::new();
        for entry in fs::read_dir(self.root.join("pairs"))? {
            let entry = entry?;
            if !entry.file_type()?.is_dir() {
                continue;
            }
            let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
                continue;
            };
            if name.len() != 32 {
                continue;
            }
            let Ok(id) = u128::from_str_radix(&name, 16) else {
                continue;
            };
            let pair: OutputPair =
                serde_json::from_slice(&read_small(&entry.path().join("pair.json"))?)
                    .map_err(invalid)?;
            if pair.version != 1
                || pair.id != id
                || OutputPair::from_hashes(
                    pair.dmb_bytes,
                    pair.dmb_hash,
                    pair.rsc_bytes,
                    pair.rsc_hash,
                ) != pair
            {
                return Err(invalid("eviction pair manifest identity differs"));
            }
            let old = now
                .duration_since(entry.metadata()?.modified()?)
                .unwrap_or_default()
                > retention;
            pairs.push((entry.path(), pair, old));
        }
        let mut result = EvictionResult::default();
        let mut archives = BTreeSet::new();
        for (path, pair, old) in pairs {
            let protected = roots.contains(&pair.id);
            if protected {
                result.protected_pairs += 1;
            }
            if old && !protected {
                if unlink_pair(&path).is_ok() {
                    result.pairs += 1;
                    let _ = fs::remove_file(
                        self.root
                            .join("verified")
                            .join(format!("{:032x}.json", pair.id)),
                    );
                    self.verified
                        .lock()
                        .map_err(|_| invalid("pair verification lock poisoned"))?
                        .remove(&pair.id);
                    continue;
                }
                result.deferred.push(path);
            }
            archives.insert(format!("{:032x}-{}.rsc", pair.rsc_hash, pair.rsc_bytes));
        }
        for entry in fs::read_dir(self.root.join("resources"))? {
            let entry = entry?;
            if !entry.file_type()?.is_file() {
                continue;
            }
            let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
                continue;
            };
            if archives.contains(&name) {
                continue;
            }
            let Some(identity) = archive_identity(&name) else {
                continue;
            };
            if now
                .duration_since(entry.metadata()?.modified()?)
                .unwrap_or_default()
                <= retention
            {
                continue;
            }
            match unlink_immutable(&entry.path()) {
                Ok(()) => {
                    result.resources += 1;
                    self.verified_resources
                        .lock()
                        .map_err(|_| invalid("resource verification lock poisoned"))?
                        .remove(&(identity.bytes, identity.hash));
                    let _ = fs::remove_file(self.root.join("verified").join(format!(
                        "resource-{:032x}-{}.json",
                        identity.hash, identity.bytes
                    )));
                }
                Err(_) => result.deferred.push(entry.path()),
            }
        }
        Ok(result)
    }
}
fn archive_identity(name: &str) -> Option<super::ResourceIdentity> {
    let (hash, len) = name.strip_suffix(".rsc")?.split_once('-')?;
    if hash.len() != 32 {
        return None;
    }
    Some(super::ResourceIdentity {
        hash: u128::from_str_radix(hash, 16).ok()?,
        bytes: len.parse().ok()?,
    })
}
fn read_small(path: &Path) -> io::Result<Vec<u8>> {
    let mut file = fs::File::open(path)?;
    if file.metadata()?.len() > 32768 {
        return Err(invalid("eviction root manifest too large"));
    }
    let mut bytes = Vec::new();
    Read::by_ref(&mut file)
        .take(32769)
        .read_to_end(&mut bytes)?;
    if bytes.len() > 32768 {
        return Err(invalid("eviction root manifest grew during read"));
    }
    Ok(bytes)
}
fn unlink_pair(path: &Path) -> io::Result<()> {
    // Only published fixed children are removed; unexpected files keep the
    // directory deferred. No traversal into links or arbitrary nested paths.
    for name in ["deepquarry.dmb", "deepquarry.rsc", "pair.json"] {
        match unlink_immutable(&path.join(name)) {
            Ok(()) => (),
            Err(error) if error.kind() == io::ErrorKind::NotFound => (),
            Err(error) => return Err(error),
        }
    }
    fs::remove_dir(path)
}
#[cfg(not(windows))]
pub(super) fn unlink_immutable(path: &Path) -> io::Result<()> {
    fs::remove_file(path)
}
#[cfg(windows)]
pub(super) fn unlink_immutable(path: &Path) -> io::Result<()> {
    use std::os::windows::{fs::OpenOptionsExt, io::AsRawHandle};
    #[link(name = "kernel32")]
    extern "system" {
        fn SetFileInformationByHandle(
            handle: *mut core::ffi::c_void,
            class: i32,
            information: *const core::ffi::c_void,
            bytes: u32,
        ) -> i32;
    }
    let file = fs::OpenOptions::new()
        .access_mode(0x0001_0000 | 0x80)
        .share_mode(7)
        .custom_flags(0x0020_0000)
        .open(path)?;
    // FileDispositionInfoEx=21, DELETE|POSIX_SEMANTICS|IGNORE_READONLY_ATTRIBUTE.
    // Microsoft STL uses this same Windows10+ operation. Unlike clearing the
    // read-only bit, it cannot change any surviving resource hardlink's attributes.
    // Unsupported systems are deferred rather than taking an unsafe fallback.
    let flags = 0x13u32;
    let success = unsafe {
        SetFileInformationByHandle(file.as_raw_handle(), 21, (&flags as *const u32).cast(), 4)
    };
    if success == 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Barrier};
    struct Temp(PairStore);
    impl Temp {
        fn new() -> Self {
            let sequence =
                super::super::TEMP_SEQUENCE.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            Self(
                PairStore::open(
                    std::env::temp_dir()
                        .join(format!("dmb-eviction-{}-{sequence}", std::process::id())),
                )
                .unwrap(),
            )
        }
    }
    impl Drop for Temp {
        fn drop(&mut self) {
            if let Ok(entries) = fs::read_dir(self.0.root.join("pairs")) {
                for entry in entries.flatten() {
                    let _ = unlink_pair(&entry.path());
                }
            }
            if let Ok(entries) = fs::read_dir(self.0.root.join("resources")) {
                for entry in entries.flatten() {
                    let _ = unlink_immutable(&entry.path());
                }
            }
            let _ = fs::remove_dir_all(&self.0.root);
        }
    }
    #[test]
    fn eviction_preserves_last_three_pairs_and_acquired_slots_without_attribute_changes() {
        let root = Temp::new();
        let store = &root.0;
        let first = store.publish(7, b"world-0", b"resource-0").unwrap();
        let slot = store.acquire(first.id, store.root.join("slots")).unwrap();
        let mut retained = Vec::new();
        for number in 1..=3 {
            retained.push(
                store
                    .publish(7, format!("world-{number}").as_bytes(), b"shared")
                    .unwrap(),
            );
        }
        let shared = store.root.join("resources").join(format!(
            "{:032x}-{}.rsc",
            retained[0].rsc_hash, retained[0].rsc_bytes
        ));
        assert!(fs::metadata(&shared).unwrap().permissions().readonly());
        let result = store
            .evict(
                SystemTime::now() + Duration::from_secs(8 * 86400),
                Duration::from_secs(7 * 86400),
            )
            .unwrap();
        assert_eq!(result.pairs, 1);
        assert_eq!(result.resources, 1);
        assert_eq!(result.protected_pairs, 3);
        assert!(store.verify(first.id, true).is_err());
        for pair in retained {
            store.verify(pair.id, true).unwrap();
        }
        assert_eq!(fs::read(slot.join("deepquarry.dmb")).unwrap(), b"world-0");
        assert_eq!(
            fs::read(slot.join("deepquarry.rsc")).unwrap(),
            b"resource-0"
        );
        assert!(fs::metadata(shared).unwrap().permissions().readonly());
    }
    #[test]
    fn malformed_session_roots_abort_before_any_pair_is_removed() {
        let root = Temp::new();
        let store = &root.0;
        let first = store.publish(9, b"world", b"resource").unwrap();
        fs::write(
            store.root.join("sessions").join(format!("{:032x}.json", 9)),
            b"truncated root",
        )
        .unwrap();
        assert!(store
            .evict(
                SystemTime::now() + Duration::from_secs(8 * 86400),
                Duration::from_secs(7 * 86400)
            )
            .is_err());
        store.verify(first.id, true).unwrap();
    }
    #[test]
    fn acquisition_racing_eviction_returns_whole_slot_or_absence() {
        let root = Temp::new();
        let store = Arc::new(PairStore::open(&root.0.root).unwrap());
        let first = store.publish(1, b"old-world", b"old-resource").unwrap();
        for number in 0..3 {
            store
                .publish(1, format!("next-{number}").as_bytes(), b"new-resource")
                .unwrap();
        }
        let barrier = Arc::new(Barrier::new(2));
        std::thread::scope(|scope| {
            let publisher = Arc::clone(&store);
            let ready = Arc::clone(&barrier);
            let evict = scope.spawn(move || {
                ready.wait();
                publisher
                    .evict(
                        SystemTime::now() + Duration::from_secs(8 * 86400),
                        Duration::from_secs(7 * 86400),
                    )
                    .unwrap()
            });
            barrier.wait();
            let acquired = store.acquire(first.id, store.root.join("racing-slots"));
            evict.join().unwrap();
            match acquired {
                Ok(slot) => {
                    assert_eq!(fs::read(slot.join("deepquarry.dmb")).unwrap(), b"old-world");
                    assert_eq!(
                        fs::read(slot.join("deepquarry.rsc")).unwrap(),
                        b"old-resource"
                    );
                }
                Err(error) => assert_eq!(error.kind(), io::ErrorKind::NotFound),
            }
        });
    }
}
