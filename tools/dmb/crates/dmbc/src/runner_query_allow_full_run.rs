//! One closed actual execution owner for full/exclusions-only ALLOW usage.
//! No caller-supplied usage vectors, counts or revision hashes can complete it.
use super::SourceSnapshot;
use crate::policy_request::{WorkspaceAuxiliaryQuestion as Q,AnalysisContext};
use dq_analyze::{captured_allow_annotations::{self as annotations,Operation,ValidationData},captured_allow_annotations::full_unused::{self,FrameData,UsageJoinData},captured_generator_budget::Budget,captured_raw_file::Config,captured_reactive_reads::Failure,key_policy_control::{self as kc,Control},lint::AllowUse};
use std::{io,sync::Arc};
fn operational(error:Failure)->io::Error{match error{Failure::Operational(error)=>error,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)}}
/// Borrowed only while this SAME execution's data and allocation budgets live.
/// This type has no public constructor and no independent source/run authority.
pub(crate) struct CompleteAllowRun<'a>{selected:&'a[String],validation:Option<&'a ValidationData>,unused:&'a[String]}
impl CompleteAllowRun<'_>{pub(crate) fn selected(&self)->&[String]{self.selected}pub(crate) fn validation(&self)->Option<&ValidationData>{self.validation}pub(crate) fn unused(&self)->&[String]{self.unused}}
/// A private staged report may borrow completed findings from these exact
/// producer calls. The final callback still owns authorization to publish.
enum UnionRows<'a,'rows>{
 Raw(&'a mut dyn Iterator<Item=&'rows dq_analyze::captured_raw_file::Findings>),
 Tree(&'a dq_analyze::captured_raw_tree_pages::Data),
 Silicon(&'a dq_analyze::captured_silicon_entry::Data),
 LibraryLayering(&'a dq_analyze::captured_engine_layering_pages::LayeringData),
 Handlers(&'a dq_analyze::captured_sem_handlers::Data),
 Untyped(&'a dq_analyze::captured_untyped_pages::UntypedData),
 DerivedReads(&'a dq_analyze::captured_derived_reads::DerivedReadData),
 SysReactive(&'a dq_analyze::captured_sys_reactive::Data),
 Semantic(Q,&'a dq_analyze::captured_sem_reads::SemanticPolicyData),
 Validation(&'a ValidationData),
}
#[derive(Clone,Copy,Debug)]enum Producer{Raw(&'static str),Tree(dq_analyze::captured_raw_tree_pages::Policy),Fold(dq_analyze::workspace_fold_policy::Policy),Special(&'static str)}
impl Producer{
 fn from_name(name:&str)->Option<Self>{
  // The union has its own validation plus unused-usage join. Its special
  // producer must remain distinct from explicit check-only report delivery.
  if name=="allow_annotations"{return Some(Self::Special("allow_annotations"))}
  if dq_analyze::captured_raw_policy::RAW_FILE_LINTS.contains(&name){return dq_analyze::captured_raw_policy::metadata(name).map(|meta|Self::Raw(meta.name))}
  if let Some(policy)=dq_analyze::captured_raw_tree_pages::Policy::from_name(name){return Some(Self::Tree(policy))}
  if let Some(policy)=dq_analyze::workspace_fold_policy::Policy::from_name(name){return Some(Self::Fold(policy))}
  Some(Self::Special(match name{
   "silicon_entry"=>"silicon_entry","sem/keys"=>"sem/keys","check_grep"=>"check_grep","sys/hygiene"=>"sys/hygiene","sys/resolvers"=>"sys/resolvers","sys/tables"=>"sys/tables","system_boundary"=>"system_boundary",
   "derived_reads"=>"derived_reads","sem/handlers"=>"sem/handlers","sem/reads"=>"sem/reads","untracked_inputs"=>"untracked_inputs","setter_publishes"=>"setter_publishes","decl"=>"decl","init"=>"init","base_vars"=>"base_vars","requirement_bool"=>"requirement_bool","player_link"=>"player_link","untyped_member"=>"untyped_member","weak_raw_read"=>"weak_raw_read","rel_write_undeclared"=>"rel_write_undeclared","untyped"=>"untyped","stored_refs"=>"stored_refs","engine_layering"=>"engine_layering","library_layering"=>"library_layering","sys/dx_reactive"=>"sys/dx_reactive","lifeforms"=>"lifeforms",_=>return None,
  }))
 }
 fn metadata(self)->&'static dq_analyze::lint::Meta{match self{
  Self::Raw(name)=>dq_analyze::captured_raw_policy::metadata(name).expect("closed raw metadata"),Self::Tree(policy)=>policy.metadata(),Self::Fold(policy)=>policy.metadata(),Self::Special(name)=>match name{
   "allow_annotations"=>dq_analyze::allow_annotation_policy::metadata(),"silicon_entry"=>&dq_analyze::silicon_entry_policy::META,"sem/keys"=>dq_analyze::keys_policy::metadata(),"check_grep"=>dq_analyze::lints::check_grep::native::metadata(),"sys/hygiene"=>dq_analyze::captured_sys_hygiene_pages::metadata(),"sys/resolvers"=>dq_analyze::captured_sys_resolvers_pages::metadata(),"sys/tables"=>dq_analyze::captured_sys_tables_pages::metadata(),"system_boundary"=>dq_analyze::captured_system_boundary_pages::metadata(),"derived_reads"=>dq_analyze::captured_derived_reads::metadata(),"sem/handlers"=>dq_analyze::sem_handlers_policy::metadata(),"sem/reads"=>dq_analyze::sem_reads_policy::metadata(),"untracked_inputs"=>dq_analyze::untracked_inputs_policy::metadata(),"setter_publishes"=>dq_analyze::setter_publication_policy::metadata(),"decl"=>dq_analyze::captured_decl_pages::metadata(),"init"=>dq_analyze::captured_init_pages::metadata(),"base_vars"=>dq_analyze::captured_base_vars_pages::metadata(),"requirement_bool"=>dq_analyze::captured_requirement_bool::metadata(),"player_link"=>dq_analyze::player_link_policy::metadata(),"untyped_member"=>dq_analyze::untyped_member_policy::metadata(),"weak_raw_read"=>dq_analyze::weak_relation_policy::metadata(),"rel_write_undeclared"=>dq_analyze::rel_write_policy::metadata(),"untyped"=>dq_analyze::untyped_policy_metadata::metadata(),"stored_refs"=>dq_analyze::stored_refs_policy::metadata(),"engine_layering"=>dq_analyze::engine_layering_policy::metadata(),"library_layering"=>dq_analyze::engine_layering_policy::Layer::Library.metadata(),"sys/dx_reactive"=>dq_analyze::sys_reactive_policy::metadata(),"lifeforms"=>dq_analyze::lifeforms_policy::metadata(),_=>unreachable!("closed producer metadata")
  }
 }}
 fn name(self)->&'static str{match self{Self::Raw(name)|Self::Special(name)=>name,Self::Tree(policy)=>policy.name(),Self::Fold(policy)=>policy.name()}}
 fn stages_report(self)->bool {
  use dq_analyze::captured_raw_tree_pages::Policy;
  matches!(self,
   Self::Raw(_) | Self::Tree(Policy::NoticePublisher | Policy::ReportInCatch | Policy::Cooldown)
   | Self::Special("allow_annotations" | "silicon_entry" | "library_layering" | "sem/handlers"
      | "sem/reads" | "untracked_inputs" | "setter_publishes" | "untyped" | "derived_reads" | "sys/dx_reactive")
  )
 }
 fn question(self)->Option<Q>{Some(match self.name(){"silicon_entry"=>Q::SiliconEntry,"sem/keys"=>Q::Keys,"check_grep"=>Q::CheckGrep,"deadline_polling"=>Q::DeadlinePollingAllowlist,"op_order"=>Q::OpOrder,"ui_actions"=>Q::UiActions,"doc_snippets"=>Q::DocSnippets,"ownership"=>Q::Ownership,"derived_reads"=>Q::DerivedReads,"sem/handlers"=>Q::SemHandlersFullAllow,"sem/reads"=>Q::SemReads,"untracked_inputs"=>Q::UntrackedInputs,"setter_publishes"=>Q::SetterPublishes,"tracked"=>Q::Tracked,"tracked_tests"=>Q::TrackedTests,"decl"=>Q::Decl,"init"=>Q::Init,"base_vars"=>Q::BaseVars,"requirement_bool"=>Q::RequirementBool,"player_link"=>Q::PlayerLink,"untyped_member"=>Q::UntypedMember,"weak_raw_read"=>Q::WeakRawRead,"rel_write_undeclared"=>Q::RelWriteUndeclared,"untyped"=>Q::Untyped,"stored_refs"=>Q::StoredRefs,"engine_layering"=>Q::EngineLayering,"library_layering"=>Q::LibraryLayeringFullAllow,"sys/dx_reactive"=>Q::SysReactive,"lifeforms"=>Q::Lifeforms,_=>return None})}
}
fn copy_validation(data:&ValidationData,c:&mut impl Control<Error=Failure>)->Result<ValidationData,Failure>{
 if data.sites.len()!=data.source_text.len(){return Err("actual ALLOW validation shape differs".into())}let mut out=ValidationData{sites:Vec::new(),source_text:Vec::new()};
 for(site,text)in data.sites.iter().zip(&data.source_text){c.checkpoint()?;let width=[site.rule.len(),site.rel.len(),site.msg.len(),site.key.len(),site.ident.len(),text.len()].into_iter().try_fold(0usize,|n,x|n.checked_add(x)).ok_or_else(||c.overflow())?;kc::reserve(c,||width.checked_mul(4)?.checked_add(1024))?;kc::row(c,&mut out.sites)?;kc::row(c,&mut out.source_text)?;out.sites.push(site.clone());out.source_text.push(text.clone());}c.checkpoint()?;Ok(out)
}
impl SourceSnapshot{
 /// Execute original full/exclusions-only selection through its real producers.
 /// A missing producer or child role refuses before any completed-union output.
 pub(crate) fn with_native_allow_full_run<R>(&self,tree:&dm_tree::SemanticTree,exclusions:&[String],consume:impl FnOnce(&CompleteAllowRun<'_>,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
  self.with_native_allow_full_run_using(tree,exclusions,None,None,None,consume)
 }
 fn with_native_allow_full_run_using<R>(&self,tree:&dm_tree::SemanticTree,exclusions:&[String],retained:Option<&Arc<Budget>>,handlers:Option<&super::HandlerWorkspaceSnapshot>,mut stage:Option<&mut dyn FnMut(&dq_analyze::lint::Meta,UnionRows<'_,'_>,&dq_analyze::scopes::LintScope,&Arc<Budget>)->io::Result<()>>,consume:impl FnOnce(&CompleteAllowRun<'_>,&Config,&Arc<Budget>)->io::Result<R>)->Result<R,Failure>{
  crate::daemon::control::checkpoint()?;if !self.matches_tree(tree){return Err("full ALLOW actual tree differs".into())}self.require_analysis_context(Some(AnalysisContext::OriginalAnalyze0290))?;self.require_original_fixed_report_subject(tree)?;
  let capture=self.native_workspace.as_ref().ok_or("full ALLOW actual workspace absent")?;let queries=self.native_raw_queries.as_ref().ok_or("full ALLOW actual QueryDb absent")?;let guard=self.workspace_native_read()?;capture.require_scope(&guard)?;queries.require_workspace_report_configuration(capture,&guard)?;
  let owned_budget;
  let budget=match retained{Some(budget)=>budget,None=>{owned_budget=queries.workspace_allow_run_budget(capture,&guard)?;&owned_budget}};
  let poll=||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()?;capture.require_scope(&guard)};
  let mut c=Operation{budget,poll:&poll};let selection=full_unused::registered_full_selection(exclusions,&mut c)?;
  if selection.names().is_empty(){kc::reserve(&mut c,||exclusions.iter().try_fold(128usize,|n,name|n.checked_add(name.len().checked_mul(4)?)))?;return Err(Failure::Unsupported(format!("no lint matches {exclusions:?}")))}
  let mut producers=Vec::new();
  for name in selection.names(){c.checkpoint()?;let Some(producer)=Producer::from_name(name)else{let message=kc::format(&mut c,format_args!("full ALLOW selected producer is not yet admitted: {name}"))?;return Err(Failure::Unsupported(message))};if matches!(producer,Producer::Special("silicon_entry"))&&stage.is_none(){return Err("silicon_entry usage requires the qualified staged selected-tree domain".into())}if matches!(producer,Producer::Special("library_layering"))&&stage.is_none(){return Err("library layering usage requires its qualified staged selected-tree domain".into())}if matches!(producer,Producer::Special("sem/handlers"))&&(stage.is_none()||handlers.is_none()){return Err("handlers usage requires its actual current demanded-full staged pair".into())}if stage.is_some()&&!producer.stages_report(){return Err("selected policy has no staged report adapter".into())}if let Some(question)=producer.question(){if !capture.has_auxiliary_question(question){return Err("full ALLOW selected producer lacks its actual prepared auxiliary question".into())}if question.is_semantic(){self.workspace_semantic_inputs_with_guard(question,&guard)?;}}kc::row(&mut c,&mut producers)?;producers.push(producer);}
  let selected_tree=full_unused::SelectedTreePlanData::new(producers.iter().map(|producer|producer.metadata().select),&mut c)?;
  let frame=FrameData{semantic:tree.identity(),source:self.source_revision,configuration:capture.policy_revision()};let mut usage=UsageJoinData::new(&selection,frame);let mut validation=None;
  for producer in producers{poll()?;let name=producer.name();
   // Only these concrete callbacks reach record_fold. No public record method,
   // registry name count or externally supplied UsageData can certify this run.
   let mut record=|used:&[AllowUse]|->io::Result<()>{usage.record_fold(name,frame,used,&mut c).map_err(operational)};
   match producer{
    Producer::Raw(_)=>{
     if let Some(stage)=stage.as_deref_mut(){
      queries.with_workspace_raw_union_rows(capture,&guard,name,budget,true,|rows,allows,report|{
       let (scope,child)=report.ok_or_else(||io::Error::other("raw union report has no actual child render budget"))?;
       stage(producer.metadata(),UnionRows::Raw(rows),scope,child)?;usage.record_fold_iter(name,frame,allows,&mut c).map_err(operational)})?;
     }else{
      queries.with_workspace_raw_allow_usage(capture,&guard,name,budget,|rows|usage.record_fold_iter(name,frame,rows,&mut c).map_err(operational))?;
     }
    },
    Producer::Tree(policy)=>{self.with_native_raw_tree(tree,policy,|data,config,child|{if let Some(stage)=stage.as_deref_mut(){let meta=producer.metadata();let default=dq_analyze::scopes::LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&default);stage(meta,UnionRows::Tree(data),scope,child)?}record(data.allow_used())})?;},
    Producer::Fold(policy)=>{self.with_native_workspace_fold_report(tree,policy,|data,_,_|record(data.allow_used()))?;},
    Producer::Special("allow_annotations")=>{self.with_native_allow_annotations(tree,|data,config,child|{
     if let Some(stage)=stage.as_deref_mut(){let meta=producer.metadata();let default=dq_analyze::scopes::LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&default);stage(meta,UnionRows::Validation(data),scope,child)?}
     else{validation=Some(copy_validation(data,&mut c).map_err(operational)?);}
     usage.record_fold(name,frame,&[],&mut c).map_err(operational)})?;},
    Producer::Special("silicon_entry")=>{
     let stage=stage.as_deref_mut().ok_or("silicon_entry selected report adapter absent")?;
     self.with_original_silicon_entry_policy_using(
      crate::runner_host::workspace_capture::SiliconActorDomain::SelectedCodeMaps(&selected_tree),
      |data,config,child|{
       let meta=producer.metadata();let empty=dq_analyze::scopes::LintScope::default();
       let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);
       stage(meta,UnionRows::Silicon(data),scope,child)?;
       record(data.allow_used())
      }
     )?;
    },
    Producer::Special("sem/keys")=>{self.with_native_keys(tree,|data,_,_|record(data.allow_used()))?;},
    Producer::Special("check_grep")=>{self.with_native_check_grep_report(tree,|data,_,_|record(&data.allow_used).map_err(Failure::Operational))?;},
    Producer::Special("sys/hygiene")=>{queries.with_workspace_hygiene_report(capture,&guard,|data,_,_|record(data.allow_used()))?;},
    Producer::Special("sys/resolvers")=>{queries.with_workspace_resolvers_report(capture,&guard,|data,_,_|record(data.allow_used()))?;},
    Producer::Special("sys/tables")=>{queries.with_workspace_tables_report(capture,&guard,|data,_,_|record(data.allow_used()))?;},
    Producer::Special("system_boundary")=>{queries.with_workspace_boundary_report(capture,&guard,|data,_,_|record(data.allow_used()))?;},
    Producer::Special("sem/handlers")=>{
     let stage=stage.as_deref_mut().ok_or("selected handlers report adapter absent")?;
     let handlers=handlers.ok_or("selected handlers actual paired source absent")?;
     handlers.with_selected_full_report(self,&guard,&selected_tree,|data,config,child_budget|{
      let meta=producer.metadata();let empty=dq_analyze::scopes::LintScope::default();
      let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);
      stage(meta,UnionRows::Handlers(data),scope,child_budget)?;
      record(data.allow_used())
     })?;
    },
    Producer::Special("sem/reads"|"untracked_inputs")=>{
     let question=producer.question().ok_or("semantic read producer has no source question")?;
     if let Some(stage)=stage.as_deref_mut(){
      let child=self.workspace_semantic_inputs_with_guard(question,&guard)?;
      queries.with_selected_workspace_semantic_read_report(capture,&guard,child,question,|data,config,child_budget|{
       let meta=producer.metadata();let empty=dq_analyze::scopes::LintScope::default();
       let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);
       stage(meta,UnionRows::Semantic(question,data),scope,child_budget)?;
       record(data.allow_used())
      })?;
     }else{
      self.with_original_semantic_policy_report(question,|data,_,_|record(data.allow_used()))?;
     }
    },
    Producer::Special("setter_publishes")=>{
     if let Some(stage)=stage.as_deref_mut(){
      let child=self.workspace_semantic_inputs_with_guard(Q::SetterPublishes,&guard)?;
      queries.with_selected_workspace_setter_report(capture,&guard,child,|data,config,child_budget|{
       let meta=producer.metadata();let empty=dq_analyze::scopes::LintScope::default();
       let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);
       stage(meta,UnionRows::Semantic(Q::SetterPublishes,data),scope,child_budget)?;
       record(data.allow_used())
      })?;
     }else{
      self.with_original_semantic_policy_report(Q::SetterPublishes,|data,_,_|record(data.allow_used()))?;
     }
    },
    Producer::Special("decl")=>{self.with_original_decl_policy(|data,_,_|record(data.allow_used()))?;},
    Producer::Special("init")=>{self.with_original_init_policy(|data,_,_|record(data.allow_used()))?;},
    Producer::Special("base_vars")=>{self.with_original_base_vars_policy(|data,_,_|record(data.allow_used()))?;},
    Producer::Special("requirement_bool")=>{self.with_original_requirement_bool_policy(|data,_,_|record(data.allow_used()))?;},
    Producer::Special("player_link")=>{self.with_original_player_link_policy(|data,_,_|record(data.allow_used()))?;},
    Producer::Special("untyped_member")=>{self.with_original_untyped_member_policy(|data,_,_|record(data.allow_used()))?;},
    Producer::Special("weak_raw_read")=>{self.with_original_weak_raw_read_policy(|data,_,_|record(data.allow_used()))?;},
    Producer::Special("rel_write_undeclared")=>{self.with_original_rel_write_undeclared_policy(|data,_,_|record(data.allow_used()))?;},
    Producer::Special("derived_reads")=>{
     let child=self.workspace_semantic_inputs_with_guard(Q::DerivedReads,&guard)?;
     let subject=child.original_analysis_subject().ok_or("Derived ALLOW requires its actual full Original subject")?;
     subject.derived_preflight()?.require_current(subject,capture,&guard,child.policy(),queries)?;
     // Selected preparation already owns the preprocessing transcript. The
     // exclusive wrapper would replay it, so borrow the actual judge directly.
     queries.with_original_workspace_derived_guard_report(capture,&guard,child,|data,config,child_budget|{
      if let Some(stage)=stage.as_deref_mut(){
       let meta=producer.metadata();let empty=dq_analyze::scopes::LintScope::default();
       let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);
       stage(meta,UnionRows::DerivedReads(data),scope,child_budget)?;
      }
      record(data.allow_used())
     })?;
    },
    Producer::Special("untyped")=>{
     if let Some(stage)=stage.as_deref_mut(){
      let child=self.workspace_semantic_inputs_with_guard(Q::Untyped,&guard)?;
      let subject=self.analysis_subject.as_ref().ok_or("selected untyped requires its actual full Original subject")?;
      if self.body_archive.as_ref().is_none_or(|archive| !Arc::ptr_eq(child.policy().archive(),archive))
       || !child.policy().archive().uses_body_queries(queries.as_ref()) {
       return Err("selected untyped does not share the current combined archive and QueryDb".into());
      }
      queries.with_selected_original_workspace_untyped_guard(capture,&guard,child,subject,|data,config,child_budget|{
       let meta=producer.metadata();let empty=dq_analyze::scopes::LintScope::default();
       let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);
       stage(meta,UnionRows::Untyped(data),scope,child_budget)?;
       record(data.allow_used())
      })?;
     }else{self.with_original_untyped_policy(|data,_,_|record(data.allow_used()))?;}
    },
    Producer::Special("stored_refs")=>{self.with_original_stored_refs_policy(|data,_,_|record(data.allow_used()))?;},
    Producer::Special("engine_layering")=>{self.with_original_engine_layering_policy(|data,_,_|record(data.allow_used()))?;},
    Producer::Special("library_layering")=>{
     let stage=stage.as_deref_mut().ok_or("library layering selected report adapter absent")?;
     let child=self.workspace_semantic_inputs(Q::LibraryLayeringFullAllow)?;
     let subject=self.analysis_subject.as_ref().ok_or("library layering selected Original subject unavailable")?;
     queries.with_original_workspace_library_layering_selected_union(capture,&guard,child,subject,|data,config,child_budget|{
      let meta=producer.metadata();let empty=dq_analyze::scopes::LintScope::default();
      let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);
      stage(meta,UnionRows::LibraryLayering(data),scope,child_budget)?;
      record(data.allow_used())
     })?;
    },
    Producer::Special("sys/dx_reactive")=>{
     self.with_original_sys_reactive_policy_report(|data,config,budget|{
      if let Some(stage)=stage.as_deref_mut(){
       let meta=producer.metadata();
       let default=dq_analyze::scopes::LintScope::default();
       let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&default);
       stage(meta,UnionRows::SysReactive(data),scope,budget)?;
      }
      record(data.allow_used())
     })?;
    },
    Producer::Special("lifeforms")=>{self.with_original_lifeforms_policy_report(|_,_,_|record(&[]))?;},
    Producer::Special(_)=>return Err("closed full ALLOW producer dispatch differs".into()),
   }
   poll()?;
  }
  let completed=usage.finish_data(&mut c)?;
  queries.with_workspace_full_allow_unused(capture,&guard,&selected_tree,&completed,|problems,config,unused_budget|{poll()?;let data=CompleteAllowRun{selected:selection.names(),validation:validation.as_ref(),unused:problems};let pending=consume(&data,config,if retained.is_some(){unused_budget}else{budget});if pending.is_err(){return pending}poll()?;pending})
 }
}

#[cfg(test)]mod metadata_controls{
 use super::*;
 #[test]fn unported_producers_never_become_zero_use_completions_and_every_dispatch_has_its_actual_name(){
  for name in ["not_a_registered_policy"]{assert!(Producer::from_name(name).is_none(),"no source authority or completion for {name}");}
  for name in ["allow_annotations","scheduler","derived_reads","silicon_entry","sem/handlers","op_order","ui_actions","sem/keys","check_grep","tracked","tracked_tests","sem/reads","setter_publishes","init","decl","base_vars","requirement_bool","sys/dx_reactive","lifeforms"]{let producer=Producer::from_name(name).unwrap();assert_eq!(producer.name(),name);if let Some(question)=producer.question(){assert!(Q::ALL.contains(&question));}}
 }
}

#[cfg(test)]
#[path="runner_query_allow_full_run_tests.rs"]
mod union_tests;

#[path="runner_query_selected_report.rs"]
mod selected_report;
pub(in crate::runner_host) use selected_report::{checked_stage,stage_named_image_dir,validate_selection,validate_selection_v2,SelectedReportPlan};
