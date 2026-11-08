//! Actual raw traversal -> SAME primary -> restricted diagnostic/generation
//! handoff. No ordinary planner, expanded-string reparse or compiler promotion.
use super::{OriginalDemandDelivery,OriginalPrimaryStreamConsumer,OriginalBatchExecution,DirectivePlan,ExpandedRegions,GenerationDirectivePlan,GenerationOmissions,OriginalDiagnosticPlan,original_literal_source::OriginalLiteralSourceBinding,original_primary_controller::{OriginalLogicalProducer,OriginalPreparedTokenSource,OriginalPrimaryOutput,consume_prepared_primary_using},original_batch_primary::{OriginalBatchRunner,consume_batch_primary_using},original_source_controller::{State,NoticeSink,Host,Control},original_driver::RawSourceDriver,original_diagnostic_plan::{DiagnosticFinalMacros,OriginalPlanRetention}};
use crate::{SourceProvider,InitialEnvironment,SourceText,source_arena_credit::{SourceArenaWork,read_original_source_open_using},macro_expansion::{OriginalMacroText as Text,original_format_using}};
use dm_syntax::{SettingAdmission,SharedSpanTokens};
use super::{OriginalStreamPrimary,original_define_history::HistoryPurpose};
use std::{collections::BTreeMap,path::Path,io,rc::Rc,sync::Arc};
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
pub struct OriginalGenerationProduct{delivery:OriginalDemandDelivery,consumed_eof:bool,plan:DirectivePlan,omissions:GenerationOmissions,expanded:ExpandedRegions,primary:OriginalStreamPrimary,literals:OriginalLiteralSourceBinding,retention:OriginalPlanRetention,
 #[cfg(test)]
 token_projection:Result<ProjectionCheck, ProjectionMismatch>,
}
/// Exact complete source and token pair issued by the actual batch receiver.
/// No raw constructor; a cheap pair of temporary aliases protects identity.
pub struct OriginalHeaderTokenGeometry {
 source: SourceText,
 tokens: SharedSpanTokens,
}
impl OriginalHeaderTokenGeometry {
 pub fn matches(&self,source:&SourceText,tokens:&SharedSpanTokens,a:&SettingAdmission<'_>)->bool{
  self.source.matches_retained_subview(0..self.source.len(),source)&&self.tokens.same_owner(tokens)&&tokens.admitted_by(a)
 }
}
impl OriginalGenerationProduct{
 pub fn delivery(&self)->OriginalDemandDelivery{self.delivery}
 pub fn expanded(&self)->&ExpandedRegions{&self.expanded}
 pub fn primary(&self)->&OriginalStreamPrimary{&self.primary}
 /// Only complete committed batch delivery can skip the generic token walk.
 /// Each adopted token was appended as UTF-8 at exactly its span, and the
 /// receiver checked its order and the actual immutable loan before adoption.
 pub fn header_token_geometry(&self)->Option<OriginalHeaderTokenGeometry>{
  if !self.consumed_eof || self.delivery!=OriginalDemandDelivery::AnalyzeBatch8192x64{return None}
  let OriginalStreamPrimary::Committed(primary)=&self.primary else{return None};
  let tokens=self.expanded.tokens.shared()?;
  if primary.observer_stop().is_some() || !tokens.same_owner(primary.tokens()){return None}
  Some(OriginalHeaderTokenGeometry{source:self.expanded.text.clone(),tokens:tokens.clone()})
 }
 pub(super) fn has_full_define_history(&self)->bool{self.retention.history.is_full()}
 pub fn literal_source(&self)->&OriginalLiteralSourceBinding{&self.literals}
 pub(super) fn into_primary_parts(self)->(DirectivePlan,GenerationOmissions,ExpandedRegions,OriginalStreamPrimary,OriginalLiteralSourceBinding,OriginalPlanRetention){(self.plan,self.omissions,self.expanded,self.primary,self.literals,self.retention)}
 pub fn into_diagnostic_parts_using(self,a:&SettingAdmission<'_>)->io::Result<(OriginalDiagnosticPlan,ExpandedRegions,OriginalStreamPrimary,OriginalLiteralSourceBinding)>{let(plan,omissions,expanded,primary,literals,retention)=self.into_primary_parts();let restricted=OriginalDiagnosticPlan::from_actual_using(plan,&omissions,retention,a)?;Ok((restricted,expanded,primary,literals))}
 pub fn into_generation_parts(self)->io::Result<(GenerationDirectivePlan,ExpandedRegions,OriginalStreamPrimary,OriginalLiteralSourceBinding)>{GenerationDirectivePlan::from_original_product(self)}
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
struct Metadata{state:State,final_macros:DiagnosticFinalMacros}
struct Recipe<'a>{project:&'a Path,provider:&'a dyn SourceProvider,defines:&'a BTreeMap<String,String>,omissions:&'a GenerationOmissions,max_raw_bytes:usize,work:&'a dyn SourceArenaWork,root_observer:Option<&'a dyn OriginalRootOpenObserver>,loan_batch_geometry:bool,history:HistoryPurpose,compact_final_macros:bool}
impl Recipe<'_>{
 fn with_source(&self,a:&SettingAdmission<'_>,run:&mut dyn FnMut(&mut dyn OriginalPreparedTokenSource)->io::Result<()>)->io::Result<Metadata>{
  poll(a)?;if self.provider.initial_environment()!=InitialEnvironment::OriginalChecker0290{return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual Original source environment required"))}
  let shared=State::new(self.project,self.provider,self.defines,a,self.work,self.history)?;
  let mut driver=RawSourceDriver::new_for_project(self.provider.initial_environment(),self.defines,self.project,self.history,a,&mut|input,a|{
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
   if self.loan_batch_geometry{source.enable_batch_geometry();}
   if self.history==HistoryPurpose::Diagnostic{source.enable_body_spelling_projection();}
   shared.borrow_mut().bind(&source.initial_delivery(),a)?;
   run(&mut source)
  };
  #[cfg(debug_assertions)]
  if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
   eprintln!("ORIGINAL_PHYSICAL_LINE_STARTS failed={} {:?}", result.is_err(), driver.trace_line_starts());
   if let Some((attempts, hits)) = driver.trace_definition_geometry() {
    eprintln!("ORIGINAL_DEFINITION_GEOMETRY attempts={attempts} exact_hits={hits}");
   }
  }
  #[cfg(debug_assertions)]
  if std::env::var_os("DMB_ORIGINAL_TRACE_FUNDING_OWNERS").is_some() {
   let state = shared.borrow();
   let (occurrences, regions, retained) = state.plan.trace_reservations();
   eprintln!("ORIGINAL_LIVE_DIRECTIVE_OWNER occurrences={occurrences} regions={regions} retained={retained}");
  }
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
    if let Some(origin) = driver.trace_last_outer_origin() {
     let path = state.plan.occurrence(origin.occurrence).ok().map(|row| row.path.as_path());
     eprintln!("ORIGINAL_SOURCE_FRONTIER last_outer_path={path:?} occurrence={} line={} physical={:?}",
      origin.occurrence, origin.line, origin.physical);
    }
    state.plan.log_failure_reservations();
    // No source/lexer calls, additional credit, or first-error mutation.
    // Shared product columns are reference-weighted upper bounds only.
    let live=driver.environment().read().trace_original_products();
    let(history_rows,history_row_capacity,history_name_capacity,removed)=state.history.trace_original_products();
    use std::io::Write;
    let _=writeln!(io::stderr().lock(),"ORIGINAL_MACRO_PRODUCT_CENSUS stage=producer_after_source_loan live={live:?} removed={removed:?} history_rows={history_rows} history_row_capacity={history_row_capacity} history_name_capacity={history_name_capacity}");
    let (trace_runs,trace_rank_bytes,trace_run_bytes)=state.origins.trace_run_capacity();
    let (bases, delta_bytes, anchor_bytes, wide, wide_bytes) = state.origins.trace_output_base_capacity();
    eprintln!("ORIGINAL_OUTPUT_BASE_CAPACITY bases={bases} delta_bytes={delta_bytes} anchor_bytes={anchor_bytes} wide={wide} wide_bytes={wide_bytes}");
    if std::env::var_os("DMB_ORIGINAL_TRACE_OUTPUT_BASE_WIDTHS").is_some(){
     eprintln!("ORIGINAL_OUTPUT_BASE_PACKING {:?}",state.origins.trace_output_base_packing());
    }
    let (omitted, owner_bytes, mapping_bytes) = state.origins.trace_run_compaction_capacity();
    eprintln!("ORIGINAL_TRACE_RUN_COMPACTION omitted={omitted} owner_bytes={owner_bytes} mapping_bytes={mapping_bytes}");
    if let Some(census)=state.origins.trace_row_geometry_census(){
     eprintln!("ORIGINAL_ORIGIN_ROW_GEOMETRY stage=producer {census:?}");
    }
    eprintln!("ORIGINAL_RETAINED_STAGE=producer counter_after_source_loan={counter_after_source_loan} rows={rows} source_origin_page_bytes={source_origin_page_bytes} row_capacity_bytes={row_capacity_bytes} groups={groups} group_trace_runs={trace_runs} group_trace_rank_bytes={trace_rank_bytes} group_trace_run_bytes={trace_run_bytes} group_capacity_bytes={group_capacity_bytes} encounters={encounters} wide_capacity_bytes={wide_capacity_bytes} opened_occurrences={opened_occurrences} regions={regions} plan_reserved_bytes={plan_reserved_bytes} macro_names={macro_names} macro_metadata_reserved_bytes={macro_metadata_reserved_bytes} macro_map_reserved_bytes={macro_map_reserved_bytes}");
   }
  })?;
  drop((control,host,notices));
  {let mut state=shared.borrow_mut();driver.capture_final_define_history_using(&mut state.history,a).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=producer_history {error:?}");}})?;}
  let final_macros=(if self.compact_final_macros{
   driver.into_final_debug_presence_using(a)
  }else{
   driver.into_final_environment_using(a).map(DiagnosticFinalMacros::Full)
  }).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=producer_final_macros {error:?}");}})?;
  let state=Rc::try_unwrap(shared).map_err(|_|io::Error::new(io::ErrorKind::InvalidData,"actual producer retained a live traversal loan at metadata finalization"))?.into_inner();
  Ok(Metadata{state,final_macros})
 }
}
/// A Sync descriptor borrows only the authentic execution.provider loan. Every
/// mutable driver/notice/host/control is constructed locally inside its admission.
struct BatchRecipe<'a>{project:&'a Path,provider:&'a(dyn SourceProvider+Sync),defines:&'a BTreeMap<String,String>,omissions:&'a GenerationOmissions,max_raw_bytes:usize,work:&'a dyn SourceArenaWork,root_observer:Option<&'a dyn OriginalRootOpenObserver>,loan_batch_geometry:bool,history:HistoryPurpose,compact_final_macros:bool}
impl OriginalBatchRunner for BatchRecipe<'_>{type Metadata=Metadata;fn with_source(&self,a:&SettingAdmission<'_>,run:&mut dyn FnMut(&mut dyn OriginalPreparedTokenSource)->io::Result<()>)->io::Result<Metadata>{Recipe{project:self.project,provider:self.provider,defines:self.defines,omissions:self.omissions,max_raw_bytes:self.max_raw_bytes,work:self.work,root_observer:self.root_observer,loan_batch_geometry:self.loan_batch_geometry,history:self.history,compact_final_macros:self.compact_final_macros}.with_source(a,run)}}
#[cfg(any(test, debug_assertions))]
#[derive(Debug)]
struct ProjectionMismatch {
 reason: &'static str,
 ordinal: usize,
 origin: Option<dm_syntax::SpanToken>,
 primary: Option<dm_syntax::SpanToken>,
}

#[cfg(any(test, debug_assertions))]
#[derive(Debug)]
struct ProjectionCheck {
 rows: usize,
 eof: bool,
}

#[cfg(any(test, debug_assertions))]
fn check_delivered_projection(
 origins: &super::origin_raw_rows::OriginalRawOrigins,
 receipt: &super::original_prepared_output::OriginalDeliveryFrontier,
 tokens: &SharedSpanTokens, eof: bool, a:&SettingAdmission<'_>,
)->Result<ProjectionCheck,ProjectionMismatch>{
 let projected=origins.delivered_tokens(receipt,a).map_err(|reason|ProjectionMismatch {
  reason, ordinal:0, origin:None, primary:None,
 })?;
 let primary=tokens.window().iter();
 let count=primary.len();
 if projected.len()!=count{return Err(ProjectionMismatch {
  reason:"retained output and primary lengths differ", ordinal:projected.len().min(count),
  origin:None, primary:None,
 })}
 for (ordinal,(origin,token)) in projected.zip(primary).enumerate(){
  if origin!=Some(token){return Err(ProjectionMismatch {
   reason:"retained output and primary token differ", ordinal, origin, primary:Some(token),
  })}
 }
 Ok(ProjectionCheck{rows:count,eof})
}

fn finalize(delivery:OriginalDemandDelivery,mut metadata:Metadata,output:OriginalPrimaryOutput,omissions:GenerationOmissions,a:&SettingAdmission<'_>,work:&dyn SourceArenaWork)->io::Result<OriginalGenerationProduct>{
 poll(a)?;metadata.state.origins.retain_delivered_using(&output.delivery,a,work).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=retain_delivered {error:?}");}})?;
 #[cfg(any(test, debug_assertions))]
 let delivered=output.delivery.clone();
 let(source,primary,tokens,literals,_actual_consumed_eof)=output.into_bound_parts_using(a).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=into_bound {error:?}");}})?;
 #[cfg(test)]
 let token_projection=check_delivered_projection(&metadata.state.origins,&delivered,&tokens,_actual_consumed_eof,a);
 #[cfg(debug_assertions)]
 if std::env::var_os("DMB_ORIGINAL_TRACE_SHARED_GEOMETRY").is_some(){
  let outcome=check_delivered_projection(&metadata.state.origins,&delivered,&tokens,_actual_consumed_eof,a);
  match outcome {
   Ok(ProjectionCheck{rows,eof})=>eprintln!("ORIGINAL_SHARED_GEOMETRY rows={rows} eof={eof}"),
   Err(ProjectionMismatch{reason,ordinal,origin,primary})=>eprintln!(
    "ORIGINAL_SHARED_GEOMETRY mismatch={reason} ordinal={ordinal} origin={origin:?} primary={primary:?}"),
  }
 }
 // Every empty Arc control below is funded before allocation. No placeholder
 // full-source token/tree/EOF role is manufactured from metadata completion.
 metadata.state.plan.charge_using(6*std::mem::size_of::<usize>(),a)?;
 let(plan,paths,credit)=metadata.state.plan.finish_using(a)?;
 let origins=super::ExpandedOriginArena::from_actual_raw_rows_using(metadata.state.origins,credit.clone(),a)?;
 let expanded=ExpandedRegions{input_keys:Arc::new(Vec::new()),text:source,tokens:tokens.into(),origins,dense_emission_regions:Vec::new(),diagnostics:Vec::new(),receipts:Vec::new(),lexical_diagnostics:Vec::new()};
 let retention=OriginalPlanRetention{paths,notices:metadata.state.notices,history:metadata.state.history,conditionals:metadata.state.conditionals,scripts:metadata.state.scripts,metadata:credit,final_macros:metadata.final_macros};
 Ok(OriginalGenerationProduct{delivery,consumed_eof:_actual_consumed_eof,plan,omissions,expanded,primary,literals,retention,
  #[cfg(test)]
  token_projection,
 })
}
impl GenerationDirectivePlan{
 pub fn prepare_original_stream_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,consumer:&mut dyn OriginalPrimaryStreamConsumer)->io::Result<OriginalGenerationProduct>{
  Self::prepare_original_stream_root_observer_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,batch,consumer,None,HistoryPurpose::Full,false)
 }
 pub fn prepare_original_stream_observing_root_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,consumer:&mut dyn OriginalPrimaryStreamConsumer,observer:&dyn OriginalRootOpenObserver)->io::Result<OriginalGenerationProduct>{
  Self::prepare_original_stream_root_observer_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,batch,consumer,Some(observer),HistoryPurpose::Full,false)
 }
 fn prepare_original_stream_root_observer_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,consumer:&mut dyn OriginalPrimaryStreamConsumer,root_observer:Option<&dyn OriginalRootOpenObserver>,history:HistoryPurpose,compact_final_macros:bool)->io::Result<OriginalGenerationProduct>{
  poll(a)?;let execution=batch.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"Original Analyze requires its actual bounded batch execution loan"))?;
  let actual:&dyn SourceProvider=execution.provider();if !std::ptr::addr_eq(provider,actual){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual Original batch execution belongs to another provider"))}
  let root_observer=root_observer.or_else(||provider.original_root_open_observer());
  let recipe=BatchRecipe{project,provider:execution.provider(),defines,omissions:&omissions,max_raw_bytes,work:source_work,root_observer,loan_batch_geometry:consumer.retains_committed_items(),history,compact_final_macros};let(output,metadata)=consume_batch_primary_using(execution,source_work,a,consumer,&recipe).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=batch_primary {error:?}");}})?;finalize(OriginalDemandDelivery::AnalyzeBatch8192x64,metadata,output,omissions,a,source_work)
 }
 /// Restricted diagnostic traversal borrows the same actual lazy/batch
 /// producers but keeps no full historical macro replacement/doc products.
 /// The resulting product cannot be promoted to the generation role.
 pub fn prepare_original_diagnostic_stream_using(
    project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,
    omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,
    a:&SettingAdmission<'_>,batch:Option<&OriginalBatchExecution<'_>>,
    consumer:&mut dyn OriginalPrimaryStreamConsumer,
 )->io::Result<OriginalGenerationProduct>{
    match batch {
        Some(batch)=>Self::prepare_original_stream_root_observer_using(
            project,provider,defines,omissions,max_raw_bytes,source_work,a,Some(batch),consumer,None,HistoryPurpose::Diagnostic,false),
        None=>Self::prepare_original_checker_stream_root_observer_using(
            project,provider,defines,omissions,max_raw_bytes,source_work,a,consumer,None,HistoryPurpose::Diagnostic),
    }
 }
 /// Closed joined Checker/Analyze role. No final macro inventory is
 /// issued, and the independent diagnostic define history remains required.
 pub fn prepare_original_compound_diagnostic_stream_using(
    project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,
    omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,
    a:&SettingAdmission<'_>,batch:&OriginalBatchExecution<'_>,
    consumer:&mut dyn OriginalPrimaryStreamConsumer,
 )->io::Result<OriginalGenerationProduct>{
    Self::prepare_original_stream_root_observer_using(
      project,provider,defines,omissions,max_raw_bytes,source_work,a,Some(batch),consumer,None,HistoryPurpose::Diagnostic,true)
 }
 /// Direct checker profile is explicitly named; it cannot masquerade as Analyze
 /// by wrapping a lazy stream or manufacturing a successful batch/EOF receipt.
 pub fn prepare_original_checker_stream_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer)->io::Result<OriginalGenerationProduct>{
  Self::prepare_original_checker_stream_root_observer_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,consumer,None,HistoryPurpose::Full)
 }
 pub fn prepare_original_checker_stream_observing_root_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer,observer:&dyn OriginalRootOpenObserver)->io::Result<OriginalGenerationProduct>{
  Self::prepare_original_checker_stream_root_observer_using(project,provider,defines,omissions,max_raw_bytes,source_work,a,consumer,Some(observer),HistoryPurpose::Full)
 }
 fn prepare_original_checker_stream_root_observer_using(project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,max_raw_bytes:usize,source_work:&dyn SourceArenaWork,a:&SettingAdmission<'_>,consumer:&mut dyn OriginalPrimaryStreamConsumer,root_observer:Option<&dyn OriginalRootOpenObserver>,history:HistoryPurpose)->io::Result<OriginalGenerationProduct>{
  let root_observer=root_observer.or_else(||provider.original_root_open_observer());
  let recipe=Recipe{project,provider,defines,omissions:&omissions,max_raw_bytes,work:source_work,root_observer,loan_batch_geometry:false,history,compact_final_macros:false};let mut output=None;let metadata=recipe.with_source(a,&mut|source|{if output.is_some(){return Err(io::ErrorKind::InvalidData.into())}output=Some(consume_prepared_primary_using(source,source_work,a,consumer)?);Ok(())})?;finalize(OriginalDemandDelivery::CheckerLazy0290,metadata,output.ok_or(io::ErrorKind::InvalidData)?,omissions,a,source_work)
 }
}

#[cfg(test)]#[path="original_generation_tests.rs"]mod tests;
