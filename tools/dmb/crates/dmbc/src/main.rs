//! Native compilation over captured inputs, with disposable validated disk memos.
use std::collections::BTreeMap;
use std::io::{self, Write};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

#[cfg(feature = "allocation-counting")]
#[global_allocator]
static ALLOCATOR: dm_profile::CountingAllocator = dm_profile::CountingAllocator;

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if arguments.iter().any(|arg| arg == "--verify") {
        if let Err(error) = dmbc::verification::run_cli(&arguments) {
            eprintln!("{error}");
            std::process::exit(1);
        }
        return;
    }
    let trace_path = arguments
        .windows(2)
        .find(|pair| pair[0] == "--trace")
        .map(|pair| PathBuf::from(&pair[1]));
    let profile = match trace_path
        .as_deref()
        .map(dm_profile::initialize)
        .transpose()
    {
        Ok(profile) => profile,
        Err(error) => {
            eprintln!("native profile initialization failed: {error}");
            std::process::exit(1);
        }
    };
    let result = run();
    if let Some(profile) = profile {
        let sequential_stages: &[&str] = if result.is_ok()
            && profile.has_stage("session_validation")
            && !profile.has_stage("engine_capture")
        {
            &["engine_input", "session_validation"]
        } else {
            &[
                "engine_input",
                "engine_capture",
                "session_validation",
                "input_scan",
                "frontend.directive_planning",
                "frontend.expansion",
                "frontend.source_indexing",
                "frontend.declaration_parsing",
                "frontend.declaration_origins",
                "frontend.tree_resolution",
                "frontend.body_indexing",
                "captured_facts",
                "resources_maps",
                "linking_inputs",
                "cold.startup_capture",
                "cold.abi_preparation",
                "cold.initializers",
                "cold.procedure_lowering",
                "cold.required_type_admission",
                "cold.symbolic_linking",
                "cold.composition",
                "cache_flush",
                "publication",
            ]
        };
        if let Err(error) = profile.finish(sequential_stages) {
            eprintln!("native profile finalization failed: {error}");
            std::process::exit(1);
        }
    }
    if let Err(error) = result {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_else(|| "--help".into());
    if command == "gc" {
        let project =
            std::fs::canonicalize(args.next().unwrap_or_else(|| "deepquarry.dme".into()))?;
        println!(
            "{}",
            serde_json::to_string_pretty(&dmbc::cache_maintenance::run(&project)?)?
        );
        return Ok(());
    }
    if command == "stats" || command == "explain" {
        let target = if command == "explain" {
            Some(
                args.next()
                    .ok_or("explain requires an absolute procedure path")?,
            )
        } else {
            None
        };
        let project =
            std::fs::canonicalize(args.next().unwrap_or_else(|| "deepquarry.dme".into()))?;
        println!(
            "{}",
            serde_json::to_string_pretty(&dmbc::telemetry::inspect(&project, target.as_deref())?)?
        );
        return Ok(());
    }
    if command == "--help" || command == "-h" {
        println!("dmbc analyze|compile [--no-daemon] [--no-cache] [--exact-inputs] [--verify] [--trace FILE] PROJECT [-DNAME[=VALUE]] [--workers N] [--engine-template PATH] [--bootstrap-catalog] [--progress] [--output-store PATH]");
        println!("dmbc stats [PROJECT] | explain PROCEDURE [PROJECT] | gc [PROJECT]");
        println!("compile publishes a new immutable output pair and installs PROJECT.dmb/.rsc; unsupported semantics fail before publication.");
        return Ok(());
    }
    if command != "analyze" && command != "compile" {
        return Err("expected analyze or compile".into());
    }
    let mut project = None;
    let mut defines = BTreeMap::new();
    let mut workers = 2usize;
    let mut engine_template = None;
    let mut bootstrap_catalog = false;
    let mut progress_enabled = false;
    let mut output_store = None;
    let mut exact_inputs = false;
    let mut no_cache = false;
    let mut record_inputs = None;
    let mut replay_inputs = None;
    let mut artifact_directory = None;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--no-daemon" => {}
            "--exact-inputs" => exact_inputs = true,
            "--no-cache" => no_cache = true,
            "--trace" => {
                args.next().ok_or("--trace requires a file")?;
            }
            "--record-inputs" => {
                record_inputs = Some(PathBuf::from(
                    args.next().ok_or("--record-inputs requires a directory")?,
                ))
            }
            "--replay-inputs" => {
                replay_inputs = Some(PathBuf::from(
                    args.next().ok_or("--replay-inputs requires a directory")?,
                ))
            }
            "--artifact-directory" => {
                artifact_directory = Some(PathBuf::from(
                    args.next()
                        .ok_or("--artifact-directory requires a directory")?,
                ))
            }
            "--bootstrap-catalog" => bootstrap_catalog = true,
            "--progress" => progress_enabled = true,
            "--output-store" => {
                if output_store
                    .replace(PathBuf::from(
                        args.next().ok_or("--output-store requires a path")?,
                    ))
                    .is_some()
                {
                    return Err("--output-store accepts one directory".into());
                }
            }
            "--engine-template" => {
                if engine_template
                    .replace(PathBuf::from(
                        args.next().ok_or("--engine-template requires a path")?,
                    ))
                    .is_some()
                {
                    return Err("--engine-template accepts one template".into());
                }
            }
            "--workers" => {
                workers = args.next().ok_or("--workers requires a number")?.parse()?;
                if workers == 0 {
                    return Err("--workers must be positive".into());
                }
            }
            "-D" => {
                define(&mut defines, &args.next().ok_or("-D requires a name")?)?;
            }
            _ if arg.starts_with("-D") => define(&mut defines, &arg[2..])?,
            _ if arg.starts_with('-') => return Err(format!("unknown option {arg}").into()),
            _ => {
                if project.replace(PathBuf::from(arg)).is_some() {
                    return Err("analyze accepts one project manifest".into());
                }
            }
        }
    }
    let project = std::fs::canonicalize(project.ok_or("a project manifest is required")?)?;
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
    let _build_profile = dm_profile::stage("build");
    let mut build_lock = if command == "compile" {
        Some(dmbc::compile_driver::acquire_build_lock(&project)?)
    } else {
        None
    };
    if bootstrap_catalog && engine_template.is_none() {
        return Err("--bootstrap-catalog requires --engine-template".into());
    }
    // These are caller-supplied source defines. No target ABI is inferred by the
    // reusable frontend; supply DM_VERSION/DM_BUILD explicitly when needed.
    if command == "compile" && engine_template.is_none() {
        engine_template = Some(
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_template.bin"),
        );
        bootstrap_catalog = true;
    }
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
    if command == "compile" {
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
    let mut resource_prior = None;
    let mut memo_policy = 0;
    let session_profile = dm_profile::stage("session_validation");
    if command == "compile" && !no_cache {
        let compiler = file_hash(&std::env::current_exe()?)?;
        let mut policy_bytes = b"native-lowering-policy-v1\0".to_vec();
        policy_bytes.extend_from_slice(&compiler.to_le_bytes());
        policy_bytes.extend_from_slice(&engine_identity.to_le_bytes());
        policy_bytes.push(u8::from(bootstrap_catalog));
        memo_policy = xxhash_rust::xxh3::xxh3_128(&policy_bytes);
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
                    if !outputs_match {
                        store.install(
                            pair.id,
                            &output_project.with_extension("dmb"),
                            &output_project.with_extension("rsc"),
                            &output_project.with_extension("dmb-pair.json"),
                        )?;
                    }
                    if progress_enabled {
                        let timing = &validated.timings;
                        eprintln!("native session validation: record={:.3}s bulk_capture={:.3}s input_validate={:.3}s pair={:.3}s outputs={:.3}s proofs={:?}", timing.record_decode.as_secs_f64(), timing.bulk_capture.as_secs_f64(), timing.input_validate.as_secs_f64(), pair_verification_seconds, output_validation_started.elapsed().as_secs_f64(), timing.proofs);
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
                    eprintln!(
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
                    return Ok(());
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
        .map(|bytes| {
            let snapshot = dmbc::engine::EngineSnapshot::from_bytes(&bytes, 1)
                .map_err(|error| format!("engine template: {error:?}"))?;
            let snapshot = if bootstrap_catalog {
                snapshot
                    .with_bootstrap_catalog()
                    .map_err(|error| format!("engine catalog: {error:?}"))?
            } else {
                snapshot
            };
            Ok::<_, String>((bytes, snapshot))
        })
        .transpose()?;
    let engine = engine_capture.as_ref().map(|(_, engine)| engine);
    let memo_cache = if command == "compile" && !no_cache {
        match dm_cache::Cache::user_default(dm_cache::Limits::default()) {
            Ok(cache) => Some(Arc::new(cache)),
            Err(error) => {
                eprintln!("native cache unavailable: {error}; compiling fresh");
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
                eprintln!("native cache snapshot rejected: {error}; compiling fresh");
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
    let procedure_memo = cache_snapshot.clone().map(|snapshot| {
        dmbc::lowering_memo::ProcedureMemo::with_disk(memo_policy, snapshot)
            .with_explanation_limit(131072)
            .with_publisher(
                cache_publisher
                    .as_ref()
                    .expect("snapshot publisher")
                    .clone(),
            )
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
    let seed = engine.map(dmbc::engine::EngineSnapshot::frontend_seed);
    drop(engine_profile);
    let progress = |event: dm_tree::frontend::FrontendProgress| {
        eprintln!(
            "frontend {:?} {:?}: {:.3}s {}/{}",
            event.stage,
            event.kind,
            event.elapsed.as_secs_f64(),
            event.completed_items,
            event.total_items
        );
    };
    let input_preparation_seconds;
    let frontend_result = {
        let preparation_start = Instant::now();
        let input_profile = dm_profile::stage("input_scan");
        let inputs =
            match dmbc::native_inputs::NativeInputs::prepare(&project, &inputs_capture, workers) {
                Ok(inputs) => Some(inputs),
                Err(dmbc::native_inputs::NativeInputError::RequiredSourceRead { .. }) => None,
                Err(dmbc::native_inputs::NativeInputError::InternalPreparation { message }) => {
                    return Err(format!("native internal: {message}").into())
                }
            };
        input_preparation_seconds = preparation_start.elapsed().as_secs_f64();
        drop(input_profile);
        if progress_enabled {
            eprintln!(
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
        let _frontend_profile = dm_profile::stage("frontend");
        dm_tree::frontend::build_with_expansion_memo(
            &project,
            &provider,
            &defines,
            dm_tree::frontend::FrontendConfig {
                workers,
                engine: seed.as_ref(),
                observer: progress_enabled.then_some(&progress),
            },
            expansion_memo
                .as_ref()
                .map(|memo| memo as &dyn dm_preprocess::regions::ExpansionMemo),
        )
    };
    let frontend = match frontend_result {
        Ok(frontend) => frontend,
        Err(diagnostics) => {
            dmbc::diagnostics::write_diagnostics(&mut io::stderr().lock(), &diagnostics)?;
            return Err("source analysis did not produce a complete declaration model".into());
        }
    };
    if command == "compile" {
        let (bytes, engine) = engine_capture
            .as_ref()
            .ok_or("compile requires captured engine")?;
        if progress_enabled {
            eprintln!(
                "native captured facts started: {} types, {} members, {} bodies",
                frontend.snapshot.tree.types().len(),
                frontend.snapshot.tree.members().len(),
                frontend.bodies.len()
            );
        }
        let facts_started = Instant::now();
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
        let source_host = dmbc::engine_host::EngineResolverHost::new(
            frontend.snapshot.tree.clone(),
            constants.clone(),
            runtime.clone(),
        )
        .with_pinned_callables(engine, &frontend)?
        .with_pinned_variables(engine, &frontend)?;
        let scalar = dmbc::compile_driver::scalars(
            &frontend,
            engine,
            &source_host,
            source_host.configuration_identity(),
        );
        let defaults = dmbc::compile_driver::map_defaults(&scalar)?;
        let host = dmbc::engine_host::EngineResolverHost::new(Arc::new(scalar), constants, runtime)
            .with_pinned_callables(engine, &frontend)?
            .with_pinned_variables(engine, &frontend)?;
        let facts_seconds = facts_started.elapsed().as_secs_f64();
        drop(facts_profile);
        let nontext_started = Instant::now();
        let nontext_profile = dm_profile::stage("resources_maps");
        if progress_enabled {
            eprintln!("native resources and maps started");
        }
        let captured_engine = byond_dmb::dmb::Dmb::from_bytes(bytes)?;
        let roots = engine
            .frontend_seed()
            .hierarchy
            .parents
            .into_iter()
            .map(|(id, _)| id)
            .collect();
        let capture_observer = |measurement: dmbc::captured_non_text_driver::CaptureMeasurement| {
            if progress_enabled {
                eprintln!(
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
            eprintln!(
                "native resource FilesystemProofCapture: {:.3}s",
                proof_started.elapsed().as_secs_f64()
            );
            let observer = |measurement: dmbc::resource_manifest::ResourceValidationMeasurement| {
                eprintln!(
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
        let mut nontext = dmbc::captured_non_text_driver::capture_with_resource_reuse(
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
        )?;
        let nontext_seconds = nontext_started.elapsed().as_secs_f64();
        drop(nontext_profile);
        let linking_inputs_started = Instant::now();
        let linking_inputs_profile = dm_profile::stage("linking_inputs");
        let mut links = dmbc::engine_link::capture(bytes, engine)?;
        nontext.extend_inventory(&mut links.inventory)?;
        let values = dmbc::type_values::CapturedTypeValues::pinned(&frontend, engine)
            .map_err(|error| format!("runtime type values: {error:?}"))?;
        let values = dmbc::resource_values::CapturedResourceValues::new(
            &values,
            &nontext.resolver,
            nontext.resource_search_context,
        );
        let artifacts = std::mem::take(&mut nontext.artifacts);
        let linking_inputs_seconds = linking_inputs_started.elapsed().as_secs_f64();
        drop(linking_inputs_profile);
        let compilation_started = Instant::now();
        if progress_enabled {
            eprintln!("native compilation started");
        }
        let cold_observer = |measurement: dmbc::cold::ColdMeasurement| {
            eprintln!(
                "native cold {:?}: {:.3}s success={:?}",
                measurement.stage,
                measurement.elapsed.as_secs_f64(),
                measurement.succeeded
            );
        };
        // One immutable captured host for this compile. Consumer read recording
        // remains outside this optimization, including on memo hits.
        let compilation_resolver = dm_ir::MemoResolver::new(&nontext.resolver, 65_536);
        let compile_result = dmbc::compile_driver::compile_observed_with_memo(
            &frontend,
            &compilation_resolver,
            engine,
            bytes,
            links,
            &values,
            Some(nontext.resource_search_context),
            artifacts,
            Some(&nontext.stage(&frontend)),
            workers,
            progress_enabled.then_some(&cold_observer),
            procedure_memo.as_ref(),
        );
        if progress_enabled {
            eprintln!("native resolver memo: {:?}", compilation_resolver.stats());
        }
        if progress_enabled && compile_result.is_err() {
            eprintln!("native failed stages: input_preparation={:.3}s frontend={:.3}s captured_facts={:.3}s resources_maps={:.3}s linking_inputs={:.3}s compilation={:.3}s total={:.3}s",
                input_preparation_seconds, frontend.timings.total.as_secs_f64(), facts_seconds, nontext_seconds,
                linking_inputs_seconds, compilation_started.elapsed().as_secs_f64(),
                total.elapsed().as_secs_f64());
        }
        let output = match compile_result {
            Ok(output) => output,
            Err(dmbc::cold::ColdError::Lowering(diagnostics)) => {
                dmbc::diagnostics::write_lowering_diagnostics(
                    &mut io::stderr().lock(),
                    &diagnostics,
                )?;
                return Err("native lowering did not produce a complete executable".into());
            }
            Err(dmbc::cold::ColdError::InitializerInvariant(message)) => {
                return Err(format!("native internal: {message}").into())
            }
            Err(dmbc::cold::ColdError::Initializer(message)) => {
                return Err(format!("native unsupported: {message}").into())
            }
            Err(error) => return Err(format!("native compilation: {error:?}").into()),
        };
        let compilation_seconds = compilation_started.elapsed().as_secs_f64();
        let cache_flush_profile = dm_profile::stage("cache_flush");
        if let (Some(cache), Some(memo)) = (&memo_cache, &procedure_memo) {
            let records = memo.take_pending();
            published_keys
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .extend(publish_cache_records(cache, records)?);
            use std::sync::atomic::Ordering::Relaxed;
            eprintln!("native lowering memo: disk_hits={} resident_hits={} recomputed={} unsupported_disk={}",
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
            eprintln!("native publication started");
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
        let pair = match &nontext.resources.archive {
            dmbc::assets::ResourceArchive::Captured(bytes) => {
                store.publish(session_id, &output.dmb, bytes)?
            }
            dmbc::assets::ResourceArchive::Retained(identity) => {
                store.publish_with_resource(session_id, &output.dmb, *identity)?
            }
        };
        store.install(
            pair.id,
            &output_project.with_extension("dmb"),
            &output_project.with_extension("rsc"),
            &output_project.with_extension("dmb-pair.json"),
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
                eprintln!("native cache lease skipped: {error}");
            }
        }
        if let Some(session) = &session.filter(|_| !verification_capture) {
            let mut inputs = inputs_capture.snapshot()?;
            if let Some(retained) = &nontext.retained_resource_inputs {
                inputs.merge(retained)?;
            }
            let publication_proofs = dmbc::filesystem_proofs::BulkFileSystemProofs::capture(
                inputs.proof_paths(),
                inputs.proof_folders(),
            );
            if inputs.restat(&publication_proofs)?.unchanged() {
                let mut outputs = dmbc::input_snapshot::InputSnapshot::new(now_ns());
                for extension in ["dmb", "rsc", "dmb-pair.json"] {
                    let path = project.with_extension(extension);
                    capture_output_digest(&mut outputs, &path)?;
                }
                let asset_paths = nontext
                    .resource_catalog
                    .record()
                    .aliases
                    .iter()
                    .map(|alias| alias.disk_path.clone())
                    .collect();
                let resource_manifest = dmbc::resource_manifest::ResourceManifest::capture(
                    memo_policy,
                    &nontext.resource_catalog,
                    inputs.select_files(&asset_paths)?,
                    nontext.resource_archive_order.clone(),
                    nontext.resources.archive.identity(),
                )?;
                session.store(dmbc::session::Record {
                    inputs,
                    pair: pair.id,
                    outputs: Some(outputs),
                    resource_manifest: Some(resource_manifest),
                })?;
            } else {
                eprintln!("native session not saved: inputs changed during compilation");
            }
        }
        let publication_seconds = publication_started.elapsed().as_secs_f64();
        drop(publication_profile);
        let explanations: Vec<_> = procedure_memo.as_ref().map(|memo| memo.explain()).unwrap_or_default().into_iter().map(|entry| {
            let symbols = frontend.snapshot.tree.symbols();
            let owner = symbols.text(entry.identity.owner).unwrap_or("<unknown>");
            let name = symbols.text(entry.identity.name).unwrap_or("<unknown>");
            let namespace = if entry.identity.verb { "verb" } else { "proc" };
            let path = format!("{}/{namespace}/{name}", owner.trim_end_matches('/'));
            serde_json::json!({"path":path,"occurrence":entry.identity.occurrence,"outcome":format!("{:?}",entry.outcome),"reason":entry.reason.map(|reason|format!("{reason:?}")),"changed_query":entry.changed_query})
        }).collect();
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
        let d = &frontend.timings.declaration_reuse;
        let declaration_stats = serde_json::json!({"chunks":d.chunks,"region_hits":d.region_hits,"independent_hits":d.independent_hits,"facts_hits":d.facts_hits,"parsed_chunks":d.parsed_chunks,"descriptor_scan_seconds":d.descriptor_scan.as_secs_f64(),"worker_lookup_decode_and_parse_seconds":d.worker_lookup_decode_and_parse.as_secs_f64(),"worker_fresh_facts_seconds":d.worker_fresh_facts.as_secs_f64(),"ordered_merge_seconds":d.ordered_merge.as_secs_f64()});
        eprintln!("native declaration reuse: {declaration_stats}");
        let stats = serde_json::json!({"project":project,"workers":workers,"session_hit":false,"seconds":total.elapsed().as_secs_f64(),"input_preparation_seconds":input_preparation_seconds,"frontend_seconds":frontend.timings.total.as_secs_f64(),"declaration_reuse":declaration_stats,"nontext_seconds":nontext_seconds,"compilation_seconds":compilation_seconds,"publication_seconds":publication_seconds,"dmb_bytes":pair.dmb_bytes,"rsc_bytes":pair.rsc_bytes,"memo":memo_stats,"expansion_memo":expansion_stats,"map_memo":map_stats,"explanations":explanations});
        if let Err(error) = dmbc::telemetry::save(&project, "stats", &stats) {
            eprintln!("native telemetry skipped: {error}");
        }
        let _ = dmbc::telemetry::save(
            &project,
            "last-run",
            &serde_json::json!({"session_hit":false,"seconds":total.elapsed().as_secs_f64(),"pair":pair.name()}),
        );
        eprintln!("native stages: input_preparation={:.3}s frontend={:.3}s captured_facts={:.3}s resources_maps={:.3}s linking_inputs={:.3}s compilation={:.3}s publication={:.3}s",
            input_preparation_seconds, frontend.timings.total.as_secs_f64(), facts_seconds, nontext_seconds,
            linking_inputs_seconds, compilation_seconds, publication_seconds);
        eprintln!("native compile: total={:.3}s ABI={:.3}s lowering={:.3}s initialization={:.3}s linking={:.3}s composition={:.3}s DMB={} RSC={} pair={}",
            total.elapsed().as_secs_f64(), output.timings.abi_preparation.as_secs_f64(),
            output.timings.lowering.as_secs_f64(), output.timings.initializers.as_secs_f64(),
            output.timings.symbolic_linking.as_secs_f64(), output.timings.composition.as_secs_f64(),
            pair.dmb_bytes, pair.rsc_bytes, pair.name());
        return Ok(());
    }
    let mut output = io::BufWriter::new(io::stdout().lock());
    let counts = dm_analysis::tree_export::write_jsonl(&frontend, &mut output)?;
    output.flush()?;
    let timings = &frontend.timings;
    eprintln!(
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
    Ok(())
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

fn define(
    defines: &mut BTreeMap<String, String>,
    input: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let (name, value) = input.split_once('=').unwrap_or((input, "1"));
    if name.is_empty()
        || !name.chars().enumerate().all(|(index, ch)| {
            ch == '_' || ch.is_ascii_alphabetic() || (index != 0 && ch.is_ascii_digit())
        })
    {
        return Err(format!("invalid define name {name:?}").into());
    }
    defines.insert(name.into(), value.into());
    Ok(())
}
