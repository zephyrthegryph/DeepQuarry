//! Shared request execution; the CLI and future hosts use this exact pipeline.
use crate as dmbc;
use crate::request::{BuildCommand, BuildOutcome, BuildRequest, Command, CommandOutcome};
use std::io::{self, Write};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;
#[path = "runner_report.rs"]
mod runner_report;

#[derive(Default)]
struct ResourceOutputs {
    pins: Vec<dmbc::publish::ResourcePin>,
    prepared: Option<dmbc::publish::PreparedOutputFile>,
}
struct OutputResourceSink<'a> {
    store: &'a dmbc::publish::PairStore,
    exact: bool,
    destination: &'a std::path::Path,
    outputs: &'a std::sync::Mutex<ResourceOutputs>,
}
impl dmbc::assets::ResourceArchiveSink for OutputResourceSink<'_> {
    fn retain(
        &self,
        rows: &[byond_dmb::rsc::NamedResourceView<'_>],
    ) -> io::Result<dmbc::publish::ResourceIdentity> {
        let (identity, pin, prepared) =
            self.store
                .publish_resource_views_prepared(rows, self.exact, Some(self.destination))?;
        let mut outputs = self
            .outputs
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        outputs.pins.push(pin);
        outputs.prepared = prepared;
        Ok(identity)
    }
}

pub fn run(request: Command) -> Result<CommandOutcome, Box<dyn std::error::Error>> {
    match request {
        Command::Help => {
            dmbc::daemon_println!("dmbc analyze|compile [--no-daemon] [--no-cache] [--exact-inputs] [--verify] [--trace FILE] PROJECT [-DNAME[=VALUE]] [--workers N] [--engine-template PATH] [--bootstrap-catalog] [--progress] [--output-store PATH]");
            dmbc::daemon_println!(
                "dmbc stats [PROJECT] | explain PROCEDURE [PROJECT] | gc [PROJECT]"
            );
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

pub fn run_build(request: BuildRequest) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    run_build_with_host(request, &mut crate::runner_host::BuildHost::one_shot())
}

/// Execute the same pipeline with an optional retained exact-engine owner.
pub fn run_build_with_host(
    request: BuildRequest,
    host: &mut crate::runner_host::BuildHost,
) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    let _build_profile = dm_profile::stage("build");
    let request_profile = dm_profile::stage("request.prepare");
    let BuildRequest {
        command,
        project,
        mut defines,
        workers,
        mut engine_template,
        mut bootstrap_catalog,
        progress_enabled,
        output_store,
        exact_inputs,
        no_cache,
        record_inputs,
        replay_inputs,
        artifact_directory,
        no_daemon: _,
        trace_path: _,
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
    if command == BuildCommand::Compile && engine_template.is_none() {
        engine_template = Some(
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_template.bin"),
        );
        bootstrap_catalog = true;
    }
    drop(request_profile);
    let engine_input_profile = dm_profile::stage("engine_input");
    let engine_bytes = engine_template
        .as_ref()
        .map(|path| {
            dm_profile::io_call(|| std::fs::read(path), |bytes| (bytes.len() as u64, 0))
                .map_err(|error| format!("engine template {}: {error}", path.display()))
        })
        .transpose()?;
    let engine_identity = engine_bytes
        .as_ref()
        .map_or(0, |bytes| xxhash_rust::xxh3::xxh3_128(bytes));
    drop(engine_input_profile);
    let input_context_profile = dm_profile::stage("request.input_context");
    if command == BuildCommand::Compile {
        if engine_bytes.as_deref()
            != Some(include_bytes!("../../../fixtures/native_template.bin").as_slice())
        {
            return Err(
                "native unsupported: compile requires the pinned BYOND 516.1687 engine template"
                    .into(),
            );
        }
        // This driver supports the pinned 516.1687 ABI. The reusable frontend
        // still receives explicit configuration rather than inferring a target.
        defines
            .entry("DM_VERSION".into())
            .or_insert_with(|| "516".into());
        defines
            .entry("DM_BUILD".into())
            .or_insert_with(|| "1687".into());
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
    let inputs_capture = dmbc::input_snapshot::RecordingInputs::new(&input_provider, now_ns());
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
    let compiler = if command == BuildCommand::Compile && (!no_cache || host.retains_artifacts()) {
        let compiler = file_hash(&std::env::current_exe()?)?;
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
        let configuration = dmbc::session::Configuration::new(
            project.parent().ok_or("manifest parent missing")?,
            &project,
            defines.clone(),
            compiler,
            engine_identity,
            xxhash_rust::xxh3::xxh3_128(if bootstrap_catalog {
                b"native-session-v1-bootstrap"
            } else {
                b"native-session-v1-template"
            }),
        )?;
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
            if let Some(mut validated) =
                configured.validate_filesystem_observed(id, exact_inputs, now_ns(), |record| {
                    if prior_outputs.is_none() {
                        prior_outputs = record.outputs.clone();
                    }
                    if resource_prior.is_none() {
                        if let Some(manifest) = &record.resource_manifest {
                            resource_prior = Some((record.pair, manifest.clone()));
                        }
                    }
                })?
            {
                let pair_verification_started = Instant::now();
                if let Ok(pair) = store.verify(validated.record().pair, exact_inputs) {
                    let pair_verification_seconds =
                        pair_verification_started.elapsed().as_secs_f64();
                    let output_validation_started = Instant::now();
                    let (outputs_match, output_rehashes) = validated.refresh_outputs(
                        &dmbc::input_snapshot::FileSystemInputs,
                        exact_inputs,
                        now_ns(),
                    )?;
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
                    if progress_enabled {
                        let timing = &validated.timings;
                        dmbc::daemon_eprintln!("native session validation: record={:.3}s bulk_capture={:.3}s input_validate={:.3}s pair={:.3}s outputs={:.3}s proofs={:?}", timing.record_decode.as_secs_f64(), timing.bulk_capture.as_secs_f64(), timing.input_validate.as_secs_f64(), pair_verification_seconds, output_validation_started.elapsed().as_secs_f64(), timing.proofs);
                    }
                    let rehashed = validated.validation.rehashed;
                    if validated.validation.rehashed > 0 || output_rehashes > 0 || !outputs_match {
                        let mut record = validated.into_record();
                        if !outputs_match {
                            let mut outputs = dmbc::input_snapshot::InputSnapshot::new(now_ns());
                            for extension in ["dmb", "rsc", "dmb-pair.json"] {
                                capture_output_digest(
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
                    return Ok(BuildOutcome::Published {
                        pair,
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
    let memo_cache = if command == BuildCommand::Compile && !no_cache {
        match dm_cache::Cache::user_default(dm_cache::Limits::default()) {
            Ok(cache) => Some(Arc::new(cache)),
            Err(error) => {
                dmbc::daemon_eprintln!("native cache unavailable: {error}; compiling fresh");
                None
            }
        }
    } else {
        None
    };
    let cache_snapshot = memo_cache
        .as_ref()
        .and_then(|cache| match cache.snapshot() {
            Ok(snapshot) => Some(Arc::new(snapshot)),
            Err(error) => {
                dmbc::daemon_eprintln!("native cache snapshot rejected: {error}; compiling fresh");
                None
            }
        });
    let published_keys = Arc::new(std::sync::Mutex::new(std::collections::BTreeSet::new()));
    let cache_publisher: Option<Arc<dmbc::lowering_memo::CachePublisher>> =
        memo_cache.as_ref().map(|cache| {
            let cache = Arc::clone(cache);
            let published_keys = Arc::clone(&published_keys);
            Arc::new(move |records: Vec<dm_cache::Record>| {
                let mut sink = cache.publish_sink(8 * 1024 * 1024);
                for record in records {
                    sink.push(record).map_err(|error| error.to_string())?;
                }
                let report = sink.finish().map_err(|error| error.to_string())?;
                published_keys
                    .lock()
                    .unwrap_or_else(|error| error.into_inner())
                    .extend(report.keys);
                Ok(())
            }) as Arc<dmbc::lowering_memo::CachePublisher>
        });
    let procedure_memo = host
        .procedure_memo(memo_policy, cache_snapshot.clone())
        .map(|memo| {
            let memo = memo.with_explanation_limit(131072);
            match &cache_publisher {
                Some(publisher) => memo.with_publisher(Arc::clone(publisher)),
                None => memo,
            }
        });
    let expansion_memo = cache_snapshot.clone().map(|snapshot| {
        dmbc::expansion_memo::DiskExpansionMemo::new(memo_policy, snapshot).with_publisher(
            cache_publisher
                .as_ref()
                .expect("snapshot publisher")
                .clone(),
        )
    });
    let map_memo = cache_snapshot.clone().map(|snapshot| {
        dmbc::map_memo::MapMemo::with_disk(memo_policy, 64 * 1024 * 1024, snapshot).with_publisher(
            cache_publisher
                .as_ref()
                .expect("snapshot publisher")
                .clone(),
        )
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
    let (frontend_memo, execution, semantic_state) = host.execution(
        workers,
        expansion_memo
            .as_ref()
            .map(|memo| memo as &dyn dm_preprocess::regions::ExpansionMemo),
    )?;
    execution.run(|executor| -> Result<BuildOutcome, Box<dyn std::error::Error>> {
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
            semantic_state,
        )
    };
    let frontend_handoff_profile = dm_profile::stage("request.frontend_handoff");
    dmbc::daemon::control::checkpoint()?;
    let frontend = dm_tree::frontend::FrontendRevision::new(match frontend_result {
        Ok(frontend) => frontend,
        Err(diagnostics) => {
            dmbc::diagnostics::write_diagnostics(&mut dmbc::daemon::stderr_writer(), &diagnostics)?;
            let message = "source analysis did not produce a complete declaration model";
            let failure = if diagnostics.iter().all(|diagnostic| diagnostic.kind == dm_tree::frontend::DiagnosticKind::SourceError) {
                dmbc::request_failure::RequestFailure::source(message)
            } else {
                dmbc::request_failure::RequestFailure::internal(message)
            };
            return Err(failure.into());
        }
    });
    if command == BuildCommand::Compile {
        let frontend_report = runner_report::FrontendReport::capture(&frontend);
        let retained_engine = engine_capture
            .as_ref()
            .ok_or("compile requires captured engine")?;
        let bytes = &retained_engine.bytes;
        let engine = &retained_engine.snapshot;
        dmbc::heap_census::emit_if_enabled("frontend.ready", |census| census.frontend(&frontend))?;
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
        let mut symbols = dm_ir::SymbolTable::overlay(frontend.snapshot.tree.shared_symbols());
        let constants = dmbc::engine_host::ConstantCatalog::native_516_1687(&mut symbols)
            .map_err(|error| format!("engine constants: {error:?}"))?;
        let ordinary = frontend
            .snapshot
            .tree
            .types()
            .iter()
            .map(|node| node.path)
            .collect();
        let runtime = dmbc::engine_host::RuntimeAliasCatalog::new(
            engine.identity(),
            &symbols,
            Vec::new(),
            ordinary,
            dmbc::engine_host::Completeness::Partial,
        )
        .map_err(|error| format!("runtime type catalog: {error:?}"))?;
        let pinned_facts =
            dmbc::engine_host::PinnedHostFacts::capture(engine, &frontend, &constants, &runtime)?;
        let source_host = dmbc::engine_host::EngineResolverHost::new(
            frontend.snapshot.tree.clone(),
            constants.clone(),
            runtime.clone(),
        )
        .with_pinned_facts(engine, &frontend, Arc::clone(&pinned_facts))?;
        let scalar = dmbc::compile_driver::scalars(
            &frontend,
            engine,
            &source_host,
            source_host.configuration_identity(),
        );
        drop(source_host);
        let defaults = dmbc::compile_driver::map_defaults(&scalar)?;
        let host = dmbc::engine_host::EngineResolverHost::new(Arc::new(scalar), constants, runtime)
            .with_pinned_facts(engine, &frontend, pinned_facts)?;
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
            let Some((prior_pair, manifest)) = resource_prior.as_ref() else {
                return Ok(None);
            };
            let Some(store) = pair_store.as_ref() else {
                return Ok(None);
            };
            let proof_started = std::time::Instant::now();
            let proof_profile = dm_profile::stage("resources.filesystem_proofs");
            let proofs = manifest.filesystem_proofs();
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
                        Ok(store.verify(*prior_pair, exact_inputs).is_ok_and(|pair| {
                            pair.rsc_bytes == identity.bytes && pair.rsc_hash == identity.hash
                        }))
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
            drop(symbols);
            drop(frontend);
            let output =
                composition.compose(executor, progress_enabled.then_some(&cold_observer))?;
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
                let failure = if diagnostics.iter().all(|diagnostic| diagnostic.kind == dm_tree::frontend::DiagnosticKind::SourceError) {
                    dmbc::request_failure::RequestFailure::source(message)
                } else {
                    dmbc::request_failure::RequestFailure::internal(message)
                };
                return Err(failure.into());
            }
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
            if let dmbc::assets::ResourceArchive::Captured(archive) = &publication.archive {
                census.output_resources("rsc.bytes", archive);
            }
        })?;
        drop(compilation_profile);
        let cache_flush_profile = dm_profile::stage("cache_flush");
        if let (Some(cache), Some(memo)) = (&memo_cache, &procedure_memo) {
            let records = memo.take_pending();
            published_keys
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .extend(publish_cache_records(cache, records)?);
            use std::sync::atomic::Ordering::Relaxed;
            dmbc::daemon_eprintln!("native lowering memo: disk_hits={} resident_hits={} recomputed={} unsupported_disk={}",
                memo.counts.disk_hits.load(Relaxed), memo.counts.resident_hits.load(Relaxed),
                memo.counts.recomputed.load(Relaxed), memo.counts.unsupported_disk.load(Relaxed));
            let errors = memo.publication_errors();
            if !errors.is_empty() {
                return Err(format!("cache population failed: {}", errors.join("; ")).into());
            }
        }
        if let (Some(cache), Some(memo)) = (&memo_cache, &expansion_memo) {
            published_keys
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .extend(publish_cache_records(cache, memo.take_pending())?);
            let errors = memo.publication_errors();
            if !errors.is_empty() {
                return Err(
                    format!("expansion cache population failed: {}", errors.join("; ")).into(),
                );
            }
        }
        if let (Some(cache), Some(memo)) = (&memo_cache, &map_memo) {
            published_keys
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .extend(publish_cache_records(cache, memo.take_pending())?);
            let errors = memo.publication_errors();
            if !errors.is_empty() {
                return Err(format!("map cache population failed: {}", errors.join("; ")).into());
            }
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
        input_provider.finish()?;
        if let (Some(cache), Some(snapshot), Some(session)) =
            (&memo_cache, &cache_snapshot, &session)
        {
            let mut roots = snapshot.record_used_keys();
            roots.extend(
                published_keys
                    .lock()
                    .unwrap_or_else(|error| error.into_inner())
                    .iter()
                    .copied(),
            );
            if let Err(error) =
                cache.record_lease(session.identity()?, std::time::SystemTime::now(), &roots)
            {
                dmbc::daemon_eprintln!("native cache lease skipped: {error}");
            }
        }
        if let Some(session) = &session.filter(|_| !verification_capture) {
            let mut inputs = inputs_capture.snapshot()?;
            if let Some(retained) = &publication.retained_resource_inputs {
                inputs.merge(retained)?;
            }
            let publication_proofs = dmbc::filesystem_proofs::BulkFileSystemProofs::capture(
                inputs.proof_paths(),
                inputs.proof_folders(),
            );
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
                session.store(dmbc::session::Record {
                    inputs,
                    pair: pair.id,
                    outputs: Some(outputs),
                    resource_manifest: Some(resource_manifest),
                })?;
            } else {
                dmbc::daemon_eprintln!("native session not saved: inputs changed during compilation");
            }
        }
        let publication_seconds = publication_started.elapsed().as_secs_f64();
        drop(publication_profile);
        let _finalization_profile = dm_profile::stage("request.finalization");
        let memo_stats = procedure_memo.as_ref().map(|memo| {
            use std::sync::atomic::Ordering::Relaxed;
            serde_json::json!({"disk_hits":memo.counts.disk_hits.load(Relaxed),"issued_preparations":memo.counts.issued_preparations.load(Relaxed),"parsed_preparations":memo.counts.parsed_preparations.load(Relaxed),"recomputed":memo.counts.recomputed.load(Relaxed),"pending_dropped":memo.counts.pending_dropped.load(Relaxed),"published_records":memo.counts.published_records.load(Relaxed),"publication_failed":memo.counts.publication_failed.load(Relaxed),"key_preparation_seconds":memo.counts.key_preparation_ns.load(Relaxed) as f64 / 1e9,"lookup_seconds":memo.counts.lookup_ns.load(Relaxed) as f64 / 1e9,"occurrence_reads_seconds":memo.counts.occurrence_reads_ns.load(Relaxed) as f64 / 1e9,"explanation_seconds":memo.counts.explanation_ns.load(Relaxed) as f64 / 1e9,"encode_seconds":memo.counts.encode_ns.load(Relaxed) as f64 / 1e9,"publication_cpu_scope_seconds":memo.counts.publication_ns.load(Relaxed) as f64 / 1e9,"errors":memo.publication_errors()})
        });
        let expansion_stats = expansion_memo.as_ref().map(|memo| {
            use std::sync::atomic::Ordering::Relaxed;
            serde_json::json!({"candidates":memo.candidates.load(Relaxed),"stored":memo.stored.load(Relaxed),"dropped":memo.dropped.load(Relaxed),"published_records":memo.published_records.load(Relaxed),"publication_failed":memo.publication_failed.load(Relaxed),"publication_seconds":memo.publication_ns.load(Relaxed) as f64 / 1e9,"errors":memo.publication_errors()})
        });
        let map_stats = map_memo.as_ref().map(|memo| {
            use std::sync::atomic::Ordering::Relaxed;
            serde_json::json!({"parse_hits":memo.counts.parse_hits.load(Relaxed),"geometry_hits":memo.counts.geometry_hits.load(Relaxed),"parsed":memo.counts.parsed.load(Relaxed),"projected":memo.counts.projected.load(Relaxed),"disk_admitted":memo.counts.disk_admitted.load(Relaxed),"skipped_disk_budget":memo.counts.skipped_disk_budget.load(Relaxed),"published_records":memo.counts.published_records.load(Relaxed),"publication_failed":memo.counts.publication_failed.load(Relaxed),"errors":memo.publication_errors()})
        });
        let declaration_stats = frontend_report.declaration_reuse;
        dmbc::daemon_eprintln!("native declaration reuse: {declaration_stats}");
        let stats = serde_json::json!({"project":project,"workers":workers,"session_hit":false,"seconds":total.elapsed().as_secs_f64(),"input_preparation_seconds":input_preparation_seconds,"frontend_seconds":frontend_report.frontend_seconds,"declaration_reuse":declaration_stats,"nontext_seconds":nontext_seconds,"compilation_seconds":compilation_seconds,"publication_seconds":publication_seconds,"dmb_bytes":pair.dmb_bytes,"rsc_bytes":pair.rsc_bytes,"memo":memo_stats,"expansion_memo":expansion_stats,"map_memo":map_stats,"explanations":explanations});
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
        return Ok(BuildOutcome::Published {
            pair,
            output_project,
            session_hit: false,
            seconds: total.elapsed().as_secs_f64(),
        });
    }
    let mut output = io::BufWriter::new(dmbc::daemon::stdout_writer());
    let counts = dm_analysis::tree_export::write_jsonl(&frontend, &mut output)?;
    output.flush()?;
    let timings = &frontend.timings;
    dmbc::daemon_eprintln!(
        "source analysis: {} semantic, {} occurrence, {} body rows; planning={:.3}s expansion={:.3}s declarations={:.3}s tree={:.3}s provenance={:.3}s total={:.3}s",
        counts.semantic_rows,
        counts.occurrence_rows,
        counts.body_rows,
        timings.directive_planning.as_secs_f64(),
        timings.expansion.as_secs_f64(),
        timings.declaration_parsing.as_secs_f64(),
        timings.tree_resolution.as_secs_f64(),
        timings.provenance_and_body_indexing.as_secs_f64(),
        timings.total.as_secs_f64(),
    );
    Ok(BuildOutcome::Analyzed {
        semantic_rows: counts.semantic_rows,
        occurrence_rows: counts.occurrence_rows,
        body_rows: counts.body_rows,
        seconds: total.elapsed().as_secs_f64(),
    })
    })?
}

fn file_hash(path: &std::path::Path) -> io::Result<u128> {
    let _profile = dm_profile::stage("filesystem.hash");
    use std::io::Read;
    let mut file = std::fs::File::open(path)?;
    let mut buffer = [0u8; 65536];
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    loop {
        let count = dm_profile::io_call(|| file.read(&mut buffer), |count| (*count as u64, 0))?;
        if count == 0 {
            return Ok(hash.digest128());
        }
        hash.update(&buffer[..count]);
    }
}

fn capture_output_digest(
    snapshot: &mut dmbc::input_snapshot::InputSnapshot,
    path: &std::path::Path,
) -> io::Result<()> {
    use dmbc::input_snapshot::{FileSystemInputs, SnapshotProvider};
    let (stamp, content) = FileSystemInputs.digest(path)?;
    snapshot.record_verified_digest(path, stamp, content)
}

fn publish_cache_records(
    cache: &dm_cache::Cache,
    records: Vec<dm_cache::Record>,
) -> Result<std::collections::BTreeSet<dm_cache::RecordKey>, String> {
    let mut sink = cache.publish_sink(8 * 1024 * 1024);
    for record in records {
        sink.push(record)
            .map_err(|error| format!("cache population failed: {error}"))?;
    }
    match sink.finish() {
        Ok(report) => Ok(report.keys),
        Err(error) => Err(format!("cache population failed: {error}")),
    }
}
