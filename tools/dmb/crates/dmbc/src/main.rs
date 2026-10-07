//! Uncached source-analysis entry point. Full bytecode compilation is not yet
//! exposed here: lowering and linking still require migration.
use std::collections::BTreeMap;
use std::io::{self, Write};
use std::path::PathBuf;

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
        println!("dmbc analyze [--no-daemon] PROJECT [-DNAME[=VALUE]] [--workers N] [--engine-template PATH] [--bootstrap-catalog] [--progress]");
        println!("Streams source-declaration JSON-lines; engine and executable resolution remain incomplete.");
        return Ok(());
    }
    if command != "analyze" {
        return Err("expected analyze; bytecode compilation is not yet wired into dmbc".into());
    }
    let mut project = None;
    let mut defines = BTreeMap::new();
    let mut workers = 2usize;
    let mut engine_template = None;
    let mut bootstrap_catalog = false;
    let mut progress_enabled = false;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--no-daemon" => {}
            "--bootstrap-catalog" => bootstrap_catalog = true,
            "--progress" => progress_enabled = true,
            "--engine-template" => {
                if engine_template
                    .replace(PathBuf::from(args.next().ok_or("--engine-template requires a path")?))
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
    let project = project.ok_or("analyze requires a project manifest")?;
    if bootstrap_catalog && engine_template.is_none() {
        return Err("--bootstrap-catalog requires --engine-template".into());
    }
    // These are caller-supplied source defines. No target ABI is inferred by the
    // reusable frontend; supply DM_VERSION/DM_BUILD explicitly when needed.
    let engine = engine_template
        .map(|path| {
            let bytes = std::fs::read(&path)
                .map_err(|error| format!("engine template {}: {error}", path.display()))?;
            let snapshot = dmbc::engine::EngineSnapshot::from_bytes(&bytes, 1)
                .map_err(|error| format!("engine template {}: {error:?}", path.display()))?;
            if bootstrap_catalog {
                snapshot.with_bootstrap_catalog()
                    .map_err(|error| format!("engine catalog {}: {error:?}", path.display()))
            } else {
                Ok(snapshot)
            }
        })
        .transpose()?;
    let seed = engine.as_ref().map(dmbc::engine::EngineSnapshot::frontend_seed);
    let progress = |event: dm_tree::frontend::FrontendProgress| {
        eprintln!("frontend {:?} {:?}: {:.3}s {}/{}", event.stage, event.kind,
            event.elapsed.as_secs_f64(), event.completed_items, event.total_items);
    };
    let frontend =
        match dm_tree::frontend::build_with_config(
            &project,
            &dm_preprocess::FileSystem,
            &defines,
            dm_tree::frontend::FrontendConfig {
                workers,
                engine: seed.as_ref(),
                observer: progress_enabled.then_some(&progress),
            },
        ) {
            Ok(frontend) => frontend,
            Err(diagnostics) => {
                dmbc::diagnostics::write_diagnostics(&mut io::stderr().lock(), &diagnostics)?;
                return Err("source analysis did not produce a complete declaration model".into());
            }
        };
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
