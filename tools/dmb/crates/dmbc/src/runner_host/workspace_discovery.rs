//! Private typed recursive discovery over the SAME RecordingInputs.
//! No source text is parsed or reread here; only metadata is retained.
use crate::input_snapshot::{
    InputSnapshot, PolicyDirectoryListing as Listing, PolicyEntryKind as Kind, RecordingInputs,
    SnapshotProvider,
};
use dm_preprocess::regions::{canonical_path, relative_filesystem_path};
use std::{
    collections::BTreeSet,
    io,
    path::{Path, PathBuf},
    sync::Arc,
};
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct DiscoveryContract {
    pub root: PathBuf,
    pub recursive_roots: Vec<PathBuf>,
}
/// All fields private. Only actual typed observations issue this receipt.
pub(crate) struct DiscoveryReceipt {
    issuer: Arc<()>,
    contract: DiscoveryContract,
    facts: InputSnapshot,
    files: Vec<PathBuf>,
}
impl DiscoveryReceipt {
    pub(crate) fn census(self: &Arc<Self>, census: &mut crate::heap_census::HeapCensus) {
        let owner = "query_snapshot.workspace.discovery";
        if !census.arc_object(owner, self) {
            return;
        }
        census.path(owner, &self.contract.root);
        census.vec_payload(owner, &self.contract.recursive_roots);
        for path in &self.contract.recursive_roots {
            census.path(owner, path);
        }
        census.vec_payload(owner, &self.files);
        for path in &self.files {
            census.path(owner, path);
        }
        census.workspace_policy_facts(&self.facts);
    }

    pub(crate) fn files(&self) -> &[PathBuf] {
        &self.files
    }
    pub(crate) fn directory_paths(&self) -> impl Iterator<Item = &PathBuf> {
        self.facts.policy_directories().keys()
    }
    pub(crate) fn validate_recording<P: SnapshotProvider>(
        &self,
        inputs: &RecordingInputs<P>,
    ) -> io::Result<()> {
        if !Arc::ptr_eq(&self.issuer, &inputs.policy_discovery_issuer())
            || !inputs.matches_policy_directory_facts(&self.facts)?
        {
            return Err(io::Error::other(
                "discovery receipt belongs to another capture/closure",
            ));
        }
        Ok(())
    }
    pub(crate) fn retained_charge(&self) -> io::Result<usize> {
        self.retained_charge_with(&mut BTreeSet::new())
    }
    pub(crate) fn retained_charge_with(&self, seen: &mut BTreeSet<usize>) -> io::Result<usize> {
        self.facts
            .policy_closure_charge_with(seen)?
            .checked_add(
                std::mem::size_of_val(self)
                    + 2 * std::mem::size_of::<usize>()
                    + self.contract.root.capacity()
                    + self.contract.recursive_roots.capacity() * std::mem::size_of::<PathBuf>()
                    + self
                        .contract
                        .recursive_roots
                        .iter()
                        .map(|path| path.capacity())
                        .sum::<usize>()
                    + self.files.capacity() * std::mem::size_of::<PathBuf>()
                    + self.files.iter().map(|path| path.capacity()).sum::<usize>(),
            )
            .ok_or_else(|| io::Error::other("discovery metadata overflow"))
    }

    pub(crate) fn contract(&self) -> &DiscoveryContract {
        &self.contract
    }
}
pub(crate) fn discover<P: SnapshotProvider>(
    inputs: &RecordingInputs<P>,
    mut contract: DiscoveryContract,
) -> io::Result<DiscoveryReceipt> {
    if !contract.root.is_absolute() || contract.recursive_roots.iter().any(|p| !p.is_absolute()) {
        return Err(io::Error::other(
            "workspace discovery paths must be caller absolute",
        ));
    }
    contract.root = canonical_path(&contract.root);
    contract.recursive_roots = contract
        .recursive_roots
        .into_iter()
        .map(|p| canonical_path(&p))
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    if contract.recursive_roots.is_empty() {
        return Err(io::Error::other(
            "workspace discovery needs explicit recursive roots",
        ));
    }
    for root in &contract.recursive_roots {
        if relative_filesystem_path(root, &contract.root).is_none() {
            return Err(io::Error::other(
                "workspace discovery root escapes declared root",
            ));
        }
    }
    // Reserve the traversal's own PathBuf/tree/stack metadata before growing
    // it, in the SAME64MiB family as the typed directory observations. The
    // four path copies cover pending/visited/selected/final closure structures.
    const LIMIT: usize = 64 * 1024 * 1024;
    let mut metadata = 8192usize
        .checked_add(contract.root.capacity())
        .ok_or_else(|| io::Error::other("discovery metadata overflow"))?;
    for root in &contract.recursive_roots {
        metadata = metadata
            .checked_add(512 + root.capacity() * 4)
            .ok_or_else(|| io::Error::other("discovery root metadata overflow"))?;
    }
    fn check<P: SnapshotProvider>(inputs: &RecordingInputs<P>, own: usize) -> io::Result<()> {
        if inputs
            .policy_discovery_metadata_charge()?
            .checked_add(own)
            .is_none_or(|n| n > LIMIT)
        {
            return Err(io::Error::other(
                "discovery traversal exceeds existing64MiB metadata bound",
            ));
        }
        Ok(())
    }
    check(inputs, metadata)?;
    let mut stack = contract
        .recursive_roots
        .iter()
        .cloned()
        .map(|p| (p, true))
        .collect::<Vec<_>>();
    let mut visited = BTreeSet::new();
    let mut files = BTreeSet::new();
    let mut observed = BTreeSet::new();
    while let Some((folder, follow_root)) = stack.pop() {
        crate::daemon::control::checkpoint()?;
        if relative_filesystem_path(&folder, &contract.root).is_none() {
            return Err(io::Error::other(
                "discovered directory escapes declared root",
            ));
        }
        if !visited.insert(folder.clone()) {
            continue;
        }
        let listing = inputs.capture_policy_directory_bounded(&folder, follow_root, metadata)?;
        observed.insert(folder.clone());
        match listing {
            Listing::Missing => {} // exact negative directory fact retained, not an empty positive listing
            Listing::NotDirectory => {
                return Err(io::Error::other(
                    "workspace discovery root changed to nondirectory",
                ))
            }
            Listing::Present(entries) => {
                for entry in entries.iter() {
                    let path = folder.join(&entry.name);
                    match entry.kind {
                        Kind::Directory => {
                            metadata = metadata.checked_add(512 + path.capacity() * 4).ok_or_else(
                                || io::Error::other("discovery directory metadata overflow"),
                            )?;
                            check(inputs, metadata)?;
                            stack.push((path, false));
                        }
                        Kind::File
                            if Path::new(&entry.name)
                                .extension()
                                .is_some_and(|v| v == "dm") =>
                        {
                            if !files.contains(&path) {
                                metadata =
                                    metadata.checked_add(512 + path.capacity() * 4).ok_or_else(
                                        || io::Error::other("discovery source metadata overflow"),
                                    )?;
                                check(inputs, metadata)?;
                                files.insert(path);
                            }
                        }
                        Kind::File | Kind::Symlink | Kind::Other => {}
                    }
                }
            }
        }
    }
    check(inputs, metadata)?;
    let facts = inputs.policy_directory_facts(&observed)?;
    let mut files = files.into_iter().collect::<Vec<_>>();
    files.sort_by_cached_key(|path| {
        relative_filesystem_path(path, &contract.root)
            .unwrap()
            .to_string_lossy()
            .replace('\\', "/")
    });
    let mut relative = std::collections::BTreeSet::new();
    for path in &files {
        let rel = relative_filesystem_path(path, &contract.root)
            .ok_or_else(|| io::Error::other("discovered source escapes root"))?
            .to_string_lossy()
            .replace('\\', "/");
        if !relative.insert(rel) {
            return Err(io::Error::other(
                "distinct discovered provider keys collide in report paths",
            ));
        }
    }
    Ok(DiscoveryReceipt {
        issuer: inputs.policy_discovery_issuer(),
        contract,
        facts,
        files,
    })
}
