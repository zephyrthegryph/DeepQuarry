//! Offline canonical procedure coverage audit. Never publishes or runs DMB/RSC.
use dm_compiler::{bootstrap::audit_canonical_lowering, frontend::OutlineSession, ProjectSession};
use serde_json::json;
use std::{collections::BTreeMap, fs, path::PathBuf, time::Instant};

fn run() -> Result<(), String> {
    let _budget = dm_host::install_process_budget().map_err(|e| e.to_string())?;
    let mut args = std::env::args().skip(1);
    let (mut project, mut output, mut builtins) = (None, None, None);
    let mut defines = BTreeMap::new();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--project" => project = Some(PathBuf::from(args.next().ok_or("missing project")?)),
            "--output" => output = Some(PathBuf::from(args.next().ok_or("missing output")?)),
            "--builtins" => builtins = Some(PathBuf::from(args.next().ok_or("missing builtin image")?)),
            _ if arg.starts_with("-D") => {
                let (name, value) = arg[2..].split_once('=').unwrap_or((&arg[2..], "1"));
                defines.insert(name.to_owned(), value.to_owned());
            }
            _ => return Err("usage: canonical_lowering_audit --project PRIVATE.dme --output NEW_DIR [--builtins image] [-DNAME]".into()),
        }
    }
    let project = project
        .ok_or("--project required")?
        .canonicalize()
        .map_err(|e| e.to_string())?;
    let output = output.ok_or("--output required")?;
    if output.exists() {
        return Err("audit output directory must be new".into());
    }
    fs::create_dir_all(&output).map_err(|e| e.to_string())?;
    std::env::set_var("DM_COMPILER_CACHE_ROOT", output.join("cache"));
    let builtin = match builtins {
        Some(path) => fs::read(path).map_err(|e| e.to_string())?,
        None => include_bytes!("../../../fixtures/native_template.bin").to_vec(),
    };
    let start = Instant::now();
    let expanded = ProjectSession::from_disk(project.clone(), defines).preprocess_incremental();
    let mut frontend = OutlineSession::new(Some(output.join("frontend")));
    let audit = audit_canonical_lowering(&project, &expanded, &builtin, &mut frontend, 2)?;
    let groups = audit
        .lowering
        .groups
        .iter()
        .map(|(reason, group)| {
            json!({
                "reason": reason, "count": group.count,
                "samples": group.samples.iter().map(|sample| json!({
                    "procedure": sample.procedure, "span": [sample.span.start, sample.span.end],
                    "diagnostic": sample.statement,
                })).collect::<Vec<_>>(),
            })
        })
        .collect::<Vec<_>>();
    let report = json!({
        "format_version": 1, "coverage": "authored procedure lowering; successful bodies linked, lowering errors continue; excludes resource existence, dynamic initializers and output publication",
        "expected_procedures": audit.expected_procedures, "procedures": audit.lowering.procedures,
        "passed": audit.lowering.passed, "failed": audit.lowering.failed, "error_count": audit.lowering.error_count,
        "cache_hits": audit.cache_hits, "cache_misses": audit.cache_misses,
        "truncated_texts": audit.truncated_texts, "seconds": start.elapsed().as_secs_f64(), "groups": groups,
    });
    fs::write(
        output.join("audit.json"),
        serde_json::to_vec_pretty(&report).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    println!("canonical lowering audit: {}/{} procedures, {} passed, {} failed, {} errors; cache {}/{} hits/misses; {:.3}s",
        audit.lowering.procedures, audit.expected_procedures, audit.lowering.passed,
        audit.lowering.failed, audit.lowering.error_count, audit.cache_hits, audit.cache_misses, start.elapsed().as_secs_f64());
    for (reason, group) in &audit.lowering.groups {
        println!("{}: {}", group.count, reason);
        for sample in &group.samples {
            println!("  {}: {}", sample.procedure, sample.statement);
        }
    }
    if audit.lowering.failed > 0 {
        return Err("canonical lowering gaps found (no artifact emitted)".into());
    }
    Ok(())
}
fn main() {
    if let Err(error) = run() {
        eprintln!("canonical_lowering_audit: {error}");
        std::process::exit(1);
    }
}
