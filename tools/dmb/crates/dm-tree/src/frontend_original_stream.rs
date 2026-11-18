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
  let pending=self.0.with_original_batch_producer_admission(&mut|a|{
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
 committed_inputs:Option<Box<std::sync::Mutex<Option<super::committed_bodies::FinalCommittedBodyInputs>>>>,
}
impl StreamedOriginalDeclarations{
 pub(crate) fn plan(&self)->&OriginalDiagnosticPlan{&self.plan}
 pub(crate) fn expanded(&self)->&ExpandedRegions{&self.expanded}
 pub(crate) fn primary(&self)->&super::original_declaration_input::OrderedOriginalDeclarations{&self.primary}
 /// Run only the existing adapter, signature-alias owner, previous BODY-code
 /// convergence and current-leaf assembly after the real primary frontier.
 /// General constants run iff that frontier really is complete.
 pub(crate) fn into_prepared(self,engine:Option<&EngineSeed>,previous:Option<&DeclarationSyntax>,host:&dyn SettingExpressionQueries,a:&dm_syntax::SettingAdmission<'_>)->Result<(OriginalDiagnosticPlan,ExpandedRegions,super::original_declaration_input::PreparedOriginalDeclarations),FrontendBuildFailure>{self.into_prepared_with_code_mode(engine,previous,host,a,false)}
 pub(crate) fn into_prepared_with_code_mode(self,engine:Option<&EngineSeed>,previous:Option<&DeclarationSyntax>,host:&dyn SettingExpressionQueries,a:&dm_syntax::SettingAdmission<'_>,ordinary_demand:bool)->Result<(OriginalDiagnosticPlan,ExpandedRegions,super::original_declaration_input::PreparedOriginalDeclarations),FrontendBuildFailure>{
  if ordinary_demand&&self.committed_inputs.is_some(){return Err(FrontendBuildFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"ordinary Code demand cannot replace the committed BODY producer")))}
  if !self.primary.expanded().same_view(&self.expanded.text){return Err(FrontendBuildFailure::Operational(io::Error::new(io::ErrorKind::InvalidData,"streamed declaration primary detached from actual output arena")))}
  #[cfg(debug_assertions)]
  let trace = std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some();
  #[cfg(debug_assertions)]
  if trace { eprintln!("ORIGINAL_ADAPTER_CREDIT stage=before_adapt retained={}", a.retained_bytes_for_trace()); }
  let adapted=self.primary.adapt_for_original_outcome(a).map_err(FrontendBuildFailure::Operational)?;
  #[cfg(debug_assertions)]
  if trace { eprintln!("ORIGINAL_ADAPTER_CREDIT stage=after_adapt retained={}", a.retained_bytes_for_trace()); }
  let current=adapted.into_current_mode(a,ordinary_demand).map_err(FrontendBuildFailure::Operational)?;
  current.retain_signature_aliases(host,a).map_err(|error|match error{BodySyntaxFailure::Operational(actual)=>FrontendBuildFailure::Operational(actual),BodySyntaxFailure::Syntax(actual)=>FrontendBuildFailure::Diagnostics(vec![actual].into())})?;
  #[cfg(debug_assertions)]
  if trace { eprintln!("ORIGINAL_ADAPTER_CREDIT stage=aliases retained={}", a.retained_bytes_for_trace()); }
  let mut prepared=current.converge_previous_code(if self.committed_inputs.is_some(){None}else{previous},a).and_then(|current|current.into_prepared(engine,a)).map_err(FrontendBuildFailure::Operational)?;
  if let Some(inputs)=self.committed_inputs{let owner=Arc::get_mut(&mut prepared.retention).ok_or_else(||FrontendBuildFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"actual committed preparation escaped before Input transfer")))?;owner.install_committed_inputs(inputs).map_err(FrontendBuildFailure::Operational)?;}
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
 prepare_original_stream_with_lazy_body_parameters_using(
  project,provider,defines,omissions,max_raw_bytes,source_work,a,batch,false,
 )
}

pub(crate) fn prepare_original_stream_with_lazy_body_parameters_using(
 project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,
 omissions:GenerationOmissions,max_raw_bytes:usize,
 source_work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,
 a:&dm_syntax::SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,
 lazy_parameters:bool,
)->io::Result<StreamedOriginalDeclarations>{
 prepare_original_stream_with_parameter_mode_using(
  project,provider,defines,omissions,max_raw_bytes,source_work,a,batch,lazy_parameters,lazy_parameters,
 )
}

pub(crate) fn prepare_original_stream_with_parameter_mode_using(
 project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,
 omissions:GenerationOmissions,max_raw_bytes:usize,
 source_work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,
 a:&dm_syntax::SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,
 lazy_parameters:bool,compact_compound:bool,
)->io::Result<StreamedOriginalDeclarations>{
 prepare_original_stream_with_committed_body_consumer_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,batch,lazy_parameters,compact_compound,None)
}
/// Private opt-in decorator of the SAME actual diagnostic producer. It installs
/// no client/default behavior; final adoption must consume the returned owners.
pub(super) fn prepare_original_stream_with_committed_body_consumer_using(
 project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,
 omissions:GenerationOmissions,max_raw_bytes:usize,
 source_work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,
 a:&dm_syntax::SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,
 lazy_parameters:bool,compact_compound:bool,
 body:Option<&mut dyn crate::procedure::original_primary_signatures::CommittedBodySyntaxConsumer>,
)->io::Result<StreamedOriginalDeclarations>{
 prepare_original_stream_with_committed_body_reporting_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,batch,lazy_parameters,compact_compound,false,body)
}
pub(super) fn prepare_original_stream_with_committed_body_reporting_using(
 project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,
 omissions:GenerationOmissions,max_raw_bytes:usize,
 source_work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,
 a:&dm_syntax::SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,
 lazy_parameters:bool,compact_compound:bool,
 allow_formal_prefix:bool, mut body:Option<&mut dyn crate::procedure::original_primary_signatures::CommittedBodySyntaxConsumer>,
)->io::Result<StreamedOriginalDeclarations>{
 let mut observer=actual(a,||crate::procedure::original_primary_signatures::OriginalSignatureObserver::new(a))?;
 let product=actual(a,||{
  let mut decorated;
  let active:&mut dyn dm_preprocess::regions::OriginalPrimaryStreamConsumer=if let Some(body)=body.as_deref_mut(){decorated=crate::procedure::original_primary_signatures::CommittedSignatureConsumer{observer:&mut observer,body};&mut decorated}else{&mut observer};
  if compact_compound{
   let batch=batch.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"compact compound diagnostics require actual batch execution"))?;
   GenerationDirectivePlan::prepare_original_compound_diagnostic_stream_using(
     project,provider,defines,omissions,max_raw_bytes,source_work,a,batch,active)
 }else{
   GenerationDirectivePlan::prepare_original_diagnostic_stream_using(
     project,provider,defines,omissions,max_raw_bytes,source_work,a,batch,active)
 }}).inspect_err(|_error|{
  #[cfg(debug_assertions)]
  observer.trace_failed_stream_retention("raw_product");
  #[cfg(test)]
  eprintln!("ORIGINAL_STREAM_STAGE=raw_product {_error:?}");
 })?;
 #[cfg(debug_assertions)]
 observer.trace_live_stream_retention();
 let geometry=if compact_compound{product.header_token_geometry()}else{None};
 let(plan,expanded,primary,binding)=actual(a,||product.into_diagnostic_parts_using(a)).inspect_err(|_error|{
  #[cfg(debug_assertions)]
  observer.trace_failed_stream_retention("diagnostic_handoff");
  #[cfg(test)]
  eprintln!("ORIGINAL_STREAM_STAGE=diagnostic_handoff {_error:?}");
 })?;
 #[cfg(test)]if expanded.text.len()<=512{
  match &primary{
   dm_preprocess::regions::OriginalStreamPrimary::Dense(primary)=>eprintln!("actual Original produced arena: {:?}; primary items: {:#?}",expanded.text.as_str(),primary.syntax().items),
   dm_preprocess::regions::OriginalStreamPrimary::Committed(primary)=>eprintln!("actual Original produced arena: {:?}; primary items: {:#?}",expanded.text.as_str(),primary.items(&expanded.text)?.iter().collect::<Vec<_>>()),
  }
 }
 let prefix=if allow_formal_prefix&&primary.observer_stop().is_some(){if !observer.has_actual_formal_fatal(){return Err(io::Error::new(io::ErrorKind::Unsupported,"report-only prefix requires the actual typed formal fatal"))}Some(body.as_deref_mut().ok_or_else(||super::committed_bodies::trace_invalid_input("original-stream-prefix: typed formal fatal has no committed BODY consumer"))?.formal_prefix_adoption(&primary,a)?)}else{None};
 let adoption=if prefix.is_some(){None}else{match body.as_deref_mut(){Some(body)=>{let end=observer.reader_registration.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual committed final reader registration is absent"))?;Some(body.final_adoption(&primary,end,a)?)},None=>None}};
 let(input,committed_inputs)=actual(a,||observer.finish_primary_for_ordered_adapter_with_body_handoffs(expanded.text.clone(),primary,Some(&binding),lazy_parameters,geometry.as_ref(),adoption,prefix).map_err(header_failure)).inspect_err(|_error|{#[cfg(test)]eprintln!("ORIGINAL_STREAM_STAGE=actual_header_finish {_error:?}")})?;
 drop(geometry);
 // Clauses, typed values and default roots have moved into the genuine header
 // owner; dropping the neutral binding now cannot detach those borrowed facts.
 let primary=super::original_declaration_input::OrderedOriginalDeclarations::from_actual_signature_input(input,a).inspect_err(|_error|{#[cfg(test)]eprintln!("ORIGINAL_STREAM_STAGE=current_signature_input {_error:?}")})?;
 actual(a,||a.checkpoint())?;Ok(StreamedOriginalDeclarations{plan,expanded,primary,committed_inputs})
}

#[cfg(test)]mod batch_admission_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[derive(Debug)]struct Host{counter:Arc<dm_syntax::SettingChargeCounter>,mode:u8}
 impl SettingExpressionQueries for Host{
  fn expression(&self,_:&SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{panic!("this contract is a permit loan, not a second expression parser")}
  fn with_declaration_admission(&self,run:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{
   if self.mode==1{return Ok(())}let a=dm_syntax::SettingAdmission::new(&self.counter,1<<20,&||Ok(()));
   let result=run(&a);if self.mode==2{return Err(BodySyntaxFailure::Operational(io::Error::from_raw_os_error(87)))}result
  }
 }
 #[test]fn batch_worker_permit_uses_actual_host_counter_and_releases_lease(){let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let host=Host{counter:counter.clone(),mode:0};let adapter=TreeOriginalBatchHost(&host);let mut called=0;adapter.with_producer_admission(&mut|a|{called+=1;let lease=a.reserve(4096)?;assert!(counter.load(Ordering::Acquire)>=dm_syntax::SettingChargeCounter::root_allocation_bytes() + (4096));drop(lease);Ok(())}).unwrap();assert_eq!(called,1);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn actual_batch_worker_first_io_survives_host_cleanup_and_missing_loan_is_rejected(){let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let host=Host{counter:counter.clone(),mode:2};let error=TreeOriginalBatchHost(&host).with_producer_admission(&mut|_|Err(io::Error::from_raw_os_error(1450))).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));let host=Host{counter,mode:1};assert_eq!(TreeOriginalBatchHost(&host).with_producer_admission(&mut|_|panic!("omitted actual callback")).unwrap_err().kind(),io::ErrorKind::InvalidData);}
}

#[cfg(test)]pub(crate) mod actual_stream_controls{
 use super::*;use std::{any::Any,sync::atomic::{AtomicUsize,Ordering}};
 use dm_preprocess::source_arena_credit::{SourceArenaWork,SourceArenaCredit,SourceArenaCreditOwner};
 pub(crate) struct Source{raw:Vec<u8>,source:dm_preprocess::AcquiredSource}
 impl Source{pub(crate) fn new(text:&str)->Self{Self{raw:text.as_bytes().to_vec(),source:dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),())}}}
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
 #[derive(Debug)]struct StreamHost{counter:Arc<dm_syntax::SettingChargeCounter>}
 impl SettingExpressionQueries for StreamHost{
  fn expression(&self,_:&SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{panic!("direct productive stream control must not invoke a parallel compatibility expression parser")}
  fn with_declaration_admission(&self,run:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{
   let poll=||Ok(());let admission=dm_syntax::SettingAdmission::new(&self.counter,32<<20,&poll);let pending=run(&admission);if let Some(actual)=admission.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}if matches!(&pending,Err(BodySyntaxFailure::Operational(_))){return pending}admission.checkpoint().map_err(BodySyntaxFailure::Operational)?;pending
  }
 }
 fn omissions()->GenerationOmissions{GenerationOmissions::probe(std::iter::empty(),&mut|_|panic!("no synthetic omissions"),&mut|_|Ok(())).unwrap()}
 #[test]fn actual_produced_clause_rows_preserve_narrow_and_long_header_parameter_positions(){
  for batch_mode in [false,true]{
   let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();let live=Arc::new(AtomicUsize::new(0));let work=Work{live:live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));
   let text=format!("/proc/narrow(obj/value = null)\n    return value\n/proc/wide({}obj/value = null)\n    return value\n"," ".repeat(1<<16));let source=Source::new(&text);let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:counter.clone()};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);
   let streamed=prepare_original_stream_using(Path::new("actual-packed-clauses.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,batch_mode.then_some(&batch)).unwrap();assert!(streamed.primary().frontier().is_none());let input=&streamed.primary().inputs()[0];let headers=input.headers();let(count,bytes)=headers.clause_storage_for_test();assert_eq!(count,2);#[cfg(target_pointer_width="64")]assert_eq!(bytes,2*48,"actual final main rows own physically smaller backing");
   let items=input.items().unwrap();let mut seen=0;for item in items.iter().filter(|item|item.header().contains("/narrow(")||item.header().contains("/wide(")){let parameters=headers.parameter_signature(item.span()).unwrap();assert_eq!(parameters.header(),item.header_span());let entries=parameters.entries().unwrap();assert_eq!(entries.len(),1);assert_eq!(entries[0].type_path(input.source()).unwrap().as_deref(),Some("/obj"));let value=entries[0].expressions().unwrap().unwrap().default_root().unwrap();let mut matching=0;headers.visit_default_roots(|root|matching+=usize::from(value.same_root(root)));assert_eq!(matching,1,"each exact produced default keeps its genuine retained root");seen+=1;}assert_eq!(seen,2);
   drop(streamed);assert_eq!(counter.load(Ordering::Acquire),root);assert_eq!(live.load(Ordering::Acquire),0);
  }
 }
 #[test]fn productive_actual_stream_keeps_header_fatal_and_analyze_first_batch_notices(){
  for (text,fatal,notice)in[("/proc/p(var/static/A=1)\n    return A\n",false,false),("/proc/p(var/static/A=1)\n    return A\n#error MUST_NOT_BE_CONSUMED\n",false,true),("/proc/p(var/A=)\n",true,false),("/proc/p(var/A=)\n#error MUST_NOT_BE_CONSUMED\n",true,true)]{
   let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));let source=Source::new(text);let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:Arc::clone(&counter)};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);
   let streamed=prepare_original_stream_using(Path::new("actual-stream.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,Some(&batch)).unwrap_or_else(|actual|panic!("actual Analyze direct stream fatal={fatal} notice={notice}: {actual:?}"));
   assert_eq!(streamed.primary().frontier().is_some(),fatal);// Frozen Analyze parse_source consumes a short (<8192 token) producer
   // stream to EOF before sending its first batch, then joins and keeps all
   // preprocessor errors even when the parser's primary header is fatal.
   assert_eq!(streamed.plan().original_notices().iter().any(|row|row.message.contains("MUST_NOT_BE_CONSUMED")),notice,"Analyze delivery must preserve the actual producer batch notice, independently of primary prefix completion");
   let input=&streamed.primary().inputs()[0];assert!(input.source().same_view(&streamed.expanded().text));assert!(input.headers().all_formal_notices().unwrap().next().is_some(),"actual var/ formal notice must reach retained header owner");
   let parameters=input.headers();assert!(parameters.formal_source_matches(&streamed.expanded().text,0));
   drop(streamed);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(source_live.load(Ordering::Acquire),0);
  }
 }
 #[test]
 fn issued_header_geometry_requires_the_complete_exact_batch_source_and_tape() {
  let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();
  let counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();
  let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));
  let live=Arc::new(AtomicUsize::new(0));
  let work=Work{live:live.clone(),fail:false};
  let executor=dm_exec::BuildExecutor::new(1).unwrap();
  let host=StreamHost{counter:counter.clone()};
  let adapter=TreeOriginalBatchHost(&host);
  for (text,complete) in [("/proc/probe()\n    return \"é\"\n",true),("/proc/probe(value=)\n",false)] {
   let source=Source::new(text);
   let batch=OriginalBatchExecution::new(&source,&adapter,&executor);
   let mut observer=crate::procedure::original_primary_signatures::OriginalSignatureObserver::new(&a).unwrap();
   let product=GenerationDirectivePlan::prepare_original_compound_diagnostic_stream_using(
    Path::new("actual-header-geometry.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,&batch,&mut observer,
   ).unwrap();
   let geometry=product.header_token_geometry();
   assert_eq!(geometry.is_some(),complete);
   if let Some(geometry)=geometry {
    let expanded=product.expanded();
    let tokens=expanded.tokens.shared().unwrap();
    let exact=&expanded.text;
    assert!(geometry.matches(exact,tokens,&a));
    let foreign=dm_preprocess::SourceText::from(exact.as_str().to_owned());
    assert!(!geometry.matches(&foreign,tokens,&a));
    assert!(!geometry.matches(&exact.checked_view(0..1).unwrap(),tokens,&a));
    let rows:Vec<_>=tokens.window().iter().collect();
    let credit=a.reserve(rows.capacity()*std::mem::size_of::<dm_syntax::SpanToken>()).unwrap();
    let copied=dm_syntax::SharedSpanTokens::from_admitted_using(rows,credit,&a).unwrap();
    assert!(!geometry.matches(exact,&copied,&a));
    let foreign_counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();
    let foreign_admission=dm_syntax::SettingAdmission::new(&foreign_counter,32<<20,&||Ok(()));
    assert!(!geometry.matches(exact,tokens,&foreign_admission));
   }
   drop(product);
   drop(observer);
   assert_eq!(counter.load(Ordering::Acquire),root);
   assert_eq!(live.load(Ordering::Acquire),0);
  }
 }

 #[test]
 fn issued_compact_callable_spellings_keep_their_owner_across_the_engine_union() {
  for lazy_parameters in [false,true]{
  let root = dm_syntax::SettingChargeCounter::root_allocation_bytes();
  let counter = dm_syntax::SettingChargeCounter::try_new(root).unwrap();
  let a = dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));
  let live = Arc::new(AtomicUsize::new(0));
  let work = Work { live: live.clone(), fail: false };
  let executor = dm_exec::BuildExecutor::new(1).unwrap();
  let host = StreamHost { counter: counter.clone() };
  let adapter = TreeOriginalBatchHost(&host);
  let source = Source::new("/datum/scope
    proc/long_callable()
        return 1
/proc/exact_source_path()
    return 2
");
  let batch = OriginalBatchExecution::new(&source,&adapter,&executor);
  let streamed = prepare_original_stream_with_lazy_body_parameters_using(
   Path::new("actual-compact-symbols.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,Some(&batch),lazy_parameters,
  ).unwrap();
  assert!(!streamed.primary().frontier().is_some());
  assert_eq!(streamed.primary().inputs()[0].headers().lazy_body_parameters(),lazy_parameters);
  assert!(streamed.expanded.text.source_arena_payload_credit().is_some());
  assert!(streamed.expanded.text.source_arena_control_credit().is_some());
  let spelling = "/datum/scope/proc/long_callable";
  let id = dm_ir::SymbolId::of(spelling);
  let current = streamed.primary.adapt_for_original_outcome(&a).unwrap().into_current(&a).unwrap();
  let local = current.current()[0].symbols();
  assert_eq!(local.compact_spelling_len(),4,"two callable paths plus their two bare member names");
  assert!(local.shared_text(dm_ir::SymbolId::of("/datum/scope")).is_some(),"absolute type owner keeps its shared Arc contract");
  assert!(local.shared_text(id).is_none(),"callable spelling is compact storage, not a copied Arc<str>");
  let exact = "/proc/exact_source_path";
  let offset = streamed.expanded.text.find(exact).unwrap();
  assert_eq!(local.text(dm_ir::SymbolId::of(exact)).unwrap().as_ptr(),
   streamed.expanded.text[offset..].as_ptr());
  let address = local.text(id).unwrap().as_ptr();
  let seed = crate::checker_builtins::original_analysis_seed().unwrap();
  let prepared = current.into_prepared(Some(seed.frontend_seed()),&a).unwrap();
  assert_eq!(prepared.parsed.adapted.symbols.text(id).unwrap().as_ptr(),address);
  let detached = prepared.parsed.adapted.symbols.clone();
  drop(prepared);
  drop(streamed.expanded);
  drop(streamed.plan);
  assert_eq!(detached.text(id),Some(spelling));
  assert_eq!(detached.text(id).unwrap().as_ptr(),address);
  assert!(counter.load(Ordering::Acquire)>root);
  drop(detached);
  assert_eq!(counter.load(Ordering::Acquire),root);
  assert_eq!(live.load(Ordering::Acquire),0);
  }
 }

 #[test]
 fn actual_lazy_body_realizes_only_its_parameter_owner_and_preserves_first_io() {
  for compact_compound in [false,true] {
  let root = dm_syntax::SettingChargeCounter::root_allocation_bytes();
  let counter = dm_syntax::SettingChargeCounter::try_new(root).unwrap();
  let live = Arc::new(AtomicUsize::new(0));
  let work = Work { live: live.clone(), fail: false };
  let a = dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));
  let source = Source::new("/proc/typed(obj/value = null)
    return value
/proc/unused()
    return
");
  let executor = dm_exec::BuildExecutor::new(1).unwrap();
  let host = StreamHost { counter: counter.clone() };
  let adapter = TreeOriginalBatchHost(&host);
  let batch = OriginalBatchExecution::new(&source,&adapter,&executor);
  let streamed = prepare_original_stream_with_parameter_mode_using(
    Path::new("actual-lazy-parameters.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,Some(&batch),true,compact_compound,
  ).unwrap();
  let input = &streamed.primary().inputs()[0];
  let headers = input.headers();
  let body = input.items().unwrap().iter().find(|item|item.header().contains("/typed(")).unwrap().span();
  let before = counter.load(Ordering::Acquire);
  assert!(headers.parameter_signature(body).is_err());
  let stopped = dm_syntax::SettingAdmission::new(&counter,32<<20,&||Err(io::Error::from_raw_os_error(1450)));
  assert_eq!(headers.parse_body_admitted(body,0,&stopped).err().unwrap().raw_os_error(),Some(1450));
  assert_eq!(counter.load(Ordering::Acquire),before);
  let denied = dm_syntax::SettingAdmission::new(&counter,before,&||Ok(()));
  assert_eq!(headers.parse_body_admitted(body,0,&denied).err().unwrap().kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(counter.load(Ordering::Acquire),before);
  let issued = headers.parse_body_admitted(body,0,&a).unwrap().unwrap();
  assert_eq!(issued.parameters.entries().unwrap()[0].type_path(input.source()).unwrap().as_deref(),Some("/obj"));
  let alias = issued.parameters.entries().unwrap()[0].expressions().unwrap().unwrap().default_root().unwrap();
  headers.visit_default_roots(|actual|assert!(alias.same_root(actual)));
  assert!(headers.parameter_signature(body).is_err(),"demand never installs a per-header cache");
  drop(issued);
  assert_eq!(counter.load(Ordering::Acquire),before);
  drop(streamed);
  assert_eq!(counter.load(Ordering::Acquire),root);
  assert_eq!(live.load(Ordering::Acquire),0);
  }
 }

 #[test]
 fn actual_plain_empty_checker_metadata_uses_the_issued_header_and_body_owner() {
  use crate::procedure::header_input::PLAIN_EMPTY_PARAMETER_SIGNATURES;
  for batch_mode in [false, true] {
   let counter = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let source_live = Arc::new(AtomicUsize::new(0));
   let work = Work { live: Arc::clone(&source_live), fail: false };
   let a = dm_syntax::SettingAdmission::new(&counter, 32 << 20, &|| Ok(()));
   let source = Source::new(concat!(
       "/proc/empty()\n    return 0\n",
       "/proc/with_parameter(obj/value = null)\n    return value\n",
       "/proc/last_empty()\n    return 0\n",
   ));
   let executor = dm_exec::BuildExecutor::new(1).unwrap();
   let host = StreamHost { counter: Arc::clone(&counter) };
   let adapter = TreeOriginalBatchHost(&host);
   let batch = OriginalBatchExecution::new(&source, &adapter, &executor);
   let before = PLAIN_EMPTY_PARAMETER_SIGNATURES.with(|n| n.get());
   let streamed = prepare_original_stream_using(Path::new("actual-plain-empty.dme"),
       &source, &BTreeMap::new(), omissions(), 1 << 20, &work, &a,
       batch_mode.then_some(&batch)).unwrap();
   assert!(streamed.primary().frontier().is_none());
   let input = &streamed.primary().inputs()[0];
   let headers = input.headers();
   assert_eq!(PLAIN_EMPTY_PARAMETER_SIGNATURES.with(|n| n.get()), before + 2);
   let (clause_rows, funded_bytes) = headers.clause_storage_for_test();
   assert_eq!(clause_rows, 1, "only the typed formal has a requestable clause");
   assert!(funded_bytes > 0, "the actual clause index must have its own credit");
   let items = input.items().unwrap();
   let empty = items.iter().find(|item| item.header().contains("/empty(")).unwrap();
   let metadata = headers.parameter_signature(empty.span()).unwrap();
   assert_eq!(metadata.header(), empty.header_span());
   assert!(metadata.entries().unwrap().is_empty());
   assert!(metadata.absolute_declarations().unwrap().is_empty());
   assert!(metadata.is_admitted_by(&a));
   let body = headers.parse_body(empty.span(), 0).unwrap();
   assert!(matches!(&body.parameters, dm_syntax::ProcedureParameters::Shared(actual)
       if actual.same_owner(metadata)));
   let alias = metadata.clone();
   let typed = items.iter().find(|item| item.header().contains("/with_parameter(")).unwrap();
   let fallback = headers.parameter_signature(typed.span()).unwrap();
   assert_eq!(fallback.entries().unwrap()[0].type_path(input.source()).unwrap().as_deref(), Some("/obj"));
   let default = fallback.entries().unwrap()[0].expressions().unwrap().unwrap().default_root().unwrap();
   headers.visit_default_roots(|root| assert!(default.same_root(root)));
   let mut roots = 0;
   headers.visit_default_roots(|_| roots += 1);
   assert_eq!(roots, 1);
   drop((body, streamed));
   assert!(alias.is_admitted_by(&a));
   assert!(counter.load(Ordering::Acquire) > dm_syntax::SettingChargeCounter::root_allocation_bytes());
   drop(alias);
   assert_eq!(counter.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
   assert_eq!(source_live.load(Ordering::Acquire), 0);
  }
 }
 #[test]
 fn actual_stream_body_layout_borrows_issued_interpolation_facts_without_dense_tokens(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));
  let source=Source::new("/proc/earlier()\n    return 0\n/proc/interp_body(value)\n    var/message = \"literal { ; [value] }\"\n    return message\n");
  let streamed=prepare_original_stream_using(Path::new("actual-interp-body.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,None).unwrap();
  assert!(streamed.primary().frontier().is_none());
  let input=&streamed.primary().inputs()[0];let headers=input.headers();
  let owner=headers.shared_span_tokens().unwrap();
  assert!(owner.same_owner(streamed.expanded().tokens.shared().unwrap()));
  assert!(owner.window().as_dense_slice().is_none());
  let item=input.items().unwrap().iter().find(|row|row.header().contains("interp_body")).unwrap();
  assert_eq!(item.header().as_ptr(),input.source()[item.header_span().range()].as_ptr());
  let facts=headers.original_literal_facts().unwrap().unwrap();
  assert!(facts.raw_parts().0.iter().any(|(_,row)|matches!(row.value().unwrap(),dm_syntax::OriginalTokenValue::InterpBegin(_))));
  let parsed=headers.parse_body(item.span(),0).unwrap();
  assert_eq!(parsed.item.children.len(),2,"fragment punctuation must not split a native statement");
  assert!(parsed.item.children[0].header.contains("[value]"));
  assert_eq!(parsed.item.children[1].header,"return message");
  drop(parsed);drop(streamed);
  assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(source_live.load(Ordering::Acquire),0);
 }
 #[test]
 fn live_original_body_slots_skip_hashing_and_reordered_bodies_use_the_exact_fallback() {
  use super::super::relative_declarations::code_recipe_hashes;
  let host=super::original_resource_host::Host::new();
  let counter=Arc::clone(&host.counter);
  let source_live=Arc::new(AtomicUsize::new(0));
  let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));
  let work=Work{live:Arc::clone(&source_live),fail:false};
  let build=|text:&str,previous:Option<&DeclarationSyntax>|{
   let source=Source::new(text);
   prepare_original_stream_using(Path::new("actual-body-slots.dme"),&source,&BTreeMap::new(),
      omissions(),1<<20,&work,&a,None).unwrap().into_prepared(None,previous,host.as_ref(),&a).unwrap()
  };
  let p="/proc/p(value=1)\n    return value\n";
  let q="/proc/q()\n    return 2\n";
  let (old_plan,old_expanded,old)=build(&format!("{p}{q}"),None);
  let old_codes:Vec<_>=old.parsed.syntax.body_recipes().map(|recipe|recipe.code_identity()).collect();
  assert_eq!(old_codes.len(),2);
  let before=code_recipe_hashes();
  let (shifted_plan,shifted_expanded,shifted)=build(
     &format!("/datum/extra\n    var/a\n{p}{q}"),Some(&old.parsed.syntax));
  assert_eq!(code_recipe_hashes(),before,"warm live stream skips both hash walks");
  assert!(!old_plan.same_owner(&shifted_plan));
  assert!(!old_expanded.text.same_view(&shifted_expanded.text));
  for (old,current) in old.parsed.syntax.body_recipes().zip(shifted.parsed.syntax.body_recipes()){
   assert!(Arc::ptr_eq(&old.code_identity(),&current.code_identity()));
   assert!(current.span().start>old.span().start);
   assert!(!Arc::ptr_eq(old.setting_headers().unwrap(),current.setting_headers().unwrap()));
  }

  let (reordered_plan,reordered_expanded,reordered)=build(&format!("{q}{p}"),Some(&old.parsed.syntax));
  let reordered_codes:Vec<_>=reordered.parsed.syntax.body_recipes().map(|recipe|recipe.code_identity()).collect();
  assert!(code_recipe_hashes()>before,"changed ordinal exercises existing fallback");
  assert!(Arc::ptr_eq(&old_codes[1],&reordered_codes[0]));
  assert!(Arc::ptr_eq(&old_codes[0],&reordered_codes[1]));
  let (changed_plan,changed_expanded,changed)=build(
     &format!("{p}/proc/q()\n    return 3\n"),Some(&old.parsed.syntax));
  let changed_codes:Vec<_>=changed.parsed.syntax.body_recipes().map(|recipe|recipe.code_identity()).collect();
  assert!(Arc::ptr_eq(&old_codes[0],&changed_codes[0]));
  assert!(!Arc::ptr_eq(&old_codes[1],&changed_codes[1]));
  drop((old_plan,old_expanded,old,shifted_plan,shifted_expanded,shifted,
      reordered_plan,reordered_expanded,reordered,changed_plan,changed_expanded,changed,
      old_codes,reordered_codes,changed_codes));
  host.with_declaration_admission(&mut |_|Ok(())).unwrap();
  assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
  assert_eq!(source_live.load(Ordering::Acquire),0);
 }

 #[test]
 fn actual_original_image_dir_callable_roster_preserves_mixed_formals_and_values() {
  use crate::{MemberKind,DefinitionMode};
  use dm_ir::SymbolId;
  let source=Source::new(include_str!("../../../fixtures/unified_checks/image_dir_mixed_callable/probe.dm"));
  let seed=crate::checker_builtins::original_analysis_seed().unwrap();
  let executor=dm_exec::BuildExecutor::new(1).unwrap();
  let host=super::super::declaration_checked_tests::original_test_host();
  let config=FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None};
  let path=Path::new("image-dir-mixed.dme");
  let old_role=super::super::build_for_original_analysis_with_state_checked(path,&source,&BTreeMap::new(),config,None,&executor,None,&host);
  assert!(old_role.is_err(),"the ordinary Original capture still rejects unqualified mixed forms");
  let prepared=super::super::build_for_original_image_dir_checked(path,&source,&BTreeMap::new(),config,&executor,&host).unwrap();
  let select=|owner|prepared.callable(SymbolId::of(owner),SymbolId::of("choose_face"),&mut||Ok(())).unwrap();
  let archive=prepared.archive();
  let kind=|id|archive.tree().member(id).unwrap().kind;
  let body=|ordinal:usize| {
   let text=prepared.expanded_text().get(archive.occurrences()[ordinal].expanded_span.range()).unwrap();
   text.split_whitespace().collect::<String>()
  };
  let proc=select("/datum/proc_first");
  assert_eq!(proc.formal,proc.value);
  assert_eq!(kind(proc.value.unwrap()),MemberKind::Proc);
  let chosen_proc=body(proc.body.unwrap());
  assert!(chosen_proc.contains("SpacemanDMM_return_type=/image"),"{chosen_proc}");
  let verb=select("/datum/verb_first");
  assert_eq!(verb.formal,verb.value);
  assert_eq!(kind(verb.value.unwrap()),MemberKind::Verb);
  assert!(body(verb.body.unwrap()).contains("SpacemanDMM_return_type=/turf"));
  let implicit=select("/datum/implicit_last");
  assert_ne!(implicit.formal,implicit.value);
  assert_eq!(archive.tree().member(implicit.value.unwrap()).unwrap().definition,DefinitionMode::Implicit);
  assert!(body(implicit.body.unwrap()).contains("SpacemanDMM_return_type=/image"));
  let annotated=select("/datum/first_annotation");
  assert_ne!(annotated.formal,annotated.value);
  assert!(archive.tree().member(annotated.formal.unwrap()).unwrap().metadata.procedure.as_ref().unwrap().signature.return_annotation.is_some());
  assert!(body(annotated.body.unwrap()).contains("SpacemanDMM_return_type=/turf"));
  let bodyless=select("/datum/bodyless_first");
  assert_eq!(bodyless.formal,bodyless.value);
  assert!(bodyless.value.is_some());
  assert!(!body(bodyless.body.unwrap()).contains("SpacemanDMM_return_type"));
  let child=select("/datum/inherited_mixed/child");
  assert_eq!(child.formal,child.value);
  assert_eq!(kind(child.formal.unwrap()),MemberKind::Verb);
  let losing=archive.occurrences().iter().find(|row|body(archive.callables().ordinal(row.member).unwrap()).contains("I.dir=2")).unwrap();
  assert_eq!(kind(losing.member),MemberKind::Verb);
  assert_ne!(select("/datum/losing_body").value,Some(losing.member));
  let error=prepared.callable(SymbolId::of("/datum/proc_first"),SymbolId::of("choose_face"),&mut||Err(io::Error::from_raw_os_error(1450))).unwrap_err();
  assert_eq!(error.raw_os_error(),Some(1450));
 }
 #[test]fn source_operational_error_survives_streamed_frontend_boundary(){let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));let live=Arc::new(AtomicUsize::new(0));let work=Work{live:live.clone(),fail:true};let source=Source::new("/proc/p(A=1)\n    return A\n");let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:Arc::clone(&counter)};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);let actual=prepare_original_stream_using(Path::new("actual-failed-stream.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,Some(&batch)).err().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(live.load(Ordering::Acquire),0);}
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

 #[test]
 fn joined_handler_formal_mode_preserves_actual_default_and_fatal_prefix() {
  let host=super::original_resource_host::Host::new() as Arc<dyn SettingExpressionQueries>;
  let seed=crate::checker_builtins::original_analysis_seed().unwrap();
  let executor=dm_exec::BuildExecutor::new(1).unwrap();
  let config=FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None};
  let path=Path::new("actual-handler-formal-parity.dme");
  let source=Source::new("/proc/p(obj/A = null)\n    return A\n");
  let eager=super::super::build_for_original_handlers_structural_checked(path,&source,config,None,&executor,&host).unwrap();
  let lazy=super::super::build_for_joined_original_handlers_structural_checked(path,&source,config,None,&executor,&host).unwrap();
  let eager=eager.handlers_structural_source().unwrap();
  let lazy=lazy.handlers_structural_source().unwrap();
  assert_eq!(eager.completeness(),lazy.completeness());
  assert_eq!(lazy.completeness(),super::super::OriginalAnalysisCompleteness::Complete);
  let eager=eager.view().archive();
  let lazy=lazy.view().archive();
  assert!(lazy.header_parameters_using(0,&||Ok(())).is_err());
  let before=eager.header_parameters_using(0,&||Ok(())).unwrap();
  assert_eq!(before.name(&before.entries().unwrap()[0]).unwrap(),"A");
  host.with_declaration_admission(&mut |a|{
   lazy.with_header_parameters_admitted(0,a,|actual|{
    let entries=actual.entries().unwrap();
    assert_eq!(entries.len(),1);
    assert_eq!(actual.name(&entries[0]).unwrap(),"A");
    Ok(())
   })
  }).unwrap();

  let malformed=Source::new("#warn EARLY_HANDLER\n/proc/p(var/A=)\n#error FUTURE_HANDLER\n");
  let eager=super::super::build_for_original_handlers_structural_checked(path,&malformed,config,None,&executor,&host).unwrap();
  let lazy=super::super::build_for_joined_original_handlers_structural_checked(path,&malformed,config,None,&executor,&host).unwrap();
  for outcome in [&eager,&lazy] {
   let structural=outcome.handlers_structural_source().unwrap();
   assert_eq!(structural.completeness(),super::super::OriginalAnalysisCompleteness::PrimaryPrefix);
   let notices=structural.view().original_preprocess_notices().unwrap();
   // Both Handler builders use actual AnalyzeBatch8192x64 delivery. This
   // short source's directives are processed while filling the first batch,
   // before the primary receiver can stop at the malformed formal. Producer
   // read-ahead does not turn this genuine PrimaryPrefix into complete input.
   assert_eq!(notices.len(),2);
   let mut actual=notices.iter();
   let early=actual.next().unwrap().unwrap();
   assert_eq!(early.message,"#warn EARLY_HANDLER");
   assert_eq!(early.severity,dm_preprocess::regions::OriginalNoticeSeverity::Warning);
   assert!(matches!(early.point,super::super::OriginalDiagnosticPoint::Acquired{line:1,..}));
   let future=actual.next().unwrap().unwrap();
   assert_eq!(future.message,"#error FUTURE_HANDLER");
   assert_eq!(future.severity,dm_preprocess::regions::OriginalNoticeSeverity::Error);
   assert!(matches!(future.point,super::super::OriginalDiagnosticPoint::Acquired{line:3,..}));
   assert!(actual.next().is_none());
  }
 }

 #[test]fn strict_fatal_report_retains_same_source_credit_after_actual_host_drop_then_releases_all(){
  let concrete=super::original_resource_host::Host::new();let counter=Arc::clone(&concrete.counter);let host=concrete.clone()as Arc<dyn SettingExpressionQueries>;let source=Source::new("#warn EARLY_RAW_OWNER\n/proc/p(var/A=)\n#error FUTURE_UNPULLED\n");let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let result=super::super::build_for_checker_diagnostics_with_state_checked(Path::new("strict-source-owner.dme"),&source,&BTreeMap::new(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host);let report=match result{Err(FrontendBuildFailure::Diagnostics(report))=>report,Err(FrontendBuildFailure::Operational(actual))=>panic!("real strict source report required: {actual:?}"),Ok(_)=>panic!("malformed formal cannot issue graph")};
  drop(source);drop(executor);drop(host);drop(concrete);assert!(counter.load(Ordering::Acquire)>dm_syntax::SettingChargeCounter::root_allocation_bytes(),"actual retained raw/diagnostic payload still funds the same original counter after host disappears");let raw=report.original_preprocess_notices().unwrap();assert_eq!(raw.len(),1);let notice=raw.iter().next().unwrap().unwrap();assert!(notice.message.contains("EARLY_RAW_OWNER"));assert!(matches!(notice.point,super::super::OriginalDiagnosticPoint::Acquired{line:1,..}));drop(notice);drop(raw);drop(report);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes(),"no Weak or unfunded control allocation may survive last report");
 }

 #[test]fn productive_formal_member_recovery_keeps_actual_boundary_empty_selector_and_ordered_header_messages(){
  for(text,wanted,primitive)in[("/proc/p(var/value=world.)\n    return value\n",')',false),("/proc/p(value=world., next=2)\n    return value\n",',',false),("/proc/p(value=locate(world in world).)\n    return value\n",')',true)]{for batch_mode in[false,true]{
   let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));let source=Source::new(text);let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:Arc::clone(&counter)};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);
   let streamed=prepare_original_stream_using(Path::new("actual-member-formal.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,batch_mode.then_some(&batch)).unwrap_or_else(|actual|panic!("actual formal recovery {text:?} batch={batch_mode}: {actual:?}"));assert!(streamed.primary().frontier().is_none(),"recoverable missing selector must not become fatal or modelNone");
   let input=&streamed.primary().inputs()[0];let headers=input.headers();let rows=headers.all_formal_notices().unwrap().collect::<Vec<_>>();let recovery=rows.iter().position(|notice|notice.family()=="missing_member_identifier").expect("actual header-owned member diagnostic");if primitive{assert!(rows[..recovery].iter().any(|notice|notice.family()=="locate_in_argument"),"same Pratt primitive notice must precede member recovery");}let notice=rows[recovery];assert_eq!(notice.registration(),(None,crate::OriginalFormalNoticeLevel::Error));let message=headers.formal_notice_text(notice).unwrap().unwrap();assert_eq!(message,format!("got '{wanted}', expected one of: identifier"));let mut has_empty=false;headers.visit_default_roots(|root|{if matches!(&root.original_expression().kind,dm_syntax::ExprKind::Member{selector,..}if selector.is_empty()){has_empty=true}});assert!(has_empty,"same canonical default root must retain old empty member selector rather than replacing expression");drop(rows);drop(streamed);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(source_live.load(Ordering::Acquire),0);
  }}
 }

 #[test]fn productive_formal_read_roles_preserve_same_default_roots_and_produced_metadata_in_lazy_and_batch(){
  for(text,wanted,annotation)in[("/proc/p(value=world.as)\n    return value\n","member",false),("/proc/p(value=world?.as, next=2)\n    return value\n","safe",false),("/proc/p(value=::as)\n    return value\n","global",false),("/proc/p(value=/datum/as as num)\n    return value\n","path",true)]{for batch_mode in[false,true]{
   let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));let source=Source::new(text);let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:Arc::clone(&counter)};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);
   let streamed=prepare_original_stream_using(Path::new("actual-read-role-formal.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,batch_mode.then_some(&batch)).unwrap_or_else(|actual|panic!("actual read role {wanted} batch={batch_mode}: {actual:?}"));assert!(streamed.primary().frontier().is_none(),"accepted real selector must not become fatal/prefix");let input=&streamed.primary().inputs()[0];let headers=input.headers();assert!(!headers.all_formal_notices().unwrap().any(|notice|notice.family()=="missing_member_identifier"),"actual Ident as is a selector, never missing-member recovery");
   let mut matching=0;headers.visit_default_roots(|root|{let actual=match(wanted,&root.original_expression().kind){("member",dm_syntax::ExprKind::Member{selector,..})|("safe",dm_syntax::ExprKind::SafeMember{selector,..})=>selector=="as",("global",dm_syntax::ExprKind::Unary{op,value})=>op=="::"&&matches!(&value.kind,dm_syntax::ExprKind::Ident(name)if name=="as"),("path",dm_syntax::ExprKind::TypePath(path))=>path=="/datum/as",_=>false};if actual{matching+=1}});assert_eq!(matching,1,"same genuine native default root is retained once");
   // The actual stream has already supplied ParameterClauseCursor spans to
   // complete_formal_produced/consume_produced. Adapter consumes that SAME
   // signature; no lexical rescan may turn a selector as into an annotation.
   let StreamedOriginalDeclarations{plan,expanded,primary,committed_inputs}=streamed;assert!(committed_inputs.is_none(),"ordinary stream must not retain committed BODY inputs");drop(committed_inputs);let native=primary.adapt_for_original_outcome(&a).unwrap().into_current(&a).unwrap();let metadata=native.current()[0].skeletons().iter().find_map(|row|match row{crate::Skeleton::Member{metadata,..}=>metadata.procedure.clone(),_=>None}).unwrap();let parameters=&metadata.signature.parameters;assert_eq!(parameters.len(),if wanted=="safe"{2}else{1});assert!(parameters[0].default.is_some());assert_eq!(parameters[0].input_annotation.is_some(),annotation,"only actual produced annotation clause may set metadata");assert!(parameters[0].source_expression.is_none());drop(metadata);drop(native);drop((plan,expanded));assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes(),"all same-owner aliases release batch={batch_mode}");assert_eq!(source_live.load(Ordering::Acquire),0);
  }}
 }

 #[test]
 fn actual_streamed_pending_buffers_keep_valid_defaults_and_input_annotations() {
    let arguments = (0..9).map(|n| format!("value{n}={n} as num")).collect::<Vec<_>>().join(", ");
    let text = format!("/proc/probe({arguments})\n    return value8\n");
    for batch_mode in [false, true] {
        let counter = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let source_live = Arc::new(AtomicUsize::new(0));
        let work = Work { live: Arc::clone(&source_live), fail: false };
        let a = dm_syntax::SettingAdmission::new(&counter, 32 << 20, &|| Ok(()));
        let source = Source::new(&text);
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        let host = StreamHost { counter: Arc::clone(&counter) };
        let adapter = TreeOriginalBatchHost(&host);
        let batch = OriginalBatchExecution::new(&source, &adapter, &executor);
        let streamed = prepare_original_stream_using(
            Path::new("actual-pending-formals.dme"), &source, &BTreeMap::new(),
            omissions(), 1 << 20, &work, &a, batch_mode.then_some(&batch),
        ).unwrap();
        assert!(streamed.primary().frontier().is_none());
        let mut defaults = 0;
        streamed.primary().inputs()[0].headers().visit_default_roots(|_| defaults += 1);
        assert_eq!(defaults, 9, "all genuine default roots survive two pending-buffer grows");
        let StreamedOriginalDeclarations { plan, expanded, primary, committed_inputs } = streamed;
        assert!(committed_inputs.is_none(), "ordinary stream must not retain committed BODY inputs");
        drop(committed_inputs);
        let native = primary.adapt_for_original_outcome(&a).unwrap().into_current(&a).unwrap();
        let skeletons = native.current()[0].skeletons();
        let metadata = skeletons.iter().find_map(|row| match row {
            crate::Skeleton::Member { metadata, .. } => metadata.procedure.as_ref(),
            _ => None,
        }).unwrap();
        assert_eq!(metadata.signature.parameters.len(), 9);
        assert!(metadata.signature.parameters.iter()
            .all(|parameter| parameter.default.is_some() && parameter.input_annotation.is_some()));
        drop(native);
        drop((plan, expanded));
        assert_eq!(counter.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
        assert_eq!(source_live.load(Ordering::Acquire), 0);
    }
 }

 #[test]fn productive_empty_parentheses_default_retains_native_null_and_exact_warning_in_lazy_and_batch(){for batch_mode in[false,true]{let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));let source=Source::new("/proc/p(value=())\n    return value\n");let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:Arc::clone(&counter)};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);let streamed=prepare_original_stream_using(Path::new("actual-empty-group.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,batch_mode.then_some(&batch)).unwrap();assert!(streamed.primary().frontier().is_none());let headers=streamed.primary().inputs()[0].headers();let rows=headers.all_formal_notices().unwrap().filter(|notice|notice.family()=="empty_parentheses").collect::<Vec<_>>();assert_eq!(rows.len(),1);assert_eq!(rows[0].registration(),(None,crate::OriginalFormalNoticeLevel::Warning));assert_eq!(rows[0].static_message(),Some("'()' should be replaced with 'null'"));let mut actual=0;headers.visit_default_roots(|root|{if matches!(&root.original_expression().kind,dm_syntax::ExprKind::Literal(value)if value.as_str()=="null"){actual+=1}});assert_eq!(actual,1);drop(rows);drop(streamed);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(source_live.load(Ordering::Acquire),0);}}


 #[test]
 fn original_reader_registration_commits_full_bodies_and_retains_actual_end() {
  for batch_mode in [false,true]{
   let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));
   let text="/proc/first(var/value)\n    if(value)\n        return value\n/proc/second(static/value)\n    return value\n";let source=Source::new(text);let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:Arc::clone(&counter)};let adapter=TreeOriginalBatchHost(&host);let batch=OriginalBatchExecution::new(&source,&adapter,&executor);
   let streamed=prepare_original_stream_using(Path::new("actual-registration.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,batch_mode.then_some(&batch)).unwrap();assert!(streamed.primary().frontier().is_none());
   let input=&streamed.primary().inputs()[0];let headers=input.headers();let items=input.items().unwrap();let first=items.iter().find(|item|item.header().contains("/first(")).unwrap().header_span();let second=items.iter().find(|item|item.header().contains("/second(")).unwrap().header_span();
   let first_commit=headers.reader_commit_registration(first,0).unwrap();let second_commit=headers.reader_commit_registration(second,0).unwrap();let end=headers.reader_end_registration().unwrap();end.require_after_actual_end().unwrap();
   let notices=headers.all_formal_notices().unwrap().collect::<Vec<_>>();assert_eq!(notices.len(),2);let first_notice=headers.formal_notice_registration(notices[0]).unwrap();let second_notice=headers.formal_notice_registration(notices[1]).unwrap();
   assert_eq!(first_notice.compare_same_source(&first_commit).unwrap(),std::cmp::Ordering::Less);assert_eq!(first_commit.compare_same_source(second_notice).unwrap(),std::cmp::Ordering::Less);assert_ne!(second_notice.compare_same_source(&second_commit).unwrap(),std::cmp::Ordering::Greater);assert_ne!(second_commit.compare_same_source(&end).unwrap(),std::cmp::Ordering::Greater);
   assert!(headers.reader_commit_registration(dm_syntax::Span::new(first.start,first.end-1),0).is_err());
   drop(notices);drop(streamed);
   assert!(counter.load(Ordering::Acquire)>dm_syntax::SettingChargeCounter::root_allocation_bytes(),"actual neutral registration owner stays funded while receipt clones survive");
   drop((first_commit,second_commit,end));
   assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(source_live.load(Ordering::Acquire),0);
  }
 }
 #[test]
 fn original_reader_registration_actual_end_exists_without_callable_rows() {
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,16<<20,&||Ok(()));let source=Source::new("/datum/empty\n    var/value=1\n");
  let streamed=prepare_original_stream_using(Path::new("actual-registration-empty.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,None).unwrap();assert!(streamed.primary().frontier().is_none());streamed.primary().inputs()[0].headers().reader_end_registration().unwrap().require_after_actual_end().unwrap();drop(streamed);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(source_live.load(Ordering::Acquire),0);
 }

 #[test]
 fn original_reader_prefix_failure_never_issues_actual_end_registration() {
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let source_live=Arc::new(AtomicUsize::new(0));let work=Work{live:source_live.clone(),fail:false};let a=dm_syntax::SettingAdmission::new(&counter,16<<20,&||Ok(()));let source=Source::new("/proc/fail(var/value=)\n    return value\n/proc/future()\n    return 2\n");
  let streamed=prepare_original_stream_using(Path::new("actual-registration-prefix.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,None).unwrap();assert!(streamed.primary().frontier().is_some());assert!(streamed.primary().inputs()[0].headers().reader_end_registration().is_err());drop(streamed);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(source_live.load(Ordering::Acquire),0);
 }

 #[test]
 fn original_reader_archive_commit_lookup_uses_actual_body_owner_not_header_extent() {
  let source=Source::new("/proc/p(var/value)\n    if(value)\n        return value\n/proc/q()\n    return 2\n");let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=super::super::declaration_checked_tests::original_test_host();let config=FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None};
  let frontend=super::super::build_for_original_analysis_with_state_checked(Path::new("actual-registration-archive.dme"),&source,&BTreeMap::new(),config,None,&executor,None,&host).unwrap();let view=frontend.source_view().unwrap();let archive=view.archive();let headers=archive.callable_header_source();assert_eq!(archive.occurrences().len(),2);let first=headers.reader_commit_registration(archive.occurrences()[0].member).unwrap().expect("actual first commit");let second=headers.reader_commit_registration(archive.occurrences()[1].member).unwrap().expect("actual second commit");assert_eq!(first.compare_same_source(&second).unwrap(),std::cmp::Ordering::Less);headers.reader_end_registration().unwrap().expect("actual complete end").require_after_actual_end().unwrap();
 }
 #[test]fn native_full_parameter_demand_preserves_eager_formals_full_macros_and_refunds(){
  let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let path=Path::new("actual-native-demand.dme");
  let mut summaries=Vec::new();let mut retained=Vec::new();
  for demand in [false,true]{
   let concrete=super::original_resource_host::Host::new();let counter=Arc::clone(&concrete.counter);let host=concrete.clone()as Arc<dyn SettingExpressionQueries>;
   let source=Source::new("#define ACTUAL_PARAMETER_MACRO 7\n/proc/empty()\n    return 0\n/proc/typed(obj/A = null)\n    return A\n/proc/unused()\n    return (1 + )\n");
   let config=FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None};
   let build=if demand{super::super::build_for_original_native_parameter_demand_with_callable_anchors_checked}else{super::super::build_for_original_analysis_with_callable_anchors_checked};
   let frontend=build(path,&source,&BTreeMap::new(),config,None,&executor,None,&host,None).unwrap();
   assert_eq!(frontend.original_analysis_completeness(),Some(super::super::OriginalAnalysisCompleteness::Complete));assert!(frontend.checker_source_view().is_ok());
   let view=frontend.source_view().unwrap();let archive=view.archive();
   archive.callable_header_source().reader_end_registration().unwrap().unwrap().require_after_actual_end().unwrap();
   assert!(view.original_plan().final_macro("ACTUAL_PARAMETER_MACRO").unwrap().is_some(),"full actual macro table, not compact debug-only history");
   assert!(!frontend.preparation_original_primary().unwrap().compact_macro_history());
   retained.push(counter.load(Ordering::Acquire));
   assert_eq!(archive.header_parameters_using(0,&||Ok(())).is_err(),demand,"old borrowed API stays eager; private native route requires scoped admission");
   let mut rows=Vec::new();
   for ordinal in 0..archive.occurrences().len(){archive.with_header_parameters_using(ordinal,&||Ok(()),|parameters|{
    rows.push((parameters.header_span().unwrap(),parameters.entries().unwrap().iter().map(|entry|(parameters.name(entry).unwrap().to_owned(),parameters.type_path(entry).unwrap())).collect::<Vec<_>>()));Ok(())
   }).unwrap();}
   assert_eq!(counter.load(Ordering::Acquire),retained[retained.len()-1],"scoped demand retains no per-header cache or BODY product");
   summaries.push(rows);drop(view);assert!(frontend.try_into_compilable().is_err());drop(source);host.with_declaration_admission(&mut |_|Ok(())).unwrap();drop(host);drop(concrete);
   assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
  }
  assert_eq!(summaries[0],summaries[1]);assert!(retained[1]<retained[0],"actual same-source retained counter must decrease before BODY demand");
 }
 #[test]fn native_full_parameter_demand_keeps_first_io_cancel_prefix_and_same_host_recovery(){
  let concrete=super::original_resource_host::Host::new();let host=concrete.clone()as Arc<dyn SettingExpressionQueries>;let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let config=FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None};let path=Path::new("actual-native-demand-errors.dme");
  let source=Source::new("/proc/p(obj/A = null)\n    return A\n");let frontend=super::super::build_for_original_native_parameter_demand_with_callable_anchors_checked(path,&source,&BTreeMap::new(),config,None,&executor,None,&host,None).unwrap();
  let view=frontend.source_view().unwrap();let archive=view.archive();let before=concrete.counter.load(Ordering::Acquire);
  concrete.fail.store(true,Ordering::Release);let failure=archive.with_header_parameters_using(0,&||Ok(()),|_|->Result<(),BodySyntaxFailure>{panic!("failed admission cannot call consumer")}).unwrap_err();assert!(matches!(failure,BodySyntaxFailure::Operational(actual)if actual.raw_os_error()==Some(1450)));concrete.fail.store(false,Ordering::Release);
  let failure=archive.with_header_parameters_using(0,&||Err(io::ErrorKind::Interrupted.into()),|_|->Result<(),BodySyntaxFailure>{panic!("cancelled request cannot call consumer")}).unwrap_err();assert!(matches!(failure,BodySyntaxFailure::Operational(actual)if actual.kind()==io::ErrorKind::Interrupted));
  archive.with_header_parameters_using(0,&||Ok(()),|parameters|{assert_eq!(parameters.name(&parameters.entries().unwrap()[0]).unwrap(),"A");Ok(())}).unwrap();assert_eq!(concrete.counter.load(Ordering::Acquire),before);
  drop(view);drop(frontend);drop(source);
  let malformed=Source::new("#warn EARLY_NATIVE_DEMAND\n/proc/p(var/A=)\n#error FUTURE_NATIVE_DEMAND\n");
  for demand in [false,true]{let build=if demand{super::super::build_for_original_native_parameter_demand_with_callable_anchors_checked}else{super::super::build_for_original_analysis_with_callable_anchors_checked};let prefix=build(path,&malformed,&BTreeMap::new(),config,None,&executor,None,&host,None).unwrap();assert_eq!(prefix.original_analysis_completeness(),Some(super::super::OriginalAnalysisCompleteness::PrimaryPrefix));assert!(prefix.checker_source_view().is_err());let raw=prefix.source_view().unwrap();assert_eq!(raw.original_preprocess_notices().unwrap().len(),2);}
  drop(malformed);host.with_declaration_admission(&mut |_|Ok(())).unwrap();let counter=Arc::clone(&concrete.counter);drop(host);drop(concrete);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn native_full_parameter_demand_remembered_mode_never_borrows_compact_history(){
  let concrete=super::original_resource_host::Host::new();let host=concrete.clone()as Arc<dyn SettingExpressionQueries>;let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let config=FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None};let path=Path::new("actual-native-demand-modes.dme");let defines=BTreeMap::new();let source=Source::new("#define ACTUAL_MODE_MACRO 9\n/proc/p()\n    return ACTUAL_MODE_MACRO\n");
  let mut state=RetainedSemanticTree::new();
  for compact in [false,true]{let build=if compact{super::super::build_for_original_compound_with_callable_anchors_checked}else{super::super::build_for_original_native_parameter_demand_with_callable_anchors_checked};let frontend=Arc::new(build(path,&source,&defines,config,None,&executor,Some(&mut state),&host,None).unwrap());assert_eq!(frontend.preparation_original_primary().unwrap().compact_macro_history(),compact);assert_eq!(frontend.source_view().unwrap().original_plan().final_macro("ACTUAL_MODE_MACRO").is_err(),compact);state.remember_analysis_frontend(path,&defines,frontend).unwrap();assert!(state.previous_original_frontend(path,&defines,true,true,compact).is_some());assert!(state.previous_original_frontend(path,&defines,true,true,!compact).is_none());assert!(state.previous_original_frontend(path,&defines,true,false,false).is_none());}
  drop(state);drop(source);host.with_declaration_admission(&mut |_|Ok(())).unwrap();let counter=Arc::clone(&concrete.counter);drop(host);drop(concrete);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }


 #[test]
 fn compact_member_names_keep_later_formal_names_owned_and_type_paths_shared(){
  for lazy_parameters in [false,true]{
   let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&||Ok(()));let live=Arc::new(AtomicUsize::new(0));let work=Work{live:live.clone(),fail:false};let executor=dm_exec::BuildExecutor::new(1).unwrap();let host=StreamHost{counter:counter.clone()};let adapter=TreeOriginalBatchHost(&host);
   let source=Source::new("/datum/scope\n    var/fresh_member = 1\n    var/kept_formal = 2\n    proc/new_handler(kept_formal)\n        return kept_formal\n    fresh_member = 3\n");let batch=OriginalBatchExecution::new(&source,&adapter,&executor);
   let streamed=prepare_original_stream_with_lazy_body_parameters_using(Path::new("actual-member-names.dme"),&source,&BTreeMap::new(),omissions(),1<<20,&work,&a,Some(&batch),lazy_parameters).unwrap();assert!(streamed.primary().frontier().is_none());
   let current=streamed.primary.adapt_for_original_outcome(&a).unwrap().into_current(&a).unwrap();let local=current.current()[0].symbols();
   for name in ["fresh_member","new_handler"]{let id=dm_ir::SymbolId::of(name);assert_eq!(local.text(id),Some(name));assert!(local.shared_text(id).is_none(),"fresh bare member name must use actual compact storage");}
   for owned in ["/datum/scope","kept_formal"]{let id=dm_ir::SymbolId::of(owned);assert_eq!(local.text(id),Some(owned));assert!(local.shared_text(id).is_some(),"type owner and later formal retain their original shared allocation");}
   let names=current.current()[0].skeletons().iter().filter_map(|row|match row{crate::Skeleton::Member{owner,name,..}=>Some((local.text(*owner).unwrap().to_owned(),local.text(*name).unwrap().to_owned())),_=>None}).collect::<Vec<_>>();
   assert_eq!(names,[("/datum/scope".to_owned(),"fresh_member".to_owned()),("/datum/scope".to_owned(),"kept_formal".to_owned()),("/datum/scope".to_owned(),"new_handler".to_owned()),("/datum/scope".to_owned(),"fresh_member".to_owned())]);
   let id=dm_ir::SymbolId::of("fresh_member");let address=local.text(id).unwrap().as_ptr();let original=streamed.expanded.text.find("fresh_member").unwrap();assert_eq!(address,streamed.expanded.text[original..].as_ptr(),"member bytes are loaned from the actual immutable source, not copied into slabs");let seed=crate::checker_builtins::original_analysis_seed().unwrap();let prepared=current.into_prepared(Some(seed.frontend_seed()),&a).unwrap();assert_eq!(prepared.parsed.adapted.symbols.text(id).unwrap().as_ptr(),address);let detached=prepared.parsed.adapted.symbols.clone();drop(prepared);drop(streamed.expanded);drop(streamed.plan);assert_eq!(detached.text(id),Some("fresh_member"));assert_eq!(detached.text(id).unwrap().as_ptr(),address);drop(detached);assert_eq!(counter.load(Ordering::Acquire),root);assert_eq!(live.load(Ordering::Acquire),0);
  }
 }

 // Insert inside existing actual_stream_controls; these use its genuine raw
 // Original Source/provider and SAME admitted resource host, never a lexer shim.
 #[test]fn actual_initializer_debug_uses_same_retained_root_facts_and_refunds_scratch(){
  let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();
  for expression in ["1+2","list(1,2)","\"value\""]{
   let concrete=super::original_resource_host::Host::new();let counter=Arc::clone(&concrete.counter);let host=concrete.clone()as Arc<dyn SettingExpressionQueries>;
   let source=Source::new(&format!("/datum/probe\n    var/static/value = {expression}\n"));
   let frontend=super::super::build_for_original_native_parameter_demand_with_callable_anchors_checked(Path::new("actual-initializer-debug.dme"),&source,&BTreeMap::new(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host,None).unwrap();
   assert_eq!(frontend.original_analysis_completeness(),Some(super::super::OriginalAnalysisCompleteness::Complete));
   let cold=frontend.preparation_frontend();let plan=crate::initializers::capture_declaration_plan(&cold.snapshot,&cold.emission_order).unwrap();
   let ordinal=plan.plan().writes.iter().position(|write|matches!(&write.target,dm_ir::InitializerTarget::Shared{name,..}if *name==dm_ir::SymbolId::of("value"))).expect("actual authored static value row");
   let input=cold.original_initializer_input(&plan,ordinal).unwrap();let held=input.expression().unwrap();let before=counter.load(Ordering::Acquire);
   host.with_declaration_admission(&mut|a|{let formatted=input.original_debug_using(a,&mut|_|Ok(7))?;assert!(matches!(formatted.support(),dm_preprocess::original_expression_debug::DebugSupport::Complete));assert!(formatted.as_str().contains("Location { file: FileId(7)"));if expression=="1+2"{assert!(formatted.as_str().starts_with("BinaryOp { op: Add, lhs: "));assert!(formatted.as_str().contains("elem: Int(1)"));assert!(formatted.as_str().contains("elem: Int(2)"));}else if expression.starts_with("list"){assert!(formatted.as_str().contains("elem: List(["));}else{assert!(formatted.as_str().contains("elem: String(\"value\")"));}drop(formatted);assert!(input.expression()?.same_root(&held));Ok(())}).unwrap();
   assert_eq!(counter.load(Ordering::Acquire),before,"only SAME held root survives; Debug scratch fully refunds");
   drop(held);drop(input);drop(plan);drop(frontend);drop(source);host.with_declaration_admission(&mut|_|Ok(())).unwrap();drop(host);drop(concrete);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]fn actual_initializer_debug_keeps_first_io_foreign_owner_and_same_host_recovery(){
  let concrete=super::original_resource_host::Host::new();let counter=Arc::clone(&concrete.counter);let host=concrete.clone()as Arc<dyn SettingExpressionQueries>;let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let source=Source::new("/datum/probe\n    var/static/value = 1+2\n");
  let frontend=super::super::build_for_original_native_parameter_demand_with_callable_anchors_checked(Path::new("actual-initializer-debug-errors.dme"),&source,&BTreeMap::new(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host,None).unwrap();let cold=frontend.preparation_frontend();let plan=crate::initializers::capture_declaration_plan(&cold.snapshot,&cold.emission_order).unwrap();let ordinal=plan.plan().writes.iter().position(|write|matches!(&write.target,dm_ir::InitializerTarget::Shared{name,..}if *name==dm_ir::SymbolId::of("value"))).unwrap();let input=cold.original_initializer_input(&plan,ordinal).unwrap();let held=input.expression().unwrap();let before=counter.load(Ordering::Acquire);
  let stop=||Err(io::Error::from_raw_os_error(1450));let a=dm_syntax::SettingAdmission::new(&counter,128<<20,&stop);let failure=input.original_debug_using(&a,&mut|_|panic!("actual admission IO precedes file mapping")).err().unwrap();assert!(matches!(failure,BodySyntaxFailure::Operational(actual)if actual.raw_os_error()==Some(1450)));
  let foreign=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&foreign,128<<20,&||Ok(()));let failure=input.original_debug_using(&a,&mut|_|panic!("foreign owner cannot format")).err().unwrap();assert!(matches!(failure,BodySyntaxFailure::Operational(actual)if actual.kind()==io::ErrorKind::InvalidInput));
  host.with_declaration_admission(&mut|a|{let mut files=0;let failure=input.original_debug_using(a,&mut|_|{files+=1;Err(io::Error::from_raw_os_error(1450))}).err().unwrap();assert!(matches!(failure,BodySyntaxFailure::Operational(actual)if actual.raw_os_error()==Some(1450)));assert_eq!(files,1,"no later term after first actual file-map IO");Ok(())}).unwrap();assert_eq!(counter.load(Ordering::Acquire),before);
  host.with_declaration_admission(&mut|a|{let text=input.original_debug_using(a,&mut|_|Ok(9))?;assert!(matches!(text.support(),dm_preprocess::original_expression_debug::DebugSupport::Complete));drop(text);Ok(())}).unwrap();assert_eq!(counter.load(Ordering::Acquire),before);assert!(input.expression().unwrap().same_root(&held));
  drop(held);drop(input);drop(plan);drop(frontend);drop(source);host.with_declaration_admission(&mut|_|Ok(())).unwrap();drop(host);drop(concrete);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(foreign.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn actual_original_utility_values_keep_typed_null_new_array_and_relative_paths(){
  let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let concrete=super::original_resource_host::Host::new();let counter=Arc::clone(&concrete.counter);let host=concrete.clone()as Arc<dyn SettingExpressionQueries>;
  let source=Source::new("/datum/value\n    var/const/first=2+3\n    var/const/alias=first*2\n    var/datum/value/typed_null\n    var/list/sized[1+2][][4]\n    var/made=new /datum/value()\n    var/relative=.nested\n/datum/value/nested\n");
  let front=super::super::build_for_original_native_parameter_demand_with_callable_anchors_checked(Path::new("actual-utility-values.dme"),&source,&BTreeMap::new(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host,None).unwrap();let view=front.source_view().unwrap();let owner=view.tree().lookup_type(dm_ir::SymbolId::of("/datum/value")).unwrap();
  host.with_declaration_admission(&mut|a|{let mut file=|_: &std::path::Path|Ok(7);let values=super::super::OriginalUtilityValues::capture(front.original_utility_declaration_context()?,Arc::clone(view.archive()),a,&mut file).map_err(BodySyntaxFailure::Operational)?;values.evaluate_all().map_err(BodySyntaxFailure::Operational)?;let mut errors=0;values.visit_errors(&mut|_|{errors+=1;Ok(())}).map_err(BodySyntaxFailure::Operational)?;assert_eq!(errors,0);
   for(name,expected)in[("first","Float(5.0)"),("alias","Float(10.0)"),("typed_null","Null(Some([\"datum\", \"value\"]))"),("relative","Prefab(Pop { path: [\"datum\", \"value\", \"nested\"], vars: {} })")]{let mut seen=false;assert!(values.with_value(owner,name,&mut|_,value|{let value=value.expect("actual folded own value");let text=value.debug_using(a)?;assert_eq!(text.as_str(),expected,"{name}");seen=true;Ok(())}).map_err(BodySyntaxFailure::Operational)?);assert!(seen);}
   for name in["made","sized"]{values.with_value(owner,name,&mut|_,value|{let text=value.unwrap().debug_using(a)?;assert!(text.as_str().starts_with("New { type_: Some(Pop { path: ["));if name=="made"{assert!(text.as_str().ends_with("args: Some([]) }"));}else{assert!(text.as_str().contains("[\"list\"]"));assert!(text.as_str().contains("(Float(3.0), None), (Float(4.0), None)"));}Ok(())}).map_err(BodySyntaxFailure::Operational)?;}Ok(())}).unwrap();
  drop(view);drop(front);drop(source);host.with_declaration_admission(&mut|_|Ok(())).unwrap();drop(host);drop(concrete);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_original_utility_constant_errors_keep_caller_saved_assignment_and_skip_static(){
  let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let concrete=super::original_resource_host::Host::new();let counter=Arc::clone(&concrete.counter);let host=concrete.clone()as Arc<dyn SettingExpressionQueries>;let source=Source::new("/datum/value\n    var/first=missing\n    var/second=first\n    var/static/ignored=missing_static\n");let front=super::super::build_for_original_native_parameter_demand_with_callable_anchors_checked(Path::new("actual-utility-errors.dme"),&source,&BTreeMap::new(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host,None).unwrap();let view=front.source_view().unwrap();
  host.with_declaration_admission(&mut|a|{let mut file=|_: &std::path::Path|Ok(7);let values=super::super::OriginalUtilityValues::capture(front.original_utility_declaration_context()?,Arc::clone(view.archive()),a,&mut file).map_err(BodySyntaxFailure::Operational)?;values.evaluate_all().map_err(BodySyntaxFailure::Operational)?;let mut errors=super::super::OriginalUtilityErrors::new();values.append_constant_errors(&mut errors).map_err(BodySyntaxFailure::Operational)?;let mut bytes=Vec::new();errors.write_prelude(Default::default(),&mut bytes,a).map_err(BodySyntaxFailure::Operational)?;let text=String::from_utf8(bytes).unwrap();assert!(text.contains("2 parse errors"));assert!(text.contains("  2:14: error: unknown variable: missing"),"{text}");assert!(text.contains("  3:15: error: recursive constant reference: first"),"{text}");assert!(!text.contains("missing_static"));Ok(())}).unwrap();drop(view);drop(front);drop(source);host.with_declaration_admission(&mut|_|Ok(())).unwrap();drop(host);drop(concrete);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod ordinary_code_demand_mode_controls{
 use super::*;
 #[test]fn actual_ordinary_code_demand_predecessor_distinguishes_eager_demand_and_compact_history(){
  let host=crate::frontend::declaration_checked_tests::original_test_host();let source=super::actual_stream_controls::Source::new("#define ACTUAL_CODE_MODE 7\n/proc/p(value=1)\n    return value\n");let path=std::path::Path::new("ordinary-code-mode.dme");let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();
  for demand in[false,true]{
   let builder=if demand{super::super::build_for_original_native_body_demand_with_callable_anchors_checked}else{super::super::build_for_original_native_parameter_demand_with_callable_anchors_checked};let front=Arc::new(builder(path,&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host,None).unwrap());
   assert_eq!(front.original_analysis_completeness(),Some(super::super::OriginalAnalysisCompleteness::Complete));assert!(front.source_view().unwrap().original_plan().final_macro("ACTUAL_CODE_MODE").unwrap().is_some());let mut state=RetainedSemanticTree::new();state.remember_analysis_frontend(path,&Default::default(),front).unwrap();
   assert!(state.previous_original_frontend_with_code_mode(path,&Default::default(),true,true,false,demand).is_some());assert!(state.previous_original_frontend_with_code_mode(path,&Default::default(),true,true,false,!demand).is_none(),"actual new storage mode is part of predecessor admission in BOTH directions");assert!(state.previous_original_frontend_with_code_mode(path,&Default::default(),true,true,true,demand).is_none(),"full actual history cannot be relabeled compact history");
  }
 }
}
