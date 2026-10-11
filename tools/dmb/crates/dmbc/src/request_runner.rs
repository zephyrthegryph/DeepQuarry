//! Shared request execution; the CLI and future hosts use this exact pipeline.
use crate as dmbc;
use crate::request::{BuildCommand, BuildOutcome, BuildRequest, Command, CommandOutcome};
use std::{
    io::{self, Write},
    path::PathBuf,
    sync::Arc,
    time::Instant,
};
#[path = "runner_facts.rs"]
pub(crate) mod runner_facts;
#[path = "runner_report.rs"]
mod runner_report;
#[path = "runner_resources.rs"]
mod runner_resources;
use runner_resources::{OutputResourceSink, ResourceOutputs};
#[path = "runner_cache_records.rs"]
mod runner_cache_records;
#[path = "runner_configuration.rs"]
mod runner_configuration;
#[path = "runner_freshness.rs"]
mod runner_freshness;
#[path = "runner_generated_paths.rs"]
mod runner_generated_paths;
use runner_cache_records::publish_cache_records;
pub fn run(request: Command) -> Result<CommandOutcome, Box<dyn std::error::Error>> {
    match request {
        Command::Query { request, jsonl } => {
            dmbc::daemon::query::run_file(&request, jsonl).map(|()| CommandOutcome::Completed)
        }
        Command::Help => {
            dmbc::daemon_println!("dmbc analyze|compile [--bodies|--resolved (analyze only)] [--no-daemon] [--no-cache] [--exact-inputs] [--verify] [--trace FILE] PROJECT [-DNAME[=VALUE]] [--workers N] [--engine-template PATH] [--bootstrap-catalog] [--progress] [--output-store PATH]");
            dmbc::daemon_println!(
                "dmbc stats [PROJECT] | explain PROCEDURE [PROJECT] | gc [PROJECT] | query REQUEST.json [--jsonl]"
            );
            dmbc::daemon_println!("compile publishes a new immutable output pair and installs PROJECT.dmb/.rsc; unsupported semantics fail before publication.");
            Ok(CommandOutcome::Completed)
        }
        Command::Gc { project } => {
            let publishable_artifacts = command == BuildCommand::Compile && demand.is_none();
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
pub fn run_build(request: BuildRequest) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    run_build_with_host(request, &mut crate::runner_host::BuildHost::one_shot())
}
pub fn run_build_with_host(
    request: BuildRequest,
    host: &mut crate::runner_host::BuildHost,
) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    runner_freshness::run(request, |request| run_build_attempt(request, host, None))
}
#[path = "runner_analysis.rs"]
mod runner_analysis;
#[path = "runner_selected_demand.rs"]
pub(crate) mod selected_demand;
fn run_build_attempt(
    request: BuildRequest,
    host: &mut crate::runner_host::BuildHost,
    mut demand: Option<&mut selected_demand::Demand>,
) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    let mut query_attempt = crate::runner_host::query_snapshot::QueryAttempt::new(
        if demand.is_some() {
            Arc::new(std::sync::Mutex::new(Default::default()))
        } else {
            host.query_state()
        },
        host.retains_artifacts(),
    );
    let _build_profile = dm_profile::stage("build");
    let request_profile = dm_profile::stage("request.prepare");
    let BuildRequest {
        command,
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
    } = request;
    let project = std::fs::canonicalize(project)?;
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
        BuildCommand::Compile | BuildCommand::AnalyzeResolved
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
    let input_provider = match (&record_inputs, &replay_inputs) {
        (Some(directory), _) => dmbc::frozen_inputs::Inputs::record(directory)?,
        (_, Some(directory)) => dmbc::frozen_inputs::Inputs::replay(directory)?,
        _ => dmbc::frozen_inputs::Inputs::Live,
    };
    let generated_provider = dmbc::input_snapshot::GeneratedOutputInputs::new(
        &input_provider,
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
    let prepared_sources = host.prepared_sources();
    let inputs_capture = dmbc::input_snapshot::RecordingInputs::new(&generated_provider, now_ns())
        .with_exact_reuse(exact_inputs)
        .with_prepared_sources(prepared_sources.clone());
    drop(request_profile);
    let engine_input_profile = dm_profile::stage("engine_input");
    let engine_bytes = if embedded_engine {
        Some(include_bytes!("../../../fixtures/native_template.bin").to_vec())
    } else {
        engine_template
            .as_ref()
            .map(|path| {
                inputs_capture
                    .read_binary(path)
                    .map_err(|error| format!("engine template {}: {error}", path.display()))
            })
            .transpose()?
    };
    let engine_identity = engine_bytes
        .as_ref()
        .map_or(0, |bytes| xxhash_rust::xxh3::xxh3_128(bytes));
    drop(engine_input_profile);
    let input_context_profile = dm_profile::stage("request.input_context");
    if executable {
        if engine_bytes.as_deref()
            != Some(include_bytes!("../../../fixtures/native_template.bin").as_slice())
        {
            return Err(dmbc::request_failure::RequestFailure::internal(
                "native unsupported: compile requires the pinned BYOND 516.1687 engine template",
            )
            .into());
        }
        // This driver supports the pinned 516.1687 ABI. The reusable frontend
        // still receives explicit configuration rather than inferring a target.
        dmbc::pinned_target::admit_defines(&mut defines)?;
    }
    let mut session = None;
    let mut pair_store = None;
    // Request-owned leases outlive the borrowed capture sink and cold compiler.
    // They are released only after the final immutable pair is published.
    let resource_outputs = std::sync::Mutex::new(ResourceOutputs::default());
    let mut resource_prior = None;
    let mut prior_outputs = None;
    let mut memo_policy = 0;
    drop(input_context_profile);
    let session_profile = dm_profile::stage("session_validation");
    let compiler = if executable && (!no_cache || host.retains_artifacts()) {
        let compiler = dmbc::daemon::compiler_identity()?;
        let mut policy_bytes = b"native-lowering-policy-v1\0".to_vec();
        policy_bytes.extend_from_slice(&compiler.to_le_bytes());
        policy_bytes.extend_from_slice(&engine_identity.to_le_bytes());
        policy_bytes.push(u8::from(bootstrap_catalog));
        memo_policy = xxhash_rust::xxh3::xxh3_128(&policy_bytes);
        Some(compiler)
    } else {
        None
    };
    if command == BuildCommand::Compile && !no_cache {
        let compiler = compiler.expect("configured compiler identity");
        let configuration = runner_configuration::session(
            &project,
            &defines,
            compiler,
            engine_identity,
            bootstrap_catalog,
        )?;
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
            if let Some(mut validated) = configured
                .validate_filesystem_observed_with_generated_outputs(
                    id,
                    exact_inputs,
                    now_ns(),
                    generated_paths,
                    |record| {
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
                )?
            {
                let pair_verification_started = Instant::now();
                if let Ok(pair) = store.verify(validated.record().pair, exact_inputs) {
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
                                selected_demand::capture_output_digest(
                                    &mut outputs,
                                    &output_project.with_extension(extension),
                                )?;
                            }
                            record.outputs = Some(outputs);
                        }
                        configured.store(record)?;
                    }
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
    drop(session_profile);
    let engine_profile = dm_profile::stage("engine_capture");
    // An authenticated unchanged session needs no decoded engine or bootstrap
    // catalog. The key above pins exact engine bytes and this compiler/policy.
    let engine_capture = engine_bytes
        .map(|bytes| host.engine(project.clone(), defines.clone(), bootstrap_catalog, bytes))
        .transpose()?;
    if engine_capture.is_none() {
        host.clear_regions();
    }
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
        .procedure_memo(memo_policy, cache_snapshot.clone(), publishable_artifacts)
        .map(|memo| {
            let memo = memo.with_explanation_limit(131072);
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
    let seed = engine_capture
        .as_ref()
        .map(|capture| capture.frontend_seed());
    drop(engine_profile);
    let frontend_context_profile = dm_profile::stage("request.frontend_context");
    let progress = |event: dm_tree::frontend::FrontendProgress| {
        dmbc::daemon_eprintln!(
            "frontend {:?} {:?}: {:.3}s {}/{}",
            event.stage,
            event.kind,
            event.elapsed.as_secs_f64(),
            event.completed_items,
            event.total_items
        );
    };
    // One request-local execution boundary spans input capture, parsing, ABI,
    // lowering and linking. Its Drop joins workers before the CLI profiler ends.
    let generation = if executable {
        host.generation(memo_policy)
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
    let (frontend_memo, execution, mut semantic_state) = host.execution(
        workers,
        expansion_memo
            .as_ref()
            .map(|memo| memo as &dyn dm_preprocess::regions::ExpansionMemo),
    )?;
    // One-shot compilation uses the same named declaration receipt issuer as
    // retained sessions. This owner lasts for this request only: disabling
    // caches must not change which semantic answers the compiler can prove.
    let mut request_semantic = dm_tree::frontend::RetainedSemanticTree::default();
    let semantic_state = semantic_state
        .as_deref_mut()
        .unwrap_or(&mut request_semantic);
    let execution_result = execution.run(|executor| -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    dmbc::daemon::control::checkpoint()?;
    let input_preparation_seconds;
    let frontend_result = {
        let preparation_start = Instant::now();
        drop(frontend_context_profile);
        let input_profile = dm_profile::stage("input_scan");
        let inputs = match dmbc::native_inputs::NativeInputs::prepare_with_executor(
            &project,
            &inputs_capture,
            executor,
        ) {
            Ok(inputs) => Some(inputs),
            Err(dmbc::native_inputs::NativeInputError::RequiredSourceRead { .. }) => None,
            Err(dmbc::native_inputs::NativeInputError::InternalPreparation { message }) => {
                return Err(dmbc::request_failure::RequestFailure::internal(format!("native internal: {message}")).into())
            }
        };
        input_preparation_seconds = preparation_start.elapsed().as_secs_f64();
        drop(input_profile);
        let source_context_profile = dm_profile::stage("request.source_context");
        if progress_enabled {
            dmbc::daemon_eprintln!(
                "native input preparation: {:.3}s {:?}",
                input_preparation_seconds,
                inputs.as_ref().map(|inputs| inputs.stats())
            );
        }
        let empty = dm_preprocess::regions::prepared_source::PreparedSources::default();
        let provider = match &inputs {
            Some(inputs) => inputs.provider(&inputs_capture),
            None => dm_preprocess::regions::prepared_source::PreparedSourceProvider::new(
                &empty,
                &inputs_capture,
            ),
        };
        // Only requested captures enter the semantic model. Release unused
        // speculative preparations before maps, resources and lowering begin.
        drop(source_context_profile);
        let _frontend_profile = dm_profile::stage("frontend");
        dm_tree::frontend::build_with_executor_and_semantic_state(
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
        )
    };
    let frontend_handoff_profile = dm_profile::stage("request.frontend_handoff");
    dmbc::daemon::control::checkpoint()?;
    let frontend = dm_tree::frontend::FrontendRevision::new(match frontend_result {
        Ok(frontend) => frontend,
        Err(diagnostics) => {
            dmbc::diagnostics::write_diagnostics(&mut dmbc::daemon::stderr_writer(), &diagnostics)?;
            let message = "source analysis did not produce a complete declaration model";
            let failure = dmbc::request_failure::RequestFailure {
                kind: dmbc::diagnostics::failure_kind(diagnostics.iter().map(|diagnostic| diagnostic.kind)),
                message: message.into(),
            };
            return Err(failure.into());
        }
    });
    if let Some(demand) = demand.as_deref_mut() {
        let engine = engine_capture.as_ref().ok_or("selected query requires pinned engine")?;
        demand.complete(&frontend, engine, host_facts.as_deref(), executor, procedure_memo.as_ref(), memo_policy)?;
        runner_freshness::admit_captured(&inputs_capture, None, &input_provider, generated_paths)?;
        return Ok(BuildOutcome::Analyzed { semantic_rows: 0, occurrence_rows: 0, body_rows: 0, seconds: total.elapsed().as_secs_f64() });
    }
    query_attempt.capture(&frontend);
    if command == BuildCommand::Compile {
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
        let facts_profile = dm_profile::stage("captured_facts");
        let (host, scalar) = runner_facts::prepare_retained(&frontend, retained_engine, host_facts.as_deref())?;
        let defaults = dmbc::compile_driver::map_defaults(&scalar)?;
        drop(scalar);
        dmbc::heap_census::emit_if_enabled("captured_facts.ready", |census| {
            census.frontend(&frontend);
            host.census(census);
        })?;
        let facts_seconds = facts_started.elapsed().as_secs_f64();
        drop(facts_profile);
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
            let raw_proofs = manifest.filesystem_proofs().map_err(|error| error.to_string())?;
            let proofs = dmbc::input_snapshot::GeneratedOutputInputs::new(&raw_proofs, generated_paths.iter().cloned());
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
        let mut nontext =
            dmbc::captured_non_text_driver::capture_with_resource_reuse_on_executor_with_sink(
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
        let linking_inputs_started = Instant::now();
        let linking_inputs_profile = dm_profile::stage("linking_inputs");
        let mut links = retained_engine.link_overlay()?;
        nontext.extend_inventory(&mut links.inventory)?;
        let artifacts = std::mem::take(&mut nontext.artifacts);
        let linking_inputs_seconds = linking_inputs_started.elapsed().as_secs_f64();
        drop(linking_inputs_profile);
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
        let compile_result = (|| {
            let values = dmbc::type_values::CapturedTypeValues::pinned(&frontend, engine)
                .map_err(dmbc::cold::ColdError::RuntimeTypeValues)?;
            let values = dmbc::resource_values::CapturedResourceValues::new(
                &values,
                &nontext.resolver,
                nontext.resource_search_context,
            );
            let compilation_resolver = dm_ir::MemoResolver::new(&nontext.resolver, 65_536);
            let prepared = dmbc::compile_driver::prepare_revision_observed_with_memo_on_executor(
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
            )?;
            if progress_enabled {
                dmbc::daemon_eprintln!("native resolver memo: {:?}", compilation_resolver.stats());
            }
            let explanations = runner_report::explanations(&frontend, procedure_memo.as_ref());
            let owned_values = Arc::new(dmbc::resource_values::PreparedResourceValues::capture(
                &values,
                &prepared.domains(),
            ));
            drop(compilation_resolver);
            let (resolver, output_stage, publication) = nontext.into_composition_parts();
            let composition = prepared.seal(
                &frontend,
                Arc::clone(bytes),
                owned_values,
                Some(Box::new(output_stage)),
            )?;
            // The sealed composition retains exact output facts and no source owners.
            drop(resolver);
            drop(frontend);
            let output =
                composition.compose_with_generation(executor, progress_enabled.then_some(&cold_observer), generation.as_deref())?;
            Ok::<_, dmbc::cold::ColdError>((output, publication, explanations))
        })();
        if progress_enabled && compile_result.is_err() {
            dmbc::daemon_eprintln!("native failed stages: input_preparation={:.3}s frontend={:.3}s captured_facts={:.3}s resources_maps={:.3}s linking_inputs={:.3}s compilation={:.3}s total={:.3}s",
                input_preparation_seconds, frontend_report.frontend_seconds, facts_seconds, nontext_seconds,
                linking_inputs_seconds, compilation_started.elapsed().as_secs_f64(),
                total.elapsed().as_secs_f64());
        }
        let (output, publication, explanations) = match compile_result {
            Ok(output) => output,
            Err(dmbc::cold::ColdError::Lowering(diagnostics)) => {
                dmbc::diagnostics::write_lowering_diagnostics(
                    &mut dmbc::daemon::stderr_writer(),
                    &diagnostics,
                )?;
                let message = "native lowering did not produce a complete executable";
                let failure = dmbc::request_failure::RequestFailure {
                    kind: dmbc::diagnostics::failure_kind(diagnostics.iter().map(|diagnostic| diagnostic.kind)),
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
        let cache_flush_profile = dm_profile::stage("cache_flush");
        if let (Some(cache), Some(memo)) = (&memo_cache, &procedure_memo) {
            let records = memo.take_pending();
            publish_cache_records(cache, records);
            use std::sync::atomic::Ordering::Relaxed;
            dmbc::daemon_eprintln!("native retention: policy={:032x} host={}", memo.policy, retention_status);
            dmbc::daemon_eprintln!("native lowering memo: disk_hits={} resident_hits={} resident_dropped={} retention={:?} recomputed={} unsupported_disk={}",
                memo.counts.disk_hits.load(Relaxed), memo.counts.resident_hits.load(Relaxed),
                memo.counts.resident_dropped.load(Relaxed), memo.resident_retention(),
                memo.counts.recomputed.load(Relaxed), memo.counts.unsupported_disk.load(Relaxed));
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
        let publication_inputs = runner_freshness::admit_captured(&inputs_capture, publication.retained_resource_inputs.as_ref(), &input_provider, generated_paths)?;
        input_provider.finish()?;
        inputs_capture.finish_prepared()?;
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
        )?;
        let publication_proof = verification_capture.then(|| crate::publication_proof::issue(&publication_inputs, &pair, &project, &defines, engine_identity, bootstrap_catalog, store.root_path())).transpose().map_err(|error| std::io::Error::other(format!("output pair {} was published, but native input proof issuance failed: {error}", pair.name())))?;
        if !verification_capture && (session.is_some() || resource_owner.is_some()) {
            let inputs = publication_inputs;
            let raw_publication_proofs = dmbc::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(&inputs)?;
            let publication_proofs = dmbc::input_snapshot::GeneratedOutputInputs::new(&raw_publication_proofs, generated_paths.iter().cloned());
            if inputs.restat(&publication_proofs)?.unchanged() {
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
                if let Some(session) = &session {
                    session.store(dmbc::session::Record { inputs, pair: pair.id,
                        outputs: Some(outputs), warnings: dmbc::initializer_policy::warnings::render(&output.warnings)?, resource_manifest: Some((*resource_manifest).clone()) })?;
                }
            } else {
                dmbc::daemon_eprintln!("native session not saved: inputs changed during compilation");
            }
        }
        let publication_seconds = publication_started.elapsed().as_secs_f64();
        drop(publication_profile);
        let _finalization_profile = dm_profile::stage("request.finalization");
        let store_path = std::fs::canonicalize(store.root_path())?;
        // Required compile, freshness, pair installation and session operations
        // succeeded. The sole cache segment is published only at this boundary.
        dmbc::daemon::control::checkpoint()?;
        if let Some(memo) = &procedure_memo {
            memo.publish_successful();
        }
        if let Some(memo) = &map_memo {
            memo.publish_successful();
        }
        let cache_batch_stats = memo_cache.as_ref().map(|cache| match cache.finish_batch() {
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
        });
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
        let stats = serde_json::json!({"project":project,"workers":workers,"session_hit":false,"seconds":total.elapsed().as_secs_f64(),"input_preparation_seconds":input_preparation_seconds,"frontend_seconds":frontend_report.frontend_seconds,"frontend_stage_wall_seconds":frontend_report.frontend_stage_wall_seconds,"declaration_reuse":declaration_stats,"nontext_seconds":nontext_seconds,"compilation_seconds":compilation_seconds,"publication_seconds":publication_seconds,"dmb_bytes":pair.dmb_bytes,"rsc_bytes":pair.rsc_bytes,"memo":memo_stats,"cache_batch":cache_batch_stats,"expansion_memo":expansion_stats,"map_memo":map_stats,"explanations":explanations});
        let mut stats = stats;
        stats["metadata_resolution"] = frontend_report.metadata_resolution;
        if let Err(error) = dmbc::telemetry::save(&project, "stats", &stats) {
            dmbc::daemon_eprintln!("native telemetry skipped: {error}");
        }
        let _ = dmbc::telemetry::save(
            &project,
            "last-run",
            &serde_json::json!({"session_hit":false,"seconds":total.elapsed().as_secs_f64(),"pair":pair.name()}),
        );
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
        return Ok(BuildOutcome::Published {
            publication_proof,
            pair,
            store: store_path,
            output_project,
            session_hit: false,
            seconds: total.elapsed().as_secs_f64(),
        });
    }
    runner_analysis::finish(&frontend, engine_capture.as_ref(), host_facts.as_deref(), executor,
        procedure_memo.as_ref(), memo_policy, command, &mut query_attempt, total)
    });
    drop(frontend_memo);
    host.prune_foreign_callable_index();
    execution_result?
}
