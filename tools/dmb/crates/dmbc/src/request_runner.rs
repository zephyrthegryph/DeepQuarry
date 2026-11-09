//! Shared request execution; the CLI and future hosts use this exact pipeline.
use crate as dmbc;
use crate::request::{BuildCommand, BuildOutcome, BuildRequest, Command, CommandOutcome};
use std::{
    io::{self, Write},
    path::{Path, PathBuf},
    sync::Arc,
    time::Instant,
};
#[path = "runner_facts.rs"]
pub(crate) mod runner_facts;
#[path = "runner_report.rs"]
mod runner_report;
#[path="runner_owner_observation.rs"]
mod owner_observation;
#[path = "runner_resources.rs"]
mod runner_resources;
use runner_resources::{OutputResourceSink, ResourceOutputs};
#[path = "runner_cache_records.rs"]
mod runner_cache_records;
#[path = "runner_configuration.rs"]
mod runner_configuration;
#[path = "runner_freshness.rs"]
pub(crate) mod runner_freshness;
#[path = "runner_generated_paths.rs"]
mod runner_generated_paths;
use runner_cache_records::publish_cache_records;
#[path="request_handlers_prepare.rs"]mod handlers_prepare;
pub fn run(request: Command) -> Result<CommandOutcome, Box<dyn std::error::Error>> {
    match request {
        Command::Query { request, jsonl } => {
            dmbc::daemon::query::run_file(&request, jsonl).map(|()| CommandOutcome::Completed)
        }
        Command::QueryExport { request, limits } => {
            dmbc::daemon::query::semantic_client::run_export_file(&request, limits)
                .map(|()| CommandOutcome::Completed)
        }
        Command::Help => {
            dmbc::daemon_println!("dmbc analyze|compile|prepare-query [--bodies|--resolved (analyze only)] [--request-timeout-seconds N] [--no-daemon] [--no-cache] [--exact-inputs] [--verify] [--trace FILE] PROJECT [-DNAME[=VALUE]] [--workers N] [--engine-template PATH] [--bootstrap-catalog] [--progress] [--output-store PATH] [--warnings-as-errors] [--ignore-warning CODE[,CODE...]]");
            dmbc::daemon_println!(
                "dmbc stats [PROJECT] | explain PROCEDURE [PROJECT] | gc [PROJECT] | query REQUEST.json [--jsonl|--export-jsonl]"
            );
            dmbc::daemon_println!("prepare-query uses the ordinary source configuration, emits current revision pins without compiling bodies or publishing output; retained queries require a daemon, and pressure may make prepared owners unavailable.");
            dmbc::daemon_println!("compile publishes a new immutable output pair and installs PROJECT.dmb/.rsc; unsupported semantics fail before publication.");
            Ok(CommandOutcome::Completed)
        }
        Command::Gc { project } => {
            let project = std::fs::canonicalize(project)?;
            dmbc::daemon_println!(
                "{}",
                serde_json::to_string_pretty(&dmbc::cache_maintenance::run(&project)?)?
            );
            Ok(CommandOutcome::Completed)
        }
        Command::Stats { project } => inspect(project, None).map(|()| CommandOutcome::Completed),
        Command::Explain { project, target } => {
            inspect(project, Some(&target)).map(|()| CommandOutcome::Completed)
        }
        Command::Verify(arguments) => {
            dmbc::verification::run_cli(&arguments).map(|()| CommandOutcome::Completed)
        }
        Command::Build(request) => run_build(*request).map(CommandOutcome::Build),
    }
}
fn inspect(project: PathBuf, target: Option<&str>) -> Result<(), Box<dyn std::error::Error>> {
    let project = std::fs::canonicalize(project)?;
    dmbc::daemon_println!(
        "{}",
        serde_json::to_string_pretty(&dmbc::telemetry::inspect(&project, target)?)?
    );
    Ok(())
}
/// Progress line for one prior session record's validation attempt.
struct RecordTimer(u128, Instant);
impl Drop for RecordTimer {
    fn drop(&mut self) {
        dmbc::daemon_eprintln!(
            "native session record {:032x}: {:.3}s",
            self.0,
            self.1.elapsed().as_secs_f64()
        );
    }
}
pub fn run_build(request: BuildRequest) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    run_build_with_host(request, &mut crate::runner_host::BuildHost::one_shot())
}
pub fn run_build_with_host(
    request: BuildRequest,
    host: &mut crate::runner_host::BuildHost,
) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    let mut writer=crate::daemon::stderr_writer();let mut output=PreparationDiagnosticOutput::immediate(&mut writer);
    run_build_with_host_and_derived_sink(request,host,None,&mut output)
}
pub(crate) trait DerivedFailureReportSink{
    fn consume(&mut self,data:&dq_analyze::captured_derived_reads::DerivedReadData,config:&dq_analyze::captured_raw_file::Config);
    fn consume_budget(&mut self,data:&dq_analyze::captured_derived_reads::DerivedReadData,config:&dq_analyze::captured_raw_file::Config,_budget:&Arc<dq_analyze::captured_generator_budget::Budget>){self.consume(data,config)}
    fn failed(&mut self,error:io::Error);
}
pub(crate) fn run_build_with_host_and_derived_sink(
    request:BuildRequest,host:&mut crate::runner_host::BuildHost,derived_sink:Option<&mut dyn DerivedFailureReportSink>,preparation_output:&mut PreparationDiagnosticOutput<'_>,
)->Result<BuildOutcome,Box<dyn std::error::Error>>{run_build_with_host_and_derived_sink_from(request,host,derived_sink,preparation_output,None)}
/// The borrowed provider is carried through the SAME normal factory and retry
/// loop. No source role is granted by accepting this operation-scoped loan.
pub(crate) fn run_build_with_host_and_derived_sink_from(
    request:BuildRequest,host:&mut crate::runner_host::BuildHost,derived_sink:Option<&mut dyn DerivedFailureReportSink>,preparation_output:&mut PreparationDiagnosticOutput<'_>,source_override:Option<&(dyn crate::input_snapshot::SnapshotProvider+Sync)>,
)->Result<BuildOutcome,Box<dyn std::error::Error>>{run_build_with_host_and_policy_sinks_from(request,host,derived_sink,None,preparation_output,source_override)}

pub(crate) fn run_build_with_host_and_policy_sinks_from(
    request:BuildRequest,host:&mut crate::runner_host::BuildHost,derived_sink:Option<&mut dyn DerivedFailureReportSink>,handlers_sink:Option<&mut dyn HandlersFailureReportSink>,preparation_output:&mut PreparationDiagnosticOutput<'_>,source_override:Option<&(dyn crate::input_snapshot::SnapshotProvider+Sync)>,
)->Result<BuildOutcome,Box<dyn std::error::Error>>{
    run_build_with_selected_publication(request,host,derived_sink,handlers_sink,preparation_output,source_override,None,false)
}

pub(crate) use runner_freshness::JoinedSelectedInputs;
pub(crate) fn validate_joined_compile_request(
    request: &BuildRequest, host: &crate::runner_host::BuildHost,
) -> io::Result<()> {
    if request.command != BuildCommand::Compile || !request.exact_inputs || !request.no_cache
        || request.record_inputs.is_some() || request.replay_inputs.is_some() || request.no_daemon
        || request.policy_inputs.is_some() || request.source_questions.is_some()
        || request.diagnostic_declarations || request.trace_path.is_some() || !host.retains_artifacts()
        || request.warnings != crate::diagnostics::WarningPolicy::default() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined selected reports require live exact no-cache native compilation"));
    }
    Ok(())
}

/// Strict native entry for private, already staged selected reports.
pub(crate) fn compile_with_joined_selected_inputs(
    request: BuildRequest, host: &mut crate::runner_host::BuildHost, joined: &JoinedSelectedInputs,
) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    validate_joined_compile_request(&request, host)?;
    joined.require_strict_profile(&request.defines)?;
    let mut writer = crate::daemon::stderr_writer();
    let mut output = PreparationDiagnosticOutput::immediate(&mut writer);
    run_build_with_selected_publication(request,host,None,None,&mut output,None,Some(joined),false)
}

/// Private host entry. Ordinary request admission cannot acquire this roster.
pub(crate) fn prepare_private_authored_doc_ui(
    request: BuildRequest, host: &mut crate::runner_host::BuildHost,
) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    if request.command != BuildCommand::PrepareQuery || !host.retains_artifacts()
        || request.record_inputs.is_some() || request.replay_inputs.is_some()
        || request.policy_inputs.is_none()
    {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "private authored Docs/UI requires live retained preparation").into());
    }
    let mut writer = crate::daemon::stderr_writer();
    let mut output = PreparationDiagnosticOutput::immediate(&mut writer);
    run_build_with_selected_publication(request,host,None,None,&mut output,None,None,true)
}

fn run_build_with_selected_publication(
    mut request:BuildRequest,host:&mut crate::runner_host::BuildHost,mut derived_sink:Option<&mut dyn DerivedFailureReportSink>,mut handlers_sink:Option<&mut dyn HandlersFailureReportSink>,preparation_output:&mut PreparationDiagnosticOutput<'_>,source_override:Option<&(dyn crate::input_snapshot::SnapshotProvider+Sync)>,
    joined: Option<&JoinedSelectedInputs>,
    private_authored_doc_ui: bool,
)->Result<BuildOutcome,Box<dyn std::error::Error>>{
    if joined.is_none() { host.discard_joined_report_replay(); }
    if source_override.is_some(){
        if request.command!=BuildCommand::PrepareQuery||!host.retains_artifacts()||request.policy_inputs.as_ref().and_then(|p|p.analysis_context).is_none()||request.record_inputs.is_some()||request.replay_inputs.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"borrowed source requires retained Original preparation without journal overrides").into())}
        // No default-provider cache or prepared-source artifact may stand in for
        // this provider. Genuine current facts are revalidated through it below.
        request.no_cache=true;request.exact_inputs=true;
    }
    crate::request::validate_timeout_seconds(request.timeout_seconds)?;
    crate::request::validate_source_questions(&request)?;
    if request.source_questions.is_some() && !host.retains_artifacts(){return Err(std::io::Error::other("source question preparation requires retained original owners").into());}
    crate::request::validate_diagnostic_declarations(&request)?;
    if request.diagnostic_declarations && !host.retains_artifacts(){return Err(std::io::Error::other("diagnostic preparation requires the existing retained query owner").into());}
    // Service-bound requests inherit the original admission+execution deadline;
    // local requests issue it once, outside freshness retries.
    let _deadline_binding = if crate::daemon::control::WorkerContext::capture().is_none() {
        crate::daemon::prepare_deadline::capture(request.command, request.timeout_seconds, Instant::now())?
            .map(|deadline| crate::daemon::control::bind_with_deadline(
                crate::daemon::control::Cancellation::default(), deadline))
    } else { None };
    let report = (request.command == BuildCommand::Compile).then(|| request.project.clone());
    dmbc::diagnostics::begin(request.warnings.clone());
    let result = runner_freshness::run(request, |request| {
        preparation_output.start_attempt()?;
        run_build_attempt(request, host,&mut derived_sink,&mut handlers_sink,preparation_output,source_override,joined,private_authored_doc_ui)
    });
    match report {
        Some(project) => finish_report(&project, result),
        None => result,
    }
}
#[path = "runner_summary.rs"]
mod runner_summary;
use runner_summary::finish_report;
#[path = "runner_analysis.rs"]
pub(crate) mod runner_analysis;
#[path = "runner_output_digest.rs"]
mod output_digest;
fn run_build_attempt(
    request: BuildRequest,
    host: &mut crate::runner_host::BuildHost,
    derived_sink:&mut Option<&mut dyn DerivedFailureReportSink>,
    handlers_sink:&mut Option<&mut dyn HandlersFailureReportSink>,
    preparation_output:&mut PreparationDiagnosticOutput<'_>,
    source_override:Option<&(dyn crate::input_snapshot::SnapshotProvider+Sync)>,
    joined: Option<&JoinedSelectedInputs>,
    private_authored_doc_ui: bool,
) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    let retains_query_owners = host.retains_artifacts();
    let mut query_attempt = crate::runner_host::query_snapshot::QueryAttempt::new(
        host.query_state(),
        host.retains_artifacts(),
    );
    let _build_profile = dm_profile::stage("build");
    // A retried attempt reports its own diagnostics; count only those.
    dmbc::diagnostics::begin(request.warnings.clone());
    let request_profile = dm_profile::stage("request.prepare");
    crate::request::validate_diagnostic_declarations(&request)?;
    let BuildRequest {
        command,
        source_questions,
        diagnostic_declarations,
        timeout_seconds: _,
        policy_inputs,
        project,
        mut defines,
        workers,
        engine_template,
        mut bootstrap_catalog,
        progress_enabled,
        output_store,
        exact_inputs,
        no_cache,
        cache_root,
        record_inputs,
        replay_inputs,
        artifact_directory,
        no_daemon: _,
        trace_path,
        warnings: _,
    } = request;
    let policy_inputs = policy_inputs.map(|request| if private_authored_doc_ui {
        request.admit_private_authored_doc_ui()
    } else { request.admit() }).transpose()?;
    let analysis_context=policy_inputs.as_ref().and_then(|request|request.analysis_context());
    if analysis_context.is_some(){
        if command!=BuildCommand::PrepareQuery || !retains_query_owners || !defines.is_empty()
            || engine_template.is_some() || bootstrap_catalog || source_questions.is_some()
            || record_inputs.is_some() || replay_inputs.is_some() || trace_path.is_some()
            || artifact_directory.is_some() || output_store.is_some(){
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"original analysis context requires retained PrepareQuery with default declarations and no compiler/trace/replay overrides").into());
        }
        if policy_inputs.as_ref().and_then(|intent|intent.workspace()).is_some_and(|workspace|
            policy_inputs.as_ref().is_some_and(|intent|intent.workspace_auxiliary().iter().any(|question|matches!(question,crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep|crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrepBaseline)))
            && project!=workspace.root.join("deepquarry.dme")){
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"original Analyze workspace requires its actual fixed deepquarry.dme environment").into());
        }
    }

    let publishable_artifacts = command == BuildCommand::Compile;
    let project = crate::policy_request::canonical_analysis_project(&project,analysis_context)?;
    if record_inputs.is_some() && replay_inputs.is_some() {
        return Err("record and replay inputs are mutually exclusive".into());
    }
    let verification_capture = record_inputs.is_some() || replay_inputs.is_some();
    let output_project = match &artifact_directory {
        Some(directory) => {
            std::fs::create_dir_all(directory)?;
            directory.join(project.file_name().ok_or("manifest filename missing")?)
        }
        None => project.clone(),
    };
    let total = Instant::now();
    dm_profile::request_marks_begin_if_idle();
    dm_profile::request_mark("runner.start");
    let mut build_lock = if command == BuildCommand::Compile {
        Some(dmbc::compile_driver::acquire_build_lock(&project)?)
    } else {
        None
    };
    if bootstrap_catalog && engine_template.is_none() {
        return Err("--bootstrap-catalog requires --engine-template".into());
    }
    // These are caller-supplied source defines. No target ABI is inferred by the
    // reusable frontend; supply DM_VERSION/DM_BUILD explicitly when needed.
    let executable = matches!(
        command,
        BuildCommand::Compile | BuildCommand::AnalyzeResolved | BuildCommand::PrepareQuery
    );
    let embedded_engine = executable && engine_template.is_none();
    if embedded_engine {
        bootstrap_catalog = true;
    }
    let now_ns = || {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock is after epoch")
            .as_nanos()
    };
    let input_provider = generation_input_provider(record_inputs.as_deref(), replay_inputs.as_deref())?;
    input_provider.bind_policy_request(policy_inputs.as_ref())?;
    // Stamps come from session validation's directory proofs once captured.
    let stamped_provider = match source_override{Some(provider)=>dmbc::frozen_inputs::ProofStampedInputs::from_original_provider(&input_provider,provider),None=>dmbc::frozen_inputs::ProofStampedInputs::new(&input_provider)};
    let generated_provider = dmbc::input_snapshot::GeneratedOutputInputs::new(
        &stamped_provider,
        runner_generated_paths::paths(
            &project,
            &output_project,
            command,
            output_store.as_deref(),
            artifact_directory.as_deref(),
            record_inputs.as_deref(),
            cache_root.as_deref(),
            trace_path.as_deref(),
        )?,
    );
    let generated_paths =
        dmbc::input_snapshot::SnapshotProvider::generated_outputs(&generated_provider)
            .expect("explicit generated output policy");
    let prepared_sources = if source_override.is_none(){host.prepared_sources()}else{None};
    let mut inputs_capture = dmbc::input_snapshot::RecordingInputs::new(&generated_provider, now_ns())
        .with_initial_environment(analysis_context.map_or(dm_preprocess::InitialEnvironment::Native5161687,|context|context.initial_environment()))
        .with_exact_reuse(exact_inputs)
        .with_prepared_sources(prepared_sources.clone());
    // Engine selection is configuration+metadata first, exactly like the old
    // lint's files().is_empty() branch. Never open a manifest or CODE payload
    // merely to prove that no engine source survived the actual selection.
    let mut engine_preflight=if command==BuildCommand::PrepareQuery&&policy_inputs.as_ref().is_some_and(|intent|crate::policy_request::WorkspaceAuxiliaryQuestion::exclusive_layering(intent.workspace_auxiliary()).is_some()){Some(crate::runner_host::workspace_discovery::discover_engine_preflight(&inputs_capture,policy_inputs.as_ref().expect("actual engine intent"))?)}else{None};
    if engine_preflight.as_ref().is_some_and(|selection|selection.is_empty()){
        let intent=policy_inputs.as_ref().expect("actual conditional Engine intent");let queries=Arc::clone(host.query_db());query_attempt.bind_current_variant(host.query_state())?;
        let proof=engine_preflight.take().expect("actual empty Engine preflight").into_unselected()?;let(captured,owner)=crate::runner_host::workspace_capture::capture_engine_unselected(&inputs_capture,intent,&queries,proof)?;
        let admission=runner_freshness::admit_workspace_captured_using(&inputs_capture,None,&stamped_provider,generated_paths,Arc::clone(&captured),queries.as_ref())?.1;
        input_provider.finish()?;inputs_capture.finish_prepared()?;dmbc::daemon::control::checkpoint()?;
        let(query,source,policy)=query_attempt.admit_raw_source(intent,captured,owner,queries,admission)?;query_attempt.finish_raw_source();
        return Ok(BuildOutcome::RawQueryPrepared{query_revision:format!("{query:032x}"),source_revision:format!("{source:032x}"),policy_revision:format!("{policy:032x}"),retained:retains_query_owners});
    }
    // Purely textual producers need no DME or semantic guard. An exact raw
    // purpose can publish only its own report and cannot compile or lower.
    if command==BuildCommand::PrepareQuery&&policy_inputs.as_ref().is_some_and(|intent|intent.analysis_context()==Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)&&(intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::DocSnippets]||intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::DocSnippetsFullAllow]||intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::Ownership]||intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::NoticePublisher]||intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::OpOrder]||intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::UiActions]||intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::UiActionsFullAllow]||intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::DocUiFullAllow]||intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::AllRawFilePolicies])){
        let intent=policy_inputs.as_ref().expect("exact admitted raw source intent");let queries=Arc::clone(host.query_db());query_attempt.bind_current_variant(host.query_state())?;
        let prior=query_attempt.current_raw_capture();let(captured,owner)=crate::runner_host::workspace_capture::capture_raw_only_with_prior(&inputs_capture,intent,&queries,prior.as_ref())?;
        let admission=runner_freshness::admit_workspace_captured_using(&inputs_capture,None,&stamped_provider,generated_paths,Arc::clone(&captured),queries.as_ref())?.1;
        input_provider.finish()?;inputs_capture.finish_prepared()?;dmbc::daemon::control::checkpoint()?;
        let(query,source,policy)=query_attempt.admit_raw_source(intent,captured,owner,queries,admission)?;query_attempt.finish_raw_source();
        return Ok(BuildOutcome::RawQueryPrepared{query_revision:format!("{query:032x}"),source_revision:format!("{source:032x}"),policy_revision:format!("{policy:032x}"),retained:retains_query_owners});
    }
    // Derived's selected raw schema is a genuine cold preflight: run it
    // before issuing any manifest/frontend subject, using the same recorder
    // and the QueryDb input-family resource ledger. This is not a raw-only
    // completion; the existing full semantic pipeline still follows below.
    let joined_derived = match policy_inputs.as_ref() {
        Some(intent) if intent.workspace_auxiliary() == crate::policy_request::WorkspaceAuxiliaryQuestion::PRIVATE_FULL_REGISTRY =>
            Some(Arc::clone(host.query_db()).prepare_derived_preflight(&inputs_capture,intent)?),
        _ => None,
    };
    if joined_derived.is_some() { dm_profile::detail_mark("request.joined_derived", total); }
    // Genuine partial source is prepared before any independent full Subject.
    let stage_handlers=joined_derived.is_some()&&preparation_output.needs_combined_checker()&&preparation_output.wants_joined_inputs();
    let mut handlers_capture=if command==BuildCommand::PrepareQuery{match policy_inputs.as_ref(){Some(intent)=>handlers_prepare::prepare(&inputs_capture,intent,host,workers,joined_derived.as_ref(),stage_handlers)?,None=>None}}else{None};
    if stage_handlers{
        let capture=handlers_capture.take().ok_or("full registry partial handler source absent")?;
        let cache=cache_root.as_deref().ok_or("full registry handler row stage requires its admitted cache root")?;
        let queries=Arc::clone(host.query_db());
        // Notices go only to the private attempt spool and stay before full
        // notices; full preparation errors still win before publication.
        if let Some(frontend)=capture.prepared().frontend(){
            let partial=frontend.handlers_structural_source().map_err(io::Error::other)?;
            if let Some(notices)=partial.view().original_preprocess_notices(){
                preparation_output.emit(|mut output|dmbc::diagnostics::write_original_preprocess_notices(&mut output,&notices))?;
            }
        }
        let proof=runner_freshness::admit_handlers_structural_staging(&inputs_capture,Arc::clone(&capture),queries.as_ref())?;
        let staged=queries.stage_handler_structural_rows(&capture,&proof,cache);
        drop(proof);
        // Preserve the original report-stage position of a structural policy
        // failure. No pending row/error is published before the full barrier.
        handlers_capture=Some(crate::input_snapshot::HandlerPreparedCapture::detach_staged(capture,staged)?);
    }
    if joined_derived.is_some() { dm_profile::detail_mark("request.joined_handlers", total); }
    if handlers_capture.as_ref().is_some_and(|capture|
        !capture.prepared().subject().requires_full_model() && !capture.prepared().subject().is_selected_full()
    ){
        let capture=handlers_capture.take().expect("actual structural-only preparation");let intent=policy_inputs.as_ref().expect("actual handler intent");let queries=Arc::clone(host.query_db());query_attempt.bind_current_variant(host.query_state())?;
        let partial_source_revision=capture.partial_revision()?.map(|revision|format!("{revision:032x}"));
        let proof=runner_freshness::admit_handlers_captured_using(&inputs_capture,None,&input_provider,generated_paths,Arc::clone(&capture),queries.as_ref())?.1.into_shared()?;
        input_provider.finish()?;inputs_capture.finish_prepared()?;dmbc::daemon::control::checkpoint()?;
        let query=query_attempt.admit_handlers_source(intent,capture,proof,queries)?;query_attempt.finish_handlers_source();
        return Ok(BuildOutcome::HandlersQueryPrepared{query_revision:format!("{query:032x}"),partial_source_revision,full_source_revision:None,retained:retains_query_owners});
    }
    let derived_preflight=if joined_derived.is_some(){joined_derived}else if analysis_context==Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)&&policy_inputs.as_ref().is_some_and(|intent|intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::DerivedReads]){
        Some(Arc::clone(host.query_db()).prepare_derived_preflight(&inputs_capture,policy_inputs.as_ref().expect("exact admitted Derived intent"))?)
    }else{None};
    let analysis_subject=if analysis_context==Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290){let intent=policy_inputs.as_ref().ok_or("Analyze subject intent absent")?;Some(if let Some(preflight)=derived_preflight{inputs_capture.issue_original_analysis_subject_derived(intent,preflight)?}else{match engine_preflight.take(){Some(selection)=>inputs_capture.issue_original_analysis_subject_engine(intent,selection)?,None=>inputs_capture.issue_original_analysis_subject(intent)?}})}else{None};
    let project=analysis_subject.as_ref().map_or_else(||project.clone(),|subject|subject.project().to_path_buf());
    // Arm only this selected actual root attempt, with the existing QueryDb
    // declaration admission. An observation is evidence, never fallback or a
    // model-unavailable classification inferred from an unrelated error.
    if analysis_context==Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)&&policy_inputs.as_ref().is_some_and(|intent|matches!(intent.workspace_auxiliary(),[crate::policy_request::WorkspaceAuxiliaryQuestion::DerivedReads]|[crate::policy_request::WorkspaceAuxiliaryQuestion::SemHandlers])){
        host.query_db().arm_recorded_root_attempt(&inputs_capture,&project)?;
    }
    drop(request_profile);
    dm_profile::detail_mark("request.prepare", total);
    let engine_input_profile = dm_profile::stage("engine_input");
    let engine_bytes = generation_engine_bytes(embedded_engine, executable, &input_provider, engine_template.as_deref(), &inputs_capture)?;
    let engine_identity = engine_bytes
        .as_ref()
        .map_or(0, |bytes| xxhash_rust::xxh3::xxh3_128(bytes));
    drop(engine_input_profile);
    dm_profile::detail_mark("engine_input", total);
    let input_context_profile = dm_profile::stage("request.input_context");
    if analysis_context.is_none(){generation_engine_defines(executable, engine_bytes.as_deref(), &mut defines)?;}
    let mut session = None;
    let mut pair_store = None;
    // Request-owned leases outlive the borrowed capture sink and cold compiler.
    // They are released only after the final immutable pair is published.
    let resource_outputs = std::sync::Mutex::new(ResourceOutputs::default());
    let mut resource_prior = None;
    let mut prior_outputs = None;
    // Source files read by the latest recorded build; offered to the parallel
    // input pass as speculative candidates (see NativeInputs::prepare_with_hints).
    let mut recorded_source_paths: Vec<PathBuf> = Vec::new();
    let mut memo_policy = 0;
    let mut facts_policy = 0;
    drop(input_context_profile);
    dm_profile::detail_mark("input_context", total);
    let session_profile = dm_profile::stage("session_validation");
    if retains_query_owners && source_override.is_none() {
        if let Some(root) = project.parent() {
            dmbc::fs_watch::arm(root);
            dmbc::fs_watch::sync(root);
        }
        dm_profile::request_mark("session.watch_synced");
    }
    // Daemon sessions retain artifacts; only they outlive the request and may publish the cache batch afterwards.
    let defer_cache_batch = host.retains_artifacts();
    let compiler = if executable && (!no_cache || host.retains_artifacts()) {
        let compiler = dmbc::daemon::compiler_identity()?;
        let mut policy_bytes = b"native-lowering-policy-v1\0".to_vec();
        policy_bytes.extend_from_slice(&compiler.to_le_bytes());
        policy_bytes.extend_from_slice(&engine_identity.to_le_bytes());
        policy_bytes.push(u8::from(bootstrap_catalog));
        // DbgFile/DbgLine are emitted only under DEBUG, so a DEBUG flip must not reuse memoized code.
        policy_bytes.push(u8::from(defines.contains_key("DEBUG")));
        memo_policy = xxhash_rust::xxh3::xxh3_128(&policy_bytes);
        // Facts caches (classification, modifier facts) do not read the DEBUG flag: without that byte the game and the
        // test variant, and any other define set, claim the same artifacts.
        policy_bytes.pop();
        facts_policy = xxhash_rust::xxh3::xxh3_128(&policy_bytes);
        Some(compiler)
    } else {
        None
    };
    let mut shared_proofs = None;
    let mut rejected_contents: Vec<(PathBuf, u128)> = Vec::new();
    if command == BuildCommand::Compile && !no_cache {
        let compiler = compiler.expect("configured compiler identity");
        let configuration = runner_configuration::session(
            &project,
            &defines,
            compiler,
            engine_identity,
            bootstrap_catalog,
        )?.with_policy_inputs(policy_inputs.as_ref());
        query_attempt.configure(configuration.clone());
        let configured = dmbc::session::Session::from_locked(
            configuration,
            build_lock.take().expect("compile lock held"),
        )?;
        let store = dmbc::publish::PairStore::open(
            output_store
                .clone()
                .map(Ok)
                .unwrap_or_else(|| dmbc::publish::default_store_path(&project))?,
        )?;
        for id in configured.latest(if verification_capture { 0 } else { 4 })? {
            let _record_timer = progress_enabled.then(|| RecordTimer(id, Instant::now()));
            if let Some(mut validated) = configured
                .validate_filesystem_shared(
                    id,
                    exact_inputs,
                    now_ns(),
                    generated_paths,
                    |record| {
                        if recorded_source_paths.is_empty() {
                            recorded_source_paths = record
                                .inputs
                                .file_paths()
                                .filter(|path| {
                                    path.extension().is_some_and(|extension| {
                                        extension.eq_ignore_ascii_case("dm")
                                    })
                                })
                                .map(Path::to_path_buf)
                                .collect();
                        }
                        if prior_outputs.is_none() {
                            prior_outputs = record
                                .outputs
                                .as_ref()
                                .map(|outputs| std::sync::Arc::new(outputs.clone()));
                        }
                        if resource_prior.is_none() {
                            if let Some(manifest) = &record.resource_manifest {
                                resource_prior =
                                    Some((record.pair, std::sync::Arc::new(manifest.clone())));
                            }
                        }
                    },
                    &mut shared_proofs,
                    &mut rejected_contents,
                )?
            {
                let pair_verification_started = Instant::now();
                if let Ok(pair) = store.verify(validated.record().pair, exact_inputs) {
                    // The patch base describes the last image this session built. A stored record that serves another image
                    // (an edit was reverted, or an earlier state came back) must not be answered as a hit while that base
                    // stays behind: every later edit would be compared with the wrong build and fall off the patch path. Leave
                    // this record and let the patch path take the change; its result becomes the new base.
                    if let Some(base_image) = host.patch_base_image_hash().filter(|base| *base != pair.dmb_hash) {
                        dmbc::daemon_eprintln!(
                            "native session hit skipped: stored image {:032x} differs from the patch base image {:032x}; patching from the base",
                            pair.dmb_hash,
                            base_image
                        );
                        // Every older record is for an image the base does not describe either; validating them is wasted time.
                        break;
                    }
                    let pair_verification_seconds =
                        pair_verification_started.elapsed().as_secs_f64();
                    let output_validation_started = Instant::now();
                    let (outputs_match, output_rehashes) = validated.refresh_outputs_at(
                        &output_project,
                        &dmbc::input_snapshot::FileSystemInputs,
                        exact_inputs,
                        now_ns(),
                    )?;
                    runner_freshness::admit_live(&validated.record().inputs, generated_paths)?;
                    dmbc::daemon::control::begin_publication()?;
                    if !outputs_match {
                        store.install_exact(
                            pair.id,
                            &output_project.with_extension("dmb"),
                            &output_project.with_extension("rsc"),
                            &output_project.with_extension("dmb-pair.json"),
                            exact_inputs,
                        )?;
                    }
                    runner_report::replay_warnings(&validated.record().warnings)?;
                    if progress_enabled {
                        let timing = &validated.timings;
                        dmbc::daemon_eprintln!("native session validation: record={:.3}s bulk_capture={:.3}s input_validate={:.3}s pair={:.3}s outputs={:.3}s proofs={:?}", timing.record_decode.as_secs_f64(), timing.bulk_capture.as_secs_f64(), timing.input_validate.as_secs_f64(), pair_verification_seconds, output_validation_started.elapsed().as_secs_f64(), timing.proofs);
                    }
                    query_attempt.admit_published_replay(
                        &validated.record().inputs,
                        engine_bytes.as_deref().unwrap_or_default(),
                        host.query_tree(),
                    );
                    let rehashed = validated.validation.rehashed;
                    if validated.validation.rehashed > 0 || output_rehashes > 0 || !outputs_match {
                        let mut record = validated.into_record();
                        if !outputs_match {
                            let mut outputs = dmbc::input_snapshot::InputSnapshot::new(now_ns());
                            for extension in ["dmb", "rsc", "dmb-pair.json"] {
                                output_digest::capture_output_digest(
                                    &mut outputs,
                                    &output_project.with_extension(extension),
                                )?;
                            }
                            record.outputs = Some(outputs);
                        }
                        configured.store(record)?;
                    }
                    dmbc::compile_stats::note_hit();
                    dmbc::daemon_eprintln!(
                        "native session hit: total={:.3}s rehashed={} pair={}",
                        total.elapsed().as_secs_f64(),
                        rehashed,
                        pair.name()
                    );
                    let _ = dmbc::telemetry::save(
                        &project,
                        "last-run",
                        &serde_json::json!({"session_hit":true,"seconds":total.elapsed().as_secs_f64(),"rehashed":rehashed,"pair":pair.name()}),
                    );
                    let store_path = std::fs::canonicalize(store.root_path())?;
                    query_attempt.finish_published(&pair);
                    return Ok(BuildOutcome::Published {
                        publication_proof: None,
                        pair,
                        store: store_path,
                        output_project,
                        session_hit: true,
                        seconds: total.elapsed().as_secs_f64(),
                    });
                }
            }
        }
        session = Some(configured);
        pair_store = Some(store);
    }
    if retains_query_owners && dmbc::fs_watch::enabled() {
        let (hits, misses) = dmbc::fs_watch::counters();
        dmbc::daemon_eprintln!("native fs watch: directory proofs cached={hits} captured={misses}");
    }
    stamped_provider.adopt(shared_proofs.clone());
    drop(session_profile);
    dm_profile::detail_mark("session_validation", total);
    let engine_profile = dm_profile::stage("engine_capture");
    let engine_capture_started=Instant::now();
    if progress_enabled { dmbc::daemon_eprintln!("native stage request.engine_capture: started"); }
    // An authenticated unchanged session needs no decoded engine or bootstrap
    // catalog. The key above pins exact engine bytes and this compiler/policy.
    let engine_capture = engine_bytes
        .map(|bytes| host.engine_with_context(project.clone(),defines.clone(),bootstrap_catalog,bytes,analysis_context))
        .transpose()?;
    if progress_enabled { dmbc::daemon_eprintln!("native stage request.engine_capture: {:.3}s",engine_capture_started.elapsed().as_secs_f64()); }
    if engine_capture.is_none() {
        host.clear_regions();
    }
    query_attempt.bind_current_variant(host.query_state())?;
    if command == BuildCommand::Compile && source_override.is_none()
        && matches!(&input_provider, dmbc::frozen_inputs::Inputs::Live)
    {
        if let Some(source) = host.retained_original_decoded_sources(&project) {
            inputs_capture.offer_prior_original_text(source);
        }
    }
    // The variant's stored patch base (`dmbc::variant_spill`): this cache root's spill directory and this project, defines
    // and compiler policy's file.
    let spill_target = (executable && !no_cache && dmbc::variant_spill::enabled())
        .then(|| cache_root.clone().map_or_else(dm_cache::Cache::default_root, Ok).ok())
        .flatten()
        .map(|root| {
            (
                dmbc::variant_spill::directory(&root),
                dmbc::variant_spill::key(&project, &defines, memo_policy),
            )
        });
    let memo_cache = if executable && !no_cache {
        match cache_root.map_or_else(dm_cache::Cache::default_root, Ok) {
            Ok(root) => Some(Arc::new(dmbc::runner_disk::LazyDisk::new(root))),
            Err(error) => {
                dmbc::daemon_eprintln!("native cache unavailable: {error}; compiling fresh");
                None
            }
        }
    } else {
        None
    };
    let _cache_batch_attempt = memo_cache.as_ref().map(|cache| cache.batch_attempt());
    // The shared handle stays unopened until resident fallback or computed staging.
    let cache_snapshot = memo_cache.clone();
    let cache_publisher: Option<Arc<dmbc::lowering_memo::CachePublisher>> =
        memo_cache.as_ref().map(|cache| {
            let cache = Arc::clone(cache);
            Arc::new(move |records: Vec<dm_cache::Record>| cache.append_records(records))
                as Arc<dmbc::lowering_memo::CachePublisher>
        });
    let procedure_memo = host
        .procedure_memo(memo_policy, facts_policy, cache_snapshot.clone(), publishable_artifacts)
        .map(|memo| {
            let memo = memo.with_explanation_limit(131072).with_facts_policy(facts_policy);
            match &cache_publisher {
                Some(publisher) => memo.with_publisher(Arc::clone(publisher)),
                None => memo,
            }
        });
    let retention_status = host.retention_status();
    let expansion_memo = cache_snapshot.clone().map(|snapshot| {
        let memo = dmbc::expansion_memo::DiskExpansionMemo::with_lazy_disk(memo_policy, snapshot);
        match &cache_publisher {
            Some(publisher) => memo.with_publisher(Arc::clone(publisher)),
            None => memo,
        }
    });
    let map_memo = host
        .map_memo(memo_policy, cache_snapshot.clone(), publishable_artifacts)
        .map(|memo| match &cache_publisher {
            Some(publisher) => memo.with_publisher(Arc::clone(publisher)),
            None => memo,
        });
    let analysis_seed=analysis_context.map(|_|dm_tree::checker_builtins::original_analysis_seed()).transpose().map_err(|error|format!("original analysis catalog: {error:?}"))?;
    let seed = analysis_seed.as_ref().map(|owner|owner.frontend_seed()).or_else(||engine_capture
        .as_ref()
        .map(|capture| capture.frontend_seed()));
    drop(engine_profile);
    dm_profile::detail_mark("engine_capture", total);
    let frontend_context_profile = dm_profile::stage("request.frontend_context");
    let progress = generation_progress;
    // One request-local execution boundary spans input capture, parsing, ABI,
    // lowering and linking. Its Drop joins workers before the CLI profiler ends.
    let generation = if executable {
        host.generation(memo_policy).map(|owner| {
            if let Some((directory, key)) = &spill_target {
                owner.attach_spill(directory.clone(), *key);
            }
            owner.for_request(publishable_artifacts)
        })
    } else {
        None
    };
    let resource_owner = if executable && !verification_capture {
        host.resources()
    } else {
        None
    };
    let resource_configuration = crate::runner_host::resources::Configuration {
        policy: memo_policy,
        project: project.clone(),
        defines: defines.clone(),
        output: output_project.clone(),
        store: output_store.clone(),
        generated: generated_paths.clone(),
    };
    if let Some(hint) = resource_owner
        .as_ref()
        .and_then(|owner| owner.hint(&resource_configuration))
    {
        resource_prior = Some((hint.pair, std::sync::Arc::clone(&hint.manifest)));
        prior_outputs = Some(std::sync::Arc::clone(&hint.outputs));
    }
    let host_facts = if executable { host.host_facts() } else { None };
    let query_db = host.retains_artifacts().then(|| std::sync::Arc::clone(host.query_db()));
    let source_policy_queries = std::sync::Arc::clone(host.query_db());
    let selected_original_anchors =
        analysis_context == Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)
            && preparation_output.needs_combined_checker()
            && analysis_subject.as_ref().is_some_and(|subject| !subject.synthetic());
    let ((frontend_memo, execution, mut semantic_state), declaration_prior) =
        host.execution_with_selected_declaration_loans(
            workers,
            expansion_memo
                .as_ref()
                .map(|memo| memo as &dyn dm_preprocess::regions::ExpansionMemo),
            selected_original_anchors,
            joined.map(JoinedSelectedInputs::strict_profile),
        )?;
    let strict_callable_prior = selected_original_anchors.then_some(declaration_prior).flatten();
    let original_type_prior = joined.is_some().then_some(declaration_prior).flatten();
    // One-shot compilation uses the same named declaration receipt issuer as
    // retained sessions. This owner lasts for this request only: disabling
    // caches must not change which semantic answers the compiler can prove.
    let mut request_semantic = dm_tree::frontend::RetainedSemanticTree::one_shot();
    let semantic_state = semantic_state
        .as_deref_mut()
        .unwrap_or(&mut request_semantic);
    let declaration_request = semantic_state.begin_declaration_request(publishable_artifacts);
    let execution_result = execution.run(|executor| -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    dmbc::daemon::control::checkpoint()?;
    // Existing host/executor admits declarations BEFORE adapter constant folding.
    let settings_host=std::sync::Arc::clone(&source_policy_queries)
        as std::sync::Arc<dyn dm_tree::frontend::SettingExpressionQueries>;
    let input_preparation_seconds;
    let frontend_result = {
        let preparation_start = Instant::now();
        drop(frontend_context_profile);
        dm_profile::detail_mark("frontend_context", total);
        let input_profile = dm_profile::stage("input_scan");
        let mut hints = inputs_capture.previous_prepared_paths();
        if hints.is_empty() {
            hints = std::mem::take(&mut recorded_source_paths);
        }
        if progress_enabled && !hints.is_empty() {
            dmbc::daemon_eprintln!("native input preparation hints: {} previously prepared paths", hints.len());
        }
        let selected_original = analysis_context == Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)
            && preparation_output.is_selected_report();
        let prepared_inputs = if selected_original {
            dmbc::native_inputs::NativeInputs::prepare_selected_original_with_hints(
                &project, &inputs_capture, executor, hints,
            )
        } else {
            dmbc::native_inputs::NativeInputs::prepare_with_hints(
                &project, &inputs_capture, executor, hints,
            )
        };
        let inputs = match prepared_inputs {
            Ok(inputs) => Some(inputs),
            Err(dmbc::native_inputs::NativeInputError::RequiredSourceRead { .. }) => None,
            Err(dmbc::native_inputs::NativeInputError::InternalPreparation { message }) => {
                return Err(dmbc::request_failure::RequestFailure::internal(format!("native internal: {message}")).into())
            }
        };
        input_preparation_seconds = preparation_start.elapsed().as_secs_f64();
        drop(input_profile);
        dm_profile::detail_mark("input_scan", total);
        let source_context_profile = dm_profile::stage("request.source_context");
        if progress_enabled {
            dmbc::daemon_eprintln!(
                "native input preparation: {:.3}s {:?} {}",
                input_preparation_seconds,
                inputs.as_ref().map(|inputs| inputs.stats()),
                dmbc::input_snapshot::prepared::counters::take()
            );
        }
        if let (Some(inputs), Some(query_db)) = (&inputs, &query_db) {
            let _timer = dm_profile::detail_timer("query_db.revise");
            let mut configuration = format!("{project:?} {defines:?} ").into_bytes();
            configuration.extend_from_slice(&memo_policy.to_le_bytes());
            configuration.push(u8::from(bootstrap_catalog));
            configuration.extend_from_slice(if diagnostic_declarations {b"checker-declaration-domain-v1".as_slice()}else{b"strict-declaration-domain-v1".as_slice()});
            if let Some(context)=analysis_context{configuration.extend_from_slice(b"original-analysis-context-v1");configuration.extend_from_slice(&context.initial_environment().profile().to_le_bytes());}
            if analysis_context.is_some(){configuration.extend_from_slice(b"actual-original-primary-preparation");configuration.extend_from_slice(&dm_tree::frontend::ORIGINAL_ANALYZE_PREPARATION_VERSION.to_le_bytes());}
            crate::policy_request::append_identity(&mut configuration, policy_inputs.as_ref())?;
            match query_db.revise(inputs.sources(), dm_query::hash_bytes(&configuration)) {
                Ok(revision) => dmbc::daemon_eprintln!("native query db: {revision:?}"),
                Err(error) => dmbc::daemon_eprintln!("native query db: {error:?}"),
            }
        }
        let inputs = if selected_original { drop(inputs); None } else { inputs };
        let empty = dm_preprocess::regions::prepared_source::PreparedSources::default();
        let provider = match &inputs {
            Some(inputs) => {
                let provider = inputs.provider(&inputs_capture);
                match &query_db {
                    // The frontend asks the database which sources changed since its last plan.
                    Some(db) => provider.with_changes(&**db),
                    None => provider,
                }
            }
            None => dm_preprocess::regions::prepared_source::PreparedSourceProvider::new(
                &empty,
                &inputs_capture,
            ),
        };
        // Only requested captures enter the semantic model. Release unused
        // speculative preparations before maps, resources and lowering begin.
        drop(source_context_profile);
        dm_profile::detail_mark("source_context", total);
        let _frontend_profile = dm_profile::stage("frontend");
        if diagnostic_declarations || analysis_context.is_some() {
            // Select the original builder's diagnostic mode BEFORE construction.
            // Valid graphs transfer the SAME owner; no strict-failure retry.
            // The actual typed input stack is Sync. Lend this SAME recorder to
            // both the calling receiver and producer for the entire Original
            // preparation; never infer Sync through erased generic providers.
            let original_provider=inputs_capture.original_batch_view(query_db.as_deref().map(|db|db as &(dyn dm_preprocess::SourceChanges+Sync)));
            let preparation=if analysis_context==Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290){
                let prepare=if preparation_output.compact_checker_cache().is_some()
                    && preparation_output.needs_combined_checker()
                    && preparation_output.wants_joined_inputs() {
                    dm_tree::frontend::build_for_original_compound_with_callable_anchors_checked
                } else {
                    dm_tree::frontend::build_for_original_analysis_with_callable_anchors_checked
                };
                prepare(&project,&original_provider,&defines,
                    dm_tree::frontend::FrontendConfig{workers,engine:seed,observer:progress_enabled.then_some(&progress)},
                    frontend_memo.as_ref().map(|memo|memo as &dyn dm_preprocess::regions::ExpansionMemo),executor,Some(&mut *semantic_state),&settings_host,strict_callable_prior)
            }else{dm_tree::frontend::build_for_checker_diagnostics_with_state_checked(&project,&provider,&defines,
                dm_tree::frontend::FrontendConfig{workers,engine:seed,observer:progress_enabled.then_some(&progress)},
                frontend_memo.as_ref().map(|memo|memo as &dyn dm_preprocess::regions::ExpansionMemo),executor,Some(&mut *semantic_state),&settings_host)};
            let prepared=match preparation{Ok(frontend)=>frontend,
                Err(dm_tree::frontend::FrontendBuildFailure::Operational(actual))=>{
                // Only the closed real-attempt entry supplies this sink. A
                // private exact failed-root loan, not ErrorKind or None,
                // decides whether the raw-only report can even be attempted.
                if let Some(sink)=handlers_sink.as_deref_mut(){
                    if let Some(failed)=inputs_capture.take_actual_root_open_failure(){
                        if let Some(capture)=handlers_capture.take(){
                            let reported=(||{let proof=runner_freshness::admit_handlers_actual_failed_full(&inputs_capture,Arc::clone(&capture),source_policy_queries.as_ref(),failed)?;
                                source_policy_queries.with_handlers_failed_full_report(&inputs_capture,&capture,&proof,|data,config,budget|{sink.consume_budget(data,config,budget);Ok(())}).map_err(|error|Box::new(error)as Box<dyn std::error::Error>)
                            })();if let Err(error)=reported{sink.failed(match error.downcast::<io::Error>(){Ok(actual)=>*actual,Err(other)=>io::Error::other(other.to_string())})}
                        }
                    }
                }
                if let Some(sink)=derived_sink.as_deref_mut(){
                    if let Some(failed)=inputs_capture.take_actual_root_open_failure(){
                        let reported=source_policy_queries.with_failed_original_derived(&inputs_capture,failed,|data,config,budget|{sink.consume_budget(data,config,budget);Ok(())});
                        if let Err(error)=reported{sink.failed(error)}
                    }
                }
                // The SAME original source error remains the preparation
                // result, irrespective of any later report/callback error.
                return Err(actual.into())
            },
                Err(dm_tree::frontend::FrontendBuildFailure::Diagnostics(mut diagnostics))=>{
                // The strict Original fatal report keeps its actual raw-prefix
                // plan alive; it never needs a fabricated expanded span.
                if let Some(notices)=diagnostics.original_preprocess_notices(){preparation_output.emit(|mut output|dmbc::diagnostics::write_original_preprocess_notices(&mut output,&notices))?;}
                if let Some(legacy)=diagnostics.legacy_mut(){dmbc::diagnostics::refine(legacy);}
                preparation_output.emit(|mut output|dmbc::diagnostics::write_diagnostics(&mut output,&diagnostics))?;
                let kind=dmbc::diagnostics::failure_kind(diagnostics.iter().map(|diagnostic|diagnostic.kind));
                // Return the SAME already-issued source message after printing it;
                // a generic graph-admission message must not replace the actual
                // primary syntax failure on the public/daemon error boundary.
                if diagnostics.is_retained(){return Err(dmbc::diagnostics::retained_preparation_failure(diagnostics,kind,true,"diagnostic preparation did not produce an admitted original declaration graph",source_policy_queries.as_ref())?)}
                let diagnostics=diagnostics.into_legacy().expect("legacy diagnostic representation has no retained output credit");
                let message=if kind==dmbc::request_failure::FailureKind::Source{
                    diagnostics.into_iter().find(|diagnostic|diagnostic.kind.is_source_error()).map(|diagnostic|diagnostic.message)
                        .unwrap_or_else(||"diagnostic preparation did not produce an admitted original declaration graph".into())
                }else{"diagnostic preparation did not produce an admitted original declaration graph".into()};
                return Err(dmbc::request_failure::RequestFailure{kind,message}.into());
            }};
            // Actual raw directive notices may have no emitted expanded token.
            // Present the retained Original owner without a native span or role promotion.
            // A closed integrated report defers this output to its report boundary;
            // standalone preparation still renders its own diagnostic stream.
            if derived_sink.is_none()&&handlers_sink.is_none(){
                if let Some(capture)=handlers_capture.as_ref().filter(|capture|capture.prepared().subject().is_selected_full()){
                    capture.require_bound()?;
                    if let Some(frontend)=capture.prepared().frontend(){
                        let partial=frontend.handlers_structural_source().map_err(io::Error::other)?;
                        if let Some(notices)=partial.view().original_preprocess_notices(){
                            preparation_output.emit(|mut output|dmbc::diagnostics::write_original_preprocess_notices(&mut output,&notices))?;
                        }
                    }
                }
                let view=prepared.source_view()?;
                if let Some(notices)=view.original_preprocess_notices(){
                    preparation_output.emit(|mut output|dmbc::diagnostics::write_original_preprocess_notices(&mut output,&notices))?;
                }
            }
            if analysis_context.is_some(){
                // A genuine analysis purpose stays diagnostic-only even when
                // the original graph has zero declaration errors. No ABI or
                // lowering admission is inferred from that fact.
                let prepared=Arc::new(prepared.with_body_queries(Arc::clone(&source_policy_queries) as Arc<dyn dm_tree::frontend::BodySyntaxQueries>)?);
                let view=prepared.source_view()?;
                let intent=policy_inputs.as_ref().ok_or("analysis purpose requires its actual admitted request")?;
                let mut pending_joined = None;
                if let Some(workspace)=intent.workspace(){
                    let check_grep=intent.workspace_auxiliary().iter().any(|question|matches!(question,crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep|crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrepBaseline));
                    if check_grep&&analysis_subject.is_none(){
                        let root=view.original_plan().occurrences().first().ok_or("analysis actual root occurrence absent")?;
                        let original=view.original_plan().source_texts().get(root.path.as_ref()).ok_or("analysis actual manifest original absent")?;
                        if root.path.file_name()!=Some(std::ffi::OsStr::new("deepquarry.dme")) || !original.as_str().contains("#include") {
                            return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"original Analyze context has no issued synthetic-manifest preparation; actual fixed include environment required").into());
                        }
                    }
                    let contract=crate::runner_host::workspace_discovery::DiscoveryContract{root:workspace.root.clone(),recursive_roots:workspace.recursive_roots.clone()};
                    let discovery=if let Some(subject)=&analysis_subject{subject.bind_frontend(&view)?;Arc::clone(subject.discovery())}else{Arc::new(if check_grep{crate::runner_host::workspace_discovery::discover_check_grep(&inputs_capture,contract)?}else{crate::runner_host::workspace_discovery::discover(&inputs_capture,contract)?})};
                    dm_profile::request_mark("joined.discovery_bound");
                    let joined_header_charge = if preparation_output.needs_combined_checker() && preparation_output.wants_joined_inputs() {
                        Some(crate::runner_host::policy_capture::JoinedHeaderCharge::capture(&view, source_policy_queries.as_ref())?)
                    } else { None };
                    dm_profile::request_mark("joined.header_funding_bound");
                    let capture_checker_policy = || -> Result<_, Box<dyn std::error::Error>> {
                        use crate::policy_request::{AnalysisContext,PolicyInputFile,PolicyInputRequest,PolicyInputRole,WorkspaceAuxiliaryQuestion as Q};
                        let private_combined = private_authored_doc_ui
                            && Q::is_private_authored_checker(intent.workspace_auxiliary());
                        if (!private_combined && !Q::admits_combined_reports(intent.workspace_auxiliary())) ||
                           analysis_subject.as_ref().is_none_or(|subject|subject.synthetic()) ||
                           view.preparation_purpose()!=dm_tree::frontend::DiagnosticPreparationPurpose::OriginalSharedComplete {
                            return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"combined report requires the fixed authored complete Original source and qualified semantic roster").into());
                        }
                        let checker_config=dm_analysis::check_configuration::select(&project,None);
                        let checker_intent=PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),
                            files:vec![PolicyInputFile{path:checker_config.path,role:PolicyInputRole::Configuration,required:false}],
                            ..Default::default()}.admit()?;
                        Ok(Arc::new(crate::runner_host::policy_capture::capture_joined_checker(&view,&inputs_capture,&checker_intent.capture_files(),checker_intent.search_folders(),joined_header_charge.as_ref())?.bind_request(&checker_intent)?.bind_diagnostic_profile()?))
                    };
                    // Full CI baseline observations belong to Analyze. Bind the
                    // Checker policy to the actual shared Original source
                    // before those reads enter the common recorder. Both
                    // captures still enter the same final freshness closure.
                    let early_checker = if preparation_output.needs_full_ci_baselines() {
                        Some(capture_checker_policy()?)
                    } else { None };
                    let captured=if preparation_output.needs_full_ci_baselines(){
                        crate::runner_host::workspace_capture::capture_analysis_full_ci(
                            &view,&inputs_capture,discovery,&workspace.configuration,intent.workspace_auxiliary(),source_policy_queries.as_ref(),
                        )?
                    }else if crate::policy_request::WorkspaceAuxiliaryQuestion::admits_map_edits_capture(intent.workspace_auxiliary()){
                        crate::runner_host::workspace_capture::capture_analysis_map_edits(&view,&inputs_capture,discovery,&workspace.configuration,intent.workspace_auxiliary(),source_policy_queries.as_ref())?
                    }else if preparation_output.needs_library_sites_baseline(){
                        if analysis_context != Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)
                            || analysis_subject.as_ref().is_none_or(|subject|subject.synthetic()) {
                            return Err(io::Error::new(io::ErrorKind::InvalidInput,"library Sites requires its authored Original Analyze subject").into());
                        }
                        crate::runner_host::workspace_capture::capture_analysis_with_library_baseline(
                            &view,&inputs_capture,discovery,&workspace.configuration,intent.workspace_auxiliary(),
                            source_policy_queries.as_ref(),
                        )?
                    }else{
                        crate::runner_host::workspace_capture::capture_analysis_with_auxiliary(&view,&inputs_capture,discovery,&workspace.configuration,intent.workspace_auxiliary())?
                    };
                    dm_profile::request_mark("joined.workspace_capture_done");
                    let checker=if preparation_output.needs_combined_checker(){
                        let checker_policy = match early_checker {
                            Some(policy) => policy,
                            None => capture_checker_policy()?,
                        };
                        let checker_frame=crate::runner_host::query_snapshot::CombinedCheckerFrame::stage(&view,Arc::clone(&source_policy_queries),Arc::clone(&checker_policy),&captured)?;
                        Some((checker_frame,checker_policy))
                    }else{None};
                    dm_profile::request_mark("joined.checker_capture_done");
                    query_attempt.stage_analysis_workspace(&view,Arc::clone(&source_policy_queries),Arc::clone(&captured),workspace,&inputs_capture,intent,joined_header_charge.as_ref())?;
                    dm_profile::request_mark("joined.workspace_policy_staged");
                    let (admission,checker_ready)=if let Some((frame,policy))=checker{
                        let retain_for = preparation_output.wants_joined_inputs().then_some(project.as_path());
                        let (workspace,checker,joined)=runner_freshness::admit_combined_workspace_captured_using(&inputs_capture,&stamped_provider,generated_paths,Arc::clone(&captured),policy,source_policy_queries.as_ref(),retain_for)?;
                        pending_joined = joined;
                        (workspace,Some((frame,checker)))
                    }else if intent.workspace_generators().is_empty(){
                        (runner_freshness::admit_workspace_captured_using(&inputs_capture,None,&stamped_provider,generated_paths,Arc::clone(&captured),source_policy_queries.as_ref())?.1,None)
                    }else{
                        (runner_freshness::admit_generator_workspace_captured_using(&inputs_capture,None,&stamped_provider,generated_paths,Arc::clone(&captured),intent,source_policy_queries.as_ref())?,None)
                    };
                    dm_profile::request_mark("joined.workspace_freshness_bound");
                    input_provider.finish()?;inputs_capture.finish_prepared()?;dmbc::daemon::control::checkpoint()?;
                    if let Some((frame,proof))=checker_ready{
                        let compact_cache=preparation_output.compact_checker_cache();
                        preparation_output.emit_combined_checker(|stage|frame.write(proof,&project,compact_cache,stage))?;
                    }
                    semantic_state.remember_analysis_frontend(&project,&defines,Arc::clone(&prepared))?;
                    query_attempt.admit_workspace_policy(admission)?;
                }else{
                    let captured=Arc::new(crate::runner_host::policy_capture::capture_diagnostic(&view,&inputs_capture,&intent.capture_files(),intent.search_folders())?.bind_request(intent)?.bind_diagnostic_profile()?);
                    query_attempt.stage_diagnostic(&view,Arc::clone(&source_policy_queries),Arc::clone(&captured))?;
                    let admission=runner_freshness::admit_diagnostic_captured_using(&inputs_capture,None,&stamped_provider,generated_paths,captured,source_policy_queries.as_ref())?.1;
                    input_provider.finish()?;inputs_capture.finish_prepared()?;dmbc::daemon::control::checkpoint()?;
                    semantic_state.remember_analysis_frontend(&project,&defines,Arc::clone(&prepared))?;
                    query_attempt.admit_diagnostic_policy(admission)?;
                }
                if let Some(capture)=handlers_capture.take(){
                    let selected=capture.prepared().subject().is_selected_full();
                    let partial_source_revision=if selected{None}else{capture.partial_revision()?.map(|revision|format!("{revision:032x}"))};
                    let proof=runner_freshness::admit_handlers_captured_using(&inputs_capture,None,&input_provider,generated_paths,Arc::clone(&capture),source_policy_queries.as_ref())?.1.into_shared()?;
                    let query=query_attempt.admit_handlers_source(intent,capture,proof,Arc::clone(&source_policy_queries))?;
                    if !selected {
                        query_attempt.finish_handlers_source();
                        return Ok(BuildOutcome::HandlersQueryPrepared{query_revision:format!("{query:032x}"),partial_source_revision,full_source_revision:Some(format!("{:032x}",view.source_revision())),retained:retains_query_owners});
                    }
                    // The selected result uses this attempt's actual full
                    // pins, now with its actual current handler child bound.

                }
                let outcome=BuildOutcome::QueryPrepared{semantic_revision:format!("{:032x}",view.tree().identity()),source_revision:format!("{:032x}",view.source_revision()),policy_revision:query_attempt.policy_revision().map(|pin|format!("{pin:032x}")),retained:retains_query_owners};
                if let Some(joined) = pending_joined {
                    preparation_output.record_joined_inputs(Some(joined.finish(inputs_capture)?));
                }
                query_attempt.finish_analyzed();return Ok(outcome);
            }
            match prepared.try_into_compilable_retained(&mut *semantic_state){
                Ok(frontend)=>Ok(frontend),
                Err(prepared)=>{
                    if prepared.source_view()?.receipt().errors().is_empty(){return Err(std::io::Error::other("valid diagnostic program lacks complete original retained records; reuse unsupported").into());}
                    let prepared=prepared.with_body_queries(std::sync::Arc::clone(&source_policy_queries) as std::sync::Arc<dyn dm_tree::frontend::BodySyntaxQueries>)?;
                    let view=prepared.source_view()?;
                    let intent=policy_inputs.as_ref().ok_or("diagnostic preparation requires explicit policy input contract")?;
                    let captured=std::sync::Arc::new(crate::runner_host::policy_capture::capture_diagnostic(&view,&inputs_capture,&intent.capture_files(),intent.search_folders())?.bind_request(intent)?.bind_diagnostic_profile()?);
                    query_attempt.stage_diagnostic(&view,std::sync::Arc::clone(&source_policy_queries),std::sync::Arc::clone(&captured))?;
                    // The staged frame is invisible to all queries and cache
                    // reads until the COMPLETE original input closure passes.
                    let staged=query_attempt.pending_diagnostic_policy().ok_or("diagnostic original staged capture unavailable")?;
                    let admission=runner_freshness::admit_diagnostic_captured_using(&inputs_capture,None,&stamped_provider,generated_paths,staged,source_policy_queries.as_ref())?.1;
                    input_provider.finish()?;
                    inputs_capture.finish_prepared()?;
                    dmbc::daemon::control::checkpoint()?;
                    query_attempt.admit_diagnostic_policy(admission)?;
                    let outcome=BuildOutcome::QueryPrepared{semantic_revision:format!("{:032x}",view.tree().identity()),source_revision:format!("{:032x}",view.source_revision()),policy_revision:query_attempt.policy_revision().map(|pin|format!("{pin:032x}")),retained:retains_query_owners};
                    query_attempt.finish_analyzed();
                    return Ok(outcome);
                }
            }
        }else{
        dm_tree::frontend::build_with_executor_and_semantic_state_with_original_types(
            &project,
            &provider,
            &defines,
            dm_tree::frontend::FrontendConfig {
                workers,
                engine: seed,
                observer: progress_enabled.then_some(&progress),
            },
            frontend_memo
                .as_ref()
                .map(|memo| memo as &dyn dm_preprocess::regions::ExpansionMemo),
            executor,
            Some(&mut *semantic_state),
            policy_inputs.as_ref().is_some_and(|request| request.workspace().is_none() || !request.workspace_generators().is_empty() || request.workspace_auxiliary().iter().any(|question|matches!(question,crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep|crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrepBaseline))) || std::env::var_os("DMB_UNIFIED_ANALYSIS").is_some(),
            &settings_host,
            original_type_prior,
        )
        }
    };
    if frontend_result.is_ok() && progress_enabled {
        if let Some(prior) = original_type_prior {
            let reused = semantic_state.shared_original_authored_type_owners(prior, &project);
            dmbc::daemon_eprintln!("native compound shared authored type owners: {reused}");
        }
    }
    dm_profile::detail_mark("frontend", total);
    let frontend_handoff_profile = dm_profile::stage("request.frontend_handoff");
    dmbc::daemon::control::checkpoint()?;
    let frontend = dm_tree::frontend::FrontendRevision::new(match frontend_result {
        Ok(frontend) => {
            // Migration opt-in until all checker/lint parity and memory gates
            // pass. Compile-only users keep the existing lazy body path.
            if policy_inputs.as_ref().is_some_and(|request| request.workspace().is_none() || !request.workspace_generators().is_empty() || request.workspace_auxiliary().iter().any(|question|matches!(question,crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep|crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrepBaseline))) || std::env::var_os("DMB_UNIFIED_ANALYSIS").is_some() {
                match query_db.as_ref() {
                    Some(db) => frontend.with_body_queries(Arc::clone(db) as Arc<dyn dm_tree::frontend::BodySyntaxQueries>),
                    None => frontend,
                }
            } else { frontend }
        },
        Err(dm_tree::frontend::FrontendBuildFailure::Operational(actual)) => return Err(actual.into()),
        Err(dm_tree::frontend::FrontendBuildFailure::Diagnostics(mut diagnostics)) => {
            if let Some(legacy)=diagnostics.legacy_mut(){dmbc::diagnostics::refine(legacy);}
            preparation_output.emit(|mut output|dmbc::diagnostics::write_diagnostics(&mut output, &diagnostics))?;
            let kind = dmbc::diagnostics::failure_kind(diagnostics.iter().map(|diagnostic| diagnostic.kind));
            // Source errors are fully reported above and by the summary line.
            let message = if kind == dmbc::request_failure::FailureKind::Source { "" } else { "source analysis did not produce a complete declaration model" };
            if diagnostics.is_retained(){return Err(dmbc::diagnostics::retained_preparation_failure(diagnostics,kind,false,message,source_policy_queries.as_ref())?)}
            let failure = dmbc::request_failure::RequestFailure {
                kind,
                message: message.into(),
            };
            return Err(failure.into());
        }
    });
    owner_observation::emit("frontend",&frontend,source_policy_queries.as_ref(),&*semantic_state);
    dm_profile::request_mark("frontend.revision");
    if retains_query_owners {
        // The next request adopts this revision's unchanged include subtrees and regions.
        let _timer = dm_profile::detail_timer("frontend.remember");
        semantic_state.remember_frontend(&project, &defines, frontend.clone());
    }
    if progress_enabled {
        dmbc::daemon_eprintln!("native directive lookups: {}", crate::runner_host::memo_lookups_report());
    }
    // Opt-in migration: empty explicit lists capture only compiled raw views.
    // The helper can accept host-requested extra paths once admission exposes
    // them; this does not crawl or claim complete workspace coverage.
    if let Some(workspace) = policy_inputs.as_ref().and_then(|request| request.workspace()) {
        let discovery_started=Instant::now();
        if progress_enabled { dmbc::daemon_eprintln!("native stage workspace.discovery: started"); }
        dm_profile::request_mark("workspace.discovery.start");
        let contract=crate::runner_host::workspace_discovery::DiscoveryContract{root:workspace.root.clone(),recursive_roots:workspace.recursive_roots.clone()};
        let check_grep=policy_inputs.as_ref().is_some_and(|request|request.workspace_auxiliary().iter().any(|question|matches!(question,crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep|crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrepBaseline)));
        let discovery=std::sync::Arc::new(if check_grep{crate::runner_host::workspace_discovery::discover_check_grep(&inputs_capture,contract)?}else{crate::runner_host::workspace_discovery::discover(&inputs_capture,contract)?});
        if progress_enabled { dmbc::daemon_eprintln!("native stage workspace.discovery: {:.3}s sources={} directories={}",discovery_started.elapsed().as_secs_f64(),discovery.files().len(),discovery.directory_paths().count()); }
        dm_profile::request_mark("workspace.discovery.done");
        let capture_started=Instant::now();
        if progress_enabled { dmbc::daemon_eprintln!("native stage workspace.original_capture: started"); }
        dm_profile::request_mark("workspace.capture.start");
        let captured = crate::runner_host::workspace_capture::capture_with_auxiliary(&frontend, &inputs_capture, discovery, &workspace.configuration,policy_inputs.as_ref().expect("actual admitted workspace intent").workspace_auxiliary())?;
        if progress_enabled { dmbc::daemon_eprintln!("native stage workspace.original_capture: {:.3}s sources={}",capture_started.elapsed().as_secs_f64(),captured.file_count()); }
        dm_profile::request_mark("workspace.capture.done");
        let frame_started=Instant::now();
        if progress_enabled { dmbc::daemon_eprintln!("native stage workspace.frame_staging: started"); }
        if policy_inputs.as_ref().is_some_and(|intent|!intent.workspace_generators().is_empty()){
            query_attempt.capture_with_workspace_generator_recorded_sources(&frontend,std::sync::Arc::clone(&source_policy_queries),captured,workspace,&inputs_capture,policy_inputs.as_ref().expect("actual generator intent"))?;
        }else{
        query_attempt.capture_with_workspace_recorded_sources(&frontend, std::sync::Arc::clone(&source_policy_queries), captured, workspace, &inputs_capture)?;
        }
        if progress_enabled { dmbc::daemon_eprintln!("native stage workspace.frame_staging: {:.3}s",frame_started.elapsed().as_secs_f64()); }
        dm_profile::request_mark("workspace.frame_staged");
    } else {
    let raw_policy = if let Some(request) = policy_inputs.as_ref() {
        let files = request.capture_files();
        let captured = crate::runner_host::policy_capture::capture(&frontend, &inputs_capture, &files, request.search_folders())?.bind_request(request)?;
        if !captured.facts().same_recorded_facts(&inputs_capture.snapshot()?) {
            return Err(std::io::Error::other("raw policy ledger changed before source snapshot").into());
        }
        Some(std::sync::Arc::new(captured))
    } else { None };
    query_attempt.capture_with_recorded_sources(&frontend, std::sync::Arc::clone(&source_policy_queries), raw_policy, &inputs_capture)?;
    }
    if let Some(questions)=source_questions.as_deref(){ query_attempt.require_source_questions(questions)?; }
    dm_profile::request_mark("frontend.query_capture");
    dmbc::heap_census::emit_if_enabled("input_source_originals.current",|census|census.exceptional_source_inputs(&inputs_capture))?;
    if command == BuildCommand::Compile {
        // DreamMaker rejects these; the native pipeline would accept them.
        let source_errors = dmbc::source_checks::check(&frontend);
        if !source_errors.is_empty() {
            preparation_output.emit(|mut output|dmbc::diagnostics::write_diagnostics(&mut output, &source_errors))?;
            preparation_output.emit(|mut output|dmbc::diagnostics::write_local_warnings(&mut output, &frontend))?;
            return Err(dmbc::request_failure::RequestFailure::source("").into());
        }
        dm_profile::request_mark("frontend.source_checks");
        // Source inputs the retained output is compared with (`dmbc::retained_output`): the
        // program text outside bodies, positions and per-body digests of this frontend.
        let patch_shape = generation
            .as_ref()
            .filter(|_| !verification_capture)
            .map(|_| Arc::new(dmbc::retained_output::SourceShape::capture(&frontend, executor)));
        dm_profile::request_mark("patch.source_shape");
        let mut frontend_report = runner_report::FrontendReport::capture(&frontend);
        frontend_report.capture_metadata(Some(&*semantic_state));
        let retained_engine = engine_capture
            .as_ref()
            .ok_or("compile requires captured engine")?;
        let bytes = &retained_engine.bytes;
        let engine = &retained_engine.snapshot;
        crate::runner_retained_census::emit_frontend(&frontend, Some(&*semantic_state),
            frontend_memo.as_ref().map(|memo| memo as &dyn dm_preprocess::regions::ExpansionMemo),
            prepared_sources.as_deref(),
        )?;
        crate::runner_retained_census::emit(Some(&*semantic_state))?;
        if progress_enabled {
            dmbc::daemon_eprintln!(
                "native captured facts started: {} types, {} members, {} bodies",
                frontend.snapshot.tree.types().len(),
                frontend.snapshot.tree.members().len(),
                frontend.bodies.len()
            );
        }
        let facts_started = Instant::now();
        drop(frontend_handoff_profile);
        dm_profile::detail_mark("frontend_handoff", total);
        let facts_profile = dm_profile::stage("captured_facts");
        let (host, scalar) = match runner_facts::prepare_retained_original(&frontend, retained_engine, host_facts.as_deref()) {
            Ok(prepared)=>prepared,
            Err(runner_facts::HostPreparationFailure::Operational(actual))=>return Err(actual.into()),
            Err(runner_facts::HostPreparationFailure::Source(source))=>return Err(source.into()),
            Err(runner_facts::HostPreparationFailure::Policy(message))=>return Err(message.into()),
        };
        let defaults = dmbc::compile_driver::map_defaults(&scalar)?;
        drop(scalar);
        dmbc::heap_census::emit_if_enabled("captured_facts.ready", |census| {
            census.frontend(&frontend);
            host.census(census);
        })?;
        let facts_seconds = facts_started.elapsed().as_secs_f64();
        drop(facts_profile);
        dm_profile::detail_mark("captured_facts", total);
        let nontext_context_profile = dm_profile::stage("request.nontext_context");
        let nontext_started = Instant::now();
        drop(nontext_context_profile);
        let nontext_profile = dm_profile::stage("resources_maps");
        dmbc::daemon::control::checkpoint()?;
        if progress_enabled {
            dmbc::daemon_eprintln!("native resources and maps started");
        }
        let captured_engine = byond_dmb::dmb::Dmb::from_bytes(bytes)?;
        // Output storage is independent of compiler memo policy. Failure here
        // disables this memory optimization; publication still reports the
        // ordinary output error after all source/semantic diagnostics succeed.
        if pair_store.is_none() {
            if let Ok(path) = output_store
                .clone()
                .map(Ok)
                .unwrap_or_else(|| dmbc::publish::default_store_path(&project))
            {
                pair_store = dmbc::publish::PairStore::open(path).ok();
            }
        }
        let resource_destination = output_project.with_extension("rsc");
        let resource_sink = pair_store.as_ref().map(|store| OutputResourceSink {
            store,
            exact: exact_inputs,
            destination: &resource_destination,
            outputs: &resource_outputs,
        });
        let roots = retained_engine
            .frontend_seed()
            .hierarchy
            .parents
            .iter()
            .map(|(id, _)| *id)
            .collect();
        let capture_observer = |measurement: dmbc::captured_non_text_driver::CaptureMeasurement| {
            if progress_enabled {
                dmbc::daemon_eprintln!(
                    "native nontext {:?}: {:.3}s success={}",
                    measurement.stage, measurement.seconds, measurement.succeeded
                );
            }
        };
        let admit_resources = |demand: &dm_resources::capture::ResourceDemand| {
            let Some((_prior_pair, manifest)) = resource_prior.as_ref() else {
                return Ok(None);
            };
            let Some(store) = pair_store.as_ref() else {
                return Ok(None);
            };
            let proof_started = std::time::Instant::now();
            let proof_profile = dm_profile::stage("resources.filesystem_proofs");
            // The directory proofs session validation captured at the start of this request already
            // cover the previous build's inputs, resource files included (paths outside them fall back
            // to live handling inside the proofs). Publication restats every captured input live, so
            // a file that moves between that capture and now still rebuilds.
            let raw_proofs = match &shared_proofs {
                Some(shared) => std::sync::Arc::clone(shared),
                None => std::sync::Arc::new(
                    manifest.filesystem_proofs().map_err(|error| error.to_string())?,
                ),
            };
            let proofs = dmbc::input_snapshot::GeneratedOutputInputs::new(&*raw_proofs, generated_paths.iter().cloned());
            drop(proof_profile);
            dmbc::daemon_eprintln!(
                "native resource FilesystemProofCapture: {:.3}s",
                proof_started.elapsed().as_secs_f64()
            );
            let observer = |measurement: dmbc::resource_manifest::ResourceValidationMeasurement| {
                dmbc::daemon_eprintln!(
                    "native resource {:?}: {:.3}s",
                    measurement.stage, measurement.seconds
                );
            };
            manifest
                .validate_observed(
                    memo_policy,
                    demand,
                    &proofs,
                    dmbc::resource_manifest::ObservedValidation {
                        exact: exact_inputs,
                        now: now_ns(),
                    },
                    |identity| {
                        match store.verify_resource_pinned(identity, exact_inputs) {
                            Ok(pin) => {
                                resource_outputs
                                    .lock()
                                    .unwrap_or_else(|error| error.into_inner())
                                    .pins
                                    .push(pin);
                                Ok(true)
                            }
                            Err(_) => Ok(false),
                        }
                    },
                    Some(&observer),
                )
                .map_err(|error| error.to_string())
        };
        let resource_journal_admission = std::sync::Mutex::new(None);
        let capture_resource_evidence = |demand: &dm_resources::capture::ResourceDemand,
            resources: &dm_resources::capture::CapturedResources, extra: &dmbc::assets::ExtraAssets| {
            let policy = dm_resources::encoding::byond516_raw_policy();
            let receipt = dmbc::resource_journal_coverage::admit_recorded_demand(
                &input_provider, demand, resources,
                dm_resources::capture::CaptureConfig { policy: &policy,
                    encoded: &extra.encoded_skins, additional: &extra.skins },
                dmbc::resource_journal_coverage::CoverageLimits {
                    candidate_reads: 262_144, source_payload_bytes: 512 * 1024 * 1024,
                },
            );
            *resource_journal_admission.lock().unwrap_or_else(|error| error.into_inner()) = Some(receipt);
        };
        let mut nontext =
            dmbc::captured_non_text_driver::capture_with_resource_reuse_on_executor_with_sink_and_evidence(
                &frontend,
                &inputs_capture,
                &inputs_capture,
                host,
                &captured_engine,
                &roots,
                &defaults,
                Some(&capture_observer),
                map_memo.as_ref(),
                Some(&admit_resources),
                executor,
                resource_sink
                    .as_ref()
                    .map(|sink| sink as &dyn dmbc::assets::ResourceArchiveSink),
                verification_capture.then_some(&capture_resource_evidence
                    as dmbc::captured_non_text_driver::ResourceCaptureEvidence<'_>),
            )?
            .into_prepared(&frontend)?;
        // Only this one-shot request discards expansion execution inputs. No
        // revision issuance exists yet; shared revisions retain their full plan.
        let frontend = frontend.try_into_compile_only().unwrap_or_else(|full| full);
        // Nontext capture owns the resolver, captured resources/maps and defaults
        // it needs. These inputs are not borrowed by its returned bundle.
        drop(defaults);
        drop(roots);
        drop(captured_engine);
        let nontext_seconds = nontext_started.elapsed().as_secs_f64();
        drop(nontext_profile);
        dm_profile::detail_mark("resources_maps", total);
        let linking_inputs_started = Instant::now();
        let linking_inputs_profile = dm_profile::stage("linking_inputs");
        let mut links = retained_engine.link_overlay()?;
        nontext.extend_inventory(&mut links.inventory)?;
        let artifacts = std::mem::take(&mut nontext.artifacts);
        let linking_inputs_seconds = linking_inputs_started.elapsed().as_secs_f64();
        drop(linking_inputs_profile);
        dm_profile::detail_mark("linking_inputs", total);
        let compilation_profile = dm_profile::stage("request.compilation");
        let compilation_started = Instant::now();
        if progress_enabled {
            dmbc::daemon_eprintln!("native compilation started");
        }
        let cold_observer = |measurement: dmbc::cold::ColdMeasurement| {
            dmbc::daemon_eprintln!(
                "native cold {:?}: {:.3}s success={:?}",
                measurement.stage,
                measurement.elapsed.as_secs_f64(),
                measurement.succeeded
            );
        };
        // One immutable captured host for this compile. Consumer read recording
        // remains outside this optimization, including on memo hits.
        dmbc::daemon::control::checkpoint()?;
        // Every input is captured now; prove freshness while compilation runs.
        let snapshot_memo = runner_freshness::SnapshotMemo::default();
        let early_admission = match snapshot_memo.get_using(&inputs_capture, nontext.retained_resource_inputs(),source_policy_queries.as_ref()) {
            Ok(inputs) if source_override.is_none() => Some(runner_freshness::EarlyAdmission::start(inputs, &input_provider, generated_paths)),
            Ok(_) => None,
            Err(error) => {
                dmbc::daemon_eprintln!("native early admission skipped: {error}");
                None
            }
        };
        dm_profile::request_mark("patch.early_admission_started");
        if generation.is_none() {
            dmbc::compile_stats::note_full("no retained generation (cold session)");
        }
        dm_profile::request_mark("patch.attempted");
        // An incremental output claims nothing it reused in the procedure memo;
        // publishing its request lease would replace (evict) every resident record.
        let incremental = std::cell::Cell::new(false);
        let compile_result = { (|| {
            let values = dmbc::type_values::CapturedTypeValues::pinned(&frontend, engine)
                .map_err(dmbc::cold::ColdError::RuntimeTypeValues)?;
            let values = dmbc::resource_values::CapturedResourceValues::new(
                &values,
                &nontext.resolver,
                nontext.resource_search_context,
            );
            let compilation_resolver = dm_ir::MemoResolver::new(
                &nontext.resolver,
                std::env::var("DMB_RESOLVER_MEMO_ENTRIES")
                    .ok()
                    .and_then(|value| value.parse().ok())
                    // A full compile asks about 4.2M queries, 0.9M of them distinct. At the old 64k budget 88 % of the
                    // asks missed, and replaying cached procedures re-resolved their reads (41 CPU-s on a fresh
                    // session); 2M entries retain every distinct answer (about 80 MB for the request).
                    .unwrap_or(2_097_152),
            );
            // The retained output this request may build on incrementally.
            let retained = match (&generation, &patch_shape) {
                (Some(generation), Some(shape)) => snapshot_memo
                    .get_using(&inputs_capture, nontext.retained_resource_inputs(),source_policy_queries.as_ref())
                    .ok()
                    .map(|inputs| dmbc::retained_output::RetainedOutput {
                        generation,
                        shape,
                        inputs,
                        archive: nontext.archive_identity(),
                    }),
                _ => None,
            };
            let prepared = dmbc::compile_driver::prepare_original_revision_observed_with_memo_on_executor(
                &frontend,
                &compilation_resolver,
                engine,
                bytes,
                links,
                &values,
                Some(nontext.resource_search_context),
                artifacts,
                Some(nontext.stage()),
                executor,
                progress_enabled.then_some(&cold_observer),
                procedure_memo.as_ref(),
                retained,
            )?;
            let mut prepared = match prepared {
                dmbc::cold::Prepared::Full(prepared) => prepared,
                dmbc::cold::Prepared::Incremental(patched) => {
                    incremental.set(true);
                    dmbc::retained_output::note_applied(&project);
                    drop(compilation_resolver);
                    let (resolver, _stage, publication) = nontext.into_composition_parts();
                    let patched = *patched;
                    let (abi, startup) = patched.query;
                    query_attempt
                        .capture_resolved_host(&frontend, resolver, abi, startup)
                        .map_err(|error| dmbc::cold::ColdError::InitializerInvariant(format!("query host capture: {error}")))?;
                    let explanations = runner_report::explanations(&frontend, None);
                    owner_observation::emit("compiled_source",&frontend,source_policy_queries.as_ref(),&*semantic_state);
                    drop(frontend);
                    return Ok::<_, dmbc::cold::ColdError>((
                        dmbc::cold::ColdOutput {
                            dmb: patched.dmb,
                            timings: Default::default(),
                            warnings: patched.warnings,
                            startup: None,
                        },
                        publication,
                        explanations,
                        None,
                    ));
                }
            };
            dm_profile::request_mark("compilation.prepared");
            if progress_enabled {
                dmbc::daemon_eprintln!("native resolver memo: {:?}", compilation_resolver.stats());
            }
            let explanations = runner_report::explanations(&frontend, procedure_memo.as_ref());
            let owned_values = Arc::new(
                dmbc::resource_values::PreparedResourceValues::capture(&values, &prepared.domains())
                    .with_project_name(&project),
            );
            // Opt-in live request boundary: the memo is not a retained host
            // owner. Shared declaration payloads deduplicate against frontend;
            // private memo table backing remains explicitly unknown.
            dmbc::heap_census::emit_if_enabled("request_resolver_memo.before_drop", |census| {
                census.frontend(&frontend);
                census.resolver_memo(&compilation_resolver);
            }).map_err(|error| dmbc::cold::ColdError::InitializerInvariant(
                format!("request resolver memo census: {error}")))?;
            drop(compilation_resolver);
            let (resolver, output_stage, publication) = nontext.into_composition_parts();
            let query_owners = prepared.query_owners();
            if let Some((abi,startup)) = query_owners {
                query_attempt.capture_resolved_host(&frontend,resolver,abi,startup)
                    .map_err(|error|dmbc::cold::ColdError::InitializerInvariant(format!("query host capture: {error}")))?;
            } else { drop(resolver); }

            let patch_records = patch_shape.as_ref().and_then(|_| prepared.take_patch_records());
            let composition = prepared.seal(
                &frontend,
                Arc::clone(bytes),
                owned_values,
                Some(Box::new(output_stage)),
            )?;
            dm_profile::request_mark("compilation.sealed");
            // The sealed composition retains exact output facts and no source owners.
            owner_observation::emit("compiled_source",&frontend,source_policy_queries.as_ref(),&*semantic_state);
            drop(frontend);
            dm_profile::request_mark("compilation.frontend_dropped");
            let output =
                composition.compose_with_generation(executor, progress_enabled.then_some(&cold_observer), generation.as_deref())?;
            Ok::<_, dmbc::cold::ColdError>((output, publication, explanations, patch_records))
        })() };
        if progress_enabled && compile_result.is_err() {
            dmbc::daemon_eprintln!("native failed stages: input_preparation={:.3}s frontend={:.3}s captured_facts={:.3}s resources_maps={:.3}s linking_inputs={:.3}s compilation={:.3}s total={:.3}s",
                input_preparation_seconds, frontend_report.frontend_seconds, facts_seconds, nontext_seconds,
                linking_inputs_seconds, compilation_started.elapsed().as_secs_f64(),
                total.elapsed().as_secs_f64());
        }
        let built_on_retained = incremental.get();
        let (output, publication, explanations, patch_records) = match compile_result {
            Ok(output) => output,
            Err(dmbc::cold::ColdError::Lowering(diagnostics)) => {
                dmbc::diagnostics::write_lowering_diagnostics(
                    &mut dmbc::daemon::stderr_writer(),
                    &diagnostics,
                )?;
                let kind = dmbc::diagnostics::failure_kind(diagnostics.iter().map(|diagnostic| diagnostic.kind));
                // Source errors are fully reported above and by the summary line.
                let message = if kind == dmbc::request_failure::FailureKind::Source { "" } else { "native lowering did not produce a complete executable" };
                let failure = dmbc::request_failure::RequestFailure {
                    kind,
                    message: message.into(),
                };
                return Err(failure.into());
            }
            Err(dmbc::cold::ColdError::Composition(dmbc::composition::CompositionError::SourceError(diagnostic))) => return Err(dmbc::diagnostics::report_source_error(diagnostic)?.into()),
            Err(dmbc::cold::ColdError::InitializerInvariant(message)) => {
                return Err(dmbc::request_failure::RequestFailure::internal(format!("native internal: {message}")).into())
            }
            Err(dmbc::cold::ColdError::Initializer(message)) => {
                return Err(dmbc::request_failure::RequestFailure::internal(format!("native unsupported: {message}")).into())
            }
            Err(dmbc::cold::ColdError::RuntimeTypeValues(error)) => {
                return Err(dmbc::request_failure::RequestFailure::internal(format!("runtime type values: {error:?}")).into())
            }
            Err(dmbc::cold::ColdError::Operational(error)) => return Err(error.into()),
            Err(dmbc::cold::ColdError::AbiPreparation(message))
                if dmbc::diagnostics::write_carried_source_error(&mut dmbc::daemon::stderr_writer(), &message)? =>
            {
                return Err(dmbc::request_failure::RequestFailure::source("").into())
            }
            Err(error) => return Err(dmbc::request_failure::RequestFailure::internal(format!("native compilation: {error:?}")).into()),
        };
        let compilation_seconds = compilation_started.elapsed().as_secs_f64();
        dmbc::heap_census::emit_if_enabled("publication.ready", |census| {
            census.output_encoded("dmb.bytes", &output.dmb);
            if let Some(generation) = &generation { census.composition_generation(generation); }
            if let dmbc::assets::ResourceArchive::Captured(archive) = &publication.archive {
                census.output_resources("rsc.bytes", archive);
            }
        })?;
        if progress_enabled {
            if let Some(totals) = runner_report::initializer_totals(procedure_memo.as_ref()) {
                dmbc::daemon_eprintln!("native initializer reuse: {totals}");
            }
            if let Some(totals) = runner_report::startup_totals(procedure_memo.as_ref()) {
                dmbc::daemon_eprintln!("native startup reuse: {totals}");
            }
            if let Some(totals) = runner_report::abi_totals(procedure_memo.as_ref()) {
                dmbc::daemon_eprintln!("native ABI reuse: {totals}");
            }
            if let Some(totals) = runner_report::initializer_fragment_totals(procedure_memo.as_ref()) {
                dmbc::daemon_eprintln!("native initializer fragment reuse: {totals}");
            }
        }
        drop(compilation_profile);
        dm_profile::detail_mark("compilation", total);
        let cache_flush_profile = dm_profile::stage("cache_flush");
        if let (Some(cache), Some(memo)) = (&memo_cache, &procedure_memo) {
            let records = memo.take_pending();
            publish_cache_records(cache, records);
            use std::sync::atomic::Ordering::Relaxed;
            dmbc::daemon_eprintln!("native retention: policy={:032x} host={}", memo.policy, retention_status);
            dmbc::daemon_eprintln!("native lowering memo: disk_hits={} resident_hits={} resident_dropped={} retention={:?} recomputed={} unsupported_disk={} local_attempts={} local_hits={} local_worker_s={:.3} keyed_worker_s={:.3} local_declines=[{}]",
                memo.counts.disk_hits.load(Relaxed), memo.counts.resident_hits.load(Relaxed),
                memo.counts.resident_dropped.load(Relaxed), memo.resident_retention(),
                memo.counts.recomputed.load(Relaxed), memo.counts.unsupported_disk.load(Relaxed),
                memo.counts.local_attempts.load(Relaxed), memo.counts.local_hits.load(Relaxed),
                memo.counts.local_ns.load(Relaxed) as f64 / 1e9, memo.counts.keyed_ns.load(Relaxed) as f64 / 1e9,
                dmbc::lowering::local_decline_stats());
            match memo.dep_index() {
                Some(index) => dmbc::daemon_eprintln!("native dependency index: {}", index.summary()),
                None => dmbc::daemon_eprintln!("native dependency index: off"),
            }
            if let Some(db) = memo.query_db() {
                let started = std::time::Instant::now();
                let summary = db.answer_diff().summary();
                let (resolved, carried, _) = db.answer_counts();
                dmbc::daemon_eprintln!("native answer diff: {summary}, resolved={resolved} carried={carried} ({:.4}s)", started.elapsed().as_secs_f64());
            }
            dmbc::daemon_eprintln!("native accumulated: {}", dm_profile::take_accumulated());
            for outcome in dm_tree::change_set::take_outcomes() {
                dmbc::daemon_eprintln!("native change set: {outcome}");
            }
            let errors = memo.staging_errors();
            if !errors.is_empty() {
                dmbc::daemon_eprintln!("cache population skipped: {}", errors.join("; "));
            }
        }
        if let (Some(cache), Some(memo)) = (&memo_cache, &expansion_memo) {
            publish_cache_records(cache, memo.take_pending());
            let errors = memo.staging_errors();
            if !errors.is_empty() {
                dmbc::daemon_eprintln!("expansion cache population skipped: {}", errors.join("; "));
            }
        }
        if let (Some(cache), Some(memo)) = (&memo_cache, &map_memo) {
            publish_cache_records(cache, memo.take_pending());
            let errors = memo.staging_errors();
            if !errors.is_empty() {
                dmbc::daemon_eprintln!("map cache population skipped: {}", errors.join("; "));
            }
        }
        if let Some(cache) = &memo_cache {
            dmbc::heap_census::emit_if_enabled("cache_batch.staged", |census| census.cache_batch(cache))?;
        }
        drop(cache_flush_profile);
        dm_profile::detail_mark("cache_flush", total);
        let publication_started = Instant::now();
        let publication_profile = dm_profile::stage("publication");
        if progress_enabled {
            dmbc::daemon_eprintln!("native publication started");
        }
        let store_path = match output_store {
            Some(path) => path,
            None => dmbc::publish::default_store_path(&project)?,
        };
        let store = match pair_store.take() {
            Some(store) => store,
            None => dmbc::publish::PairStore::open(store_path)?,
        };
        let session_id = match &session {
            Some(session) => session.identity()?,
            None => xxhash_rust::xxh3::xxh3_128(project.to_string_lossy().as_bytes()),
        };
        // A live admission (early or here) already proved these exact inputs,
        // so the session record below needs no second freshness sweep.
        let early_inputs = early_admission.and_then(|early| {
            snapshot_memo
                .get_using(&inputs_capture, publication.retained_resource_inputs.as_ref(),source_policy_queries.as_ref())
                .ok()
                .and_then(|current| early.finish(&current))
        });
        let early_admitted = early_inputs.is_some();
        let (publication_inputs, workspace_admission, source_admission) = if let Some(workspace) = query_attempt.pending_workspace() {
            let (inputs, admission) = runner_freshness::admit_workspace_captured_using(&inputs_capture, publication.retained_resource_inputs.as_ref(), &stamped_provider, generated_paths, workspace,source_policy_queries.as_ref())?;
            (inputs, Some(admission), None)
        } else if let Some(frame) = query_attempt.pending_source() {
            let (inputs, admission) = runner_freshness::admit_source_captured_using(&inputs_capture, publication.retained_resource_inputs.as_ref(), &stamped_provider, generated_paths, frame,source_policy_queries.as_ref())?;
            (inputs, None, Some(admission))
        } else { (match early_inputs {
            Some(inputs) => inputs,
            None => runner_freshness::admit_captured_using(&inputs_capture, publication.retained_resource_inputs.as_ref(), &stamped_provider, generated_paths,source_policy_queries.as_ref())?,
        }, None, None) };
        let live_admitted = source_override.is_none() && (early_admitted || !matches!(input_provider, dmbc::frozen_inputs::Inputs::Replay(_)));
        dmbc::daemon_eprintln!("native publication admission: early={early_admitted} live={live_admitted}");
        input_provider.finish()?;
        inputs_capture.finish_prepared()?;
        if let Some(admission) = workspace_admission { query_attempt.admit_workspace_policy(admission)?; }
        if let Some(admission) = source_admission { query_attempt.admit_source_frame(admission)?; }
        dm_profile::request_mark("publication.inputs_admitted");
        if let Some(joined) = joined { joined.require_current(&project, &publication_inputs)?; }
        dmbc::daemon::control::begin_publication()?;
        let pair = match &publication.archive {
            dmbc::assets::ResourceArchive::Captured(bytes) => {
                store.publish_images_exact(session_id, &output.dmb, bytes, exact_inputs)?
            }
            dmbc::assets::ResourceArchive::Retained(identity) => store
                .publish_encoded_with_resource_exact(
                    session_id,
                    &output.dmb,
                    *identity,
                    exact_inputs,
                )?,
        };
        dm_profile::request_mark("publication.pair_stored");
        // A whole-program build leaves its output for the next request to build on.
        if let (Some(generation), Some(shape), Some((records, warnings))) = (&generation, &patch_shape, patch_records) {
            match dmbc::retained_output::OutputBase::of_full_build(
                Arc::clone(shape),
                records,
                publication_inputs.clone(),
                publication.archive.identity(),
                warnings,
                procedure_memo.as_ref().and_then(|memo| memo.query_db()?.answers_version()),
                procedure_memo.as_ref().and_then(|memo| memo.query_db()?.answers_context()),
                procedure_memo.as_ref().and_then(|memo| Some(memo.query_db()?.mark_published())),
                procedure_memo.as_ref().and_then(|memo| memo.query_db()?.answer_facts()),
                output.dmb.content_hash(),
            ) {
                Some(base) => {
                    if !generation.install_patch_base(base) {
                        dmbc::daemon_eprintln!("native retained output: not installed (no link answers)");
                    }
                }
                None => dmbc::daemon_eprintln!("native retained output: not installed (duplicate units)"),
            }
            dm_profile::request_mark("publication.patch_base");
        }
        let ResourceOutputs { pins: _, prepared } = resource_outputs
            .into_inner()
            .unwrap_or_else(|error| error.into_inner());
        let installation = store.install_receipt_with_resource_proof(
            pair.id,
            &output_project.with_extension("dmb"),
            &output_project.with_extension("rsc"),
            &output_project.with_extension("dmb-pair.json"),
            exact_inputs,
            dmbc::publish::ResourceInstall {
                prepared,
                prior: prior_outputs
                    .as_ref()
                    .map(|outputs| dmbc::publish::PriorResourceProof::new(outputs, now_ns())),
            },
            Some(&output.dmb),
        )?;
        dm_profile::request_mark("publication.installed");
        let resource_journal_admission = resource_journal_admission.into_inner().unwrap_or_else(|error| error.into_inner());
        let publication_proof = verification_capture.then(|| crate::publication_proof::issue_with_resource_admission(&publication_inputs, &pair, &project, &defines, engine_identity, bootstrap_catalog, store.root_path(), resource_journal_admission)).transpose().map_err(|error| std::io::Error::other(format!("output pair {} was published, but native input proof issuance failed: {error}", pair.name())))?;
        if !verification_capture && (session.is_some() || resource_owner.is_some()) {
            let inputs = publication_inputs;
            // The record pairs the compiled snapshot with its output; a live
            // admission already proved it, so only replayed inputs sweep again.
            let unchanged = live_admitted || {
                let raw_publication_proofs = dmbc::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(&inputs)?;
                let publication_proofs = dmbc::input_snapshot::GeneratedOutputInputs::new(&raw_publication_proofs, generated_paths.iter().cloned());
                inputs.restat(&publication_proofs)?.unchanged()
            };
            dm_profile::request_mark("publication.session_admitted");
            if unchanged {
                let mut outputs = dmbc::input_snapshot::InputSnapshot::new(now_ns());
                installation.record_outputs(&mut outputs)?;
                let asset_paths = publication
                    .resource_catalog
                    .record()
                    .aliases
                    .iter()
                    .map(|alias| alias.disk_path.clone())
                    .collect();
                let resource_manifest = dmbc::resource_manifest::ResourceManifest::capture(
                    memo_policy,
                    &publication.resource_catalog,
                    inputs.select_files(&asset_paths)?,
                    publication.resource_archive_order.clone(),
                    publication.archive.identity(),
                )?;
                let resource_manifest = std::sync::Arc::new(resource_manifest);
                if let Some(owner) = &resource_owner {
                    owner.remember(resource_configuration, crate::runner_host::resources::Hint {
                        pair: pair.id, manifest: std::sync::Arc::clone(&resource_manifest), outputs: std::sync::Arc::new(outputs.clone()),
                    });
                }
                if let Some(engine) = &engine_capture { query_attempt.bind_publication_proof(&inputs, &engine.bytes); }
                dm_profile::request_mark("publication.resource_manifest");
                if let Some(session) = &session {
                    let stored = session.store(dmbc::session::Record { inputs, pair: pair.id,
                        outputs: Some(outputs), warnings: dmbc::initializer_policy::warnings::render(&output.warnings)?, resource_manifest: Some((*resource_manifest).clone()) })?;
                    // The next request validates this record first. A resident daemon decodes it now,
                    // beside the reply, so the request that follows finds it decoded.
                    if retains_query_owners {
                        let records = session.records();
                        let _ = std::thread::Builder::new()
                            .name("dmbc-session-decode".into())
                            .spawn(move || {
                                let _ = records.prior(stored);
                            });
                    }
                }
            } else {
                dmbc::daemon_eprintln!("native session not saved: inputs changed during compilation");
            }
        }
        let publication_seconds = publication_started.elapsed().as_secs_f64();
        drop(publication_profile);
        dm_profile::detail_mark("publication", total);
        let _finalization_profile = dm_profile::stage("request.finalization");
        let store_path = std::fs::canonicalize(store.root_path())?;
        // Required compile, freshness, pair installation and session operations
        // succeeded. The sole cache segment is published only at this boundary.
        dmbc::daemon::control::checkpoint()?;
        dm_profile::request_mark("finalization.checkpoint");
        declaration_request.publish_successful();
        dm_profile::request_mark("finalization.declarations_published");
        if let Some(generation) = &generation {
            generation.publish_successful();
        }
        dm_profile::request_mark("finalization.generation_published");
        if let Some(memo) = procedure_memo.as_ref().filter(|_| !built_on_retained) {
            memo.publish_successful();
        }
        dm_profile::request_mark("finalization.procedure_memo_published");
        if let Some(memo) = &map_memo {
            memo.publish_successful();
        }
        dm_profile::request_mark("finalization.memo_published");
        // A daemon replies once the output is installed and publishes the cache batch in the background (`cache_flush`); a
        // one-shot compile exits when the request ends, so it publishes here.
        let cache_batch_stats = memo_cache.as_ref().map(|cache| {
            if defer_cache_batch {
                if let Some(root) = cache.root().map(std::path::Path::to_path_buf) {
                    return match cache.take_batch() {
                        Ok(dmbc::runner_disk::TakenBatch::Spool(spool)) => {
                            dmbc::cache_flush::defer(root, "request batch", move || {
                                spool.finish().map_err(|error| error.to_string()).map(|report| {
                                    format!(
                                        "segment {} records={} variants={}",
                                        report.segment.map_or_else(|| "none".to_owned(), |id| format!("{id:032x}")),
                                        report.records,
                                        report.variants
                                    )
                                })
                            });
                            serde_json::json!({"segment":null,"committed_records":0,"committed_variants":0,
                                "status":"deferred","scope":"one_request_completed_batch"})
                        }
                        Ok(dmbc::runner_disk::TakenBatch::Report(report)) => serde_json::json!({
                            "segment": report.segment.map(|id| format!("{id:032x}")),
                            "committed_records": report.records,
                            "committed_variants": report.variants,
                            "status": "completed",
                            "scope": "one_request_completed_batch",
                        }),
                        Err(error) => {
                            dmbc::daemon_eprintln!("native cache publication skipped: {error}");
                            serde_json::json!({"segment":null,"committed_records":0,
                                "committed_variants":0,"status":"failed","error":error,
                                "scope":"one_request_completed_batch"})
                        }
                    };
                }
            }
            match cache.finish_batch() {
            Ok(report) => serde_json::json!({
                "segment": report.segment.map(|id| format!("{id:032x}")),
                "committed_records": report.records,
                "committed_variants": report.variants,
                "status": "completed",
                "scope": "one_request_completed_batch",
            }),
            Err(error) => {
                dmbc::daemon_eprintln!("native cache publication skipped: {error}");
                serde_json::json!({"segment":null,"committed_records":0,
                    "committed_variants":0,"status":"failed","error":error,
                    "scope":"one_request_completed_batch"})
            }
            }
        });
        dm_profile::request_mark("finalization.cache_batch");
        let memo_stats = procedure_memo.as_ref()
            .map(|memo| runner_report::memo_statistics(memo, &retention_status));
        let expansion_stats = expansion_memo.as_ref().map(|memo| {
            use std::sync::atomic::Ordering::Relaxed;
            serde_json::json!({"candidates":memo.candidates.load(Relaxed),"stored":memo.stored.load(Relaxed),"dropped":memo.dropped.load(Relaxed),"staged_records":memo.staged_records.load(Relaxed),"staging_failed":memo.staging_failed.load(Relaxed),"staging_wall_seconds":memo.staging_ns.load(Relaxed) as f64 / 1e9,"staging_errors":memo.staging_errors()})
        });
        let map_stats = map_memo.as_ref().map(|memo| {
            use std::sync::atomic::Ordering::Relaxed;
            serde_json::json!({"parse_hits":memo.counts.parse_hits.load(Relaxed),"geometry_hits":memo.counts.geometry_hits.load(Relaxed),"output_hits":memo.counts.output_hits.load(Relaxed),"unit_hits":memo.counts.unit_hits.load(Relaxed),"outputs_prepared":memo.counts.outputs_prepared.load(Relaxed),"parsed":memo.counts.parsed.load(Relaxed),"projected":memo.counts.projected.load(Relaxed),"disk_admitted":memo.counts.disk_admitted.load(Relaxed),"skipped_disk_budget":memo.counts.skipped_disk_budget.load(Relaxed),"staged_records":memo.counts.staged_records.load(Relaxed),"staging_failed":memo.counts.staging_failed.load(Relaxed),"staging_errors":memo.staging_errors()})
        });
        let declaration_stats = frontend_report.declaration_reuse;
        dmbc::daemon_eprintln!("native declaration reuse: {declaration_stats}");
        let stats = serde_json::json!({"project":project,"workers":workers,"session_hit":false,"seconds":total.elapsed().as_secs_f64(),"input_preparation_seconds":input_preparation_seconds,"frontend_seconds":frontend_report.frontend_seconds,"frontend_stage_wall_seconds":frontend_report.frontend_stage_wall_seconds,"declaration_reuse":declaration_stats,"nontext_seconds":nontext_seconds,"compilation_seconds":compilation_seconds,"publication_seconds":publication_seconds,"dmb_bytes":pair.dmb_bytes,"rsc_bytes":pair.rsc_bytes,"memo":memo_stats,"cache_batch":cache_batch_stats,"expansion_memo":expansion_stats,"map_memo":map_stats,"explanations":runner_report::explanations_value(&explanations)});
        let mut stats = stats;
        stats["metadata_resolution"] = frontend_report.metadata_resolution;
        dm_profile::request_mark("finalization.stats_built");
        if let Err(error) = dmbc::telemetry::save(&project, "stats", &stats) {
            dmbc::daemon_eprintln!("native telemetry skipped: {error}");
        }
        let _ = dmbc::telemetry::save(
            &project,
            "last-run",
            &serde_json::json!({"session_hit":false,"seconds":total.elapsed().as_secs_f64(),"pair":pair.name()}),
        );
        dm_profile::request_mark("finalization.telemetry_saved");
        dmbc::daemon_eprintln!("native stages: input_preparation={:.3}s frontend={:.3}s captured_facts={:.3}s resources_maps={:.3}s linking_inputs={:.3}s compilation={:.3}s publication={:.3}s",
            input_preparation_seconds, frontend_report.frontend_seconds, facts_seconds, nontext_seconds,
            linking_inputs_seconds, compilation_seconds, publication_seconds);
        dmbc::daemon_eprintln!("native compile: total={:.3}s ABI={:.3}s lowering={:.3}s initialization={:.3}s linking={:.3}s composition={:.3}s DMB={} RSC={} pair={}",
            total.elapsed().as_secs_f64(), output.timings.abi_preparation.as_secs_f64(),
            output.timings.lowering.as_secs_f64(), output.timings.initializers.as_secs_f64(),
            output.timings.symbolic_linking.as_secs_f64(), output.timings.composition.as_secs_f64(),
            pair.dmb_bytes, pair.rsc_bytes, pair.name());
        dmbc::initializer_policy::warnings::write_warnings(&mut dmbc::daemon::stderr_writer(), &output.warnings)?;
        query_attempt.finish_published(&pair);
        dm_profile::request_mark("finalization.done");
        return Ok(BuildOutcome::Published {
            publication_proof,
            pair,
            store: store_path,
            output_project,
            session_hit: false,
            seconds: total.elapsed().as_secs_f64(),
        });
    }
    if command == BuildCommand::PrepareQuery {
        let owners_started=Instant::now();
        if progress_enabled { dmbc::daemon_eprintln!("native stage query_prepare.owners: started"); }
        dm_profile::request_mark("query_prepare.owners.start");
        let outcome = if source_questions.is_some() { runner_analysis::prepare_source_questions(&frontend, retains_query_owners)? } else { runner_analysis::prepare_query_observed(
            &frontend, engine_capture.as_ref(), host_facts.as_deref(), executor,
            procedure_memo.as_ref(), memo_policy, &mut query_attempt, retains_query_owners, progress_enabled,
        )? };
        if progress_enabled { dmbc::daemon_eprintln!("native stage query_prepare.owners: {:.3}s",owners_started.elapsed().as_secs_f64()); }
        dm_profile::request_mark("query_prepare.owners.done");
        let freshness_started=Instant::now();
        if progress_enabled { dmbc::daemon_eprintln!("native stage query_prepare.freshness: started"); }
        dm_profile::request_mark("query_prepare.freshness.start");
        // Preparation is not output publication, but its pins still require the
        // ordinary captured-input freshness barrier before becoming current.
        let (workspace_admission, source_admission) = if let Some(workspace) = query_attempt.pending_workspace() {
            (Some(if let Some(intent)=policy_inputs.as_ref().filter(|intent|!intent.workspace_generators().is_empty()){runner_freshness::admit_generator_workspace_captured_using(&inputs_capture,None,&stamped_provider,generated_paths,workspace,intent,source_policy_queries.as_ref())?}else{runner_freshness::admit_workspace_captured_using(&inputs_capture,None,&stamped_provider,generated_paths,workspace,source_policy_queries.as_ref())?.1}),None)
        } else if let Some(frame) = query_attempt.pending_source() {
            (None, Some(runner_freshness::admit_source_captured_using(&inputs_capture, None, &stamped_provider, generated_paths, frame,source_policy_queries.as_ref())?.1))
        } else { runner_freshness::admit_captured_using(&inputs_capture, None, &stamped_provider, generated_paths,source_policy_queries.as_ref())?; (None, None) };
        input_provider.finish()?;
        inputs_capture.finish_prepared()?;
        dmbc::daemon::control::checkpoint()?;
        if let Some(admission) = workspace_admission { query_attempt.admit_workspace_policy(admission)?; }
        if let Some(admission) = source_admission { query_attempt.admit_source_frame(admission)?; }
        if progress_enabled { dmbc::daemon_eprintln!("native stage query_prepare.freshness: {:.3}s",freshness_started.elapsed().as_secs_f64()); }
        dm_profile::request_mark("query_prepare.freshness.done");
        let outcome = match outcome {
            BuildOutcome::QueryPrepared { semantic_revision, source_revision, retained, .. } => BuildOutcome::QueryPrepared { semantic_revision, source_revision, policy_revision: query_attempt.policy_revision().map(|pin| format!("{pin:032x}")), retained },
            other => other,
        };
        query_attempt.finish_analyzed();
        owner_observation::emit("prepared",&frontend,source_policy_queries.as_ref(),&*semantic_state);
        return Ok(outcome);
    }
    let outcome = runner_analysis::finish(&frontend, engine_capture.as_ref(), host_facts.as_deref(), executor,
        procedure_memo.as_ref(), memo_policy, command, &mut query_attempt, total)?;
    // Source/ABI query epochs produced by analysis exports obey the same closure
    // admission as PrepareQuery; exporting rows is not publication authority.
    let (workspace_admission, source_admission) = if let Some(workspace) = query_attempt.pending_workspace() {
        (Some(runner_freshness::admit_workspace_captured_using(&inputs_capture, None, &stamped_provider, generated_paths, workspace,source_policy_queries.as_ref())?.1), None)
    } else if let Some(frame) = query_attempt.pending_source() {
        (None, Some(runner_freshness::admit_source_captured_using(&inputs_capture, None, &stamped_provider, generated_paths, frame,source_policy_queries.as_ref())?.1))
    } else { runner_freshness::admit_captured_using(&inputs_capture, None, &stamped_provider, generated_paths,source_policy_queries.as_ref())?; (None, None) };
    input_provider.finish()?;
    inputs_capture.finish_prepared()?;
    dmbc::daemon::control::checkpoint()?;
    if let Some(admission) = workspace_admission { query_attempt.admit_workspace_policy(admission)?; }
    if let Some(admission) = source_admission { query_attempt.admit_source_frame(admission)?; }
    query_attempt.finish_analyzed();
    Ok(outcome)
    });
    dm_profile::request_mark("runner.execution_joined");
    drop(frontend_memo);
    host.prune_foreign_callable_index();
    dm_profile::request_mark("runner.host_pruned");
    execution_result?
}

// Shared actual native engine recipe. Generation-only preparation uses this
// same selection/read/ABI validation rather than a fixture seed or guessed template.
pub(crate) fn generation_engine_bytes<P: crate::input_snapshot::SnapshotProvider>(
    embedded_engine: bool, executable: bool, input_provider: &crate::frozen_inputs::Inputs,
    engine_template: Option<&std::path::Path>, inputs_capture: &crate::input_snapshot::RecordingInputs<P>,
) -> Result<Option<Vec<u8>>, Box<dyn std::error::Error>> {
    let engine_bytes = if embedded_engine {
        Some(include_bytes!("../../../fixtures/native_template.bin").to_vec())
    } else {
        // A compile accepts only the pinned template (checked below against the embedded copy), so where the caller keeps the
        // file says nothing about the build. Reading it through the capture recorded its PATH as a non-text input, and every
        // worktree keeps its own copy: a body edit compiled from another worktree was declined as "non-text input changed:
        // <template A> / <template B>" and took the full path. A live compile reads it unrecorded; recording and replay (which
        // must reproduce every read) and the analysis commands (whose catalog does depend on it) keep the recorded read.
        let unrecorded = executable && matches!(input_provider, dmbc::frozen_inputs::Inputs::Live);
        engine_template
            .map(|path| {
                if unrecorded {
                    std::fs::read(path).map_err(|error| format!("engine template {}: {error}", path.display()))
                } else {
                    inputs_capture
                        .read_binary(path)
                        .map_err(|error| format!("engine template {}: {error}", path.display()))
                }
            })
            .transpose()?
    };
    Ok(engine_bytes)
}
pub(crate) fn generation_engine_defines(executable: bool, engine_bytes: Option<&[u8]>, defines: &mut std::collections::BTreeMap<String,String>) -> Result<(),Box<dyn std::error::Error>> {
    if executable {
        if engine_bytes
            != Some(include_bytes!("../../../fixtures/native_template.bin").as_slice())
        {
            return Err(dmbc::request_failure::RequestFailure::internal(
                "native unsupported: compile requires the pinned BYOND 516.1687 engine template",
            )
            .into());
        }
        // This driver supports the pinned 516.1687 ABI. The reusable frontend
        // still receives explicit configuration rather than inferring a target.
        dmbc::pinned_target::admit_defines(defines)?;
    }
    Ok(())
}

#[path="runner_generation_cold.rs"]
pub(crate) mod generation_cold;

pub(crate) fn generation_input_provider(record_inputs: Option<&std::path::Path>, replay_inputs: Option<&std::path::Path>) -> std::io::Result<crate::frozen_inputs::Inputs> {
    let input_provider = match (record_inputs, replay_inputs) {
        (Some(directory), _) => dmbc::frozen_inputs::Inputs::record(directory)?,
        (_, Some(directory)) => dmbc::frozen_inputs::Inputs::replay(directory)?,
        _ => dmbc::frozen_inputs::Inputs::Live,
    };
    Ok(input_provider)
}

pub(crate) fn generation_progress(event: dm_tree::frontend::FrontendProgress) {
        dmbc::daemon_eprintln!(
            "frontend {:?} {:?}: {:.3}s {}/{}",
            event.stage,
            event.kind,
            event.elapsed.as_secs_f64(),
            event.completed_items,
            event.total_items
        );
}

#[path="runner_preparation_diagnostics.rs"]mod preparation_diagnostics;
pub(crate) use preparation_diagnostics::{PreparationDiagnosticOutput, PreparedCheckerTranscript};
pub use preparation_diagnostics::PreparationDiagnosticResult;
/// Explicit PrepareQuery-only output loan. No cached source/result authority
/// follows from the diagnostic outcome or caller-supplied output writer.
pub fn prepare_with_host_to(request:BuildRequest,host:&mut crate::runner_host::BuildHost,writer:&mut impl io::Write)->io::Result<PreparationDiagnosticResult>{
 if request.command!=BuildCommand::PrepareQuery{return Err(io::Error::new(io::ErrorKind::InvalidInput,"diagnostic capture entry is PrepareQuery only"))}
 let mut output=PreparationDiagnosticOutput::captured(writer);let preparation=run_build_with_host_and_derived_sink(request,host,None,&mut output);let diagnostics=output.take_error().map_or(Ok(()),Err);Ok(PreparationDiagnosticResult{preparation,diagnostics})
}

/// The selected report publishes only the successful attempt's diagnostics.
pub(crate) fn prepare_selected_report(
    request:BuildRequest, host:&mut crate::runner_host::BuildHost,
    stage:&mut crate::selected_report_spool::Stage, checker:Option<&mut crate::selected_report_spool::Stage>,
    joined: Option<&mut Option<JoinedSelectedInputs>>, library_sites: bool, compact_cache:Option<&Path>,
)->io::Result<(PreparationDiagnosticResult, Option<PreparedCheckerTranscript>)>{
    prepare_selected_report_using(request, host, stage, checker, joined, library_sites, compact_cache, false, false)
}

#[cfg(test)]
pub(crate) fn prepare_private_authored_with_checker(
    request: BuildRequest, host: &mut crate::runner_host::BuildHost,
    stage: &mut crate::selected_report_spool::Stage, checker: &mut crate::selected_report_spool::Stage,
)->Result<(PreparationDiagnosticResult, PreparedCheckerTranscript), Box<dyn std::error::Error>> {
    use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
    if !host.retains_artifacts() || request.record_inputs.is_some() || request.replay_inputs.is_some()
        || request.policy_inputs.as_ref().is_none_or(|intent|
            !Q::is_private_authored_checker(intent.workspace_auxiliary.as_slice()))
    {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "private combined report requires its exact live authored intent").into());
    }
    let (result, checker) = prepare_selected_report_using(request, host, stage, Some(checker), None, false, None, true, false)?;
    match checker {
        Some(checker) => Ok((result, checker)),
        None => {
            result.preparation?;
            result.diagnostics?;
            Err(io::Error::other("private combined report has no staged Checker transcript").into())
        }
    }
}

pub(crate) fn prepare_compound_full_registry(
    request:BuildRequest, host:&mut crate::runner_host::BuildHost,
    stage:&mut crate::selected_report_spool::Stage, checker:&mut crate::selected_report_spool::Stage,
    joined:&mut Option<JoinedSelectedInputs>, compact_cache:Option<&Path>, full_ci:bool,
)->io::Result<(PreparationDiagnosticResult,Option<PreparedCheckerTranscript>)>{
    use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
    if request.policy_inputs.as_ref().is_none_or(|intent|intent.workspace_auxiliary!=Q::PRIVATE_FULL_REGISTRY){
        return Err(io::Error::new(io::ErrorKind::InvalidInput,"compound full registry requires its exact internal authored intent"));
    }
    prepare_selected_report_using(request,host,stage,Some(checker),Some(joined),false,compact_cache,true,full_ci)
}

fn prepare_selected_report_using(
    request:BuildRequest, host:&mut crate::runner_host::BuildHost,
    stage:&mut crate::selected_report_spool::Stage, checker:Option<&mut crate::selected_report_spool::Stage>,
    joined: Option<&mut Option<JoinedSelectedInputs>>, library_sites: bool, compact_cache:Option<&Path>,
    private_authored_doc_ui: bool, full_ci: bool,
)->io::Result<(PreparationDiagnosticResult, Option<PreparedCheckerTranscript>)>{
    if request.command != BuildCommand::PrepareQuery {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "selected report preparation is PrepareQuery only"));
    }
    let mut output=match checker{
        Some(checker)=>PreparationDiagnosticOutput::selected_combined(stage,checker),
        None=>PreparationDiagnosticOutput::selected_report(stage),
    };
    if let Some(joined) = joined { output.retain_joined_inputs(joined); }
    if library_sites { output.require_library_sites_baseline()?; }
    if full_ci { output.require_full_ci_baselines()?; }
    if let Some(cache)=compact_cache{output.use_compact_checker(cache)?;}
    let preparation=run_build_with_selected_publication(request,host,None,None,&mut output,None,None,private_authored_doc_ui);
    let diagnostics=output.take_error().map_or(Ok(()),Err);
    Ok((PreparationDiagnosticResult{preparation,diagnostics}, output.take_checker_frame()))
}

pub(crate) trait HandlersFailureReportSink{
    fn consume_budget(&mut self,data:&dq_analyze::captured_sem_handlers::Data,config:&dq_analyze::captured_raw_file::Config,budget:&Arc<dq_analyze::captured_generator_budget::Budget>);
 fn failed(&mut self,error:io::Error);
}
