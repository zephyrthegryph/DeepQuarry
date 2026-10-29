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
    pub(crate) fn policy_discovery_issuer(&self) -> Arc<()> {
        Arc::clone(&self.source_issuer)
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
        let current = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?;
        let mut result = InputSnapshot::new(current.scanned_ns);
        for path in files {
            if let Some(file) = current.files.get(path) {
                result.files.insert(path.clone(), file.clone());
            } else if current.negative_files.contains(path) {
                result.negative_files.insert(path.clone());
            } else {
                return Err(invalid("workspace requests an unrecorded file/absence"));
            }
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
        Ok(result)
    }
}

#[cfg(test)]
#[path = "input_policy_directories_tests.rs"]
mod tests;
