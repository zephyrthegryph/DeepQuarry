//! WORKING private pre-final utility loan. Not a model/source/completion issuer.
//! Install as an input_snapshot child so existing bounded recorder kernels stay private.
use super::*;
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};

/// Raw physical bytes: required readers must preserve Err and distinguish None
/// (actual recorded NotFound) from invalid UTF8. Decoding is the caller's choice.
/// Payload drops before its SAME raw-ledger allocation credit.
pub(crate) struct UtilityBytes{bytes:Vec<u8>,stamp:Stamp,content:u128,_credit:SourceArenaCredit}
impl UtilityBytes{
 pub(crate) fn bytes(&self)->&[u8]{&self.bytes}
 /// Provider-issued physical identity/digest from this exact recorded read.
 /// The writer must still validate the final moved Inputs/current operation.
 pub(crate) fn stamp(&self)->&Stamp{&self.stamp}
 pub(crate) fn content(&self)->u128{self.content}
}

pub(crate) trait UtilityPhysicalInputs{
 /// Only already captured DATA may be processed inside this held-work loan.
 /// Read/read_optional/discovery must run outside it: they enter the SAME ledger.
 fn with_work(&mut self,visit:&mut dyn FnMut(&dyn SourceArenaWork)->io::Result<()>)->io::Result<()>;
 fn read(&mut self,path:&Path,limit:usize)->io::Result<Option<UtilityBytes>>;
 /// Actual typed observations for the fixed codemod output's parent chain.
 /// Returns only its FIRST missing direct child; the coordinator must retire
 /// this attempt and reprepare after EACH successful directory mutation.
 fn capture_codemod_parent(&mut self,target:&crate::runner_host::codemod_targets::CapturedCodemodTarget<'_>)->io::Result<Option<CapturedDirectoryTarget>>;

 /// Optional DATA read: actual OS NoText is recorded without demanding a parent listing.
 fn read_optional(&mut self,path:&Path,limit:usize)->io::Result<Option<UtilityBytes>>;
 fn with_base_vars_roster(&mut self,root:&Path,visit:&mut dyn FnMut(&crate::runner_host::workspace_discovery::DiscoveryReceipt,&dyn SourceArenaWork)->io::Result<()>)->io::Result<()>;
 fn with_dm_roster(&mut self,root:&Path,visit:&mut dyn FnMut(&crate::runner_host::workspace_discovery::DiscoveryReceipt,&dyn SourceArenaWork)->io::Result<()>)->io::Result<()>;
}

/// The outer coordinator loans this only BEFORE Pending::capture finalizes the
/// actual recorder epoch. The metadata lender is already under its real gate;
/// reserve payload only through its existing held-work callback, never QueryDb.
pub(crate) struct UtilityPhysicalLoan<'a,P:SnapshotProvider>{
 pub(crate) recording:&'a RecordingInputs<P>,
 pub(crate) queries:&'a crate::query_db::QueryDb,
 pub(crate) budget:&'a std::sync::Arc<dq_analyze::captured_generator_budget::Budget>,
 pub(crate) lender:&'a mut dyn RecordedPolicySourceLender,
}
impl<P:SnapshotProvider> UtilityPhysicalInputs for UtilityPhysicalLoan<'_,P>{
 fn capture_codemod_parent(&mut self,target:&crate::runner_host::codemod_targets::CapturedCodemodTarget<'_>)->io::Result<Option<CapturedDirectoryTarget>>{
  target.stamp()?; // target must own this attempt's actual output read first
  let root=target.root();let relative=Path::new(target.relative());
  if !root.is_absolute()||relative.components().any(|c|!matches!(c,std::path::Component::Normal(_))){return Err(invalid("codemod parent capture needs ordinary issued output"))}
  let mut full=None;
  self.lender.with_held_source_work(self.queries,&mut|work|{full=Some(dm_preprocess::regions::joined_path_using(root,target.relative(),work)?);Ok(())})?;
  let full=full.ok_or_else(||invalid("codemod parent path work loan omitted"))?;
  let parent=full.path().parent().ok_or_else(||invalid("codemod output has no parent"))?;
  if !parent.starts_with(root){return Err(invalid("codemod parent escapes root"))}
  // All prefixes borrow the one actually paid joined path. Preserve the
  // original root-to-leaf observation/first-IO order WITHOUT a cloned cursor
  // or a new path roster. Fixed registry outputs have only a few components.
  let depth=parent.strip_prefix(root).map_err(|_|invalid("codemod parent escapes root"))?.components().count();
  for skip in (0..=depth).rev(){
   let cursor=parent.ancestors().nth(skip).ok_or_else(||invalid("codemod parent ancestor depth changed"))?;
   if !cursor.starts_with(root){return Err(invalid("codemod parent ancestor escapes root"))}
   let known={self.recording.snapshot.lock().map_err(|_|invalid("utility recorder poisoned"))?.policy_directories.contains_key(cursor)};
   if !known{self.recording.capture_policy_directory_lent(cursor,false,0,self.budget,self.lender)?;}
  }
  let mut issued=None;
  let resource=self.lender.with_held_source_work(self.queries,&mut|work|{
   let facts=self.recording.snapshot.lock().map_err(|_|invalid("utility recorder poisoned"))?;
   issued=Some(directory_target_from_recorded(&facts,root,parent,work));
   if issued.as_ref().is_some_and(Result::is_err){Err(io::ErrorKind::Other.into())}else{Ok(())}
  });
  match issued{Some(Err(first))=>Err(first),Some(Ok(target))=>resource.map(|()|target),None=>resource.and_then(|()|Err(invalid("codemod directory work loan was not visited")))}
 }

 fn with_base_vars_roster(&mut self,root:&Path,visit:&mut dyn FnMut(&crate::runner_host::workspace_discovery::DiscoveryReceipt,&dyn SourceArenaWork)->io::Result<()>)->io::Result<()>{let actual=crate::runner_host::workspace_discovery::discover_utility_base_vars_admitted(self.recording,root,self.budget,self.lender)?;self.lender.with_held_source_work(self.queries,&mut|work|visit(&actual,work))}

 fn with_work(&mut self,visit:&mut dyn FnMut(&dyn SourceArenaWork)->io::Result<()>)->io::Result<()>{self.lender.with_held_source_work(self.queries,visit)}
 fn with_dm_roster(&mut self,root:&Path,visit:&mut dyn FnMut(&crate::runner_host::workspace_discovery::DiscoveryReceipt,&dyn SourceArenaWork)->io::Result<()>)->io::Result<()>{
  // Discovery completes without an active held-work borrow; then only the
  // immutable receipt is lent with SAME paid metadata work. No nested gate.
  let actual=crate::runner_host::workspace_discovery::discover_utility_dm_admitted(self.recording,root,self.queries,self.budget,self.lender)?;
  self.lender.with_held_source_work(self.queries,&mut |work|visit(&actual,work))
 }

 fn read_optional(&mut self,path:&Path,limit:usize)->io::Result<Option<UtilityBytes>>{self.read_bytes(path,limit,true)}
 fn read(&mut self,path:&Path,limit:usize)->io::Result<Option<UtilityBytes>>{self.read_bytes(path,limit,false)}
}
impl<P:SnapshotProvider> UtilityPhysicalLoan<'_,P>{
 fn read_bytes(&mut self,path:&Path,limit:usize,optional:bool)->io::Result<Option<UtilityBytes>>{
  // A required physical-byte read first owns its actual typed parent listing
  // through the existing lender. Original raw opens do not populate legacy
  // search-folder rows, so requiring .folders here would reject real inputs.
  if !path.is_absolute(){return Err(invalid("utility bytes require an actual absolute captured path"))}
  // SAME lexical canonical fold, paid by the actual held-work loan before
  // creating any path buffer; no generic width-based scratch allowance.
  let mut canonical=None;
  self.lender.with_held_source_work(self.queries,&mut|work|{canonical=Some(dm_preprocess::regions::canonical_path_using(path,work)?);Ok(())})?;
  let canonical=canonical.ok_or_else(||invalid("utility canonical path work omitted"))?;let path=canonical.path();
  if !optional{
  let parent=path.parent().ok_or_else(||invalid("utility byte path has no parent"))?;
  let known={let facts=self.recording.snapshot.lock().map_err(|_|invalid("utility recorder poisoned"))?;facts.policy_directories.contains_key(parent)};
  if !known{self.recording.capture_policy_directory_lent(parent,false,0,self.budget,self.lender)?;}
  }
  let oom=|m:String|io::Error::new(io::ErrorKind::OutOfMemory,m);
  // The existing recorder owns file facts independently of the returned byte
  // buffer. Publish/settle its SAME metadata row even when the actual read fails.
  let metadata=||self.recording.snapshot.lock().map_err(|_|invalid("utility recorder poisoned"))?.policy_closure_charge();
  let before=metadata()?;let owner=self.recording.policy_metadata_owner(Some(self.budget))?;
  self.lender.prepare_directory_metadata(&owner,before)?;
  let fact_bound=path.as_os_str().len().checked_mul(16).and_then(|n|n.checked_add(512+std::mem::size_of::<FileInput>())).ok_or(io::ErrorKind::OutOfMemory)?;
  let window=dq_analyze::captured_generator_budget::Budget::reserve_window(self.budget,fact_bound).map_err(oom)?;
  self.lender.directory_window_started(&owner,before.checked_add(window.capacity()).ok_or(io::ErrorKind::OutOfMemory)?)?;
  let mut pending=None;
  let resource=self.lender.with_held_source_work(self.queries,&mut |work|{
   let mut credit=None;
   let mut fund=|capacity|{
    if credit.is_some(){return Err(invalid("utility provider repeated byte allocation admission"))}
    credit=Some(work.reserve(capacity)?);Ok(())
   };
   let read=if optional{self.recording.read_optional_callback_payload(path,limit,work,&mut fund)}else{self.recording.read_policy_payload_admitted(path,limit,&mut fund)};
   pending=Some(match read{
    Err(first)=>Err(first),
    Ok(None)=>Ok(None),
    Ok(Some(bytes))=>match credit.take(){
     Some(credit) if bytes.capacity()<=credit.reserved_bytes()=>{
      // Both required and Optional-positive kernels committed this provider
      // fact before returning bytes. Borrow its scalar identity, never stat a
      // second path or manufacture a write target from decoded text.
      let captured=(||{
       let facts=self.recording.snapshot.lock().map_err(|_|invalid("utility recorder poisoned"))?;
       let fact=facts.files.get(path).ok_or_else(||invalid("utility physical payload omitted its actual recorded file identity"))?;
       if fact.stamp.size!=bytes.len() as u64{return Err(invalid("utility physical identity length differs from its payload"))}
       Ok((fact.stamp.clone(),fact.content))
      })();
      captured.map(|(stamp,content)|Some(UtilityBytes{bytes,stamp,content,_credit:credit}))
     },
     _=>Err(invalid("utility physical bytes lack actual preallocation credit")),
    },
   });
   if pending.as_ref().is_some_and(Result::is_err){Err(io::ErrorKind::Other.into())}else{Ok(())}
  });
  let pending=match pending{Some(Err(first))=>Err(first),Some(Ok(bytes))=>resource.map(|()|bytes),None=>resource.and_then(|()|Err(invalid("utility held resource loan was not visited")))};
  let after=match metadata(){Ok(n)=>n,Err(later)=>{window.keep();return match pending{Err(first)=>Err(first),Ok(_)=>Err(later)}}};
  if let Err(later)=self.lender.directory_metadata_settled(&owner,after){window.keep();return match pending{Err(first)=>Err(first),Ok(_)=>Err(later)}}
  let settled=self.lender.settle_directory_window(window,after.saturating_sub(before)).map_err(oom);
  match pending{Err(first)=>Err(first),Ok(bytes)=>{settled?;Ok(bytes)}}
 }
}

/// Issued only from the actual fixed-output capture's typed directory ledger.
/// A path or command JSON cannot construct this physical mutation target.
pub(crate) struct CapturedDirectoryTarget{
 root:PathBuf,path:PathBuf,parent_identity:u128,_credit:SourceArenaCredit,
}
impl CapturedDirectoryTarget{
 pub(crate) fn root(&self)->&Path{&self.root}
 pub(crate) fn path(&self)->&Path{&self.path}
 pub(crate) fn parent_identity(&self)->u128{self.parent_identity}
}
fn directory_target_from_recorded(facts:&InputSnapshot,root:&Path,parent:&Path,work:&dyn SourceArenaWork)->io::Result<Option<CapturedDirectoryTarget>>{
 work.checkpoint()?;facts.check_structure()?;
 let relative=parent.strip_prefix(root).map_err(|_|invalid("captured directory parent outside root"))?;
 if !root.is_absolute()||relative.components().any(|c|!matches!(c,std::path::Component::Normal(_))){return Err(invalid("captured directory parent not ordinary"))}
 let root_key=dm_preprocess::regions::canonical_path_using(root,work)?;let parent_key=dm_preprocess::regions::canonical_path_using(parent,work)?;
 if !matches!(facts.policy_directories.get(root_key.path()).map(|r|&r.listing),Some(PolicyDirectoryListing::Present(_))){return Err(invalid("captured root is not a present directory"))}
 let mut first_missing=None;
 for cursor in parent_key.path().ancestors(){
  if !cursor.starts_with(root_key.path()){break}
  work.checkpoint()?;
  match facts.policy_directories.get(cursor).map(|r|&r.listing){
   Some(PolicyDirectoryListing::Present(_))=>{},
   Some(PolicyDirectoryListing::Missing)=>first_missing=Some(cursor),
   Some(PolicyDirectoryListing::NotDirectory)=>return Err(invalid("captured output ancestor is not directory")),
   None=>return Err(invalid("codemod directory chain omits actual typed observation")),
  }
  if cursor==root_key.path(){break}
 }
 let Some(cursor)=first_missing else{return Ok(None)};
 let parent=cursor.parent().ok_or_else(||invalid("captured missing directory has no parent"))?;
 let leaf=cursor.file_name().and_then(|s|s.to_str()).ok_or_else(||invalid("captured directory leaf is not UTF8"))?;
 let Some(PolicyDirectoryListing::Present(entries))=facts.policy_directories.get(parent).map(|r|&r.listing)else{return Err(invalid("missing directory lacks actual present parent listing"))};
 if entries.iter().any(|e|e.name==leaf){return Err(invalid("negative directory contradicts captured parent"))}
 let _guard_credit=work.reserve(crate::frozen_inputs::generation_publication_guard_charge(parent,root_key.path())?)?;
 let parent_identity=crate::frozen_inputs::generation_directory_identity(parent,root_key.path())?;
 let mut credit=work.reserve(0)?;let actual_root=dm_preprocess::regions::copy_path_into_credit(root_key.path(),work,&mut credit)?;let path=dm_preprocess::regions::copy_path_into_credit(cursor,work,&mut credit)?;
 Ok(Some(CapturedDirectoryTarget{root:actual_root,path,parent_identity,_credit:credit}))
}

#[cfg(test)]mod directory_transition_controls{
 use super::*;
 use crate::native_author_fix_transaction::{commit_directory,commit_directory_using,DirectoryEvent};
 fn observed(root:&Path,parent:&Path)->InputSnapshot{
  let actual=FileSystemInputs;let mut facts=InputSnapshot::new(0);let mut cursor=root.to_owned();
  for part in std::iter::once(None).chain(parent.strip_prefix(root).unwrap().components().map(Some)){
   if let Some(part)=part{cursor.push(part.as_os_str())}
   let listing=actual.policy_directory(&cursor,false,1024*1024).unwrap().expect("actual filesystem supports typed directory capture");
   facts.record_policy_directory(&cursor,false,listing).unwrap();facts.record_folder(&cursor,actual.list(&cursor).unwrap()).unwrap();
  }
  let source=root.join("proof.dm");let(stamp,bytes)=actual.read(&source).unwrap();facts.record_file(&source,stamp,&bytes).unwrap();
  facts.record_negative(&parent.join("revert.json")).unwrap();facts
 }
 fn fixture(label:&str)->(PathBuf,PathBuf,crate::query_db::QueryDb){
  let root=std::fs::canonicalize(crate::test_scratch::dir(label)).unwrap();std::fs::write(root.join("proof.dm"),b"/datum/proof\n").unwrap();
  let parent=root.join("data/codemod/own_set");(root,parent,crate::query_db::QueryDb::default())
 }
 #[test]fn codemod_directory_actual_negative_chain_reprepares_one_parent_at_a_time(){
  let(root,parent,work)=fixture("codemod-directory-three-steps");let mut before=observed(&root,&parent);let mut steps=0;
  while let Some(target)=directory_target_from_recorded(&before,&root,&parent,&work).unwrap(){
   let mut current=0;let transition=commit_directory(&target,&work,&mut||{current+=1;Ok(())}).unwrap().into_transition();assert_eq!(current,1);
   steps+=1;assert_eq!(transition.path().components().count(),root.components().count()+steps);
   let after=observed(&root,&parent);assert!(before.same_directory_step(&after,&transition,&work).unwrap());assert!(!after.same_directory_step(&before,&transition,&work).unwrap());
   assert!(!before.same_directory_step(&before,&transition,&work).unwrap());before=after;
  }
  assert_eq!(steps,3);assert!(parent.is_dir());assert!(!parent.join("revert.json").exists());assert_eq!(std::fs::read(root.join("proof.dm")).unwrap(),b"/datum/proof\n");
 }
 #[test]fn codemod_directory_refuses_uncaptured_foreign_and_outside_parent_without_mutation(){
  let(root,parent,work)=fixture("codemod-directory-foreign");let facts=observed(&root,&parent);
  assert!(directory_target_from_recorded(&InputSnapshot::new(0),&root,&parent,&work).is_err());
  let other=std::fs::canonicalize(crate::test_scratch::dir("codemod-directory-other-root")).unwrap();
  assert!(directory_target_from_recorded(&facts,&other,&parent,&work).is_err());
  assert!(directory_target_from_recorded(&facts,&root,&root.join("../outside"),&work).is_err());
  let mut incomplete=InputSnapshot::new(0);let listing=FileSystemInputs.policy_directory(&root,false,1024*1024).unwrap().unwrap();incomplete.record_policy_directory(&root,false,listing).unwrap();
  assert!(directory_target_from_recorded(&incomplete,&root,&parent,&work).is_err());assert!(!root.join("data").exists());
 }
 #[test]fn codemod_directory_preserves_first_currentness_io_and_cancel_before_actual_create(){
  let(root,parent,work)=fixture("codemod-directory-first-io");let facts=observed(&root,&parent);let target=directory_target_from_recorded(&facts,&root,&parent,&work).unwrap().unwrap();
  let error=commit_directory(&target,&work,&mut||Err(Box::new(io::Error::from_raw_os_error(1450)))).err().unwrap();assert!(!error.may_have_changed);assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert!(!target.path().exists());
  let error=commit_directory(&target,&work,&mut||Err(Box::new(io::Error::new(io::ErrorKind::Interrupted,"actual cancellation")))).err().unwrap();assert!(!error.may_have_changed);assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::Interrupted);assert!(!target.path().exists());
  let error=commit_directory_using(&target,&work,&mut||Ok(()),&mut|event|if matches!(event,DirectoryEvent::BeforeCreate){Err(io::Error::from_raw_os_error(5))}else{panic!("permission failure cannot continue after create")}).err().unwrap();assert!(error.may_have_changed);assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(5));assert!(!target.path().exists());
 }
 #[test]fn codemod_directory_partial_creation_keeps_actual_state_and_first_error_without_rollback(){
  let(root,parent,work)=fixture("codemod-directory-partial-truth");let before=observed(&root,&parent);let target=directory_target_from_recorded(&before,&root,&parent,&work).unwrap().unwrap();
  let first=commit_directory(&target,&work,&mut||Ok(())).unwrap().into_transition();let after=observed(&root,&parent);assert!(before.same_directory_step(&after,&first,&work).unwrap());
  let target=directory_target_from_recorded(&after,&root,&parent,&work).unwrap().unwrap();let mut events=0;
  let error=commit_directory_using(&target,&work,&mut||Ok(()),&mut|event|{if matches!(event,DirectoryEvent::AfterCreate){events+=1;Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}).err().unwrap();
  assert!(error.may_have_changed);assert_eq!(events,1);assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert!(root.join("data").is_dir());assert!(root.join("data/codemod").is_dir());assert!(!parent.exists());
  let partial=observed(&root,&parent);assert!(!before.same_directory_step(&partial,&first,&work).unwrap(),"first transition cannot swallow later partial creation");assert_eq!(std::fs::read(root.join("proof.dm")).unwrap(),b"/datum/proof\n");
 }
 #[test]fn codemod_directory_transition_refuses_foreign_source_sibling_and_new_child_changes(){
  let(root,parent,work)=fixture("codemod-directory-exact-ledger");let before=observed(&root,&parent);let target=directory_target_from_recorded(&before,&root,&parent,&work).unwrap().unwrap();let transition=commit_directory(&target,&work,&mut||Ok(())).unwrap().into_transition();
  std::fs::write(root.join("sibling.txt"),b"foreign").unwrap();assert!(!before.same_directory_step(&observed(&root,&parent),&transition,&work).unwrap());std::fs::remove_file(root.join("sibling.txt")).unwrap();
  std::fs::write(target.path().join("foreign"),b"foreign child").unwrap();assert!(!before.same_directory_step(&observed(&root,&parent),&transition,&work).unwrap());std::fs::remove_file(target.path().join("foreign")).unwrap();
  std::fs::write(root.join("proof.dm"),b"/datum/changed\n").unwrap();assert!(!before.same_directory_step(&observed(&root,&parent),&transition,&work).unwrap());
 }
 #[test]fn codemod_directory_existing_foreign_entry_never_becomes_our_transition(){
  let(root,parent,work)=fixture("codemod-directory-created-before-write");let before=observed(&root,&parent);let target=directory_target_from_recorded(&before,&root,&parent,&work).unwrap().unwrap();std::fs::create_dir(target.path()).unwrap();
  let error=commit_directory(&target,&work,&mut||Ok(())).err().unwrap();assert!(!error.may_have_changed);assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::AlreadyExists);assert!(target.path().is_dir());
 }
 #[cfg(any(windows,unix))]#[test]fn codemod_directory_rejects_linked_reparse_parent_and_preserves_external_files(){
  let(root,parent,work)=fixture("codemod-directory-linked-parent");std::fs::create_dir(root.join("data")).unwrap();let before=observed(&root,&parent);let target=directory_target_from_recorded(&before,&root,&parent,&work).unwrap().unwrap();
  let outside=std::fs::canonicalize(crate::test_scratch::dir("codemod-directory-external")).unwrap();std::fs::write(outside.join("untouched"),b"outside").unwrap();std::fs::rename(root.join("data"),root.join("original-data")).unwrap();
  #[cfg(windows)]std::os::windows::fs::symlink_dir(&outside,root.join("data")).expect("actual symlink privilege required by filesystem negative control");
  #[cfg(unix)]std::os::unix::fs::symlink(&outside,root.join("data")).unwrap();
  let error=commit_directory(&target,&work,&mut||Ok(())).err().unwrap();assert!(!error.may_have_changed);assert_eq!(std::fs::read(outside.join("untouched")).unwrap(),b"outside");assert!(!outside.join("codemod").exists());
 }

 #[test]fn codemod_directory_transition_requires_captured_parent_row_and_same_parent_identity(){
  let(root,parent,work)=fixture("codemod-directory-parent-proof");std::fs::create_dir(root.join("data")).unwrap();std::fs::create_dir(root.join("data/codemod")).unwrap();
  let mut before=observed(&root,&parent);let target=directory_target_from_recorded(&before,&root,&parent,&work).unwrap().unwrap();let transition=commit_directory(&target,&work,&mut||Ok(())).unwrap().into_transition();let mut after=observed(&root,&parent);
  assert!(before.same_directory_step(&after,&transition,&work).unwrap());
  // Fault-injection of an omitted observation must not widen the comparator.
  before.policy_directories.remove(&canonical_path(parent.parent().unwrap()));after.policy_directories.remove(&canonical_path(parent.parent().unwrap()));
  assert!(!before.same_directory_step(&after,&transition,&work).unwrap());
  let child_identity=crate::frozen_inputs::generation_directory_identity(&parent,&root).unwrap();
  std::fs::rename(root.join("data/codemod"),root.join("data/old-codemod")).unwrap();std::fs::create_dir(root.join("data/codemod")).unwrap();std::fs::rename(root.join("data/old-codemod/own_set"),&parent).unwrap();
  assert_eq!(crate::frozen_inputs::generation_directory_identity(&parent,&root).unwrap(),child_identity,"same child inode/file-id alone is insufficient");assert!(transition.require_identity().is_err(),"the actual captured parent identity also binds the step");
 }
}
