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
        "prepare-query" => BuildCommand::PrepareQuery,
        _ => return Err("expected analyze, compile or prepare-query".into()),
    };
    let mut project = None;
    let mut policy_inputs = None;
    let mut source_questions = None;
    let mut diagnostic_declarations = false;
    let mut timeout_seconds = None;
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
    let mut warnings = crate::diagnostics::WarningPolicy::default();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--diagnostic-declarations" => diagnostic_declarations = true,
            "--source-questions-json" => {
                if source_questions.is_some() {
                    return Err("--source-questions-json accepts one roster".into());
                }
                let value = args
                    .next()
                    .ok_or("--source-questions-json requires inline typed questions JSON")?;
                if value.len() > 65536 {
                    return Err("source questions exceed request bound".into());
                }
                let questions: Vec<crate::daemon::query::QueryItem> = serde_json::from_str(&value)?;
                crate::request::validate_source_question_roster(&questions)?;
                source_questions = Some(questions);
            }
            "--request-timeout-seconds" => {
                if timeout_seconds.is_some() {
                    return Err("--request-timeout-seconds accepts one budget".into());
                }
                let text = args
                    .next()
                    .ok_or("--request-timeout-seconds requires an integer in 1..300")?;
                if text.is_empty() || !text.bytes().all(|byte| byte.is_ascii_digit()) {
                    return Err("--request-timeout-seconds requires an integer in 1..300".into());
                }
                let seconds = text
                    .parse::<u16>()
                    .map_err(|_| "--request-timeout-seconds requires an integer in 1..300")?;
                crate::request::validate_timeout_seconds(Some(seconds))?;
                timeout_seconds = Some(seconds);
            }
            "--policy-inputs-json" => {
                if policy_inputs.is_some() {
                    return Err("--policy-inputs-json accepts one contract".into());
                }
                let value = args
                    .next()
                    .ok_or("--policy-inputs-json requires inline JSON")?;
                let request: crate::policy_request::PolicyInputRequest =
                    serde_json::from_str(&value)?;
                request.clone().admit()?;
                policy_inputs = Some(request);
            }
            "--warnings-as-errors" => warnings.as_errors = true,
            "--ignore-warning" => {
                let codes = args
                    .next()
                    .ok_or("--ignore-warning requires a warning code")?;
                warnings.ignored.extend(
                    codes
                        .split(',')
                        .map(str::trim)
                        .filter(|code| !code.is_empty())
                        .map(str::to_owned),
                );
            }
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
        source_questions,
        diagnostic_declarations,
        timeout_seconds,
        policy_inputs,
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
        warnings,
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

// Deliberately absent from normal help, BuildRequest and daemon/query authority.
// This opt-in diagnostic shares the exact existing private census implementation.
fn original_grammar_census_arguments(arguments: &[String]) -> Result<(PathBuf, usize, usize), String> {
    if arguments.len() != 4 || arguments[0] != "--original-grammar-census" {
        return Err("usage: dmbc --original-grammar-census <absolute.dme> <start> <count:1..1024>".into());
    }
    let project = PathBuf::from(&arguments[1]);
    let decimal = |text: &str| !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit());
    if !project.is_absolute() || !decimal(&arguments[2]) || !decimal(&arguments[3]) {
        return Err("Original grammar census requires an absolute project and unsigned decimal bounds".into());
    }
    let start = arguments[2].parse::<usize>().map_err(|_| "Original grammar census start is out of range")?;
    let count = arguments[3].parse::<usize>().map_err(|_| "Original grammar census count is out of range")?;
    if !(1..=1024).contains(&count) || start.checked_add(count).is_none() {
        return Err("Original grammar census count must be 1..1024 and start+count must not overflow".into());
    }
    Ok((project, start, count))
}

#[doc(hidden)]
pub fn run_original_grammar_census(arguments: &[String]) -> Result<(), String> {
    let (project, start, count) = original_grammar_census_arguments(arguments)?;
    crate::query_db::run_original_grammar_census(project, start, count)
}
