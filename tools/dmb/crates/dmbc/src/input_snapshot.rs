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
}

pub struct FileSystemInputs;
#[path = "input_generated_outputs.rs"]
mod generated;
pub use generated::GeneratedOutputInputs;
#[path = "input_snapshot_open.rs"]
mod source_open;
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
mod prepared;
pub use prepared::{PreparedInputArtifacts, PreparedInputPayload};

pub struct RecordingInputs<P = FileSystemInputs> {
    provider: P,
    snapshot: Mutex<InputSnapshot>,
    exact_reuse: bool,
    prepared: Option<std::sync::Arc<PreparedInputArtifacts>>,
    prepared_keys: Mutex<Vec<std::sync::Arc<[u8]>>>,
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub fn new(provider: P, scanned_ns: u128) -> Self {
        let mut snapshot = InputSnapshot::new(scanned_ns);
        snapshot.generated_outputs = provider.generated_outputs().cloned().unwrap_or_default();
        Self {
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

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct InputSnapshot {
    pub scanned_ns: u128,
    files: BTreeMap<PathBuf, FileInput>,
    folders: BTreeMap<PathBuf, FolderListing>,
    negative_files: BTreeSet<PathBuf>,
    generated_outputs: BTreeSet<PathBuf>,
    #[serde(skip)]
    structure_proof: StructureProof,
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
                names.retain(|name| {
                    !self
                        .generated_outputs
                        .contains(&canonical_path(&folder.join(name)))
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
            let fact = self
                .files
                .get(&path)
                .ok_or_else(|| invalid("selected input was not captured"))?;
            next.files.insert(path, fact.clone());
        }
        next.folders = self.folders.clone();
        next.generated_outputs = self.generated_outputs.clone();
        next.negative_files = self.negative_files.clone();
        Ok(next)
    }
    /// Merge a freshly validated retained domain into this capture. Conflicting
    /// reads reject the build instead of silently selecting one observation.
    pub fn merge(&mut self, other: &Self) -> io::Result<()> {
        other.check_structure()?;
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
        for path in &other.negative_files {
            self.record_negative(path)?;
        }
        for (path, listing) in &other.folders {
            self.record_folder(path, listing.clone())?;
        }
        self.scanned_ns = self.scanned_ns.min(other.scanned_ns);
        Ok(())
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
    fn validate_impl(
        &self,
        provider: &impl SnapshotProvider,
        exact: bool,
        now_ns: u128,
        stop_on_change: bool,
    ) -> io::Result<(Validation, Self)> {
        self.check_structure()?;
        let mut report = Validation::default();
        let mut next = Self::new(now_ns);
        next.generated_outputs = self.generated_outputs.clone();
        if !self.generated_policy_matches(provider) {
            report.changed.extend(self.folders.keys().cloned());
            return Ok((report, next));
        }
        for (path, old) in &self.files {
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
            let racy = old.stamp.modified_ns.abs_diff(self.scanned_ns) <= 2_000_000_000;
            if exact || old.stamp.file_id.is_none() || stamp != old.stamp || racy {
                let (read_stamp, content) = provider.digest(path)?;
                report.rehashed += 1;
                next.record_verified_digest(path, read_stamp, content)?;
                if next.files[path].content != old.content {
                    report.changed.push(path.clone());
                    if stop_on_change {
                        return Ok((report, next));
                    }
                }
            } else {
                next.files.insert(path.clone(), old.clone());
            }
        }
        for (path, old) in &self.folders {
            let listing = self.filter_generated(path, provider.list(path)?);
            next.record_folder(path, listing.clone())?;
            if &listing != old {
                report.changed.push(path.clone());
                if stop_on_change {
                    return Ok((report, next));
                }
            }
        }
        if stop_on_change {
            for path in &self.negative_files {
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
            self.validate_negatives(provider, &mut report)?;
        }
        next.negative_files = self.negative_files.clone();
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
#[path = "input_snapshot_tests.rs"]
mod tests;
