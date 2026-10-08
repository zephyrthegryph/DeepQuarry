//! Opt-in verification journal. Replay never consults the live filesystem.
//! Payloads live on disk; recording does not retain the asset corpus in RAM.
use crate::input_snapshot::{FileSystemInputs, FolderListing, SnapshotProvider, Stamp};
use dm_preprocess::regions::canonical_path;
use serde::{Deserialize, Serialize};
use std::{
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
fn invalid(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message.into())
}
impl Inputs {
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
            let path = canonical_path(path);
            let index = journal
                .index
                .lock()
                .map_err(|_| invalid("verification mutex poisoned"))?;
            return match index.files.get(&path) {
                Some((stamp, _)) => Ok(stamp.clone()),
                None if index.negative.contains(&path) => Err(Journal::missing(&path)),
                None => Err(Journal::unknown(&path)),
            };
        }
        FileSystemInputs.stamp(path)
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        let path = canonical_path(path);
        match self {
            Self::Live => FileSystemInputs.read(&path),
            Self::Recording(journal) => {
                let result = FileSystemInputs.read(&path);
                let mut index = journal
                    .index
                    .lock()
                    .map_err(|_| invalid("verification mutex poisoned"))?;
                match result {
                    Ok((stamp, bytes)) => {
                        let hash = xxhash_rust::xxh3::xxh3_128(&bytes);
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
                            fs::write(payload, &bytes)?;
                        }
                        index.files.insert(path, (stamp.clone(), hash));
                        Ok((stamp, bytes))
                    }
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {
                        if index.files.contains_key(&path) {
                            return Err(invalid("verification input disappeared during capture"));
                        }
                        index.negative.insert(path);
                        Err(error)
                    }
                    Err(error) => Err(error),
                }
            }
            Self::Replay(journal) => {
                let (stamp, hash) = {
                    let index = journal
                        .index
                        .lock()
                        .map_err(|_| invalid("verification mutex poisoned"))?;
                    match index.files.get(&path) {
                        Some(value) => value.clone(),
                        None if index.negative.contains(&path) => {
                            return Err(Journal::missing(&path))
                        }
                        None => return Err(Journal::unknown(&path)),
                    }
                };
                let bytes = dm_profile::io_call(
                    || fs::read(journal.payload(hash)),
                    |bytes| (bytes.len() as u64, 0),
                )?;
                if bytes.len() as u64 != stamp.size || xxhash_rust::xxh3::xxh3_128(&bytes) != hash {
                    return Err(invalid("verification payload checksum mismatch"));
                }
                Ok((stamp, bytes))
            }
        }
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        let path = canonical_path(path);
        match self {
            Self::Live => FileSystemInputs.list(&path),
            Self::Recording(journal) => {
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
                index.folders.insert(path, listing.clone());
                Ok(listing)
            }
            Self::Replay(journal) => journal
                .index
                .lock()
                .map_err(|_| invalid("verification mutex poisoned"))?
                .folders
                .get(&path)
                .cloned()
                .ok_or_else(|| Journal::unknown(&path)),
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
        drop(replay);
        fs::remove_dir_all(root).unwrap();
    }
}
