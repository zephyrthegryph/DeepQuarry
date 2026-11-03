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
enum DiscoverySelection{RecursiveDmNoChildLinksV1,CheckGrepDmAndRawNoChildLinksV1,DocSnippetsCodeAndMarkdownV1,DocSnippetsDemandV2,OwnershipCodeDmV2,UiActionsVisibleRootsV1}
impl DiscoverySelection{
 fn includes_file(self,path:&Path,root:&Path)->bool{match self{
  Self::UiActionsVisibleRootsV1=>path.strip_prefix(root).is_ok_and(|relative|{
   if relative.components().any(|part|part.as_os_str().to_string_lossy().starts_with('.')){return false}
   let extension=relative.extension().and_then(|value|value.to_str());
   (relative.starts_with("code")&&extension==Some("dm"))||
   (relative.starts_with("tgui/packages/tgui/interfaces")&&matches!(extension,Some("tsx"|"ts"|"jsx"|"js")))
  }),
  Self::OwnershipCodeDmV2=>path.strip_prefix(root).is_ok_and(|relative|dq_analyze::captured_raw_file::is_code_dm(&relative.to_string_lossy().replace('\\',"/"))),
  Self::DocSnippetsDemandV2=>path.strip_prefix(root).is_ok_and(|relative|{let relative=relative.to_string_lossy().replace('\\',"/");dq_analyze::captured_raw_file::is_code_dm(&relative)||(!relative.split('/').any(|part|part.starts_with('.'))&&dq_analyze::doc_snippets_policy::is_doc_path(&relative))}),
  Self::DocSnippetsCodeAndMarkdownV1=>path.strip_prefix(root).is_ok_and(|relative|(relative.starts_with("code")&&path.extension().is_some_and(|ext|ext=="dm"))||(relative.starts_with("doc/rewrite")&&path.extension().is_some_and(|ext|ext=="md"))),
  Self::RecursiveDmNoChildLinksV1=>path.extension().is_some_and(|extension|extension=="dm"),
  // Preserve existing code/maps DM roles; the added tgui walk retains only
  // the unique CheckGrep selector, not unrelated tgui DM payloads.
  Self::CheckGrepDmAndRawNoChildLinksV1=>path.strip_prefix(root).is_ok_and(|relative|{let code_or_maps=relative.starts_with("code")||relative.starts_with("maps");let dm=path.file_name().is_some_and(|name|name.as_encoded_bytes().ends_with(b".dm"));(code_or_maps&&dm)||dq_analyze::lints::check_grep::native::selects_filesystem_source(relative)}),
 }}
}
/// Names are issued only by the actual private CheckGrep traversal.
struct DocConfiguration{path:PathBuf,facts:InputSnapshot,value:Arc<dq_analyze::captured_raw_file::Config>}
impl DocConfiguration{fn excludes(&self,relative:&str)->bool{self.value.policy_path_exempt("doc_snippets",dq_analyze::doc_snippets_policy::metadata().group,relative)}fn excludes_subtree(&self,relative:&str)->bool{self.value.borrowed_report_scope("doc_snippets",dq_analyze::doc_snippets_policy::metadata().group).is_some_and(|scope|scope.exempt_prefixes.iter().any(|prefix|relative.starts_with(prefix))||scope.exempt_contains.iter().any(|part|relative.contains(part)))}}
struct CheckGrepNames{dmes:Vec<PathBuf>,jsx:Vec<PathBuf>}

/// All fields private. Only actual typed observations issue this receipt.
pub(crate) struct DiscoveryReceipt {
    issuer: Arc<()>,
    selection: DiscoverySelection,
    contract: DiscoveryContract,
    facts: InputSnapshot,
    files: Vec<PathBuf>,
    check_grep:Option<CheckGrepNames>,
    doc_configuration:Option<DocConfiguration>,
}
impl DiscoveryReceipt {
    pub(crate) fn check_grep_names(&self)->io::Result<(&[PathBuf],&[PathBuf])>{match (&self.selection,&self.check_grep){(DiscoverySelection::CheckGrepDmAndRawNoChildLinksV1,Some(names))=>Ok((&names.dmes,&names.jsx)),_=>Err(io::Error::new(io::ErrorKind::Unsupported,"complete check_grep selection was not actually observed"))}}
    /// Full CODE_DM coverage is a property of this actual unfiltered typed
    /// traversal, not a normal folder fact or a caller's claimed prefix.
    pub(crate) fn covers_code_dm(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        if matches!(self.selection,DiscoverySelection::OwnershipCodeDmV2){return self.covers_selected_roots(&[("code","dm")],true,false,admit)}
        self.covers_dm_roots(dq_analyze::captured_raw_file::code_dm_roots(),false,admit)
    }
    pub(crate) fn covers_generator_cli_tests(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        if matches!(self.selection,DiscoverySelection::OwnershipCodeDmV2){return Ok(false)}
        self.covers_dm_roots(dq_analyze::captured_raw_file::generator_cli_test_roots(),true,admit)
    }
    pub(crate) fn covers_dm_roots(&self,roots:&[(&str,&str)],missing_is_empty:bool,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        if matches!(self.selection,DiscoverySelection::UiActionsVisibleRootsV1){return Ok(false)}
        if matches!(self.selection,DiscoverySelection::DocSnippetsCodeAndMarkdownV1|DiscoverySelection::DocSnippetsDemandV2){return Ok(false)}
        if matches!(self.selection,DiscoverySelection::OwnershipCodeDmV2)&&roots!=[("code","dm")]{return Ok(false)}
        self.covers_selected_roots(roots,missing_is_empty,false,admit)
    }
    /// A mixed MD receipt can certify only the actual doc purpose, never CODE authority.
    pub(crate) fn covers_doc_snippets(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        if !matches!(self.selection,DiscoverySelection::DocSnippetsCodeAndMarkdownV1|DiscoverySelection::DocSnippetsDemandV2){return Ok(false)}
        if matches!(self.selection,DiscoverySelection::DocSnippetsDemandV2){
          let config=self.doc_configuration.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"productive Doc discovery has no actual configuration owner"))?;
          for relative in ["code/","doc/rewrite/"]{crate::daemon::control::checkpoint()?;admit(1024)?;if config.excludes_subtree(relative){continue}if !self.facts.policy_directories().contains_key(&self.contract.root.join(relative.trim_end_matches('/'))){return Ok(false)}}return Ok(true)
        }
        self.covers_selected_roots(&[("doc/rewrite","md"),("code","dm")],true,true,admit)
    }
    /// Only this producer's actual visible mixed-root traversal can issue UI
    /// completion. It cannot grant generic CODE, generator or semantic coverage.
    pub(crate) fn covers_ui_actions(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        if !matches!(self.selection,DiscoverySelection::UiActionsVisibleRootsV1){return Ok(false)}
        self.covers_selected_roots(&[("code","dm"),("tgui/packages/tgui/interfaces","tsx"),("tgui/packages/tgui/interfaces","ts"),("tgui/packages/tgui/interfaces","jsx"),("tgui/packages/tgui/interfaces","js")],true,false,admit)
    }
    fn covers_selected_roots(&self,roots:&[(&str,&str)],missing_is_empty:bool,doc:bool,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        for &(directory,extension) in roots{
            crate::daemon::control::checkpoint()?;
            if extension!="dm"&&!(doc&&directory=="doc/rewrite"&&extension=="md")&&!(matches!(self.selection,DiscoverySelection::UiActionsVisibleRootsV1)&&directory=="tgui/packages/tgui/interfaces"&&matches!(extension,"tsx"|"ts"|"jsx"|"js")){return Ok(false)}
            if matches!(self.selection,DiscoverySelection::CheckGrepDmAndRawNoChildLinksV1)&&!["code","maps","tgui/packages/tgui/interfaces"].iter().any(|root|Path::new(directory).starts_with(root)){return Ok(false)}
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

    pub(crate) fn productive_ui_configuration(&self,path:&Path)->io::Result<Option<&dq_analyze::captured_raw_file::Config>>{
     if !matches!(self.selection,DiscoverySelection::UiActionsVisibleRootsV1){return Ok(None)}
     match &self.doc_configuration{Some(config)if config.path==path=>Ok(Some(config.value.as_ref())),_=>Err(io::Error::new(io::ErrorKind::InvalidInput,"actual UI productive configuration absent or foreign"))}
    }
    pub(crate) fn productive_doc_configuration(&self,path:&Path)->io::Result<Option<&dq_analyze::captured_raw_file::Config>>{if matches!(self.selection,DiscoverySelection::UiActionsVisibleRootsV1){return Ok(None)}match &self.doc_configuration{None=>Ok(None),Some(config)if config.path==path=>Ok(Some(config.value.as_ref())),Some(_)=>Err(io::Error::new(io::ErrorKind::InvalidInput,"Doc discovery configuration differs from actual capture"))}}
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
        if let Some(names)=&self.check_grep{for rows in [&names.dmes,&names.jsx]{census.vec_payload(owner,rows);for path in rows{census.path(owner,path);}}}
        if let Some(config)=&self.doc_configuration{census.path(owner,&config.path);census.workspace_policy_facts(&config.facts);census.arc_object(owner,&config.value);census.unknown(owner,"Doc interpreted scope nested allocations use conservative existing Config admission charge");}
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
        if let Some(config)=&self.doc_configuration{let current=inputs.policy_workspace_closure(&BTreeSet::from([config.path.clone()]),std::iter::empty())?;if !current.same_recorded_facts(&config.facts){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Doc configuration was not recorded by this actual discovery issuer"))}}
        Ok(())
    }
    pub(crate) fn retained_charge(&self) -> io::Result<usize> {
        self.retained_charge_with(&mut BTreeSet::new())
    }
    pub(crate) fn retained_charge_with(&self, seen: &mut BTreeSet<usize>) -> io::Result<usize> {
        let doc=match &self.doc_configuration{None=>0,Some(config)=>config.path.capacity().checked_add(config.value.budget_charge()).and_then(|n|n.checked_add(std::mem::size_of::<DocConfiguration>()+std::mem::size_of::<dq_analyze::captured_raw_file::Config>()+2*std::mem::size_of::<usize>())).and_then(|n|config.facts.policy_closure_charge_with(seen).ok().and_then(|facts|n.checked_add(facts))).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"Doc interpreted configuration metadata overflow"))?};
        self.facts
            .policy_closure_charge_with(seen)?.checked_add(doc).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"Doc metadata overflow"))?
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
                    + self.files.iter().map(|path| path.capacity()).sum::<usize>()
                    + self.check_grep.as_ref().map_or(0,|names|[&names.dmes,&names.jsx].into_iter().map(|rows|rows.capacity()*std::mem::size_of::<PathBuf>()+rows.iter().map(|path|path.capacity()).sum::<usize>()).sum::<usize>()),
            )
            .ok_or_else(|| io::Error::other("discovery metadata overflow"))
    }

    pub(crate) fn contract(&self) -> &DiscoveryContract {
        &self.contract
    }
}
pub(crate) fn discover<P: SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract)->io::Result<DiscoveryReceipt>{
 discover_selected(inputs,contract,DiscoverySelection::RecursiveDmNoChildLinksV1)
}
pub(crate) fn discover_check_grep<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract)->io::Result<DiscoveryReceipt>{
 let root=contract.root.as_path();
 if !root.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"check_grep needs its actual absolute workspace root"))}
 let preflight=root.as_os_str().len().checked_mul(16).and_then(|n|n.checked_add(8192)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"check_grep discovery root overflow"))?;
 if inputs.policy_discovery_metadata_charge()?.checked_add(preflight).is_none_or(|n|n>64*1024*1024){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"check_grep discovery exceeds existing metadata bound"))}
 let expected=["code","maps","tgui"];
 if contract.recursive_roots.len()!=expected.len()||expected.iter().any(|name|!contract.recursive_roots.contains(&root.join(name))){return Err(io::Error::new(io::ErrorKind::Unsupported,"check_grep requires the admitted code/maps/tgui recursive roots"))}
 let receipt=discover_selected(inputs,contract,DiscoverySelection::CheckGrepDmAndRawNoChildLinksV1)?;
 // Canonical alias roots cannot silently change the legacy report namespace.
 // This actual issuer refuses the unproved root-alias domain, never relabels it.
 let expected=["code","maps","tgui"];if expected.iter().any(|name|!receipt.contract.recursive_roots.contains(&receipt.contract.root.join(name))){return Err(io::Error::new(io::ErrorKind::Unsupported,"check_grep root alias report namespace is unissued"))}
 Ok(receipt)
}
pub(crate) fn discover_doc_snippets<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract)->io::Result<DiscoveryReceipt>{
 let root=contract.root.as_path();let expected=["code","doc/rewrite"];
 if !root.is_absolute()||contract.recursive_roots.len()!=2||expected.iter().any(|name|!contract.recursive_roots.contains(&root.join(name))){return Err(io::Error::new(io::ErrorKind::Unsupported,"doc_snippets requires exactly its admitted code and doc/rewrite recursive roots"))}
 let receipt=discover_selected(inputs,contract,DiscoverySelection::DocSnippetsCodeAndMarkdownV1)?;
 if expected.iter().any(|name|!receipt.contract.recursive_roots.contains(&receipt.contract.root.join(name))){return Err(io::Error::new(io::ErrorKind::Unsupported,"doc_snippets root-alias namespace is unissued"))}Ok(receipt)
}
/// Exact original UI selector: visible DM plus four interface source suffixes.
/// This does not open any source body or the physical DME.
pub(crate) fn discover_ui_actions<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract)->io::Result<DiscoveryReceipt>{
 let expected=[contract.root.join("code"),contract.root.join("tgui/packages/tgui/interfaces")];
 if contract.recursive_roots.len()!=expected.len()||expected.iter().any(|path|!contract.recursive_roots.contains(path)){
  return Err(io::Error::new(io::ErrorKind::InvalidInput,"UI actions requires exactly its original code and interface roots"))
 }
 let receipt=discover_selected(inputs,contract,DiscoverySelection::UiActionsVisibleRootsV1)?;
 let mut admit=|_:usize|Ok(());
 if !receipt.covers_ui_actions(&mut admit)?{return Err(io::Error::new(io::ErrorKind::Unsupported,"UI root-alias discovery is unissued"))}
 Ok(receipt)
}
/// Reuse one actual interpreted configuration for UI capture and reporting.
/// Discovery keeps fixed-dispatcher membership even when the UI scope exempts it.
pub(crate) fn discover_ui_actions_productive<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,configuration:&Path)->io::Result<(DiscoveryReceipt,Option<dm_resources::SharedBytes>)>{
 let expected=[contract.root.join("code"),contract.root.join("tgui/packages/tgui/interfaces")];
 if !contract.root.is_absolute()||contract.recursive_roots.len()!=2||expected.iter().any(|path|!contract.recursive_roots.contains(path)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"UI productive capture requires its exact visible roots"))}
 let path=canonical_path(configuration);if !path.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual UI configuration must be absolute"))}
 let bytes=inputs.read_policy_candidate(&path,64*1024*1024)?;
 let peak=bytes.as_ref().map_or(Some(1024),|bytes|bytes.capacity().checked_mul(64).and_then(|n|n.checked_add(8192+path.capacity()*8))).ok_or(io::ErrorKind::OutOfMemory)?;
 if inputs.policy_discovery_metadata_charge()?.checked_add(peak).is_none_or(|n|n>64*1024*1024){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"UI configuration exceeds existing metadata grant before interpretation"))}
 let config=Arc::new(dq_analyze::captured_raw_file::Config::capture(bytes.as_ref().map_or(dq_analyze::captured_raw_policy::Configuration::ProvenMissing,|bytes|dq_analyze::captured_raw_policy::Configuration::Captured(bytes.as_slice()))).map_err(io::Error::other)?);
 let facts=inputs.policy_workspace_closure(&BTreeSet::from([path.clone()]),std::iter::empty())?;
 let receipt=discover_selected_using(inputs,contract,DiscoverySelection::UiActionsVisibleRootsV1,Some(DocConfiguration{path,facts,value:config}))?;
 let mut admit=|_:usize|Ok(());if !receipt.covers_ui_actions(&mut admit)?{return Err(io::Error::new(io::ErrorKind::Unsupported,"UI productive root alias is unissued"))}
 Ok((receipt,bytes))
}
fn discover_selected<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,selection:DiscoverySelection)->io::Result<DiscoveryReceipt>{discover_selected_using(inputs,contract,selection,None)}
fn discover_selected_using<P:SnapshotProvider>(inputs:&RecordingInputs<P>,mut contract:DiscoveryContract,selection:DiscoverySelection,doc_configuration:Option<DocConfiguration>)->io::Result<DiscoveryReceipt>{
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
    if let Some(config)=&doc_configuration{metadata=metadata.checked_add(config.value.budget_charge()).and_then(|n|n.checked_add(config.path.capacity()*8+4096)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"Doc scope/traversal metadata overflow"))?;}
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
    let mut dmes=BTreeSet::new();let mut jsx=BTreeSet::new();
    if matches!(selection,DiscoverySelection::CheckGrepDmAndRawNoChildLinksV1){
     let listing=inputs.capture_policy_directory_bounded(&contract.root,true,metadata)?;observed.insert(contract.root.clone());
     let Listing::Present(entries)=listing else{return Err(io::Error::new(io::ErrorKind::Interrupted,"check_grep workspace root disappeared or changed kind"))};
     for entry in entries.iter(){crate::daemon::control::checkpoint()?;if entry.kind==Kind::File&&dq_analyze::lints::check_grep::native::is_root_dme(&entry.name){let path=contract.root.join(&entry.name);metadata=metadata.checked_add(512+path.capacity()*4).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"check_grep root DME metadata overflow"))?;check(inputs,metadata)?;dmes.insert(path.clone());files.insert(path);}}
    }
    while let Some((folder, follow_root)) = stack.pop() {
        crate::daemon::control::checkpoint()?;
        if matches!(selection,DiscoverySelection::DocSnippetsDemandV2){let relative=folder.strip_prefix(&contract.root).map_err(|_|io::Error::new(io::ErrorKind::InvalidInput,"Doc folder escapes actual root"))?.to_string_lossy().replace('\\',"/");let key=format!("{relative}/");if (relative.starts_with("doc/rewrite/")||relative.split('/').any(|part|part.starts_with('.')))||doc_configuration.as_ref().is_some_and(|config|config.excludes_subtree(&key)){continue}}
        if matches!(selection,DiscoverySelection::OwnershipCodeDmV2|DiscoverySelection::UiActionsVisibleRootsV1)&&folder.strip_prefix(&contract.root).is_ok_and(|relative|relative.components().any(|part|part.as_os_str().to_string_lossy().starts_with('.'))){continue}
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
            Listing::NotDirectory if matches!(selection,DiscoverySelection::DocSnippetsDemandV2|DiscoverySelection::OwnershipCodeDmV2|DiscoverySelection::UiActionsVisibleRootsV1)=>{} // genuine negative subtree observation, never a fabricated empty listing
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
                        Kind::File if selection.includes_file(&path,&contract.root)&&!( !matches!(selection,DiscoverySelection::UiActionsVisibleRootsV1)&&doc_configuration.as_ref().is_some_and(|config|path.strip_prefix(&contract.root).is_ok_and(|relative|config.excludes(&relative.to_string_lossy().replace('\\',"/"))))) =>
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
                        Kind::File if matches!(selection,DiscoverySelection::CheckGrepDmAndRawNoChildLinksV1)=>{
                         let relative=path.strip_prefix(&contract.root).map_err(|_|io::Error::other("check_grep JSX observation escapes root"))?;
                         if dq_analyze::lints::check_grep::native::is_jsx_path(relative)&&!jsx.contains(&path){metadata=metadata.checked_add(512+path.capacity()*4).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"check_grep JSX metadata overflow"))?;check(inputs,metadata)?;jsx.insert(path);}
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
    let mut names_vec=|rows:BTreeSet<PathBuf>|->io::Result<Vec<PathBuf>>{
        let capacity=rows.len().checked_mul(4).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"check_grep name capacity overflow"))?;
        metadata=metadata.checked_add(capacity.checked_mul(std::mem::size_of::<PathBuf>()).and_then(|n|n.checked_add(128)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"check_grep name metadata overflow"))?).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"check_grep name overlap overflow"))?;
        check(inputs,metadata)?;let mut result=Vec::new();result.try_reserve_exact(rows.len()).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;
        if result.capacity()>capacity{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"check_grep actual name capacity exceeds admitted overlap"))}
        result.extend(rows);Ok(result)
    };
    let check_grep=if matches!(selection,DiscoverySelection::CheckGrepDmAndRawNoChildLinksV1){Some(CheckGrepNames{dmes:names_vec(dmes)?,jsx:names_vec(jsx)?})}else{None};
    Ok(DiscoveryReceipt {
        issuer: inputs.policy_discovery_issuer(),
        selection,
        contract,
        facts,
        files,check_grep,doc_configuration,
    })
}

#[cfg(test)]mod doc_source_role_tests{
 use super::*;
 #[test]fn doc_source_receipt_is_mixed_role_not_code_or_maps_and_requires_actual_both_roots(){
  let root=crate::test_scratch::dir("doc-source-role");for dir in ["code","doc/rewrite/archive","maps"]{std::fs::create_dir_all(root.join(dir)).unwrap();}for(path,text)in[("code/a.dm","/proc/a()\n    return\n"),("doc/rewrite/a.md","```dm\na()\n```\n"),("doc/rewrite/archive/x.md","```dm\nx()\n```\n"),("maps/a.dm","// maps are outside doc policy\n")]{std::fs::write(root.join(path),text).unwrap();}
  let input=RecordingInputs::new(crate::input_snapshot::FileSystemInputs,0);let contract=DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("doc/rewrite")]};let docs=discover_doc_snippets(&input,contract.clone()).unwrap();docs.validate_recording(&input).unwrap();assert!(docs.covers_doc_snippets(&mut |_|Ok(())).unwrap());assert!(!docs.covers_code_dm(&mut |_|panic!("mixed MD receipt cannot certify generic CODE authority")).unwrap());assert!(!docs.covers_dm_roots(&[("maps","dm")],true,&mut |_|Ok(())).unwrap());assert!(docs.files().contains(&root.join("doc/rewrite/a.md")));assert!(!docs.files().contains(&root.join("maps/a.dm")));assert_eq!(docs.covers_doc_snippets(&mut |_|Err(io::Error::from_raw_os_error(1450))).unwrap_err().raw_os_error(),Some(1450));
  let other=RecordingInputs::new(crate::input_snapshot::FileSystemInputs,0);assert!(docs.validate_recording(&other).is_err());let plain=discover(&input,contract.clone()).unwrap();assert!(!plain.covers_doc_snippets(&mut |_|Ok(())).unwrap());let mut partial=contract;partial.recursive_roots.pop();assert!(discover_doc_snippets(&input,partial).is_err());
 }
}

pub(crate) fn discover_ownership_code<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract)->io::Result<DiscoveryReceipt>{if contract.recursive_roots.as_slice()!=[contract.root.join("code")]{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Ownership source purpose requires exact CODE_DM"))}discover_selected(inputs,contract,DiscoverySelection::OwnershipCodeDmV2)}
/// Productive source demand of the original Doc algorithm. Recursive archive
/// and exempt payloads never become reads, empty substitutes, or CODE authority.
pub(crate) fn discover_doc_snippets_productive<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,configuration:&Path)->io::Result<(DiscoveryReceipt,Option<dm_resources::SharedBytes>)>{
 let root=&contract.root;let expected=["code","doc/rewrite"];if !root.is_absolute()||contract.recursive_roots.len()!=2||expected.iter().any(|name|!contract.recursive_roots.contains(&root.join(name))){return Err(io::Error::new(io::ErrorKind::InvalidInput,"productive Doc requires its exact two source roots"))}
 let path=canonical_path(configuration);if !path.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual Doc configuration must be absolute"))}
 let bytes=inputs.read_policy_candidate(&path,64*1024*1024)?;let peak=bytes.as_ref().map_or(Some(1024),|bytes|bytes.capacity().checked_mul(64).and_then(|n|n.checked_add(8192+path.capacity()*8))).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;if inputs.policy_discovery_metadata_charge()?.checked_add(peak).is_none_or(|n|n>64*1024*1024){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"Doc configuration exceeds existing metadata grant before interpretation"))}
 let config=Arc::new(dq_analyze::captured_raw_file::Config::capture(bytes.as_ref().map_or(dq_analyze::captured_raw_policy::Configuration::ProvenMissing,|bytes|dq_analyze::captured_raw_policy::Configuration::Captured(bytes.as_slice()))).map_err(io::Error::other)?);
 let facts=inputs.policy_workspace_closure(&BTreeSet::from([path.clone()]),std::iter::empty())?;let receipt=discover_selected_using(inputs,contract,DiscoverySelection::DocSnippetsDemandV2,Some(DocConfiguration{path,facts,value:config}))?;
 if expected.iter().any(|name|!receipt.contract.recursive_roots.contains(&receipt.contract.root.join(name))){return Err(io::Error::new(io::ErrorKind::InvalidInput,"productive Doc root alias changes report namespace"))}Ok((receipt,bytes))
}

/// Request-local conditional Original producer selection. It owns no source
/// payload/model and never authorizes a compiler/checker question.
pub(crate) struct EnginePreflight{
 discovery:Arc<DiscoveryReceipt>,configuration:PathBuf,bytes:Option<dm_resources::SharedBytes>,config:Arc<dq_analyze::captured_raw_file::Config>,facts:InputSnapshot,selection:dq_analyze::captured_engine_layering_pages::Selection,charge:usize,
}
pub(crate) struct EngineNoModelProof{preflight:EnginePreflight}
impl EnginePreflight{
 pub(crate) fn discovery(&self)->&Arc<DiscoveryReceipt>{&self.discovery}
 pub(crate) fn configuration(&self)->(&Path,Option<&[u8]>){(&self.configuration,self.bytes.as_ref().map(|b|b.as_slice()))}
 pub(crate) fn configuration_bytes(&self)->Option<&dm_resources::SharedBytes>{self.bytes.as_ref()}
 pub(crate) fn selection(&self)->&dq_analyze::captured_engine_layering_pages::Selection{&self.selection}
 pub(crate) fn config(&self)->&dq_analyze::captured_raw_file::Config{&self.config}
 pub(crate) fn charge(&self)->usize{self.charge}
 pub(crate) fn is_empty(&self)->bool{self.selection.is_empty()}
 pub(crate) fn require<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>)->io::Result<()>{crate::daemon::control::checkpoint()?;self.discovery.validate_recording(inputs)?;let facts=inputs.policy_workspace_closure(&BTreeSet::from([self.configuration.clone()]),std::iter::empty())?;if !facts.same_recorded_facts(&self.facts){return Err(io::Error::new(io::ErrorKind::InvalidInput,"engine selection configuration differs from its actual recording"))}Ok(())}
 pub(crate) fn into_unselected(self)->io::Result<EngineNoModelProof>{if !self.selection.is_empty(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected engine files cannot receive no-model authority"))}Ok(EngineNoModelProof{preflight:self})}
}
impl EngineNoModelProof{
 pub(crate) fn preflight(&self)->&EnginePreflight{&self.preflight}
 pub(crate) fn require<P:SnapshotProvider>(&self,inputs:&RecordingInputs<P>)->io::Result<()>{self.preflight.require(inputs)?;if !self.preflight.selection.is_empty(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"engine no-model proof contains selected source"))}Ok(())}
}
/// Metadata and configuration ONLY. This executes before Original manifest
/// acquisition; a hostile/missing DME and unrelated CODE bytes are not read.
pub(crate) fn discover_engine_preflight<P:SnapshotProvider>(inputs:&RecordingInputs<P>,intent:&crate::policy_request::AdmittedPolicyRequest)->io::Result<EnginePreflight>{
 crate::daemon::control::checkpoint()?;if dm_preprocess::SourceProvider::initial_environment(inputs)!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(io::Error::new(io::ErrorKind::InvalidInput,"engine preflight requires actual Original input context"))}
 use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure,captured_engine_layering_pages as engine};
 let bad=|s:&str|io::Error::new(io::ErrorKind::InvalidInput,s);let quota=|s:String|io::Error::new(io::ErrorKind::OutOfMemory,s);let actual=|f:Failure|match f{Failure::Operational(e)=>e,Failure::Unsupported(s)=>io::Error::new(io::ErrorKind::Unsupported,s)};
 if intent.analysis_context()!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[crate::policy_request::WorkspaceAuxiliaryQuestion::EngineLayering]||!intent.files().is_empty()||!intent.search_folders().is_empty()||!intent.workspace_generators().is_empty(){return Err(bad("conditional engine requires its exclusive actual Original purpose"))}
 let workspace=intent.workspace().ok_or_else(||bad("engine selection workspace absent"))?;if workspace.recursive_roots.as_slice()!=[workspace.root.join("code")]{return Err(bad("engine preflight requires exactly original CODE_DM root"))}
 let configuration=canonical_path(&workspace.configuration);let bytes=inputs.read_policy_candidate(&configuration,64*1024*1024)?;let peak=bytes.as_ref().map_or(Some(8192),|b|b.capacity().checked_mul(64).and_then(|n|n.checked_add(configuration.capacity()*8+8192))).ok_or(io::ErrorKind::OutOfMemory)?;
 let prior=inputs.policy_discovery_metadata_charge()?;if prior.checked_add(peak).is_none_or(|n|n>64*1024*1024){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"engine configuration cannot fit actual metadata family before interpretation"))}
 let config=Arc::new(dq_analyze::captured_raw_file::Config::capture(bytes.as_ref().map_or(dq_analyze::captured_raw_policy::Configuration::ProvenMissing,|b|dq_analyze::captured_raw_policy::Configuration::Captured(b.as_slice()))).map_err(io::Error::other)?);
 let discovery=Arc::new(discover_ownership_code(inputs,DiscoveryContract{root:workspace.root.clone(),recursive_roots:workspace.recursive_roots.clone()})?);discovery.validate_recording(inputs)?;if discovery.contract.root!=workspace.root||discovery.contract.recursive_roots!=workspace.recursive_roots{return Err(bad("engine authored report namespace differs from actual discovery"))}
 let retained=discovery.retained_charge()?.checked_add(config.budget_charge()).and_then(|n|n.checked_add(bytes.as_ref().map_or(0,dm_resources::SharedBytes::capacity))).and_then(|n|n.checked_add(configuration.capacity()*8+4096)).ok_or(io::ErrorKind::OutOfMemory)?;let already=inputs.policy_discovery_metadata_charge()?.checked_add(retained).ok_or(io::ErrorKind::OutOfMemory)?;let limit=(64usize*1024*1024).checked_sub(already).ok_or(io::ErrorKind::OutOfMemory)?;let budget=Budget::new(limit).map_err(quota)?;
 struct Names<'a>{discovery:&'a DiscoveryReceipt,budget:&'a Arc<Budget>}
 impl engine::PathPages for Names<'_>{fn for_each_path(&self,visit:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<bool,Failure>{for path in self.discovery.files(){crate::daemon::control::checkpoint()?;let relative=path.strip_prefix(&self.discovery.contract.root).map_err(|_|Failure::from("engine path escapes discovery owner"))?;let width=relative.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(512)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget.charge(width).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let relative=relative.to_string_lossy().replace('\\',"/");if !dq_analyze::captured_raw_file::is_code_dm(&relative){return Err("engine discovery selected a non-CODE_DM path".into())}visit(&relative)?;}Ok(true)}}
 let selection=engine::preflight(&Names{discovery:&discovery,budget:&budget},&config,&budget,&crate::daemon::control::checkpoint).map_err(actual)?;budget.require().map_err(quota)?;let facts=inputs.policy_workspace_closure(&BTreeSet::from([configuration.clone()]),std::iter::empty())?;let charge=retained.checked_add(budget.used()).and_then(|n|n.checked_add(facts.policy_closure_charge_with(&mut BTreeSet::new()).ok()?)).ok_or(io::ErrorKind::OutOfMemory)?;if charge>64*1024*1024{return Err(io::ErrorKind::OutOfMemory.into())}let out=EnginePreflight{discovery,configuration,bytes,config,facts,selection,charge};out.require(inputs)?;Ok(out)
}
