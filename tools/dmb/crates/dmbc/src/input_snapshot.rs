//! S0 input facts. Payloads belong to capture/lowering, never to this record.
//! Stamp reuse assumes metadata-changing edits; exact mode makes no such assumption.
use dm_preprocess::regions::canonical_path;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::io;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Stamp {
    pub size: u64,
    pub modified_ns: u128,
    /// A provider-issued stable volume/file identity. None disables stamp reuse.
    pub file_id: Option<u128>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct FileInput {
    pub path: PathBuf,
    pub stamp: Stamp,
    pub content: u128,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum FolderListing {
    Missing,
    /// Exact case-preserving names, sorted and duplicate-free. Includes all names,
    /// not only files whose extensions were requested by this build.
    Present(Vec<String>),
}

/// Provider reads must return the stamp of the bytes read (restat around the read
/// or use a single open handle). An unstable read is an error, never a cache hit.
pub trait SnapshotProvider {
    fn stamp(&self, path: &Path) -> io::Result<Stamp>;
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)>;
    fn list(&self, folder: &Path) -> io::Result<FolderListing>;
    fn digest(&self, path: &Path) -> io::Result<(Stamp, u128)> {
        let (stamp, bytes) = self.read(path)?;
        Ok((stamp, xxhash_rust::xxh3::xxh3_128(&bytes)))
    }
}

pub struct FileSystemInputs;
impl SnapshotProvider for FileSystemInputs {
    fn digest(&self, path: &Path) -> io::Result<(Stamp, u128)> {
        use std::io::Read;
        let mut file = std::fs::File::open(path)?;
        let before = stamp_handle(&file)?;
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        let mut buffer = [0u8; 65536];
        let mut size = 0u64;
        loop {
            let count = file.read(&mut buffer)?;
            if count == 0 { break; }
            size += count as u64; hash.update(&buffer[..count]);
        }
        if stamp_handle(&file)? != before || self.stamp(path)? != before || size != before.size {
            return Err(io::Error::new(io::ErrorKind::Interrupted, "input changed during digest"));
        }
        Ok((before, hash.digest128()))
    }
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        if !std::fs::metadata(path)?.is_file() {
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                "candidate is not a regular file",
            ));
        }
        // Identity validation needs attributes, not permission to read payloads.
        // Avoid opening every unchanged asset with GENERIC_READ on Windows.
        #[cfg(windows)]
        let file = {
            use std::os::windows::fs::OpenOptionsExt;
            std::fs::OpenOptions::new().access_mode(0x80).open(path)?
        };
        #[cfg(not(windows))]
        let file = std::fs::File::open(path)?;
        stamp_handle(&file)
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        use std::io::Read;
        if !std::fs::metadata(path)?.is_file() {
            return Err(io::Error::new(io::ErrorKind::NotFound, "candidate is not a regular file"));
        }
        let mut file = std::fs::File::open(path)?;
        let before = stamp_handle(&file)?;
        let mut bytes = Vec::new();
        file.read_to_end(&mut bytes)?;
        let after = stamp_handle(&file)?;
        if before != after || after != self.stamp(path)? || bytes.len() as u64 != after.size {
            return Err(io::Error::new(
                io::ErrorKind::Interrupted,
                "input changed while reading",
            ));
        }
        Ok((after, bytes))
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        let entries = match std::fs::read_dir(path) {
            Ok(entries) => entries,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                return Ok(FolderListing::Missing)
            }
            Err(error) => return Err(error),
        };
        let mut names = Vec::new();
        for entry in entries {
            let name = entry?
                .file_name()
                .into_string()
                .map_err(|_| invalid("resource folder name is not Unicode"))?;
            names.push(name);
        }
        names.sort();
        Ok(FolderListing::Present(names))
    }
}

fn stamp_handle(file: &std::fs::File) -> io::Result<Stamp> {
    let metadata = file.metadata()?;
    if !metadata.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "candidate is not a regular file",
        ));
    }
    let modified_ns = metadata
        .modified()?
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| invalid("input modification time predates epoch"))?
        .as_nanos();
    Ok(Stamp {
        size: metadata.len(),
        modified_ns,
        file_id: platform_file_id(file)?,
    })
}
#[cfg(unix)]
fn platform_file_id(file: &std::fs::File) -> io::Result<Option<u128>> {
    use std::os::unix::fs::MetadataExt;
    let metadata = file.metadata()?;
    Ok(Some(
        (u128::from(metadata.dev()) << 64) | u128::from(metadata.ino()),
    ))
}
#[cfg(windows)]
fn platform_file_id(file: &std::fs::File) -> io::Result<Option<u128>> {
    use std::os::windows::io::AsRawHandle;
    #[repr(C)]
    struct Information {
        attributes: u32,
        creation: [u32; 2],
        access: [u32; 2],
        write: [u32; 2],
        volume: u32,
        size_high: u32,
        size_low: u32,
        links: u32,
        index_high: u32,
        index_low: u32,
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn GetFileInformationByHandle(handle: *mut std::ffi::c_void, info: *mut Information)
            -> i32;
    }
    let mut information = std::mem::MaybeUninit::<Information>::uninit();
    // SAFETY: file owns a live handle; Win32 initializes the exact C-layout
    // structure on success. No initialized data is read on failure.
    if unsafe { GetFileInformationByHandle(file.as_raw_handle(), information.as_mut_ptr()) } == 0 {
        return Err(io::Error::last_os_error());
    }
    let information = unsafe { information.assume_init() };
    Ok(Some(
        (u128::from(information.volume) << 64)
            | (u128::from(information.index_high) << 32)
            | u128::from(information.index_low),
    ))
}
#[cfg(not(any(unix, windows)))]
fn platform_file_id(_: &std::fs::File) -> io::Result<Option<u128>> {
    Ok(None)
}

/// One capture owner shared by lexical workers and resource discovery. Records
/// only actual reads; it retains no payload cache. Drop it after taking snapshot.
pub struct RecordingInputs<P = FileSystemInputs> {
    provider: P,
    snapshot: Mutex<InputSnapshot>,
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub fn new(provider: P, scanned_ns: u128) -> Self {
        Self {
            provider,
            snapshot: Mutex::new(InputSnapshot::new(scanned_ns)),
        }
    }
    pub fn snapshot(&self) -> io::Result<InputSnapshot> {
        Ok(self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .clone())
    }
    pub fn into_snapshot(self) -> io::Result<InputSnapshot> {
        self.snapshot
            .into_inner()
            .map_err(|_| invalid("input capture mutex poisoned"))
    }
    fn read_recorded(&self, path: &Path) -> io::Result<Vec<u8>> {
        let (stamp, bytes) = self.provider.read(path)?;
        self.snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .record_file(path, stamp, &bytes)?;
        Ok(bytes)
    }
    pub fn record_search_folder(&self, path: &Path) -> io::Result<()> {
        let path = canonical_path(path);
        if self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .folders
            .contains_key(&path)
        {
            return Ok(());
        }
        let listing = self.provider.list(&path)?;
        self.snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .record_folder(&path, listing)
    }
}
impl<P: SnapshotProvider> dm_preprocess::SourceProvider for RecordingInputs<P> {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.read_recorded(path)
            .map(|bytes| dm_preprocess::decode_source_bytes(&bytes))
            .map_err(|error| error.to_string())
    }
}
impl<P: SnapshotProvider> dm_resources::capture::CaptureProvider for RecordingInputs<P> {
    fn read_candidate(&self, path: &Path) -> io::Result<Option<Arc<[u8]>>> {
        // Every attempted candidate records its parent listing, including
        // negative outcomes. Discovery still owns exact FILE_DIR precedence.
        let parent = path
            .parent()
            .ok_or_else(|| invalid("resource candidate has no parent"))?;
        self.record_search_folder(parent)?;
        match self.read_recorded(path) {
            Ok(bytes) => Ok(Some(Arc::from(bytes))),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                self.snapshot
                    .lock()
                    .map_err(|_| invalid("input capture mutex poisoned"))?
                    .record_negative(path)?;
                Ok(None)
            }
            Err(error) => Err(error),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct InputSnapshot {
    pub scanned_ns: u128,
    files: BTreeMap<PathBuf, FileInput>,
    folders: BTreeMap<PathBuf, FolderListing>,
    negative_files: BTreeSet<PathBuf>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Validation {
    pub changed: Vec<PathBuf>,
    pub rehashed: usize,
}

impl Validation {
    pub fn unchanged(&self) -> bool {
        self.changed.is_empty()
    }
}

impl InputSnapshot {
    pub fn new(scanned_ns: u128) -> Self {
        Self {
            scanned_ns,
            files: BTreeMap::new(),
            folders: BTreeMap::new(),
            negative_files: BTreeSet::new(),
        }
    }

    pub fn files(&self) -> impl Iterator<Item = &FileInput> {
        self.files.values()
    }
    /// Select a payload-free asset proof domain. Search membership and negative
    /// candidates are retained because they qualify source-path shadowing.
    pub fn select_files(&self, selected: &BTreeSet<PathBuf>) -> io::Result<Self> {
        let mut next = Self::new(self.scanned_ns);
        for path in selected {
            let path = canonical_path(path);
            let fact = self.files.get(&path).ok_or_else(|| invalid("selected input was not captured"))?;
            next.files.insert(path, fact.clone());
        }
        next.folders = self.folders.clone();
        next.negative_files = self.negative_files.clone();
        Ok(next)
    }
    /// Merge a freshly validated retained domain into this capture. Conflicting
    /// reads reject the build instead of silently selecting one observation.
    pub fn merge(&mut self, other: &Self) -> io::Result<()> {
        other.check_structure()?;
        for (path, file) in &other.files {
            if self.negative_files.contains(path) { return Err(invalid("retained input conflicts with absence")); }
            if let Some(current) = self.files.get(path) {
                if current != file { return Err(invalid("retained input differs from current capture")); }
            } else { self.files.insert(path.clone(), file.clone()); }
        }
        for path in &other.negative_files { self.record_negative(path)?; }
        for (path, listing) in &other.folders { self.record_folder(path, listing.clone())?; }
        self.scanned_ns = self.scanned_ns.min(other.scanned_ns);
        Ok(())
    }
    pub fn contains_file(&self, path: &Path) -> bool {
        self.files.contains_key(&canonical_path(path))
    }
    pub fn folders(&self) -> &BTreeMap<PathBuf, FolderListing> {
        &self.folders
    }

    /// Record precisely the bytes consumed, not a second read of the path.
    /// Repeated reads that differ are rejected; the caller must restart capture.
    pub fn record_file(&mut self, path: &Path, stamp: Stamp, bytes: &[u8]) -> io::Result<()> {
        if stamp.size != bytes.len() as u64 {
            return Err(invalid("captured stamp size differs from compiled bytes"));
        }
        self.record_verified_digest(path, stamp, xxhash_rust::xxh3::xxh3_128(bytes))
    }

    /// Streaming capture boundary. Caller must hash the consumed bytes
    /// and prove an unchanged file identity/stamp around that read.
    pub fn record_verified_digest(&mut self, path: &Path, stamp: Stamp, content: u128) -> io::Result<()> {
        let path = canonical_path(path);
        if self.negative_files.contains(&path) {
            return Err(invalid("negative input became present during capture"));
        }
        let fact = FileInput {
            path: path.clone(),
            stamp,
            content,
        };
        if let Some(previous) = self.files.get(&path) {
            if previous != &fact {
                return Err(invalid("input changed during repeated capture"));
            }
        } else {
            self.files.insert(path, fact);
        }
        Ok(())
    }

    /// Record every searched folder, including absent folders and unsuccessful
    /// lookups. IO/permission errors must propagate rather than become Missing.
    pub fn record_folder(&mut self, path: &Path, listing: FolderListing) -> io::Result<()> {
        check_listing(&listing)?;
        let path = canonical_path(path);
        if let Some(previous) = self.folders.get(&path) {
            if previous != &listing {
                return Err(invalid("resource folder changed during capture"));
            }
        } else {
            self.folders.insert(path, listing);
        }
        Ok(())
    }
    pub fn record_negative(&mut self, path: &Path) -> io::Result<()> {
        let path = canonical_path(path);
        if self.files.contains_key(&path) {
            return Err(invalid("present input became negative during capture"));
        }
        self.negative_files.insert(path);
        Ok(())
    }

    pub fn check_structure(&self) -> io::Result<()> {
        for (path, file) in &self.files {
            if path != &file.path || canonical_path(path) != *path {
                return Err(invalid("noncanonical input record"));
            }
        }
        for (path, listing) in &self.folders {
            if canonical_path(path) != *path {
                return Err(invalid("noncanonical folder record"));
            }
            check_listing(listing)?;
        }
        for path in &self.negative_files {
            if canonical_path(path) != *path || self.files.contains_key(path) {
                return Err(invalid("invalid negative input record"));
            }
        }
        Ok(())
    }

    /// Validate ALL captured files and search folders before any memo reuse.
    /// A changed stamp whose bytes agree is a safe hit; refreshed facts are
    /// returned in a new immutable snapshot, never patched into the old record.
    pub fn validate(
        &self,
        provider: &impl SnapshotProvider,
        exact: bool,
        now_ns: u128,
    ) -> io::Result<(Validation, Self)> {
        self.check_structure()?;
        let mut report = Validation::default();
        let mut next = Self::new(now_ns);
        for (path, old) in &self.files {
            let stamp = match provider.stamp(path) {
                Ok(stamp) => stamp,
                Err(error) if error.kind() == io::ErrorKind::NotFound => {
                    report.changed.push(path.clone());
                    continue;
                }
                Err(error) => return Err(error),
            };
            let racy = old.stamp.modified_ns.abs_diff(self.scanned_ns) <= 2_000_000_000;
            if exact || old.stamp.file_id.is_none() || stamp != old.stamp || racy {
                let (read_stamp, content) = provider.digest(path)?;
                report.rehashed += 1;
                next.record_verified_digest(path, read_stamp, content)?;
                if next.files[path].content != old.content {
                    report.changed.push(path.clone());
                }
            } else {
                next.files.insert(path.clone(), old.clone());
            }
        }
        for (path, old) in &self.folders {
            let listing = provider.list(path)?;
            next.record_folder(path, listing.clone())?;
            if &listing != old {
                report.changed.push(path.clone());
            }
        }
        self.validate_negatives(provider, &mut report)?;
        next.negative_files = self.negative_files.clone();
        Ok((report, next))
    }

    /// Publication freshness is best effort; this does not replace content
    /// validation for exact reuse. The caller owns the bounded rebuild policy.
    pub fn restat(&self, provider: &impl SnapshotProvider) -> io::Result<Validation> {
        let mut report = Validation::default();
        for (path, file) in &self.files {
            match provider.stamp(path) {
                Ok(stamp) if stamp == file.stamp => {}
                Ok(_) => report.changed.push(path.clone()),
                Err(error) if error.kind() == io::ErrorKind::NotFound => {
                    report.changed.push(path.clone())
                }
                Err(error) => return Err(error),
            }
        }
        for (path, listing) in &self.folders {
            if provider.list(path)? != *listing {
                report.changed.push(path.clone());
            }
        }
        self.validate_negatives(provider, &mut report)?;
        Ok(report)
    }
    fn validate_negatives(
        &self,
        provider: &impl SnapshotProvider,
        report: &mut Validation,
    ) -> io::Result<()> {
        for path in &self.negative_files {
            match provider.stamp(path) {
                Ok(_) => report.changed.push(path.clone()),
                Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                Err(error) => return Err(error),
            }
        }
        Ok(())
    }
}

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}
fn check_listing(listing: &FolderListing) -> io::Result<()> {
    if let FolderListing::Present(names) = listing {
        if names.windows(2).any(|pair| pair[0] >= pair[1])
            || names
                .iter()
                .any(|name| name.is_empty() || name.contains(['/', '\\']))
        {
            return Err(invalid(
                "resource listing must contain sorted unique leaf names",
            ));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    struct Host {
        bytes: Vec<u8>,
        stamp: Stamp,
        listing: FolderListing,
        reads: Cell<usize>,
        listings: Cell<usize>,
    }
    impl SnapshotProvider for Host {
        fn stamp(&self, _: &Path) -> io::Result<Stamp> {
            Ok(self.stamp.clone())
        }
        fn read(&self, _: &Path) -> io::Result<(Stamp, Vec<u8>)> {
            self.reads.set(self.reads.get() + 1);
            Ok((self.stamp.clone(), self.bytes.clone()))
        }
        fn list(&self, _: &Path) -> io::Result<FolderListing> {
            self.listings.set(self.listings.get() + 1);
            Ok(self.listing.clone())
        }
    }
    #[test]
    fn exact_and_racy_inputs_rehash_and_negative_folders_invalidate() {
        let mut host = Host {
            bytes: b"old".to_vec(),
            stamp: Stamp {
                size: 3,
                modified_ns: 1,
                file_id: Some(9),
            },
            listing: FolderListing::Missing,
            reads: Cell::new(0),
            listings: Cell::new(0),
        };
        let mut snapshot = InputSnapshot::new(10_000_000_000);
        snapshot
            .record_file(Path::new("project.dm"), host.stamp.clone(), &host.bytes)
            .unwrap();
        snapshot
            .record_folder(Path::new("assets"), FolderListing::Missing)
            .unwrap();
        assert!(snapshot
            .validate(&host, false, 20_000_000_000)
            .unwrap()
            .0
            .unchanged());
        assert_eq!(host.reads.get(), 0);
        host.bytes = b"new".to_vec();
        assert!(!snapshot
            .validate(&host, true, 20_000_000_000)
            .unwrap()
            .0
            .unchanged());
        snapshot.scanned_ns = 1;
        assert!(!snapshot
            .validate(&host, false, 20_000_000_000)
            .unwrap()
            .0
            .unchanged());
        host.bytes = b"old".to_vec();
        host.listing = FolderListing::Present(vec!["new.png".into()]);
        assert_eq!(
            snapshot
                .validate(&host, false, 20_000_000_000)
                .unwrap()
                .0
                .changed,
            vec![PathBuf::from("assets")]
        );
    }
    #[test]
    fn captured_bytes_and_repeated_reads_are_exact() {
        let mut snapshot = InputSnapshot::new(0);
        let stamp = Stamp {
            size: 3,
            modified_ns: 1,
            file_id: None,
        };
        snapshot
            .record_file(Path::new("a.dm"), stamp.clone(), b"one")
            .unwrap();
        assert!(snapshot
            .record_file(Path::new("a.dm"), stamp, b"two")
            .is_err());
        assert!(snapshot
            .record_folder(
                Path::new("assets"),
                FolderListing::Present(vec!["b".into(), "a".into()])
            )
            .is_err());
    }
    #[test]
    fn recording_lists_each_resource_parent_once_then_restats() {
        let host = Host {
            bytes: b"asset".to_vec(),
            stamp: Stamp {
                size: 5,
                modified_ns: 1,
                file_id: Some(1),
            },
            listing: FolderListing::Present(vec!["a.png".into(), "b.png".into()]),
            reads: Cell::new(0),
            listings: Cell::new(0),
        };
        let recording = RecordingInputs::new(host, 10_000_000_000);
        dm_resources::capture::CaptureProvider::read_candidate(
            &recording,
            Path::new("assets/a.png"),
        )
        .unwrap();
        dm_resources::capture::CaptureProvider::read_candidate(
            &recording,
            Path::new("assets/b.png"),
        )
        .unwrap();
        assert_eq!(recording.provider.listings.get(), 1);
        let snapshot = recording.snapshot().unwrap();
        assert!(snapshot.restat(&recording.provider).unwrap().unchanged());
        assert_eq!(recording.provider.listings.get(), 2);
    }
}
