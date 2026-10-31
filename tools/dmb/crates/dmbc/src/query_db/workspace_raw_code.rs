//! Borrowed original CODE_DM production over the existing workspace capture.
//! No captured raw Tree/model, acquisition, per-file query or retained text view.
use super::*;
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure};
use dq_analyze::captured_raw_file::RawPolicyViews;

/// Request-local reader; only an actual admitted workspace guard constructs it.
/// A false visitor result stops a search and does not assert complete coverage.
pub(crate) struct WorkspaceCodeReader<'a,'scope>{
 db:&'a QueryDb,capture:&'a Arc<WorkspaceCapture>,scope:&'a NativeReadGuard<'scope>,
 inventory:&'a ResourceInventory,budget:Arc<Budget>,fixed:usize,
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
#[derive(Clone,Copy)]enum FileDomain<'a>{Code,GeneratorTests,Hygiene(&'a Config,&'static str,&'static str)}
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
  let archive=inputs.archive();let occurrence=archive.occurrences().get(ordinal).ok_or_else(||Failure::Operational(invalid("required reader ordinal unavailable")))?;if archive.callables().ordinal(occurrence.member)!=Some(ordinal){return Err(Failure::Operational(invalid("required reader original roster differs")))}let tree=archive.tree();let member=tree.member(occurrence.member).ok_or_else(||Failure::Operational(invalid("required reader member unavailable")))?;if tree.symbols().text(member.name)!=Some(name)||!matches!(member.kind,dm_tree::MemberKind::Proc|dm_tree::MemberKind::Verb){return Err(Failure::Operational(invalid("required reader name differs from original callable")))}let origin=archive.callable_header_policy_origin(occurrence.member)?;
  let mapping=inputs.mapping();let(index,lease)=mapping.source_acquisitions().enumerate().find_map(|(index,(path,lease))|(path==origin.path.as_path()).then_some((index,lease))).ok_or_else(||Failure::Operational(invalid("required reader source acquisition unavailable")))?;let lease=lease.ok_or_else(||Failure::Operational(invalid("required reader has no original acquisition")))?;let original=self.scope.original(index,&lease.identity())?;
  let pending=dq_analyze::captured_raw_file::with_original_policy_file_prepared(self.capture.root(),&origin.path,0,&self.budget,|scratch|{
   self.checkpoint()?;let mut backing=Some(0usize);let raw=match &original{crate::input_snapshot::RecordedSourceOriginal::Utf8(text)=>{dq_analyze::captured_raw_file::visit_source_storage(text,|_,bytes|backing=backing.and_then(|n|n.checked_add(bytes)));text.as_bytes()},crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)=>{backing=bytes.capacity().checked_add(128);bytes.as_slice()}};let transform=if matches!(&original,crate::input_snapshot::RecordedSourceOriginal::Utf8(text)if !text.as_bytes().contains(&b'\r')){Some(0)}else{dq_analyze::captured_raw_file::analyze_raw_len(raw)?.checked_mul(4).and_then(|n|n.checked_add(8192))};let peak=backing.and_then(|n|n.checked_add(transform?)).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"required original normalization overflow")))?;scratch.charge(peak).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;Ok(crate::input_snapshot::normalize_recorded_policy_original(&original))
  },&mut|relative,views|{visit(relative,views)?;Ok(true)});
  if matches!(&pending,Err(Failure::Operational(_))){return pending.map(|_|())}self.require_policy_inputs(inputs)?;pending.map(|_|())
 }
 pub(crate) fn budget(&self)->&Arc<Budget>{&self.budget}
 pub(crate) fn root(&self)->&std::path::Path{self.capture.root()}
 pub(crate) fn configuration(&self)->(&std::path::Path,Option<&[u8]>){self.capture.configuration()}
 fn checkpoint(&self)->Result<(),Failure>{let _=self.inventory.bytes();crate::daemon::control::checkpoint()?;self.capture.require_scope(self.scope)?;self.budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))}
 pub(crate) fn for_each_code_file(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  self.for_each_file(FileDomain::Code,visit)
 }
 fn for_each_file(&self,domain:FileDomain<'_>,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
  self.checkpoint()?;let mut start=0;
  while start<self.capture.file_count(){
   self.checkpoint()?;
   let fixed=self.fixed.checked_add(self.budget.used()).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace code fold accounting overflow")))?;
   let available=self.db.workspace_input_headroom_locked(fixed)?;
   let(files,end)=match domain{FileDomain::Code=>self.capture.code_page(self.scope,start,PAGE_FILES,available)?,FileDomain::GeneratorTests=>self.capture.generator_test_page(self.scope,start,PAGE_FILES,available)?,FileDomain::Hygiene(config,policy,group)=>self.capture.hygiene_page(self.scope,start,PAGE_FILES,available,config,policy,group)?};
   if end<=start{return Err(Failure::Operational(invalid("original code page made no progress")))}
   // Sum is deliberately conservative for aliased sources; the existing page
   // constructor independently admits its exact union before normalization.
   let live=files.iter().try_fold(files.capacity().checked_mul(std::mem::size_of::<CurrentFile>()).ok_or_else(||invalid("code page metadata overflow"))?,|n,file|n.checked_add(file.charge).and_then(|n|n.checked_add(file.path.capacity())).ok_or_else(||invalid("code page live ownership overflow")))?;
   for file in &files{
    self.checkpoint()?;
    let Some(text)=&file.text else{continue};
    let pending=dq_analyze::captured_raw_file::with_original_policy_file(self.capture.root(),&file.path,text.clone(),live,&self.budget,visit);
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
  let fixed=capture.retained_charge()?.checked_add(inventory.coordination_charge(0)?).and_then(|n|n.checked_add(std::mem::size_of::<WorkspaceCodeReader<'_,'_>>()+PAGE_FILES*std::mem::size_of::<CurrentFile>()+4096)).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace code fixed accounting overflow")))?;
  let input=self.workspace_input_headroom_locked(fixed)?;
  let budget=match shared{Some(budget)=>{budget.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;Arc::clone(budget)},None=>{
  let results=RESULT_BOUND.checked_sub(self.raw_policy.charge.load(Ordering::Relaxed)).and_then(|n|n.checked_sub(inventory.bytes())).and_then(|n|n.checked_sub(aggregate::REPORT_RESERVE)).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace code result-family headroom exhausted")))?;
  let budget=Budget::new(input.min(results).min(limit.unwrap_or(usize::MAX))).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
budget}};
  let reader=WorkspaceCodeReader{db:self,capture,scope,inventory:&inventory,budget,fixed};
  let pending=visit(&reader);
  if matches!(&pending,Err(Failure::Operational(_))){return pending}
  reader.checkpoint()?;pending
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
  let result=self.with_workspace_code_pages(capture,scope,|reader|{
   reader.require_sys_discovery()?;let(_,bytes)=reader.configuration();let bound=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Hygiene existing configuration bound overflow")))?;reader.budget.charge(bound).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
   let pages=SysPages::new(reader,&config,"sys/hygiene",1);
   let output=dq_analyze::captured_sys_hygiene_pages::collect(&pages,&config,reader.budget(),&||{crate::daemon::control::checkpoint()})?;
   pages.finish()?;reader.checkpoint()?;
   let pending=consume(&output).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
  });match result{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(invalid(message))}
 }
 pub(crate) fn with_workspace_resolvers<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_resolvers_pages::ResolverData)->io::Result<R>)->io::Result<R>{
  let result=self.with_workspace_code_pages(capture,scope,|reader|{
   reader.require_sys_discovery()?;let(_,bytes)=reader.configuration();let bound=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Resolver existing configuration bound overflow")))?;reader.budget.charge(bound).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
   let pages=SysPages::new(reader,&config,"sys/resolvers",2);
   let output=dq_analyze::captured_sys_resolvers_pages::collect(&pages,&config,reader.budget(),&||{crate::daemon::control::checkpoint()})?;
   pages.finish()?;reader.checkpoint()?;
   let pending=consume(&output).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
  });match result{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(invalid(message))}
 }
 pub(crate) fn with_workspace_tables<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_sys_tables_pages::TablesData)->io::Result<R>)->io::Result<R>{
  let result=self.with_workspace_code_pages(capture,scope,|reader|{
   reader.require_sys_discovery()?;let(_,bytes)=reader.configuration();let bound=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Tables existing configuration bound overflow")))?;reader.budget.charge(bound).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
   let pages=SysPages::new(reader,&config,"sys/tables",2);
   let output=dq_analyze::captured_sys_tables_pages::collect(&pages,&config,reader.budget(),&||{crate::daemon::control::checkpoint()})?;
   pages.finish()?;reader.checkpoint()?;
   let pending=consume(&output).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
  });match result{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(invalid(message))}
 }
 pub(crate) fn with_workspace_boundary<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,consume:impl FnOnce(&dq_analyze::captured_system_boundary_pages::BoundaryData)->io::Result<R>)->io::Result<R>{
  let result=self.with_workspace_code_pages(capture,scope,|reader|{
   reader.require_sys_discovery()?;let(_,bytes)=reader.configuration();let bound=bytes.map_or(Some(1024),|bytes|bytes.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Boundary existing configuration bound overflow")))?;reader.budget.charge(bound).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;
   let mut pages=SysPages::new(reader,&config,"system_boundary",2);pages.group="";
   let output=dq_analyze::captured_system_boundary_pages::collect(&pages,&config,reader.budget(),&||{crate::daemon::control::checkpoint()})?;
   pages.finish()?;reader.checkpoint()?;
   let pending=consume(&output).map_err(Failure::Operational);if matches!(&pending,Err(Failure::Operational(_))){return pending}reader.checkpoint()?;pending
  });match result{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(invalid(message))}
 }
}
