//! Closed current-source Derived report child. It cannot invent a cold proof.
use super::*;
use dq_analyze::{captured_derived_reads::DerivedReadData,captured_reactive_reads::{self as reads,GlobalProvider},generator_test_scope::TestTypeCollector,key_policy_control::Control};
pub(crate) struct WorkspaceDerivedWitness{code:WorkspaceCodeWitness,tests:WorkspaceGeneratorTestWitness,subject:Arc<crate::input_snapshot::OriginalAnalysisSubject>}
impl WorkspaceDerivedWitness{
 pub(crate) fn matches(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,inputs:&dm_analysis::policy_inputs::PolicyInputs)->Result<bool,Failure>{self.subject.derived_preflight()?.require_bound_current(&self.subject,capture,scope,inputs)?;Ok(self.code.matches(capture,scope,inputs)?&&self.tests.matches(capture,scope,inputs)?)}
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){self.code.visit_storage(&mut visit);self.tests.visit_storage(&mut visit);visit(Arc::as_ptr(&self.subject)as usize,self.subject.charge());}
}
struct Phase{budget:Arc<Budget>,complete:bool}impl Drop for Phase{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}
struct C<'a>{budget:&'a Budget,poll:&'a dyn Fn()->io::Result<()>}impl Control for C<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.budget.require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;(self.poll)()?;Ok(())}fn reserve(&mut self,n:usize)->Result<(),Failure>{self.budget.charge(n).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))}fn overflow(&mut self)->Failure{self.budget.deny();Failure::Operational(io::ErrorKind::OutOfMemory.into())}fn allocation_failed(&mut self)->Failure{self.overflow()}}
impl WorkspaceCodeReader<'_,'_>{
 pub(crate) fn derived_reads_data(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,subject:&Arc<crate::input_snapshot::OriginalAnalysisSubject>,order:&std::collections::HashMap<String,usize>,config:&Config,globals:&dyn GlobalProvider,poll:&dyn Fn()->io::Result<()>,body:&dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>)->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>)->Result<(DerivedReadData,WorkspaceDerivedWitness),Failure>{
  self.derived_reads_data_using(inputs,subject,order,config,globals,poll,body,None)
 }
 pub(crate) fn derived_reads_data_using(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,subject:&Arc<crate::input_snapshot::OriginalAnalysisSubject>,order:&std::collections::HashMap<String,usize>,config:&Config,globals:&dyn GlobalProvider,poll:&dyn Fn()->io::Result<()>,body:&dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>)->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>,fixture:Option<&mut dq_analyze::captured_derived_reads::FixtureVisitor<'_>>)->Result<(DerivedReadData,WorkspaceDerivedWitness),Failure>{
  self.require_policy_inputs(inputs)?;self.require_full_code_discovery()?;self.require_generator_test_discovery()?;
  if !self.capture.has_semantic_question(crate::policy_request::WorkspaceAuxiliaryQuestion::DerivedReads){return Err("Derived actual source role was not selected".into())}let preflight=subject.derived_preflight_owner()?;preflight.require_bound_current(subject,self.capture,self.scope,inputs)?;preflight.require_configuration(self.configuration().0,self.configuration().1)?;
  // Generator test-only classification is the real original all-DM tree domain,
  // including hidden code, not the lint's selected/visible Model domain.
  let mut phase=Phase{budget:Budget::scoped_temporaries(self.budget()).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?,complete:false};let mut c=C{budget:&phase.budget,poll};let mut collector=TestTypeCollector::default();let completed=self.for_each_generator_test_file_completed(inputs,&mut|relative,views|{collector.observe(relative,views.raw()?,&mut c)?;Ok(true)})?;let tests=completed.into_witness()?.ok_or("Derived test-only source traversal stopped")?;let rows=collector.finish();
  struct Selected<'r,'c,'s>{reader:&'r WorkspaceCodeReader<'c,'s>,inputs:&'r dm_analysis::policy_inputs::PolicyInputs,config:&'r Config,complete:std::cell::Cell<usize>}
  impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Selected<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{self.reader.require_policy_inputs(self.inputs)?;let all=self.reader.for_each_file(FileDomain::CodeSelected(self.config,"derived_reads",dq_analyze::captured_derived_reads::metadata().group),visit)?;if all{self.reader.require_policy_inputs(self.inputs)?;self.complete.set(self.complete.get()+1);}Ok(all)}}
  struct All<'r,'c,'s>{reader:&'r WorkspaceCodeReader<'c,'s>,inputs:&'r dm_analysis::policy_inputs::PolicyInputs,complete:std::cell::Cell<usize>,witness:std::cell::RefCell<Option<WorkspaceCodeWitness>>}
  impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for All<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let completed=self.reader.for_each_code_file_completed(self.inputs,visit)?;let Some(witness)=completed.into_witness()?else{return Ok(false)};if !witness.matches(self.reader.capture,self.reader.scope,self.inputs)?{return Err("Derived all-CODE receipt belongs to another actual source".into())}self.complete.set(self.complete.get()+1);self.witness.replace(Some(witness));Ok(true)}}
  let selected=Selected{reader:self,inputs,config,complete:0.into()};let all=All{reader:self,inputs,complete:0.into(),witness:None.into()};let original=if fixture.is_none(){preflight.take_bound_current(subject,self.capture,self.scope,inputs)?}else{None};
  let pending=if let Some(visit)=fixture{reads::derived_reads_fixture_from_pages(inputs,self.root(),&selected,&all,order,&rows,self.budget(),globals,poll,body,visit)}else{match original{Some(data)=>reads::derived_reads_data_from_preflight_pages(data,inputs,self.root(),&selected,&all,order,&rows,self.budget(),globals,poll,body),None=>reads::derived_reads_data_from_pages(inputs,self.root(),&selected,&all,order,&rows,self.budget(),globals,poll,body)}};
  let data=match pending{Ok(data)=>data,Err(Failure::Operational(actual))=>return Err(Failure::Operational(actual)),Err(actual)=>{self.checkpoint()?;return Err(actual)}};
  if all.complete.get()<2||selected.complete.get()<2{return Err("Derived skipped an actual selected/all-CODE judgment phase".into())}let code=all.witness.into_inner().ok_or("Derived all-CODE EOF absent")?;self.require_policy_inputs(inputs)?;preflight.require_bound_current(subject,self.capture,self.scope,inputs)?;
  self.budget().charge(std::mem::size_of::<WorkspaceDerivedWitness>()+subject.charge()).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;let witness=WorkspaceDerivedWitness{code,tests,subject:Arc::clone(subject)};if !witness.matches(self.capture,self.scope,inputs)?{return Err("Derived final source witness differs".into())}drop(rows);phase.complete=true;drop(phase);Ok((data,witness))
 }
}

impl QueryDb{
 /// Uncached, scoped fixture inspection over the SAME actual retained model,
 /// workspace reader, compiler BODY queries and physical source ledger.
 /// This issues no report/cache completion and publishes no source changes.
 pub(crate) fn with_original_workspace_derived_fixture_guard(&self,workspace:&Arc<WorkspaceCapture>,guard:&NativeReadGuard<'_>,capture:&Arc<CapturedPolicyInputs>,subject:&Arc<crate::input_snapshot::OriginalAnalysisSubject>,visit:&mut dq_analyze::captured_derived_reads::FixtureVisitor<'_>)->io::Result<()>{
  use dq_analyze::{captured_raw_file::Config,captured_raw_policy::Configuration};
  crate::daemon::control::checkpoint()?;workspace.require_scope(guard)?;workspace.require_analysis_subject(subject)?;subject.require_bound_mapping(capture.policy().mapping())?;
  if !guard.uses_queries(self)||!workspace.has_semantic_question(crate::policy_request::WorkspaceAuxiliaryQuestion::DerivedReads)||guard.model_preparation()!=Some(dm_tree::frontend::DiagnosticPreparationPurpose::OriginalSharedComplete){return Err(io::Error::new(io::ErrorKind::InvalidInput,"derived fixture requires the actual complete selected native model and QueryDb"))}
  capture.semantic_source_evidence().check(capture.policy().mapping())?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  let pending=self.with_workspace_code_pages_limit_locked(workspace,guard,None,|reader|{
   reader.require_policy_inputs(capture.policy())?;reader.require_full_code_discovery()?;reader.require_generator_test_discovery()?;
   let(path,bytes)=reader.configuration();if capture.configuration_bytes(path)?!=bytes{return Err("derived fixture configuration differs from the real captured input".into())}
   let width=bytes.map_or(Some(1024),|b|b.len().checked_mul(64).and_then(|n|n.checked_add(1024))).ok_or_else(||Failure::Operational(io::ErrorKind::OutOfMemory.into()))?;reader.budget().charge(width).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured))?;let poll=||crate::daemon::control::checkpoint();
   let manifest=capture.untyped_manifest(reader.root())?;let bytes=match manifest{dq_analyze::captured_untyped::ManifestRead::CompiledOriginalBytes(bytes)|dq_analyze::captured_untyped::ManifestRead::OriginalBytes(bytes)=>Some(bytes),dq_analyze::captured_untyped::ManifestRead::ProvenUnavailable=>None,dq_analyze::captured_untyped::ManifestRead::Compiled=>return Err("derived fixture original include order is unissued".into())};
   let order=reads::scoped_original_include_order_bytes(bytes,reader.budget(),&poll)?;
   let body=|input:&Arc<dm_tree::frontend::BodySyntaxInput>|dm_tree::frontend::BodySyntaxQueries::syntax_checked(self,input);
   let held=std::cell::RefCell::new(None);
   let globals=|consume:&mut dyn FnMut(&reads::GlobalResult)->Result<bool,Failure>|->Result<bool,Failure>{
    if held.borrow().is_none(){let actual=reads::globals_native(capture.policy(),reader.root(),reader.budget(),&poll,&body)?;held.replace(Some(actual));}
    let borrowed=held.borrow();consume(borrowed.as_ref().expect("actual fixture Globals retained"))
   };
   let(data,witness)=reader.derived_reads_data_using(capture.policy(),subject,&order,&config,&globals,&poll,&body,Some(visit))?;
   if !witness.matches(workspace,guard,capture.policy())?{return Err("derived fixture actual source witness differs after callback".into())}drop(data);reader.require_policy_inputs(capture.policy())?;Ok(())
  });pending.map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})
 }
}
