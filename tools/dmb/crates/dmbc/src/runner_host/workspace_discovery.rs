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

/// The selector actually executed by the only recursive receipt issuer.
/// No caller flag, include glob or exclusion list can construct this value.
#[derive(Clone,Copy)]
enum DiscoverySelection{RecursiveDmNoChildLinksV1}
impl DiscoverySelection{
 fn includes_file(self,path:&Path)->bool{match self{Self::RecursiveDmNoChildLinksV1=>path.extension().is_some_and(|extension|extension=="dm")}}
}

/// All fields private. Only actual typed observations issue this receipt.
pub(crate) struct DiscoveryReceipt {
    issuer: Arc<()>,
    selection: DiscoverySelection,
    contract: DiscoveryContract,
    facts: InputSnapshot,
    files: Vec<PathBuf>,
}
impl DiscoveryReceipt {
    /// Full CODE_DM coverage is a property of this actual unfiltered typed
    /// traversal, not a normal folder fact or a caller's claimed prefix.
    pub(crate) fn covers_code_dm(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        self.covers_dm_roots(dq_analyze::captured_raw_file::code_dm_roots(),false,admit)
    }
    pub(crate) fn covers_generator_cli_tests(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        self.covers_dm_roots(dq_analyze::captured_raw_file::generator_cli_test_roots(),true,admit)
    }
    pub(crate) fn covers_dm_roots(&self,roots:&[(&str,&str)],missing_is_empty:bool,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        match self.selection{DiscoverySelection::RecursiveDmNoChildLinksV1=>{}}
        for &(directory,extension) in roots{
            crate::daemon::control::checkpoint()?;
            if extension!="dm"{return Ok(false)}
            if !self.contract.recursive_roots.iter().any(|root|root.strip_prefix(&self.contract.root).is_ok_and(|relative|Path::new(directory).starts_with(relative))){return Ok(false)}
            admit(self.contract.root.as_os_str().len().checked_add(directory.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(512)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"code discovery proof path overflow"))?)?;
            let code=self.contract.root.join(directory);
            // Must have been reached by THIS typed recursive traversal. An
            // unrelated cached/flat folder listing is absent from these facts.
            let Some(observation)=self.facts.policy_directories().get(&code)else{return Ok(false)};
            if !missing_is_empty&&matches!(observation.listing,Listing::NotDirectory){return Ok(false)}
            // Extra explicit roots must not follow a child symlink that the
            // original CODE_DM WalkDir(follow_links=false) would not traverse.
            for root in &self.contract.recursive_roots{
                if root==&code||!root.starts_with(&code){continue}
                let mut current=root.as_path();
                while current!=code.as_path(){
                    crate::daemon::control::checkpoint()?;
                    let Some(parent)=current.parent()else{return Ok(false)};
                    let Some(name)=current.file_name().and_then(|name|name.to_str())else{return Ok(false)};
                    let Some(parent_observation)=self.facts.policy_directories().get(parent)else{return Ok(false)};
                    let Listing::Present(entries)=&parent_observation.listing else{return Ok(false)};
                    let Ok(index)=entries.binary_search_by(|entry|entry.name.as_str().cmp(name))else{return Ok(false)};
                    if entries[index].kind!=Kind::Directory{return Ok(false)}
                    current=parent;
                }
            }
        }
        Ok(true)
    }

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
    let selection=DiscoverySelection::RecursiveDmNoChildLinksV1;
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
                        Kind::File if selection.includes_file(Path::new(&entry.name)) =>
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
        selection,
        contract,
        facts,
        files,
    })
}
