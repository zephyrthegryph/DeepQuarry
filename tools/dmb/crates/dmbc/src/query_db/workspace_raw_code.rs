//! Borrowed original CODE_DM production over the existing workspace capture.
//! No captured raw Tree/model, acquisition, per-file query or retained text view.
use super::*;
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure};
use dq_analyze::captured_raw_file::RawPolicyViews;
use crate::runner_host::workspace_capture::SiliconActorDomain;

/// Request-local reader; only an actual admitted workspace guard constructs it.
/// A false visitor result stops a search and does not assert complete coverage.
pub(crate) struct WorkspaceCodeReader<'a,'scope>{
 db:&'a QueryDb,capture:&'a Arc<WorkspaceCapture>,scope:&'a NativeReadGuard<'scope>,
 inventory:&'a ResourceInventory,budget:Arc<Budget>,fixed:usize,
}

/// One actual selected-tree discovery proof for the handler report. Each
/// row still reads through the same current capture and exact file index.
pub(crate) struct SelectedHandlerFiles<'reader,'capture,'scope>{
 reader:&'reader WorkspaceCodeReader<'capture,'scope>,
 inputs:&'reader dm_analysis::policy_inputs::PolicyInputs,
 domain:SiliconActorDomain<'reader>,
}
impl<'capture,'scope> WorkspaceCodeReader<'capture,'scope>{
 pub(crate) fn selected_handler_files<'reader>(
  &'reader self,inputs:&'reader dm_analysis::policy_inputs::PolicyInputs,
  plan:&'reader dq_analyze::captured_allow_annotations::full_unused::SelectedTreePlanData,
 )->Result<SelectedHandlerFiles<'reader,'capture,'scope>,Failure>{
  self.require_policy_inputs(inputs)?;
  self.require_hidden_selected_tree(plan)?;
  Ok(SelectedHandlerFiles{reader:self,inputs,domain:SiliconActorDomain::SelectedCodeMaps(plan)})
 }
}
impl SelectedHandlerFiles<'_,'_,'_>{
 /// None is a true negative in the authenticated selected tree.
 pub(crate) fn with_file(&self,relative:&str,visit:&mut dyn FnMut(Option<RawPolicyViews<'_>>)->Result<(),Failure>)->Result<(),Failure>{
  self.reader.require_policy_inputs(self.inputs)?;
  self.reader.with_hidden_tree_file(self.domain,relative,visit)?;
  self.reader.require_policy_inputs(self.inputs)
 }
}

impl dq_analyze::captured_sem_reads::SelectedReadAllowFiles for SelectedHandlerFiles<'_,'_,'_> {
 fn with_file(&self, relative:&str, visit:&mut dyn FnMut(Option<RawPolicyViews<'_>>)->Result<(),Failure>)->Result<(),Failure> {
  SelectedHandlerFiles::with_file(self, relative, visit)
 }
}

/// Only the exhausted original loop can construct this proof. A stopped
/// name-search cannot be mistaken for complete raw input coverage.
pub(crate) enum WorkspaceCodeTraversal<'reader,'capture,'scope>{Stopped,Completed(WorkspaceCodeCompletion<'reader,'capture,'scope>)}
pub(crate) struct WorkspaceCodeCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>,inputs:&'reader dm_analysis::policy_inputs::PolicyInputs}
/// Compare-only original workspace/discovery/config owner for retained facts.
/// No original bytes, source views or discovery payloads are retained strongly.
pub(crate) struct WorkspaceCodeWitness{capture:Weak<WorkspaceCapture>}
/// Separate CLI generator test-type domain: hidden DM files are included and
/// generated outputs are excluded. This cannot be promoted to CODE_DM proof.
pub(crate) enum WorkspaceGeneratorTestTraversal<'reader,'capture,'scope>{Stopped,Completed(WorkspaceGeneratorTestCompletion<'reader,'capture,'scope>)}
pub(crate) struct WorkspaceGeneratorTestCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>,inputs:&'reader dm_analysis::policy_inputs::PolicyInputs}
pub(crate) struct WorkspaceGeneratorTestWitness{capture:Weak<WorkspaceCapture>}
#[derive(Clone,Copy)]enum FileDomain<'a>{AllowUnused(&'a dq_analyze::captured_allow_annotations::full_unused::SelectedTreePlanData),RawTree(&'a Config,dq_analyze::captured_raw_tree_pages::Policy,bool),Code,Silicon(SiliconActorDomain<'a>),CodeSelected(&'a Config,&'static str,&'static str),EngineMarker(&'a Config,dq_analyze::engine_layering_policy::Layer),GeneratorTests,Hygiene(&'a Config,&'static str,&'static str),CheckGrep(&'a Config,bool),Tracked(Option<(&'a Config,bool)>),Lifecycle(&'a Config),InstanceList(Option<&'a Config>),Decl(Option<&'a Config>),Init(Option<&'a Config>),BaseVars}
fn matches_capture_witness(owner:&Weak<WorkspaceCapture>,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->Result<bool,Failure>{
 crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;
 if !capture.matches_source(inputs.mapping(),inputs.revision().compiler_source){return Err(Failure::Operational(invalid("workspace witness/current semantic source frame differs")))}
 let same=owner.strong_count()!=0&&Weak::ptr_eq(owner,&Arc::downgrade(capture));
 crate::daemon::control::checkpoint()?;Ok(same)
}
impl WorkspaceCodeWitness{
 pub(crate) fn matches(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->Result<bool,Failure>{
  matches_capture_witness(&self.capture,capture,scope,inputs)
 }
 /// Reissue only this actual completed immutable capture proof after current
 /// scope/input checks; a bool/hash/address cannot mint this private witness.
 pub(crate) fn reissue(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs,admit:&mut dyn FnMut(usize)->io::Result<()>)->Result<Self,Failure>{if !self.matches(capture,scope,inputs)?{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"completed code proof belongs to another current capture")))}admit(std::mem::size_of::<Self>()+std::mem::size_of::<WorkspaceCapture>()+2*std::mem::size_of::<usize>())?;Ok(Self{capture:Arc::downgrade(capture)})}
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){if !self.capture.as_ptr().is_null(){visit(self.capture.as_ptr()as usize,std::mem::size_of::<WorkspaceCapture>()+2*std::mem::size_of::<usize>())}}
}
impl WorkspaceGeneratorTestWitness{
 pub(crate) fn matches(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->Result<bool,Failure>{matches_capture_witness(&self.capture,capture,scope,inputs)}
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){if !self.capture.as_ptr().is_null(){visit(self.capture.as_ptr()as usize,std::mem::size_of::<WorkspaceCapture>()+2*std::mem::size_of::<usize>())}}
}
impl WorkspaceGeneratorTestTraversal<'_,'_,'_>{
 pub(crate) fn into_witness(self)->Result<Option<WorkspaceGeneratorTestWitness>,Failure>{match self{Self::Stopped=>Ok(None),Self::Completed(completed)=>completed.into_witness().map(Some)}}
}
impl WorkspaceGeneratorTestCompletion<'_,'_,'_>{
 pub(crate) fn into_witness(self)->Result<WorkspaceGeneratorTestWitness,Failure>{
  self.reader.require_policy_inputs(self.inputs)?;self.reader.require_generator_test_discovery()?;
  self.reader.budget.charge(std::mem::size_of::<WorkspaceGeneratorTestWitness>()+std::mem::size_of::<WorkspaceCapture>()+2*std::mem::size_of::<usize>()).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let witness=WorkspaceGeneratorTestWitness{capture:Arc::downgrade(self.reader.capture)};self.reader.checkpoint()?;Ok(witness)
 }
}
impl WorkspaceCodeTraversal<'_,'_,'_>{
 pub(crate) fn into_witness(self)->Result<Option<WorkspaceCodeWitness>,Failure>{match self{Self::Stopped=>Ok(None),Self::Completed(completed)=>completed.into_witness().map(Some)}}
}
impl WorkspaceCodeCompletion<'_,'_,'_>{
 pub(crate) fn into_witness(self)->Result<WorkspaceCodeWitness,Failure>{
  self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;
  self.reader.budget.charge(std::mem::size_of::<WorkspaceCodeWitness>()+std::mem::size_of::<WorkspaceCapture>()+2*std::mem::size_of::<usize>()).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let witness=WorkspaceCodeWitness{capture:Arc::downgrade(self.reader.capture)};
  self.reader.checkpoint()?;Ok(witness)
 }
}

impl<'capture,'scope> WorkspaceCodeReader<'capture,'scope>{
 pub(crate) fn for_each_generator_test_file_completed<'reader>(&'reader self,inputs:&'reader dm_analysis::policy_inputs::PolicyInputs,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<WorkspaceGeneratorTestTraversal<'reader,'capture,'scope>,Failure>{
  self.require_policy_inputs(inputs)?;self.require_generator_test_discovery()?;
  if !self.for_each_file(FileDomain::GeneratorTests,visit)?{return Ok(WorkspaceGeneratorTestTraversal::Stopped)}
  self.require_policy_inputs(inputs)?;self.require_generator_test_discovery()?;
  Ok(WorkspaceGeneratorTestTraversal::Completed(WorkspaceGeneratorTestCompletion{reader:self,inputs}))
 }
 fn require_generator_test_discovery(&self)->Result<(),Failure>{
  self.checkpoint()?;
  let full=self.capture.covers_generator_cli_tests(&mut|bytes|self.budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  if !full{return Err(Failure::from("complete original generator CLI test-source discovery is required"))}self.checkpoint()?;Ok(())
 }
 pub(crate) fn for_each_code_file_completed<'reader>(&'reader self,inputs:&'reader dm_analysis::policy_inputs::PolicyInputs,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<WorkspaceCodeTraversal<'reader,'capture,'scope>,Failure>{
  self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;
  if !self.for_each_code_file(visit)?{return Ok(WorkspaceCodeTraversal::Stopped)}
  self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;Ok(WorkspaceCodeTraversal::Completed(WorkspaceCodeCompletion{reader:self,inputs}))
 }

 fn require_full_code_discovery(&self)->Result<(),Failure>{
  self.checkpoint()?;
  let full=self.capture.covers_code_dm(&mut|bytes|self.budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  if !full{return Err(Failure::from("complete original recursive CODE_DM discovery is required"))}self.checkpoint()?;Ok(())
 }
 pub(crate) fn require_policy_inputs(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs)->Result<(),Failure>{
  self.checkpoint()?;if !self.capture.matches_source(inputs.mapping(),inputs.revision().compiler_source){return Err(Failure::Operational(invalid("workspace raw/semantic inputs have different original source frames")))}Ok(())
 }

 /// Loan ONLY the original file of this actual callable. This is not CODE
 /// discovery or an arbitrary-path request and cannot mint completion.
 pub(crate) fn with_callable_file(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,ordinal:usize,name:&str,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<(),Failure>)->Result<(),Failure>{
  self.require_policy_inputs(inputs)?;if !matches!(name,"reactions"|"derived"|"generated_reads"|"derived_reads"){return Err(Failure::Operational(invalid("requested callable is not an original Plans reader")))}
  let archive=inputs.archive();let occurrence=archive.occurrences().get(ordinal).ok_or_else(||Failure::Operational(invalid("required reader ordinal unavailable")))?;if archive.callables().ordinal(occurrence.member)!=Some(ordinal){return Err(Failure::Operational(invalid("required reader original roster differs")))}
  self.with_original_callable_file(inputs,occurrence.member,name,&mut|relative,views,_|visit(relative,views))
 }
 pub(crate) fn with_setter_header(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,member:dm_tree::MemberId,name:&str,visit:&mut dyn FnMut(&str,usize,&str)->Result<(),Failure>)->Result<(),Failure>{
  self.require_policy_inputs(inputs)?;if !dq_analyze::auto_setter_calls_policy::PREFIXES.iter().any(|prefix|name.starts_with(prefix)){return Err(Failure::Operational(invalid("requested original callable is not a setter")))}
  self.with_original_callable_file(inputs,member,name,&mut|relative,views,display|{let raw=views.raw()?;let line=raw.lines().nth(display.saturating_sub(1)).ok_or("setter original header line absent")?;visit(relative,display,line)})
 }
 fn with_original_callable_file(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,member:dm_tree::MemberId,name:&str,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>,usize)->Result<(),Failure>)->Result<(),Failure>{
  self.require_policy_inputs(inputs)?;let archive=inputs.archive();let tree=archive.tree();let node=tree.member(member).ok_or_else(||Failure::Operational(invalid("required callable member unavailable")))?;if tree.symbols().text(node.name)!=Some(name)||!matches!(node.kind,dm_tree::MemberKind::Proc|dm_tree::MemberKind::Verb){return Err(Failure::Operational(invalid("required callable name differs from original member")))}
  let origin=archive.callable_header_policy_line(member)?;let file=inputs.file_exact(origin.path.as_path()).ok_or_else(||Failure::Operational(invalid("required callable original file unavailable")))?;let display=file.analyze_display_line(origin.line).map_err(|error|Failure::Unsupported(error.to_string()))?;
  let mapping=inputs.mapping();let(index,lease)=mapping.source_acquisitions().enumerate().find_map(|(index,(path,lease))|(path==origin.path.as_path()).then_some((index,lease))).ok_or_else(||Failure::Operational(invalid("required reader source acquisition unavailable")))?;let lease=lease.ok_or_else(||Failure::Operational(invalid("required reader has no original acquisition")))?;let original=self.scope.original(index,&lease.identity())?;
  let pending=dq_analyze::captured_raw_file::with_original_policy_file_prepared(self.capture.root(),&origin.path,0,&self.budget,|scratch|{
   self.checkpoint()?;let mut backing=Some(0usize);let raw=match &original{crate::input_snapshot::RecordedSourceOriginal::Utf8(text)=>{dq_analyze::captured_raw_file::visit_source_storage(text,|_,bytes|backing=backing.and_then(|n|n.checked_add(bytes)));text.as_bytes()},crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)=>{backing=bytes.capacity().checked_add(128);bytes.as_slice()}};let transform=if matches!(&original,crate::input_snapshot::RecordedSourceOriginal::Utf8(text)if !text.as_bytes().contains(&b'\r')){Some(0)}else{dq_analyze::captured_raw_file::analyze_raw_len(raw)?.checked_mul(4).and_then(|n|n.checked_add(8192))};let peak=backing.and_then(|n|n.checked_add(transform?)).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"required original normalization overflow")))?;scratch.charge(peak).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;Ok(crate::input_snapshot::normalize_recorded_policy_original(&original))
  },&mut|relative,views|{visit(relative,views,display)?;Ok(true)});
  if matches!(&pending,Err(Failure::Operational(_))){return pending.map(|_|())}self.require_policy_inputs(inputs)?;pending.map(|_|())
 }
 pub(crate) fn budget(&self)->&Arc<Budget>{&self.budget}
 pub(crate) fn root(&self)->&std::path::Path{self.capture.root()}
 pub(crate) fn configuration(&self)->(&std::path::Path,Option<&[u8]>){self.capture.configuration()}
 fn checkpoint(&self)->Result<(),Failure>{let _=self.inventory.bytes();crate::daemon::control::checkpoint()?;self.capture.require_scope(self.scope)?;self.budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))}
 pub(crate) fn for_each_check_grep_file(&self,config:&Config,include_exempt:bool,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{self.capture.check_grep_names(self.scope)?;self.for_each_file(FileDomain::CheckGrep(config,include_exempt),visit)}
 pub(crate) fn with_check_grep_fixed<R>(&self,which:dq_analyze::lints::check_grep::native::Fixed,visit:impl FnOnce(Option<&[u8]>)->Result<R,Failure>)->Result<R,Failure>{self.checkpoint()?;let pending=self.capture.with_check_grep_fixed(self.scope,which,visit);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;pending}
 pub(crate) fn for_each_check_grep_dme(&self,visit:&mut dyn FnMut(&str,&[u8])->Result<(),Failure>)->Result<(),Failure>{self.checkpoint()?;let pending=self.capture.for_each_check_grep_dme(self.scope,visit);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;pending}
 pub(crate) fn check_grep_names(&self)->Result<(&[std::path::PathBuf],&[std::path::PathBuf]),Failure>{self.checkpoint()?;Ok(self.capture.check_grep_names(self.scope)?)}
 pub(crate) fn require_check_grep_archive(&self,archive:&dm_tree::frontend::BodyArchive)->Result<(),Failure>{self.checkpoint()?;self.capture.require_check_grep_archive(self.scope,archive)?;if !archive.uses_body_queries(self.db){return Err(Failure::Operational(invalid("check_grep archive has another or absent actual body QueryDb")))}self.checkpoint()}
 pub(crate) fn check_grep_checkpoint(&self)->Result<(),Failure>{self.checkpoint()}
 pub(crate) fn for_each_code_file(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  self.for_each_file(FileDomain::Code,visit)
 }
 fn for_each_file(&self,domain:FileDomain<'_>,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  self.checkpoint()?;let mut start=0;
  while start<self.capture.file_count(){
   self.checkpoint()?;
   let fixed=self.fixed.checked_add(self.budget.used()).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace code fold accounting overflow")))?;
   let available=self.db.workspace_input_headroom_locked(fixed)?;
   let(files,end)=match domain{FileDomain::AllowUnused(plan)=>self.capture.allow_unused_page(self.scope,start,PAGE_FILES,available,plan)?,FileDomain::RawTree(config,policy,selected)=>self.capture.raw_tree_policy_page(self.scope,start,PAGE_FILES,available,config,policy,selected)?,FileDomain::Code=>self.capture.code_page(self.scope,start,PAGE_FILES,available)?,FileDomain::Silicon(domain)=>self.capture.silicon_page(self.scope,start,PAGE_FILES,available,domain)?,FileDomain::CodeSelected(config,policy,group)=>self.capture.code_policy_page(self.scope,start,PAGE_FILES,available,config,policy,group)?,FileDomain::EngineMarker(config,layer)=>self.capture.engine_marker_page(self.scope,start,PAGE_FILES,available,config,layer)?,FileDomain::GeneratorTests=>self.capture.generator_test_page(self.scope,start,PAGE_FILES,available)?,FileDomain::Hygiene(config,policy,group)=>self.capture.hygiene_page(self.scope,start,PAGE_FILES,available,config,policy,group)?,FileDomain::CheckGrep(config,include_exempt)=>self.capture.check_grep_page(self.scope,start,PAGE_FILES,available,config,include_exempt)?,FileDomain::Tracked(config)=>self.capture.tracked_page(self.scope,start,PAGE_FILES,available,config)?,FileDomain::Lifecycle(config)=>self.capture.lifecycle_page(self.scope,start,PAGE_FILES,available,config)?,FileDomain::InstanceList(config)=>self.capture.instance_list_page(self.scope,start,PAGE_FILES,available,config)?,FileDomain::Decl(config)=>self.capture.decl_page(self.scope,start,PAGE_FILES,available,config)?,FileDomain::Init(config)=>self.capture.init_page(self.scope,start,PAGE_FILES,available,config)?,FileDomain::BaseVars=>self.capture.base_vars_page(self.scope,start,PAGE_FILES,available)?};
   if end<=start{return Err(Failure::Operational(invalid("original code page made no progress")))}
   // Sum is deliberately conservative for aliased sources; the existing page
   // constructor independently admits its exact union before normalization.
   let live=files.iter().try_fold(files.capacity().checked_mul(std::mem::size_of::<CurrentFile>()).ok_or_else(||invalid("code page metadata overflow"))?,|n,file|n.checked_add(file.charge).and_then(|n|n.checked_add(file.path.capacity())).ok_or_else(||invalid("code page live ownership overflow")))?;
   for file in &files{
    self.checkpoint()?;
    let Some(text)=&file.text else{continue};
    let pending=if matches!(domain,FileDomain::RawTree(_,dq_analyze::captured_raw_tree_pages::Policy::DocSnippets|dq_analyze::captured_raw_tree_pages::Policy::UiActions,_)|FileDomain::EngineMarker(..)){dq_analyze::captured_raw_file::with_original_policy_file_clean(self.capture.root(),&file.path,text.clone(),live,&self.budget,visit)}else{dq_analyze::captured_raw_file::with_original_policy_file(self.capture.root(),&file.path,text.clone(),live,&self.budget,visit)};
    if matches!(&pending,Err(Failure::Operational(_))){return pending}
    self.checkpoint()?;if !pending?{return Ok(false)}
   }
   drop(files);start=end;
  }
  self.checkpoint()?;Ok(true)
 }
}
impl QueryDb{
 /// Execute policy-only folds over actual discovered original files. Complete
 /// discovery/config/source evidence remains on the existing WorkspaceCapture.
 /// The operation budget is funded from this SAME raw-family inventory and
 /// limits. No result or source authority is cached by this entry.
 pub(crate) fn with_workspace_code_pages<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,visit:impl FnOnce(&WorkspaceCodeReader<'_,'_>)->Result<R,Failure>)->Result<R,Failure>{
  crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;
  if !scope.uses_queries(self){return Err(Failure::Operational(invalid("original code pages need the current compiler QueryDb")))}
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  self.with_workspace_code_pages_locked(capture,scope,visit)
 }
 /// Registered queries enter through an endpoint already holding this SAME
 /// raw-family gate. Reuse its one reader budget rather than relocking the
 /// non-reentrant gate or creating a second operation-budget domain.
 pub(in crate::query_db) fn with_workspace_code_pages_locked<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,visit:impl FnOnce(&WorkspaceCodeReader<'_,'_>)->Result<R,Failure>)->Result<R,Failure>{
  self.with_workspace_code_pages_using_locked(capture,scope,None,None,visit)
 }
 /// Child computations share the actual endpoint operation Budget; no mint or
 /// parent-delta recharge occurs on this path. This is control, not authority.
 pub(in crate::query_db) fn with_workspace_code_pages_budget_locked<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,budget:&Arc<Budget>,visit:impl FnOnce(&WorkspaceCodeReader<'_,'_>)->Result<R,Failure>)->Result<R,Failure>{self.with_workspace_code_pages_using_locked(capture,scope,Some(budget),None,visit)}
 pub(in crate::query_db) fn with_workspace_code_pages_limit_locked<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:Option<usize>,visit:impl FnOnce(&WorkspaceCodeReader<'_,'_>)->Result<R,Failure>)->Result<R,Failure>{self.with_workspace_code_pages_using_locked(capture,scope,None,limit,visit)}
 fn with_workspace_code_pages_using_locked<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,shared:Option<&Arc<Budget>>,limit:Option<usize>,visit:impl FnOnce(&WorkspaceCodeReader<'_,'_>)->Result<R,Failure>)->Result<R,Failure>{
  crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;
  if !scope.uses_queries(self){return Err(Failure::Operational(invalid("original code pages need the current compiler QueryDb")))}
  self.raw_prune_locked(std::time::Instant::now());
  let inventory=self.workspace_resource_inventory_locked()?;
  let fixed=self.raw_source_capture_fixed_credit_locked(capture)?.map_or_else(||capture.retained_charge(),|_|Ok(0))?.checked_add(inventory.coordination_charge(0)?).and_then(|n|n.checked_add(std::mem::size_of::<WorkspaceCodeReader<'_,'_>>()+PAGE_FILES*std::mem::size_of::<CurrentFile>()+4096)).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace code fixed accounting overflow")))?;
  let input=self.workspace_input_headroom_locked(fixed)?;
  let budget=match shared{Some(budget)=>{budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;Arc::clone(budget)},None=>{
  let results=RESULT_BOUND.checked_sub(self.raw_policy.charge.load(Ordering::Relaxed)).and_then(|n|n.checked_sub(inventory.bytes())).and_then(|n|n.checked_sub(aggregate::REPORT_RESERVE)).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace code result-family headroom exhausted")))?;
  let budget=Budget::new(input.min(results).min(limit.unwrap_or(usize::MAX))).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
budget}};
  let reader=WorkspaceCodeReader{db:self,capture,scope,inventory:&inventory,budget,fixed};
  let pending=visit(&reader);
  if matches!(&pending,Err(Failure::Operational(_))){return pending}
  self.refresh_raw_source_inputs_locked()?;self.workspace_input_headroom_locked(fixed)?;reader.checkpoint()?;pending
 }
}

/// Only this actual selected-domain loop can issue an exhausted Hygiene proof.
pub(crate) struct SysSelectionCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>}
impl SysSelectionCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_sys_discovery()?;self.reader.checkpoint()}}
impl<'capture,'scope> WorkspaceCodeReader<'capture,'scope>{
 fn require_sys_discovery(&self)->Result<(),Failure>{self.checkpoint()?;let mut admit=|bytes|self.budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message));if !self.capture.covers_hygiene(&mut admit)?{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"Hygiene requires actual complete Meta.Select code/maps discovery")))}Ok(())}
 fn for_each_sys_selection<'reader>(&'reader self,configuration:&'reader Config,policy:&'static str,group:&'static str,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<Option<SysSelectionCompletion<'reader,'capture,'scope>>,Failure>{self.require_sys_discovery()?;if !self.for_each_file(FileDomain::Hygiene(configuration,policy,group),visit)?{return Ok(None)}self.require_sys_discovery()?;Ok(Some(SysSelectionCompletion{reader:self}))}
}
struct SysPages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,configuration:&'a Config,policy:&'static str,group:&'static str,completions:std::cell::RefCell<[Option<SysSelectionCompletion<'a,'capture,'scope>>;2]>,passes:std::cell::Cell<usize>,expected:usize}
impl<'a,'capture,'scope> SysPages<'a,'capture,'scope>{
 fn new(reader:&'a WorkspaceCodeReader<'capture,'scope>,configuration:&'a Config,policy:&'static str,expected:usize)->Self{Self{reader,configuration,policy,group:"sys",completions:std::cell::RefCell::new([None,None]),passes:std::cell::Cell::new(0),expected}}
 fn finish(self)->Result<(),Failure>{if self.passes.get()!=self.expected{return Err(Failure::Operational(invalid("Sys actual source pass count differs")))}for(index,completion)in self.completions.into_inner().into_iter().enumerate(){if index<self.expected{completion.ok_or_else(||Failure::Operational(invalid("Sys actual selected EOF token absent")))?.require()?}}Ok(())}
}
impl<'a,'capture,'scope> dq_analyze::reactive_raw_policy_pages::RawPolicyPages for SysPages<'a,'capture,'scope>{
 fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let index=self.passes.get();if index>=self.expected||index>=2{return Err(Failure::Operational(invalid("Sys original provider exceeded its actual policy passes")))}let reader:&'a WorkspaceCodeReader<'capture,'scope>=self.reader;let completion=reader.for_each_sys_selection(self.configuration,self.policy,self.group,visit)?;let complete=completion.is_some();self.completions.borrow_mut()[index]=completion;self.passes.set(index+1);Ok(complete)}
}
impl QueryDb{
 /// Actual scope/current-Db dispatch. Borrowed output cannot escape the funded
 /// operation. Unsealed Analyze DATA alone cannot invoke this publication loan.
 pub(crate) fn with_workspace_hygiene<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_hygiene_pages::HygieneData)->io::Result<R>)->io::Result<R>{
  self.with_workspace_hygiene_report(capture,scope,|data,_config,_budget|consume(data))
 }
 /// SAME complete selected-domain issuer, additionally lending actual config
 /// and operation funding for borrowed report projection; no owner escapes.
 pub(crate) fn with_workspace_hygiene_report<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_hygiene_pages::HygieneData,&Config,&Arc<Budget>)->io::Result<R>)->io::Result<R>{
  let result=self.with_workspace_code_pages(capture,scope,|reader|{
   let(_,bytes)=reader.configuration();let bound=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Hygiene existing configuration bound overflow")))?;reader.budget.charge(bound).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
   let pages=SysPages::new(reader,&config,"sys/hygiene",1);
   let output=dq_analyze::captured_sys_hygiene_pages::collect(&pages,&config,reader.budget(),&||{crate::daemon::control::checkpoint()})?;
   pages.finish()?;reader.checkpoint()?;
   let pending=consume(&output,&config,reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
  });match result{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(invalid(message))}
 }
 pub(crate) fn with_workspace_resolvers<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_resolvers_pages::ResolverData)->io::Result<R>)->io::Result<R>{
  self.with_workspace_resolvers_report(capture,scope,|data,_config,_budget|consume(data))
 }
 pub(crate) fn with_workspace_resolvers_report<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_resolvers_pages::ResolverData,&Config,&Arc<Budget>)->io::Result<R>)->io::Result<R>{
  let result=self.with_workspace_code_pages(capture,scope,|reader|{
   let(_,bytes)=reader.configuration();let bound=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Resolver existing configuration bound overflow")))?;reader.budget.charge(bound).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
   let pages=SysPages::new(reader,&config,"sys/resolvers",2);
   let output=dq_analyze::captured_sys_resolvers_pages::collect(&pages,&config,reader.budget(),&||{crate::daemon::control::checkpoint()})?;
   pages.finish()?;reader.checkpoint()?;
   let pending=consume(&output,&config,reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
  });match result{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(invalid(message))}
 }
 pub(crate) fn with_workspace_tables<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_tables_pages::TablesData)->io::Result<R>)->io::Result<R>{
  self.with_workspace_tables_report(capture,scope,|data,_config,_budget|consume(data))
 }
 pub(crate) fn with_workspace_tables_report<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_tables_pages::TablesData,&Config,&Arc<Budget>)->io::Result<R>)->io::Result<R>{
  let result=self.with_workspace_code_pages(capture,scope,|reader|{
   let(_,bytes)=reader.configuration();let bound=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Tables existing configuration bound overflow")))?;reader.budget.charge(bound).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
   let pages=SysPages::new(reader,&config,"sys/tables",2);
   let output=dq_analyze::captured_sys_tables_pages::collect(&pages,&config,reader.budget(),&||{crate::daemon::control::checkpoint()})?;
   pages.finish()?;reader.checkpoint()?;
   let pending=consume(&output,&config,reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
  });match result{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(invalid(message))}
 }
 pub(crate) fn with_workspace_boundary<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_system_boundary_pages::BoundaryData)->io::Result<R>)->io::Result<R>{
  self.with_workspace_boundary_report(capture,scope,|data,_config,_budget|consume(data))
 }
 pub(crate) fn with_workspace_boundary_report<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_system_boundary_pages::BoundaryData,&Config,&Arc<Budget>)->io::Result<R>)->io::Result<R>{
  let result=self.with_workspace_code_pages(capture,scope,|reader|{
   let(_,bytes)=reader.configuration();let bound=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Boundary existing configuration bound overflow")))?;reader.budget.charge(bound).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
   let mut pages=SysPages::new(reader,&config,"system_boundary",2);pages.group="";
   let output=dq_analyze::captured_system_boundary_pages::collect(&pages,&config,reader.budget(),&||{crate::daemon::control::checkpoint()})?;
   pages.finish()?;reader.checkpoint()?;
   let pending=consume(&output,&config,reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
  });match result{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(invalid(message))}
 }
}

// ALLOW validation shares the exact original CODE_MAPS_DM source domain, but
// never turns an annotation scan into a complete all-policy usage certificate.
fn allow_validation_rows<T>(budget:&Budget,rows:&mut Vec<T>)->Result<(),Failure>{
 if rows.len()<rows.capacity(){return Ok(())}let wanted=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;let max=wanted.checked_mul(4).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;budget.charge(max.checked_mul(std::mem::size_of::<T>()).and_then(|n|n.checked_add(64)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;rows.try_reserve_exact(wanted-rows.len()).map_err(|error|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,error)))?;if rows.capacity()>max{budget.deny();return Err(Failure::Operational(io::ErrorKind::OutOfMemory.into()))}Ok(())
}
fn allow_annotations_using<R>(reader:&WorkspaceCodeReader<'_,'_>,consume:impl FnOnce(&dq_analyze::captured_allow_annotations::ValidationData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 use dq_analyze::{captured_allow_annotations as policy,lint::Site};
 reader.require_sys_discovery()?;let meta=dq_analyze::allow_annotation_policy::metadata();let selected=dq_analyze::dm::sys::policy_selection();if meta.select.roots!=selected.roots||meta.select.hidden!=selected.hidden{return Err("ALLOW original selected domain differs from the actual shared recorded issuer".into())}
 let(_,bytes)=reader.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;reader.budget().charge(width).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 let checkpoint=||reader.checkpoint().map_err(|error|match error{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>invalid(message)});let mut control=policy::Operation{budget:reader.budget(),poll:&checkpoint};let registry=dq_analyze::allow_registry_metadata::complete_registry_allow_names(&mut control)?;let mut output=policy::ValidationData{sites:Vec::new(),source_text:Vec::new()};
 policy::with_names(&registry,&config,&mut control,|known,_control|{
  let completion=reader.for_each_sys_selection(&config,meta.name,meta.group,&mut|relative,views|{
   policy::validate_original_budgeted(known,views,reader.budget(),&checkpoint,|rule,line,message,original|{
    let bytes=rule.len().checked_add(relative.len()).and_then(|n|n.checked_add(message.len())).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(original.len().checked_mul(8)?)).and_then(|n|n.checked_add(1024)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;reader.budget().charge(bytes).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;allow_validation_rows(reader.budget(),&mut output.sites)?;allow_validation_rows(reader.budget(),&mut output.source_text)?;output.sites.push(Site{rule:rule.to_owned(),rel:relative.to_owned(),line:u32::try_from(line).map_err(|_|Failure::Operational(io::ErrorKind::OutOfMemory.into()))?,msg:message.to_owned(),key:String::new(),ident:String::new()});output.source_text.push(dq_analyze::util::normalize_ws(original));Ok(())
   })?;Ok(true)
  })?;completion.ok_or("ALLOW selected recorded traversal stopped before its actual EOF")?.require()?;Ok(())
 })?;
 reader.checkpoint()?;let pending=consume(&output,&config,reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
}
impl QueryDb{
 pub(crate) fn with_workspace_allow_annotations<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_allow_annotations::ValidationData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{self.with_workspace_code_pages(capture,scope,|reader|allow_annotations_using(reader,consume))}
 #[cfg(test)]pub(crate) fn with_workspace_allow_annotations_limit<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:usize,consume:impl FnOnce(&dq_analyze::captured_allow_annotations::ValidationData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;if !scope.uses_queries(self){return Err(Failure::Operational(invalid("ALLOW source pages need the actual current QueryDb")))}let _gate=self.raw_policy.gate.lock().unwrap_or_else(|error|error.into_inner());self.with_workspace_code_pages_limit_locked(capture,scope,Some(limit),|reader|allow_annotations_using(reader,consume))}
}


// Actual sem/keys source completion is distinct from finite capture coverage.
struct KeysSourceCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>}
impl KeysSourceCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_full_code_discovery()?;self.reader.checkpoint()}}
struct KeysPages<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>,completed:std::cell::RefCell<[Option<KeysSourceCompletion<'reader,'capture,'scope>>;2]>,passes:std::cell::Cell<usize>}
impl<'reader,'capture,'scope> KeysPages<'reader,'capture,'scope>{
 fn new(reader:&'reader WorkspaceCodeReader<'capture,'scope>)->Self{Self{reader,completed:std::cell::RefCell::new([None,None]),passes:std::cell::Cell::new(0)}}
 fn finish(&self)->Result<(),Failure>{if self.passes.get()!=2{return Err("keys did not execute both actual original source phases".into())}for completed in self.completed.borrow_mut().iter_mut(){completed.take().ok_or("keys actual original phase did not reach EOF")?.require()?;}self.reader.checkpoint()}
}
impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for KeysPages<'_,'_,'_>{
 fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  let index=self.passes.get();if index>=2{return Err("keys source provider exceeded its actual original phases".into())}self.reader.require_full_code_discovery()?;
  if !self.reader.for_each_code_file(visit)?{self.passes.set(index+1);return Ok(false)}self.reader.require_full_code_discovery()?;self.completed.borrow_mut()[index]=Some(KeysSourceCompletion{reader:self.reader});self.passes.set(index+1);Ok(true)
 }
}
struct KeysOrderScratch{budget:Arc<Budget>,complete:bool}impl KeysOrderScratch{fn new(root:&Arc<Budget>)->Result<Self,Failure>{Ok(Self{budget:Budget::scoped_temporaries(root).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?,complete:false})}}impl Drop for KeysOrderScratch{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}
fn keys_using<R>(reader:&WorkspaceCodeReader<'_,'_>,consume:impl FnOnce(&dq_analyze::captured_keys_pages::KeyData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 reader.require_full_code_discovery()?;let meta=dq_analyze::keys_policy::metadata();if meta.select.roots!=dq_analyze::captured_raw_file::code_dm_roots()||meta.select.hidden!=dq_analyze::tree::CODE_DM.hidden{return Err("keys original selection differs from actual CODE source issuer".into())}
 let(_,bytes)=reader.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;reader.budget().charge(width).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 let checkpoint=||reader.checkpoint().map_err(|error|match error{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>invalid(message)});
 reader.capture.with_keys_manifest(reader.scope,|original|{
  let mut scratch=KeysOrderScratch::new(reader.budget())?;
  let text=original.and_then(|bytes|std::str::from_utf8(bytes).ok()).unwrap_or("");
  let mut control=dq_analyze::captured_allow_annotations::Operation{budget:&scratch.budget,poll:&checkpoint};
  let order=dq_analyze::raw_marker_policy::dme_include_order_controlled(text,false,&mut control)?;
  let pages=KeysPages::new(reader);let data=dq_analyze::captured_keys_pages::collect(&pages,&config,&order,reader.budget(),&checkpoint)?;pages.finish()?;reader.checkpoint()?;
  let pending=consume(&data,&config,reader.budget()).map_err(Failure::Operational);
  // Source/row/order owners physically end before a successful scratch credit.
  drop(data);drop(pages);drop(order);drop(control);scratch.complete=pending.is_ok();drop(scratch);
  if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
 })
}
impl QueryDb{
 pub(crate) fn with_workspace_keys<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_keys_pages::KeyData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{self.with_workspace_code_pages(capture,scope,|reader|keys_using(reader,consume))}
 #[cfg(test)]pub(crate) fn with_workspace_keys_limit<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:usize,consume:impl FnOnce(&dq_analyze::captured_keys_pages::KeyData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;if !scope.uses_queries(self){return Err(Failure::Operational(invalid("keys source pages require actual current QueryDb")))}let _gate=self.raw_policy.gate.lock().unwrap_or_else(|error|error.into_inner());self.with_workspace_code_pages_limit_locked(capture,scope,Some(limit),|reader|keys_using(reader,consume))}
}

impl QueryDb{
 /// Metadata-only full registry validation under the actual captured workspace
 /// guard and reader budget. No source pass or execution completion is issued.
 pub(crate) fn require_workspace_report_configuration(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>)->Result<(),Failure>{
  self.with_workspace_code_pages(capture,scope,|reader|{
   use dq_analyze::key_policy_control::Control as _;
   let (_,bytes)=reader.configuration();
   let bound=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
   reader.budget().charge(bound).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
   let poll=||reader.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});
   let mut control=dq_analyze::captured_allow_annotations::Operation{budget:reader.budget(),poll:&poll};
   let result=config.validate_complete_registry_scopes(&mut control)?;
   if result.problems().is_empty(){control.checkpoint()?;return Ok(())}
   let mut width=0usize;for problem in result.problems(){control.checkpoint()?;width=width.checked_add(problem.len()).and_then(|n|n.checked_add(1)).ok_or_else(||control.overflow())?;}
   let cap=width.checked_mul(4).and_then(|n|n.checked_add(128)).ok_or_else(||control.overflow())?;control.reserve(cap)?;
   let mut message=String::new();message.try_reserve_exact(width).map_err(|_|control.allocation_failed())?;if message.capacity()>cap{return Err(control.allocation_failed())}
   for problem in result.problems(){control.checkpoint()?;if !message.is_empty(){message.push('\n')}message.push_str(problem);}
   control.checkpoint()?;Err(Failure::Unsupported(message))
  })
 }
}

impl QueryDb{
 pub(crate) fn require_original_fixed_report_subject(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,mapping:&dm_tree::frontend::SourceExportMapping)->Result<(),Failure>{
  self.with_workspace_code_pages(capture,scope,|reader|{
   let(index,entry,path,lease)=mapping.original_root_acquisition_using(&mut||reader.checkpoint())?;
   // Existing comparison helpers allocate lexical comparison paths. Admit both
   // live path pairs before allocation; this does not authorize a source alias.
   let width=entry.as_os_str().len().checked_add(path.as_os_str().len()).and_then(|n|n.checked_add(capture.root().as_os_str().len().checked_mul(2)?)).and_then(|n|n.checked_mul(64)).and_then(|n|n.checked_add(8192)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
   reader.budget().charge(width).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let declared=dm_preprocess::regions::relative_filesystem_path(entry,capture.root());
   let acquired=dm_preprocess::regions::relative_filesystem_path(path,capture.root());
   if declared.as_deref()!=Some(std::path::Path::new("deepquarry.dme"))||acquired.as_deref()!=Some(std::path::Path::new("deepquarry.dme")){return Err("public Original subject is not the actual fixed deepquarry root entry".into())}
   // The real current guard authenticates this exact root lease. Neither a
   // fixed-name search nor its separately captured optional file can pass here.
   let original=scope.original(index,&lease.identity())?;
   let text=match &original{crate::input_snapshot::RecordedSourceOriginal::Utf8(text)=>Some(text.as_str()),crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)=>std::str::from_utf8(bytes.as_slice()).ok()};
   if !text.is_some_and(|text|text.contains("#include")){return Err("public Original root lacks a genuine readable include manifest".into())}
   reader.checkpoint()
  })
 }
}

/// Distinct CODE_MAPS_DM evidence minted only after actual tracked index/selected loops.
/// A completed CODE_DM fold cannot construct or substitute this proof.
pub(crate) struct WorkspaceTrackedWitness{capture:Weak<WorkspaceCapture>}
impl WorkspaceTrackedWitness{
 pub(crate) fn matches(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->Result<bool,Failure>{matches_capture_witness(&self.capture,capture,scope,inputs)}
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){if !self.capture.as_ptr().is_null(){visit(self.capture.as_ptr()as usize,std::mem::size_of::<WorkspaceCapture>()+2*std::mem::size_of::<usize>())}}
}
impl WorkspaceCodeReader<'_,'_>{
 /// Unique concrete producer, not a caller-supplied completion callback. The
 /// first pass includes exempt files because they still declare tracked schema.
 pub(crate) fn tracked_data(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,config:&Config,tests:bool,body:&dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>)->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>)->Result<(dq_analyze::captured_tracked_pages::TrackedData,WorkspaceTrackedWitness),Failure>{
  self.require_policy_inputs(inputs)?;self.require_sys_discovery()?;
  let actual=dq_analyze::tracked_policy::metadata(tests).select;let required=dq_analyze::dm::sys::policy_selection();if actual.roots!=required.roots||actual.hidden!=required.hidden{return Err(Failure::Operational(invalid("tracked metadata differs from actual CODE_MAPS_DM discovery")))}
  struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,config:&'a Config,tests:bool,passes:std::cell::Cell<usize>}
  impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>1{return Err(Failure::Operational(invalid("tracked producer exceeded its actual two source phases")))}self.reader.require_sys_discovery()?;let selection=if pass==0{None}else{Some((self.config,self.tests))};if !self.reader.for_each_file(FileDomain::Tracked(selection),visit)?{return Ok(false)}self.reader.require_sys_discovery()?;self.reader.checkpoint()?;self.passes.set(pass+1);Ok(true)}}
  let pages=Pages{reader:self,config,tests,passes:std::cell::Cell::new(0)};let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});
  let data=dq_analyze::captured_tracked_pages::collect_from_pages(inputs,self.root(),&pages,config,tests,self.budget(),&poll,body)?;
  // The concrete producer can omit phase two only when no tracked schema exists.
  // Arbitrary DATA callbacks cannot supply this count or mint the witness.
  if !(1..=2).contains(&pages.passes.get()){return Err(Failure::Operational(invalid("tracked producer omitted actual complete declaration EOF")))}
  self.require_policy_inputs(inputs)?;self.require_sys_discovery()?;self.budget.charge(std::mem::size_of::<WorkspaceTrackedWitness>()+std::mem::size_of::<WorkspaceCapture>()+2*std::mem::size_of::<usize>())?;let witness=WorkspaceTrackedWitness{capture:Arc::downgrade(self.capture)};self.checkpoint()?;Ok((data,witness))
 }
}

/// Real CODE_DM exhaustion of the unique raw state-schema producer only.
/// Kept private and borrowed: DATA adapters cannot manufacture this role.
struct StateSchemaCompletion<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>}
impl StateSchemaCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_full_code_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{
 fn state_schema_using<T>(&self,consume:impl FnOnce(&dq_analyze::captured_state_schema_pages::StateSchemaData)->io::Result<T>)->Result<T,Failure>{self.state_schema_using_config(false,|data,_,_|consume(data))}
 fn state_schema_using_report<T>(&self,consume:impl FnOnce(&dq_analyze::captured_state_schema_pages::StateSchemaData,&Config,&Arc<Budget>)->io::Result<T>)->Result<T,Failure>{self.state_schema_using_config(true,|data,config,budget|consume(data,config.expect("actual report configuration"),budget))}
 fn state_schema_using_config<T>(&self,report:bool,consume:impl FnOnce(&dq_analyze::captured_state_schema_pages::StateSchemaData,Option<&Config>,&Arc<Budget>)->io::Result<T>)->Result<T,Failure>{
  self.require_full_code_discovery()?;let meta=&dq_analyze::state_schema_policy::META;let selected=dq_analyze::tree::CODE_DM;if meta.select.roots!=selected.roots||meta.select.hidden!=selected.hidden{return Err(Failure::Operational(invalid("state-schema metadata differs from actual CODE_DM discovery")))}
let config=if report{let(_,bytes)=self.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(width).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let captured=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;Some(captured)}else{None};
  struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,completion:std::cell::RefCell<Option<StateSchemaCompletion<'a,'capture,'scope>>>,begun:std::cell::Cell<bool>}
  impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{if self.begun.replace(true){return Err(Failure::Operational(invalid("state-schema producer repeated its actual source phase")))}self.reader.require_full_code_discovery()?;if !self.reader.for_each_code_file(visit)?{return Ok(false)}self.reader.require_full_code_discovery()?;*self.completion.borrow_mut()=Some(StateSchemaCompletion{reader:self.reader});Ok(true)}}
  let pages=Pages{reader:self,completion:std::cell::RefCell::new(None),begun:std::cell::Cell::new(false)};let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_state_schema_pages::collect_from_pages(&pages,self.budget(),&poll)?;pages.completion.into_inner().ok_or_else(||Failure::Operational(invalid("state-schema actual complete CODE EOF is absent")))?.require()?;
  let pending=consume(&data,config.as_ref(),self.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;pending
 }
}
impl QueryDb{
 /// Private raw-only complete state-schema policy loan. It uses the existing
 /// current guard, raw-family gate and operation Budget; no compiler model,
 /// body demand, answer cache or public execution-union receipt is introduced.
 pub(crate) fn with_workspace_state_schema<T>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_state_schema_pages::StateSchemaData)->io::Result<T>)->io::Result<T>{self.with_workspace_state_schema_limit(capture,scope,None,consume)}
 pub(crate) fn with_workspace_state_schema_limit<T>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:Option<usize>,consume:impl FnOnce(&dq_analyze::captured_state_schema_pages::StateSchemaData)->io::Result<T>)->io::Result<T>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|error|error.into_inner());let pending=self.with_workspace_code_pages_limit_locked(capture,scope,limit,|reader|reader.state_schema_using(consume));match pending{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(io::Error::new(io::ErrorKind::Unsupported,message))}}
}

// Private two-phase CODE receipt for the concrete lifecycle producer only.
struct LifecycleCompletion<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>}
impl LifecycleCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_full_code_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{fn lifecycle_using<T>(&self,consume:impl FnOnce(&dq_analyze::captured_lifecycle_pages::LifecycleData)->io::Result<T>)->Result<T,Failure>{self.lifecycle_using_report(|data,_,_|consume(data))}
 fn lifecycle_using_report<T>(&self,consume:impl FnOnce(&dq_analyze::captured_lifecycle_pages::LifecycleData,&Config,&Arc<Budget>)->io::Result<T>)->Result<T,Failure>{self.require_full_code_discovery()?;let meta=&dq_analyze::lifecycle_policy::META;if meta.select.roots!=dq_analyze::tree::CODE_DM.roots||meta.select.hidden!=dq_analyze::tree::CODE_DM.hidden{return Err("lifecycle actual CODE selection differs".into())}let(_,bytes)=self.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(width).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,config:&'a Config,passes:std::cell::Cell<usize>,completed:std::cell::RefCell<[Option<LifecycleCompletion<'a,'capture,'scope>>;2]>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("lifecycle producer exceeded actual two CODE phases".into())}self.reader.require_full_code_discovery()?;let complete=if pass==0{self.reader.for_each_code_file(visit)?}else{self.reader.for_each_file(FileDomain::Lifecycle(self.config),visit)?};if !complete{return Ok(false)}self.reader.require_full_code_discovery()?;self.reader.checkpoint()?;self.completed.borrow_mut()[pass]=Some(LifecycleCompletion{reader:self.reader});self.passes.set(pass+1);Ok(true)}}
 let pages=Pages{reader:self,config:&config,passes:std::cell::Cell::new(0),completed:std::cell::RefCell::new([None,None])};let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_lifecycle_pages::collect_from_pages(&pages,self.budget(),&poll)?;if pages.passes.get()!=2{return Err("lifecycle producer omitted original source phases".into())}for token in pages.completed.borrow_mut().iter_mut(){token.take().ok_or("lifecycle actual CODE EOF absent")?.require()?;}self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;pending}}
impl QueryDb{pub(crate) fn with_workspace_lifecycle<T>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_lifecycle_pages::LifecycleData)->io::Result<T>)->io::Result<T>{self.with_workspace_lifecycle_limit(capture,scope,None,consume)}pub(crate) fn with_workspace_lifecycle_limit<T>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:Option<usize>,consume:impl FnOnce(&dq_analyze::captured_lifecycle_pages::LifecycleData)->io::Result<T>)->io::Result<T>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|error|error.into_inner());let pending=self.with_workspace_code_pages_limit_locked(capture,scope,limit,|reader|reader.lifecycle_using(consume));match pending{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(io::Error::new(io::ErrorKind::Unsupported,message))}}}

impl WorkspaceCodeReader<'_,'_>{fn sys_loot_using<T>(&self,consume:impl FnOnce(&dq_analyze::captured_sys_loot_pages::LootData)->io::Result<T>)->Result<T,Failure>{self.sys_loot_using_report(|data,_,_|consume(data))}
 fn sys_loot_using_report<T>(&self,consume:impl FnOnce(&dq_analyze::captured_sys_loot_pages::LootData,&Config,&Arc<Budget>)->io::Result<T>)->Result<T,Failure>{self.require_sys_discovery()?;let meta=dq_analyze::captured_sys_loot_pages::metadata();let expected=dq_analyze::dm::sys::policy_selection();if meta.select.roots!=expected.roots||meta.select.hidden!=expected.hidden{return Err("Loot selected CODE_MAPS domain differs".into())}let(_,bytes)=self.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(width).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,config:&'a Config,passes:std::cell::Cell<usize>,completed:std::cell::RefCell<[Option<SysSelectionCompletion<'a,'capture,'scope>>;2]>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("Loot producer exceeded original two selected phases".into())}let token=self.reader.for_each_sys_selection(self.config,"sys/loot","sys",visit)?;let Some(token)=token else{return Ok(false)};self.reader.checkpoint()?;self.completed.borrow_mut()[pass]=Some(token);self.passes.set(pass+1);Ok(true)}}
 let pages=Pages{reader:self,config:&config,passes:std::cell::Cell::new(0),completed:std::cell::RefCell::new([None,None])};let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_sys_loot_pages::collect(&pages,&config,self.budget(),&poll)?;if pages.passes.get()!=2{return Err("Loot omitted original selected source phases".into())}for token in pages.completed.borrow_mut().iter_mut(){token.take().ok_or("Loot actual selected EOF absent")?.require()?;}self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;pending}}
impl QueryDb{pub(crate) fn with_workspace_sys_loot<T>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_loot_pages::LootData)->io::Result<T>)->io::Result<T>{self.with_workspace_sys_loot_limit(capture,scope,None,consume)}pub(crate) fn with_workspace_sys_loot_limit<T>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:Option<usize>,consume:impl FnOnce(&dq_analyze::captured_sys_loot_pages::LootData)->io::Result<T>)->io::Result<T>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|error|error.into_inner());let pending=self.with_workspace_code_pages_limit_locked(capture,scope,limit,|reader|reader.sys_loot_using(consume));match pending{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(io::Error::new(io::ErrorKind::Unsupported,message))}}}

// Hidden-inclusive CODE evidence for this concrete two-phase policy only.
struct InstanceListCompletion<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>}
impl InstanceListCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_instance_list_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{
 fn require_instance_list_discovery(&self)->Result<(),Failure>{self.checkpoint()?;if !self.capture.covers_instance_list(&mut|bytes|self.budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message)))?{return Err("instance-list requires actual complete hidden-inclusive CODE discovery".into())}self.checkpoint()}
 fn instance_list_using<R>(&self,consume:impl FnOnce(&dq_analyze::captured_instance_list_pages::InstanceListData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 self.require_instance_list_discovery()?;let selected=dq_analyze::instance_list_policy::META.select;if selected.roots!=&[("code","dm")]||!selected.hidden{return Err("instance-list hidden-inclusive source contract differs".into())}
 let(_,bytes)=self.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(width).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,config:&'a Config,passes:std::cell::Cell<usize>,completed:std::cell::RefCell<[Option<InstanceListCompletion<'a,'capture,'scope>>;2]>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("instance-list producer exceeded its actual two source phases".into())}self.reader.require_instance_list_discovery()?;let config=if pass==0{None}else{Some(self.config)};if !self.reader.for_each_file(FileDomain::InstanceList(config),visit)?{return Ok(false)}self.reader.require_instance_list_discovery()?;self.reader.checkpoint()?;self.completed.borrow_mut()[pass]=Some(InstanceListCompletion{reader:self.reader});self.passes.set(pass+1);Ok(true)}}
 let pages=Pages{reader:self,config:&config,passes:std::cell::Cell::new(0),completed:std::cell::RefCell::new([None,None])};let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_instance_list_pages::collect_from_pages(&pages,self.budget(),&poll)?;if pages.passes.get()!=2{return Err("instance-list omitted its actual source phases".into())}for token in pages.completed.borrow_mut().iter_mut(){token.take().ok_or("instance-list hidden-inclusive CODE EOF absent")?.require()?;}self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;pending
 }
}
impl QueryDb{pub(crate) fn with_workspace_instance_list<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_instance_list_pages::InstanceListData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{self.with_workspace_code_pages(capture,scope,|reader|reader.instance_list_using(consume))}
#[cfg(test)]pub(crate) fn with_workspace_instance_list_limit<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:usize,consume:impl FnOnce(&dq_analyze::captured_instance_list_pages::InstanceListData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;if !scope.uses_queries(self){return Err(Failure::Operational(invalid("instance-list source pages need actual current QueryDb")))}let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.with_workspace_code_pages_limit_locked(capture,scope,Some(limit),|reader|reader.instance_list_using(consume))}}

// One direct borrowed-original byte traversal. No decoded file or CODE view is
// substituted for the raw bytes required by errors=ignore cache policy.
struct CacheCompletion<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>}
impl CacheCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_instance_list_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{fn for_each_cache_original(&self,config:&Config,visit:&mut dyn FnMut(&str,&[u8])->Result<bool,Failure>)->Result<bool,Failure>{
 self.require_instance_list_discovery()?;for index in 0..self.capture.file_count(){self.checkpoint()?;let original_path=self.capture.path(index)?;let mut scratch=KeysOrderScratch::new(self.budget())?;let width=self.root().as_os_str().len().checked_add(original_path.as_os_str().len()).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(1024)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;scratch.budget.charge(width).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;
 let pending=(||{let path=dm_preprocess::regions::relative_filesystem_path(original_path,self.root()).ok_or("cache original path escapes current root")?;let relative=path.to_string_lossy().replace('\\',"/");if relative.capacity()>width{return Err(Failure::Operational(io::ErrorKind::OutOfMemory.into()))}if !dq_analyze::cache_policy::selects_path(&relative)||config.policy_path_exempt("cache","",&relative){return Ok(true)}let original=self.capture.original(index,self.scope)?;let bytes=match &original{crate::input_snapshot::RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()};visit(&relative,bytes)})();scratch.complete=pending.is_ok();drop(scratch);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;if !pending?{return Ok(false)}}self.require_instance_list_discovery()?;self.checkpoint()?;Ok(true)
 }
 fn cache_using<R>(&self,consume:impl FnOnce(&dq_analyze::captured_cache_bytes::CacheData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 self.require_instance_list_discovery()?;let meta=&dq_analyze::cache_policy::META;if meta.select.roots!=&[("code","dm")]||!meta.select.hidden{return Err("cache actual hidden-inclusive byte domain differs".into())}let(_,bytes)=self.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(width).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,config:&'a Config,completion:std::cell::RefCell<Option<CacheCompletion<'a,'capture,'scope>>>,begun:std::cell::Cell<bool>}
 impl dq_analyze::captured_cache_bytes::OriginalBytesPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,&[u8])->Result<bool,Failure>)->Result<bool,Failure>{if self.begun.replace(true){return Err("cache original-byte producer repeated its actual source phase".into())}self.reader.require_instance_list_discovery()?;if !self.reader.for_each_cache_original(self.config,visit)?{return Ok(false)}self.reader.require_instance_list_discovery()?;*self.completion.borrow_mut()=Some(CacheCompletion{reader:self.reader});Ok(true)}}
 let pages=Pages{reader:self,config:&config,completion:std::cell::RefCell::new(None),begun:std::cell::Cell::new(false)};let poll=||self.checkpoint().map_err(|f|match f{Failure::Operational(e)=>e,Failure::Unsupported(m)=>io::Error::new(io::ErrorKind::Unsupported,m)});let data=dq_analyze::captured_cache_bytes::collect(&pages,self.budget(),&poll)?;pages.completion.borrow_mut().take().ok_or("cache actual original-byte EOF absent")?.require()?;self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;pending
 }
}
impl QueryDb{pub(crate) fn with_workspace_cache<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_cache_bytes::CacheData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{self.with_workspace_code_pages(capture,scope,|reader|reader.cache_using(consume))}
#[cfg(test)]pub(crate) fn with_workspace_cache_limit<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:usize,consume:impl FnOnce(&dq_analyze::captured_cache_bytes::CacheData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;if !scope.uses_queries(self){return Err(Failure::Operational(invalid("cache original bytes need actual current QueryDb")))}let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.with_workspace_code_pages_limit_locked(capture,scope,Some(limit),|reader|reader.cache_using(consume))}}

impl WorkspaceCodeReader<'_,'_>{fn sys_ownership_forms_using<T>(&self,consume:impl FnOnce(&dq_analyze::captured_sys_ownership_forms_pages::OwnershipFormsData)->io::Result<T>)->Result<T,Failure>{self.sys_ownership_forms_using_report(|data,_,_|consume(data))}
 fn sys_ownership_forms_using_report<T>(&self,consume:impl FnOnce(&dq_analyze::captured_sys_ownership_forms_pages::OwnershipFormsData,&Config,&Arc<Budget>)->io::Result<T>)->Result<T,Failure>{self.require_sys_discovery()?;let meta=dq_analyze::captured_sys_ownership_forms_pages::metadata();let expected=dq_analyze::dm::sys::policy_selection();if meta.select.roots!=expected.roots||meta.select.hidden!=expected.hidden{return Err("Ownership-form selected CODE_MAPS domain differs".into())}let(_,bytes)=self.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(width).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,config:&'a Config,passes:std::cell::Cell<usize>,completed:std::cell::RefCell<[Option<SysSelectionCompletion<'a,'capture,'scope>>;2]>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("Ownership-form producer exceeded original two selected phases".into())}let token=self.reader.for_each_sys_selection(self.config,"sys/dx_ownership_forms","sys",visit)?;let Some(token)=token else{return Ok(false)};self.reader.checkpoint()?;self.completed.borrow_mut()[pass]=Some(token);self.passes.set(pass+1);Ok(true)}}
 let pages=Pages{reader:self,config:&config,passes:std::cell::Cell::new(0),completed:std::cell::RefCell::new([None,None])};let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_sys_ownership_forms_pages::collect(&pages,self.budget(),&poll)?;if pages.passes.get()!=2{return Err("Ownership-form omitted original selected source phases".into())}for token in pages.completed.borrow_mut().iter_mut(){token.take().ok_or("Ownership-form actual selected EOF absent")?.require()?;}self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;pending}}
impl QueryDb{pub(crate) fn with_workspace_sys_ownership_forms<T>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_ownership_forms_pages::OwnershipFormsData)->io::Result<T>)->io::Result<T>{self.with_workspace_sys_ownership_forms_limit(capture,scope,None,consume)}pub(crate) fn with_workspace_sys_ownership_forms_limit<T>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:Option<usize>,consume:impl FnOnce(&dq_analyze::captured_sys_ownership_forms_pages::OwnershipFormsData)->io::Result<T>)->io::Result<T>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|error|error.into_inner());let pending=self.with_workspace_code_pages_limit_locked(capture,scope,limit,|reader|reader.sys_ownership_forms_using(consume));match pending{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(io::Error::new(io::ErrorKind::Unsupported,message))}}}

struct ApiSourceCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>}
impl ApiSourceCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_full_code_discovery()?;self.reader.checkpoint()}}
struct ApiPages<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>,config:&'reader Config,completed:std::cell::RefCell<[Option<ApiSourceCompletion<'reader,'capture,'scope>>;3]>,passes:std::cell::Cell<usize>}
impl ApiPages<'_,'_,'_>{fn finish(&self)->Result<(),Failure>{if self.passes.get()!=3{return Err("API requires all three actual original phases".into())}for token in self.completed.borrow_mut().iter_mut(){token.take().ok_or("API original source did not reach actual EOF")?.require()?;}self.reader.checkpoint()}}
impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for ApiPages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let index=self.passes.get();if index>=3{return Err("API source exceeded its actual three phases".into())}self.reader.require_full_code_discovery()?;let domain=if index==0{FileDomain::Code}else{FileDomain::CodeSelected(self.config,"api","")};let complete=self.reader.for_each_file(domain,visit)?;self.passes.set(index+1);if complete{self.reader.require_full_code_discovery()?;self.completed.borrow_mut()[index]=Some(ApiSourceCompletion{reader:self.reader});}Ok(complete)}}
fn api_using<R>(reader:&WorkspaceCodeReader<'_,'_>,consume:impl FnOnce(&dq_analyze::captured_api_pages::ApiData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 reader.require_full_code_discovery()?;let meta=dq_analyze::captured_api_pages::metadata();if meta.select.roots!=dq_analyze::captured_raw_file::code_dm_roots()||meta.select.hidden!=dq_analyze::tree::CODE_DM.hidden{return Err("API actual source domain differs from registered Meta".into())}
 let(_,bytes)=reader.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;reader.budget().charge(width).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 let pages=ApiPages{reader,config:&config,completed:std::cell::RefCell::new([None,None,None]),passes:std::cell::Cell::new(0)};let poll=||reader.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>invalid(message)});let data=dq_analyze::captured_api_pages::collect(&pages,&config,reader.budget(),&poll)?;pages.finish()?;reader.checkpoint()?;let pending=consume(&data,&config,reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
}
impl QueryDb{
 pub(crate) fn with_workspace_api<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_api_pages::ApiData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{self.with_workspace_code_pages(capture,scope,|reader|api_using(reader,consume))}
 #[cfg(test)]pub(crate) fn with_workspace_api_limit<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:usize,consume:impl FnOnce(&dq_analyze::captured_api_pages::ApiData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;if !scope.uses_queries(self){return Err("API source needs actual current QueryDb".into())}let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.with_workspace_code_pages_limit_locked(capture,scope,Some(limit),|reader|api_using(reader,consume))}
}

struct FieldsPages<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>,config:&'reader Config,index:std::cell::RefCell<Option<ApiSourceCompletion<'reader,'capture,'scope>>>,selected:std::cell::RefCell<Option<SysSelectionCompletion<'reader,'capture,'scope>>>,passes:std::cell::Cell<usize>}
impl FieldsPages<'_,'_,'_>{fn finish(&self)->Result<(),Failure>{if self.passes.get()!=2{return Err("Sys fields requires both original source phases".into())}self.index.borrow_mut().take().ok_or("Sys fields actual CODE index did not reach EOF")?.require()?;self.selected.borrow_mut().take().ok_or("Sys fields actual selected CODE_MAPS source did not reach EOF")?.require()?;self.reader.checkpoint()}}
impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for FieldsPages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{match self.passes.get(){0=>{self.reader.require_full_code_discovery()?;let complete=self.reader.for_each_code_file(visit)?;self.passes.set(1);if complete{self.reader.require_full_code_discovery()?;*self.index.borrow_mut()=Some(ApiSourceCompletion{reader:self.reader});}Ok(complete)},1=>{self.reader.require_sys_discovery()?;let complete=self.reader.for_each_sys_selection(self.config,"sys/fields","sys",visit)?;self.passes.set(2);let ended=complete.is_some();*self.selected.borrow_mut()=complete;Ok(ended)},_=>Err("Sys fields source exceeded two actual phases".into())}}}
fn fields_using<R>(reader:&WorkspaceCodeReader<'_,'_>,consume:impl FnOnce(&dq_analyze::captured_sys_fields_pages::FieldData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{reader.require_full_code_discovery()?;reader.require_sys_discovery()?;let meta=dq_analyze::captured_sys_fields_pages::metadata();let actual=dq_analyze::dm::sys::policy_selection();if meta.select.roots!=actual.roots||meta.select.hidden!=actual.hidden{return Err("Sys fields actual source domain differs from registered Meta".into())}let(_,bytes)=reader.configuration();let peak=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or("Sys fields configuration bound overflow")?;reader.budget().charge(peak).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;let pages=FieldsPages{reader,config:&config,index:std::cell::RefCell::new(None),selected:std::cell::RefCell::new(None),passes:std::cell::Cell::new(0)};let poll=||reader.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>invalid(message)});let data=dq_analyze::captured_sys_fields_pages::collect(&pages,&config,reader.budget(),&poll)?;pages.finish()?;reader.checkpoint()?;let pending=consume(&data,&config,reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending}
impl QueryDb{pub(crate) fn with_workspace_fields<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_fields_pages::FieldData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{self.with_workspace_code_pages(capture,scope,|reader|fields_using(reader,consume))}}

impl QueryDb{#[cfg(test)]pub(crate) fn with_workspace_fields_limit<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:usize,consume:impl FnOnce(&dq_analyze::captured_sys_fields_pages::FieldData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;if !scope.uses_queries(self){return Err("Sys fields source needs actual current QueryDb".into())}let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.with_workspace_code_pages_limit_locked(capture,scope,Some(limit),|reader|fields_using(reader,consume))}}

struct AppearancePages<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>,config:&'reader Config,index:std::cell::RefCell<Option<ApiSourceCompletion<'reader,'capture,'scope>>>,selected:std::cell::RefCell<[Option<SysSelectionCompletion<'reader,'capture,'scope>>;3]>,passes:std::cell::Cell<usize>}
impl AppearancePages<'_,'_,'_>{fn finish(&self)->Result<(),Failure>{if self.passes.get()!=4{return Err("Appearance requires all four original source phases".into())}self.index.borrow_mut().take().ok_or("Appearance actual CODE index did not reach EOF")?.require()?;for completion in self.selected.borrow_mut().iter_mut(){completion.take().ok_or("Appearance actual selected schema/owning/judge did not reach EOF")?.require()?;}self.reader.checkpoint()}}
impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for AppearancePages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();match pass{0=>{self.reader.require_full_code_discovery()?;let complete=self.reader.for_each_code_file(visit)?;self.passes.set(1);if complete{self.reader.require_full_code_discovery()?;*self.index.borrow_mut()=Some(ApiSourceCompletion{reader:self.reader});}Ok(complete)},1..=3=>{self.reader.require_sys_discovery()?;let complete=self.reader.for_each_sys_selection(self.config,"sys/appearance","sys",visit)?;self.passes.set(pass+1);let ended=complete.is_some();self.selected.borrow_mut()[pass-1]=complete;Ok(ended)},_=>Err("Appearance source exceeded its actual four phases".into())}}}
fn appearance_using<R>(reader:&WorkspaceCodeReader<'_,'_>,consume:impl FnOnce(&dq_analyze::captured_sys_appearance_pages::AppearanceData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{reader.require_full_code_discovery()?;reader.require_sys_discovery()?;let meta=dq_analyze::captured_sys_appearance_pages::metadata();let actual=dq_analyze::dm::sys::policy_selection();if meta.select.roots!=actual.roots||meta.select.hidden!=actual.hidden{return Err("Appearance actual source domain differs from registered Meta".into())}let(_,bytes)=reader.configuration();let peak=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or("Appearance configuration bound overflow")?;reader.budget().charge(peak).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;let pages=AppearancePages{reader,config:&config,index:std::cell::RefCell::new(None),selected:std::cell::RefCell::new([None,None,None]),passes:std::cell::Cell::new(0)};let poll=||reader.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>invalid(message)});let data=dq_analyze::captured_sys_appearance_pages::collect(&pages,&config,reader.budget(),&poll)?;pages.finish()?;reader.checkpoint()?;let pending=consume(&data,&config,reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending}
impl QueryDb{pub(crate) fn with_workspace_appearance<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_appearance_pages::AppearanceData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{self.with_workspace_code_pages(capture,scope,|reader|appearance_using(reader,consume))}}

impl QueryDb{#[cfg(test)]pub(crate) fn with_workspace_appearance_limit<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,limit:usize,consume:impl FnOnce(&dq_analyze::captured_sys_appearance_pages::AppearanceData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;if !scope.uses_queries(self){return Err("Appearance source needs actual current QueryDb".into())}let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.with_workspace_code_pages_limit_locked(capture,scope,Some(limit),|reader|appearance_using(reader,consume))}}

/// A token can only be constructed after the actual requested domain loop completes.
struct RawTreeCompletion<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,policy:dq_analyze::captured_raw_tree_pages::Policy,phase:usize}
impl RawTreeCompletion<'_,'_,'_>{fn require(self,policy:dq_analyze::captured_raw_tree_pages::Policy,phase:usize)->Result<(),Failure>{if self.policy!=policy||self.phase!=phase{return Err("raw tree completed phase differs".into())}self.reader.require_raw_tree_discovery(policy)}}
impl WorkspaceCodeReader<'_,'_>{fn require_raw_tree_discovery(&self,policy:dq_analyze::captured_raw_tree_pages::Policy)->Result<(),Failure>{self.checkpoint()?;if !self.capture.covers_raw_tree_policy(policy,&mut|bytes|self.budget.charge(bytes).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m)))?{return Err("raw tree policy requires its complete actual registered Select discovery".into())}self.checkpoint()}}
struct RawTreePages<'a,'capture,'scope>{ui_proof:Option<&'a Arc<UiInputProof>>,reader:&'a WorkspaceCodeReader<'capture,'scope>,config:&'a Config,policy:dq_analyze::captured_raw_tree_pages::Policy,passes:std::cell::Cell<usize>,completed:std::cell::RefCell<[Option<RawTreeCompletion<'a,'capture,'scope>>;3]>}
impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for RawTreePages<'_,'_,'_>{fn with_op_order_manifest(&self,visit:&mut dyn FnMut(Option<&[u8]>)->Result<(),Failure>)->Result<(),Failure>{if self.policy!=dq_analyze::captured_raw_tree_pages::Policy::OpOrder{return Err("op_order fixed manifest asked under another raw purpose".into())}self.reader.checkpoint()?;self.reader.capture.with_op_order_manifest(self.reader.scope,|original|visit(original))}fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let phase=self.passes.get();if phase>=self.policy.source_visits(){return Err("raw tree original provider exceeded its actual policy phases".into())}self.reader.require_raw_tree_discovery(self.policy)?;let selected=self.policy.selected_source_phase(phase);let ended=self.reader.for_each_file(FileDomain::RawTree(self.config,self.policy,selected),visit)?;self.passes.set(phase+1);if ended{self.reader.require_raw_tree_discovery(self.policy)?;self.completed.borrow_mut()[phase]=Some(RawTreeCompletion{reader:self.reader,policy:self.policy,phase});if phase==0&&self.policy==dq_analyze::captured_raw_tree_pages::Policy::UiActions{self.ui_proof.ok_or("UI actual source pass has no private EOF proof")?.complete.store(true,Ordering::Release);}}Ok(ended)}}
impl RawTreePages<'_,'_,'_>{fn finish(self)->Result<(),Failure>{if self.passes.get()!=self.policy.source_visits(){return Err("raw tree policy omitted an actual source phase".into())}for(phase,token)in self.completed.into_inner().into_iter().enumerate().take(self.policy.source_visits()){token.ok_or("raw tree actual source EOF proof absent")?.require(self.policy,phase)?}self.reader.checkpoint()}}
fn raw_tree_using<R>(reader:&WorkspaceCodeReader<'_,'_>,policy:dq_analyze::captured_raw_tree_pages::Policy,consume:impl FnOnce(&dq_analyze::captured_raw_tree_pages::Data,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{reader.require_raw_tree_discovery(policy)?;if policy.metadata().name!=policy.name(){return Err("raw tree actual registered metadata differs".into())}let borrowed=if policy==dq_analyze::captured_raw_tree_pages::Policy::UiActions{reader.capture.productive_ui_configuration()?}else{reader.capture.productive_doc_configuration()?};let owned;let config=if let Some(config)=borrowed{config}else{let(_,bytes)=reader.configuration();let peak=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or("raw tree configuration bound overflow")?;reader.budget().charge(peak).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;owned=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;&owned};if policy==dq_analyze::captured_raw_tree_pages::Policy::UiActions{return ui_actions_using(reader,config,consume)}let pages=RawTreePages{ui_proof:None,reader,config:&config,policy,passes:std::cell::Cell::new(0),completed:std::cell::RefCell::new([None,None,None])};let poll=||reader.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>invalid(message)});let data=dq_analyze::captured_raw_tree_pages::collect(&pages,policy,&config,reader.budget(),&poll)?;pages.finish()?;reader.checkpoint()?;let pending=consume(&data,&config,reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending}
impl QueryDb{pub(crate) fn with_workspace_raw_tree<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,policy:dq_analyze::captured_raw_tree_pages::Policy,consume:impl FnOnce(&dq_analyze::captured_raw_tree_pages::Data,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{self.with_workspace_code_pages(capture,scope,|reader|raw_tree_using(reader,policy,consume))}
#[cfg(test)]pub(crate) fn with_workspace_raw_tree_limit<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,policy:dq_analyze::captured_raw_tree_pages::Policy,limit:usize,consume:impl FnOnce(&dq_analyze::captured_raw_tree_pages::Data,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;if !scope.uses_queries(self){return Err("raw tree source needs actual current QueryDb".into())}let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.with_workspace_code_pages_limit_locked(capture,scope,Some(limit),|reader|raw_tree_using(reader,policy,consume))}}

impl QueryDb{pub(crate) fn with_workspace_fold_report<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,policy:dq_analyze::workspace_fold_policy::Policy,consume:impl FnOnce(dq_analyze::workspace_fold_policy::Data<'_>,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{use dq_analyze::workspace_fold_policy::{Policy as P,Data as D};self.with_workspace_code_pages(capture,scope,|reader|match policy{P::StateSchema=>reader.state_schema_using_report(|data,config,budget|consume(D::StateSchema(data),config,budget)),P::Lifecycle=>reader.lifecycle_using_report(|data,config,budget|consume(D::Lifecycle(data),config,budget)),P::Loot=>reader.sys_loot_using_report(|data,config,budget|consume(D::Loot(data),config,budget)),P::OwnershipForms=>reader.sys_ownership_forms_using_report(|data,config,budget|consume(D::OwnershipForms(data),config,budget)),P::InstanceList=>reader.instance_list_using(|data,config,budget|consume(D::InstanceList(data),config,budget)),P::Cache=>reader.cache_using(|data,config,budget|consume(D::Cache(data),config,budget)),P::Api=>api_using(reader,|data,config,budget|consume(D::Api(data),config,budget)),P::Fields=>fields_using(reader,|data,config,budget|consume(D::Fields(data),config,budget)),P::Appearance=>appearance_using(reader,|data,config,budget|consume(D::Appearance(data),config,budget)),P::AllowAnnotations=>allow_annotations_using(reader,|data,config,budget|consume(D::AllowAnnotations(data),config,budget)),P::Tracked|P::TrackedTests=>Err("tracked policy requires its actual selected semantic child".into())})}}
// A distinct hidden-inclusive CODE completion for the original decl policy.
struct DeclCompletion<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>}
impl DeclCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_decl_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{
 fn require_decl_discovery(&self)->Result<(),Failure>{self.checkpoint()?;let meta=dq_analyze::captured_decl_pages::metadata();if meta.select.roots!=&[("code","dm")]||!meta.select.hidden{return Err("decl metadata differs from original hidden-inclusive CODE".into())}if !self.capture.covers_decl(&mut|bytes|self.budget.charge(bytes).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m)))?{return Err("decl requires actual complete hidden-inclusive CODE discovery".into())}self.checkpoint()}
 pub(crate) fn decl_using<R>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,consume:impl FnOnce(&dq_analyze::captured_decl_pages::DeclData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 self.require_policy_inputs(inputs)?;self.require_decl_discovery()?;let(_,bytes)=self.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(width).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,inputs:&'a dm_analysis::policy_inputs::PolicyInputs,config:&'a Config,passes:std::cell::Cell<usize>,completed:std::cell::RefCell<[Option<DeclCompletion<'a,'capture,'scope>>;2]>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("decl producer exceeded its two source phases".into())}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_decl_discovery()?;if !self.reader.for_each_file(FileDomain::Decl(if pass==0{None}else{Some(self.config)}),visit)?{return Ok(false)}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_decl_discovery()?;self.completed.borrow_mut()[pass]=Some(DeclCompletion{reader:self.reader});self.passes.set(pass+1);Ok(true)}}
 let pages=Pages{reader:self,inputs,config:&config,passes:std::cell::Cell::new(0),completed:std::cell::RefCell::new([None,None])};let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_decl_pages::collect_from_pages(inputs,self.root(),&pages,&config,self.budget(),&poll)?;if pages.passes.get()!=2{return Err("decl omitted an actual original source phase".into())}for token in pages.completed.borrow_mut().iter_mut(){token.take().ok_or("decl hidden-inclusive CODE EOF absent")?.require()?;}self.require_policy_inputs(inputs)?;self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;self.checkpoint()?;pending
 }
}

// A distinct hidden-inclusive CODE completion for the original init policy.
struct InitCompletion<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>}
impl InitCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_init_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{
 fn require_init_discovery(&self)->Result<(),Failure>{self.checkpoint()?;let meta=dq_analyze::captured_init_pages::metadata();if meta.select.roots!=&[("code","dm"),("maps","dm")]||!meta.select.hidden{return Err("init metadata differs from original hidden-inclusive CODE".into())}if !self.capture.covers_init(&mut|bytes|self.budget.charge(bytes).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m)))?{return Err("init requires actual complete hidden-inclusive CODE discovery".into())}self.checkpoint()}
 pub(crate) fn init_using<R>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,consume:impl FnOnce(&dq_analyze::captured_init_pages::InitData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 self.require_policy_inputs(inputs)?;self.require_init_discovery()?;let(_,bytes)=self.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(width).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,inputs:&'a dm_analysis::policy_inputs::PolicyInputs,config:&'a Config,passes:std::cell::Cell<usize>,completed:std::cell::RefCell<[Option<InitCompletion<'a,'capture,'scope>>;2]>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("init producer exceeded its two source phases".into())}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_init_discovery()?;if !self.reader.for_each_file(FileDomain::Init(if pass==0{Some(self.config)}else{None}),visit)?{return Ok(false)}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_init_discovery()?;self.completed.borrow_mut()[pass]=Some(InitCompletion{reader:self.reader});self.passes.set(pass+1);Ok(true)}}
 let pages=Pages{reader:self,inputs,config:&config,passes:std::cell::Cell::new(0),completed:std::cell::RefCell::new([None,None])};let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_init_pages::collect_from_pages(inputs,self.root(),&pages,&config,self.budget(),&poll)?;if pages.passes.get()!=2{return Err("init omitted an actual original source phase".into())}for token in pages.completed.borrow_mut().iter_mut(){token.take().ok_or("init hidden-inclusive CODE EOF absent")?.require()?;}self.require_policy_inputs(inputs)?;self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;self.checkpoint()?;pending
 }
}

struct BaseVarsCompletion<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>}
impl BaseVarsCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_base_vars_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{
 fn require_base_vars_discovery(&self)->Result<(),Failure>{self.checkpoint()?;let meta=dq_analyze::captured_base_vars_pages::metadata();if meta.select.roots!=&[("code","dm")]||!meta.select.hidden{return Err("base-vars original hidden CODE metadata differs".into())}if !self.capture.covers_base_vars(&mut|bytes|self.budget.charge(bytes).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m)))?{return Err("base-vars requires actual complete hidden-inclusive CODE discovery".into())}self.checkpoint()}
 fn with_base_vars_record_line(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,member:dm_tree::MemberId,visit:&mut dyn FnMut(&str,usize,&str)->Result<(),Failure>)->Result<(),Failure>{
 self.require_policy_inputs(inputs)?;let archive=inputs.archive();let tree=archive.tree();let ordinal=archive.callables().ordinal(member).ok_or("record header has no actual callable ordinal")?;let occurrence=archive.occurrences().get(ordinal).filter(|row|row.member==member).ok_or("record header differs from actual authored occurrence")?;let node=tree.member(member).ok_or("record header has no actual member")?;if !matches!(node.kind,dm_tree::MemberKind::Proc|dm_tree::MemberKind::Verb){return Err("record header is not a callable".into())}let owner=tree.type_node(node.owner).and_then(|ty|tree.symbols().text(ty.path)).ok_or("record owner unavailable")?;if owner!="/datum/record"&&!owner.starts_with("/datum/record/"){return Err("required header is outside original lexical record domain".into())}let _=occurrence;
 let origin=archive.callable_header_policy_line(member)?;let source=inputs.file_exact(origin.path.as_path()).ok_or("record header lacks its actual source input")?;let line=source.analyze_display_line(origin.line).map_err(|error|Failure::Unsupported(error.to_string()))?;let mut acquired=None;for(index,(path,lease))in inputs.mapping().source_acquisitions().enumerate(){self.checkpoint()?;if path==origin.path.as_path(){acquired=Some((index,lease));break}}let(index,lease)=acquired.ok_or("record header source acquisition absent")?;let lease=lease.ok_or("record header original acquisition unavailable")?;let original=self.scope.original(index,&lease.identity())?;
 let scratch=Budget::scoped_temporaries(&self.budget).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;struct Guard<'a>{budget:&'a Budget,ok:bool}impl Drop for Guard<'_>{fn drop(&mut self){if !self.ok{self.budget.keep_failed_scratch()}}}let mut guard=Guard{budget:&scratch,ok:false};let pending=(||{
 self.checkpoint()?;let raw=match &original{crate::input_snapshot::RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()};let width=raw.len().checked_mul(8).and_then(|n|n.checked_add(origin.path.as_os_str().len().checked_add(self.root().as_os_str().len())?.checked_mul(128)?)).and_then(|n|n.checked_add(8192)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;scratch.charge(width).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let text=crate::input_snapshot::normalize_recorded_policy_original(&original);let target=line.checked_sub(1).ok_or("record original header line absent")?;let mut selected=None;for(index,current)in text.as_str().split('\n').enumerate(){self.checkpoint()?;if index==target{selected=Some(current);break}}let line_text=selected.ok_or("record original header line absent")?;let relative=dm_preprocess::regions::relative_filesystem_path(origin.path.as_path(),self.root());let label=dq_analyze::util::normalize_dots(&relative.as_deref().unwrap_or(origin.path.as_path()).to_string_lossy().replace('\\',"/"));visit(&label,line,line_text)
 })();if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;guard.ok=pending.is_ok();pending
 }
 fn with_base_vars_configuration_line(&self,visit:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<(),Failure>{self.checkpoint()?;let scratch=Budget::scoped_temporaries(&self.budget).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let pending=self.capture.with_base_vars_configuration(self.scope,|bytes|{self.checkpoint()?;let Some(bytes)=bytes else{return visit("")};let Ok(text)=std::str::from_utf8(bytes)else{return visit("")};scratch.charge(text.len().checked_mul(8).and_then(|n|n.checked_add(4096)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let normalized=if text.contains('\r'){std::borrow::Cow::Owned(text.replace("\r\n","\n").replace('\r',"\n"))}else{std::borrow::Cow::Borrowed(text)};visit(normalized.split('\n').next().unwrap_or(""))});if pending.is_err(){scratch.keep_failed_scratch()}if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;pending}
 pub(crate) fn base_vars_using<R>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,consume:impl FnOnce(&dq_analyze::captured_base_vars_pages::BaseVarsData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 self.require_policy_inputs(inputs)?;self.require_base_vars_discovery()?;let(_,bytes)=self.configuration();let width=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(width).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,inputs:&'a dm_analysis::policy_inputs::PolicyInputs,passes:std::cell::Cell<usize>,completed:std::cell::RefCell<[Option<BaseVarsCompletion<'a,'capture,'scope>>;2]>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("base-vars exceeded its two source phases".into())}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_base_vars_discovery()?;if !self.reader.for_each_file(FileDomain::BaseVars,visit)?{return Ok(false)}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_base_vars_discovery()?;self.completed.borrow_mut()[pass]=Some(BaseVarsCompletion{reader:self.reader});self.passes.set(pass+1);Ok(true)}}
 impl dq_analyze::captured_base_vars_pages::BaseVarPages for Pages<'_,'_,'_>{fn with_record_line(&self,member:dm_tree::MemberId,visit:&mut dyn FnMut(&str,usize,&str)->Result<(),Failure>)->Result<(),Failure>{self.reader.with_base_vars_record_line(self.inputs,member,visit)}fn with_fixed_configuration_line(&self,visit:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<(),Failure>{self.reader.with_base_vars_configuration_line(visit)}}
 let pages=Pages{reader:self,inputs,passes:std::cell::Cell::new(0),completed:std::cell::RefCell::new([None,None])};let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_base_vars_pages::collect_from_pages(inputs,self.root(),&pages,&config,self.budget(),&poll)?;if pages.passes.get()!=2{return Err("base-vars omitted an actual hidden CODE phase".into())}for token in pages.completed.borrow_mut().iter_mut(){token.take().ok_or("base-vars hidden CODE EOF missing")?.require()?;}self.require_policy_inputs(inputs)?;self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;self.checkpoint()?;pending
 }
}

// Only this concrete full requirement-bool producer consumes these two selected
// CODE EOF receipts. Body parsing is the same current archive/QueryDb borrower.
struct RequirementCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>}
impl RequirementCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_full_code_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{pub(crate) fn requirement_bool_using<R>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,consume:impl FnOnce(&dq_analyze::captured_requirement_bool_pages::RequirementData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;let meta=dq_analyze::captured_requirement_bool_pages::metadata();let selected=dq_analyze::tree::CODE_DM;if meta.select.roots!=selected.roots||meta.select.hidden!=selected.hidden{return Err("requirement original CODE selection differs".into())}let(_,bytes)=self.configuration();let peak=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(peak).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,inputs:&'a dm_analysis::policy_inputs::PolicyInputs,config:&'a Config,passes:std::cell::Cell<usize>,completed:std::cell::RefCell<[Option<RequirementCompletion<'a,'capture,'scope>>;2]>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("requirement producer exceeded its original two selected CODE phases".into())}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;if !self.reader.for_each_file(FileDomain::CodeSelected(self.config,"requirement_bool",""),visit)?{return Ok(false)}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;self.completed.borrow_mut()[pass]=Some(RequirementCompletion{reader:self.reader});self.passes.set(pass+1);Ok(true)}}
 let pages=Pages{reader:self,inputs,config:&config,passes:std::cell::Cell::new(0),completed:std::cell::RefCell::new([None,None])};let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_requirement_bool_pages::collect_from_pages(inputs,self.root(),&pages,&config,self.budget(),&poll)?;if pages.passes.get()!=2{return Err("requirement producer omitted an actual selected CODE phase".into())}for token in pages.completed.borrow_mut().iter_mut(){token.take().ok_or("requirement actual selected CODE EOF absent")?.require()?;}self.require_policy_inputs(inputs)?;self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;self.checkpoint()?;pending
}}

// Original player-link observes all issued proc bodies, including non-CODE
// members. The complete Original Analyze subject is checked by its endpoint;
// this distinct CODE EOF guards the raw workspace/current source closure only.
struct PlayerCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>}
impl PlayerCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_full_code_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{pub(crate) fn player_link_using<R>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,consume:impl FnOnce(&dq_analyze::captured_player_link_pages::PlayerData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;if !self.for_each_file(FileDomain::Code,&mut|_,views|{self.checkpoint()?;let _=views.raw()?;self.checkpoint()?;Ok(true)})?{return Err("player-link current CODE closure EOF absent".into())}let complete=PlayerCompletion{reader:self};complete.require()?;
 let(_,bytes)=self.configuration();let peak=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(peak).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_player_link_pages::collect(inputs,self.root(),&config,self.budget(),&poll)?;self.require_policy_inputs(inputs)?;self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;self.checkpoint()?;pending
}}

struct MemberCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>}
impl MemberCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_full_code_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{pub(crate) fn untyped_member_using<R>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,consume:impl FnOnce(&dq_analyze::captured_untyped_member_pages::MemberData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;if !self.for_each_file(FileDomain::Code,&mut|_,views|{self.checkpoint()?;let _=views.raw()?;self.checkpoint()?;Ok(true)})?{return Err("untyped-member current CODE closure EOF absent".into())}let complete=MemberCompletion{reader:self};complete.require()?;
 let(_,bytes)=self.configuration();let peak=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(peak).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;let poll=||self.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_untyped_member_pages::collect(inputs,self.root(),&config,self.budget(),&poll)?;self.require_policy_inputs(inputs)?;self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;self.checkpoint()?;pending
}}

struct WeakCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>}
impl WeakCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_full_code_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{pub(crate) fn weak_raw_read_using<R>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,consume:impl FnOnce(&dq_analyze::captured_weak_raw_read_pages::WeakData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;let meta=dq_analyze::weak_relation_policy::metadata();let code=dq_analyze::tree::CODE_DM;if meta.select.roots!=code.roots||meta.select.hidden!=code.hidden{return Err("weak original CODE declaration selection differs".into())}let(_,bytes)=self.configuration();let peak=bytes.map_or(Some(1024),|b|b.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(peak).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,inputs:&'a dm_analysis::policy_inputs::PolicyInputs,config:&'a Config,completed:std::cell::RefCell<Option<WeakCompletion<'a,'capture,'scope>>>,used:std::cell::Cell<bool>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{if self.used.replace(true){return Err("weak producer exceeded original single declaration phase".into())}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;if !self.reader.for_each_file(FileDomain::CodeSelected(self.config,"weak_raw_read",""),visit)?{return Ok(false)}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;*self.completed.borrow_mut()=Some(WeakCompletion{reader:self.reader});Ok(true)}}
 let pages=Pages{reader:self,inputs,config:&config,completed:std::cell::RefCell::new(None),used:std::cell::Cell::new(false)};let poll=||self.checkpoint().map_err(|f|match f{Failure::Operational(actual)=>actual,Failure::Unsupported(m)=>io::Error::new(io::ErrorKind::Unsupported,m)});let data=dq_analyze::captured_weak_raw_read_pages::collect_from_pages(inputs,self.root(),&pages,&config,self.budget(),&poll)?;pages.completed.borrow_mut().take().ok_or("weak actual selected CODE EOF absent")?.require()?;self.require_policy_inputs(inputs)?;self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;self.checkpoint()?;pending
}}

struct RelationCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>}
impl RelationCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_full_code_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{pub(crate) fn rel_write_undeclared_using<R>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,consume:impl FnOnce(&dq_analyze::captured_rel_write_pages::RelationData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;let meta=dq_analyze::rel_write_policy::metadata();let code=dq_analyze::tree::CODE_DM;if meta.select.roots!=code.roots||meta.select.hidden!=code.hidden{return Err("weak original CODE declaration selection differs".into())}let(_,bytes)=self.configuration();let peak=bytes.map_or(Some(1024),|b|b.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(peak).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,inputs:&'a dm_analysis::policy_inputs::PolicyInputs,config:&'a Config,completed:std::cell::RefCell<[Option<RelationCompletion<'a,'capture,'scope>>;2]>,passes:std::cell::Cell<usize>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("relation producer exceeded its declaration and path phases".into())}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;if !self.reader.for_each_file(if pass==0{FileDomain::Code}else{FileDomain::CodeSelected(self.config,"rel_write_undeclared","")},visit)?{return Ok(false)}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;self.completed.borrow_mut()[pass]=Some(RelationCompletion{reader:self.reader});self.passes.set(pass+1);Ok(true)}}
 let pages=Pages{reader:self,inputs,config:&config,completed:std::cell::RefCell::new([None,None]),passes:std::cell::Cell::new(0)};let poll=||self.checkpoint().map_err(|f|match f{Failure::Operational(actual)=>actual,Failure::Unsupported(m)=>io::Error::new(io::ErrorKind::Unsupported,m)});let data=dq_analyze::captured_rel_write_pages::collect_from_pages(inputs,self.root(),&pages,&config,self.budget(),&poll)?;if pages.passes.get()!=2{return Err("relation omitted an actual raw phase".into())}for token in pages.completed.borrow_mut().iter_mut(){token.take().ok_or("relation actual CODE EOF absent")?.require()?;}self.require_policy_inputs(inputs)?;self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;self.checkpoint()?;pending
}}

struct CurrentUntypedBodies<'reader, 'capture, 'scope> {
    reader: &'reader WorkspaceCodeReader<'capture, 'scope>,
    inputs: &'reader dm_analysis::policy_inputs::PolicyInputs,
}
impl dq_analyze::captured_untyped_pages::CurrentBodyLoan for CurrentUntypedBodies<'_, '_, '_> {
    fn visit_body<'a>(
        &self, archive: &'a dm_tree::frontend::BodyArchive, ordinal: usize,
        consume: &mut dyn for<'p, 'budget> FnMut(
            dm_tree::frontend::CurrentArchivedBody<'a, 'p>, &dm_syntax::SettingAdmission<'budget>,
        ) -> Result<(), Failure>,
    ) -> Result<(), Failure> {
        use dm_tree::frontend::BodySyntaxFailure;
        self.reader.require_policy_inputs(self.inputs)?;
        if !std::ptr::eq(self.inputs.archive().as_ref(), archive) {
            return Err("Untyped current BODY loan differs from its actual semantic archive".into());
        }
        // This is outside the value-proof Ctx. The archive's actual query
        // host obtains the same canonical Kind4 product through the flat API.
        let mut unsupported = None;
        self.reader.db.with_setting_admission(|admission| {
            archive.with_current_body_checked(ordinal, admission, |body| {
                match consume(body, admission) {
                    Ok(()) => Ok(()),
                    Err(Failure::Operational(actual)) => Err(BodySyntaxFailure::Operational(actual)),
                    Err(Failure::Unsupported(actual)) => { unsupported = Some(actual); Ok(()) }
                }
            })
        }).map_err(dq_analyze::captured_untyped_pages::body_failure)?;
        if let Some(actual) = unsupported { return Err(Failure::Unsupported(actual)); }
        self.reader.require_policy_inputs(self.inputs)?;
        self.reader.checkpoint()
    }
}

struct UntypedCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>}
impl UntypedCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_full_code_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{pub(crate) fn untyped_using<R>(&self,capture:&crate::runner_host::policy_capture::CapturedPolicyInputs,canonical:bool,consume:impl FnOnce(&dq_analyze::captured_untyped_pages::UntypedData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 let inputs=capture.policy();self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;let meta=dq_analyze::untyped_policy_metadata::metadata();let code=dq_analyze::tree::CODE_DM;if meta.select.roots!=code.roots||meta.select.hidden!=code.hidden{return Err("weak original CODE declaration selection differs".into())}let(_,bytes)=self.configuration();let peak=bytes.map_or(Some(1024),|b|b.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(peak).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 let empty=dq_analyze::scopes::LintScope::default();let current_scope=config.borrowed_report_scope("untyped","").unwrap_or(&empty);self.checkpoint()?;let value_input=capture.untyped_input_mode(current_scope.list("exempt_types"),canonical).map_err(Failure::Operational)?;let proof=dm_analysis::value_query::ArchiveValueQueries::value_proof_checked(self.db,&value_input).map_err(|e|match e{dm_analysis::value_query::ValueQueryFailure::Operational(actual)=>Failure::Operational(actual),dm_analysis::value_query::ValueQueryFailure::Unsupported(error)=>Failure::Unsupported(error.0),dm_analysis::value_query::ValueQueryFailure::Syntax(error)=>Failure::Unsupported(error.message)})?;let manifest=capture.untyped_manifest(self.root()).map_err(Failure::Operational)?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,inputs:&'a dm_analysis::policy_inputs::PolicyInputs,config:&'a Config,completed:std::cell::RefCell<[Option<UntypedCompletion<'a,'capture,'scope>>;2]>,passes:std::cell::Cell<usize>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("untyped producer exceeded schema and source-report phases".into())}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;if !self.reader.for_each_file(if pass==0{FileDomain::Code}else{FileDomain::CodeSelected(self.config,"untyped","")},visit)?{return Ok(false)}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;self.completed.borrow_mut()[pass]=Some(UntypedCompletion{reader:self.reader});self.passes.set(pass+1);Ok(true)}}
 let pages=Pages{reader:self,inputs,config:&config,completed:std::cell::RefCell::new([None,None]),passes:std::cell::Cell::new(0)};let poll=||self.checkpoint().map_err(|f|match f{Failure::Operational(actual)=>actual,Failure::Unsupported(m)=>io::Error::new(io::ErrorKind::Unsupported,m)});let bodies=CurrentUntypedBodies{reader:self,inputs};let current=value_input.requires_canonical_bodies().then_some(&bodies as &dyn dq_analyze::captured_untyped_pages::CurrentBodyLoan);let data=dq_analyze::captured_untyped_pages::collect_from_pages(inputs,&value_input,proof,manifest,self.root(),&pages,&config,self.budget(),&poll,current)?;if pages.passes.get()!=2{return Err("relation omitted an actual raw phase".into())}for token in pages.completed.borrow_mut().iter_mut(){token.take().ok_or("relation actual CODE EOF absent")?.require()?;}self.require_policy_inputs(inputs)?;self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;self.checkpoint()?;pending
}}

struct StoredRefsCompletion<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>}
impl StoredRefsCompletion<'_,'_,'_>{fn require(self)->Result<(),Failure>{self.reader.require_full_code_discovery()?;self.reader.checkpoint()}}
impl WorkspaceCodeReader<'_,'_>{pub(crate) fn stored_refs_using<R>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,consume:impl FnOnce(&dq_analyze::captured_stored_refs_pages::StoredData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;let meta=dq_analyze::stored_refs_policy::metadata();let code=dq_analyze::tree::CODE_DM;if meta.select.roots!=code.roots||meta.select.hidden!=code.hidden{return Err("weak original CODE declaration selection differs".into())}let(_,bytes)=self.configuration();let peak=bytes.map_or(Some(1024),|b|b.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;self.budget().charge(peak).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
 struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,inputs:&'a dm_analysis::policy_inputs::PolicyInputs,config:&'a Config,completed:std::cell::RefCell<[Option<StoredRefsCompletion<'a,'capture,'scope>>;2]>,passes:std::cell::Cell<usize>}
 impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("stored_refs producer exceeded raw facts and ALLOW/source-report phases".into())}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;if !self.reader.for_each_file(if pass==0{FileDomain::Code}else{FileDomain::CodeSelected(self.config,"stored_refs","")},visit)?{return Ok(false)}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;self.completed.borrow_mut()[pass]=Some(StoredRefsCompletion{reader:self.reader});self.passes.set(pass+1);Ok(true)}}
 let pages=Pages{reader:self,inputs,config:&config,completed:std::cell::RefCell::new([None,None]),passes:std::cell::Cell::new(0)};let poll=||self.checkpoint().map_err(|f|match f{Failure::Operational(actual)=>actual,Failure::Unsupported(m)=>io::Error::new(io::ErrorKind::Unsupported,m)});let data=dq_analyze::captured_stored_refs_pages::collect_from_pages(inputs,self.root(),&pages,&config,self.budget(),&poll)?;if pages.passes.get()!=2{return Err("relation omitted an actual raw phase".into())}for token in pages.completed.borrow_mut().iter_mut(){token.take().ok_or("relation actual CODE EOF absent")?.require()?;}self.require_policy_inputs(inputs)?;self.checkpoint()?;let pending=consume(&data,&config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);drop(config);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;self.checkpoint()?;pending
}}

impl WorkspaceCodeReader<'_,'_>{
 pub(crate) fn engine_layering_using<R>(&self,layer:dq_analyze::engine_layering_policy::Layer,inputs:&dm_analysis::policy_inputs::PolicyInputs,config:&Config,consume:impl FnOnce(&dq_analyze::captured_engine_layering_pages::LayeringData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
  self.layering_using(layer,inputs,config,false,consume)
 }

 pub(crate) fn library_layering_selected_union_using<R>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,consume:impl FnOnce(&dq_analyze::captured_engine_layering_pages::LayeringData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
  self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;
  let (_,bytes)=self.configuration();
  let bound=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
  self.budget().charge(bound).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
  self.layering_using(dq_analyze::engine_layering_policy::Layer::Library,inputs,&config,true,consume)
 }

 fn layering_using<R>(&self,layer:dq_analyze::engine_layering_policy::Layer,inputs:&dm_analysis::policy_inputs::PolicyInputs,config:&Config,allow_empty_selection:bool,consume:impl FnOnce(&dq_analyze::captured_engine_layering_pages::LayeringData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
  self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;
  struct Names<'a,'capture,'scope>(&'a WorkspaceCodeReader<'capture,'scope>);
  impl dq_analyze::captured_engine_layering_pages::PathPages for Names<'_,'_,'_>{fn for_each_path(&self,visit:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<bool,Failure>{let mut failure=None;let pending=self.0.capture.for_each_engine_path(self.0.scope,&mut|n|self.0.budget.charge(n).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m)),&mut|path|match visit(path){Ok(())=>Ok(()),Err(Failure::Operational(e))=>Err(e),Err(e)=>{failure=Some(e);Err(io::Error::new(io::ErrorKind::Unsupported,"engine path callback refused"))}});if let Some(actual)=failure{return Err(actual)}pending?;Ok(true)}}
  struct Pages<'a,'capture,'scope>{reader:&'a WorkspaceCodeReader<'capture,'scope>,inputs:&'a dm_analysis::policy_inputs::PolicyInputs,config:&'a Config,layer:dq_analyze::engine_layering_policy::Layer,passes:std::cell::Cell<usize>}
  impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("engine source exceeded provenance/marker phases".into())}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;let ended=self.reader.for_each_file(if pass==0{FileDomain::Code}else{FileDomain::EngineMarker(self.config,self.layer)},visit)?;if !ended{return Ok(false)}self.reader.require_policy_inputs(self.inputs)?;self.reader.require_full_code_discovery()?;self.passes.set(pass+1);Ok(true)}}
  let poll=||self.checkpoint().map_err(|f|match f{Failure::Operational(actual)=>actual,Failure::Unsupported(m)=>io::Error::new(io::ErrorKind::Unsupported,m)});let selection=dq_analyze::captured_engine_layering_pages::preflight_for(layer,&Names(self),config,self.budget(),&poll)?;if selection.is_empty(){
   if !allow_empty_selection{return Err("nonempty Original engine model route cannot certify metadata-only completion".into())}
   // Only the selected union reaches this branch, inside its already issued
   // complete model. The exact same actual path producer has proved emptiness.
   let data=dq_analyze::captured_engine_layering_pages::finish_unselected_ref(&selection,self.budget(),&poll)?;
   self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;self.checkpoint()?;
   let pending=consume(&data,config,self.budget()).map_err(Failure::Operational);
   if matches!(&pending,Err(Failure::Operational(_))){return pending}
   self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;self.checkpoint()?;
   return pending
  }
  let pages=Pages{reader:self,inputs,config,layer,passes:std::cell::Cell::new(0)};let data=dq_analyze::captured_engine_layering_pages::collect_available(&pages,inputs,self.root(),config,selection,self.budget(),&poll)?;if pages.passes.get()!=2{return Err("engine actual provenance/marker EOF missing".into())}self.require_policy_inputs(inputs)?;self.checkpoint()?;let pending=consume(&data,config,self.budget()).map_err(Failure::Operational);drop(data);drop(pages);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.require_policy_inputs(inputs)?;self.checkpoint()?;pending
 }
}

impl QueryDb{
 pub(crate) fn with_engine_unselected<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_engine_layering_pages::LayeringData,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
  capture.require_scope(scope)?;if !scope.uses_queries(self){return Err("engine no-model report requires its same actual QueryDb".into())}let proof=capture.engine_no_model()?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.with_workspace_code_pages_locked(capture,scope,|reader|{reader.checkpoint()?;let poll=||reader.checkpoint().map_err(|f|match f{Failure::Operational(e)=>e,Failure::Unsupported(m)=>io::Error::new(io::ErrorKind::Unsupported,m)});let data=dq_analyze::captured_engine_layering_pages::finish_unselected_ref(proof.preflight().selection(),reader.budget(),&poll)?;let pending=consume(&data,proof.preflight().config(),reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;capture.engine_no_model()?;pending})
 }
}

/// UI-only body loan. Exact current capture/header metadata is checked by the
/// caller; this function supplies only that file's current clean source lines.
impl WorkspaceCodeReader<'_,'_>{
 pub(in crate::query_db) fn with_ui_proc_lines(&self,proc:&dq_analyze::captured_ui_actions::UiProc,visit:&mut dyn FnMut(usize,&str)->Result<bool,Failure>)->Result<(),Failure>{
  let policy=dq_analyze::captured_raw_tree_pages::Policy::UiActions;self.require_raw_tree_discovery(policy)?;let config=self.capture.productive_ui_configuration()?.ok_or("UI current interpreted configuration absent")?;let mut found=false;
  self.for_each_file(FileDomain::RawTree(config,policy,true),&mut|relative,views|{self.checkpoint()?;if relative!=proc.proc.rel{return Ok(true)}if found{return Err("UI current body file repeated".into())}dq_analyze::captured_ui_actions::with_proc_lines(views,proc,self.budget(),&crate::daemon::control::checkpoint,visit)?;found=true;Ok(false)})?;if !found{return Err("UI current body file absent from issued productive source".into())}self.require_raw_tree_discovery(policy)
 }
}
fn ui_actions_using<R>(reader:&WorkspaceCodeReader<'_,'_>,config:&Config,consume:impl FnOnce(&dq_analyze::captured_raw_tree_pages::Data,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
 let policy=dq_analyze::captured_raw_tree_pages::Policy::UiActions;reader.require_raw_tree_discovery(policy)?;let prepared=reader.capture.prepared_ui_dispatcher()?;reader.db.begin_result_admission_locked()?;reader.budget().charge(std::mem::size_of::<UiInputProof>()+std::mem::size_of::<WorkspaceCapture>()+4*std::mem::size_of::<usize>()).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;let proof=Arc::new(UiInputProof{owner:Arc::downgrade(reader.capture),complete:std::sync::atomic::AtomicBool::new(false),published:std::sync::atomic::AtomicBool::new(false)});let _operation=super::super::reactive_ui_actions::bind(reader.db,reader.budget(),reader.capture,reader.scope,&proof)?;let mut roots=super::super::reactive_ui_actions::Session::new(reader.db,reader.capture,reader.scope,Arc::clone(&proof))?;
 let pages=RawTreePages{ui_proof:Some(&proof),reader,config,policy,passes:std::cell::Cell::new(0),completed:std::cell::RefCell::new([None,None,None])};let poll=||reader.checkpoint().map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)});let data=dq_analyze::captured_ui_actions::collect(&pages,prepared,&mut roots,config,reader.budget(),&poll)?;
 if prepared.needs_sources(){pages.finish()?}else if pages.passes.get()!=0{return Err("UI missing/bad dispatcher read productive source".into())}reader.require_raw_tree_discovery(policy)?;reader.capture.prepared_ui_dispatcher()?;reader.checkpoint()?;let pending=consume(&data,config,reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
}

/// Sealed source phase proof; only the actual UI RawTreePages exhausted loop
/// can set `complete`. No public DATA constructor or borrowed callback can.
pub(crate) struct UiInputProof{owner:Weak<WorkspaceCapture>,complete:std::sync::atomic::AtomicBool,published:std::sync::atomic::AtomicBool}
impl UiInputProof{
 pub(crate) fn mark_published(&self,capture:&Arc<WorkspaceCapture>)->io::Result<()>{self.require(capture)?;self.published.store(true,Ordering::Release);Ok(())}
 pub(crate) fn require_published(&self,capture:&Arc<WorkspaceCapture>)->io::Result<()>{self.require(capture)?;if !self.published.load(Ordering::Acquire){return Err(io::Error::new(io::ErrorKind::InvalidInput,"UI source facts are not completely published"))}Ok(())}
 pub(crate) fn require_owner(&self,capture:&Arc<WorkspaceCapture>)->io::Result<()>{if !Weak::ptr_eq(&self.owner,&Arc::downgrade(capture)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"UI EOF proof belongs to another actual capture"))}Ok(())}
 pub(crate) fn require(&self,capture:&Arc<WorkspaceCapture>)->io::Result<()>{self.require_owner(capture)?;if !self.complete.load(Ordering::Acquire){return Err(io::Error::new(io::ErrorKind::InvalidInput,"UI facts have not reached actual productive source EOF"))}Ok(())}
}

#[path="workspace_sys_reactive.rs"]mod sys_reactive;
pub(crate) use sys_reactive::WorkspaceSysReactiveWitness;

impl WorkspaceCodeReader<'_,'_>{
 pub(crate) fn lifeforms_data(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,order:&std::collections::HashMap<String,usize>,config:&Config,poll:&dyn Fn()->io::Result<()>,body:&dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>)->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>)->Result<(dq_analyze::captured_lifeforms::Data,WorkspaceCodeWitness),Failure>{
  self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;
  if !self.capture.has_semantic_question(crate::policy_request::WorkspaceAuxiliaryQuestion::Lifeforms){return Err("Lifeforms semantic question was not selected".into())}
  struct Pages<'r,'c,'s>{reader:&'r WorkspaceCodeReader<'c,'s>,inputs:&'r dm_analysis::policy_inputs::PolicyInputs,passes:std::cell::Cell<usize>,witness:std::cell::RefCell<Option<WorkspaceCodeWitness>>}
  impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.passes.get();if pass>=2{return Err("Lifeforms exceeded actual two CODE phases".into())}let completed=self.reader.for_each_code_file_completed(self.inputs,visit)?;let Some(witness)=completed.into_witness()?else{return Ok(false)};if !witness.matches(self.reader.capture,self.reader.scope,self.inputs)?{return Err("Lifeforms CODE completion belongs to another owner".into())}self.witness.replace(Some(witness));self.reader.checkpoint()?;self.passes.set(pass+1);Ok(true)}}
  let pages=Pages{reader:self,inputs,passes:0.into(),witness:None.into()};let data=dq_analyze::captured_lifeforms::collect_available(inputs,self.root(),&pages,order,config,self.budget(),poll,body)?;
  if pages.passes.get()!=2{return Err("Lifeforms omitted an actual CODE source phase".into())}let witness=pages.witness.into_inner().ok_or("Lifeforms actual CODE EOF absent")?;self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;self.checkpoint()?;Ok((data,witness))
 }
}

impl QueryDb{
 pub(crate) fn workspace_allow_run_budget(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>)->Result<Arc<Budget>,Failure>{self.with_workspace_code_pages(capture,scope,|reader|Ok(Arc::clone(reader.budget())))}
 pub(crate) fn with_workspace_full_allow_unused<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,plan:&dq_analyze::captured_allow_annotations::full_unused::SelectedTreePlanData,usage:&dq_analyze::captured_allow_annotations::full_unused::UsageData<'_>,consume:impl FnOnce(&[String],&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
  self.with_workspace_code_pages(capture,scope,|reader|{
   use dq_analyze::{captured_allow_annotations as policy,reactive_raw_policy_pages::RawPolicyPages};
   let require_plan=||->Result<(),Failure>{reader.checkpoint()?;if !reader.capture.covers_allow_unused(plan,&mut|bytes|reader.budget().charge(bytes).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m)))?{return Err("full unused lacks actual selected-tree CODE_MAPS_DM discovery".into())}reader.checkpoint()};require_plan()?;let(_,bytes)=reader.configuration();let bound=bytes.map_or(Some(1024),|b|b.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;reader.budget().charge(bound).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
   let poll=||reader.checkpoint().map_err(|e|match e{Failure::Operational(e)=>e,Failure::Unsupported(m)=>io::Error::new(io::ErrorKind::Unsupported,m)});let mut c=policy::Operation{budget:reader.budget(),poll:&poll};let registry=dq_analyze::allow_registry_metadata::complete_registry_allow_names(&mut c)?;
   struct Pages<'r,'c,'s>{reader:&'r WorkspaceCodeReader<'c,'s>,plan:&'r dq_analyze::captured_allow_annotations::full_unused::SelectedTreePlanData,require:&'r dyn Fn()->Result<(),Failure>,ended:std::cell::Cell<bool>}
   impl RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{if self.ended.get(){return Err("full unused source phase repeated".into())}(self.require)()?;if !self.reader.for_each_file(FileDomain::AllowUnused(self.plan),visit)?{return Ok(false)}(self.require)()?;self.reader.checkpoint()?;self.ended.set(true);Ok(true)}}
   let pages=Pages{reader,plan,require:&require_plan,ended:std::cell::Cell::new(false)};
   policy::with_names(&registry,&config,&mut c,|known,_|{let problems=policy::full_unused::collect_unused_data(known,usage,&pages,&[],&|_|String::new(),reader.budget(),&poll)?;if !pages.ended.get(){return Err("full unused source lacks actual unexempt CODE_MAPS_DM EOF".into())}reader.checkpoint()?;let pending=consume(&problems,&config,reader.budget()).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending})
  })
 }
}

#[path="workspace_derived_reads.rs"]mod derived_reads;
pub(crate) use derived_reads::WorkspaceDerivedWitness;

impl WorkspaceCodeReader<'_,'_>{
 fn require_silicon_discovery(&self,domain:SiliconActorDomain<'_>)->Result<(),Failure>{
  self.require_full_code_discovery()?;
  if let SiliconActorDomain::SelectedCodeMaps(plan)=domain { self.require_hidden_selected_tree(plan)?; }
  self.checkpoint()
 }

 fn require_hidden_selected_tree(&self,plan:&dq_analyze::captured_allow_annotations::full_unused::SelectedTreePlanData)->Result<(),Failure>{
  self.checkpoint()?;
  let root=self.capture.root();
  let roots=self.capture.recursive_roots();
  let exact_roots=roots.len()==2&&roots.iter().zip(["code","maps"]).all(|(path,expected)|
   path.strip_prefix(root).ok()==Some(std::path::Path::new(expected)));
  if plan.roots()!=["code","maps"]||!exact_roots{return Err("report differs from its qualified selected tree".into())}
  if !self.capture.covers_allow_unused(plan,&mut|bytes|self.budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message)))?{
   return Err("report lacks complete original selected tree discovery".into());
  }
  self.checkpoint()
 }

 fn with_hidden_tree_file(
  &self,domain:SiliconActorDomain<'_>,relative:&str,visit:&mut dyn FnMut(Option<RawPolicyViews<'_>>)->Result<(),Failure>,
 )->Result<(),Failure>{
  let scratch=Budget::scoped_temporaries(&self.budget).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;
  let pending=(||{
   let width=self.root().as_os_str().len().checked_add(relative.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
   scratch.charge(width).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;
   let Some(index)=self.capture.silicon_file_index(self.scope,relative,domain)?else{return visit(None)};
   let fixed=self.fixed.checked_add(self.budget.used()).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
   let available=self.db.workspace_input_headroom_locked(fixed)?;
   let (files,end)=self.capture.silicon_page(self.scope,index,1,available,domain)?;
   if end!=index+1||files.len()!=1{return Err("selected tree source was not loaned exactly once".into())}
   let file=&files[0];let text=file.text.as_ref().ok_or("selected tree source has no text")?;
   let slots=files.capacity().checked_mul(std::mem::size_of::<CurrentFile>()).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
   let live=file.charge.checked_add(file.path.capacity()).and_then(|n|n.checked_add(slots)).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
   // The file helper borrows its own scratch from this same operation budget.
   dq_analyze::captured_raw_file::with_original_policy_file(self.root(),&file.path,text.clone(),live,&self.budget,&mut|path,views|{
    if path!=relative{return Err("selected tree loan changed source identity".into())}
    visit(Some(views))?;Ok(true)
   })?;
   self.checkpoint()
  })();
  if pending.is_err(){scratch.keep_failed_scratch()}pending
 }

 pub(crate) fn silicon_entry_using<R>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,domain:SiliconActorDomain<'_>,consume:impl FnOnce(&dq_analyze::captured_silicon_entry::Data,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
  self.require_policy_inputs(inputs)?;self.require_silicon_discovery(domain)?;
  if !inputs.archive().uses_body_queries(self.db){return Err(Failure::Operational(invalid("silicon Original archive does not use the same checked BODY QueryDb")))}
  let (_,bytes)=self.configuration();
  let bound=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;
  self.budget.charge(bound).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;
  let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
  struct Pages<'a,'c,'s,'d>{reader:&'a WorkspaceCodeReader<'c,'s>,inputs:&'a dm_analysis::policy_inputs::PolicyInputs,domain:SiliconActorDomain<'d>,complete:std::cell::Cell<bool>}
  impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_,'_>{
   fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
    if self.complete.get(){return Err("silicon raw source phase repeated".into())}
    self.reader.require_policy_inputs(self.inputs)?;self.reader.require_silicon_discovery(self.domain)?;
    if !self.reader.for_each_file(FileDomain::Silicon(self.domain),visit)?{return Ok(false)}
    self.reader.require_policy_inputs(self.inputs)?;self.reader.require_silicon_discovery(self.domain)?;
    self.complete.set(true);Ok(true)
   }
  }
  impl dq_analyze::captured_silicon_entry::SiliconPages for Pages<'_,'_,'_,'_>{
   fn with_actor_file(&self,relative:&str,visit:&mut dyn FnMut(RawPolicyViews<'_>)->Result<(),Failure>)->Result<(),Failure>{
    let r=self.reader;r.require_policy_inputs(self.inputs)?;
    if !self.complete.get(){return Err("silicon actor file requires completed original raw discovery".into())}
    r.with_hidden_tree_file(self.domain,relative,&mut|file|{
     if let Some(views)=file{visit(views)?;}
     Ok(())
    })?;
    r.require_policy_inputs(self.inputs)
   }
  }
  let pages=Pages{reader:self,inputs,domain,complete:false.into()};
  let poll=||self.checkpoint().map_err(|f|match f{Failure::Operational(e)=>e,Failure::Unsupported(m)=>io::Error::new(io::ErrorKind::Unsupported,m)});
  let body=|input:&Arc<dm_tree::frontend::BodySyntaxInput>|dm_tree::frontend::BodySyntaxQueries::syntax_checked(self.db,input);
  let data=dq_analyze::captured_silicon_entry::collect_available(inputs,self.root(),&pages,&config,&self.budget,&poll,&body)?;
  if !pages.complete.get(){return Err("silicon actual raw discovery EOF absent".into())}
  self.require_policy_inputs(inputs)?;
  let pending=consume(&data,&config,&self.budget).map_err(Failure::Operational);
  if pending.is_err(){return pending}self.require_policy_inputs(inputs)?;pending
 }
}
