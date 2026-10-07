//! Uncached analysis and native compilation over the shared captured pipeline.
use std::collections::BTreeMap;
use std::io::{self, Write};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_else(|| "--help".into());
    if command == "--help" || command == "-h" {
        println!("dmbc analyze|compile [--no-daemon] PROJECT [-DNAME[=VALUE]] [--workers N] [--engine-template PATH] [--bootstrap-catalog] [--progress] [--output-store PATH]");
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
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--no-daemon" => {}
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
    let total = Instant::now();
    let _build_lock = if command == "compile" {
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
    let engine_capture = engine_template
        .map(|path| {
            let bytes = std::fs::read(&path)
                .map_err(|error| format!("engine template {}: {error}", path.display()))?;
            let snapshot = dmbc::engine::EngineSnapshot::from_bytes(&bytes, 1)
                .map_err(|error| format!("engine template {}: {error:?}", path.display()))?;
            if bootstrap_catalog {
                snapshot
                    .with_bootstrap_catalog()
                    .map(|snapshot| (bytes, snapshot))
                    .map_err(|error| format!("engine catalog {}: {error:?}", path.display()))
            } else {
                Ok((bytes, snapshot))
            }
        })
        .transpose()?;
    let engine = engine_capture.as_ref().map(|(_, engine)| engine);
    if command == "compile" {
        if !engine.is_some_and(|engine| {
            engine.matches_template(include_bytes!("../../../fixtures/native_template.bin"), 1)
        }) {
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
    let seed = engine.map(dmbc::engine::EngineSnapshot::frontend_seed);
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
        let inputs = match dmbc::native_inputs::NativeInputs::prepare(
            &project,
            &dm_preprocess::FileSystem,
            workers,
        ) {
            Ok(inputs) => Some(inputs),
            Err(dmbc::native_inputs::NativeInputError::RequiredSourceRead { .. }) => None,
            Err(dmbc::native_inputs::NativeInputError::InternalPreparation { message }) => {
                return Err(format!("native internal: {message}").into())
            }
        };
        input_preparation_seconds = preparation_start.elapsed().as_secs_f64();
        if progress_enabled {
            eprintln!(
                "native input preparation: {:.3}s {:?}",
                input_preparation_seconds,
                inputs.as_ref().map(|inputs| inputs.stats())
            );
        }
        let empty = dm_preprocess::regions::prepared_source::PreparedSources::default();
        let provider = match &inputs {
            Some(inputs) => inputs.provider(&dm_preprocess::FileSystem),
            None => dm_preprocess::regions::prepared_source::PreparedSourceProvider::new(
                &empty,
                &dm_preprocess::FileSystem,
            ),
        };
        // Only requested captures enter the semantic model. Release unused
        // speculative preparations before maps, resources and lowering begin.
        dm_tree::frontend::build_with_config(
            &project,
            &provider,
            &defines,
            dm_tree::frontend::FrontendConfig {
                workers,
                engine: seed.as_ref(),
                observer: progress_enabled.then_some(&progress),
            },
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
        let nontext_started = Instant::now();
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
        let mut nontext = dmbc::captured_non_text_driver::capture_with_observer(
            &frontend,
            &dm_preprocess::FileSystem,
            &dm_resources::capture::FileSystemCapture,
            host,
            &captured_engine,
            &roots,
            &defaults,
            Some(&capture_observer),
        )?;
        let nontext_seconds = nontext_started.elapsed().as_secs_f64();
        let linking_inputs_started = Instant::now();
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
        let compilation_started = Instant::now();
        if progress_enabled {
            eprintln!("native compilation started");
        }
        let cold_observer = |measurement: dmbc::cold::ColdMeasurement| {
            eprintln!("native cold {:?}: {:.3}s success={:?}", measurement.stage,
                measurement.elapsed.as_secs_f64(), measurement.succeeded);
        };
        // One immutable captured host for this compile. Consumer read recording
        // remains outside this optimization, including on memo hits.
        let compilation_resolver = dm_ir::MemoResolver::new(&nontext.resolver, 65_536);
        let compile_result = dmbc::compile_driver::compile_observed(
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
        let publication_started = Instant::now();
        if progress_enabled {
            eprintln!("native publication started");
        }
        let store_path = match output_store {
            Some(path) => path,
            None => dmbc::publish::default_store_path(&project)?,
        };
        let store = dmbc::publish::PairStore::open(store_path)?;
        let session = xxhash_rust::xxh3::xxh3_128(project.to_string_lossy().as_bytes());
        let pair = store.publish(session, &output.dmb, &nontext.resources.rsc)?;
        store.install(
            pair.id,
            &project.with_extension("dmb"),
            &project.with_extension("rsc"),
            &project.with_extension("dmb-pair.json"),
        )?;
        let publication_seconds = publication_started.elapsed().as_secs_f64();
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
