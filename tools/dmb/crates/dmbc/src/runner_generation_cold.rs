//! Cold missing-output preparation on the actual serialized BuildHost.
//! This returns only a retired journal or typed NotNeeded. It never publishes a
//! SourceSnapshot or converts an incomplete generation role into a full role.
use crate::{request::{BuildRequest,BuildCommand},runner_host::BuildHost,GeneratorName};
use crate::input_snapshot::{RecordingInputs,GeneratedOutputInputs,GenerationBootstrapPreparation,GenerationBootstrapFailure,OwnedGenerationFrame};
use std::{error::Error,io,path::Path,sync::Arc};
type Failure=Box<dyn Error>;
pub(crate) enum Preparation { NotNeeded, Closed(crate::runner_host::query_snapshot::ClosedGeneration) }
fn unsupported(message:&str)->Failure{io::Error::new(io::ErrorKind::InvalidInput,message).into()}
fn preparation_error(error:GenerationBootstrapFailure)->Failure{match error{GenerationBootstrapFailure::Operational(actual)=>actual.into(),GenerationBootstrapFailure::Declarations(other)=>crate::request_failure::RequestFailure::source(format!("generation-only preparation failed: {other:?}")).into()}}
pub(crate) fn validate(context:&BuildRequest)->Result<(),Failure>{
 if context.record_inputs.is_some()||context.replay_inputs.is_some()||context.trace_path.is_some(){return Err(unsupported("generation-only bootstrap does not yet support record/replay/trace requests"))}
 if context.source_questions.is_some()||context.diagnostic_declarations||context.artifact_directory.is_some(){return Err(unsupported("generation-only bootstrap requires strict workspace generation without artifact redirection"))}
 if context.policy_inputs.as_ref().and_then(|request|request.analysis_context).is_some(){if context.policy_inputs.as_ref().and_then(|request|request.analysis_context)!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)||!context.defines.is_empty()||context.engine_template.is_some()||context.bootstrap_catalog||context.output_store.is_some(){return Err(unsupported("Original generation requires actual default full Analyze purpose without caller engine/defines/output overrides"))}}
 if context.bootstrap_catalog&&context.engine_template.is_none(){return Err(unsupported("--bootstrap-catalog requires --engine-template"))}
 Ok(())
}
/// The caller supplies exactly this real phase's admitted names. Source-only
/// preparation precedes fresh question preparation after installation.
pub(crate) fn stage(host:&mut BuildHost,context:&BuildRequest,names:&[GeneratorName],requested:&[GeneratorName],questions:bool,cache:&Path)->Result<Preparation,Failure>{
 stage_using(host, context, names, requested, questions, cache, false)
}
/// Explicit opt-in only. Default generation still uses the existing phase.
pub(crate) fn stage_declare_overlay(host: &mut BuildHost, context: &BuildRequest, cache: &Path) -> Result<Preparation, Failure> {
 let names = &[GeneratorName::Declare];
 stage_using(host, context, names, names, false, cache, true)
}
fn stage_using(host: &mut BuildHost, context: &BuildRequest, names: &[GeneratorName], requested: &[GeneratorName],
 questions: bool, cache: &Path, declare_overlay: bool) -> Result<Preparation, Failure> {
 validate(context)?;if names.iter().any(|name|!requested.contains(name)){return Err(unsupported("generation phase contains an unrequested output"))}crate::daemon::control::checkpoint()?;
 let analysis_context=context.policy_inputs.as_ref().and_then(|request|request.analysis_context);
 let project=crate::policy_request::canonical_analysis_project(&context.project,analysis_context)?;
 let mut request=context.policy_inputs.clone().ok_or_else(||unsupported("generation bootstrap requires actual workspace input intent"))?;
 request.workspace_generators=names.to_vec();let intent=request.admit()?;
 let workspace=intent.workspace().ok_or_else(||unsupported("generation bootstrap requires actual workspace discovery"))?;
 let input_provider=super::generation_input_provider(context.record_inputs.as_deref(),context.replay_inputs.as_deref())?;
 input_provider.bind_policy_request(Some(&intent))?;
 let stamped=crate::frozen_inputs::ProofStampedInputs::new(&input_provider);
 let generated=GeneratedOutputInputs::new(&stamped,super::runner_generated_paths::paths(&project,&project,BuildCommand::PrepareQuery,context.output_store.as_deref(),None,None,context.cache_root.as_deref(),None)?);
 let now=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_nanos();
 let mut recording=RecordingInputs::new(&generated,now).with_initial_environment(analysis_context.map_or(dm_preprocess::InitialEnvironment::Native5161687,|context|context.initial_environment())).with_exact_reuse(context.exact_inputs).with_prepared_sources(host.prepared_sources());
 let subject=if analysis_context.is_some(){Some(recording.issue_original_analysis_subject(&intent)?)}else{None};let project=subject.as_ref().map_or_else(||project.clone(),|subject|subject.project().to_path_buf());
 if context.progress_enabled{if let Some(subject)=&subject{eprintln!("native Original generation: subject={} selected_phase={} questions={}",if subject.synthetic(){"synthetic CODE"}else{"fixed DME"},names.len(),questions);}}
 let mut defines=context.defines.clone();let embedded=context.engine_template.is_none();
 let bytes=super::generation_engine_bytes(embedded,true,&input_provider,context.engine_template.as_deref(),&recording)?;
 if analysis_context.is_none(){super::generation_engine_defines(true,bytes.as_deref(),&mut defines)?;}
 let engine=host.engine_with_context(project.clone(),defines.clone(),context.bootstrap_catalog||embedded,bytes.ok_or_else(||unsupported("generation engine template unavailable"))?,analysis_context)?;
 // The retained engine payload remains the host variant key; Original
 // declaration permission is lent only by the SAME singleton as PrepareQuery.
 let analysis_seed=analysis_context.map(|_|dm_tree::checker_builtins::original_analysis_seed()).transpose().map_err(|error|unsupported(&format!("original generation catalog: {error:?}")))?;
 let seed=analysis_seed.as_ref().map_or_else(||engine.frontend_seed(),|owner|owner.frontend_seed());
 let db=Arc::clone(host.query_db());let settings:Arc<dyn dm_tree::frontend::SettingExpressionQueries>=db.clone();
 let (_,execution,_)=host.execution(context.workers,None)?;
 execution.run(|executor|->Result<Preparation,Failure>{
  let progress=super::generation_progress;
  let config=dm_tree::frontend::FrontendConfig{workers:context.workers,engine:Some(seed),observer:context.progress_enabled.then_some(&progress)};
  // SAME discovery metadata ceiling; this stack admission funds omission paths
  // before joins/rows. Native parse and operation payloads retain their existing
  // admission owners; no extra manager or cached Budget is constructed here.
  let mut metadata=0usize;let mut admit=|bytes:usize|->io::Result<()>{crate::daemon::control::checkpoint()?;metadata=metadata.checked_add(bytes).filter(|n|*n<=64*1024*1024).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generation preparation metadata exceeds existing discovery bound"))?;Ok(())};
  if declare_overlay {
   let plan = recording.prepare_generation_declare_plan(&project, &defines, &settings, &mut admit)
       .map_err(preparation_error)?;
   let Some(plan) = plan else {
    input_provider.finish()?;
    crate::daemon::control::checkpoint()?;
    return Ok(Preparation::NotNeeded);
   };
   let discovery = Arc::clone(subject.as_ref().ok_or_else(|| unsupported("Declare overlay actual subject absent"))?.discovery());
   let probe = crate::input_snapshot::DeclareOverlayProbe { defines: &defines, config, executor, settings: &settings, db: &db };
   let spool = crate::generation_staging::temporary_output(cache)?;
   let closed = db.stage_generation_declare_overlay(plan, recording, discovery, &intent, spool, &probe)?;
   input_provider.finish()?;
   crate::daemon::control::checkpoint()?;
   return Ok(Preparation::Closed(closed));
  }
  let prepared=if questions{recording.prepare_generation_question_bootstrap(&project,&defines,config,executor,&settings,&mut admit)}else{recording.prepare_generation_bootstrap(&project,&defines,config,executor,&settings,&mut admit)}.map_err(preparation_error)?;
  let frame=match prepared{GenerationBootstrapPreparation::NotNeeded=>{// Selection-only preparation did not complete the ordinary prepared-source roster.
  // In particular, all-present returns before preparing a single source.
  // Pruning here would retire every still-current original acquisition and
  // force fresh body inputs on the immediately following complete request.
  input_provider.finish()?;crate::daemon::control::checkpoint()?;return Ok(Preparation::NotNeeded)},GenerationBootstrapPreparation::MissingOutputs(frame)=>frame};
  // A source-only subset cannot promise the final ordinary frame while an
  // encountered, unrequested generated include remains absent. Refuse BEFORE
  // staging/installation; no implicit prerequisite writes or fake completion.
  let actual_root=if let Some(subject)=&subject{subject.declared_entry_root(&project)?}else{project.parent().ok_or_else(||unsupported("generation manifest root unavailable"))?};
  for omitted in frame.declarations().encountered_omissions(){let relative=omitted.strip_prefix(actual_root).map_err(|_|unsupported("generation omission escapes its actual manifest root"))?;let selected=requested.iter().any(|name|{if *name==GeneratorName::UiTypes{return false}let path=if *name==GeneratorName::DerivedReads{"code/_generated/reads.dm"}else{name.path()};Path::new(path)==relative});if !selected{return Err(io::Error::new(io::ErrorKind::InvalidInput,format!("cold generation requires an explicitly selected output for omitted include {}",omitted.display())).into())}}
  let frame=if questions{OwnedGenerationFrame::Questions(frame.into_native_questions(&recording,config,executor,&db).map_err(preparation_error)?)}else{OwnedGenerationFrame::Declarations(frame)};
  let discovery=if let Some(subject)=&subject{Arc::clone(subject.discovery())}else{Arc::new(crate::runner_host::workspace_discovery::discover(&recording,crate::runner_host::workspace_discovery::DiscoveryContract{root:workspace.root.clone(),recursive_roots:workspace.recursive_roots.clone()})?)};
  let closed=db.stage_generation_bootstrap(frame,recording,discovery,&intent,names,crate::generation_staging::temporary_output(cache)?)?;
  input_provider.finish()?;crate::daemon::control::checkpoint()?;
  Ok(Preparation::Closed(closed))
 })?
}
