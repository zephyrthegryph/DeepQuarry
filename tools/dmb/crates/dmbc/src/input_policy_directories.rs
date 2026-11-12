//! Typed, bounded directory facts in the SAME input ledger.
//! Explicit roots use WalkDir's default follow_root_links(true); child symlinks
//! remain classified as symlinks and are never traversed.
use super::*;
use std::sync::Arc;
const METADATA_BOUND: usize = 64 * 1024 * 1024;
#[path = "input_policy_directory_charge.rs"]
mod accounting;
pub(super) use accounting::DirectoryChargeMemo;
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum PolicyEntryKind {
    File,
    Directory,
    Symlink,
    Other,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PolicyDirectoryEntry {
    pub name: String,
    pub kind: PolicyEntryKind,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PolicyDirectoryEntries(Arc<Vec<PolicyDirectoryEntry>>);
impl std::ops::Deref for PolicyDirectoryEntries {
    type Target = Vec<PolicyDirectoryEntry>;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}
impl From<Vec<PolicyDirectoryEntry>> for PolicyDirectoryEntries {
    fn from(v: Vec<PolicyDirectoryEntry>) -> Self {
        Self(Arc::new(v))
    }
}
impl Serialize for PolicyDirectoryEntries {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        self.0.as_ref().serialize(s)
    }
}
impl<'de> Deserialize<'de> for PolicyDirectoryEntries {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        Vec::<PolicyDirectoryEntry>::deserialize(d).map(Into::into)
    }
}
pub(crate) enum PolicyDirectoryStorage<'a> {
    Owner {
        address: usize,
        bytes: usize,
    },
    Buffer {
        address: usize,
        logical: usize,
        capacity: usize,
    },
    Name(&'a String),
}
impl PolicyDirectoryEntries {
    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(PolicyDirectoryStorage<'_>)) {
        visit(PolicyDirectoryStorage::Owner {
            address: Arc::as_ptr(&self.0) as usize,
            bytes: std::mem::size_of::<Vec<PolicyDirectoryEntry>>(),
        });
        visit(PolicyDirectoryStorage::Buffer {
            address: self.as_ptr() as usize,
            logical: self.len() * std::mem::size_of::<PolicyDirectoryEntry>(),
            capacity: self.capacity() * std::mem::size_of::<PolicyDirectoryEntry>(),
        });
        for entry in self.iter() {
            visit(PolicyDirectoryStorage::Name(&entry.name));
        }
    }
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum PolicyDirectoryListing {
    Missing,
    NotDirectory,
    Present(PolicyDirectoryEntries),
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PolicyDirectoryObservation {
    pub follow_root: bool,
    pub listing: PolicyDirectoryListing,
}
impl PolicyDirectoryListing {
    pub(super) fn check(&self) -> io::Result<()> {
        if let Self::Present(entries) = self {
            let mut prior: Option<&str> = None;
            for entry in entries.iter() {
                let name = entry.name.as_str();
                let mut parts = Path::new(name).components();
                if prior.is_some_and(|old| old >= name)
                    || !matches!(
                        (parts.next(), parts.next()),
                        (Some(std::path::Component::Normal(_)), None)
                    )
                    || name.contains(['/', '\\'])
                {
                    return Err(invalid(
                        "typed policy names must be sorted unique normal leaf names",
                    ));
                }
                #[cfg(windows)]
                if name.ends_with(['.', ' ']) {
                    return Err(invalid(
                        "unsafe Windows directory spelling requires an explicit contract",
                    ));
                }
                prior = Some(name);
            }
        }
        Ok(())
    }
    fn storage(&self, seen: &mut BTreeSet<usize>) -> io::Result<usize> {
        let Self::Present(entries) = self else {
            return Ok(0);
        };
        if !seen.insert(Arc::as_ptr(&entries.0) as usize) {
            return Ok(0);
        }
        let mut n =
            std::mem::size_of::<Vec<PolicyDirectoryEntry>>() + 2 * std::mem::size_of::<usize>();
        n = n
            .checked_add(
                entries
                    .capacity()
                    .checked_mul(std::mem::size_of::<PolicyDirectoryEntry>())
                    .ok_or_else(|| invalid("typed directory capacity overflow"))?,
            )
            .ok_or_else(|| invalid("typed directory capacity overflow"))?;
        for entry in entries.iter() {
            n = n
                .checked_add(entry.name.capacity())
                .ok_or_else(|| invalid("typed directory name overflow"))?;
        }
        Ok(n)
    }
}
pub(super) fn filesystem_policy_directory(
    path: &Path,
    follow_root: bool,
    limit: usize,
) -> io::Result<PolicyDirectoryListing> {
    let meta = match if follow_root {
        std::fs::metadata(path)
    } else {
        std::fs::symlink_metadata(path)
    } {
        Ok(v) => v,
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            return Ok(PolicyDirectoryListing::Missing)
        }
        Err(e) => return Err(e),
    };
    if !meta.is_dir() || (!follow_root && meta.file_type().is_symlink()) {
        return Ok(PolicyDirectoryListing::NotDirectory);
    }
    let mut entries = Vec::new();
    let mut names = 0usize;
    for item in std::fs::read_dir(path)? {
        crate::daemon::control::checkpoint()?;
        let item = item?;
        let ty = item.file_type()?;
        let name = item
            .file_name()
            .into_string()
            .map_err(|_| invalid("typed directory name is not Unicode"))?;
        names = names
            .checked_add(name.capacity())
            .ok_or_else(|| invalid("typed directory name overflow"))?;
        // Check before growing the roster. This is a retained-capacity bound,
        // not allocator/RSS accounting; one OS entry name is observed at a time.
        let wanted = if entries.len() == entries.capacity() {
            entries
                .capacity()
                .checked_add(64)
                .ok_or_else(|| invalid("typed directory roster overflow"))?
        } else {
            entries.capacity()
        };
        let charge = wanted
            .checked_mul(std::mem::size_of::<PolicyDirectoryEntry>())
            .and_then(|n| n.checked_add(names))
            .and_then(|n| n.checked_add(128))
            .ok_or_else(|| invalid("typed directory metadata overflow"))?;
        if charge > limit {
            return Err(invalid(
                "typed directory exceeds remaining metadata admission",
            ));
        }
        if entries.len() == entries.capacity() {
            entries
                .try_reserve_exact(64)
                .map_err(|_| invalid("typed directory allocation refused"))?;
        }
        let kind = if ty.is_symlink() {
            PolicyEntryKind::Symlink
        } else if ty.is_dir() {
            PolicyEntryKind::Directory
        } else if ty.is_file() {
            PolicyEntryKind::File
        } else {
            PolicyEntryKind::Other
        };
        entries.push(PolicyDirectoryEntry { name, kind });
    }
    entries.sort_by(|a, b| a.name.cmp(&b.name));
    let result = PolicyDirectoryListing::Present(entries.into());
    result.check()?;
    if result.storage(&mut BTreeSet::new())? > limit {
        return Err(invalid("actual typed directory capacity exceeds admission"));
    }
    Ok(result)
}
impl InputSnapshot {
    pub(crate) fn policy_directories(&self) -> &BTreeMap<PathBuf, PolicyDirectoryObservation> {
        &self.policy_directories
    }
    pub(super) fn record_policy_directory(
        &mut self,
        path: &Path,
        follow_root: bool,
        listing: PolicyDirectoryListing,
    ) -> io::Result<()> {
        listing.check()?;
        let path = canonical_path(path);
        let next = PolicyDirectoryObservation {
            follow_root,
            listing,
        };
        if let Some(old) = self.policy_directories.get(&path) {
            if old != &next {
                return Err(invalid(
                    "typed policy directory/mode changed during capture",
                ));
            }
            self.policy_directory_charge()?; // retain any previous capacity-denial latch
            return Ok(());
        }
        // One incremental resource ledger, not a new semantic cache. A typed
        // fact is immutable once inserted, and this is its sole mutation path.
        let mut account = self
            .policy_directory_accounting
            .lock(&self.policy_directories)?;
        account.admit(&path, &next.listing)?;
        self.policy_directories.insert(path, next);
        Ok(())
    }
    pub(crate) fn policy_directory_charge(&self) -> io::Result<usize> {
        Ok(self
            .policy_directory_accounting
            .lock(&self.policy_directories)?
            .total())
    }
    pub(crate) fn visit_policy_directory_accounting(&self, visit: impl FnOnce(usize, usize)) {
        self.policy_directory_accounting.visit(visit);
    }
    pub(crate) fn policy_directory_accounting_retained_charge(&self) -> usize {
        self.policy_directory_accounting.retained_index_charge()
    }
    pub(crate) fn policy_closure_charge(&self) -> io::Result<usize> {
        self.policy_closure_charge_with(&mut BTreeSet::new())
    }
    pub(crate) fn policy_closure_charge_with(
        &self,
        seen: &mut BTreeSet<usize>,
    ) -> io::Result<usize> {
        let mut total = std::mem::size_of_val(self)
            .saturating_add(self.policy_directory_accounting.retained_index_charge());
        let mut add = |n: usize| -> io::Result<()> {
            total = total
                .checked_add(n)
                .ok_or_else(|| invalid("policy metadata overflow"))?;
            Ok(())
        };
        for (path, file) in &self.files {
            add(128 + std::mem::size_of_val(file) + path.capacity() + file.path.capacity())?;
        }
        for path in &self.negative_files {
            add(96 + path.capacity())?;
        }
        for (path, observation) in &self.policy_directories {
            add(128 + path.capacity())?;
            add(observation.listing.storage(seen)?)?;
        }
        Ok(total)
    }
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub(super) fn policy_metadata_owner(
        &self, budget: Option<&dq_analyze::captured_generator_budget::Budget>,
    ) -> io::Result<Arc<()>> {
        self.snapshot.lock().map_err(|_| invalid("input mutex poisoned during metadata funding"))?
            .policy_directory_accounting.metadata_owner(budget)
    }
    #[cfg(test)]
    pub(crate) fn policy_metadata_owner_address(&self) -> io::Result<usize> {
        Ok(Arc::as_ptr(&self.policy_metadata_owner(None)?) as usize)
    }
    pub(crate) fn policy_discovery_issuer(&self) -> Arc<()> {
        Arc::clone(&self.source_issuer)
    }
    pub(crate) fn has_policy_file_and_parent(&self, path: &Path) -> io::Result<bool> {
        let current = self.snapshot.lock().map_err(|_| invalid("input mutex poisoned"))?;
        Ok(path.parent().is_some_and(|parent| current.folders.contains_key(parent))
            && current.files.contains_key(path))
    }
    #[cfg(test)]
    pub(crate) fn poison_late_workspace_census_for_test(&self) {
        let failed = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _guard = self.snapshot.lock().unwrap();
            panic!("intentional recorder census poison");
        }));
        assert!(failed.is_err());
    }
    pub(crate) fn late_workspace_recorder_charge(&self) -> io::Result<usize> {
        let current = self.snapshot.lock().map_err(|_| invalid("input mutex poisoned"))?;
        let mut bytes = current.policy_closure_charge()?;
        for (path, listing) in &current.folders {
            let storage = match listing {
                FolderListing::Missing => 0,
                FolderListing::Present(names) => names.iter().try_fold(
                    names.capacity().checked_mul(std::mem::size_of::<String>())
                        .ok_or(io::ErrorKind::OutOfMemory)?,
                    |sum, name| sum.checked_add(name.capacity()).ok_or(io::ErrorKind::OutOfMemory),
                )?,
            };
            bytes = bytes.checked_add(128).and_then(|n| n.checked_add(path.capacity()))
                .and_then(|n| n.checked_add(storage)).ok_or(io::ErrorKind::OutOfMemory)?;
        }
        Ok(bytes)
    }
    pub(crate) fn late_workspace_recorder_owner(&self) -> io::Result<Arc<()>> {
        self.policy_metadata_owner(None)
    }
    pub(crate) fn policy_discovery_metadata_charge(&self) -> io::Result<usize> {
        self.snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?
            .policy_directory_charge()
    }
    pub(crate) fn capture_policy_directory(
        &self,
        path: &Path,
        follow_root: bool,
    ) -> io::Result<PolicyDirectoryListing> {
        self.capture_policy_directory_bounded(path, follow_root, 0)
    }
    pub(crate) fn capture_policy_directory_bounded(
        &self,
        path: &Path,
        follow_root: bool,
        other_metadata: usize,
    ) -> io::Result<PolicyDirectoryListing> {
        self.capture_policy_directory_with_limit(path,follow_root,other_metadata,None)
    }
    fn capture_policy_directory_with_limit(&self,path:&Path,follow_root:bool,other_metadata:usize,allocation_limit:Option<usize>)->io::Result<PolicyDirectoryListing>{
        let path = canonical_path(path);
        let current = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?;
        let used = current
            .policy_directory_charge()?
            .checked_add(other_metadata)
            .ok_or_else(|| invalid("discovery metadata overflow"))?;
        if used > METADATA_BOUND {
            return Err(invalid(
                "discovery metadata exceeds existing64MiB admission",
            ));
        }
        if let Some(old) = current.policy_directories.get(&path) {
            if old.follow_root != follow_root {
                return Err(invalid("directory follow-root contract changed"));
            }
            return Ok(old.listing.clone());
        }
        let remaining = METADATA_BOUND
            .checked_sub(used)
            .and_then(|n| n.checked_sub(128 + path.capacity()))
            .ok_or_else(|| invalid("typed directory metadata admission exhausted"))?;
        let remaining=allocation_limit.map_or(remaining,|window|window.min(remaining));
        drop(current);
        let listing = self
            .provider
            .policy_directory(&path, follow_root, remaining)?
            .ok_or_else(|| invalid("provider cannot prove typed directory discovery"))?;
        if listing.storage(&mut BTreeSet::new())? > remaining {
            return Err(invalid(
                "provider exceeded typed directory capacity admission",
            ));
        }
        self.snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?
            .record_policy_directory(&path, follow_root, listing.clone())?;
        Ok(listing)
    }
    pub(crate) fn recorded_file_fact(&self, path: &Path) -> io::Result<FileInput> {
        self.snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?
            .files
            .get(&canonical_path(path))
            .cloned()
            .ok_or_else(|| invalid("policy file not recorded"))
    }
    /// A bounded policy-file read records only the exact file stamp/digest
    /// or an observed negative. The requester binds the path and issuer.
    pub(crate) fn recorded_policy_file_observation(&self, path: &Path) -> io::Result<Option<(Stamp, u128)>> {
        let path = canonical_path(path);
        let current = self.snapshot.lock().map_err(|_| invalid("input mutex poisoned"))?;
        if let Some(file) = current.files.get(&path) {
            return Ok(Some((file.stamp.clone(), file.content)));
        }
        if current.negative_files.contains(&path) {
            return Ok(None);
        }
        Err(invalid("policy file or its absence was not recorded"))
    }

    pub(crate) fn matches_policy_directory_facts(&self, facts: &InputSnapshot) -> io::Result<bool> {
        let current = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?;
        Ok(facts
            .policy_directories
            .iter()
            .all(|(path, v)| current.policy_directories.get(path) == Some(v)))
    }
    pub(crate) fn policy_directory_facts(
        &self,
        selected: &BTreeSet<PathBuf>,
    ) -> io::Result<InputSnapshot> {
        self.policy_workspace_closure(&BTreeSet::new(), selected.iter())
    }
    pub(crate) fn policy_workspace_closure<'a>(
        &self,
        files: &BTreeSet<PathBuf>,
        directories: impl Iterator<Item = &'a PathBuf>,
    ) -> io::Result<InputSnapshot> {
        self.policy_workspace_closure_paths(files.iter().map(PathBuf::as_path), directories)
    }
    pub(crate) fn policy_workspace_closure_paths<'a, 'b>(
        &self,
        files: impl Iterator<Item = &'a Path>,
        directories: impl Iterator<Item = &'b PathBuf>,
    ) -> io::Result<InputSnapshot> {
        self.policy_workspace_closure_using(files, directories, None, None, None, false, |_, _, _| Ok(false), |facts, _| Ok(facts))
    }

    pub(crate) fn policy_workspace_joined_files<'a>(
        &self,
        files: impl Iterator<Item = &'a Path>,
        discovery: &crate::runner_host::workspace_discovery::DiscoveryReceipt,
    ) -> io::Result<InputSnapshot> {
        self.policy_workspace_joined_files_using(files, discovery, None)
    }

    pub(crate) fn policy_workspace_joined_files_using<'a>(
        &self,
        files: impl Iterator<Item = &'a Path>,
        discovery: &crate::runner_host::workspace_discovery::DiscoveryReceipt,
        donor: Option<&super::DerivedPreflight>,
    ) -> io::Result<InputSnapshot> {
        self.policy_workspace_joined_files_with_limit(files, discovery, donor, None)
    }

    pub(crate) fn policy_workspace_joined_files_with_limit<'a>(
        &self,
        files: impl Iterator<Item = &'a Path>,
        discovery: &crate::runner_host::workspace_discovery::DiscoveryReceipt,
        donor: Option<&super::DerivedPreflight>,
        local_limit: Option<usize>,
    ) -> io::Result<InputSnapshot> {
        self.policy_workspace_joined_files_finish(files, discovery, donor, local_limit, false, |_, _, _| Ok(false), |facts, _| Ok(facts))
    }

    pub(crate) fn policy_workspace_joined_files_hashed(
        &self,
        selected: &[(&Path, usize)],
        discovery: &crate::runner_host::workspace_discovery::DiscoveryReceipt,
        donor: &super::DerivedPreflight,
        local_limit: usize,
        revision: u128,
        configuration: &Path,
        auxiliary: impl Fn(&Path, &FileInput) -> io::Result<bool>,
    ) -> io::Result<(InputSnapshot, u128)> {
        self.policy_workspace_joined_files_hashed_current(
            selected, discovery, donor, local_limit, revision, configuration,
            |path, fact, _| auxiliary(path, fact),
        )
    }

    pub(crate) fn policy_workspace_joined_files_hashed_current(
        &self,
        selected: &[(&Path, usize)],
        discovery: &crate::runner_host::workspace_discovery::DiscoveryReceipt,
        donor: &super::DerivedPreflight,
        local_limit: usize,
        revision: u128,
        configuration: &Path,
        auxiliary: impl Fn(&Path, &FileInput, &InputSnapshot) -> io::Result<bool>,
    ) -> io::Result<(InputSnapshot, u128)> {
        self.policy_workspace_joined_files_finish(
            selected.iter().map(|&(path, _)| path), discovery, Some(donor), Some(local_limit), true, auxiliary,
            |facts, current| {
                let policy_revision = crate::policy_request::workspace_revision_using(
                    revision, &facts, discovery.policy_directories(), None, Some((selected, current)),
                    &discovery.contract().root, &discovery.contract().recursive_roots, configuration,
                )?;
                Ok((facts, policy_revision))
            },
        )
    }

    fn policy_workspace_joined_files_finish<'a, T>(
        &self,
        files: impl Iterator<Item = &'a Path>,
        discovery: &crate::runner_host::workspace_discovery::DiscoveryReceipt,
        donor: Option<&super::DerivedPreflight>,
        local_limit: Option<usize>,
        selected_key_may_differ: bool,
        auxiliary: impl Fn(&Path, &FileInput, &InputSnapshot) -> io::Result<bool>,
        finish: impl FnOnce(InputSnapshot, &InputSnapshot) -> io::Result<T>,
    ) -> io::Result<T> {
        discovery.validate_recording(self)?;
        if let Some(donor) = donor {
            if !std::ptr::eq(donor.discovery().as_ref(), discovery) {
                return Err(invalid("workspace file donor belongs to another discovery"));
            }
            donor.require_recording(self)?;
        }
        self.policy_workspace_closure_using(files, std::iter::empty(), Some(discovery), donor, local_limit, selected_key_may_differ, auxiliary, finish)
    }

    fn policy_workspace_closure_using<'a, 'b, T>(
        &self,
        files: impl Iterator<Item = &'a Path>,
        directories: impl Iterator<Item = &'b PathBuf>,
        discovery: Option<&crate::runner_host::workspace_discovery::DiscoveryReceipt>,
        donor: Option<&super::DerivedPreflight>,
        mut local_limit: Option<usize>,
        selected_key_may_differ: bool,
        auxiliary: impl Fn(&Path, &FileInput, &InputSnapshot) -> io::Result<bool>,
        finish: impl FnOnce(InputSnapshot, &InputSnapshot) -> io::Result<T>,
    ) -> io::Result<T> {
        let current = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?;
        let mut charge_local = |width: usize| -> io::Result<()> {
            if let Some(remaining) = &mut local_limit {
                // Keep the old conservative per-row allowance for the BTree
                // node and path allocation, including insertion scratch.
                let bytes = width.checked_mul(8).and_then(|n| n.checked_add(2048))
                    .ok_or(io::ErrorKind::OutOfMemory)?;
                *remaining = remaining.checked_sub(bytes)
                    .ok_or_else(|| io::Error::new(io::ErrorKind::OutOfMemory, "joined workspace local fact exceeds admitted capture"))?;
            }
            Ok(())
        };
        let mut result = InputSnapshot::new(current.scanned_ns);
        result.path_presence=current.path_presence.clone();result.opened_reads=current.opened_reads.clone();result.original_payloads=current.original_payloads.clone();
        let mut borrowed = 0usize;
        let mut previous: Option<&Path> = None;
        for path in files {
            if donor.is_some() {
                if previous.is_some_and(|previous| previous >= path) {
                    return Err(invalid("joined workspace selected facts are not unique path order"));
                }
                previous = Some(path);
            }
            if let Some(file) = current.files.get(path) {
                if let Some((actual, stamp, content)) = donor.and_then(|owner| owner.workspace_file(path)) {
                    if (!selected_key_may_differ && actual.as_os_str() != path.as_os_str())
                        || file.path.as_os_str() != actual.as_os_str()
                        || &file.stamp != stamp || file.content != content {
                        return Err(invalid(&format!(
                            "workspace file donor differs from the recorded selected fact: selected={path:?}, donor={actual:?}, recorded={:?}, selected_label_differs={}, recorded_label_differs={}, stamp_differs={}, content_differs={}, selected_key_may_differ={selected_key_may_differ}",
                            file.path,
                            actual.as_os_str() != path.as_os_str(),
                            file.path.as_os_str() != actual.as_os_str(),
                            &file.stamp != stamp,
                            file.content != content,
                        )));
                    }
                    borrowed = borrowed.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
                } else if !auxiliary(path, file, &current)? {
                    charge_local(path.as_os_str().len().max(file.path.capacity()))?;
                    result.files.insert(path.to_path_buf(), file.clone());
                }
            } else if current.opened_reads.get(path).is_some_and(|s|s.is_readable())&&current.original_payloads.get(path).is_some(){
                // This actual exact reader did not issue an ordinary FileInput.
                // Its independently funded immutable observations travel below.
            } else if current.negative_files.contains(path) {
                charge_local(path.as_os_str().len())?;
                result.negative_files.insert(path.to_path_buf());
            } else {
                return Err(invalid("workspace requests an unrecorded file/absence"));
            }
        }
        if donor.is_some_and(|owner| borrowed != owner.workspace_file_count()
            || owner.workspace_missing_configuration().is_some_and(|path| !result.negative_files.contains(path))) {
            return Err(invalid("workspace selection does not contain every donated file fact"));
        }
        if let Some(discovery) = discovery {
            discovery.require_current_directories(&current)?;
        }
        for path in directories {
            let observation = current
                .policy_directories
                .get(path)
                .ok_or_else(|| invalid("workspace requests unrecorded typed directory"))?;
            result.record_policy_directory(
                path,
                observation.follow_root,
                observation.listing.clone(),
            )?;
        }
        finish(result, &current)
    }
}

#[cfg(test)]
#[path = "input_policy_directories_tests.rs"]
mod tests;

impl<P:SnapshotProvider> RecordingInputs<P>{
 /// An actual raw-family headroom window reaches the existing bounded
 /// provider before Vec/name growth. Ordinary directory wrappers are unchanged.
 pub(crate) fn capture_policy_directory_lent(&self,path:&Path,follow_root:bool,other_metadata:usize,budget:&Arc<dq_analyze::captured_generator_budget::Budget>,lender:&mut dyn super::RecordedPolicySourceLender)->io::Result<PolicyDirectoryListing>{
  let metadata=||self.snapshot.lock().map_err(|_|invalid("input mutex poisoned during directory settlement"))?.policy_closure_charge();
  let before=metadata()?;
  let owner=self.policy_metadata_owner(Some(budget))?;
  lender.prepare_directory_metadata(&owner,before)?;
  let window=dq_analyze::captured_generator_budget::Budget::reserve_window(budget,METADATA_BOUND).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
  let upper=before.checked_add(window.capacity()).ok_or(io::ErrorKind::OutOfMemory)?;
  lender.directory_window_started(&owner,upper)?;
  let pending=self.capture_policy_directory_with_limit(path,follow_root,other_metadata,Some(window.capacity()));
  // Settle even after real provider/record errors. If metadata cannot be
  // inspected, retain the admitted window and its already-published resource
  // bound. Neither cleanup denial nor cancellation can replace the first IO.
  match metadata(){
   Ok(actual)=>{
    let settled=lender.directory_metadata_settled(&owner,actual);
    if let Err(error)=settled{window.keep();return match pending{Err(first)=>Err(first),Ok(_)=>Err(error)}}
    let settled=lender.settle_directory_window(window,actual.saturating_sub(before)).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m));
    match pending{Err(first)=>Err(first),Ok(listing)=>{settled?;Ok(listing)}}
   }
   Err(error)=>{window.keep();match pending{Err(first)=>Err(first),Ok(_)=>Err(error)}}
  }
 }
}

impl InputSnapshot{
 pub(crate) fn original_observations_subset_of(&self,current:&Self)->bool{
  self.path_presence.iter().all(|(p,v)|current.path_presence.get(p).as_ref()==Some(v))&&self.opened_reads.iter().all(|(p,v)|current.opened_reads.get(p).as_ref()==Some(v))&&self.original_payloads.iter().all(|(p,v)|current.original_payloads.get(p).as_ref()==Some(v))
 }
 pub(crate) fn write_original_workspace_observations(&self,output:&mut impl std::io::Write)->io::Result<()>{
  if self.path_presence.is_empty()&&self.opened_reads.is_empty()&&self.original_payloads.is_empty(){return Ok(())}
  use std::io::Write;output.write_all(b"native-workspace-actual-original-observations-v1")?;
  serde_json::to_writer(output,&(&self.path_presence,&self.opened_reads,&self.original_payloads)).map_err(io::Error::other)
 }
}
