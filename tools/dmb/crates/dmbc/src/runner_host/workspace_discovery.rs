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
enum DiscoverySelection{RecursiveDmNoChildLinksV1,MapEditsJoinedDmNoLinksV1,CheckGrepDmAndRawNoChildLinksV1,DocSnippetsCodeAndMarkdownV1,DocSnippetsDemandV2,DocSnippetsJoinedAllowV1,OwnershipCodeDmV2,UiActionsVisibleRootsV1,UiActionsJoinedAllowV1,DocUiJoinedAllowV1, AuthoredDocUiJoinedV1, AuthoredDocUiExtendedV1, AuthoredCheckGrepV1, RegisteredSourceCheckV1}
/// Obligations of the one physical traversal selected by the private issuer.
#[derive(Clone, Copy, Default, Debug, PartialEq, Eq)]
struct DiscoveryFacets {
    map_root_no_follow: bool,
    productive_docs: bool,
    docs_share_complete_dm: bool,
    visible_ui: bool,
    ui_shares_complete_dm: bool,
}

impl DiscoveryFacets {
    fn follows_requested_root(self, root: &Path) -> bool {
        !(self.map_root_no_follow && root.file_name().is_some_and(|name| name == "maps"))
    }

    fn applies_doc_exemption(self, relative: &Path) -> bool {
        self.productive_docs
            && (!self.docs_share_complete_dm || relative.starts_with("doc/rewrite"))
    }
}

impl DiscoverySelection{
 fn facets(self) -> DiscoveryFacets {
     use DiscoverySelection::*;
     DiscoveryFacets {
         map_root_no_follow: matches!(self, MapEditsJoinedDmNoLinksV1 | AuthoredDocUiJoinedV1 | AuthoredDocUiExtendedV1 | AuthoredCheckGrepV1),
         productive_docs: matches!(self, DocSnippetsDemandV2 | DocSnippetsJoinedAllowV1 | DocUiJoinedAllowV1 | AuthoredDocUiJoinedV1 | AuthoredDocUiExtendedV1 | AuthoredCheckGrepV1),
         docs_share_complete_dm: matches!(self, DocSnippetsJoinedAllowV1 | DocUiJoinedAllowV1 | AuthoredDocUiJoinedV1 | AuthoredDocUiExtendedV1 | AuthoredCheckGrepV1),
         visible_ui: matches!(self, UiActionsVisibleRootsV1 | UiActionsJoinedAllowV1 | DocUiJoinedAllowV1 | AuthoredDocUiJoinedV1 | AuthoredDocUiExtendedV1 | AuthoredCheckGrepV1),
         ui_shares_complete_dm: matches!(self, UiActionsJoinedAllowV1 | DocUiJoinedAllowV1 | AuthoredDocUiJoinedV1 | AuthoredDocUiExtendedV1 | AuthoredCheckGrepV1),
     }
 }

 fn observes_check_grep(self) -> bool {
  matches!(self, Self::CheckGrepDmAndRawNoChildLinksV1 | Self::AuthoredCheckGrepV1)
 }

 fn includes_file(self,path:&Path,root:&Path)->bool{match self{
  Self::AuthoredCheckGrepV1 => Self::AuthoredDocUiExtendedV1.includes_file(path,root)
    || path.strip_prefix(root).is_ok_and(dq_analyze::lints::check_grep::native::selects_filesystem_source),
  Self::AuthoredDocUiExtendedV1=>Self::AuthoredDocUiJoinedV1.includes_file(path,root)
   ||path.strip_prefix(root).is_ok_and(|relative|
      (relative.starts_with("interface")||relative.starts_with("modular_chomp"))
      &&relative.extension().is_some_and(|ext|ext=="dm")),
  Self::DocUiJoinedAllowV1|Self::AuthoredDocUiJoinedV1=>Self::UiActionsJoinedAllowV1.includes_file(path,root)
   ||path.strip_prefix(root).is_ok_and(|relative|
    dq_analyze::doc_snippets_policy::is_doc_path(&relative.to_string_lossy().replace('\\',"/"))),
  Self::UiActionsJoinedAllowV1=>path.strip_prefix(root).is_ok_and(|relative|
   ((relative.starts_with("code")||relative.starts_with("maps"))&&relative.extension().is_some_and(|ext|ext=="dm"))
    ||Self::UiActionsVisibleRootsV1.includes_file(path,root)),
  Self::UiActionsVisibleRootsV1=>path.strip_prefix(root).is_ok_and(|relative|{
   if relative.components().any(|part|part.as_os_str().to_string_lossy().starts_with('.')){return false}
   let extension=relative.extension().and_then(|value|value.to_str());
   (relative.starts_with("code")&&extension==Some("dm"))||
   (relative.starts_with("tgui/packages/tgui/interfaces")&&matches!(extension,Some("tsx"|"ts"|"jsx"|"js")))
  }),
  Self::OwnershipCodeDmV2=>path.strip_prefix(root).is_ok_and(|relative|dq_analyze::captured_raw_file::is_code_dm(&relative.to_string_lossy().replace('\\',"/"))),
  Self::DocSnippetsJoinedAllowV1=>path.strip_prefix(root).is_ok_and(|relative|{
   if (relative.starts_with("code")||relative.starts_with("maps"))&&relative.extension().is_some_and(|ext|ext=="dm"){return true}
   let relative=relative.to_string_lossy().replace('\\',"/");
   !relative.split('/').any(|part|part.starts_with('.'))&&dq_analyze::doc_snippets_policy::is_doc_path(&relative)
  }),
  Self::DocSnippetsDemandV2=>path.strip_prefix(root).is_ok_and(|relative|{let relative=relative.to_string_lossy().replace('\\',"/");dq_analyze::captured_raw_file::is_code_dm(&relative)||(!relative.split('/').any(|part|part.starts_with('.'))&&dq_analyze::doc_snippets_policy::is_doc_path(&relative))}),
  Self::DocSnippetsCodeAndMarkdownV1=>path.strip_prefix(root).is_ok_and(|relative|(relative.starts_with("code")&&path.extension().is_some_and(|ext|ext=="dm"))||(relative.starts_with("doc/rewrite")&&path.extension().is_some_and(|ext|ext=="md"))),
  Self::RegisteredSourceCheckV1=>false, // actual plan is required by the shared issuer below
  Self::RecursiveDmNoChildLinksV1|Self::MapEditsJoinedDmNoLinksV1=>path.extension().is_some_and(|extension|extension=="dm"),
  // Preserve existing code/maps DM roles; the added tgui walk retains only
  // the unique CheckGrep selector, not unrelated tgui DM payloads.
  Self::CheckGrepDmAndRawNoChildLinksV1=>path.strip_prefix(root).is_ok_and(|relative|{let code_or_maps=relative.starts_with("code")||relative.starts_with("maps");let dm=path.file_name().is_some_and(|name|name.as_encoded_bytes().ends_with(b".dm"));(code_or_maps&&dm)||dq_analyze::lints::check_grep::native::selects_filesystem_source(relative)}),
 }}
}
/// Names are issued only by the actual private CheckGrep traversal.
struct DocConfiguration{path:PathBuf,observation:Option<(crate::input_snapshot::Stamp,u128)>,value:Arc<dq_analyze::captured_raw_file::Config>,scope_bound:usize,scope_prepaid:bool}
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
    registered_check:Option<Arc<crate::runner_host::NativeCheckSelection>>,
}
impl DiscoveryReceipt {
    /// Only the same private selector and the actual typed traversal certify
    /// this selected producer. No generic CODE/model coverage is granted.
    /// A required index subdomain is certified only by an ACTUAL unpruned
    /// selected producer domain (or independent full audit/model dependency),
    /// never by the dynamic discovery tag alone.
    pub(crate) fn covers_registered_index_roots(&self,plan:&Arc<crate::runner_host::NativeCheckSelection>,roots:&[(&str,&str)],missing_is_empty:bool,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        self.requires_registered_check(plan)?;
        if !plan.source_only()&&roots==dq_analyze::tree::CODE_DM.roots{return self.covers_selected_roots(roots,missing_is_empty,false,admit)}
        let includes=|declared:&[(&str,&str)]|roots.iter().all(|required|declared.iter().any(|held|held==required));
        if plan.audit_unused()&&includes(dq_analyze::allow_annotation_policy::metadata().select.roots)&&self.covers_registered_audit(plan,admit)?{return self.covers_selected_roots(roots,missing_is_empty,false,admit)}
        for meta in plan.metadata(){if plan.needs_unselected_source(meta)&&includes(meta.select.roots)&&self.covers_registered_check(plan,meta,admit)?{return self.covers_selected_roots(roots,missing_is_empty,false,admit)}}
        Ok(false)
    }
    pub(crate) fn covers_registered_check(&self,plan:&Arc<crate::runner_host::NativeCheckSelection>,meta:&dq_analyze::lint::Meta,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        let Some(held)=&self.registered_check else{return Ok(false)};
        if !Arc::ptr_eq(held,plan)||!plan.metadata().any(|actual|std::ptr::eq(actual,meta)){return Ok(false)}
        self.registered_domain_observed(plan,meta,admit)
    }
    pub(crate) fn covers_registered_audit(&self,plan:&Arc<crate::runner_host::NativeCheckSelection>,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        self.requires_registered_check(plan)?;if !plan.audit_unused(){return Ok(false)}
        self.registered_domain_observed(plan,dq_analyze::allow_annotation_policy::metadata(),admit)
    }
    fn registered_domain_observed(&self,plan:&Arc<crate::runner_host::NativeCheckSelection>,meta:&dq_analyze::lint::Meta,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        for &(directory,_) in meta.select.roots{
            crate::daemon::control::checkpoint()?;
            admit(self.contract.root.as_os_str().len().checked_add(directory.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(512)).ok_or(io::ErrorKind::OutOfMemory)?)?;
            let root=self.contract.root.join(directory);
            if !plan.needs_source_directory(directory,self.registered_configuration(plan)?){continue}
            if !self.contract.recursive_roots.contains(&root)||!self.facts.policy_directories().contains_key(&root){return Ok(false)}
        }
        Ok(true)
    }
    pub(crate) fn requires_registered_check(&self,plan:&Arc<crate::runner_host::NativeCheckSelection>)->io::Result<()>{
        if self.registered_check.as_ref().is_some_and(|held|Arc::ptr_eq(held,plan)){Ok(())}else{Err(io::Error::new(io::ErrorKind::InvalidInput,"registered source discovery belongs to another actual selection"))}
    }
    pub(crate) fn registered_configuration(&self,plan:&Arc<crate::runner_host::NativeCheckSelection>)->io::Result<&dq_analyze::captured_raw_file::Config>{
        self.requires_registered_check(plan)?;self.doc_configuration.as_ref().map(|row|row.value.as_ref()).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"registered discovery lacks its actual captured configuration"))
    }
    pub(crate) fn registered_plan(&self)->Option<&Arc<crate::runner_host::NativeCheckSelection>>{self.registered_check.as_ref()}
    pub(crate) fn check_grep_names(&self)->io::Result<(&[PathBuf],&[PathBuf])>{match &self.check_grep{Some(names) if self.selection.observes_check_grep()=>Ok((&names.dmes,&names.jsx)),_=>Err(io::Error::new(io::ErrorKind::Unsupported,"complete check_grep selection was not actually observed"))}}
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
        if matches!(self.selection,DiscoverySelection::RegisteredSourceCheckV1){
            let Some(plan)=&self.registered_check else{return Ok(false)};
            // The actual private registered model demand retains complete CODE
            // declarations, independently of any selected lint exemption.
            // A source-only productive plan can never enter this path.
            if plan.source_only()||roots!=dq_analyze::tree::CODE_DM.roots{return Ok(false)}
            return self.covers_selected_roots(roots,missing_is_empty,false,admit)
        }
        if matches!(self.selection,DiscoverySelection::UiActionsVisibleRootsV1){return Ok(false)}
        if matches!(self.selection,DiscoverySelection::DocSnippetsCodeAndMarkdownV1|DiscoverySelection::DocSnippetsDemandV2){return Ok(false)}
        if matches!(self.selection,DiscoverySelection::OwnershipCodeDmV2)&&roots!=[("code","dm")]{return Ok(false)}
        if matches!(self.selection,DiscoverySelection::DocSnippetsJoinedAllowV1|DiscoverySelection::UiActionsJoinedAllowV1|DiscoverySelection::DocUiJoinedAllowV1|DiscoverySelection::AuthoredDocUiJoinedV1|DiscoverySelection::AuthoredDocUiExtendedV1|DiscoverySelection::AuthoredCheckGrepV1)
            && roots.iter().any(|(root,ext)| *ext!="dm"
                || !(Path::new(root).starts_with("code")||Path::new(root).starts_with("maps")
                    || (matches!(self.selection,DiscoverySelection::AuthoredDocUiExtendedV1|DiscoverySelection::AuthoredCheckGrepV1)
                        && (Path::new(root).starts_with("interface")||Path::new(root).starts_with("modular_chomp")))
                    || matches!(self.selection,DiscoverySelection::AuthoredCheckGrepV1) && Path::new(root).starts_with("tgui/packages/tgui/interfaces"))) {
            return Ok(false)
        }
        self.covers_selected_roots(roots,missing_is_empty,false,admit)
    }
    /// A mixed MD receipt can certify only the actual doc purpose, never CODE authority.
    pub(crate) fn covers_doc_snippets(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        if !matches!(self.selection,DiscoverySelection::DocSnippetsCodeAndMarkdownV1|DiscoverySelection::DocSnippetsDemandV2|DiscoverySelection::DocSnippetsJoinedAllowV1|DiscoverySelection::DocUiJoinedAllowV1|DiscoverySelection::AuthoredDocUiJoinedV1|DiscoverySelection::AuthoredDocUiExtendedV1|DiscoverySelection::AuthoredCheckGrepV1){return Ok(false)}
        if self.selection.facets().productive_docs{
          let config=self.doc_configuration.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"productive Doc discovery has no actual configuration owner"))?;
          for relative in ["code/","doc/rewrite/"]{crate::daemon::control::checkpoint()?;admit(1024)?;if config.excludes_subtree(relative){continue}if !self.facts.policy_directories().contains_key(&self.contract.root.join(relative.trim_end_matches('/'))){return Ok(false)}}return Ok(true)
        }
        self.covers_selected_roots(&[("doc/rewrite","md"),("code","dm")],true,true,admit)
    }
    /// Only this producer's actual visible mixed-root traversal can issue UI
    /// completion. It cannot grant generic CODE, generator or semantic coverage.
    pub(crate) fn covers_ui_actions(&self,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        if !self.selection.facets().visible_ui{return Ok(false)}
        self.covers_selected_roots(&[("code","dm"),("tgui/packages/tgui/interfaces","tsx"),("tgui/packages/tgui/interfaces","ts"),("tgui/packages/tgui/interfaces","jsx"),("tgui/packages/tgui/interfaces","js")],true,false,admit)
    }
    fn covers_selected_roots(&self,roots:&[(&str,&str)],missing_is_empty:bool,doc:bool,admit:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<bool>{
        for &(directory,extension) in roots{
            crate::daemon::control::checkpoint()?;
            if extension!="dm"&&!(doc&&directory=="doc/rewrite"&&extension=="md")&&!(matches!(self.selection,DiscoverySelection::UiActionsVisibleRootsV1|DiscoverySelection::UiActionsJoinedAllowV1|DiscoverySelection::DocUiJoinedAllowV1|DiscoverySelection::AuthoredDocUiJoinedV1|DiscoverySelection::AuthoredDocUiExtendedV1|DiscoverySelection::AuthoredCheckGrepV1)&&directory=="tgui/packages/tgui/interfaces"&&matches!(extension,"tsx"|"ts"|"jsx"|"js")){return Ok(false)}
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

    /// Only the issuer can combine these obligations. The already-issued raw
    /// Docs/UI profile follows its maps root and therefore cannot qualify.
    pub(crate) fn has_authored_doc_ui_facets(&self) -> bool {
        let facets = self.selection.facets();
        facets.map_root_no_follow && facets.docs_share_complete_dm && facets.ui_shares_complete_dm
    }

    pub(crate) fn matches_authored_doc_ui_profile(&self, roots: &[&str]) -> bool {
        use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
        let selected = match self.selection {
            DiscoverySelection::AuthoredDocUiJoinedV1 => Q::AUTHORED_DOC_UI_ROOTS,
            DiscoverySelection::AuthoredDocUiExtendedV1 => Q::EXTENDED_AUTHORED_DOC_UI_ROOTS,
            DiscoverySelection::AuthoredCheckGrepV1 if self.check_grep.is_some() =>
                Q::AUTHORED_DOC_UI_CHECK_GREP_ROOTS,
            _ => return false,
        };
        roots == selected && self.has_authored_doc_ui_facets()
            && self.contract.recursive_roots.len() == roots.len()
            && self.contract.recursive_roots.iter().zip(roots).all(|(actual, expected)|
                actual.strip_prefix(&self.contract.root).ok() == Some(Path::new(expected)))
    }

    pub(crate) fn productive_ui_configuration(&self,path:&Path)->io::Result<Option<&dq_analyze::captured_raw_file::Config>>{
     if !self.selection.facets().visible_ui{return Ok(None)}
     match &self.doc_configuration{Some(config)if config.path==path=>Ok(Some(config.value.as_ref())),_=>Err(io::Error::new(io::ErrorKind::InvalidInput,"actual UI productive configuration absent or foreign"))}
    }
    pub(crate) fn productive_doc_configuration(&self,path:&Path)->io::Result<Option<&dq_analyze::captured_raw_file::Config>>{if matches!(self.selection,DiscoverySelection::UiActionsVisibleRootsV1|DiscoverySelection::UiActionsJoinedAllowV1){return Ok(None)}match &self.doc_configuration{None=>Ok(None),Some(config)if config.path==path=>Ok(Some(config.value.as_ref())),Some(_)=>Err(io::Error::new(io::ErrorKind::InvalidInput,"Doc discovery configuration differs from actual capture"))}}
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
        if let Some(config)=&self.doc_configuration{census.path(owner,&config.path);census.arc_object(owner,&config.value);census.unknown(owner,"Doc interpreted scope nested allocations use conservative existing Config admission charge");}
        census.workspace_policy_facts(&self.facts);
    }

    pub(crate) fn files(&self) -> &[PathBuf] {
        &self.files
    }
    pub(crate) fn joined_map_directory(&self, path: &Path) -> io::Result<&Listing> {
        if !matches!(self.selection, DiscoverySelection::AuthoredCheckGrepV1) || !path.starts_with(self.contract.root.join("maps")) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined MapEdits directory escapes its actual traversal"));
        }
        self.facts.policy_directories().get(path).filter(|fact| !fact.follow_root)
            .map(|fact| &fact.listing).ok_or_else(|| io::Error::new(io::ErrorKind::Unsupported, "joined MapEdits requires its actual no-follow directory observation"))
    }
    pub(crate) fn policy_directories(&self) -> &std::collections::BTreeMap<PathBuf, crate::input_snapshot::PolicyDirectoryObservation> {
        self.facts.policy_directories()
    }
    pub(crate) fn directory_paths(&self) -> impl Iterator<Item = &PathBuf> {
        self.facts.policy_directories().keys()
    }
    pub(crate) fn directory_matches(
        &self, path: &PathBuf, expected: &crate::input_snapshot::PolicyDirectoryObservation,
    ) -> bool {
        self.facts.policy_directories().get(path)==Some(expected)
    }

    pub(crate) fn all_directories_match(
        &self, mut require: impl FnMut(&PathBuf,&crate::input_snapshot::PolicyDirectoryObservation)->bool,
    ) -> bool {
        self.facts.policy_directories().iter().all(|(path,fact)|require(path,fact))
    }

    pub(crate) fn directories_in(&self, current: &crate::input_snapshot::InputSnapshot) -> bool {
        self.facts.policy_directories().iter()
            .all(|(path,fact)| current.policy_directories().get(path)==Some(fact))
    }
    pub(crate) fn require_current_directories(&self, current: &crate::input_snapshot::InputSnapshot) -> io::Result<()> {
        for (path, fact) in self.facts.policy_directories() {
            crate::daemon::control::checkpoint()?;
            if current.policy_directories().get(path) != Some(fact) {
                return Err(io::Error::new(io::ErrorKind::InvalidData, "Derived actual preflight typed directory changed"));
            }
        }
        Ok(())
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
        if let Some(config)=&self.doc_configuration{if inputs.recorded_policy_file_observation(&config.path)? != config.observation{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Doc configuration was not recorded by this actual discovery issuer"))}}
        Ok(())
    }
    pub(crate) fn retained_charge(&self) -> io::Result<usize> {
        self.retained_charge_with(&mut BTreeSet::new())
    }
    pub(crate) fn retained_charge_with(&self, seen: &mut BTreeSet<usize>) -> io::Result<usize> {
        let doc=match &self.doc_configuration{None=>0,Some(config)=>config.path.capacity().checked_add(config.scope_bound).and_then(|n|n.checked_add(std::mem::size_of::<DocConfiguration>()+std::mem::size_of::<dq_analyze::captured_raw_file::Config>()+2*std::mem::size_of::<usize>())).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"Doc interpreted configuration metadata overflow"))?};
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
/// The joined MapEdits fold uses this same maps root with its strict
/// no-follow contract. The CODE root keeps ordinary discovery.
pub(crate) fn discover_joined_map_edits<P: SnapshotProvider>(
    inputs: &RecordingInputs<P>, contract: DiscoveryContract,
) -> io::Result<DiscoveryReceipt> {
    if contract.recursive_roots.as_slice() != [contract.root.join("code"), contract.root.join("maps")] {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined MapEdits requires exact CODE and MAPS roots"));
    }
    discover_selected(inputs, contract, DiscoverySelection::MapEditsJoinedDmNoLinksV1)
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
 discover_productive_ui_domains(inputs,contract,configuration,&["code","tgui/packages/tgui/interfaces"],DiscoverySelection::UiActionsVisibleRootsV1)
}

pub(crate) fn discover_ui_actions_joined<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,configuration:&Path)->io::Result<(DiscoveryReceipt,Option<dm_resources::SharedBytes>)>{
 discover_productive_ui_domains(inputs,contract,configuration,&["code","maps","tgui/packages/tgui/interfaces"],DiscoverySelection::UiActionsJoinedAllowV1)
}

fn discover_productive_ui_domains<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,configuration:&Path,expected:&[&str],selection:DiscoverySelection)->io::Result<(DiscoveryReceipt,Option<dm_resources::SharedBytes>)>{
 if !contract.root.is_absolute()||contract.recursive_roots.len()!=expected.len()||expected.iter().any(|name|!contract.recursive_roots.contains(&contract.root.join(name))){return Err(io::Error::new(io::ErrorKind::InvalidInput,"UI productive capture requires its exact visible roots"))}
 let path=canonical_path(configuration);if !path.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual UI configuration must be absolute"))}
 let bytes=inputs.read_policy_candidate(&path,64*1024*1024)?;
 let peak=bytes.as_ref().map_or(Some(1024),|bytes|bytes.capacity().checked_mul(64).and_then(|n|n.checked_add(8192+path.capacity()*8))).ok_or(io::ErrorKind::OutOfMemory)?;
 if inputs.policy_discovery_metadata_charge()?.checked_add(peak).is_none_or(|n|n>64*1024*1024){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"UI configuration exceeds existing metadata grant before interpretation"))}
 let config=Arc::new(dq_analyze::captured_raw_file::Config::capture(bytes.as_ref().map_or(dq_analyze::captured_raw_policy::Configuration::ProvenMissing,|bytes|dq_analyze::captured_raw_policy::Configuration::Captured(bytes.as_slice()))).map_err(io::Error::other)?);
 let observation=inputs.recorded_policy_file_observation(&path)?;
 let scope_bound=config.budget_charge();
 let receipt=discover_selected_using(inputs,contract,selection,Some(DocConfiguration{path,observation,value:config,scope_bound,scope_prepaid:false}))?;
 let mut admit=|_:usize|Ok(());if !receipt.covers_ui_actions(&mut admit)?{return Err(io::Error::new(io::ErrorKind::Unsupported,"UI productive root alias is unissued"))}
 Ok((receipt,bytes))
}
fn discover_selected<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,selection:DiscoverySelection)->io::Result<DiscoveryReceipt>{discover_selected_using(inputs,contract,selection,None)}
fn discover_selected_using<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,selection:DiscoverySelection,doc_configuration:Option<DocConfiguration>)->io::Result<DiscoveryReceipt>{discover_selected_lent(inputs,contract,selection,doc_configuration,None)}
fn discover_selected_lent<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,selection:DiscoverySelection,doc_configuration:Option<DocConfiguration>,lender:Option<(&Arc<dq_analyze::captured_generator_budget::Budget>,&mut dyn crate::input_snapshot::RecordedPolicySourceLender)>)->io::Result<DiscoveryReceipt>{
    discover_selected_lent_scoped(inputs,contract,selection,doc_configuration,lender,None)
}
fn discover_selected_lent_scoped<P:SnapshotProvider>(inputs:&RecordingInputs<P>,mut contract:DiscoveryContract,selection:DiscoverySelection,doc_configuration:Option<DocConfiguration>,mut lender:Option<(&Arc<dq_analyze::captured_generator_budget::Budget>,&mut dyn crate::input_snapshot::RecordedPolicySourceLender)>,scratch:Option<&Arc<dq_analyze::captured_generator_budget::Budget>>)->io::Result<DiscoveryReceipt>{
    discover_selected_lent_scoped_plan(inputs,contract,selection,doc_configuration,lender,scratch,None)
}
fn discover_selected_lent_scoped_plan<P:SnapshotProvider>(inputs:&RecordingInputs<P>,mut contract:DiscoveryContract,selection:DiscoverySelection,doc_configuration:Option<DocConfiguration>,mut lender:Option<(&Arc<dq_analyze::captured_generator_budget::Budget>,&mut dyn crate::input_snapshot::RecordedPolicySourceLender)>,scratch:Option<&Arc<dq_analyze::captured_generator_budget::Budget>>,registered_check:Option<Arc<crate::runner_host::NativeCheckSelection>>)->io::Result<DiscoveryReceipt>{
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
    let metadata_budget=scratch.cloned().or_else(||lender.as_ref().map(|(budget,_)|Arc::clone(budget)));
    // Joined Derived already paid this exact shared scope owner. Keep it
    // in the discovery metadata limit, with no second source-family debit.
    let mut funded_metadata=doc_configuration.as_ref().filter(|config|config.scope_prepaid).map_or(0,|config|config.scope_bound);
    let mut fund_metadata=|bytes:usize|->io::Result<()>{if let Some(budget)=&metadata_budget{let extra=bytes.saturating_sub(funded_metadata);budget.charge(extra).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;}funded_metadata=funded_metadata.max(bytes);Ok(())};
    if let Some(config)=&doc_configuration{metadata=metadata.checked_add(config.scope_bound).and_then(|n|n.checked_add(config.path.capacity()*8+4096)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"Doc scope/traversal metadata overflow"))?;}
    fund_metadata(metadata)?;check(inputs, metadata)?;
    if matches!(selection,DiscoverySelection::RegisteredSourceCheckV1)!=registered_check.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"registered discovery requires its actual selector"))}
    let facets = selection.facets();
    let mut stack = contract
        .recursive_roots
        .iter()
        .cloned()
        .map(|p| {
            let follow_root = facets.follows_requested_root(&p);
            (p, follow_root)
        })
        .collect::<Vec<_>>();
    let mut visited = BTreeSet::new();
    let mut files = BTreeSet::new();
    let mut observed = BTreeSet::new();
    let mut dmes=BTreeSet::new();let mut jsx=BTreeSet::new();
    if selection.observes_check_grep(){
     let listing=match lender.as_mut(){Some((budget,owner))=>inputs.capture_policy_directory_lent(&contract.root,true,metadata,budget,&mut **owner)?,None=>inputs.capture_policy_directory_bounded(&contract.root,true,metadata)?};observed.insert(contract.root.clone());
     let Listing::Present(entries)=listing else{return Err(io::Error::new(io::ErrorKind::Interrupted,"check_grep workspace root disappeared or changed kind"))};
     for entry in entries.iter(){crate::daemon::control::checkpoint()?;if entry.kind==Kind::File&&dq_analyze::lints::check_grep::native::is_root_dme(&entry.name){let path=contract.root.join(&entry.name);metadata=metadata.checked_add(512+path.capacity()*4).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"check_grep root DME metadata overflow"))?;fund_metadata(metadata)?;check(inputs,metadata)?;dmes.insert(path.clone());files.insert(path);}}
    }
    while let Some((folder, follow_root)) = stack.pop() {
        if let Some(plan)=&registered_check{
            crate::daemon::control::checkpoint()?;
            let relative=folder.strip_prefix(&contract.root).map_err(|_|io::Error::new(io::ErrorKind::InvalidInput,"registered discovery folder escapes workspace"))?.to_string_lossy().replace('\\',"/");
            let config=doc_configuration.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"registered discovery lacks actual configuration"))?;
            if !plan.needs_source_directory(&relative,&config.value){continue}
        }
        crate::daemon::control::checkpoint()?;
        if matches!(selection,DiscoverySelection::DocSnippetsDemandV2){let relative=folder.strip_prefix(&contract.root).map_err(|_|io::Error::new(io::ErrorKind::InvalidInput,"Doc folder escapes actual root"))?.to_string_lossy().replace('\\',"/");let key=format!("{relative}/");if (relative.starts_with("doc/rewrite/")||relative.split('/').any(|part|part.starts_with('.')))||doc_configuration.as_ref().is_some_and(|config|config.excludes_subtree(&key)){continue}}
        if facets.docs_share_complete_dm {
            let relative=folder.strip_prefix(&contract.root).map_err(|_|io::Error::new(io::ErrorKind::InvalidInput,"Doc folder escapes actual root"))?;
            if relative.starts_with("doc/rewrite") {
                let config=doc_configuration.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"joined Doc lacks its productive configuration"))?;
                if relative!=Path::new("doc/rewrite")||config.excludes_subtree("doc/rewrite/"){continue}
            }
        }
        if facets.ui_shares_complete_dm && !selection.observes_check_grep()
            && folder.strip_prefix(&contract.root).is_ok_and(|relative|
                relative.starts_with("tgui/packages/tgui/interfaces")
                && relative.components().any(|part|part.as_os_str().to_string_lossy().starts_with('.'))) {continue}
        if matches!(selection,DiscoverySelection::OwnershipCodeDmV2|DiscoverySelection::UiActionsVisibleRootsV1)&&folder.strip_prefix(&contract.root).is_ok_and(|relative|relative.components().any(|part|part.as_os_str().to_string_lossy().starts_with('.'))){continue}
        if relative_filesystem_path(&folder, &contract.root).is_none() {
            return Err(io::Error::other(
                "discovered directory escapes declared root",
            ));
        }
        if !visited.insert(folder.clone()) {
            continue;
        }
        let listing = match lender.as_mut(){Some((budget,owner))=>inputs.capture_policy_directory_lent(&folder,follow_root,metadata,budget,&mut **owner)?,None=>inputs.capture_policy_directory_bounded(&folder,follow_root,metadata)?};
        observed.insert(folder.clone());
        match listing {
            Listing::Missing => {} // exact negative directory fact retained, not an empty positive listing
            Listing::NotDirectory if matches!(selection,DiscoverySelection::DocSnippetsDemandV2|DiscoverySelection::OwnershipCodeDmV2|DiscoverySelection::UiActionsVisibleRootsV1)=>{} // genuine negative subtree observation, never a fabricated empty listing
            Listing::NotDirectory if registered_check.as_ref().is_some_and(|plan|plan.source_only())=>{} // actual negative source-only selection, never an empty positive listing
            Listing::NotDirectory => {
                return Err(io::Error::other(
                    "workspace discovery root changed to nondirectory",
                ))
            }
            Listing::Present(entries) => {
                for entry in entries.iter() {
                    let path = folder.join(&entry.name);
                    if entry.kind == Kind::File && selection.observes_check_grep() {
                        let relative=path.strip_prefix(&contract.root).map_err(|_|io::Error::other("check_grep JSX observation escapes root"))?;
                        if dq_analyze::lints::check_grep::native::is_jsx_path(relative)&&!jsx.contains(&path) {
                            metadata=metadata.checked_add(512+path.capacity()*4).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"check_grep JSX metadata overflow"))?;
                            fund_metadata(metadata)?;check(inputs,metadata)?;jsx.insert(path.clone());
                        }
                    }
                    match entry.kind {
                        Kind::Directory => {
                            metadata = metadata.checked_add(512 + path.capacity() * 4).ok_or_else(
                                || io::Error::other("discovery directory metadata overflow"),
                            )?;
                            fund_metadata(metadata)?;check(inputs, metadata)?;
                            stack.push((path, false));
                        }
                        Kind::File if registered_check.as_ref().map_or_else(||selection.includes_file(&path,&contract.root),|plan|
                            path.strip_prefix(&contract.root).is_ok_and(|relative|{
                                let relative=relative.to_string_lossy().replace('\\',"/");
                                plan.metadata().any(|meta|dq_analyze::captured_registry_check_selection::matches_meta_path(meta,&relative))
                                    ||plan.audit_unused()&&dq_analyze::captured_registry_check_selection::matches_meta_path(dq_analyze::allow_annotation_policy::metadata(),&relative)
                                    ||!plan.source_only()&&dq_analyze::captured_registry_check_selection::matches_model_declaration_path(&relative)
                            }))
                            && !doc_configuration.as_ref().is_some_and(|config|
                                path.strip_prefix(&contract.root).is_ok_and(|relative| {
                                    facets.applies_doc_exemption(relative) && config.excludes(&relative.to_string_lossy().replace('\\',"/"))
                                })) =>
                        {
                            if !files.contains(&path) {
                                metadata =
                                    metadata.checked_add(512 + path.capacity() * 4).ok_or_else(
                                        || io::Error::other("discovery source metadata overflow"),
                                    )?;
                                fund_metadata(metadata)?;check(inputs, metadata)?;
                                files.insert(path);
                            }
                        }
                        Kind::File | Kind::Symlink | Kind::Other => {}
                    }
                }
            }
        }
    }
    fund_metadata(metadata)?;check(inputs, metadata)?;
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
        fund_metadata(metadata)?;check(inputs,metadata)?;let mut result=Vec::new();result.try_reserve_exact(rows.len()).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;
        if result.capacity()>capacity{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"check_grep actual name capacity exceeds admitted overlap"))}
        result.extend(rows);Ok(result)
    };
    let check_grep=if selection.observes_check_grep(){Some(CheckGrepNames{dmes:names_vec(dmes)?,jsx:names_vec(jsx)?})}else{None};
    Ok(DiscoveryReceipt {
        issuer: inputs.policy_discovery_issuer(),
        selection,
        contract,
        facts,
        files,check_grep,doc_configuration,registered_check,
    })
}

#[cfg(test)]
mod discovery_facet_tests {
    use super::{DiscoveryFacets, DiscoverySelection, Path};

    #[test]
    fn original_selectors_keep_their_distinct_discovery_obligations() {
        use DiscoverySelection::*;
        let none = DiscoveryFacets::default();
        let docs = DiscoveryFacets { productive_docs: true, ..none };
        let ui = DiscoveryFacets { visible_ui: true, ..none };
        for (selection, expected) in [
            (RecursiveDmNoChildLinksV1, none),
            (MapEditsJoinedDmNoLinksV1, DiscoveryFacets { map_root_no_follow: true, ..none }),
            (CheckGrepDmAndRawNoChildLinksV1, none),
            (DocSnippetsCodeAndMarkdownV1, none),
            (DocSnippetsDemandV2, docs),
            (DocSnippetsJoinedAllowV1, DiscoveryFacets { docs_share_complete_dm: true, ..docs }),
            (OwnershipCodeDmV2, none),
            (UiActionsVisibleRootsV1, ui),
            (UiActionsJoinedAllowV1, DiscoveryFacets { ui_shares_complete_dm: true, ..ui }),
            (DocUiJoinedAllowV1, DiscoveryFacets {
                productive_docs: true,
                docs_share_complete_dm: true,
                ui_shares_complete_dm: true,
                ..ui
            }),
        ] {
            let facets = selection.facets();
            assert_eq!(facets, expected);
            assert!(facets.follows_requested_root(Path::new("root/code")));
            assert_eq!(facets.follows_requested_root(Path::new("root/maps")), !expected.map_root_no_follow);
            assert_eq!(facets.applies_doc_exemption(Path::new("code/exempt.dm")),
                expected.productive_docs && !expected.docs_share_complete_dm);
            assert_eq!(facets.applies_doc_exemption(Path::new("doc/rewrite/exempt.md")),
                expected.productive_docs);
        }
    }
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
 discover_productive_doc_domains(inputs,contract,configuration,&["code","doc/rewrite"],DiscoverySelection::DocSnippetsDemandV2)
}

/// Both discovery claims come from one typed traversal and recorder.
/// The Docs configuration cannot narrow the independent complete DM domain.
pub(crate) fn discover_doc_snippets_joined<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,configuration:&Path)->io::Result<(DiscoveryReceipt,Option<dm_resources::SharedBytes>)>{
 discover_productive_doc_domains(inputs,contract,configuration,&["code","doc/rewrite","maps"],DiscoverySelection::DocSnippetsJoinedAllowV1)
}

pub(crate) fn discover_doc_ui_joined<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,configuration:&Path)->io::Result<(DiscoveryReceipt,Option<dm_resources::SharedBytes>)>{
 discover_productive_doc_domains(inputs,contract,configuration,&["code","doc/rewrite","maps","tgui/packages/tgui/interfaces"],DiscoverySelection::DocUiJoinedAllowV1)
}

pub(crate) fn discover_authored_doc_ui<P: SnapshotProvider>(
    inputs: &RecordingInputs<P>, contract: DiscoveryContract, configuration: &Path,
    questions: &[crate::policy_request::WorkspaceAuxiliaryQuestion],
) -> io::Result<DiscoveryReceipt> {
    use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
    let roots = Q::authored_doc_ui_roots(questions)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "authored mixed discovery requires its exact private question roster"))?;
    let selection = if Q::is_private_grep_domain(questions) {
        DiscoverySelection::AuthoredCheckGrepV1
    } else if Q::is_extended_authored_doc_ui(questions) {
        DiscoverySelection::AuthoredDocUiExtendedV1
    } else {
        DiscoverySelection::AuthoredDocUiJoinedV1
    };
    discover_productive_doc_domains(inputs, contract, configuration, roots, selection).map(|(receipt, _)| receipt)
}

pub(crate) fn discover_full_registry_from_derived<P: SnapshotProvider>(
    inputs: &RecordingInputs<P>, contract: DiscoveryContract, configuration: &Path,
    config: &Arc<dq_analyze::captured_raw_file::Config>,
    budget: &Arc<dq_analyze::captured_generator_budget::Budget>,
    lender: &mut dyn crate::input_snapshot::RecordedPolicySourceLender,
) -> io::Result<DiscoveryReceipt> {
    use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
    let roots = Q::authored_doc_ui_roots(Q::PRIVATE_FULL_REGISTRY)
        .ok_or_else(|| io::Error::other("full registry discovery role absent"))?;
    if !contract.root.is_absolute() || contract.recursive_roots.len() != roots.len()
        || contract.recursive_roots.iter().zip(roots).any(|(path, root)|
            path.strip_prefix(&contract.root).ok() != Some(Path::new(root))) {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "full registry requires its exact joined discovery roots"));
    }
    let path = canonical_path(configuration);
    let observation = inputs.recorded_policy_file_observation(&path)?;
    let scope_bound=config.retained_scope_bound().unwrap_or_else(||config.budget_charge());
    discover_selected_lent(inputs, contract, DiscoverySelection::AuthoredCheckGrepV1,
        Some(DocConfiguration { path, observation, value: Arc::clone(config), scope_bound, scope_prepaid: true }), Some((budget, lender)))
}

fn discover_productive_doc_domains<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,configuration:&Path,expected:&[&str],selection:DiscoverySelection)->io::Result<(DiscoveryReceipt,Option<dm_resources::SharedBytes>)>{
 let root=&contract.root;if !root.is_absolute()||contract.recursive_roots.len()!=expected.len()||expected.iter().any(|name|!contract.recursive_roots.contains(&root.join(name))){return Err(io::Error::new(io::ErrorKind::InvalidInput,"productive Doc requires its exact source roots"))}
 let path=canonical_path(configuration);if !path.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual Doc configuration must be absolute"))}
 let bytes=inputs.read_policy_candidate(&path,64*1024*1024)?;let peak=bytes.as_ref().map_or(Some(1024),|bytes|bytes.capacity().checked_mul(64).and_then(|n|n.checked_add(8192+path.capacity()*8))).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;if inputs.policy_discovery_metadata_charge()?.checked_add(peak).is_none_or(|n|n>64*1024*1024){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"Doc configuration exceeds existing metadata grant before interpretation"))}
 let config=Arc::new(dq_analyze::captured_raw_file::Config::capture(bytes.as_ref().map_or(dq_analyze::captured_raw_policy::Configuration::ProvenMissing,|bytes|dq_analyze::captured_raw_policy::Configuration::Captured(bytes.as_slice()))).map_err(io::Error::other)?);
 let observation=inputs.recorded_policy_file_observation(&path)?;
 let scope_bound=config.budget_charge();
 let receipt=discover_selected_using(inputs,contract,selection,Some(DocConfiguration{path,observation,value:config,scope_bound,scope_prepaid:false}))?;
 if expected.iter().any(|name|!receipt.contract.recursive_roots.contains(&receipt.contract.root.join(name))){return Err(io::Error::new(io::ErrorKind::InvalidInput,"productive Doc root alias changes report namespace"))}Ok((receipt,bytes))
}

/// Request-local conditional Original producer selection. It owns no source
/// payload/model and never authorizes a compiler/checker question.
pub(crate) struct EnginePreflight{
 question:crate::policy_request::WorkspaceAuxiliaryQuestion,discovery:Arc<DiscoveryReceipt>,configuration:PathBuf,bytes:Option<dm_resources::SharedBytes>,config:Arc<dq_analyze::captured_raw_file::Config>,facts:InputSnapshot,selection:dq_analyze::captured_engine_layering_pages::Selection,charge:usize,
}
pub(crate) struct EngineNoModelProof{preflight:EnginePreflight}
impl EnginePreflight{
 pub(crate) fn question(&self)->crate::policy_request::WorkspaceAuxiliaryQuestion{self.question}
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
 let question=crate::policy_request::WorkspaceAuxiliaryQuestion::exclusive_layering(intent.workspace_auxiliary()).ok_or_else(||bad("exclusive actual layering question absent"))?;
 let layer=question.layering().expect("exclusive layering question");
 if intent.analysis_context()!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)||!intent.files().is_empty()||!intent.search_folders().is_empty()||!intent.workspace_generators().is_empty(){return Err(bad("conditional engine requires its exclusive actual Original purpose"))}
 let workspace=intent.workspace().ok_or_else(||bad("engine selection workspace absent"))?;if workspace.recursive_roots.as_slice()!=[workspace.root.join("code")]{return Err(bad("engine preflight requires exactly original CODE_DM root"))}
 let configuration=canonical_path(&workspace.configuration);let bytes=inputs.read_policy_candidate(&configuration,64*1024*1024)?;let peak=bytes.as_ref().map_or(Some(8192),|b|b.capacity().checked_mul(64).and_then(|n|n.checked_add(configuration.capacity()*8+8192))).ok_or(io::ErrorKind::OutOfMemory)?;
 let prior=inputs.policy_discovery_metadata_charge()?;if prior.checked_add(peak).is_none_or(|n|n>64*1024*1024){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"engine configuration cannot fit actual metadata family before interpretation"))}
 let config=Arc::new(dq_analyze::captured_raw_file::Config::capture(bytes.as_ref().map_or(dq_analyze::captured_raw_policy::Configuration::ProvenMissing,|b|dq_analyze::captured_raw_policy::Configuration::Captured(b.as_slice()))).map_err(io::Error::other)?);
 let discovery=Arc::new(discover_ownership_code(inputs,DiscoveryContract{root:workspace.root.clone(),recursive_roots:workspace.recursive_roots.clone()})?);discovery.validate_recording(inputs)?;if discovery.contract.root!=workspace.root||discovery.contract.recursive_roots!=workspace.recursive_roots{return Err(bad("engine authored report namespace differs from actual discovery"))}
 let retained=discovery.retained_charge()?.checked_add(config.budget_charge()).and_then(|n|n.checked_add(bytes.as_ref().map_or(0,dm_resources::SharedBytes::capacity))).and_then(|n|n.checked_add(configuration.capacity()*8+4096)).ok_or(io::ErrorKind::OutOfMemory)?;let already=inputs.policy_discovery_metadata_charge()?.checked_add(retained).ok_or(io::ErrorKind::OutOfMemory)?;let limit=(64usize*1024*1024).checked_sub(already).ok_or(io::ErrorKind::OutOfMemory)?;let budget=Budget::new(limit).map_err(quota)?;
 struct Names<'a>{discovery:&'a DiscoveryReceipt,budget:&'a Arc<Budget>}
 impl engine::PathPages for Names<'_>{fn for_each_path(&self,visit:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<bool,Failure>{for path in self.discovery.files(){crate::daemon::control::checkpoint()?;let relative=path.strip_prefix(&self.discovery.contract.root).map_err(|_|Failure::from("engine path escapes discovery owner"))?;let width=relative.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(512)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget.charge(width).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let relative=relative.to_string_lossy().replace('\\',"/");if !dq_analyze::captured_raw_file::is_code_dm(&relative){return Err("engine discovery selected a non-CODE_DM path".into())}visit(&relative)?;}Ok(true)}}
 let selection=engine::preflight_for(layer,&Names{discovery:&discovery,budget:&budget},&config,&budget,&crate::daemon::control::checkpoint).map_err(actual)?;budget.require().map_err(quota)?;let facts=inputs.policy_workspace_closure(&BTreeSet::from([configuration.clone()]),std::iter::empty())?;let charge=retained.checked_add(budget.used()).and_then(|n|n.checked_add(facts.policy_closure_charge_with(&mut BTreeSet::new()).ok()?)).ok_or(io::ErrorKind::OutOfMemory)?;if charge>64*1024*1024{return Err(io::ErrorKind::OutOfMemory.into())}let out=EnginePreflight{question,discovery,configuration,bytes,config,facts,selection,charge};out.require(inputs)?;Ok(out)
}

pub(crate) fn discover_ownership_code_admitted<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,budget:&Arc<dq_analyze::captured_generator_budget::Budget>,lender:&mut dyn crate::input_snapshot::RecordedPolicySourceLender)->io::Result<DiscoveryReceipt>{
 if contract.recursive_roots.as_slice()!=[contract.root.join("code")]{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Ownership source purpose requires exact CODE_DM"))}
 discover_selected_lent(inputs,contract,DiscoverySelection::OwnershipCodeDmV2,None,Some((budget,lender)))
}

/// Handler's discovery stages private traversal and sort allocations in a
/// refundable child. Real recorder directory funding still uses the root
/// lender, whose reservation window cannot be opened from a child.
pub(crate) fn discover_handlers_code_admitted<P:SnapshotProvider>(
 inputs:&RecordingInputs<P>,contract:DiscoveryContract,
 budget:&Arc<dq_analyze::captured_generator_budget::Budget>,
 scratch:&Arc<dq_analyze::captured_generator_budget::Budget>,
 lender:&mut dyn crate::input_snapshot::RecordedPolicySourceLender,
)->io::Result<DiscoveryReceipt>{
 if contract.recursive_roots.as_slice()!=[contract.root.join("code")]{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Handler source purpose requires exact CODE_DM"))}
 discover_selected_lent_scoped(inputs,contract,DiscoverySelection::OwnershipCodeDmV2,None,Some((budget,lender)),Some(scratch))
}

#[cfg(test)]
#[test]
fn joined_doc_discovery_proves_each_domain_without_admitting_exempt_markdown() {
    let root=crate::test_scratch::dir("joined-doc-discovery");
    let configuration=root.join("tools/ci/lint_scopes.toml");
    for (relative,bytes) in [
        ("tools/ci/lint_scopes.toml","[lint.doc_snippets]\nexempt_files=['code/skip.dm','doc/rewrite/skip.md']\nexempt_prefixes=['code/sub/']\n"),
        ("code/live.dm","/proc/example()\n"),
        ("code/skip.dm","// ALLOW(scheduler): aggregate audit still reads this ordinary source\n"),
        ("code/sub/keep.dm","/proc/other()\n"),
        ("maps/allow.dm","// ALLOW(scheduler): aggregate audit still reads ordinary map source\n"),
        ("doc/rewrite/live.md","visible Markdown\n"),
        ("doc/rewrite/skip.md","not selected by Docs\n"),
        ("doc/rewrite/nested/unselected.md","not in the shallow original Docs domain\n"),
    ] {
        let path=root.join(relative);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path,bytes).unwrap();
    }
    let inputs=RecordingInputs::new(crate::input_snapshot::FileSystemInputs,0);
    let contract=DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("doc/rewrite"),root.join("maps")]};
    let (joined,_)=discover_doc_snippets_joined(&inputs,contract.clone(),&configuration).unwrap();
    joined.validate_recording(&inputs).unwrap();
    let foreign=RecordingInputs::new(crate::input_snapshot::FileSystemInputs,0);
    assert!(joined.validate_recording(&foreign).is_err());
    assert!(joined.covers_doc_snippets(&mut |_|Ok(())).unwrap());
    assert!(joined.covers_code_dm(&mut |_|Ok(())).unwrap());
    assert!(joined.covers_dm_roots(&[("maps","dm")],false,&mut |_|Ok(())).unwrap());
    assert!(!joined.covers_dm_roots(&[("doc/rewrite","dm")],false,&mut |_|Ok(())).unwrap());
    for required in ["code/live.dm","code/skip.dm","code/sub/keep.dm","maps/allow.dm","doc/rewrite/live.md"] {
        assert!(joined.files().contains(&root.join(required)),"{required}");
    }
    for excluded in ["doc/rewrite/skip.md","doc/rewrite/nested/unselected.md"] {
        assert!(!joined.files().contains(&root.join(excluded)),"{excluded}");
    }
    assert!(joined.productive_doc_configuration(&configuration).unwrap().unwrap()
        .policy_path_exempt("doc_snippets","","code/skip.dm"));
    let partial=DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("doc/rewrite")]};
    assert!(discover_doc_snippets_joined(&inputs,partial,&configuration).is_err());
}

/// The only dynamic discovery issuer consumes the genuine registered plan.
/// It runs the existing typed directory kernel; no second walker or text scan.
pub(crate) fn discover_registered_source_check<P:SnapshotProvider>(inputs:&RecordingInputs<P>,contract:DiscoveryContract,configuration:&Path,plan:Arc<crate::runner_host::NativeCheckSelection>)->io::Result<(DiscoveryReceipt,Option<dm_resources::SharedBytes>)>{
    let directories=plan.roots().iter().enumerate().filter(|(index,(root,_))|!plan.roots()[..*index].iter().any(|(prior,_)|prior==root)).count();
    if contract.recursive_roots.len()!=directories||plan.roots().iter().any(|(root,_)|!contract.recursive_roots.iter().any(|path|path.strip_prefix(&contract.root).ok()==Some(Path::new(root)))){
        return Err(io::Error::new(io::ErrorKind::InvalidInput,"source selection requires all actual registered roots"))
    }
    let path=canonical_path(configuration);if !path.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected CHECK configuration must be actual absolute input"))}
    let bytes=inputs.read_policy_candidate(&path,64*1024*1024)?;
    let peak=bytes.as_ref().map_or(Some(1024),|bytes|bytes.capacity().checked_mul(64).and_then(|n|n.checked_add(8192+path.capacity()*8))).ok_or(io::ErrorKind::OutOfMemory)?;
    if inputs.policy_discovery_metadata_charge()?.checked_add(peak).is_none_or(|n|n>64*1024*1024){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"selected CHECK configuration exceeds existing discovery metadata grant"))}
    let value=Arc::new(dq_analyze::captured_raw_file::Config::capture(bytes.as_ref().map_or(dq_analyze::captured_raw_policy::Configuration::ProvenMissing,|bytes|dq_analyze::captured_raw_policy::Configuration::Captured(bytes.as_slice()))).map_err(io::Error::other)?);
    let observation=inputs.recorded_policy_file_observation(&path)?;let scope_bound=value.budget_charge();
    let config=DocConfiguration{path,observation,value,scope_bound,scope_prepaid:false};
    let receipt=discover_selected_lent_scoped_plan(inputs,contract,DiscoverySelection::RegisteredSourceCheckV1,Some(config),None,None,Some(plan))?;
    Ok((receipt,bytes))
}

#[cfg(test)]mod registered_selected_namespace_controls{
 use super::*;
 #[test]fn actual_selected_index_namespace_is_not_a_whole_unused_audit_or_productive_tag(){
  let root=std::fs::canonicalize(crate::test_scratch::dir("selected-index-vs-audit")).unwrap();for directory in ["code","maps"]{std::fs::create_dir(root.join(directory)).unwrap();std::fs::write(root.join(directory).join("proof.dm"),"/obj/proof\n").unwrap();}
  let host=crate::runner_host::BuildHost::default();let format=crate::runner_host::FullRegistryCheckOptions{raw:true,unused:false,..Default::default()};let work=host.source_arena_work();
  let plan=crate::runner_host::prepare_native_check_selection(&["tracked".into(),"sem/handlers".into()],format,work).unwrap();assert!(plan.model_handler_join()&&!plan.audit_unused());let inputs=RecordingInputs::new(crate::input_snapshot::FileSystemInputs,0);let contract=DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")]};
  let(receipt,_)=discover_registered_source_check(&inputs,contract.clone(),&root.join("absent-scopes.toml"),Arc::clone(&plan)).unwrap();receipt.validate_recording(&inputs).unwrap();assert!(receipt.covers_registered_index_roots(&plan,dq_analyze::tree::CODE_MAPS_DM.roots,false,&mut |_|Ok(())).unwrap());assert!(!receipt.covers_registered_audit(&plan,&mut |_|panic!("unrequested audit cannot borrow namespace readiness")).unwrap());
  let foreign=crate::runner_host::prepare_native_check_selection(&["tracked".into(),"sem/handlers".into()],format,work).unwrap();assert_eq!(receipt.covers_registered_index_roots(&foreign,dq_analyze::tree::CODE_MAPS_DM.roots,false,&mut |_|Ok(())).unwrap_err().kind(),io::ErrorKind::InvalidInput);
  let mut polls=0;let actual=receipt.covers_registered_index_roots(&plan,dq_analyze::tree::CODE_MAPS_DM.roots,false,&mut |_|{polls+=1;Err(io::Error::from_raw_os_error(1450))}).unwrap_err();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(polls,1);
  let productive=crate::runner_host::prepare_native_check_selection(&["scheduler".into()],format,work).unwrap();assert!(productive.source_only());let ordinary=RecordingInputs::new(crate::input_snapshot::FileSystemInputs,1);let(pruned,_)=discover_registered_source_check(&ordinary,contract,&root.join("absent-scopes.toml"),Arc::clone(&productive)).unwrap();pruned.validate_recording(&ordinary).unwrap();assert!(!pruned.covers_registered_index_roots(&productive,dq_analyze::tree::CODE_MAPS_DM.roots,false,&mut |_|Ok(())).unwrap(),"an actual productive receipt alone cannot certify a missing unselected-index obligation");
 }
}
