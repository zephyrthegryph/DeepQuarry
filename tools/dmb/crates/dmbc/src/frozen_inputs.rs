//! Opt-in verification journal. Replay never consults the live filesystem.
//! Payloads live on disk; recording does not retain the asset corpus in RAM.
use crate::input_snapshot::{
    CapturedInputRead, FileSystemInputs, FolderListing, SnapshotProvider, Stamp,
};
use dm_preprocess::regions::canonical_path;
use serde::{Deserialize, Serialize};
use std::{
    borrow::Cow,
    collections::{BTreeMap, BTreeSet},
    fs, io,
    path::{Path, PathBuf},
    sync::Mutex,
};

#[derive(Default, Serialize, Deserialize)]
struct Index {
    files: BTreeMap<PathBuf, (Stamp, u128)>,
    negative: BTreeSet<PathBuf>,
    folders: BTreeMap<PathBuf, FolderListing>,
    // Versioned physical evidence is optional: old journals remain valid for
    // observed-only replay, but cannot license strict physical containment.
    #[serde(default)]
    physical_v1: BTreeMap<PathBuf, physical_paths::Proof>,
}
#[path = "frozen_inputs/physical_paths.rs"]
mod physical_paths;

impl Index {
    fn lookup_path<'a>(&'a self, path: &Path) -> Cow<'a, Path> {
        if let Some((key, _)) = self.files.get_key_value(path) {
            return Cow::Borrowed(key);
        }
        if let Some(key) = self.negative.get(path) {
            return Cow::Borrowed(key);
        }
        if let Some((key, _)) = self.folders.get_key_value(path) {
            return Cow::Borrowed(key);
        }
        Cow::Owned(canonical_path(path))
    }
}
pub enum Inputs {
    Live,
    Recording(Journal),
    Replay(Journal),
}
pub struct Journal {
    directory: PathBuf,
    index: Mutex<Index>,
}
/// Borrowed observations from this journal, not an assertion that either
/// compiler's entire input/search/configuration closure has been captured.
/// The callback must not re-enter the same Inputs: its index is locked.
pub struct JournalAccessView<'a> {
    journal: &'a Journal,
    index: &'a Index,
}
/// One recorded file owner. Payload loading is explicit and independently
/// verified; enumerating the view never loads the complete asset corpus.
pub struct JournalFileAccess<'a> {
    pub path: &'a Path,
    pub stamp: &'a Stamp,
    pub content: u128,
    journal: &'a Journal,
}
impl JournalFileAccess<'_> {
    pub fn read_verified(&self) -> io::Result<CapturedInputRead> {
        self.journal.read_payload(self.stamp.clone(), self.content)
    }
}
impl JournalAccessView<'_> {
    /// Capture-time no-reparse path proof; never probes the replay filesystem.
    /// Returns the recorded root file identity for cross-demand consistency.
    pub fn physical_root_identity(&self, path: &Path, root: &Path) -> io::Result<u128> {
        let path = canonical_path(path);
        let proof = self.index.physical_v1.get(&path).ok_or_else(||
            io::Error::new(io::ErrorKind::Unsupported, "journal has no capture-time physical path authority"))?;
        for ancestor in proof.ancestors() {
            if let Some(other) = self.index.physical_v1.get(ancestor) {
                if !proof.agrees_with(other) {
                    return Err(invalid("journal physical ancestor identity changed during capture"));
                }
            }
        }
        proof.contained_root_identity(&path, root)
    }
    pub fn files(&self) -> impl Iterator<Item = JournalFileAccess<'_>> {
        self.index.files.iter().map(|(path, (stamp, content))| JournalFileAccess {
            path, stamp, content: *content, journal: self.journal,
        })
    }
    pub fn negative_paths(&self) -> impl Iterator<Item = &Path> {
        self.index.negative.iter().map(PathBuf::as_path)
    }
    pub fn folders(&self) -> impl Iterator<Item = (&Path, &FolderListing)> {
        self.index.folders.iter().map(|(path, listing)| (path.as_path(), listing))
    }
}
fn invalid(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message.into())
}
impl Inputs {
    /// Visit the existing journal's current borrowed roster. Live providers
    /// have no issued journal and return None. This does not finalize recording.
    pub fn with_access_view<R>(
        &self,
        visit: impl FnOnce(JournalAccessView<'_>) -> io::Result<R>,
    ) -> io::Result<Option<R>> {
        let journal = match self {
            Self::Live => return Ok(None),
            Self::Recording(journal) | Self::Replay(journal) => journal,
        };
        let index = journal.index.lock().map_err(|_| invalid("verification mutex poisoned"))?;
        visit(JournalAccessView { journal, index: &index }).map(Some)
    }
    pub fn record(directory: &Path) -> io::Result<Self> {
        fs::create_dir(directory)?;
        fs::create_dir(directory.join("payloads"))?;
        Ok(Self::Recording(Journal {
            directory: directory.to_owned(),
            index: Mutex::new(Index::default()),
        }))
    }
    pub fn replay(directory: &Path) -> io::Result<Self> {
        let bytes = fs::read(directory.join("index.json"))?;
        if bytes.len() > 64 * 1024 * 1024 {
            return Err(invalid("verification index exceeds bound"));
        }
        let hash = fs::read(directory.join("index.hash"))?;
        if hash.as_slice() != xxhash_rust::xxh3::xxh3_128(&bytes).to_le_bytes() {
            return Err(invalid("verification index checksum mismatch"));
        }
        let index: Index = serde_json::from_slice(&bytes).map_err(|e| invalid(e.to_string()))?;
        if index.files.keys().any(|path| index.negative.contains(path)) {
            return Err(invalid("verification input is both present and absent"));
        }
        Ok(Self::Replay(Journal {
            directory: directory.to_owned(),
            index: Mutex::new(index),
        }))
    }
    pub fn finish(&self) -> io::Result<()> {
        if let Self::Recording(journal) = self {
            let index = journal
                .index
                .lock()
                .map_err(|_| invalid("verification mutex poisoned"))?;
            let body = serde_json::to_vec(&*index).map_err(|e| invalid(e.to_string()))?;
            fs::write(
                journal.directory.join("index.hash"),
                xxhash_rust::xxh3::xxh3_128(&body).to_le_bytes(),
            )?;
            fs::write(journal.directory.join("index.json"), body)?;
        }
        Ok(())
    }
}
impl Drop for Inputs {
    fn drop(&mut self) {
        let _ = self.finish();
    }
}
impl Journal {
    fn read_payload(&self, stamp: Stamp, hash: u128) -> io::Result<CapturedInputRead> {
        let bytes = dm_profile::io_call(
            || fs::read(self.payload(hash)),
            |bytes| (bytes.len() as u64, 0),
        )?;
        if bytes.len() as u64 != stamp.size || xxhash_rust::xxh3::xxh3_128(&bytes) != hash {
            return Err(invalid("verification payload checksum mismatch"));
        }
        Ok(CapturedInputRead::from_verified(stamp, bytes, hash))
    }
    fn payload(&self, hash: u128) -> PathBuf {
        self.directory.join("payloads").join(format!("{hash:032x}"))
    }
    fn missing(path: &Path) -> io::Error {
        io::Error::new(
            io::ErrorKind::NotFound,
            format!("captured missing input {}", path.display()),
        )
    }
    fn unknown(path: &Path) -> io::Error {
        invalid(format!(
            "oracle requested uncaptured input {}",
            path.display()
        ))
    }
}
impl SnapshotProvider for Inputs {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        if let Self::Replay(journal) = self {
            let index = journal
                .index
                .lock()
                .map_err(|_| invalid("verification mutex poisoned"))?;
            let path = index.lookup_path(path);
            return match index.files.get(path.as_ref()) {
                Some((stamp, _)) => Ok(stamp.clone()),
                None if index.negative.contains(path.as_ref()) => {
                    Err(Journal::missing(path.as_ref()))
                }
                None => Err(Journal::unknown(path.as_ref())),
            };
        }
        FileSystemInputs.stamp(path)
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        let (stamp, bytes, _) = self.read_verified(path)?.into_parts();
        Ok((stamp, bytes))
    }
    fn read_verified(&self, path: &Path) -> io::Result<CapturedInputRead> {
        if let Self::Replay(journal) = self {
            let (stamp, hash) = {
                let index = journal
                    .index
                    .lock()
                    .map_err(|_| invalid("verification mutex poisoned"))?;
                let path = index.lookup_path(path);
                match index.files.get(path.as_ref()) {
                    Some(value) => value.clone(),
                    None if index.negative.contains(path.as_ref()) => {
                        return Err(Journal::missing(path.as_ref()))
                    }
                    None => return Err(Journal::unknown(path.as_ref())),
                }
            };
            return journal.read_payload(stamp, hash);
        }
        let path = canonical_path(path);
        match self {
            Self::Live => FileSystemInputs.read_verified(&path),
            Self::Recording(journal) => {
                let physical = physical_paths::capture(&path).ok();
                let result = FileSystemInputs.read_verified(&path);
                let mut index = journal
                    .index
                    .lock()
                    .map_err(|_| invalid("verification mutex poisoned"))?;
                match result {
                    Ok(read) => {
                        let stamp = read.stamp();
                        let bytes = read.bytes();
                        let hash = read.content();
                        if index.negative.contains(&path)
                            || index
                                .files
                                .get(&path)
                                .is_some_and(|previous| previous != &(stamp.clone(), hash))
                        {
                            return Err(invalid("verification input changed during capture"));
                        }
                        let payload = journal.payload(hash);
                        if !payload.exists() {
                            fs::write(payload, bytes)?;
                        }
                        if let Some(guard) = physical.filter(|guard| guard.proof().present() && !guard.proof().terminal_directory()) {
                            index.physical_v1.insert(path.clone(), guard.proof());
                        } else {
                            index.physical_v1.remove(&path);
                        }
                        index.files.insert(path, (stamp.clone(), hash));
                        Ok(read)
                    }
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {
                        if index.files.contains_key(&path) {
                            return Err(invalid("verification input disappeared during capture"));
                        }
                        if let Some(guard) = physical.filter(|guard| !guard.proof().present() || guard.proof().terminal_directory()) {
                            index.physical_v1.insert(path.clone(), guard.proof());
                        } else {
                            index.physical_v1.remove(&path);
                        }
                        index.negative.insert(path);
                        Err(error)
                    }
                    Err(error) => Err(error),
                }
            }
            Self::Replay(_) => unreachable!("replay handled before path normalization"),
        }
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        if let Self::Replay(journal) = self {
            let index = journal
                .index
                .lock()
                .map_err(|_| invalid("verification mutex poisoned"))?;
            let path = index.lookup_path(path);
            return index
                .folders
                .get(path.as_ref())
                .cloned()
                .ok_or_else(|| Journal::unknown(path.as_ref()));
        }
        let path = canonical_path(path);
        match self {
            Self::Live => FileSystemInputs.list(&path),
            Self::Recording(journal) => {
                let physical = physical_paths::capture(&path).ok();
                let listing = FileSystemInputs.list(&path)?;
                let mut index = journal
                    .index
                    .lock()
                    .map_err(|_| invalid("verification mutex poisoned"))?;
                if index
                    .folders
                    .get(&path)
                    .is_some_and(|previous| previous != &listing)
                {
                    return Err(invalid("verification search folder changed during capture"));
                }
                if let Some(guard) = physical.filter(|guard| match &listing {
                    FolderListing::Missing => !guard.proof().present(),
                    FolderListing::Present(_) => guard.proof().present() && guard.proof().terminal_directory(),
                }) {
                    index.physical_v1.insert(path.clone(), guard.proof());
                } else {
                    index.physical_v1.remove(&path);
                }
                index.folders.insert(path, listing.clone());
                Ok(listing)
            }
            Self::Replay(_) => unreachable!("replay handled before path normalization"),
        }
    }
    fn digest(&self, path: &Path) -> io::Result<(Stamp, u128)> {
        if matches!(self, Self::Live) {
            return FileSystemInputs.digest(path);
        }
        let (stamp, bytes) = self.read(path)?;
        Ok((stamp, xxhash_rust::xxh3::xxh3_128(&bytes)))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn borrowed_replay_lookup_keeps_canonical_key_and_alias_fallback() {
        let canonical = PathBuf::from("folder/source.dm");
        let missing = PathBuf::from("folder/absent.dm");
        let mut index = Index::default();
        index.files.insert(
            canonical.clone(),
            (
                Stamp {
                    size: 0,
                    modified_ns: 0,
                    file_id: None,
                },
                0,
            ),
        );
        index.negative.insert(missing.clone());
        assert!(matches!(index.lookup_path(&canonical), Cow::Borrowed(_)));
        assert_eq!(
            index.lookup_path(Path::new("folder/./source.dm")).as_ref(),
            canonical.as_path()
        );
        assert_eq!(
            index
                .lookup_path(Path::new("folder/sub/../source.dm"))
                .as_ref(),
            canonical.as_path()
        );
        assert_eq!(
            index
                .lookup_path(Path::new("folder/sub/../absent.dm"))
                .as_ref(),
            missing.as_path()
        );
        assert_eq!(
            index
                .lookup_path(Path::new("folder/sub/../unknown.dm"))
                .as_ref(),
            Path::new("folder/unknown.dm")
        );
        assert!(matches!(
            index.lookup_path(Path::new("folder/unknown.dm")),
            Cow::Owned(_)
        ));
        #[cfg(windows)]
        {
            let path = PathBuf::from(r"E:\root\source.dm");
            index.negative.insert(path.clone());
            assert!(matches!(index.lookup_path(&path), Cow::Borrowed(_)));
            assert_eq!(
                index
                    .lookup_path(Path::new(r"E:\root\sub\..\source.dm"))
                    .as_ref(),
                path.as_path()
            );
        }
    }

    #[test]
    fn replay_uses_captured_bytes_membership_and_absence_after_live_edits() {
        let root = std::env::temp_dir().join(format!(
            "dmbc-oracle-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&root).unwrap();
        let source = root.join("source.dm");
        let missing = root.join("absent.dm");
        fs::write(&source, b"old").unwrap();
        let journal = root.join("journal");
        let inputs = Inputs::record(&journal).unwrap();
        let (stamp, _) = inputs.read(&source).unwrap();
        assert_eq!(
            inputs.read(&missing).unwrap_err().kind(),
            io::ErrorKind::NotFound
        );
        let listing = inputs.list(&root).unwrap();
        inputs.finish().unwrap();
        drop(inputs);
        fs::write(&source, b"changed").unwrap();
        fs::write(&missing, b"new").unwrap();
        let replay = Inputs::replay(&journal).unwrap();
        let authenticated = replay.read_verified(&source).unwrap();
        assert_eq!(authenticated.stamp(), &stamp);
        assert_eq!(authenticated.bytes(), b"old");
        assert_eq!(authenticated.content(), xxhash_rust::xxh3::xxh3_128(b"old"));
        assert_eq!(replay.digest(&source).unwrap().1, authenticated.content());
        assert_eq!(replay.read(&source).unwrap(), (stamp, b"old".to_vec()));
        assert_eq!(replay.list(&root).unwrap(), listing);
        assert_eq!(
            replay.read(&missing).unwrap_err().kind(),
            io::ErrorKind::NotFound
        );
        assert_eq!(
            replay.read(&root.join("unknown.dm")).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
        if let Inputs::Replay(journal) = &replay {
            let (_, hash) = journal.index.lock().unwrap().files[&canonical_path(&source)].clone();
            fs::write(journal.payload(hash), b"bad").unwrap();
        }
        assert_eq!(
            replay.read(&source).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
        if let Inputs::Replay(journal) = &replay {
            let (_, hash) = journal.index.lock().unwrap().files[&canonical_path(&source)].clone();
            fs::write(journal.payload(hash), b"wrong length").unwrap();
        }
        assert_eq!(
            replay.read_verified(&source).unwrap_err().to_string(),
            "verification payload checksum mismatch"
        );
        assert_eq!(
            replay.digest(&source).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
        drop(replay);
        fs::remove_dir_all(root).unwrap();
    }
}

#[cfg(test)]
#[path = "frozen_inputs/access_view_tests.rs"]
mod access_view_tests;

/// Live inputs whose stamps are answered by the request's directory proofs
/// once session validation has captured them (one directory sweep instead of
/// one stat per file). Paths outside the captured directories, reads,
/// listings and every non-live mode go to the wrapped provider unchanged.
/// Publication still restats against a fresh capture, so an edit racing the
/// build is caught exactly as before.
pub struct ProofStampedInputs<'a> {
    inner: &'a Inputs,
    proofs: std::sync::OnceLock<std::sync::Arc<crate::filesystem_proofs::BulkFileSystemProofs>>,
}
impl<'a> ProofStampedInputs<'a> {
    pub fn new(inner: &'a Inputs) -> Self {
        Self {
            inner,
            proofs: std::sync::OnceLock::new(),
        }
    }
    /// Adopt the request's validation proofs (live mode only; first wins).
    pub fn adopt(&self, proofs: Option<std::sync::Arc<crate::filesystem_proofs::BulkFileSystemProofs>>) {
        if let (Inputs::Live, Some(proofs)) = (self.inner, proofs) {
            let _ = self.proofs.set(proofs);
        }
    }
}
impl SnapshotProvider for ProofStampedInputs<'_> {
    fn generated_outputs(&self) -> Option<&std::collections::BTreeSet<PathBuf>> {
        self.inner.generated_outputs()
    }
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        match self.proofs.get() {
            Some(proofs) => proofs.stamp(path),
            None => self.inner.stamp(path),
        }
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.inner.read(path)
    }
    fn read_verified(&self, path: &Path) -> io::Result<CapturedInputRead> {
        self.inner.read_verified(path)
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        self.inner.list(path)
    }
    fn digest(&self, path: &Path) -> io::Result<(Stamp, u128)> {
        self.inner.digest(path)
    }
}
