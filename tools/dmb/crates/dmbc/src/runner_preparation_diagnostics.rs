//! Scoped writer loan, no buffers/counters/source or cached rendered stamp.
use std::io::{self,Write};
#[derive(Debug)]pub struct PreparationDiagnosticResult{pub preparation:Result<crate::request::BuildOutcome,Box<dyn std::error::Error>>,pub diagnostics:io::Result<()>}
/// Status of the same successfully staged ordered Checker transcript.
pub(crate) struct PreparedCheckerTranscript {
    pub(crate) frame: dq_analyze::selected_exclusions_wire::Frame,
    pub(crate) clean: bool,
    pub(crate) archive: std::sync::Weak<dm_tree::frontend::BodyArchive>,
    pub(crate) queries: std::sync::Weak<crate::query_db::QueryDb>,
}

enum Destination<'a>{Writer(&'a mut dyn Write),ReportStage(&'a mut crate::selected_report_spool::Stage)}
pub(crate) struct PreparationDiagnosticOutput<'a>{utility_physical:Option<&'a mut dyn super::utility_capture::Capture>,utility_semantics:bool,utility_semantic_only:bool,utility_frontend:Option<&'a mut Option<std::sync::Arc<dm_tree::frontend::DiagnosticFrontend>>>,parse_only:Option<&'a mut Option<super::ParseOnlySyntaxPrepared>>,destination:Destination<'a>,checker:Option<&'a mut crate::selected_report_spool::Stage>,checker_frame:Option<PreparedCheckerTranscript>,compact_checker_cache:Option<&'a std::path::Path>,joined:Option<&'a mut Option<super::runner_freshness::JoinedSelectedInputs>>,author_fix:Option<&'a mut Option<super::author_fix_capture::Inputs>>,checker_inputs:Option<&'a mut Option<super::checker_capture::Inputs>>,schema:Option<&'a mut Option<super::schema_capture::Inputs>>,selftest_plan:Option<&'a std::sync::Arc<crate::runner_host::NativeCheckSelection>>,selftest_pending:Option<crate::runner_host::NativeSelftestPending>,first:Option<io::Error>,capture:bool,library_sites:bool,full_ci:bool,baseline_update:bool,generation_domain:Option<&'a super::runner_freshness::GenerationInputClosure>}
struct Guarded<'a>{writer:&'a mut dyn Write,first:Option<io::Error>}
impl Write for Guarded<'_>{
 fn write(&mut self,b:&[u8])->io::Result<usize>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.writer.write(b){Ok(n)=>Ok(n),Err(actual)=>{self.first=Some(actual);Err(io::ErrorKind::Other.into())}}}
 fn flush(&mut self)->io::Result<()>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}match self.writer.flush(){Ok(())=>Ok(()),Err(actual)=>{self.first=Some(actual);Err(io::ErrorKind::Other.into())}}}
}

#[cfg(test)]
mod selected_attempt_controls {
    use super::*;

    #[test]
    fn selected_report_keeps_only_the_latest_preparation_attempt() {
        let root = crate::test_scratch::dir("selected-diagnostic-attempts");
        let mut stage = crate::selected_report_spool::Stage::new(&root).unwrap();
        let mut output = PreparationDiagnosticOutput::selected_report(&mut stage);
        output.start_attempt().unwrap();
        output.emit(|sink| sink.write_all(b"warning from source that moved\n")).unwrap();
        output.start_attempt().unwrap();
        output.emit(|sink| sink.write_all(b"warning from current source\n")).unwrap();
        assert!(output.take_error().is_none());
        drop(output);

        let (verified, _) = stage.seal().unwrap().validate(|file| io::copy(file, &mut io::sink())).unwrap();
        let mut published = Vec::new();
        verified.publish(&mut published).unwrap();
        assert_eq!(published, b"warning from current source\n");
    }
}
impl<'a> PreparationDiagnosticOutput<'a>{
 pub(super) fn retain_parse_only(&mut self,slot:&'a mut Option<super::ParseOnlySyntaxPrepared>)->io::Result<()>{if self.checker_inputs.is_some()||self.schema.is_some()||self.author_fix.is_some()||self.joined.is_some()||self.checker.is_some(){return Err(io::ErrorKind::InvalidInput.into())}self.parse_only=Some(slot);Ok(())}
 pub(super) fn wants_parse_only(&self)->bool{self.parse_only.is_some()}
 pub(super) fn record_parse_only(&mut self,value:super::ParseOnlySyntaxPrepared)->io::Result<()>{let slot=self.parse_only.as_deref_mut().ok_or_else(||io::Error::from(io::ErrorKind::InvalidInput))?;if slot.is_some(){return Err(io::ErrorKind::AlreadyExists.into())}*slot=Some(value);Ok(())}

 pub(crate) fn retain_native_selftests(&mut self,plan:&'a std::sync::Arc<crate::runner_host::NativeCheckSelection>)->io::Result<()>{
  if plan.selftest_request().is_none(){return Ok(())}
  if self.selftest_plan.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native selftest preparation loan was already issued"))}
  self.selftest_plan=Some(plan);Ok(())
 }

 pub(super) fn finish_joined_native_selftests(&mut self)->io::Result<()>{
  let Some(plan)=self.selftest_plan else{return Ok(())};
  let actual=self.joined.as_deref().and_then(Option::as_ref).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"selftested whole preparation omitted its actual moved joined recorder"))?;
  self.selftest_pending.take().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"whole native callback completion is absent"))?.finish(plan,actual.native_selftest_epoch())
 }
 pub(super) fn run_native_selftests<P:crate::input_snapshot::SnapshotProvider>(&mut self,host:&mut crate::runner_host::BuildHost,recording:&crate::input_snapshot::RecordingInputs<P>,cache:Option<&std::path::Path>,workspace_root:Option<&std::path::Path>)->Result<bool,Box<dyn std::error::Error>>{
  let Some(plan)=self.selftest_plan else{return Ok(false)};
  if let Some(first)=self.first.take(){return Err(first.into())}
  if self.selftest_pending.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native callbacks repeated within one real preparation attempt").into())}
  let cache=cache.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"native callbacks require the actual admitted external request cache"))?;
  let root=workspace_root.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"native callbacks require the actual admitted workspace namespace"))?;
  self.selftest_pending=Some(host.prepare_native_selftests(plan,recording,cache,root)?);Ok(true)
 }
 pub(crate) fn finish_native_selftests(&mut self,epoch:&crate::input_snapshot::JoinedReportEpoch)->io::Result<()>{
  match self.selftest_plan{None=>{if self.selftest_pending.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"unrequested callback result appeared"))}Ok(())},Some(plan)=>self.selftest_pending.take().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual native callback completion is absent"))?.finish(plan,epoch)}
 }

 pub(crate) fn immediate(writer:&'a mut dyn Write)->Self{Self{utility_physical:None,utility_semantics:false,utility_semantic_only:false,utility_frontend:None,parse_only:None,destination:Destination::Writer(writer),checker:None,checker_frame:None,compact_checker_cache:None,joined:None,checker_inputs:None,author_fix:None,schema:None,selftest_plan:None,selftest_pending:None,first:None,capture:false,library_sites:false,full_ci:false,baseline_update:false,generation_domain:None}}
 pub(crate) fn captured(writer:&'a mut dyn Write)->Self{Self{utility_physical:None,utility_semantics:false,utility_semantic_only:false,utility_frontend:None,parse_only:None,destination:Destination::Writer(writer),checker:None,checker_frame:None,compact_checker_cache:None,joined:None,checker_inputs:None,author_fix:None,schema:None,selftest_plan:None,selftest_pending:None,first:None,capture:true,library_sites:false,full_ci:false,baseline_update:false,generation_domain:None}}
 pub(crate) fn selected_report(stage:&'a mut crate::selected_report_spool::Stage)->Self{Self{utility_physical:None,utility_semantics:false,utility_semantic_only:false,utility_frontend:None,parse_only:None,destination:Destination::ReportStage(stage),checker:None,checker_frame:None,compact_checker_cache:None,joined:None,checker_inputs:None,author_fix:None,schema:None,selftest_plan:None,selftest_pending:None,first:None,capture:true,library_sites:false,full_ci:false,baseline_update:false,generation_domain:None}}
 pub(crate) fn selected_combined(stage:&'a mut crate::selected_report_spool::Stage,checker:&'a mut crate::selected_report_spool::Stage)->Self{
  Self{utility_physical:None,utility_semantics:false,utility_semantic_only:false,utility_frontend:None,parse_only:None,destination:Destination::ReportStage(stage),checker:Some(checker),checker_frame:None,compact_checker_cache:None,joined:None,checker_inputs:None,author_fix:None,schema:None,selftest_plan:None,selftest_pending:None,first:None,capture:true,library_sites:false,full_ci:false,baseline_update:false,generation_domain:None}
 }
 pub(super) fn require_library_sites_baseline(&mut self) -> io::Result<()> {
  if !self.is_selected_report() || self.needs_combined_checker() {
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"library Sites requires its private Analyze-only selected preparation"));
  }
  self.library_sites = true;
  Ok(())
 }
 pub(super) fn compact_checker_cache(&self)->Option<&'a std::path::Path>{self.compact_checker_cache}
 pub(super) fn use_compact_checker(&mut self, cache:&'a std::path::Path)->io::Result<()>{
  if !self.needs_combined_checker() || !self.wants_joined_inputs(){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"compact Checker requires combined joined preparation"));
  }
  self.compact_checker_cache=Some(cache);
  Ok(())
 }
 pub(super) fn require_full_ci_baselines(&mut self) -> io::Result<()> {
  if !self.needs_combined_checker() || !self.wants_joined_inputs() || self.library_sites {
   return Err(io::Error::new(io::ErrorKind::InvalidInput, "full CI requires combined joined preparation"));
  }
  self.full_ci = true;
  Ok(())
 }
 pub(super) fn require_baseline_update(&mut self,domain:Option<&'a super::runner_freshness::GenerationInputClosure>)->io::Result<()>{self.require_full_ci_baselines()?;self.baseline_update=true;self.generation_domain=domain;Ok(())}
 pub(super) fn require_registered_baseline_update(&mut self,domain:Option<&'a super::runner_freshness::GenerationInputClosure>)->io::Result<()>{
  if self.baseline_update||self.full_ci||self.library_sites||self.joined.is_some()||self.author_fix.is_some()||self.checker_inputs.is_some()||self.schema.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected baseline purpose cannot borrow another preparation owner"))}
  self.baseline_update=true;self.generation_domain=domain;Ok(())
 }
 pub(super) fn needs_baseline_update(&self)->bool{self.baseline_update}
 pub(super) fn baseline_generation_domain(&self)->Option<&'a super::runner_freshness::GenerationInputClosure>{self.generation_domain}
 pub(super) fn needs_full_ci_baselines(&self) -> bool { self.full_ci }
 pub(super) fn needs_library_sites_baseline(&self) -> bool { self.library_sites }

 pub(super) fn retain_joined_inputs(&mut self, slot: &'a mut Option<super::runner_freshness::JoinedSelectedInputs>) {
  self.joined = Some(slot);
 }
 pub(super) fn wants_joined_inputs(&self) -> bool { self.joined.is_some() }
 pub(super) fn retain_checker_inputs(&mut self,slot:&'a mut Option<super::checker_capture::Inputs>){self.checker_inputs=Some(slot);}
 pub(super) fn retain_author_fix_inputs(&mut self,slot:&'a mut Option<super::author_fix_capture::Inputs>){self.author_fix=Some(slot);}
 pub(super) fn wants_author_fix_inputs(&self)->bool{self.author_fix.is_some()}
 pub(super) fn record_author_fix_inputs(&mut self,value:Option<super::author_fix_capture::Inputs>){if let Some(slot)=self.author_fix.as_deref_mut(){*slot=value;}}
 pub(super) fn wants_checker_inputs(&self)->bool{self.checker_inputs.is_some()}
 pub(super) fn record_checker_inputs(&mut self,value:Option<super::checker_capture::Inputs>){if let Some(slot)=self.checker_inputs.as_deref_mut(){*slot=value;}}

 pub(super) fn record_joined_inputs(&mut self, pending: Option<super::runner_freshness::JoinedSelectedInputs>) {
  if let Some(slot) = self.joined.as_deref_mut() { *slot = pending; }
 }
 /// Distinct private consumer purpose over the SAME complete schema recorder owner.
 /// This selects the existing committed syntax producer only; no Checker or
 /// complete-source receipt is synthesized here.
 pub(super) fn retain_native_sem_utility_inputs(&mut self,slot:&'a mut Option<super::schema_capture::Inputs>,frontend:&'a mut Option<std::sync::Arc<dm_tree::frontend::DiagnosticFrontend>>)->io::Result<()>{
  if self.utility_semantics||self.schema.is_some()||self.parse_only.is_some()||self.checker_inputs.is_some()||self.author_fix.is_some()||self.joined.is_some()||self.checker.is_some()||self.selftest_plan.is_some()||self.baseline_update{return Err(io::Error::new(io::ErrorKind::InvalidInput,"utility capture cannot borrow another preparation purpose"))}
  self.utility_semantics=true;self.schema=Some(slot);self.utility_frontend=Some(frontend);Ok(())
 }
 /// Semantic-only utility purpose: actual source/model, no interpreted rules.
 pub(super) fn retain_native_semantic_only_utility_inputs(&mut self,slot:&'a mut Option<super::schema_capture::Inputs>,frontend:&'a mut Option<std::sync::Arc<dm_tree::frontend::DiagnosticFrontend>>)->io::Result<()>{
  self.retain_native_sem_utility_inputs(slot,frontend)?;self.utility_semantic_only=true;Ok(())
 }
 pub(super) fn wants_semantic_only_utility(&self)->bool{self.utility_semantic_only}
 pub(super) fn retain_utility_physical(&mut self,capture:&'a mut dyn super::utility_capture::Capture)->io::Result<()>{
  if !self.utility_semantics||self.utility_frontend.is_none()||self.schema.is_none()||self.utility_physical.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"physical utility capture requires the exclusive actual utility preparation"))}
  self.utility_physical=Some(capture);Ok(())
 }
 pub(super) fn record_utility_workspace_roster(&mut self,discovery:&crate::runner_host::workspace_discovery::DiscoveryReceipt,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()>{
  if let Some(actual)=self.first.take(){return Err(actual)}
  if let Some(capture)=self.utility_physical.as_deref_mut(){if !self.utility_semantics{return Err(io::ErrorKind::InvalidInput.into())}capture.workspace_roster(discovery,work)?;}
  Ok(())
 }
 pub(super) fn abort_utility_capture(&mut self){if let Some(capture)=self.utility_physical.as_deref_mut(){capture.begin_attempt();}}
 pub(super) fn utility_capture_requested(&mut self)->io::Result<bool>{if let Some(actual)=self.first.take(){return Err(actual)}Ok(self.utility_physical.is_some())}
 pub(super) fn prepare_utility_current(&mut self,view:&dm_tree::frontend::DiagnosticSourceView<'_>,snapshot:&crate::runner_host::query_snapshot::SourceSnapshot,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->Result<(),Box<dyn std::error::Error>>{
  if let Some(actual)=self.first.take(){return Err(actual.into())}
  if let Some(capture)=self.utility_physical.as_deref_mut(){if !self.utility_semantics{return Err(io::Error::from(io::ErrorKind::InvalidInput).into())}capture.prepare_current(view,snapshot,work)?;}
  Ok(())
 }
 pub(super) fn capture_utility_physical<P:crate::input_snapshot::SnapshotProvider>(&mut self,recording:&crate::input_snapshot::RecordingInputs<P>,queries:&crate::query_db::QueryDb)->io::Result<()>{
  if let Some(actual)=self.first.take(){return Err(actual)}
  if let Some(capture)=self.utility_physical.as_deref_mut(){if !self.utility_semantics{return Err(io::ErrorKind::InvalidInput.into())}super::utility_capture::run(capture,recording,queries)?;}
  Ok(())
 }
 pub(super) fn wants_native_sem_utility(&self)->bool{self.utility_semantics}
 pub(super) fn record_native_sem_utility_frontend(&mut self,frontend:std::sync::Arc<dm_tree::frontend::DiagnosticFrontend>)->io::Result<()>{
  let slot=self.utility_frontend.as_deref_mut().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"utility frontend has no actual preparation loan"))?;
  if slot.is_some(){return Err(io::Error::new(io::ErrorKind::AlreadyExists,"utility frontend already transferred"))}
  frontend.require_original_utility_owner()?;*slot=Some(frontend);Ok(())
 }
 pub(super) fn retain_schema_inputs(&mut self,slot:&'a mut Option<super::schema_capture::Inputs>){self.schema=Some(slot)}
 pub(super) fn wants_schema_inputs(&self)->bool{self.schema.is_some()}
 pub(super) fn record_schema_inputs(&mut self,inputs:super::schema_capture::Inputs){if let Some(slot)=self.schema.as_deref_mut(){*slot=Some(inputs)}}
 pub(crate) fn needs_combined_checker(&self)->bool{self.checker.is_some()}
 pub(crate) fn is_selected_report(&self)->bool{matches!(&self.destination,Destination::ReportStage(_))}
 pub(crate) fn emit_combined_checker(&mut self,run:impl FnOnce(&mut crate::selected_report_spool::Stage)->io::Result<PreparedCheckerTranscript>)->io::Result<()>{
  if self.first.is_some(){return Err(self.first.take().expect("actual preparation write error"));}
  let stage=self.checker.as_deref_mut().ok_or_else(||io::Error::other("combined checker stage absent"))?;
  if self.checker_frame.is_some(){return Err(io::Error::other("combined checker issued twice in one preparation attempt"));}
  self.checker_frame=Some(run(stage)?);
  Ok(())
 }
 pub(crate) fn take_checker_frame(&mut self)->Option<PreparedCheckerTranscript>{self.checker_frame.take()}
 pub(crate) fn start_attempt(&mut self)->io::Result<()>{
  self.selftest_pending=None; // only the final real attempt may attach a completed result
  if let Some(capture)=self.utility_physical.as_deref_mut(){capture.begin_attempt();}
  if self.utility_semantics{if let Some(slot)=self.schema.as_deref_mut(){*slot=None;}}

  self.record_checker_inputs(None);
   if let Some(slot)=self.parse_only.as_deref_mut(){*slot=None;}
   if let Some(slot)=self.utility_frontend.as_deref_mut(){*slot=None;}
  self.record_author_fix_inputs(None);
  let Destination::ReportStage(stage)=&mut self.destination else{return Ok(())};
  if let Some(error)=self.first.take(){return Err(error)}
  stage.restart_attempt()?;
  if let Some(checker)=self.checker.as_deref_mut(){checker.restart_attempt()?;}
  self.checker_frame=None;
  self.record_joined_inputs(None);if let Some(slot)=self.schema.as_deref_mut(){*slot=None;}
  Ok(())
 }
 pub(crate) fn take_error(&mut self)->Option<io::Error>{self.first.take()}
 pub(crate) fn emit(&mut self,run:impl FnOnce(&mut dyn Write)->io::Result<()>)->io::Result<()>{
  if self.first.is_some(){return Ok(())}let writer:&mut dyn Write=match &mut self.destination{Destination::Writer(writer)=>*writer,Destination::ReportStage(stage)=>*stage};let mut guarded=Guarded{writer,first:None};let pending=run(&mut guarded);let pending=match guarded.first.take(){Some(actual)=>Err(actual),None=>pending};
  match pending{Ok(())=>Ok(()),Err(actual)if self.capture=>{self.first=Some(actual);Ok(())},Err(actual)=>Err(actual)}
 }
}
