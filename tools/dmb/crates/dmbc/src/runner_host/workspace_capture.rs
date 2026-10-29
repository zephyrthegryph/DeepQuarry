//! Production raw producer, distinct from bounded fixture CapturedPolicyInputs.
//! Native entries retain compare-only weak acquisition IDs, never all text views.
use crate::input_snapshot::{
    FileInput, InputSnapshot, RecordedSourceOriginal, RecordingInputs, SnapshotProvider,
};
use crate::runner_host::workspace_discovery::DiscoveryReceipt;
use dm_preprocess::{
    regions::{canonical_path, relative_filesystem_path},
    SourceAcquisitionIdentity,
};
use dm_resources::SharedBytes;
use dm_tree::frontend::{ColdFrontend, SourceExportMapping};
use std::{
    collections::BTreeMap,
    io,
    path::{Path, PathBuf},
    sync::{Arc, Weak},
};
const EXTRA_BUDGET: usize = 64 * 1024 * 1024;
#[path = "workspace_alias_index.rs"]
mod alias_index;
struct Native {
    occurrence: usize,
    identity: SourceAcquisitionIdentity,
    primary: FileInput,
}
enum Original {
    Native(Native),
    Owned(SharedBytes),
}
struct File {
    path: PathBuf,
    fact: FileInput,
    original: Original,
}
pub(crate) struct WorkspaceCapture {
    source: Weak<SourceExportMapping>,
    source_revision: u128,
    policy_revision: u128,
    issuance: u64,
    discovery: Arc<DiscoveryReceipt>,
    files: Box<[File]>,
    configuration: PathBuf,
    config: Option<SharedBytes>,
    facts: InputSnapshot,
}
impl WorkspaceCapture {
    pub(crate) fn census(self: &Arc<Self>, census: &mut crate::heap_census::HeapCensus) {
        let owner = "query_snapshot.workspace.capture";
        if !census.arc_object(owner, self) {
            return;
        }
        census.slice(owner, self.files.as_ref(), true);
        census.path(owner, &self.configuration);
        for file in &self.files {
            census.path(owner, &file.path);
            census.path(owner, &file.fact.path);
            match &file.original {
                Original::Native(native) => {
                    census.path(owner, &native.primary.path);
                    native.identity.visit_storage(|storage| {
                        if let dm_preprocess::source_acquisition::AcquisitionStorage::Object {
                            address,
                            bytes,
                        } = storage
                        {
                            census.exposed_buffer(owner, address, bytes, bytes);
                        }
                    });
                }
                Original::Owned(bytes) => {
                    if census.arc_object(owner, bytes.shared_owner()) {
                        census.vec_payload(owner, bytes.shared_owner().bytes());
                    }
                }
            }
        }
        if let Some(bytes) = &self.config {
            if census.arc_object(owner, bytes.shared_owner()) {
                census.vec_payload(owner, bytes.shared_owner().bytes());
            }
        }
        self.discovery.census(census);
        census.workspace_policy_facts(&self.facts);
    }

    pub(crate) fn issuance(&self) -> u64 {
        self.issuance
    }
    pub(crate) fn policy_revision(&self) -> u128 {
        self.policy_revision
    }
    pub(crate) fn recursive_roots(&self) -> &[PathBuf] {
        &self.discovery.contract().recursive_roots
    }
    pub(crate) fn matches_source(
        &self,
        mapping: &Arc<SourceExportMapping>,
        revision: u128,
    ) -> bool {
        Weak::ptr_eq(&self.source, &Arc::downgrade(mapping)) && self.source_revision == revision
    }
    pub(crate) fn matches_frontend(&self, frontend: &ColdFrontend) -> bool {
        frontend
            .source_export_mapping()
            .is_some_and(|mapping| Weak::ptr_eq(&self.source, &Arc::downgrade(mapping)))
            && self.source_revision == frontend.source_export_revision()
    }
    pub(crate) fn matches_request(
        &self,
        request: &crate::policy_request::WorkspacePolicyRequest,
    ) -> bool {
        self.root() == request.root
            && self.configuration == request.configuration
            && self.discovery.contract().recursive_roots == request.recursive_roots
    }
    pub(crate) fn is_recorded_in(&self, complete: &InputSnapshot) -> bool {
        let mut same = false;
        complete.visit_recorded_storage(|all_files, all_folders, all_negative, all_generated| {
            self.facts
                .visit_recorded_storage(|files, folders, negative, generated| {
                    same = files.iter().all(|(p, f)| all_files.get(p) == Some(f))
                        && folders.iter().all(|(p, f)| all_folders.get(p) == Some(f))
                        && negative.is_subset(all_negative)
                        && generated.is_subset(all_generated);
                });
        });
        same && self
            .facts
            .policy_directories()
            .iter()
            .all(|(p, f)| complete.policy_directories().get(p) == Some(f))
    }

    pub(crate) fn root(&self) -> &Path {
        &self.discovery.contract().root
    }
    pub(crate) fn require_scope(
        &self,
        scope: &crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,
    ) -> io::Result<()> {
        if !scope.matches_capture(
            self,
            &self.source,
            self.source_revision,
            self.policy_revision,
        ) {
            return Err(io::Error::other("workspace source scope is stale/foreign"));
        }
        Ok(())
    }
    pub(crate) fn page(
        &self,
        scope: &crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,
        start: usize,
        count: usize,
        budget: usize,
        scopes: &[Arc<dq_analyze::captured_raw_file::Scope>],
    ) -> io::Result<(Vec<crate::query_db::CurrentWorkspaceRawFile>, usize)> {
        use crate::query_db::{
            CurrentWorkspaceRawFile as CurrentFile, WorkspaceRawSourceProof as SourceProof,
        };
        self.require_scope(scope)?;
        if count == 0 || count > 128 {
            return Err(io::Error::other(
                "workspace page needs one to128 file slots",
            ));
        }
        let mut result = Vec::with_capacity(count.min(self.files.len().saturating_sub(start)));
        let mut owners = BTreeMap::new();
        let mut path_bytes = 0usize;
        let mut total = 0usize;
        let mut end = start;
        for (index, file) in self.files.iter().enumerate().skip(start).take(count) {
            crate::daemon::control::checkpoint()?;
            let rel = relative_filesystem_path(&file.path, self.root())
                .ok_or_else(|| io::Error::other("workspace page path escapes root"))?
                .to_string_lossy()
                .replace('\\', "/");
            let mut excluded = true;
            for scope in scopes {
                excluded &= scope.excludes_path(&rel).map_err(io::Error::other)?;
            }
            let proof = match &file.original {
                Original::Native(native) => SourceProof::Native(
                    scope.original_identity(native.occurrence, &native.identity)?,
                ),
                Original::Owned(bytes) => SourceProof::Owned(Arc::downgrade(bytes.shared_owner())),
            };
            let mut own = BTreeMap::new();
            let text = if excluded {
                None
            } else {
                let original = self.original(index, scope)?;
                let raw = match &original {
                    RecordedSourceOriginal::Utf8(text) => text.as_bytes(),
                    RecordedSourceOriginal::Bytes(bytes) => bytes.as_slice(),
                };
                let length = dq_analyze::captured_raw_file::analyze_raw_len(raw)
                    .map_err(io::Error::other)?;
                let peak = if matches!(&original,RecordedSourceOriginal::Utf8(text) if !text.as_bytes().contains(&b'\r'))
                {
                    if let RecordedSourceOriginal::Utf8(text) = &original {
                        dq_analyze::captured_raw_file::visit_source_storage(text, |key, bytes| {
                            own.entry(key)
                                .and_modify(|old: &mut usize| *old = (*old).max(bytes))
                                .or_insert(bytes);
                        });
                    }
                    own.iter()
                        .filter(|(key, _)| !owners.contains_key(*key))
                        .try_fold(0usize, |n, (_, b)| n.checked_add(*b))
                        .ok_or_else(|| io::Error::other("workspace source capacity overflow"))?
                } else {
                    length
                        .checked_mul(4)
                        .and_then(|n| n.checked_add(8192))
                        .ok_or_else(|| io::Error::other("workspace normalization peak overflow"))?
                };
                if total
                    .checked_add(file.path.capacity())
                    .and_then(|n| n.checked_add(peak))
                    .is_none_or(|n| n > budget)
                {
                    if result.is_empty() {
                        return Err(io::Error::other(
                            "whole source normalization exceeds remaining input budget",
                        ));
                    }
                    break;
                }
                let text = match &original {
                    RecordedSourceOriginal::Utf8(text) if !text.as_bytes().contains(&b'\r') => {
                        (*text).clone()
                    }
                    _ => String::from_utf8_lossy(raw)
                        .replace("\r\n", "\n")
                        .replace('\r', "\n")
                        .into(),
                };
                own.clear();
                dq_analyze::captured_raw_file::visit_source_storage(&text, |key, bytes| {
                    own.entry(key)
                        .and_modify(|old: &mut usize| *old = (*old).max(bytes))
                        .or_insert(bytes);
                });
                Some(text)
            };
            let charge = own
                .values()
                .try_fold(0usize, |n, b| n.checked_add(*b))
                .ok_or_else(|| io::Error::other("workspace source accounting overflow"))?;
            for (key, bytes) in own {
                owners
                    .entry(key)
                    .and_modify(|old: &mut usize| *old = (*old).max(bytes))
                    .or_insert(bytes);
            }
            path_bytes = path_bytes
                .checked_add(file.path.capacity())
                .ok_or_else(|| io::Error::other("workspace path accounting overflow"))?;
            total = owners
                .values()
                .try_fold(path_bytes, |n, b| n.checked_add(*b))
                .ok_or_else(|| io::Error::other("workspace page accounting overflow"))?;
            if total > budget {
                return Err(io::Error::other(
                    "workspace actual source capacity exceeds page input budget",
                ));
            }
            result.push(CurrentFile {
                path: file.path.clone(),
                text,
                proof,
                charge,
            });
            end = index + 1;
        }
        Ok((result, end))
    }
    pub(crate) fn facts(&self) -> &InputSnapshot {
        &self.facts
    }
    pub(crate) fn file_count(&self) -> usize {
        self.files.len()
    }
    pub(crate) fn path(&self, index: usize) -> io::Result<&Path> {
        self.files
            .get(index)
            .map(|file| file.path.as_path())
            .ok_or_else(|| io::Error::other("workspace file index unavailable"))
    }
    pub(crate) fn configuration(&self) -> (&Path, Option<&[u8]>) {
        (
            &self.configuration,
            self.config.as_ref().map(|bytes| bytes.as_slice()),
        )
    }
    pub(crate) fn original<'a>(
        &'a self,
        index: usize,
        scope: &'a crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,
    ) -> io::Result<RecordedSourceOriginal<'a>> {
        if !scope.matches_capture(
            self,
            &self.source,
            self.source_revision,
            self.policy_revision,
        ) {
            return Err(io::Error::other(
                "workspace native source scope is stale or foreign",
            ));
        }
        match &self
            .files
            .get(index)
            .ok_or_else(|| io::Error::other("workspace file index unavailable"))?
            .original
        {
            Original::Native(native) => scope.original(native.occurrence, &native.identity),
            Original::Owned(bytes) => Ok(RecordedSourceOriginal::Bytes(bytes)),
        }
    }
    // Exact borrowed owner accounting: metadata and extra owned originals count;
    // native bytes are NOT credited by hashes/equality but remain borrowed under
    // the active current SourceSnapshot guard and are not retained by this input.
    pub(crate) fn retained_charge(&self) -> io::Result<usize> {
        let mut count = std::mem::size_of_val(self)
            .checked_add(std::mem::size_of_val(self.files.as_ref()))
            .ok_or_else(|| io::Error::other("workspace metadata overflow"))?;
        let mut seen = std::collections::BTreeSet::new();
        let mut add = |bytes: usize| -> io::Result<()> {
            count = count
                .checked_add(bytes)
                .ok_or_else(|| io::Error::other("workspace capture overflow"))?;
            Ok(())
        };
        add(self.configuration.capacity())?;
        for file in &self.files {
            add(file.path.capacity())?;
            add(file.fact.path.capacity())?;
            match &file.original {
                Original::Native(native) => {
                    add(native.primary.path.capacity())?;
                    let mut metadata = 0;
                    native.identity.visit_storage(|v| {
                        if let dm_preprocess::source_acquisition::AcquisitionStorage::Object {
                            bytes,
                            ..
                        } = v
                        {
                            metadata = bytes.saturating_add(2 * std::mem::size_of::<usize>());
                        }
                    });
                    add(metadata)?;
                }
                Original::Owned(bytes) => {
                    let owner = bytes.shared_owner();
                    if seen.insert(Arc::as_ptr(owner) as usize) {
                        add(std::mem::size_of_val(owner.as_ref())
                            + 2 * std::mem::size_of::<usize>())?;
                        add(owner.bytes().capacity())?;
                    }
                }
            }
        }
        if let Some(bytes) = &self.config {
            let owner = bytes.shared_owner();
            if seen.insert(Arc::as_ptr(owner) as usize) {
                add(std::mem::size_of_val(owner.as_ref()) + 2 * std::mem::size_of::<usize>())?;
                add(owner.bytes().capacity())?;
            }
        }
        // Shared directory arrays are charged by actual retained ownership, with
        // PathBuf capacities and conservative map-node allowance exposed below.
        add(self.discovery.retained_charge_with(&mut seen)?)?;
        add(self.facts.policy_closure_charge_with(&mut seen)?)?;
        Ok(count)
    }
}
pub(crate) fn capture<P: SnapshotProvider>(
    frontend: &ColdFrontend,
    inputs: &RecordingInputs<P>,
    discovery: Arc<DiscoveryReceipt>,
    configuration: &Path,
) -> io::Result<Arc<WorkspaceCapture>> {
    discovery.validate_recording(inputs)?;
    if !configuration.is_absolute() {
        return Err(io::Error::other(
            "workspace configuration must be caller absolute",
        ));
    }
    let mapping = frontend
        .source_export_mapping()
        .ok_or_else(|| io::Error::other("workspace compiler mapping unproven"))?;
    let mut known = BTreeMap::new();
    for (index, occurrence) in frontend.plan.occurrences.iter().enumerate() {
        known.entry(occurrence.path.as_path()).or_insert(index);
    }
    let texts = frontend
        .files
        .iter()
        .filter(|file| file.captured)
        .map(|file| (file.path.as_path(), &file.text))
        .collect::<BTreeMap<_, _>>();
    // Reserve the COMPLETE metadata cohort before any extra original payload
    // read. A late final census must not hide an unbounded capture high-water.
    // This is conservative admission (not claimed allocator/RSS measurement).
    let mut used = discovery
        .retained_charge()?
        .checked_add(
            std::mem::size_of::<WorkspaceCapture>() + 2048 + configuration.as_os_str().len() * 4,
        )
        .ok_or_else(|| io::Error::other("workspace metadata overflow"))?;
    for path in discovery.files() {
        used = used
            .checked_add(2048 + path.capacity() * 8)
            .ok_or_else(|| io::Error::other("workspace metadata overflow"))?;
    }
    for path in known.keys() {
        // Include primary alias spelling capacity even if every source needs an
        // alias. This temporary conservative reserve is not retained storage.
        used = used
            .checked_add(path.as_os_str().len() * 2)
            .ok_or_else(|| io::Error::other("workspace primary metadata overflow"))?;
    }
    let alias_reserve = alias_index::AliasIndex::reserve_charge(known.keys().copied())?;
    used = used
        .checked_add(alias_reserve)
        .ok_or_else(|| io::Error::other("workspace alias metadata overflow"))?;
    if used > EXTRA_BUDGET {
        return Err(io::Error::other(
            "workspace metadata exceeds extra-owner bound before payload read",
        ));
    }
    let aliases = alias_index::AliasIndex::new(known.keys().copied(), alias_reserve)?;
    let mut files = Vec::with_capacity(discovery.files().len());
    for path in discovery.files() {
        crate::daemon::control::checkpoint()?;
        let mut primary = path.as_path();
        if !known.contains_key(primary) {
            if let Some(candidate) = aliases.candidate(path)? {
                let text = texts
                    .get(candidate)
                    .ok_or_else(|| io::Error::other("native source text absent"))?;
                let proof = inputs
                    .acquire_source_alias(path, candidate, text)?
                    .ok_or_else(|| {
                        io::Error::other("workspace source alias contract unsupported")
                    })?;
                if proof.primary_path() != candidate {
                    return Err(io::Error::other("foreign workspace source alias proof"));
                }
                primary = candidate;
            }
        }
        let original = if let Some(index) = known.get(primary) {
            let lease = mapping
                .source_acquisition(*index)
                .ok_or_else(|| io::Error::other("native original acquisition unavailable"))?;
            if !inputs.validate_source_lease(primary, lease) {
                return Err(io::Error::other(
                    "native original belongs to another recorder",
                ));
            }
            crate::input_snapshot::recorded_source_original(lease)?; // prove original-byte representation now
            Original::Native(Native {
                occurrence: *index,
                identity: lease.identity(),
                primary: inputs.recorded_file_fact(primary)?,
            })
        } else {
            let remaining = EXTRA_BUDGET
                .checked_sub(used)
                .ok_or_else(|| io::Error::other("workspace extra-owner capture budget exceeded"))?;
            let bytes = inputs
                .read_policy_candidate(path, remaining)?
                .ok_or_else(|| io::Error::other("discovered source disappeared before capture"))?;
            used = used
                .checked_add(bytes.capacity())
                .and_then(|n| n.checked_add(128))
                .ok_or_else(|| io::Error::other("workspace retained owner overflow"))?;
            Original::Owned(bytes)
        };
        files.push(File {
            path: path.clone(),
            fact: inputs.recorded_file_fact(path)?,
            original,
        });
    }
    let remaining = EXTRA_BUDGET
        .checked_sub(used)
        .ok_or_else(|| io::Error::other("workspace metadata leaves no config budget"))?;
    if discovery.files().iter().any(|path| path == configuration) {
        return Err(io::Error::other(
            "workspace configuration cannot also be a DM source",
        ));
    }
    let config = inputs.read_policy_candidate(configuration, remaining)?;
    let selected = files
        .iter()
        .flat_map(|file| {
            let mut paths = vec![file.path.clone()];
            if let Original::Native(native) = &file.original {
                paths.push(native.primary.path.clone());
            }
            paths
        })
        .chain(std::iter::once(canonical_path(configuration)))
        .collect();
    let facts = inputs.policy_workspace_closure(&selected, discovery.directory_paths())?;
    let policy_revision = crate::policy_request::workspace_revision(
        frontend.source_export_revision(),
        &facts,
        &discovery.contract().root,
        &discovery.contract().recursive_roots,
        &canonical_path(configuration),
    )?;
    static NEXT_ISSUANCE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    let issuance = NEXT_ISSUANCE
        .fetch_update(
            std::sync::atomic::Ordering::Relaxed,
            std::sync::atomic::Ordering::Relaxed,
            |value| value.checked_add(1),
        )
        .map_err(|_| io::Error::other("workspace capture issuance exhausted"))?;
    let result = Arc::new(WorkspaceCapture {
        source: Arc::downgrade(mapping),
        source_revision: frontend.source_export_revision(),
        policy_revision,
        issuance,
        discovery,
        files: files.into_boxed_slice(),
        configuration: canonical_path(configuration),
        config,
        facts,
    });
    if result.retained_charge()? > EXTRA_BUDGET {
        return Err(io::Error::other(
            "workspace capture exceeds existing64MiB extra-owner bound",
        ));
    }
    Ok(result)
}
