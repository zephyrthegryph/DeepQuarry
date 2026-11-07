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

/// Source failure is distinguished by the actual OS-open boundary; callback,
/// resource, cancellation and payload IO errors always remain typed Err.
pub enum OriginalOpenedRead{Suppressed,SourceOpenFailed(io::Error),Read(CapturedInputRead)}
/// Actual source-open classification shared by capture and warm reprobes.
/// Windows sharing/lock denial keeps its genuine Uncategorized kind and raw code.
pub(crate) fn original_source_open_failure(error:&io::Error)->bool{matches!(error.kind(),io::ErrorKind::NotFound|io::ErrorKind::NotADirectory|io::ErrorKind::PermissionDenied|io::ErrorKind::InvalidInput)||(cfg!(windows)&&matches!(error.raw_os_error(),Some(32|33)))}
/// Provider reads must return the stamp of the bytes read (restat around the read
/// or use a single open handle). An unstable read is an error, never a cache hit.
pub trait SnapshotProvider {
    /// Actual reader-open status only. Never reads payload, metadata stamp, or a
    /// parent folder; a source-open failure remains its exact typed observation.
    fn original_open_status(&self,_path:&Path)->io::Result<OriginalReadOpenStatus>{Err(io::Error::new(io::ErrorKind::NotConnected,"provider cannot reobserve actual Original reader open"))}

    /// Target-following metadata only, including directories; no payload IO.
    fn path_presence(&self,_path:&Path)->io::Result<bool>{Err(io::Error::new(io::ErrorKind::NotConnected,"provider cannot observe metadata-only path presence"))}
    fn path_presence_admitted(&self,path:&Path,_work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<bool>{self.path_presence(path)}

    /// Exact caller-owned generated paths; only folder-membership proofs filter
    /// these names. Explicit reads and negative path probes remain authoritative.
    fn generated_outputs(&self) -> Option<&BTreeSet<PathBuf>> {
        None
    }
    fn stamp(&self, path: &Path) -> io::Result<Stamp>;
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)>;
    fn list(&self, folder: &Path) -> io::Result<FolderListing>;
    fn read_policy_bounded(&self, _: &Path, _: usize) -> io::Result<Option<CapturedInputRead>> {
        Ok(None)
    }
    /// Unsupported providers cannot allocate first and claim admission later.
    fn read_policy_bounded_admitted(&self, _: &Path, _: usize, _: &mut dyn FnMut(usize) -> io::Result<()>) -> io::Result<Option<CapturedInputRead>> { Ok(None) }
    fn read_original_open_admitted(&self,_path:&Path,_limit:usize,_work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,_after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,_before_allocate:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<OriginalOpenedRead>{Err(io::Error::new(io::ErrorKind::NotConnected,"provider cannot issue actual Original opened reader"))}

    fn policy_directory(
        &self,
        _: &Path,
        _: bool,
        _: usize,
    ) -> io::Result<Option<PolicyDirectoryListing>> {
        Ok(None)
    }
    fn source_alias(
        &self,
        _: &Path,
        _: &SourceAliasChallenge,
    ) -> io::Result<Option<SourceAliasProof>> {
        Ok(None)
    }
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
    fn original_open_status(&self,path:&Path)->io::Result<OriginalReadOpenStatus>{(**self).original_open_status(path)}

    fn path_presence(&self,path:&Path)->io::Result<bool>{(**self).path_presence(path)}
    fn path_presence_admitted(&self,path:&Path,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<bool>{(**self).path_presence_admitted(path,work)}

    fn read_original_open_admitted(&self,path:&Path,limit:usize,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before_allocate:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<OriginalOpenedRead>{(**self).read_original_open_admitted(path,limit,work,after_open,before_allocate)}

    fn read_policy_bounded(
        &self,
        path: &Path,
        limit: usize,
    ) -> io::Result<Option<CapturedInputRead>> {
        (**self).read_policy_bounded(path, limit)
    }
    fn read_policy_bounded_admitted(&self, path: &Path, limit: usize, before_allocate: &mut dyn FnMut(usize) -> io::Result<()>) -> io::Result<Option<CapturedInputRead>> {
        (**self).read_policy_bounded_admitted(path, limit, before_allocate)
    }
    fn policy_directory(
        &self,
        path: &Path,
        follow: bool,
        limit: usize,
    ) -> io::Result<Option<PolicyDirectoryListing>> {
        (**self).policy_directory(path, follow, limit)
    }
    fn source_alias(
        &self,
        path: &Path,
        proof: &SourceAliasChallenge,
    ) -> io::Result<Option<SourceAliasProof>> {
        (**self).source_alias(path, proof)
    }
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

#[path = "input_source_alias.rs"]
mod source_alias;
pub(crate) use source_alias::{AcquiredSourceAlias, SourceAliasRecord};
pub use source_alias::{SourceAliasChallenge, SourceAliasProof};
#[path = "input_policy_directories.rs"]
mod policy_directories;
#[path = "input_policy_read.rs"]
mod policy_read;
pub(crate) use policy_read::FixedLibraryBaseline;
#[path = "input_map_edits.rs"]
mod map_edits;
pub(crate) use policy_directories::PolicyDirectoryStorage;
pub use policy_directories::{
    PolicyDirectoryEntries, PolicyDirectoryEntry, PolicyDirectoryListing,
    PolicyDirectoryObservation, PolicyEntryKind,
};
pub struct FileSystemInputs;
#[path = "input_generated_outputs.rs"]
mod generated;
#[path="input_generation.rs"]
mod generation;
pub(crate) use generation::{GenerationBootstrap,GenerationBootstrapFailure,GenerationBootstrapPreparation,GenerationDeclarePlanBootstrap,GenerationSourceReader,GenerationSourceFrame,GenerationQuestionBootstrap,OwnedGenerationFrame,RetiredGenerationInputs,DeclareOverlayProbe};
pub use generated::GeneratedOutputInputs;
#[path = "input_snapshot_open.rs"]
mod source_open;
impl SnapshotProvider for FileSystemInputs {
    fn original_open_status(&self,path:&Path)->io::Result<OriginalReadOpenStatus>{crate::daemon::control::checkpoint()?;match std::fs::File::open(path){Ok(handle)=>{drop(handle);Ok(OriginalReadOpenStatus::Readable)},Err(error)if original_source_open_failure(&error)=>OriginalReadOpenStatus::observed(&error),Err(error)=>Err(error)}}

    fn path_presence(&self,path:&Path)->io::Result<bool>{crate::daemon::control::checkpoint()?;match std::fs::metadata(path){Ok(_)=>Ok(true),Err(actual)if original_source_open_failure(&actual)=>Ok(false),Err(actual)=>Err(actual)}}

    fn read_original_open_admitted(&self,path:&Path,limit:usize,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before_allocate:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<OriginalOpenedRead>{work.checkpoint()?;policy_read::filesystem_original_open_read_admitted(path,limit,after_open,before_allocate)}

    fn read_policy_bounded(
        &self,
        path: &Path,
        limit: usize,
    ) -> io::Result<Option<CapturedInputRead>> {
        policy_read::filesystem_bounded_read(path, limit).map(Some)
    }
    fn read_policy_bounded_admitted(&self, path: &Path, limit: usize, before_allocate: &mut dyn FnMut(usize) -> io::Result<()>) -> io::Result<Option<CapturedInputRead>> {
        policy_read::filesystem_bounded_read_admitted(path, limit, before_allocate).map(Some)
    }
    fn policy_directory(
        &self,
        path: &Path,
        follow: bool,
        limit: usize,
    ) -> io::Result<Option<PolicyDirectoryListing>> {
        policy_directories::filesystem_policy_directory(path, follow, limit).map(Some)
    }
    fn source_alias(
        &self,
        path: &Path,
        proof: &SourceAliasChallenge,
    ) -> io::Result<Option<SourceAliasProof>> {
        source_alias::filesystem_source_alias(path, proof)
    }
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
                .map(|part| {
                    scope.spawn(move || {
                        part.iter()
                            .map(|path| self.digest(path))
                            .collect::<Vec<_>>()
                    })
                })
                .collect();
            for handle in handles {
                results.extend(
                    handle
                        .join()
                        .unwrap_or_else(|panic| std::panic::resume_unwind(panic)),
                );
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

#[path = "input_source_acquisition.rs"]
mod source_acquisition;
#[path = "input_source_original.rs"]
mod source_original;
pub(crate) use source_acquisition::{exact_open_receipt_charge, recorded_source_receipt_storage};
pub(crate) use source_acquisition::SemanticSourceEvidence;
pub(crate) use source_acquisition::{
    visit_raw_source_backing, recorded_source_original, recorded_source_receipt_original, RecordedSourceOriginal, normalize_recorded_policy_original,
};
#[path="input_policy_source.rs"]mod policy_source;
pub(crate) use policy_source::RecordedPolicySourceLender;
#[path="input_derived_subject.rs"]mod derived_subject;
pub(crate) use derived_subject::DerivedPreflight;
#[path="input_original_root_failure.rs"]mod original_root_failure;
pub(crate) use original_root_failure::OriginalRootOpenFailure;
#[path="input_analysis_subject.rs"]mod analysis_subject;
pub(crate) use analysis_subject::OriginalAnalysisSubject;
#[path="input_path_presence.rs"]mod path_presence;
pub(crate) use path_presence::{PathPresenceFacts,ImmutablePathFacts};
#[path="input_original_open_status.rs"]mod original_open_status;
pub use original_open_status::OriginalReadOpenStatus;
type OriginalOpenFacts=ImmutablePathFacts<OriginalReadOpenStatus>;
#[path="input_original_open_recording.rs"]mod original_open_recording;
#[path="input_original_batch_view.rs"]mod original_batch_view;
#[path="input_image_dir_report.rs"]mod image_dir_report;
pub(crate) use image_dir_report::{NamedImageDirCapture,NamedImageDirNoticeMode};
pub(crate) use original_open_recording::OriginalPayloadDigest;
type OriginalPayloadFacts=ImmutablePathFacts<OriginalPayloadDigest>;
// Keep the memo inside the original recorder lock. Only the immutable snapshot
// leaves this wrapper. Every mutable projection first discards the memo.
mod recording_snapshot {
    use super::InputSnapshot;
    use std::{num::NonZeroUsize, ops::{Deref, DerefMut}};

    pub(super) struct RecordingSnapshot {
        facts: InputSnapshot,
        next_exact_loan: Option<NonZeroUsize>,
        // Inline positive proofs for a few current exact receipts. A macro
        // commonly alternates between its invocation and definition file.
        // No source, path, snapshot owner or receipt is retained here.
        exact_loans: [Option<NonZeroUsize>; 4],
    }

    impl RecordingSnapshot {
        pub(super) fn new(facts: InputSnapshot) -> Self {
            Self { facts, next_exact_loan: NonZeroUsize::new(1), exact_loans: [None; 4] }
        }

        pub(super) fn into_facts(self) -> InputSnapshot { self.facts }

        pub(super) fn issue_exact_loan_serial(&mut self) -> Option<NonZeroUsize> {
            let serial = self.next_exact_loan?;
            // Exhaustion disables this optimization. It is never a source
            // error and an old serial is never issued again.
            self.next_exact_loan = serial.get().checked_add(1).and_then(NonZeroUsize::new);
            Some(serial)
        }

        pub(super) fn reuse_exact_loan(&mut self, serial: NonZeroUsize) -> bool {
            let serial = Some(serial);
            if self.exact_loans[0] == serial {
                return true;
            }
            if self.exact_loans[1] == serial {
                self.exact_loans.swap(0, 1);
            } else if self.exact_loans[2] == serial {
                self.exact_loans[..3].rotate_right(1);
            } else if self.exact_loans[3] == serial {
                self.exact_loans.rotate_right(1);
            } else {
                return false;
            }
            true
        }

        pub(super) fn remember_exact_loan(&mut self, serial: NonZeroUsize) {
            self.exact_loans.rotate_right(1);
            self.exact_loans[0] = Some(serial);
        }

        #[cfg(test)]
        pub(super) fn cached_exact_loan(&self) -> Option<NonZeroUsize> { self.exact_loans[0] }

        #[cfg(test)]
        pub(super) fn cached_exact_loans(&self) -> [Option<NonZeroUsize>; 4] { self.exact_loans }
    }

    impl Deref for RecordingSnapshot {
        type Target = InputSnapshot;
        fn deref(&self) -> &Self::Target { &self.facts }
    }

    impl DerefMut for RecordingSnapshot {
        fn deref_mut(&mut self) -> &mut Self::Target {
            self.exact_loans = [None; 4];
            &mut self.facts
        }
    }
}
use recording_snapshot::RecordingSnapshot;

pub struct RecordingInputs<P = FileSystemInputs> {
    original_path_bank: Mutex<Option<dm_preprocess::source_arena_credit::SourceArenaControlCredit>>,
    root_failure_capture:original_root_failure::RootFailureCapture,
    analysis_subject:Option<std::sync::Arc<OriginalAnalysisSubject>>,
    initial_environment:dm_preprocess::InitialEnvironment,
    source_issuer: std::sync::Arc<()>,
    source_acquisitions: Mutex<BTreeMap<PathBuf, dm_preprocess::AcquiredSource>>,
    exceptional_originals: Mutex<BTreeMap<PathBuf, source_original::ExceptionalOriginal>>,
    provider: P,
    /// Watcher position at creation: every fact recorded later was observed after it.
    created: Option<crate::fs_watch::WatchToken>,
    snapshot: Mutex<RecordingSnapshot>,
    exact_reuse: bool,
    prepared: Option<std::sync::Arc<PreparedInputArtifacts>>,
    prepared_keys: Mutex<Vec<std::sync::Arc<[u8]>>>,
    prior_original_text: std::sync::OnceLock<dm_tree::frontend::DecodedSourceCandidates>,
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub fn new(provider: P, scanned_ns: u128) -> Self {
        let mut snapshot = InputSnapshot::new(scanned_ns);
        snapshot.generated_outputs = provider.generated_outputs().cloned().unwrap_or_default();
        let created = provider.watch_token();
        // Merged retained parts narrow this (`InputSnapshot::merge`).
        snapshot.watch.replace(created);
        Self {
            original_path_bank: Default::default(),
            root_failure_capture:Default::default(),
            analysis_subject:None,
            initial_environment:dm_preprocess::InitialEnvironment::Native5161687,
            source_issuer: std::sync::Arc::new(()),
            source_acquisitions: Mutex::new(BTreeMap::new()),
            created,
            provider,
            snapshot: Mutex::new(RecordingSnapshot::new(snapshot)),
            exact_reuse: false,
            prepared: None,
            prepared_keys: Mutex::new(Vec::new()),
            prior_original_text: Default::default(),
            exceptional_originals: Mutex::new(BTreeMap::new()),
        }
    }
    /// Pipeline configuration only, never a source/current/completion receipt.
    pub fn with_initial_environment(mut self,environment:dm_preprocess::InitialEnvironment)->Self{self.initial_environment=environment;self}
    pub(crate) fn offer_prior_original_text(&self, source: dm_tree::frontend::DecodedSourceCandidates) {
        debug_assert_eq!(self.initial_environment, dm_preprocess::InitialEnvironment::Native5161687);
        let _ = self.prior_original_text.set(source);
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
    /// Fund the actual joined ledger before cloning its recording facts.
    pub(crate) fn snapshot_for_joined_report(
        &self, project: &Path, work: &dyn dm_preprocess::source_arena_credit::SourceArenaWork,
    ) -> io::Result<(InputSnapshot, dm_preprocess::source_arena_credit::SourceArenaCredit)> {
        let (snapshot, credit) = {
            let current = self.snapshot.lock().map_err(|_| invalid("input capture mutex poisoned"))?;
            let credit = work.reserve(current.joined_report_clone_bound(project)?)?;
            (current.clone(), credit)
        };
        self.mark(&snapshot);
        Ok((snapshot, credit))
    }

    pub fn into_snapshot(self) -> io::Result<InputSnapshot> {
        let snapshot = self
            .snapshot
            .into_inner()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .into_facts();
        let mark = match (
            self.created,
            self.provider.watch_token(),
            snapshot.watch.get(),
        ) {
            (Some(created), Some(now), Some(merged)) => crate::fs_watch::earlier(created, now)
                .and_then(|token| crate::fs_watch::earlier(token, merged)),
            _ => None,
        };
        snapshot.watch.replace(mark);
        Ok(snapshot)
    }
    /// A recorded fact was observed after this capture began, through a provider whose observations follow its own
    /// position (a provider that answers from earlier proofs reports theirs), so the earlier of the two proves them all.
    /// A merged retained part narrows it further (`InputSnapshot::merge`).
    fn mark(&self, snapshot: &InputSnapshot) {
        let mark = match (
            self.created,
            self.provider.watch_token(),
            snapshot.watch.get(),
        ) {
            (Some(created), Some(now), Some(merged)) => crate::fs_watch::earlier(created, now)
                .and_then(|token| crate::fs_watch::earlier(token, merged)),
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
    fn original_root_open_observer(&self)->Option<&dyn dm_preprocess::regions::OriginalRootOpenObserver>{self.root_failure_capture.is_armed().then_some(&self.root_failure_capture)}

    fn original_raw_source_open_admitted(&self,path:&Path,max_bytes:usize,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<dm_preprocess::OriginalRawReadOutcome>{self.capture_original_open_admitted(path,max_bytes,work,after_open,before_read,before_decode,None,acquired)}
 fn original_raw_source_open_owned_admitted(&self,path:&Path,max_bytes:usize,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,fund_text:&dm_preprocess::source_arena_credit::OriginalReadTextFunding<'_>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<dm_preprocess::OriginalRawReadOutcome>{self.capture_original_open_admitted(path,max_bytes,work,after_open,before_read,before_decode,Some(fund_text),acquired)}

    fn path_presence_admitted(&self,path:&Path,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<bool>{
        work.checkpoint()?;if !path.is_absolute(){return Err(invalid("metadata path must be caller absolute"))}
        let before=self.snapshot.lock().map_err(|_|invalid("input capture mutex poisoned"))?.path_presence.clone();
        // Fund every possible new capture allocation BEFORE metadata IO.
        let prepaid=work.reserve(before.probe_pregrant(path)?)?;let present=self.provider.path_presence_admitted(path,work)?;
        let next=before.recorded_using(path,present,prepaid,work)?;let mut snapshot=self.snapshot.lock().map_err(|_|invalid("input capture mutex poisoned"))?;
        if !snapshot.path_presence.same_owner(&before){return Err(io::Error::new(io::ErrorKind::Interrupted,"concurrent path presence capture changed before commit"))}
        snapshot.check_path_presence_compatible(path,present)?;snapshot.path_presence=next;Ok(present)
    }

    fn initial_environment(&self)->dm_preprocess::InitialEnvironment{self.initial_environment}
    fn original_raw_source_checked(&self,path:&Path,max_bytes:usize,before_decode:&mut dyn FnMut(usize,bool,bool)->io::Result<()>)->io::Result<Option<dm_preprocess::SourceAcquisitionLease>>{
        if self.initial_environment!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(invalid("Original raw source requires its actual Original pipeline context"))}
        crate::daemon::control::checkpoint()?;
        if let Some(source)=self.analysis_subject.as_ref().and_then(|subject|subject.source_for(path)){
            // SAME already-issued/prepaid subject owner; no new read/decode or
            // preparation occurs. Retention is still charged by the consumer.
            before_decode(0, matches!(source.encoding(),dm_preprocess::SourceEncoding::Utf8Bom|dm_preprocess::SourceEncoding::IncompatibleOriginal),false)?;
            return Ok(Some(source.lease().clone()));
        }
        self.read_raw_source(path,max_bytes,None,|capacity,exceptional,needs_decode|before_decode(capacity,exceptional,needs_decode))
    }
    fn original_raw_source_admitted(&self,path:&Path,max_bytes:usize,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<Option<dm_preprocess::SourceAcquisitionLease>>{
        if self.initial_environment!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(invalid("Original raw source requires its actual Original pipeline context"))}
        crate::daemon::control::checkpoint()?;
        if let Some(source)=self.analysis_subject.as_ref().and_then(|subject|subject.source_for(path)){
            before_decode(dm_preprocess::OriginalRawAllocationPlan::new(&[],0,0,0,matches!(source.encoding(),dm_preprocess::SourceEncoding::Utf8Bom|dm_preprocess::SourceEncoding::IncompatibleOriginal),false))?;
            acquired(source.lease())?;
            return Ok(Some(source.lease().clone()));
        }
        let Some(bytes)=self.read_policy_vec_admitted(path,max_bytes,before_read)?else{return Ok(None)};
        self.finish_raw_source_read_admitted(path,bytes,before_decode,acquired).map(Some)
    }
    fn original_source_bytes<'a>(&'a self,lease:&'a dm_preprocess::SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{
        self.original_bytes_checked(lease).map(Some)
    }




    fn acquired_source(
        &self,
        path: &Path,
    ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        if let Some(header)=self.analysis_subject.as_ref().and_then(|subject|subject.source_for(path)){return Ok(Some(header.clone()))}
        if let Some(source) = self.prepared_impl(path).map_err(|e| e.to_string())? {
            return Ok(self.current_source_acquisition(path, source.original()));
        }
        self.read_recorded(path)
            .and_then(|bytes| self.acquire_recorded_source(path, bytes))
            .map(Some)
            .map_err(|e| e.to_string())
    }
    fn source_acquisition(
        &self,
        path: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        if let Some(header)=self.analysis_subject.as_ref().and_then(|subject|subject.source_for(path)){return header.prepared().original().same_view(text).then(||header.clone())}
        self.current_source_acquisition(path, text)
    }
    fn prepared_source(
        &self,
        path: &Path,
    ) -> Option<std::sync::Arc<dm_preprocess::regions::prepared_source::PreparedSource>> {
        if let Some(header)=self.analysis_subject.as_ref().and_then(|subject|subject.source_for(path)){return Some(std::sync::Arc::clone(header.prepared()))}
        self.prepared_impl(path).ok().flatten()
    }
    fn read(&self, path: &Path) -> Result<String, String> {
        if let Some(header)=self.analysis_subject.as_ref().and_then(|subject|subject.source_for(path)){return Ok(header.prepared().original().as_str().to_owned())}
        self.read_recorded(path)
            .and_then(|bytes| self.decode_recorded_source(path, bytes))
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

#[derive(Clone, Debug, Eq, PartialEq, Deserialize)]
pub struct InputSnapshot {
    pub scanned_ns: u128,
    files: BTreeMap<PathBuf, FileInput>,
    folders: BTreeMap<PathBuf, FolderListing>,
    #[serde(default)]
    policy_directories: BTreeMap<PathBuf, PolicyDirectoryObservation>,
    // Resource bookkeeping only; never part of facts, wire identity or authority.
    #[serde(skip)]
    policy_directory_accounting: policy_directories::DirectoryChargeMemo,
    negative_files: BTreeSet<PathBuf>,
    generated_outputs: BTreeSet<PathBuf>,
    #[serde(default)]
    path_presence: PathPresenceFacts,
    #[serde(default)]
    opened_reads: OriginalOpenFacts,
    #[serde(default)]
    original_payloads: OriginalPayloadFacts,
    #[serde(skip)]
    structure_proof: StructureProof,
    #[serde(skip)]
    watch: WatchMark,
}

// Human-readable snapshots retain the established optional empty field. Binary
// codecs are positional: every serialized snapshot must include this map slot,
// even when it is empty, or negative/generated fields shift during decoding.
impl Serialize for InputSnapshot {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeStruct;
        let include_directories = !serializer.is_human_readable() || !self.policy_directories.is_empty();
        let include_paths = !serializer.is_human_readable() || !self.path_presence.is_empty();
        let include_open = !serializer.is_human_readable() || !self.opened_reads.is_empty();
        let include_payload = !serializer.is_human_readable() || !self.original_payloads.is_empty();
        let mut fields = serializer.serialize_struct("InputSnapshot", 5 + usize::from(include_directories) + usize::from(include_paths) + usize::from(include_open)+usize::from(include_payload))?;
        fields.serialize_field("scanned_ns", &self.scanned_ns)?;
        fields.serialize_field("files", &self.files)?;
        fields.serialize_field("folders", &self.folders)?;
        if include_directories {
            fields.serialize_field("policy_directories", &self.policy_directories)?;
        }
        fields.serialize_field("negative_files", &self.negative_files)?;
        fields.serialize_field("generated_outputs", &self.generated_outputs)?;
        if include_paths { fields.serialize_field("path_presence", &self.path_presence)?; }
        if include_open { fields.serialize_field("opened_reads", &self.opened_reads)?; }
        if include_payload { fields.serialize_field("original_payloads", &self.original_payloads)?; }
        fields.end()
    }
}

#[cfg(test)]
mod snapshot_codec_tests {
    use super::*;
    fn roundtrip(snapshot: &InputSnapshot) {
        let wire = dm_wire::encode(0x5350_0002, snapshot).unwrap();
        let restored: InputSnapshot = dm_wire::decode(0x5350_0002, &wire, dm_wire::MAX_BYTES).unwrap();
        assert_eq!(&restored, snapshot);
        assert_eq!(serde_json::from_slice::<InputSnapshot>(&serde_json::to_vec(snapshot).unwrap()).unwrap(), *snapshot);
    }
    #[test]
    fn snapshot_binary_empty_directory_slot_preserves_negative_and_generated_fields_and_legacy_json() {
        let mut snapshot = InputSnapshot::new(17);
        snapshot.record_negative(Path::new("snapshot-codec/absent.dm")).unwrap();
        snapshot.generated_outputs.insert(canonical_path(Path::new("snapshot-codec/generated.dm")));
        roundtrip(&snapshot);
        let json = serde_json::to_value(&snapshot).unwrap();
        assert!(json.get("policy_directories").is_none(), "legacy empty JSON shape is unchanged");
        let restored: InputSnapshot = serde_json::from_value(json).unwrap();
        assert_eq!(restored, snapshot);
    }
    #[test]
    fn snapshot_binary_and_json_preserve_actual_typed_directory_observations() {
        let root = crate::test_scratch::dir("snapshot-codec-real-directory");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("actual.dm"), b"/datum/actual\n").unwrap();
        let inputs = RecordingInputs::new(FileSystemInputs, 19);
        let listing = inputs.capture_policy_directory(&root, false).unwrap();
        assert!(matches!(listing, PolicyDirectoryListing::Present(ref entries) if entries.len() == 1 && entries[0].name == "actual.dm" && entries[0].kind == PolicyEntryKind::File));
        let snapshot = inputs.into_snapshot().unwrap();
        roundtrip(&snapshot);
        let json = serde_json::to_value(&snapshot).unwrap();
        assert_eq!(json["policy_directories"].as_object().unwrap().len(), 1);
        let wire = dm_wire::encode(0x5350_0002, &snapshot).unwrap();
        let restored: InputSnapshot = dm_wire::decode(0x5350_0002, &wire, dm_wire::MAX_BYTES).unwrap();
        assert!(restored.restat(&FileSystemInputs).unwrap().unchanged());
        std::fs::remove_file(root.join("actual.dm")).unwrap();
        assert!(!restored.restat(&FileSystemInputs).unwrap().unchanged());
    }
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
        (
            self.files.len().saturating_add(self.path_presence.len()).saturating_add(self.opened_reads.len()).saturating_add(self.original_payloads.len()),
            self.folders
                .len()
                .saturating_add(self.policy_directories.len()),
            self.negative_files.len(),
        )
    }
    /// Exact captured facts, independent of validation's refreshed scan time.
    /// Stamps and issued generated-output policy remain part of this proof.
    pub(crate) fn same_recorded_facts(&self, other: &Self) -> bool {
        self.files == other.files
            && self.path_presence == other.path_presence
            && self.opened_reads == other.opened_reads
            && self.original_payloads==other.original_payloads
            && self.folders == other.folders
            && self.policy_directories == other.policy_directories
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
                    !leaves
                        .iter()
                        .any(|leaf| *leaf == std::ffi::OsStr::new(name))
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
        self.files.keys().chain(self.negative_files.iter()).chain(self.path_presence.keys()).chain(self.opened_reads.keys()).chain(self.original_payloads.keys()).cloned()
    }
    pub fn proof_folders(&self) -> impl Iterator<Item = PathBuf> + '_ {
        self.folders.keys().cloned()
    }
    pub fn new(scanned_ns: u128) -> Self {
        Self {
            scanned_ns,
            files: BTreeMap::new(),
            folders: BTreeMap::new(),
            policy_directories: BTreeMap::new(),
            policy_directory_accounting: Default::default(),
            negative_files: BTreeSet::new(),
            generated_outputs: BTreeSet::new(),
            path_presence: Default::default(),
            opened_reads: Default::default(),
            original_payloads: Default::default(),
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
                    return Some(format!(
                        "{} / {} roster",
                        path.display(),
                        other_path.display()
                    ))
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
        if self.policy_directories != other.policy_directories {
            return Some("policy directory kind/follow-root observations".into());
        }
        if self.path_presence != other.path_presence { return Some("metadata path presence".into()); }
        if self.opened_reads != other.opened_reads { return Some("actual Original reader-open outcomes".into()); }
        if self.original_payloads!=other.original_payloads{return Some("exact Original raw payloads".into())}
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
        next.path_presence = self.path_presence.clone();
        next.opened_reads = self.opened_reads.clone();
        next.original_payloads = self.original_payloads.clone();
        next.watch.replace(self.watch.get());
        Ok(next)
    }
    /// Merge a freshly validated retained domain into this capture. Conflicting
    /// reads reject the build instead of silently selecting one observation.
    pub fn merge(&mut self, other: &Self) -> io::Result<()> {
        let _timer = dm_profile::detail_timer("snapshot.merge.check_structure");
        other.check_structure()?;
        for(path,present)in other.path_presence.iter(){self.check_path_presence_compatible(path,*present)?;}
        self.path_presence.merge_data(&other.path_presence)?;
        self.opened_reads.merge_data(&other.opened_reads)?;
        self.original_payloads.merge_data(&other.original_payloads)?;
        for (path, v) in &other.policy_directories {
            self.record_policy_directory(path, v.follow_root, v.listing.clone())?;
        }
        drop(_timer);
        let _timer = dm_profile::detail_timer("snapshot.merge.files");
        if !other.folders.is_empty() && other.generated_outputs != self.generated_outputs {
            return Err(invalid("retained generated-output proof policy differs"));
        }
        for (path, file) in &other.files {
            if self.negative_files.contains(path) || self.path_presence.get(path)==Some(false) {
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
        for path in &other.negative_files { if self.path_presence.get(path)==Some(true){return Err(invalid("present metadata path became negative during merge"))} }
        if self.negative_files.is_empty() {
            self.negative_files = other.negative_files.clone();
        } else {
            self.negative_files
                .extend(other.negative_files.iter().cloned());
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
        if self.path_presence.get(path)==Some(false){return Err(invalid("missing metadata path became a captured file"))}
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
    fn check_path_presence_compatible(&self,path:&Path,present:bool)->io::Result<()>{if present&&self.negative_files.contains(path)||!present&&self.files.contains_key(path){return Err(invalid("metadata path presence contradicts captured file fact"))}Ok(())}
    /// Explicit resource-host union for genuinely disjoint admitted captures.
    pub fn merge_path_presence_using(&mut self,other:&Self,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>{other.check_structure()?;for(path,present)in other.path_presence.iter(){self.check_path_presence_compatible(path,*present)?;}self.path_presence.merge_using(&other.path_presence,work)?;self.opened_reads.merge_using(&other.opened_reads,work)?;self.original_payloads.merge_using(&other.original_payloads,work)}
    pub(crate) fn path_presence_observations(&self)->impl Iterator<Item=(&PathBuf,&bool)>{self.path_presence.iter()}
    pub(crate) fn visit_original_open_storage(&self,mut visit:impl FnMut(usize,usize,usize)){self.path_presence.visit_storage(&mut visit);self.opened_reads.visit_storage(&mut visit);self.original_payloads.visit_storage(visit)}

    pub fn record_negative(&mut self, path: &Path) -> io::Result<()> {
        let path = canonical_path(path);
        if self.files.contains_key(&path) {
            return Err(invalid("present input became negative during capture"));
        }
        if self.path_presence.get(&path)==Some(true){return Err(invalid("present metadata path became negative"))}
        self.negative_files.insert(path);
        Ok(())
    }

    /// Check untrusted decoded snapshots once. A privately issued receipt
    /// avoids repeating the same path/listing traversal during input validation.
    pub fn check_structure(&self) -> io::Result<()> {
        for(path,_)in self.original_payloads.iter(){if !path.is_absolute()||self.opened_reads.get(path).is_none_or(|status|!status.is_readable()){return Err(invalid("exact Original payload lacks actual readable-open observation"))}}
        if self.opened_reads.keys().any(|path|!path.is_absolute()){return Err(invalid("Original reader-open observations must retain absolute actual lookup paths"))}
        if self.structure_proof.0.get().is_some() {
            return Ok(());
        }
        for(path,present)in self.path_presence.iter(){if !path.is_absolute(){return Err(invalid("path presence observation must retain an absolute lookup"))}self.check_path_presence_compatible(path,*present)?;}
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
        for (path, v) in &self.policy_directories {
            if canonical_path(path) != *path {
                return Err(invalid("noncanonical policy directory"));
            }
            v.listing.check()?;
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
        // Always re-follow targets: symlink targets may change outside the
        // watched parent directory. Presence never causes payload hashing.
        let mut open_rows=Vec::new();open_rows.try_reserve_exact(self.opened_reads.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;let mut same_opens=true;
        for(path,observed)in self.opened_reads.iter(){let actual=provider.original_open_status(path)?;if actual!=*observed{same_opens=false;report.changed.push(path.clone());if stop_on_change{return Ok((report,next))}}open_rows.push((path.as_path(),actual));}
        next.opened_reads=if same_opens{self.opened_reads.clone()}else{OriginalOpenFacts::from_observed_data(open_rows)?};
        let mut payload_rows=Vec::new();payload_rows.try_reserve_exact(self.original_payloads.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;let mut same_payloads=true;
        for(path,old)in self.original_payloads.iter(){if !next.opened_reads.get(path).is_some_and(|status|status.is_readable()){same_payloads=false;continue}let(stamp,content)=provider.digest(path)?;report.rehashed+=1;let actual=OriginalPayloadDigest{stamp,content};if actual.content!=old.content{same_payloads=false;report.changed.push(path.clone());if stop_on_change{return Ok((report,next))}}else if actual!=*old{same_payloads=false}payload_rows.push((path.as_path(),actual));}
        next.original_payloads=if same_payloads{self.original_payloads.clone()}else{OriginalPayloadFacts::from_observed_data(payload_rows)?};
        let mut presence_rows=Vec::new();presence_rows.try_reserve_exact(self.path_presence.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;let mut same_presence=true;
        for(path,present)in self.path_presence.iter(){let actual=provider.path_presence(path)?;presence_rows.push((path.as_path(),actual));if actual!=*present{same_presence=false;report.changed.push(path.clone());if stop_on_change{return Ok((report,next))}}}
        next.path_presence=if same_presence{self.path_presence.clone()}else{PathPresenceFacts::from_observed_data(presence_rows)?};
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
                digests.extend(
                    provider.digest_many(
                        &to_hash[1..]
                            .iter()
                            .map(|(path, _)| *path)
                            .collect::<Vec<_>>(),
                    ),
                );
            }
        } else {
            digests =
                provider.digest_many(&to_hash.iter().map(|(path, _)| *path).collect::<Vec<_>>());
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
        for (path, old) in &self.policy_directories {
            let listing = provider
                .policy_directory(path, old.follow_root, 64 * 1024 * 1024)?
                .ok_or_else(|| invalid("provider cannot revalidate typed policy directory"))?;
            next.record_policy_directory(path, old.follow_root, listing.clone())?;
            if listing != old.listing {
                identical = false;
                report.changed.push(path.clone());
                if stop_on_change {
                    return Ok((report, next));
                }
            }
        }
        let negatives: Vec<&PathBuf> = self
            .negative_files
            .iter()
            .filter(|path| !clean(path))
            .collect();
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

    /// Conservative metadata admission, including aliased directory payloads.
    /// Original immutable path trees already carry their physical owner credits.
    fn joined_report_clone_bound(&self, project: &Path) -> io::Result<usize> {
        let overflow = || io::Error::from(io::ErrorKind::OutOfMemory);
        let mut bytes = 4096usize.checked_add(project.as_os_str().len()).ok_or_else(overflow)?;
        let mut add = |width: usize| -> io::Result<()> {
            bytes = bytes.checked_add(width).ok_or_else(overflow)?;
            Ok(())
        };
        // Conservative fixed row envelope includes opaque standard B-tree nodes.
        let path_row = |path: &PathBuf| 2048usize.checked_add(path.capacity()).ok_or_else(overflow);
        for (path, file) in &self.files {
            add(path_row(path)?.checked_add(file.path.capacity()).ok_or_else(overflow)?)?;
        }
        for path in self.negative_files.iter().chain(&self.generated_outputs) {
            add(path_row(path)?)?;
        }
        for (path, listing) in &self.folders {
            add(path_row(path)?)?;
            if let FolderListing::Present(names) = listing {
                add(names.capacity().checked_mul(std::mem::size_of::<String>()).ok_or_else(overflow)?)?;
                for name in names { add(name.capacity())?; }
            }
        }
        for (path, observation) in &self.policy_directories {
            add(path_row(path)?)?;
            if let PolicyDirectoryListing::Present(entries) = &observation.listing {
                add(entries.capacity().checked_mul(std::mem::size_of::<PolicyDirectoryEntry>()).ok_or_else(overflow)?)?;
                for entry in entries.iter() { add(entry.name.capacity())?; }
            }
        }
        Ok(bytes)
    }

    /// Compare facts the two profiles actually observed in common. Path
    /// normalization here grants no source identity or compiler authority.
    pub(crate) fn require_shared_native_files(&self, native: &Self) -> io::Result<()> {
        let mismatch = |path: &Path| io::Error::new(
            io::ErrorKind::Interrupted,
            format!("compound shared input differs at {}; prepare both phases again", path.display()),
        );
        let positive = |path: &Path, content: u128| {
            let key = dm_preprocess::regions::canonical_path(path);
            if native.negative_files.contains(&key)
                || native.files.get(&key).is_some_and(|fact| fact.content != content)
            {
                return Err(mismatch(path));
            }
            Ok(())
        };
        for (path, fact) in &self.files {
            crate::daemon::control::checkpoint()?;
            positive(path, fact.content)?;
        }
        for (path, fact) in self.original_payloads.iter() {
            crate::daemon::control::checkpoint()?;
            positive(path, fact.content)?;
        }
        for path in &self.negative_files {
            crate::daemon::control::checkpoint()?;
            if native.files.contains_key(&dm_preprocess::regions::canonical_path(path)) {
                return Err(mismatch(path));
            }
        }
        for (path, present) in self.path_presence.iter() {
            crate::daemon::control::checkpoint()?;
            let key = dm_preprocess::regions::canonical_path(path);
            if (*present && native.negative_files.contains(&key))
                || (!*present && native.files.contains_key(&key))
            {
                return Err(mismatch(path));
            }
        }
        for (path, status) in self.opened_reads.iter() {
            crate::daemon::control::checkpoint()?;
            let key = dm_preprocess::regions::canonical_path(path);
            if (status.is_readable() && native.negative_files.contains(&key))
                || (status.is_missing() && native.files.contains_key(&key))
            {
                return Err(mismatch(path));
            }
        }
        Ok(())
    }

    /// Additional exact content check for the private compound operation.
    pub(crate) fn exact_positive_contents_match(&self, provider: &impl SnapshotProvider) -> io::Result<bool> {
        self.exact_positive_contents_match_after(provider, None)
    }

    /// Run one live exact observation per canonical positive path after both
    /// separate metadata/open-role admissions. Preserve Native-first order:
    /// the report can use an observation only if its entire expected fact is
    /// equal to the already checked Native fact. No bytes, path copies, digest
    /// cache or report-purpose permissions cross the boundary.
    pub(crate) fn exact_positive_contents_match_pair(&self, report: &Self, provider: &impl SnapshotProvider) -> io::Result<bool> {
        if !self.exact_positive_contents_match(provider)? {
            return Ok(false);
        }
        report.exact_positive_contents_match_after(provider, Some(self))
    }

    fn exact_positive_contents_match_after(&self, provider: &impl SnapshotProvider, checked: Option<&Self>) -> io::Result<bool> {
        for (path, expected) in &self.files {
            crate::daemon::control::checkpoint()?;
            if let Some(previous) = checked.and_then(|inputs| inputs.files.get(path)) {
                if previous != expected {
                    return Ok(false);
                }
                continue;
            }
            match provider.digest(path) {
                Ok((stamp, content)) if stamp == expected.stamp && content == expected.content => {}
                Ok(_) => return Ok(false),
                Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(false),
                Err(error) => return Err(error),
            }
        }
        Ok(true)
    }

    /// Publication freshness is best effort; this does not replace content
    /// validation for exact reuse. The caller owns the bounded rebuild policy.
    pub fn restat(&self, provider: &impl SnapshotProvider) -> io::Result<Validation> {
        let mut report = Validation::default();
        if !self.generated_policy_matches(provider) {
            report.changed.extend(self.folders.keys().cloned());
            return Ok(report);
        }
        for(path,present)in self.path_presence.iter(){if provider.path_presence(path)?!=*present{report.changed.push(path.clone());}}
        for(path,observed)in self.opened_reads.iter(){if provider.original_open_status(path)?!=*observed{report.changed.push(path.clone());}}
        for(path,old)in self.original_payloads.iter(){if !provider.original_open_status(path)?.is_readable(){continue}let(_,content)=provider.digest(path)?;report.rehashed+=1;if content!=old.content{report.changed.push(path.clone());}}
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
        for (path, old) in &self.policy_directories {
            let listing = provider
                .policy_directory(path, old.follow_root, 64 * 1024 * 1024)?
                .ok_or_else(|| invalid("typed directory publication proof unavailable"))?;
            listing.check()?;
            if listing != old.listing {
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

#[path="input_handlers_subject.rs"]mod handlers_subject;

pub(crate) use handlers_subject::{HandlerStructuralSubject,HandlerPreparedCapture,PreparedHandlersStructural};
