//! Productive raw/primary handoff into the SAME current declaration owner.
//! The distinct diagnostic plan stays restricted: this module grants no full-project,
//! compiler, checker, partial-policy or EOF authority from a text/filename.
use super::*;
use std::io;
#[cfg(test)]#[path="../../../shared/original_analysis_test_host.rs"]mod original_resource_host;
use dm_preprocess::regions::{GenerationDirectivePlan,OriginalDiagnosticPlan,GenerationOmissions,OriginalBatchExecution,OriginalBatchSyntaxHost};

/// Borrow the actual existing settings host for batch receiver worker permits.
/// No counter, QueryDb, executor or family manager is constructed here.
pub(crate) struct TreeOriginalBatchHost<'a>(pub(crate) &'a dyn SettingExpressionQueries);
#[derive(Debug)]struct BatchAdmissionDiagnostic(Diagnostic);
impl std::fmt::Display for BatchAdmissionDiagnostic{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{write!(f,"actual batch declaration admission returned source diagnostics: {:?}",self.0)}}
impl std::error::Error for BatchAdmissionDiagnostic{}
impl OriginalBatchSyntaxHost for TreeOriginalBatchHost<'_>{
 fn with_producer_admission(&self,run:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->io::Result<()>)->io::Result<()>{
  let mut called=false;let mut first=None;
  let pending=self.0.with_declaration_admission(&mut|a|{
   if called{return Err(BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidData,"batch declaration admission callback repeated")))}called=true;
   match run(a){Ok(())=>Ok(()),Err(actual)=>{first=Some(actual);Err(BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::Interrupted,"actual batch producer stopped")))}}
  });
  // The first actual worker IO survives even a later host cleanup failure.
  if let Some(actual)=first{return Err(actual)}
  match pending{Err(BodySyntaxFailure::Operational(actual))=>return Err(actual),Err(BodySyntaxFailure::Syntax(actual))=>return Err(io::Error::new(io::ErrorKind::Unsupported,BatchAdmissionDiagnostic(actual))),Ok(())=>()}
  if !called{return Err(io::Error::new(io::ErrorKind::InvalidData,"batch declaration admission callback omitted"))}Ok(())
 }
}

/// One actual no-omission diagnostic directive traversal plus its consumed native primary.
/// No conversion to a compiler DirectivePlan is provided. The source-purpose
/// owner must separately bind these products to its exact captured root.
pub(crate) struct StreamedOriginalDeclarations{
 plan:OriginalDiagnosticPlan,expanded:ExpandedRegions,
 primary:super::original_declaration_input::OrderedOriginalDeclarations,
}
impl StreamedOriginalDeclarations{
 pub(crate) fn plan(&self)->&OriginalDiagnosticPlan{&self.plan}
 pub(crate) fn expanded(&self)->&ExpandedRegions{&self.expanded}
 pub(crate) fn primary(&self)->&super::original_declaration_input::OrderedOriginalDeclarations{&self.primary}
 /// Run only the existing adapter, signature-alias owner, previous BODY-code
 /// convergence and current-leaf assembly after the real primary frontier.
 /// General constants run iff that frontier really is complete.
 pub(crate) fn into_prepared(self,engine:Option<&EngineSeed>,previous:Option<&DeclarationSyntax>,host:&dyn SettingExpressionQueries,a:&dm_syntax::SettingAdmission<'_>)->Result<(OriginalDiagnosticPlan,ExpandedRegions,super::original_declaration_input::PreparedOriginalDeclarations),FrontendBuildFailure>{
  if !self.primary.expanded().same_view(&self.expanded.text){return Err(FrontendBuildFailure::Operational(io::Error::new(io::ErrorKind::InvalidData,"streamed declaration primary detached from actual output arena")))}
  let current=self.primary.adapt_for_original_outcome(a).and_then(|products|products.into_current(a)).map_err(FrontendBuildFailure::Operational)?;
  current.retain_signature_aliases(host,a).map_err(|error|match error{BodySyntaxFailure::Operational(actual)=>FrontendBuildFailure::Operational(actual),BodySyntaxFailure::Syntax(actual)=>FrontendBuildFailure::Diagnostics(vec![actual].into())})?;
  let prepared=current.converge_previous_code(previous,a).and_then(|current|current.into_prepared(engine,a)).map_err(FrontendBuildFailure::Operational)?;
  actual(a,||a.checkpoint()).map_err(FrontendBuildFailure::Operational)?;Ok((self.plan,self.expanded,prepared))
 }
}
fn actual<T>(a:&dm_syntax::SettingAdmission<'_>,run:impl FnOnce()->io::Result<T>)->io::Result<T>{let result=run();if let Some(first)=a.take_operational_error(){Err(first)}else{result}}
fn header_failure(error:crate::procedure::header_input::OriginalHeaderFailure)->io::Error{match error{crate::procedure::header_input::OriginalHeaderFailure::Operational(actual)=>actual,crate::procedure::header_input::OriginalHeaderFailure::Source(message)=>io::Error::new(io::ErrorKind::Unsupported,message)}}

/// Consumer is installed BEFORE the first actual producer pull. Analyze callers
/// supply their actual batch execution; lazy diagnostic callers pass None. The
/// raw controller validates delivery/provider continuity; neither is inferred
/// from the expanded string, initial macro context, or filename here.
pub(crate) fn prepare_original_stream_using(
 project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,
 omissions:GenerationOmissions,max_raw_bytes:usize,
 source_work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,
 a:&dm_syntax::SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,
)->io::Result<StreamedOriginalDeclarations>{
 let mut observer=actual(a,||crate::procedure::original_primary_signatures::OriginalSignatureObserver::new(a))?;
 let product=actual(a,||match batch{Some(batch)=>GenerationDirectivePlan::prepare_original_stream_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,Some(batch),&mut observer),None=>GenerationDirectivePlan::prepare_original_checker_stream_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,&mut observer)}).inspect_err(|_error|{#[cfg(test)]eprintln!("ORIGINAL_STREAM_STAGE=raw_product {_error:?}")})?;
 let(plan,expanded,primary,binding)=actual(a,||product.into_diagnostic_parts_using(a)).inspect_err(|_error|{#[cfg(test)]eprintln!("ORIGINAL_STREAM_STAGE=diagnostic_handoff {_error:?}")})?;
 #[cfg(test)]if expanded.text.len()<=512{eprintln!("actual Original produced arena: {:?}; primary items: {:#?}",expanded.text.as_str(),primary.syntax().items);}
 let input=actual(a,||observer.finish_primary(expanded.text.clone(),primary,Some(&binding)).map_err(header_failure)).inspect_err(|_error|{#[cfg(test)]eprintln!("ORIGINAL_STREAM_STAGE=actual_header_finish {_error:?}")})?;
 // Clauses, typed values and default roots have moved into the genuine header
 // owner; dropping the neutral binding now cannot detach those borrowed facts.
 let primary=super::original_declaration_input::OrderedOriginalDeclarations::from_actual_signature_input(input,a).inspect_err(|_error|{#[cfg(test)]eprintln!("ORIGINAL_STREAM_STAGE=current_signature_input {_error:?}")})?;
 actual(a,||a.checkpoint())?;Ok(StreamedOriginalDeclarations{plan,expanded,primary})
}

#[cfg(test)]mod batch_admission_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[derive(Debug)]struct Host{counter:Arc<AtomicUsize>,mode:u8}
 impl SettingExpressionQueries for Host{
  fn expression(&self,_:&SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{panic!("this contract is a permit loan, not a second expression parser")}
  fn with_declaration_admission(&self,run:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{
   if self.mode==1{return Ok(())}let a=dm_syntax::SettingAdmission::new(&self.counter,1<<20,&||Ok(()));
   let result=run(&a);if self.mode==2{return Err(BodySyntaxFailure::Operational(io::Error::from_raw_os_error(87)))}result
  }
 }
 #[test]fn batch_worker_permit_uses_actual_host_counter_and_releases_lease(){let counter=Arc::new(AtomicUsize::new(0));let host=Host{counter:counter.clone(),mode:0};let adapter=TreeOriginalBatchHost(&host);let mut called=0;adapter.with_producer_admission(&mut|a|{called+=1;let lease=a.reserve(4096)?;assert!(counter.load(Ordering::Acquire)>=4096);drop(lease);Ok(())}).unwrap();assert_eq!(called,1);assert_eq!(counter.load(Ordering::Acquire),0);}
 #[test]fn actual_batch_worker_first_io_survives_host_cleanup_and_missing_loan_is_rejected(){let counter=Arc::new(AtomicUsize::new(0));let host=Host{counter:counter.clone(),mode:2};let error=TreeOriginalBatchHost(&host).with_producer_admission(&mut|_|Err(io::Error::from_raw_os_error(1450))).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));let host=Host{counter,mode:1};assert_eq!(TreeOriginalBatchHost(&host).with_producer_admission(&mut|_|panic!("omitted actual callback")).unwrap_err().kind(),io::ErrorKind::InvalidData);}
}

#[cfg(test)]mod actual_stream_controls{
 use super::*;use std::{any::Any,sync::atomic::{AtomicUsize,Ordering}};
 use dm_preprocess::source_arena_credit::{SourceArenaWork,SourceArenaCredit,SourceArenaCreditOwner};
 struct Source{raw:Vec<u8>,source:dm_preprocess::AcquiredSource}
 impl Source{fn new(text:&str)->Self{Self{raw:text.as_bytes().to_vec(),source:dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),())}}}
 impl SourceProvider for Source{
  fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}
  fn original_batch_source(&self)->io::Result<Option<&(dyn SourceProvider+Sync)>>{Ok(Some(self))}
  fn read(&self,_:&Path)->Result<String,String>{panic!("actual stream may not use decoded compatibility source") }
  fn original_raw_source_open_admitted(&self,path:&Path,max:usize,work:&dyn SourceArenaWork,after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before_read:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<dm_preprocess::OriginalRawReadOutcome>{work.checkpoint()?;if after_open()?==dm_preprocess::OriginalRawOpenDecision::Suppress{return Ok(dm_preprocess::OriginalRawReadOutcome::Suppressed)}self.original_raw_source_admitted(path,max,before_read,before_decode,acquired)?.map(dm_preprocess::OriginalRawReadOutcome::Acquired).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"actual captured test root lost acquisition"))}
  fn original_raw_source_admitted(&self,_:&Path,_:usize,_:&mut dyn FnMut(usize)->io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<Option<dm_preprocess::SourceAcquisitionLease>>{
   before_decode(dm_preprocess::OriginalRawAllocationPlan::new(&[],0,0,0,false,false))?;acquired(self.source.lease())?;Ok(Some(self.source.lease().clone()))
  }
  fn original_source_bytes<'a>(&'a self,lease:&'a dm_preprocess::SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{if !lease.same_binding(self.source.lease()){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(&self.raw))}
 }
 struct Credit{bytes:AtomicUsize,live:Arc<AtomicUsize>}
 impl Drop for Credit{fn drop(&mut self){self.live.fetch_sub(self.bytes.load(Ordering::Acquire),Ordering::AcqRel);}}
 impl SourceArenaCreditOwner for Credit{fn as_any(&self)->&dyn Any{self}fn reserved_bytes(&self)->usize{self.bytes.load(Ordering::Acquire)}fn visit_storage(&self,_:&mut dyn FnMut(usize,usize)){}}
 struct Work{live:Arc<AtomicUsize>,fail:bool}
 impl Work{fn loan<'a>(&self,credit:&'a SourceArenaCredit)->io::Result<&'a Credit>{let current=credit.owner().as_any().downcast_ref::<Credit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&current.live,&self.live){return Err(io::ErrorKind::InvalidInput.into())}Ok(current)}}
 impl SourceArenaWork for Work{
  fn original_read_bookkeeping_bytes(&self)->io::Result<usize>{Ok(128)}
  fn adopt_original_read(&self,credit:&mut SourceArenaCredit,_:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{self.loan(credit)?;Ok(())}
  fn checkpoint(&self)->io::Result<()>{if self.fail{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}
  fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{self.checkpoint()?;let after=self.live.load(Ordering::Acquire).checked_add(n).ok_or(io::ErrorKind::OutOfMemory)?;if after>32<<20{return Err(io::ErrorKind::OutOfMemory.into())}self.live.store(after,Ordering::Release);Ok(SourceArenaCredit::from_resource_owner(Arc::new(Credit{bytes:AtomicUsize::new(n),live:self.live.clone()})))}
  fn grow(&self,credit:&mut SourceArenaCredit,n:usize)->io::Result<()>{self.checkpoint()?;let current=self.loan(credit)?;let after=self.live.load(Ordering::Acquire).checked_add(n).ok_or(io::ErrorKind::OutOfMemory)?;if after>32<<20{return Err(io::ErrorKind::OutOfMemory.into())}let bytes=current.bytes.load(Ordering::Acquire).checked_add(n).ok_or(io::ErrorKind::OutOfMemory)?;current.bytes.store(bytes,Ordering::Release);self.live.store(after,Ordering::Release);Ok(())}
  fn shrink(&self,credit:&mut SourceArenaCredit,n:usize)->io::Result<()>{let current=self.loan(credit)?;let after=current.bytes.load(Ordering::Acquire).checked_sub(n).ok_or(io::ErrorKind::InvalidInput)?;current.bytes.store(after,Ordering::Release);self.live.fetch_sub(n,Ordering::AcqRel);Ok(())}
 }
 #[derive(Debug)]struct StreamHost{counter:Arc<AtomicUsize>}
 impl SettingExpressionQueries for StreamHost{
  fn expression(&self,_:&SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{panic!("direct productive stream control must not invoke a parallel compatibility expression parser")}
  fn with_declaration_admission(&self,run:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{
   let poll=||Ok(());let admission=dm_syntax::SettingAdmission::new(&self.counter,32<<20,&poll);let pending=run(&admission);if let Some(actual)=admission.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}if matches!(&pending,Err(BodySyntaxFailure::Operational(_))){return pending}admission.checkpoint().map_err(BodySyntaxFailure::Operational)?;pending
  }
 }
 fn omissions()->GenerationOmissions{GenerationOmissions::probe(std::iter::empty(),&mut|_|panic!("no synthetic omissions"),&mut|_|Ok(())).unwrap()}
 #[test]fn productive_actual_stream_keeps_header_fatal_and_analyze_first_batch_notices(){
  for (text,fatal,notice)in[("/proc/p(var/static/A=1)\n    return A\n",false,false),("/proc/p(var/static/A=1)\n    return A\n#error MUST_NOT_BE_CONSUMED\n",false,true),("/proc/p(var/A=)\n",true,false),("/proc/p(var/A=)\n#error MUST_NOT_BE_CONSUMED\n",true,true)]{
   let counter=Arc::new(AtomicUsize::new(0));let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));let source=Source::new(text);let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:Arc::clone(&counter)};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);
   let streamed=prepare_original_stream_using(Path::new("actual-stream.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,Some(&batch)).unwrap_or_else(|actual|panic!("actual Analyze direct stream fatal={fatal} notice={notice}: {actual:?}"));
   assert_eq!(streamed.primary().frontier().is_some(),fatal);// Frozen Analyze parse_source consumes a short (<8192 token) producer
   // stream to EOF before sending its first batch, then joins and keeps all
   // preprocessor errors even when the parser's primary header is fatal.
   assert_eq!(streamed.plan().original_notices().iter().any(|row|row.message.contains("MUST_NOT_BE_CONSUMED")),notice,"Analyze delivery must preserve the actual producer batch notice, independently of primary prefix completion");
   let input=&streamed.primary().inputs()[0];assert!(input.source().same_view(&streamed.expanded().text));assert!(input.headers().all_formal_notices().unwrap().next().is_some(),"actual var/ formal notice must reach retained header owner");
   let parameters=input.headers();assert!(parameters.formal_source_matches(&streamed.expanded().text,0));
   drop(streamed);assert_eq!(counter.load(Ordering::Acquire),0);assert_eq!(source_live.load(Ordering::Acquire),0);
  }
 }
 #[test]
 fn actual_stream_body_layout_borrows_issued_interpolation_facts_without_dense_tokens(){
  let counter=Arc::new(AtomicUsize::new(0));let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));
  let source=Source::new("/proc/earlier()\n    return 0\n/proc/interp_body(value)\n    var/message = \"literal { ; [value] }\"\n    return message\n");
  let streamed=prepare_original_stream_using(Path::new("actual-interp-body.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,None).unwrap();
  assert!(streamed.primary().frontier().is_none());
  let input=&streamed.primary().inputs()[0];let headers=input.headers();
  let owner=headers.shared_span_tokens().unwrap();
  assert!(owner.same_owner(streamed.expanded().tokens.shared().unwrap()));
  assert!(owner.window().as_dense_slice().is_none());
  let item=input.ast().items.iter().find(|row|row.header.contains("interp_body")).unwrap();
  let facts=headers.original_literal_facts().unwrap().unwrap();
  assert!(facts.raw_parts().0.iter().any(|(_,row)|matches!(row.value(),dm_syntax::OriginalTokenValue::InterpBegin(_))));
  let parsed=headers.parse_body(item.span,0).unwrap();
  assert_eq!(parsed.item.children.len(),2,"fragment punctuation must not split a native statement");
  assert!(parsed.item.children[0].header.contains("[value]"));
  assert_eq!(parsed.item.children[1].header,"return message");
  drop(parsed);drop(streamed);
  assert_eq!(counter.load(Ordering::Acquire),0);assert_eq!(source_live.load(Ordering::Acquire),0);
 }
 #[test]fn source_operational_error_survives_streamed_frontend_boundary(){let counter=Arc::new(AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));let live=Arc::new(AtomicUsize::new(0));let work=Work{live:live.clone(),fail:true};let source=Source::new("/proc/p(A=1)\n    return A\n");let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:Arc::clone(&counter)};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);let actual=prepare_original_stream_using(Path::new("actual-failed-stream.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,Some(&batch)).err().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);assert_eq!(live.load(Ordering::Acquire),0);}
 #[test]fn actual_streamed_frontend_publishes_header_defaults_without_body_and_preserves_purpose_barriers(){
  let source=Source::new("/proc/p(var/static/A=1)\n    return A\n");let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=super::super::declaration_checked_tests::original_test_host();
  let config=FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None};
  let frontend=super::super::build_for_original_analysis_with_state_checked(Path::new("actual-published-stream.dme"),&source,&BTreeMap::new(),config,None,&executor,None,&host).unwrap();
  let view=frontend.source_view().unwrap();assert!(view.original_plan().is_original_diagnostic());assert!(view.original_plan().ordinary().is_none());assert_eq!(view.bodies().len(),1);
  let signature=view.archive().header_parameters_using(0,&||Ok(())).unwrap();let parameters=signature.entries().unwrap();assert_eq!(parameters.len(),1);assert_eq!(signature.name(&parameters[0]).unwrap(),"A");
  assert_eq!(view.original_analysis_completeness(),Some(super::super::OriginalAnalysisCompleteness::Complete));drop(signature);drop(view);assert!(frontend.try_into_compilable().is_err(),"no completed Original diagnostic plan may become a compiler plan");
  let partial=super::super::build_for_original_handlers_structural_checked(Path::new("actual-published-partial.dme"),&source,config,None,&executor,&host).unwrap();
  assert_eq!(partial.preparation_purpose(),super::super::DiagnosticPreparationPurpose::OriginalHandlersStructuralComplete);assert!(partial.original_analysis_completeness().is_none());assert!(partial.checker_source_view().is_err());let view=partial.source_view().unwrap();assert!(view.original_plan().ordinary().is_none());assert_eq!(view.archive().header_parameters_using(0,&||Ok(())).unwrap().entries().unwrap().len(),1);
 }

 #[test]fn strict_fatal_report_retains_same_source_credit_after_actual_host_drop_then_releases_all(){
  let concrete=super::original_resource_host::Host::new();let counter=Arc::clone(&concrete.counter);let host=concrete.clone()as Arc<dyn SettingExpressionQueries>;let source=Source::new("#warn EARLY_RAW_OWNER\n/proc/p(var/A=)\n#error FUTURE_UNPULLED\n");let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let result=super::super::build_for_checker_diagnostics_with_state_checked(Path::new("strict-source-owner.dme"),&source,&BTreeMap::new(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host);let report=match result{Err(FrontendBuildFailure::Diagnostics(report))=>report,Err(FrontendBuildFailure::Operational(actual))=>panic!("real strict source report required: {actual:?}"),Ok(_)=>panic!("malformed formal cannot issue graph")};
  drop(source);drop(executor);drop(host);drop(concrete);assert!(counter.load(Ordering::Acquire)>0,"actual retained raw/diagnostic payload still funds the same original counter after host disappears");let raw=report.original_preprocess_notices().unwrap();assert_eq!(raw.len(),1);let notice=raw.iter().next().unwrap().unwrap();assert!(notice.message.contains("EARLY_RAW_OWNER"));assert!(matches!(notice.point,super::super::OriginalDiagnosticPoint::Acquired{line:1,..}));drop(notice);drop(raw);drop(report);assert_eq!(counter.load(Ordering::Acquire),0,"no Weak or unfunded control allocation may survive last report");
 }

 #[test]fn productive_formal_member_recovery_keeps_actual_boundary_empty_selector_and_ordered_header_messages(){
  for(text,wanted,primitive)in[("/proc/p(var/value=world.)\n    return value\n",')',false),("/proc/p(value=world., next=2)\n    return value\n",',',false),("/proc/p(value=locate(world in world).)\n    return value\n",')',true)]{for batch_mode in[false,true]{
   let counter=Arc::new(AtomicUsize::new(0));let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));let source=Source::new(text);let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:Arc::clone(&counter)};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);
   let streamed=prepare_original_stream_using(Path::new("actual-member-formal.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,batch_mode.then_some(&batch)).unwrap_or_else(|actual|panic!("actual formal recovery {text:?} batch={batch_mode}: {actual:?}"));assert!(streamed.primary().frontier().is_none(),"recoverable missing selector must not become fatal or modelNone");
   let input=&streamed.primary().inputs()[0];let headers=input.headers();let rows=headers.all_formal_notices().unwrap().collect::<Vec<_>>();let recovery=rows.iter().position(|notice|notice.family()=="missing_member_identifier").expect("actual header-owned member diagnostic");if primitive{assert!(rows[..recovery].iter().any(|notice|notice.family()=="locate_in_argument"),"same Pratt primitive notice must precede member recovery");}let notice=rows[recovery];assert_eq!(notice.registration(),(None,crate::OriginalFormalNoticeLevel::Error));let message=headers.formal_notice_text(notice).unwrap().unwrap();assert_eq!(message,format!("got '{wanted}', expected one of: identifier"));let mut has_empty=false;headers.visit_default_roots(|root|{if matches!(&root.original_expression().kind,dm_syntax::ExprKind::Member{selector,..}if selector.is_empty()){has_empty=true}});assert!(has_empty,"same canonical default root must retain old empty member selector rather than replacing expression");drop(rows);drop(streamed);assert_eq!(counter.load(Ordering::Acquire),0);assert_eq!(source_live.load(Ordering::Acquire),0);
  }}
 }

 #[test]fn productive_formal_read_roles_preserve_same_default_roots_and_produced_metadata_in_lazy_and_batch(){
  for(text,wanted,annotation)in[("/proc/p(value=world.as)\n    return value\n","member",false),("/proc/p(value=world?.as, next=2)\n    return value\n","safe",false),("/proc/p(value=::as)\n    return value\n","global",false),("/proc/p(value=/datum/as as num)\n    return value\n","path",true)]{for batch_mode in[false,true]{
   let counter=Arc::new(AtomicUsize::new(0));let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));let source=Source::new(text);let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:Arc::clone(&counter)};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);
   let streamed=prepare_original_stream_using(Path::new("actual-read-role-formal.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,batch_mode.then_some(&batch)).unwrap_or_else(|actual|panic!("actual read role {wanted} batch={batch_mode}: {actual:?}"));assert!(streamed.primary().frontier().is_none(),"accepted real selector must not become fatal/prefix");let input=&streamed.primary().inputs()[0];let headers=input.headers();assert!(!headers.all_formal_notices().unwrap().any(|notice|notice.family()=="missing_member_identifier"),"actual Ident as is a selector, never missing-member recovery");
   let mut matching=0;headers.visit_default_roots(|root|{let actual=match(wanted,&root.original_expression().kind){("member",dm_syntax::ExprKind::Member{selector,..})|("safe",dm_syntax::ExprKind::SafeMember{selector,..})=>selector=="as",("global",dm_syntax::ExprKind::Unary{op,value})=>op=="::"&&matches!(&value.kind,dm_syntax::ExprKind::Ident(name)if name=="as"),("path",dm_syntax::ExprKind::TypePath(path))=>path=="/datum/as",_=>false};if actual{matching+=1}});assert_eq!(matching,1,"same genuine native default root is retained once");
   // The actual stream has already supplied ParameterClauseCursor spans to
   // complete_formal_produced/consume_produced. Adapter consumes that SAME
   // signature; no lexical rescan may turn a selector as into an annotation.
   let StreamedOriginalDeclarations{plan,expanded,primary}=streamed;let native=primary.adapt_for_original_outcome(&a).unwrap().into_current(&a).unwrap();let metadata=native.current()[0].skeletons().iter().find_map(|row|match row{crate::Skeleton::Member{metadata,..}=>metadata.procedure.clone(),_=>None}).unwrap();let parameters=&metadata.signature.parameters;assert_eq!(parameters.len(),if wanted=="safe"{2}else{1});assert!(parameters[0].default.is_some());assert_eq!(parameters[0].input_annotation.is_some(),annotation,"only actual produced annotation clause may set metadata");assert!(parameters[0].source_expression.is_none());drop(metadata);drop(native);drop((plan,expanded));assert_eq!(counter.load(Ordering::Acquire),0,"all same-owner aliases release batch={batch_mode}");assert_eq!(source_live.load(Ordering::Acquire),0);
  }}
 }

 #[test]fn productive_empty_parentheses_default_retains_native_null_and_exact_warning_in_lazy_and_batch(){for batch_mode in[false,true]{let counter=Arc::new(AtomicUsize::new(0));let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));let source=Source::new("/proc/p(value=())\n    return value\n");let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:Arc::clone(&counter)};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);let streamed=prepare_original_stream_using(Path::new("actual-empty-group.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,batch_mode.then_some(&batch)).unwrap();assert!(streamed.primary().frontier().is_none());let headers=streamed.primary().inputs()[0].headers();let rows=headers.all_formal_notices().unwrap().filter(|notice|notice.family()=="empty_parentheses").collect::<Vec<_>>();assert_eq!(rows.len(),1);assert_eq!(rows[0].registration(),(None,crate::OriginalFormalNoticeLevel::Warning));assert_eq!(rows[0].static_message(),Some("'()' should be replaced with 'null'"));let mut actual=0;headers.visit_default_roots(|root|{if matches!(&root.original_expression().kind,dm_syntax::ExprKind::Literal(value)if value.as_str()=="null"){actual+=1}});assert_eq!(actual,1);drop(rows);drop(streamed);assert_eq!(counter.load(Ordering::Acquire),0);assert_eq!(source_live.load(Ordering::Acquire),0);}}

}
