//! S0 input facts. Payloads belong to capture/lowering, never to this record.
//! Stamp reuse assumes metadata-changing edits; exact mode makes no such assumption.
use dm_preprocess::regions::canonical_path;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::io;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

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

#[path = "input_read.rs"]
mod owned_read;
pub use owned_read::CapturedInputRead;

/// Provider reads must return the stamp of the bytes read (restat around the read
/// or use a single open handle). An unstable read is an error, never a cache hit.
pub trait SnapshotProvider {
    /// Exact caller-owned generated paths; only folder-membership proofs filter
    /// these names. Explicit reads and negative path probes remain authoritative.
    fn generated_outputs(&self) -> Option<&BTreeSet<PathBuf>> {
        None
    }
    fn stamp(&self, path: &Path) -> io::Result<Stamp>;
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)>;
    fn list(&self, folder: &Path) -> io::Result<FolderListing>;
    fn read_verified(&self, path: &Path) -> io::Result<CapturedInputRead> {
        let (stamp, bytes) = self.read(path)?;
        Ok(CapturedInputRead::new(stamp, bytes))
    }
    fn digest(&self, path: &Path) -> io::Result<(Stamp, u128)> {
        let read = self.read_verified(path)?;
        Ok((read.stamp().clone(), read.content()))
    }
    /// Digest several files, results in input order. Serial by default; a stateless provider (the live file system) reads on
    /// several threads: a checkout whose files were swapped for another worktree's identical ones has every stamp changed, and
    /// hashing the resource archive's inputs one file at a time was 8 s of a cross-worktree patch.
    fn digest_many(&self, paths: &[&PathBuf]) -> Vec<io::Result<(Stamp, u128)>> {
        paths.iter().map(|path| self.digest(path)).collect()
    }
    /// The directory watcher's position at or before this provider's first observation (`fs_watch::token`). A provider
    /// that answers from an earlier capture, or from anything but the watched file system, returns None.
    fn watch_token(&self) -> Option<crate::fs_watch::WatchToken> {
        None
    }
}
impl<T: SnapshotProvider + ?Sized> SnapshotProvider for &T {
    fn generated_outputs(&self) -> Option<&BTreeSet<PathBuf>> {
        (**self).generated_outputs()
    }
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        (**self).stamp(path)
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        (**self).read(path)
    }
    fn read_verified(&self, path: &Path) -> io::Result<CapturedInputRead> {
        (**self).read_verified(path)
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        (**self).list(path)
    }
    fn digest(&self, path: &Path) -> io::Result<(Stamp, u128)> {
        (**self).digest(path)
    }
    fn digest_many(&self, paths: &[&PathBuf]) -> Vec<io::Result<(Stamp, u128)>> {
        (**self).digest_many(paths)
    }
    fn watch_token(&self) -> Option<crate::fs_watch::WatchToken> {
        (**self).watch_token()
    }
}

pub struct FileSystemInputs;
#[path = "input_generated_outputs.rs"]
mod generated;
pub use generated::GeneratedOutputInputs;
#[path = "input_snapshot_open.rs"]
mod source_open;
impl SnapshotProvider for FileSystemInputs {
    /// Live reads: every observation follows the call.
    fn watch_token(&self) -> Option<crate::fs_watch::WatchToken> {
        crate::fs_watch::token()
    }
    fn digest_many(&self, paths: &[&PathBuf]) -> Vec<io::Result<(Stamp, u128)>> {
        const SERIAL_BELOW: usize = 16;
        const THREADS: usize = 4;
        if paths.len() < SERIAL_BELOW {
            return paths.iter().map(|path| self.digest(path)).collect();
        }
        let chunk = paths.len().div_ceil(THREADS);
        let mut results = Vec::with_capacity(paths.len());
        std::thread::scope(|scope| {
            let handles: Vec<_> = paths
                .chunks(chunk)
                .map(|part| scope.spawn(move || part.iter().map(|path| self.digest(path)).collect::<Vec<_>>()))
                .collect();
            for handle in handles {
                results.extend(handle.join().unwrap_or_else(|panic| std::panic::resume_unwind(panic)));
            }
        });
        results
    }
    fn digest(&self, path: &Path) -> io::Result<(Stamp, u128)> {
        use std::io::Read;
        let mut file = std::fs::File::open(path)?;
        let before = stamp_handle(&file)?;
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        let mut buffer = [0u8; 65536];
        let mut size = 0u64;
        loop {
            let count = file.read(&mut buffer)?;
            if count == 0 {
                break;
            }
            size += count as u64;
            hash.update(&buffer[..count]);
        }
        if stamp_handle(&file)? != before || self.stamp(path)? != before || size != before.size {
            return Err(io::Error::new(
                io::ErrorKind::Interrupted,
                "input changed during digest",
            ));
        }
        Ok((before, hash.digest128()))
    }
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        #[cfg(not(windows))]
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
            std::fs::OpenOptions::new()
                .access_mode(0x80)
                .custom_flags(0x02000000)
                .open(path)?
        };
        #[cfg(not(windows))]
        let file = std::fs::File::open(path)?;
        stamp_handle(&file)
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        use std::io::Read;
        let _profile = dm_profile::stage("filesystem.read");
        let mut file = source_open::read_file(path)?;
        let before = stamp_handle(&file)?;
        let mut bytes = Vec::new();
        dm_profile::io_call(|| file.read_to_end(&mut bytes), |count| (*count as u64, 0))?;
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

#[path = "input_handle.rs"]
mod handle;
pub(crate) use handle::{isolated_output_stamp, stamp_handle};

/// One capture owner shared by lexical workers and resource discovery. Records
/// actual read proofs and optionally shares authenticated lexical preparation.
/// Drop the request capture after taking its snapshot.
#[path = "input_snapshot_nontext.rs"]
mod nontext;
#[path = "input_prepared.rs"]
pub mod prepared;
pub use prepared::{PreparedInputArtifacts, PreparedInputPayload};

pub struct RecordingInputs<P = FileSystemInputs> {
    provider: P,
    /// Watcher position at creation: every fact recorded later was observed after it.
    created: Option<crate::fs_watch::WatchToken>,
    snapshot: Mutex<InputSnapshot>,
    exact_reuse: bool,
    prepared: Option<std::sync::Arc<PreparedInputArtifacts>>,
    prepared_keys: Mutex<Vec<std::sync::Arc<[u8]>>>,
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub fn new(provider: P, scanned_ns: u128) -> Self {
        let mut snapshot = InputSnapshot::new(scanned_ns);
        snapshot.generated_outputs = provider.generated_outputs().cloned().unwrap_or_default();
        let created = provider.watch_token();
        // Merged retained parts narrow this (`InputSnapshot::merge`).
        snapshot.watch.replace(created);
        Self {
            created,
            provider,
            snapshot: Mutex::new(snapshot),
            exact_reuse: false,
            prepared: None,
            prepared_keys: Mutex::new(Vec::new()),
        }
    }
    pub fn with_exact_reuse(mut self, exact: bool) -> Self {
        self.exact_reuse = exact;
        self
    }
    pub(crate) fn shape(&self) -> io::Result<(usize, usize, usize)> {
        Ok(self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .shape())
    }
    pub fn snapshot(&self) -> io::Result<InputSnapshot> {
        let snapshot = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .clone();
        self.mark(&snapshot);
        Ok(snapshot)
    }
    pub fn into_snapshot(self) -> io::Result<InputSnapshot> {
        let snapshot = self
            .snapshot
            .into_inner()
            .map_err(|_| invalid("input capture mutex poisoned"))?;
        let mark = match (self.created, self.provider.watch_token(), snapshot.watch.get()) {
            (Some(created), Some(now), Some(merged)) => {
                crate::fs_watch::earlier(created, now).and_then(|token| crate::fs_watch::earlier(token, merged))
            }
            _ => None,
        };
        snapshot.watch.replace(mark);
        Ok(snapshot)
    }
    /// A recorded fact was observed after this capture began, through a provider whose observations follow its own
    /// position (a provider that answers from earlier proofs reports theirs), so the earlier of the two proves them all.
    /// A merged retained part narrows it further (`InputSnapshot::merge`).
    fn mark(&self, snapshot: &InputSnapshot) {
        let mark = match (self.created, self.provider.watch_token(), snapshot.watch.get()) {
            (Some(created), Some(now), Some(merged)) => {
                crate::fs_watch::earlier(created, now).and_then(|token| crate::fs_watch::earlier(token, merged))
            }
            _ => None,
        };
        snapshot.watch.replace(mark);
    }
    /// Capture a binary compiler input through the same exact read ledger.
    pub fn read_binary(&self, path: &Path) -> io::Result<Vec<u8>> {
        self.read_recorded(path)
    }
    fn read_recorded(&self, path: &Path) -> io::Result<Vec<u8>> {
        let (stamp, bytes, content) = self.provider.read_verified(path)?.into_parts();
        // The provider's immutable envelope already authenticates the exact bytes.
        // Only fact admission needs the shared ledger lock.
        let mut snapshot = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?;
        // Preserve the original lock/size/conflict error precedence.
        if stamp.size != bytes.len() as u64 {
            return Err(invalid("captured stamp size differs from compiled bytes"));
        }
        snapshot.record_verified_digest(path, stamp, content)?;
        Ok(bytes)
    }
    pub fn record_search_folder(&self, path: &Path) -> io::Result<()> {
        if self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .folders
            .contains_key(path)
        {
            return Ok(());
        }
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

#[cfg(test)]
#[path = "input_snapshot_recording_tests.rs"]
mod recording_tests;
/// Authentication precedes decoding; consume the authenticated allocation on
/// UTF-8 sources. Legacy mixed encodings retain the shared decoder's exact rules.
fn decode_owned_source(bytes: Vec<u8>) -> String {
    match String::from_utf8(bytes) {
        Ok(mut text) => {
            if text.starts_with('\u{feff}') {
                text.drain(..3);
            }
            text
        }
        Err(error) => dm_preprocess::decode_source_bytes(&error.into_bytes()),
    }
}
impl<P: SnapshotProvider> dm_preprocess::SourceProvider for RecordingInputs<P> {
    fn prepared_source(
        &self,
        path: &Path,
    ) -> Option<std::sync::Arc<dm_preprocess::regions::prepared_source::PreparedSource>> {
        self.prepared_impl(path).ok().flatten()
    }
    fn read(&self, path: &Path) -> Result<String, String> {
        self.read_recorded(path)
            .map(decode_owned_source)
            .map_err(|error| error.to_string())
    }
    fn retained_nontext(
        &self,
        path: &Path,
        previous: Option<&dm_preprocess::RetainedText>,
    ) -> Result<Option<dm_preprocess::RetainedText>, String> {
        self.retained_nontext_impl(path, previous)
    }
}
impl<P: SnapshotProvider> dm_resources::capture::CaptureProvider for RecordingInputs<P> {
    fn read_candidate(&self, path: &Path) -> io::Result<Option<dm_resources::SharedBytes>> {
        // Every attempted candidate records its parent listing, including
        // negative outcomes. Discovery still owns exact FILE_DIR precedence.
        let parent = path
            .parent()
            .ok_or_else(|| invalid("resource candidate has no parent"))?;
        self.record_search_folder(parent)?;
        match self.read_recorded(path) {
            Ok(bytes) => Ok(Some(dm_resources::SharedBytes::from(bytes))),
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

/// Private structural admission, copied only with the exact private maps.
/// It is absent from the wire and from semantic equality. Deserialization must
/// validate afresh; successful public mutation methods preserve the invariants.
#[derive(Clone, Debug, Default)]
struct StructureProof(OnceLock<()>);
impl PartialEq for StructureProof {
    fn eq(&self, _: &Self) -> bool {
        true
    }
}
impl Eq for StructureProof {}

/// The watcher position at which this snapshot's facts were last proven equal to the file system, entry for entry
/// (stamps included). Like `StructureProof` it is private, absent from the wire and from equality: a decoded snapshot
/// starts without one and is proven in full once.
#[derive(Debug, Default)]
struct WatchMark(Mutex<Option<crate::fs_watch::WatchToken>>);
impl WatchMark {
    fn get(&self) -> Option<crate::fs_watch::WatchToken> {
        *self.0.lock().unwrap_or_else(|e| e.into_inner())
    }
    fn set(&self, token: crate::fs_watch::WatchToken) {
        *self.0.lock().unwrap_or_else(|e| e.into_inner()) = Some(token);
    }
    fn replace(&self, token: Option<crate::fs_watch::WatchToken>) {
        *self.0.lock().unwrap_or_else(|e| e.into_inner()) = token;
    }
}
impl Clone for WatchMark {
    fn clone(&self) -> Self {
        Self(Mutex::new(self.get()))
    }
}
impl PartialEq for WatchMark {
    fn eq(&self, _: &Self) -> bool {
        true
    }
}
impl Eq for WatchMark {}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct InputSnapshot {
    pub scanned_ns: u128,
    files: BTreeMap<PathBuf, FileInput>,
    folders: BTreeMap<PathBuf, FolderListing>,
    negative_files: BTreeSet<PathBuf>,
    generated_outputs: BTreeSet<PathBuf>,
    #[serde(skip)]
    structure_proof: StructureProof,
    #[serde(skip)]
    watch: WatchMark,
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
    /// Entry counts of the three recorded sets. Records only grow (a repeated
    /// read that differs is rejected), so equal counts mean an equal capture.
    pub(crate) fn shape(&self) -> (usize, usize, usize) {
        (self.files.len(), self.folders.len(), self.negative_files.len())
    }
    /// Exact captured facts, independent of validation's refreshed scan time.
    /// Stamps and issued generated-output policy remain part of this proof.
    pub(crate) fn same_recorded_facts(&self, other: &Self) -> bool {
        self.files == other.files
            && self.folders == other.folders
            && self.negative_files == other.negative_files
            && self.generated_outputs == other.generated_outputs
    }
    /// Diagnostic-only borrowed owned collections; no proof is minted here.
    pub(crate) fn visit_recorded_storage(
        &self,
        visitor: impl FnOnce(
            &BTreeMap<PathBuf, FileInput>,
            &BTreeMap<PathBuf, FolderListing>,
            &BTreeSet<PathBuf>,
            &BTreeSet<PathBuf>,
        ),
    ) {
        visitor(
            &self.files,
            &self.folders,
            &self.negative_files,
            &self.generated_outputs,
        );
    }
    pub fn generated_outputs(&self) -> &BTreeSet<PathBuf> {
        &self.generated_outputs
    }
    /// The watcher position this snapshot's facts are current at (see `WatchMark`). A copy of the same facts that
    /// went through the wire (a session record decoded again) may take it back with [`Self::adopt_watch_mark`].
    pub(crate) fn watch_mark(&self) -> Option<crate::fs_watch::WatchToken> {
        self.watch.get()
    }
    /// Only for a snapshot whose recorded facts equal those of the one the mark was taken from.
    pub(crate) fn adopt_watch_mark(&self, mark: Option<crate::fs_watch::WatchToken>) {
        self.watch.replace(mark);
    }
    fn generated_policy_matches(&self, provider: &impl SnapshotProvider) -> bool {
        self.folders.is_empty()
            || match provider.generated_outputs() {
                Some(current) => current == &self.generated_outputs,
                None => self.generated_outputs.is_empty(),
            }
    }
    fn filter_generated(&self, folder: &Path, listing: FolderListing) -> FolderListing {
        match listing {
            FolderListing::Present(mut names) => {
                if self.generated_outputs.is_empty() {
                    return FolderListing::Present(names);
                }
                // A listing name is generated when `canonical_path(folder/name)` is a generated
                // output. Only outputs that sit directly in this folder can match, so their leaf
                // names are compared instead of canonicalizing every name of every listing (a
                // path allocation per name, repeated by every freshness sweep of a request).
                let base = canonical_path(folder);
                let leaves: Vec<&std::ffi::OsStr> = self
                    .generated_outputs
                    .iter()
                    .filter(|output| output.parent() == Some(base.as_path()))
                    .filter_map(|output| output.file_name())
                    .collect();
                names.retain(|name| {
                    if name.contains(':') {
                        // Drive-relative or stream spellings keep the exact path semantics.
                        return !self
                            .generated_outputs
                            .contains(&canonical_path(&folder.join(name)));
                    }
                    !leaves.iter().any(|leaf| *leaf == std::ffi::OsStr::new(name))
                });
                FolderListing::Present(names)
            }
            FolderListing::Missing => FolderListing::Missing,
        }
    }
    pub(crate) fn canonical_proof_paths(&self) -> impl Iterator<Item = &Path> {
        self.files
            .keys()
            .chain(self.negative_files.iter())
            .map(PathBuf::as_path)
    }
    pub(crate) fn canonical_proof_folders(&self) -> impl Iterator<Item = &Path> {
        self.folders.keys().map(PathBuf::as_path)
    }
    pub fn proof_paths(&self) -> impl Iterator<Item = PathBuf> + '_ {
        self.files.keys().chain(self.negative_files.iter()).cloned()
    }
    pub fn proof_folders(&self) -> impl Iterator<Item = PathBuf> + '_ {
        self.folders.keys().cloned()
    }
    pub fn new(scanned_ns: u128) -> Self {
        Self {
            scanned_ns,
            files: BTreeMap::new(),
            folders: BTreeMap::new(),
            negative_files: BTreeSet::new(),
            generated_outputs: BTreeSet::new(),
            // All later insertion methods validate their individual facts.
            structure_proof: StructureProof(OnceLock::from(())),
            watch: WatchMark::default(),
        }
    }

    /// First difference between two snapshots outside DM text sources
    /// (`.dm`, `.dme`), by content: non-text files, folder listings, negative
    /// lookups and generated outputs. Used to admit body-edit patches.
    pub(crate) fn non_text_difference(&self, other: &Self) -> Option<String> {
        self.non_text_difference_with(other, true)
    }
    /// As `non_text_difference`, but with `listings` false the folder listings and negative lookups
    /// are not compared. A patch passes false when the resource archive and search context are
    /// unchanged: a listing only matters through what it resolved, and an icon repack that rewrites
    /// unreferenced files changes listings without changing any resolution.
    pub(crate) fn non_text_difference_with(&self, other: &Self, listings: bool) -> Option<String> {
        let text = |path: &Path| {
            path.extension().is_some_and(|extension| {
                extension.eq_ignore_ascii_case("dm") || extension.eq_ignore_ascii_case("dme")
            })
        };
        let left = self.files.iter().filter(|(path, _)| !text(path));
        let mut right = other.files.iter().filter(|(path, _)| !text(path));
        for (path, file) in left {
            match right.next() {
                Some((other_path, other_file)) if other_path == path => {
                    if other_file.content != file.content {
                        return Some(format!("{} content", path.display()));
                    }
                }
                Some((other_path, _)) => {
                    return Some(format!("{} / {} roster", path.display(), other_path.display()))
                }
                None => return Some(format!("{} added", path.display())),
            }
        }
        if let Some((path, _)) = right.next() {
            return Some(format!("{} removed", path.display()));
        }
        if listings && self.folders != other.folders {
            return Some("resource folder listing".into());
        }
        if listings && self.negative_files != other.negative_files {
            return Some("negative file lookups".into());
        }
        if self.generated_outputs != other.generated_outputs {
            return Some("generated outputs".into());
        }
        None
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
            let fact = self
                .files
                .get(&path)
                .ok_or_else(|| invalid("selected input was not captured"))?;
            next.files.insert(path, fact.clone());
        }
        next.folders = self.folders.clone();
        next.generated_outputs = self.generated_outputs.clone();
        next.negative_files = self.negative_files.clone();
        next.watch.replace(self.watch.get());
        Ok(next)
    }
    /// Merge a freshly validated retained domain into this capture. Conflicting
    /// reads reject the build instead of silently selecting one observation.
    pub fn merge(&mut self, other: &Self) -> io::Result<()> {
        let _timer = dm_profile::detail_timer("snapshot.merge.check_structure");
        other.check_structure()?;
        drop(_timer);
        let _timer = dm_profile::detail_timer("snapshot.merge.files");
        if !other.folders.is_empty() && other.generated_outputs != self.generated_outputs {
            return Err(invalid("retained generated-output proof policy differs"));
        }
        for (path, file) in &other.files {
            if self.negative_files.contains(path) {
                return Err(invalid("retained input conflicts with absence"));
            }
            if let Some(current) = self.files.get(path) {
                if current != file {
                    return Err(invalid("retained input differs from current capture"));
                }
            } else {
                self.files.insert(path.clone(), file.clone());
            }
        }
        drop(_timer);
        let _timer = dm_profile::detail_timer("snapshot.merge.rest");
        // `other` passed `check_structure` above: its paths are canonical, its listings sorted
        // leaf names, and (the policies being equal) already free of generated outputs. Merging
        // therefore compares and inserts; re-filtering every listing name through
        // `canonical_path` cost about 0.5 s per request on DeepQuarry's resource folders.
        drop(_timer);
        let _timer = dm_profile::detail_timer("snapshot.merge.negatives");
        // Both sets are ordered: one linear walk finds a negative that is also a file, where a
        // lookup per negative (a component-wise path comparison each) cost 0.18 s.
        {
            let mut files = self.files.keys().peekable();
            for path in &other.negative_files {
                while let Some(file) = files.peek() {
                    match (*file).cmp(path) {
                        std::cmp::Ordering::Less => {
                            files.next();
                        }
                        std::cmp::Ordering::Equal => {
                            return Err(invalid("present input became negative during capture"));
                        }
                        std::cmp::Ordering::Greater => break,
                    }
                }
            }
        }
        if self.negative_files.is_empty() {
            self.negative_files = other.negative_files.clone();
        } else {
            self.negative_files.extend(other.negative_files.iter().cloned());
        }
        drop(_timer);
        let _timer = dm_profile::detail_timer("snapshot.merge.folders");
        let same_policy = other.generated_outputs == self.generated_outputs;
        for (path, listing) in &other.folders {
            if !same_policy {
                self.record_folder(path, listing.clone())?;
                continue;
            }
            match self.folders.get(path) {
                Some(previous) if previous != listing => {
                    return Err(invalid("resource folder changed during capture"));
                }
                Some(_) => {}
                None => {
                    self.folders.insert(path.clone(), listing.clone());
                }
            }
        }
        self.scanned_ns = self.scanned_ns.min(other.scanned_ns);
        // Both parts must be current at the merged position: the earlier of their marks, none if either lacks one.
        let merged = match (self.watch.get(), other.watch.get()) {
            (Some(own), Some(other)) => crate::fs_watch::earlier(own, other),
            _ => None,
        };
        self.watch.replace(merged);
        Ok(())
    }
    /// Paths of every recorded file input, in path order.
    pub fn file_paths(&self) -> impl Iterator<Item = &Path> {
        self.files.keys().map(PathBuf::as_path)
    }
    pub fn contains_file(&self, path: &Path) -> bool {
        self.files.contains_key(path) || self.files.contains_key(&canonical_path(path))
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
    pub fn record_verified_digest(
        &mut self,
        path: &Path,
        stamp: Stamp,
        content: u128,
    ) -> io::Result<()> {
        // Stored keys are admitted canonically. Repeated exact reads need only
        // compare their authenticated facts, without allocating another path.
        if let Some((stored, previous)) = self.files.get_key_value(path) {
            if self.negative_files.contains(stored) {
                return Err(invalid("negative input became present during capture"));
            }
            if previous.stamp != stamp || previous.content != content {
                return Err(invalid("input changed during repeated capture"));
            }
            return Ok(());
        }
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
        let listing = self.filter_generated(path, listing);
        if let Some((_, previous)) = self.folders.get_key_value(path) {
            if previous != &listing {
                return Err(invalid("resource folder changed during capture"));
            }
            return Ok(());
        }
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

    /// Check untrusted decoded snapshots once. A privately issued receipt
    /// avoids repeating the same path/listing traversal during input validation.
    pub fn check_structure(&self) -> io::Result<()> {
        if self.structure_proof.0.get().is_some() {
            return Ok(());
        }
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
        for path in &self.generated_outputs {
            if canonical_path(path) != *path {
                return Err(invalid("noncanonical generated-output policy"));
            }
        }
        let _ = self.structure_proof.0.set(());
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
        self.validate_impl(provider, exact, now_ns, false)
    }
    /// Session candidates need a complete proof only on success. A partial
    /// refreshed snapshot is never exposed when any captured input differs.
    pub(crate) fn validate_for_reuse(
        &self,
        provider: &impl SnapshotProvider,
        exact: bool,
        now_ns: u128,
    ) -> io::Result<Option<(Validation, Self)>> {
        let (report, next) = self.validate_impl(provider, exact, now_ns, true)?;
        Ok(report.unchanged().then_some((report, next)))
    }
    /// As [`Self::validate_for_reuse`], but a changed snapshot is returned with the report of what changed (the first change: the
    /// validation stops there) instead of `None`.
    pub(crate) fn validate_for_reuse_reporting(
        &self,
        provider: &impl SnapshotProvider,
        exact: bool,
        now_ns: u128,
    ) -> io::Result<(Validation, Self)> {
        self.validate_impl(provider, exact, now_ns, true)
    }
    /// The content digest recorded for a file input, if it is one.
    pub(crate) fn recorded_content(&self, path: &Path) -> Option<u128> {
        self.files.get(path).map(|file| file.content)
    }
    fn validate_impl(
        &self,
        provider: &impl SnapshotProvider,
        exact: bool,
        now_ns: u128,
        stop_on_change: bool,
    ) -> io::Result<(Validation, Self)> {
        self.check_structure()?;
        // Taken before the first observation through the provider (or the provider's own capture position).
        let token = provider.watch_token();
        let mut report = Validation::default();
        let mut next = Self::new(now_ns);
        next.generated_outputs = self.generated_outputs.clone();
        if !self.generated_policy_matches(provider) {
            report.changed.extend(self.folders.keys().cloned());
            return Ok((report, next));
        }
        // Watched inputs: an entry whose directory no watcher event named since this snapshot was last proven entry for
        // entry is still what was recorded, so it is carried without asking the provider. Exact mode assumes nothing
        // about metadata and proves everything; so does a snapshot never proven under the watcher (decoded, captured).
        let changes = match (exact, self.watch.get(), token) {
            (false, Some(since), Some(now)) => crate::fs_watch::changes_since(since, now),
            _ => None,
        };
        let mut clean_memo: Option<(PathBuf, bool)> = None;
        let mut clean = |path: &Path| -> bool {
            let (Some(changes), Some(dir)) = (changes.as_ref(), path.parent()) else {
                return false;
            };
            if let Some((last, answer)) = &clean_memo {
                if last.as_path() == dir {
                    return *answer;
                }
            }
            let answer = changes.clean(dir);
            clean_memo = Some((dir.to_owned(), answer));
            answer
        };
        // Whether `next` records exactly this snapshot's facts (every stamp equal), which proves this one at `token` too.
        let mut identical = true;
        let mut carried = 0usize;
        // Stamps first (cheap): a file whose stamp matches is kept as it was. The files that must be re-read (a stamp that
        // differs, which is every file when a checkout's files were swapped for another worktree's identical ones) are hashed
        // on several threads afterwards: serially that was 8 s of a cross-worktree patch.
        let mut to_hash: Vec<(&PathBuf, &FileInput)> = Vec::new();
        for (path, old) in &self.files {
            let racy = old.stamp.modified_ns.abs_diff(self.scanned_ns) <= 2_000_000_000;
            // A racy or identity-less entry is proven exactly as on the unwatched path.
            if !racy && old.stamp.file_id.is_some() && clean(path) {
                next.files.insert(path.clone(), old.clone());
                carried += 1;
                continue;
            }
            let stamp = match provider.stamp(path) {
                Ok(stamp) => stamp,
                Err(error) if error.kind() == io::ErrorKind::NotFound => {
                    report.changed.push(path.clone());
                    if stop_on_change {
                        return Ok((report, next));
                    }
                    continue;
                }
                Err(error) => return Err(error),
            };
            if exact || old.stamp.file_id.is_none() || stamp != old.stamp || racy {
                to_hash.push((path, old));
            } else {
                next.files.insert(path.clone(), old.clone());
            }
        }
        if self.files.len() > 1000 && std::env::var_os("DMB_TIMINGS_DETAIL").is_some() {
            crate::daemon_eprintln!(
                "detail inputs.validate counts: files={} to_hash={} folders={} negatives={} exact={exact} watched_changes={} carried={carried}",
                self.files.len(),
                to_hash.len(),
                self.folders.len(),
                self.negative_files.len(),
                changes.as_ref().map_or_else(|| "none".to_string(), |changes| changes.len().to_string()),
            );
        }
        // A validation that stops at the first change probes one file before fanning out: a changed tree usually shows in the
        // first file, and the stop must not cost a read of every other file.
        let mut digests = Vec::with_capacity(to_hash.len());
        if stop_on_change && !to_hash.is_empty() {
            let first = provider.digest(to_hash[0].0);
            let changed_first = match &first {
                Ok((_, content)) => *content != to_hash[0].1.content,
                Err(_) => true,
            };
            digests.push(first);
            if !changed_first && to_hash.len() > 1 {
                digests.extend(provider.digest_many(&to_hash[1..].iter().map(|(path, _)| *path).collect::<Vec<_>>()));
            }
        } else {
            digests = provider.digest_many(&to_hash.iter().map(|(path, _)| *path).collect::<Vec<_>>());
        }
        for ((path, old), digest) in to_hash.into_iter().zip(digests) {
            let (read_stamp, content) = digest?;
            report.rehashed += 1;
            identical &= read_stamp == old.stamp;
            next.record_verified_digest(path, read_stamp, content)?;
            if next.files[path].content != old.content {
                report.changed.push(path.clone());
                if stop_on_change {
                    return Ok((report, next));
                }
            }
        }
        identical &= report.changed.is_empty();
        for (path, old) in &self.folders {
            if changes.as_ref().is_some_and(|changes| changes.clean(path)) {
                next.folders.insert(path.clone(), old.clone());
                continue;
            }
            let listing = self.filter_generated(path, provider.list(path)?);
            next.record_folder(path, listing.clone())?;
            if &listing != old {
                identical = false;
                report.changed.push(path.clone());
                if stop_on_change {
                    return Ok((report, next));
                }
            }
        }
        let negatives: Vec<&PathBuf> = self.negative_files.iter().filter(|path| !clean(path)).collect();
        if stop_on_change {
            for path in negatives {
                match provider.stamp(path) {
                    Ok(_) => {
                        report.changed.push(path.clone());
                        return Ok((report, next));
                    }
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                    Err(error) => return Err(error),
                }
            }
        } else {
            let before = report.changed.len();
            Self::validate_negative_paths(negatives.into_iter(), provider, &mut report)?;
            identical &= report.changed.len() == before;
        }
        next.negative_files = self.negative_files.clone();
        if let Some(token) = token {
            // `next` is what the provider showed at `token`; when it equals this snapshot, so is this one.
            next.watch.set(token);
            if identical {
                self.watch.set(token);
            }
        }
        Ok((report, next))
    }

    /// Publication freshness is best effort; this does not replace content
    /// validation for exact reuse. The caller owns the bounded rebuild policy.
    pub fn restat(&self, provider: &impl SnapshotProvider) -> io::Result<Validation> {
        let mut report = Validation::default();
        if !self.generated_policy_matches(provider) {
            report.changed.extend(self.folders.keys().cloned());
            return Ok(report);
        }
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
            if self.filter_generated(path, provider.list(path)?) != *listing {
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
        Self::validate_negative_paths(self.negative_files.iter(), provider, report)
    }
    fn validate_negative_paths<'a>(
        paths: impl Iterator<Item = &'a PathBuf>,
        provider: &impl SnapshotProvider,
        report: &mut Validation,
    ) -> io::Result<()> {
        for path in paths {
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
#[path = "input_snapshot_tests.rs"]
mod tests;
#[cfg(all(test, windows))]
#[path = "input_snapshot_watch_tests.rs"]
mod watch_tests;
