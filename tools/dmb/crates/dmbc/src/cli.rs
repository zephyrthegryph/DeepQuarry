//! Parse the established CLI and capture the caller's cache namespace without file IO.
use crate::request::{BuildCommand, BuildRequest, Command};
use std::collections::BTreeMap;
use std::path::PathBuf;

pub fn parse(arguments: &[String]) -> Result<Command, Box<dyn std::error::Error>> {
    if arguments.iter().any(|arg| arg == "--verify") {
        return Ok(Command::Verify(arguments.to_vec()));
    }
    let mut args = arguments.iter().cloned();
    let command = args.next().unwrap_or_else(|| "--help".into());
    if command == "query" {
        let request = args
            .next()
            .ok_or("query requires a request JSON file")?
            .into();
        let jsonl = match args.next().as_deref() {
            None => false,
            Some("--jsonl") => true,
            Some("--export-jsonl") => {
                let mut limits = crate::daemon::query::semantic_client::ExportLimits::default();
                let mut seen = std::collections::BTreeSet::new();
                while let Some(option) = args.next() {
                    if !seen.insert(option.clone()) {
                        return Err("duplicate retained export quota".into());
                    }
                    let value: u32 = args
                        .next()
                        .ok_or("export quota requires an integer")?
                        .parse()?;
                    match option.as_str() {
                        "--max-items" => limits.max_items = value,
                        "--max-pages" => limits.max_pages = value,
                        _ => return Err("unexpected retained export argument".into()),
                    }
                }
                limits.validate()?;
                return Ok(Command::QueryExport { request, limits });
            }
            Some(_) => {
                return Err(
                    "query accepts only REQUEST.json and optional --jsonl or --export-jsonl".into(),
                )
            }
        };
        if args.next().is_some() {
            return Err("unexpected query argument".into());
        }
        return Ok(Command::Query { request, jsonl });
    }
    if command == "gc" {
        return Ok(Command::Gc {
            project: args
                .next()
                .unwrap_or_else(|| "deepquarry.dme".into())
                .into(),
        });
    }
    if command == "stats" {
        return Ok(Command::Stats {
            project: args
                .next()
                .unwrap_or_else(|| "deepquarry.dme".into())
                .into(),
        });
    }
    if command == "explain" {
        let target = args
            .next()
            .ok_or("explain requires an absolute procedure path")?;
        return Ok(Command::Explain {
            target,
            project: args
                .next()
                .unwrap_or_else(|| "deepquarry.dme".into())
                .into(),
        });
    }
    if command == "--help" || command == "-h" {
        return Ok(Command::Help);
    }
    let mut command = match command.as_str() {
        "analyze" => BuildCommand::Analyze,
        "compile" => BuildCommand::Compile,
        _ => return Err("expected analyze or compile".into()),
    };
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
    let mut no_daemon = false;
    let mut trace_path = None;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--bodies" if command == BuildCommand::Analyze => command = BuildCommand::AnalyzeBodies,
            "--resolved" if command == BuildCommand::Analyze => {
                command = BuildCommand::AnalyzeResolved
            }
            "--no-daemon" => no_daemon = true,
            "--exact-inputs" => exact_inputs = true,
            "--no-cache" => no_cache = true,
            "--trace" => {
                let path = PathBuf::from(args.next().ok_or("--trace requires a file")?);
                trace_path.get_or_insert(path);
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
    Ok(Command::Build(Box::new(BuildRequest {
        command,
        project: project.ok_or("a project manifest is required")?,
        defines,
        workers,
        engine_template,
        bootstrap_catalog,
        progress_enabled,
        output_store,
        exact_inputs,
        no_cache,
        cache_root: Some(crate::request::client_cache_root()?),
        record_inputs,
        replay_inputs,
        artifact_directory,
        no_daemon,
        trace_path,
    })))
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

#[cfg(test)]
#[path = "cli_tests.rs"]
mod tests;
