//! Actual raw traversal -> SAME primary -> restricted diagnostic/generation
//! handoff. No ordinary planner, expanded-string reparse or compiler promotion.
use super::{OriginalDemandDelivery,OriginalPrimaryStreamConsumer,OriginalBatchExecution,DirectivePlan,ExpandedRegions,GenerationDirectivePlan,GenerationOmissions,OriginalDiagnosticPlan,original_literal_source::OriginalLiteralSourceBinding,original_primary_controller::{OriginalLogicalProducer,OriginalPreparedTokenSource,OriginalPrimaryOutput,consume_prepared_primary_using},original_batch_primary::{OriginalBatchRunner,consume_batch_primary_using},original_source_controller::{State,NoticeSink,Host,Control},original_driver::RawSourceDriver,environment::OriginalFinalMacros,original_diagnostic_plan::OriginalPlanRetention};
use crate::{SourceProvider,InitialEnvironment,SourceText,source_arena_credit::{SourceArenaWork,read_original_source_open_using},macro_expansion::{OriginalMacroText as Text,original_format_using}};
use dm_syntax::{SettingAdmission,OriginalDeclarationSkeleton,SharedSpanTokens};
use std::{collections::BTreeMap,path::Path,io,rc::Rc,sync::Arc};
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
pub struct OriginalGenerationProduct{delivery:OriginalDemandDelivery,plan:DirectivePlan,omissions:GenerationOmissions,expanded:ExpandedRegions,primary:OriginalDeclarationSkeleton,literals:OriginalLiteralSourceBinding,retention:OriginalPlanRetention}
impl OriginalGenerationProduct{
 pub fn delivery(&self)->OriginalDemandDelivery{self.delivery}
 pub fn expanded(&self)->&ExpandedRegions{&self.expanded}
 pub fn primary(&self)->&OriginalDeclarationSkeleton{&self.primary}
 pub fn literal_source(&self)->&OriginalLiteralSourceBinding{&self.literals}
 pub(super) fn into_primary_parts(self)->(DirectivePlan,GenerationOmissions,ExpandedRegions,OriginalDeclarationSkeleton,OriginalLiteralSourceBinding,OriginalPlanRetention){(self.plan,self.omissions,self.expanded,self.primary,self.literals,self.retention)}
 pub fn into_diagnostic_parts_using(self,a:&SettingAdmission<'_>)->io::Result<(OriginalDiagnosticPlan,ExpandedRegions,OriginalDeclarationSkeleton,OriginalLiteralSourceBinding)>{let(plan,omissions,expanded,primary,literals,retention)=self.into_primary_parts();let restricted=OriginalDiagnosticPlan::from_actual_using(plan,&omissions,retention,a)?;Ok((restricted,expanded,primary,literals))}
 pub fn into_generation_parts(self)->io::Result<(GenerationDirectivePlan,ExpandedRegions,OriginalDeclarationSkeleton,OriginalLiteralSourceBinding)>{GenerationDirectivePlan::from_original_product(self)}
}
/// Borrowed attempt-event observer, not a source/absence witness constructor.
/// Only the actual top root branch invokes these callbacks; concrete recorders
/// must independently authenticate their own exact failed-open fact/index.
/// Only the real root SourceOpenFailed branch can construct this borrowed
/// event. It carries no acquisition/EOF/model permission and cannot be cloned
/// or re-created from an arbitrary ioError by a consumer callback.
pub struct OriginalRootOpenFailureLoan<'loan,'budget>{provider:&'loan dyn SourceProvider,path:&'loan Path,error:&'loan io::Error,work:&'loan dyn SourceArenaWork,a:&'loan SettingAdmission<'budget>}
impl<'loan,'budget>OriginalRootOpenFailureLoan<'loan,'budget>{pub fn provider(&self)->&dyn SourceProvider{self.provider}pub fn path(&self)->&Path{self.path}pub fn error(&self)->&io::Error{self.error}pub fn source_work(&self)->&dyn SourceArenaWork{self.work}pub fn admission(&self)->&SettingAdmission<'budget>{self.a}}
pub trait OriginalRootOpenObserver:Sync{
 fn before_root_read_using(&self,provider:&dyn SourceProvider,path:&Path,work:&dyn SourceArenaWork,a:&SettingAdmission<'_>)->io::Result<()>;
 /// Observation is best-effort/no authority: inability to issue a witness
 /// cannot replace the exact original SourceOpenFailed ioError.
 fn actual_root_open_failed_using(&self,failed:OriginalRootOpenFailureLoan<'_,'_>);
}
struct Metadata{state:State,final_macros:OriginalFinalMacros}
struct Recipe<'a>{project:&'a Path,provider:&'a dyn SourceProvider,defines:&'a BTreeMap<String,String>,omissions:&'a GenerationOmissions,max_raw_bytes:usize,work:&'a dyn SourceArenaWork,root_observer:Option<&'a dyn OriginalRootOpenObserver>}
impl Recipe<'_>{
 fn with_source(&self,a:&SettingAdmission<'_>,run:&mut dyn FnMut(&mut dyn OriginalPreparedTokenSource)->io::Result<()>)->io::Result<Metadata>{
  poll(a)?;if self.provider.initial_environment()!=InitialEnvironment::OriginalChecker0290{return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual Original source environment required"))}
  let shared=State::new(self.project,self.provider,self.defines,a,self.work)?;
  let mut driver=RawSourceDriver::new_for_project(self.provider.initial_environment(),self.defines,self.project,a,&mut|input,a|{
   let fixed=input.provenance()==crate::initial_environment::OriginalInitialProvenance::FixedDefault;
   super::original_token_factory::initial_definition_using(input,a,&mut|notice|{let mut text=Text::new(a)?;original_format_using(&mut text,a,|out|notice.write_message(out))?;shared.borrow_mut().notices.message_using(if fixed{super::original_current_location::OriginalCurrentLocation::Builtins}else{super::original_current_location::OriginalCurrentLocation::Default},Some(notice.span),match notice.severity{super::original_raw_frame::OriginalRawNoticeSeverity::Error=>super::OriginalNoticeSeverity::Error,super::original_raw_frame::OriginalRawNoticeSeverity::Warning=>super::OriginalNoticeSeverity::Warning},notice.error_type,text,a)?;Ok(())},&mut|_,notice|{let mut text=Text::new(a)?;original_format_using(&mut text,a,|out|notice.write_message(out))?;shared.borrow_mut().notices.message_using(if fixed{super::original_current_location::OriginalCurrentLocation::Builtins}else{super::original_current_location::OriginalCurrentLocation::Default},None,if notice.is_warning(){super::OriginalNoticeSeverity::Warning}else{super::OriginalNoticeSeverity::Error},notice.error_type(),text,a)?;Ok(())})
  })?;
  // Physical root is opened through SAME provider. A private captured partial
  // root is intercepted by its genuine subject provider, never by path guesses.
  if let Some(observer)=self.root_observer{observer.before_root_read_using(self.provider,self.project,self.work,a)?;}
  let root=read_original_source_open_using(self.provider,self.project,self.max_raw_bytes,self.work,&mut||Ok(crate::OriginalRawOpenDecision::Read))?;
  let root=match root{crate::OriginalRawReadOutcome::Acquired(lease)=>lease,crate::OriginalRawReadOutcome::SourceOpenFailed(error)=>{if let Some(observer)=self.root_observer{observer.actual_root_open_failed_using(OriginalRootOpenFailureLoan{provider:self.provider,path:self.project,error:&error,work:self.work,a});}return Err(error)},crate::OriginalRawReadOutcome::Absent|crate::OriginalRawReadOutcome::Suppressed=>return Err(io::Error::new(io::ErrorKind::InvalidData,"actual root reader did not issue its source acquisition"))};
  let occurrence=shared.borrow_mut().plan.register_opened_using(self.project,self.project,root.clone(),None,dm_syntax::Span::default(),0,a)?;shared.borrow_mut().register_actual_root_semantic_file_using(a)?;driver.push_opened_at(self.provider,root,occurrence,self.project,a)?;
  let mut notices=NoticeSink(Rc::clone(&shared));let mut host=Host(Rc::clone(&shared),self.work);let mut control=Control{shared:Rc::clone(&shared),project:self.project,work:self.work,max_raw_bytes:self.max_raw_bytes,omissions:self.omissions};
  let result = {
   let mut source=OriginalLogicalProducer::new(&mut driver,self.provider,&mut notices,&mut host,&mut control,a)?;
   shared.borrow_mut().bind(&source.initial_delivery(),a)?;
   run(&mut source)
  };
  result.inspect_err(|_error| {
   #[cfg(debug_assertions)]
   if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
    let state = shared.borrow();
    let (rows, row_capacity_bytes, groups, group_capacity_bytes, encounters, wide_capacity_bytes) = state.origins.trace_capacity();
    let source_origin_page_bytes=state.origins.source_page_bytes();
    let (opened_occurrences, regions, plan_reserved_bytes) = state.plan.trace_reservations();
    let (macro_names, macro_metadata_reserved_bytes, macro_map_reserved_bytes) = driver.trace_macro_reservations();
    let counter_after_source_loan = a.retained_bytes_for_trace();
    eprintln!("ORIGINAL_FATAL_STAGE=producer_run {_error:?}");
    state.plan.log_failure_reservations();
    // No source/lexer calls, additional credit, or first-error mutation.
    // Shared product columns are reference-weighted upper bounds only.
    let live=driver.environment().environment().trace_original_products();
    let(history_rows,history_row_capacity,history_name_capacity,removed)=state.history.trace_original_products();
    use std::io::Write;
    let _=writeln!(io::stderr().lock(),"ORIGINAL_MACRO_PRODUCT_CENSUS stage=producer_after_source_loan live={live:?} removed={removed:?} history_rows={history_rows} history_row_capacity={history_row_capacity} history_name_capacity={history_name_capacity}");
    eprintln!("ORIGINAL_RETAINED_STAGE=producer counter_after_source_loan={counter_after_source_loan} rows={rows} source_origin_page_bytes={source_origin_page_bytes} row_capacity_bytes={row_capacity_bytes} groups={groups} group_capacity_bytes={group_capacity_bytes} encounters={encounters} wide_capacity_bytes={wide_capacity_bytes} opened_occurrences={opened_occurrences} regions={regions} plan_reserved_bytes={plan_reserved_bytes} macro_names={macro_names} macro_metadata_reserved_bytes={macro_metadata_reserved_bytes} macro_map_reserved_bytes={macro_map_reserved_bytes}");
   }
  })?;
  drop((control,host,notices));
  {let mut state=shared.borrow_mut();driver.capture_final_define_history_using(&mut state.history,a).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=producer_history {error:?}");}})?;}
  let final_macros=driver.into_final_environment_using(a).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=producer_final_macros {error:?}");}})?;
  let state=Rc::try_unwrap(shared).map_err(|_|io::Error::new(io::ErrorKind::InvalidData,"actual producer retained a live traversal loan at metadata finalization"))?.into_inner();
  Ok(Metadata{state,final_macros})
 }
}
/// A Sync descriptor borrows only the authentic execution.provider loan. Every
/// mutable driver/notice/host/control is constructed locally inside its admission.
struct BatchRecipe<'a>{project:&'a Path,provider:&'a(dyn SourceProvider+Sync),defines:&'a BTreeMap<String,String>,omissions:&'a GenerationOmissions,max_raw_bytes:usize,work:&'a dyn SourceArenaWork,root_observer:Option<&'a dyn OriginalRootOpenObserver>}
impl OriginalBatchRunner for BatchRecipe<'_>{type Metadata=Metadata;fn with_source(&self,a:&SettingAdmission<'_>,run:&mut dyn FnMut(&mut dyn OriginalPreparedTokenSource)->io::Result<()>)->io::Result<Metadata>{Recipe{project:self.project,provider:self.provider,defines:self.defines,omissions:self.omissions,max_raw_bytes:self.max_raw_bytes,work:self.work,root_observer:self.root_observer}.with_source(a,run)}}
fn finalize(delivery:OriginalDemandDelivery,mut metadata:Metadata,output:OriginalPrimaryOutput,omissions:GenerationOmissions,a:&SettingAdmission<'_>,work:&dyn SourceArenaWork)->io::Result<OriginalGenerationProduct>{
 poll(a)?;metadata.state.origins.retain_delivered_using(&output.delivery,a,work).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=retain_delivered {error:?}");}})?;
 let(source,primary,tokens,literals,_actual_consumed_eof)=output.into_bound_parts_using(a).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=into_bound {error:?}");}})?;
 // Every empty Arc control below is funded before allocation. No placeholder
 // full-source token/tree/EOF role is manufactured from metadata completion.
 metadata.state.plan.charge_using(6*std::mem::size_of::<usize>(),a)?;
 let(plan,paths,credit)=metadata.state.plan.finish_using(a)?;
 let origins=super::ExpandedOriginArena::from_actual_raw_rows_using(metadata.state.origins,credit.clone(),a)?;
 let expanded=ExpandedRegions{input_keys:Arc::new(Vec::new()),text:source,tokens:tokens.into(),origins,dense_emission_regions:Vec::new(),diagnostics:Vec::new(),receipts:Vec::new(),lexical_diagnostics:Vec::new()};
 let retention=OriginalPlanRetention{paths,notices:metadata.state.notices,history:metadata.state.history,conditionals:metadata.state.conditionals,scripts:metadata.state.scripts,metadata:credit,final_macros:metadata.final_macros};
 Ok(OriginalGenerationProduct{delivery,plan,omissions,expanded,primary,literals,retention})
}
impl GenerationDirectivePlan{
 pub fn prepare_original_stream_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,consumer:&mut dyn OriginalPrimaryStreamConsumer)->io::Result<OriginalGenerationProduct>{
  Self::prepare_original_stream_root_observer_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,batch,consumer,None)
 }
 pub fn prepare_original_stream_observing_root_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,consumer:&mut dyn OriginalPrimaryStreamConsumer,observer:&dyn OriginalRootOpenObserver)->io::Result<OriginalGenerationProduct>{
  Self::prepare_original_stream_root_observer_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,batch,consumer,Some(observer))
 }
 fn prepare_original_stream_root_observer_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,consumer:&mut dyn OriginalPrimaryStreamConsumer,root_observer:Option<&dyn OriginalRootOpenObserver>)->io::Result<OriginalGenerationProduct>{
  poll(a)?;let execution=batch.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"Original Analyze requires its actual bounded batch execution loan"))?;
  let actual:&dyn SourceProvider=execution.provider();if !std::ptr::addr_eq(provider,actual){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual Original batch execution belongs to another provider"))}
  let root_observer=root_observer.or_else(||provider.original_root_open_observer());
  let recipe=BatchRecipe{project,provider:execution.provider(),defines,omissions:&omissions,max_raw_bytes,work:source_work,root_observer};let(output,metadata)=consume_batch_primary_using(execution,source_work,a,consumer,&recipe).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=batch_primary {error:?}");}})?;finalize(OriginalDemandDelivery::AnalyzeBatch8192x64,metadata,output,omissions,a,source_work)
 }
 /// Direct checker profile is explicitly named; it cannot masquerade as Analyze
 /// by wrapping a lazy stream or manufacturing a successful batch/EOF receipt.
 pub fn prepare_original_checker_stream_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer)->io::Result<OriginalGenerationProduct>{
  Self::prepare_original_checker_stream_root_observer_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,consumer,None)
 }
 pub fn prepare_original_checker_stream_observing_root_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer,observer:&dyn OriginalRootOpenObserver)->io::Result<OriginalGenerationProduct>{
  Self::prepare_original_checker_stream_root_observer_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,consumer,Some(observer))
 }
 fn prepare_original_checker_stream_root_observer_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer,root_observer:Option<&dyn OriginalRootOpenObserver>)->io::Result<OriginalGenerationProduct>{
  let root_observer=root_observer.or_else(||provider.original_root_open_observer());
  let recipe=Recipe{project,provider,defines,omissions:&omissions,max_raw_bytes,work:source_work,root_observer};let mut output=None;let metadata=recipe.with_source(a,&mut|source|{if output.is_some(){return Err(io::ErrorKind::InvalidData.into())}output=Some(consume_prepared_primary_using(source,source_work,a,consumer)?);Ok(())})?;finalize(OriginalDemandDelivery::CheckerLazy0290,metadata,output.ok_or(io::ErrorKind::InvalidData)?,omissions,a,source_work)
 }
}

#[cfg(test)]#[path="original_generation_tests.rs"]mod tests;
