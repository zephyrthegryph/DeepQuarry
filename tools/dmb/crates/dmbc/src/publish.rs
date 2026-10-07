//! Immutable output pairs. Acquisition and publication share one OS lock.
//!
//! Run slots are writable copies: the Phase 0 engine probe rejected read-only
//! hardlinks. Conventional output installation is intentionally a separate step.

use fs2::FileExt;
use serde::{Deserialize, Serialize};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use xxhash_rust::xxh3::{xxh3_128, Xxh3};

static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct OutputPair {
    pub version: u32,
    pub id: u128,
    pub dmb_bytes: u64,
    pub dmb_hash: u128,
    pub rsc_bytes: u64,
    pub rsc_hash: u128,
}

impl OutputPair {
    pub fn from_bytes(dmb: &[u8], rsc: &[u8]) -> Self {
        Self::from_hashes(
            dmb.len() as u64,
            xxh3_128(dmb),
            rsc.len() as u64,
            xxh3_128(rsc),
        )
    }

    fn from_hashes(dmb_bytes: u64, dmb_hash: u128, rsc_bytes: u64, rsc_hash: u128) -> Self {
        let mut identity = Vec::from(&b"dmbd-output-pair-v1\0"[..]);
        identity.extend_from_slice(&dmb_bytes.to_le_bytes());
        identity.extend_from_slice(&dmb_hash.to_le_bytes());
        identity.extend_from_slice(&rsc_bytes.to_le_bytes());
        identity.extend_from_slice(&rsc_hash.to_le_bytes());
        Self {
            version: 1,
            id: xxh3_128(&identity),
            dmb_bytes,
            dmb_hash,
            rsc_bytes,
            rsc_hash,
        }
    }

    pub fn name(&self) -> String {
        format!("{:032x}", self.id)
    }
}

pub struct PairStore {
    root: PathBuf,
}

/// Content identity of an archive already owned by this store. A cold linker
/// can reuse this handle without loading the archive into its output buffer.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResourceIdentity {
    pub bytes: u64,
    pub hash: u128,
}

impl PairStore {
    /// The caller selects a store on the output volume; no drive-root permission
    /// or junction behavior is assumed here.
    pub fn open(root: impl AsRef<Path>) -> io::Result<Self> {
        fs::create_dir_all(root.as_ref())?;
        let root = fs::canonicalize(root)?;
        for name in ["pairs", "resources", "sessions", "temporary", "quarantine"] {
            fs::create_dir_all(root.join(name))?;
        }
        Ok(Self { root })
    }

    fn lock(&self) -> io::Result<File> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.root.join("store.lock"))?;
        file.lock_exclusive()?;
        Ok(file)
    }

    fn temporary(&self, prefix: &str) -> io::Result<PathBuf> {
        loop {
            let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let path = self
                .root
                .join("temporary")
                .join(format!("{prefix}-{}-{sequence}", std::process::id()));
            match fs::create_dir(&path) {
                Ok(()) => return Ok(path),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
    }

    /// Writes only new immutable content. The last-three record is updated while
    /// the store lock is still held, closing the publication/eviction race.
    pub fn publish(&self, session: u128, dmb: &[u8], rsc: &[u8]) -> io::Result<OutputPair> {
        let pair = OutputPair::from_bytes(dmb, rsc);
        self.publish_inner(session, dmb, pair, Some(rsc))
    }

    /// Compose a new DMB with a previously published archive. Authentication
    /// remains mandatory, but no RSC-sized allocation or archive rewrite occurs.
    pub fn publish_with_resource(
        &self,
        session: u128,
        dmb: &[u8],
        resource: ResourceIdentity,
    ) -> io::Result<OutputPair> {
        let pair = OutputPair::from_hashes(
            dmb.len() as u64,
            xxh3_128(dmb),
            resource.bytes,
            resource.hash,
        );
        self.publish_inner(session, dmb, pair, None)
    }

    fn publish_inner(
        &self,
        session: u128,
        dmb: &[u8],
        pair: OutputPair,
        rsc: Option<&[u8]>,
    ) -> io::Result<OutputPair> {
        let _lock = self.lock()?;
        let destination = self.root.join("pairs").join(pair.name());
        if let Ok(existing) = validate_directory(&destination, pair.id) {
            if existing != pair {
                return Err(invalid("output pair identity collision"));
            }
            self.record_session(session, pair.id)?;
            return Ok(pair);
        }
        let temp = self.temporary("pair")?;
        fs::write(temp.join("deepquarry.dmb"), dmb)?;
        let resource = self
            .root
            .join("resources")
            .join(format!("{:032x}-{}.rsc", pair.rsc_hash, pair.rsc_bytes));
        if resource.exists() {
            if file_identity(&resource)? != (pair.rsc_bytes, pair.rsc_hash) {
                return Err(invalid("shared RSC bytes do not match identity"));
            }
        } else {
            let rsc =
                rsc.ok_or_else(|| invalid("shared RSC identity is absent from this store"))?;
            let staged = self.temporary("resource")?.join("archive.rsc");
            fs::write(&staged, rsc)?;
            if file_identity(&staged)? != (pair.rsc_bytes, pair.rsc_hash) {
                return Err(invalid("new RSC bytes do not match identity"));
            }
            let mut permissions = fs::metadata(&staged)?.permissions();
            permissions.set_readonly(true);
            fs::set_permissions(&staged, permissions)?;
            fs::rename(staged, &resource)?;
        }
        if fs::hard_link(&resource, temp.join("deepquarry.rsc")).is_err() {
            fs::copy(&resource, temp.join("deepquarry.rsc"))?;
        }
        write_json(&temp.join("pair.json"), &pair)?;
        validate_directory(&temp, pair.id)?;
        for name in ["deepquarry.dmb", "deepquarry.rsc", "pair.json"] {
            let path = temp.join(name);
            let mut permissions = fs::metadata(&path)?.permissions();
            permissions.set_readonly(true);
            fs::set_permissions(path, permissions)?;
        }
        if destination.exists() {
            if validate_directory(&destination, pair.id).is_err() {
                // Do not change attributes: existing hardlink readers may exist.
                let quarantine = self.temporary("quarantine")?;
                let name = quarantine.file_name().expect("temporary basename");
                fs::rename(&destination, self.root.join("quarantine").join(name))?;
                fs::rename(&temp, &destination)?;
            }
        } else {
            fs::rename(&temp, &destination)?;
        }
        self.record_session(session, pair.id)?;
        Ok(pair)
    }

    fn record_session(&self, session: u128, pair: u128) -> io::Result<()> {
        let path = self
            .root
            .join("sessions")
            .join(format!("{session:032x}.json"));
        let mut pairs: Vec<u128> = match fs::read(&path) {
            Ok(bytes) => serde_json::from_slice(&bytes).map_err(invalid)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => Vec::new(),
            Err(error) => return Err(error),
        };
        pairs.retain(|&id| id != pair);
        pairs.insert(0, pair);
        pairs.truncate(3);
        let temp = self.temporary("session")?.join("record.json");
        write_json(&temp, &pairs)?;
        // Session records are mutable hints protected by the store lock. Keep
        // the old complete record until replacement succeeds on every platform.
        atomic_replace(&temp, &path)
    }

    /// Authenticate on every acquisition for now. Later boot/stamp memoization
    /// may avoid repeated hashing without weakening first-use validation.
    pub fn acquire(&self, id: u128, slots: impl AsRef<Path>) -> io::Result<PathBuf> {
        let _lock = self.lock()?;
        let source = self.root.join("pairs").join(format!("{id:032x}"));
        let pair = validate_directory(&source, id)?;
        fs::create_dir_all(slots.as_ref())?;
        let slot = loop {
            let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let path = slots
                .as_ref()
                .join(format!("slot-{}-{sequence}", std::process::id()));
            match fs::create_dir(&path) {
                Ok(()) => break path,
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        };
        for name in ["deepquarry.dmb", "deepquarry.rsc"] {
            let destination = slot.join(name);
            // fs::copy copies read-only permissions too. Create a writable new
            // inode explicitly instead of clearing attributes on any shared file.
            let mut input = File::open(source.join(name))?;
            let mut output = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(destination)?;
            io::copy(&mut input, &mut output)?;
        }
        write_json(&slot.join("pair.json"), &pair)?;
        validate_directory(&slot, id)?;
        fs::write(slot.join("slot-complete"), pair.name())?;
        Ok(slot)
    }

    /// Conventional output paths are compatibility copies, never run-slot
    /// authority. Publish RSC, DMB, then the marker; a crash can leave copies
    /// mismatched, and the next successful installation repairs them.
    pub fn install(&self, id: u128, dmb: &Path, rsc: &Path, marker: &Path) -> io::Result<()> {
        if dmb == rsc || dmb == marker || rsc == marker {
            return Err(invalid("conventional output paths must be distinct"));
        }
        let _lock = self.lock()?;
        let source = self.root.join("pairs").join(format!("{id:032x}"));
        let pair = validate_directory(&source, id)?;
        replace_copy(&source.join("deepquarry.rsc"), rsc)?;
        replace_copy(&source.join("deepquarry.dmb"), dmb)?;
        let staged = temporary_file(marker)?;
        write_json(&staged, &pair)?;
        atomic_replace(&staged, marker)
    }
}

fn temporary_file(destination: &Path) -> io::Result<PathBuf> {
    let parent = destination
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    fs::create_dir_all(parent)?;
    loop {
        let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let path = parent.join(format!(
            ".dmbd-install-{}-{sequence}.tmp",
            std::process::id()
        ));
        match OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(_) => return Ok(path),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
}

fn replace_copy(source: &Path, destination: &Path) -> io::Result<()> {
    let staged = temporary_file(destination)?;
    {
        let mut input = File::open(source)?;
        let mut output = OpenOptions::new()
            .write(true)
            .truncate(true)
            .open(&staged)?;
        io::copy(&mut input, &mut output)?;
    }
    if file_identity(source)? != file_identity(&staged)? {
        return Err(invalid("conventional copy failed authentication"));
    }
    atomic_replace(&staged, destination)
}

#[cfg(not(windows))]
fn atomic_replace(source: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(source, destination)
}

#[cfg(windows)]
fn atomic_replace(source: &Path, destination: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "kernel32")]
    extern "system" {
        fn MoveFileExW(existing: *const u16, replacement: *const u16, flags: u32) -> i32;
    }
    fn wide(path: &Path) -> io::Result<Vec<u16>> {
        let mut result: Vec<_> = path.as_os_str().encode_wide().collect();
        if result.contains(&0) {
            return Err(invalid("path contains NUL"));
        }
        result.push(0);
        Ok(result)
    }
    let source = wide(source)?;
    let destination = wide(destination)?;
    // Both terminated UTF-16 buffers outlive the call. REPLACE_EXISTING preserves
    // the old destination if Windows rejects replacement because it is locked.
    let result = unsafe { MoveFileExW(source.as_ptr(), destination.as_ptr(), 1) };
    if result == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

fn write_json(path: &Path, value: &impl Serialize) -> io::Result<()> {
    fs::write(path, serde_json::to_vec(value).map_err(invalid)?)
}

fn invalid(error: impl std::fmt::Display) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, error.to_string())
}

fn file_identity(path: &Path) -> io::Result<(u64, u128)> {
    let mut file = File::open(path)?;
    let mut hasher = Xxh3::new();
    let mut bytes = 0u64;
    let mut buffer = [0u8; 65536];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        bytes += count as u64;
        hasher.update(&buffer[..count]);
    }
    Ok((bytes, hasher.digest128()))
}

fn validate_directory(path: &Path, id: u128) -> io::Result<OutputPair> {
    let pair: OutputPair =
        serde_json::from_slice(&fs::read(path.join("pair.json"))?).map_err(invalid)?;
    if pair.version != 1 || pair.id != id {
        return Err(invalid("unsupported or mismatched pair manifest"));
    }
    let (dmb_bytes, dmb_hash) = file_identity(&path.join("deepquarry.dmb"))?;
    let (rsc_bytes, rsc_hash) = file_identity(&path.join("deepquarry.rsc"))?;
    let actual = OutputPair::from_hashes(dmb_bytes, dmb_hash, rsc_bytes, rsc_hash);
    if actual != pair {
        return Err(invalid("output pair bytes do not match manifest"));
    }
    Ok(pair)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> PairStore {
        let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        PairStore::open(
            std::env::temp_dir().join(format!("dmb-pair-test-{}-{sequence}", std::process::id())),
        )
        .unwrap()
    }

    #[test]
    fn changing_dmb_reuses_resource_and_acquires_writable_copy() {
        let store = store();
        let first = store.publish(1, b"world-one", b"shared-resources").unwrap();
        let second = store.publish(1, b"world-two", b"shared-resources").unwrap();
        assert_ne!(first.id, second.id);
        assert_eq!(
            fs::read_dir(store.root.join("resources")).unwrap().count(),
            1
        );
        let slot = store.acquire(second.id, store.root.join("slots")).unwrap();
        assert_eq!(fs::read(slot.join("deepquarry.dmb")).unwrap(), b"world-two");
        assert_eq!(
            fs::read(slot.join("deepquarry.rsc")).unwrap(),
            b"shared-resources"
        );
        fs::write(slot.join("deepquarry.rsc"), b"runtime writes").unwrap();
        let pair = store.root.join("pairs").join(second.name());
        assert_eq!(validate_directory(&pair, second.id).unwrap(), second);
        assert!(slot.join("slot-complete").exists());
    }

    #[test]
    fn archive_identity_composes_without_archive_input() {
        let store = store();
        let first = store.publish(1, b"first", b"assets").unwrap();
        let resource = ResourceIdentity {
            bytes: first.rsc_bytes,
            hash: first.rsc_hash,
        };
        let second = store.publish_with_resource(1, b"second", resource).unwrap();
        assert_eq!(second, OutputPair::from_bytes(b"second", b"assets"));
        assert_eq!(
            fs::read_dir(store.root.join("resources")).unwrap().count(),
            1
        );
        let slots = store.root.join("slots");
        let slot = store.acquire(second.id, slots).unwrap();
        assert_eq!(fs::read(slot.join("deepquarry.rsc")).unwrap(), b"assets");
        let missing = ResourceIdentity { hash: 0, bytes: 1 };
        let absent = OutputPair::from_hashes(4, xxh3_128(b"next"), 1, 0);
        assert!(store.publish_with_resource(1, b"next", missing).is_err());
        assert!(!store.root.join("pairs").join(absent.name()).exists());
    }

    #[test]
    fn duplicate_publication_and_session_history_are_coherent() {
        let store = store();
        let mut expected = Vec::new();
        for byte in 0..5 {
            let pair = store.publish(7, &[byte], b"resource").unwrap();
            assert_eq!(store.publish(7, &[byte], b"resource").unwrap(), pair);
            expected.insert(0, pair.id);
        }
        expected.truncate(3);
        let actual: Vec<u128> = serde_json::from_slice(
            &fs::read(
                store
                    .root
                    .join("sessions/00000000000000000000000000000007.json"),
            )
            .unwrap(),
        )
        .unwrap();
        assert_eq!(actual, expected);
        assert_eq!(fs::read_dir(store.root.join("pairs")).unwrap().count(), 5);
    }

    #[test]
    fn conventional_paths_replace_existing_copies_and_marker_last() {
        let store = store();
        let root = store.root.join("worktree");
        let dmb = root.join("deepquarry.dmb");
        let rsc = root.join("deepquarry.rsc");
        let marker = root.join("deepquarry.pair");
        let first = store.publish(3, b"first", b"assets-one").unwrap();
        store.install(first.id, &dmb, &rsc, &marker).unwrap();
        let second = store.publish(3, b"second", b"assets-two").unwrap();
        store.install(second.id, &dmb, &rsc, &marker).unwrap();
        assert_eq!(fs::read(&dmb).unwrap(), b"second");
        assert_eq!(fs::read(&rsc).unwrap(), b"assets-two");
        let actual: OutputPair = serde_json::from_slice(&fs::read(marker).unwrap()).unwrap();
        assert_eq!(actual, second);
    }

    #[test]
    fn same_length_corruption_is_rejected_before_slot_exposure() {
        let store = store();
        let pair = store.publish(1, b"original", b"resource").unwrap();
        let path = store.root.join("pairs").join(pair.name()).join("pair.json");
        // Change an unlinked manifest by replacing its directory entry. Leave
        // immutable inode permissions unchanged, as real acquisition must do.
        let replacement = path.with_extension("replacement");
        let mut false_manifest = pair.clone();
        false_manifest.dmb_hash ^= 1;
        write_json(&replacement, &false_manifest).unwrap();
        fs::rename(&path, path.with_extension("original")).unwrap();
        fs::rename(replacement, path).unwrap();
        let slots = store.root.join("slots");
        assert!(store.acquire(pair.id, &slots).is_err());
        assert!(!slots.exists());
    }
}
