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
 if context.bootstrap_catalog&&context.engine_template.is_none(){return Err(unsupported("--bootstrap-catalog requires --engine-template"))}
 Ok(())
}
/// The caller supplies exactly this real phase's admitted names. Source-only
/// preparation precedes fresh question preparation after installation.
pub(crate) fn stage(host:&mut BuildHost,context:&BuildRequest,names:&[GeneratorName],requested:&[GeneratorName],questions:bool,cache:&Path)->Result<Preparation,Failure>{
 validate(context)?;if names.iter().any(|name|!requested.contains(name)){return Err(unsupported("generation phase contains an unrequested output"))}crate::daemon::control::checkpoint()?;
 let project=std::fs::canonicalize(&context.project)?;
 let mut request=context.policy_inputs.clone().ok_or_else(||unsupported("generation bootstrap requires actual workspace input intent"))?;
 request.workspace_generators=names.to_vec();let intent=request.admit()?;
 let workspace=intent.workspace().ok_or_else(||unsupported("generation bootstrap requires actual workspace discovery"))?;
 let input_provider=super::generation_input_provider(context.record_inputs.as_deref(),context.replay_inputs.as_deref())?;
 input_provider.bind_policy_request(Some(&intent))?;
 let stamped=crate::frozen_inputs::ProofStampedInputs::new(&input_provider);
 let generated=GeneratedOutputInputs::new(&stamped,super::runner_generated_paths::paths(&project,&project,BuildCommand::PrepareQuery,context.output_store.as_deref(),None,None,context.cache_root.as_deref(),None)?);
 let now=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_nanos();
 let recording=RecordingInputs::new(&generated,now).with_exact_reuse(context.exact_inputs).with_prepared_sources(host.prepared_sources());
 let mut defines=context.defines.clone();let embedded=context.engine_template.is_none();
 let bytes=super::generation_engine_bytes(embedded,true,&input_provider,context.engine_template.as_deref(),&recording)?;
 super::generation_engine_defines(true,bytes.as_deref(),&mut defines)?;
 let engine=host.engine(project.clone(),defines.clone(),context.bootstrap_catalog||embedded,bytes.ok_or_else(||unsupported("generation engine template unavailable"))?)?;
 let db=Arc::clone(host.query_db());let settings:Arc<dyn dm_tree::frontend::SettingExpressionQueries>=db.clone();
 let (_,execution,_)=host.execution(context.workers,None)?;
 execution.run(|executor|->Result<Preparation,Failure>{
  let progress=super::generation_progress;
  let config=dm_tree::frontend::FrontendConfig{workers:context.workers,engine:Some(engine.frontend_seed()),observer:context.progress_enabled.then_some(&progress)};
  // SAME discovery metadata ceiling; this stack admission funds omission paths
  // before joins/rows. Native parse and operation payloads retain their existing
  // admission owners; no extra manager or cached Budget is constructed here.
  let mut metadata=0usize;let mut admit=|bytes:usize|->io::Result<()>{crate::daemon::control::checkpoint()?;metadata=metadata.checked_add(bytes).filter(|n|*n<=64*1024*1024).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generation preparation metadata exceeds existing discovery bound"))?;Ok(())};
  let prepared=if questions{recording.prepare_generation_question_bootstrap(&project,&defines,config,executor,&settings,&mut admit)}else{recording.prepare_generation_bootstrap(&project,&defines,config,executor,&settings,&mut admit)}.map_err(preparation_error)?;
  let frame=match prepared{GenerationBootstrapPreparation::NotNeeded=>{// Selection-only preparation did not complete the ordinary prepared-source roster.
  // In particular, all-present returns before preparing a single source.
  // Pruning here would retire every still-current original acquisition and
  // force fresh body inputs on the immediately following complete request.
  input_provider.finish()?;crate::daemon::control::checkpoint()?;return Ok(Preparation::NotNeeded)},GenerationBootstrapPreparation::MissingOutputs(frame)=>frame};
  // A source-only subset cannot promise the final ordinary frame while an
  // encountered, unrequested generated include remains absent. Refuse BEFORE
  // staging/installation; no implicit prerequisite writes or fake completion.
  let actual_root=project.parent().ok_or_else(||unsupported("generation manifest root unavailable"))?;
  for omitted in frame.declarations().encountered_omissions(){let relative=omitted.strip_prefix(actual_root).map_err(|_|unsupported("generation omission escapes its actual manifest root"))?;let selected=requested.iter().any(|name|{if *name==GeneratorName::UiTypes{return false}let path=if *name==GeneratorName::DerivedReads{"code/_generated/reads.dm"}else{name.path()};Path::new(path)==relative});if !selected{return Err(io::Error::new(io::ErrorKind::InvalidInput,format!("cold generation requires an explicitly selected output for omitted include {}",omitted.display())).into())}}
  let frame=if questions{OwnedGenerationFrame::Questions(frame.into_native_questions(&recording,config,executor,&db).map_err(preparation_error)?)}else{OwnedGenerationFrame::Declarations(frame)};
  let discovery=Arc::new(crate::runner_host::workspace_discovery::discover(&recording,crate::runner_host::workspace_discovery::DiscoveryContract{root:workspace.root.clone(),recursive_roots:workspace.recursive_roots.clone()})?);
  let closed=db.stage_generation_bootstrap(frame,recording,discovery,&intent,names,crate::generation_staging::temporary_output(cache)?)?;
  input_provider.finish()?;crate::daemon::control::checkpoint()?;
  Ok(Preparation::Closed(closed))
 })?
}
