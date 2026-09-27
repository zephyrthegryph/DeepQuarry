use dm_health::Finding;
use std::collections::{BTreeMap, HashMap};
use std::env;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::time::Instant;

fn main() {
    if let Err(error) = run() {
        eprintln!("dm-health: {error}");
        std::process::exit(2);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = env::args().skip(1);
    let command = args.next();
    if command.as_deref() == Some("ci-suite") {
        return dm_health::suite::run(&env::current_dir()?);
    }
    if command.as_deref() == Some("serve") {
        let mut history = PathBuf::from("tools/dm-health/target/history");
        let mut root = PathBuf::from(".");
        let mut port = 8765;
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--history-dir" => {
                    history = PathBuf::from(args.next().ok_or("--history-dir requires a path")?)
                }
                "--port" => port = args.next().ok_or("--port requires a number")?.parse()?,
                "--root" => root = PathBuf::from(args.next().ok_or("--root requires a path")?),
                other => return Err(format!("unknown serve argument {other}").into()),
            }
        }
        return dm_health::server::serve(&root, &history, port)
            .map_err(|error| error.to_string().into());
    }
    let mut args = env::args().skip(1);
    let run_started = Instant::now();
    let mut root = PathBuf::from(".");
    let mut json = false;
    let mut summary = false;
    let mut baseline = None;
    let mut write_baseline = None;
    let mut fail_on_new = false;
    let mut ast = None;
    let mut report = None;
    let mut history_dir = None;
    let mut cache_dir = None;
    let mut strict_types = false;
    let mut strict_modules = Vec::new();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--root" => root = PathBuf::from(args.next().ok_or("--root requires a path")?),
            "--ast" => ast = Some(PathBuf::from(args.next().ok_or("--ast requires a path")?)),
            "--json" => json = true,
            "--report" => {
                report = Some(PathBuf::from(
                    args.next().ok_or("--report requires a path")?,
                ))
            }
            "--history-dir" => {
                history_dir = Some(PathBuf::from(
                    args.next().ok_or("--history-dir requires a path")?,
                ))
            }
            "--cache-dir" => {
                cache_dir = Some(PathBuf::from(
                    args.next().ok_or("--cache-dir requires a path")?,
                ))
            }
            "--summary" => summary = true,
            "--baseline" => {
                baseline = Some(PathBuf::from(
                    args.next().ok_or("--baseline requires a path")?,
                ))
            }
            "--write-baseline" => {
                write_baseline = Some(PathBuf::from(
                    args.next().ok_or("--write-baseline requires a path")?,
                ))
            }
            "--fail-on-new" => fail_on_new = true,
            "--strict-types" => strict_types = true,
            "--strict-module" => strict_modules.push(
                args.next()
                    .ok_or("--strict-module requires a README module path")?
                    .replace('\\', "/")
                    .trim_end_matches('/')
                    .to_owned(),
            ),
            "--help" | "-h" => {
                println!("dm-health --ast OPENDREAM_AST_JSONL [--root PATH] [--strict-types] [--strict-module README_DIR] [--json|--summary] [--baseline FILE] [--write-baseline FILE] [--fail-on-new] [--report FILE] [--history-dir DIR] [--cache-dir DIR]");
                return Ok(());
            }
            other => return Err(format!("unknown argument {other}").into()),
        }
    }
    let ast = ast.ok_or("--ast is required; run the OpenDream bridge first")?;
    let root = root.canonicalize()?;
    dm_health::symbols::Symbols::verify_export_file(&ast)?;
    let mut ast_reader = BufReader::new(fs::File::open(&ast)?);
    let mut meta_line = String::new();
    ast_reader.read_line(&mut meta_line)?;
    let meta = dm_health::symbols::Symbols::collect(meta_line.as_bytes(), &[])?;
    meta.verify_sources()?;
    let included_paths = meta.included_dm_files(&root)?;
    for module in &strict_modules {
        let directory = root.join(module);
        if !["README.md", "readme.md", "Readme.md"]
            .iter()
            .any(|name| directory.join(name).is_file())
        {
            return Err(format!("{module} is not a README-defined module").into());
        }
    }
    let cache_key =
        if let Some(directory) = cache_dir.as_deref().filter(|_| write_baseline.is_none()) {
            let key = dm_health::cache::key(
                &root,
                &ast,
                baseline.as_deref(),
                strict_types,
                &strict_modules,
                &included_paths,
            )?;
            if let Some(cached) = dm_health::cache::load(directory, &key) {
                dm_health::symbols::Symbols::verify_export_file(&ast)?;
                meta.verify_sources()?;
                if dm_health::cache::key(
                    &root,
                    &ast,
                    baseline.as_deref(),
                    strict_types,
                    &strict_modules,
                    &included_paths,
                )? == key
                {
                    return emit_cached(
                        cached,
                        report,
                        history_dir,
                        json,
                        summary,
                        fail_on_new,
                        run_started.elapsed().as_millis(),
                    );
                }
            }
            Some(key)
        } else {
            None
        };
    let included: std::collections::HashSet<_> = included_paths
        .iter()
        .map(|path| {
            path.strip_prefix(&root)
                .unwrap_or(path)
                .to_string_lossy()
                .replace('\\', "/")
        })
        .collect();
    let type_selection = dm_health::typing::Selection {
        all: strict_types,
        modules: strict_modules,
        files: Some(included),
    };
    let mut phase_times = BTreeMap::<&str, u128>::new();
    let mut phase_started = Instant::now();
    let (contracts, source_findings) = dm_health::load_source_contracts(&root, &included_paths)?;
    phase_times.insert("source_contracts", phase_started.elapsed().as_millis());
    phase_started = Instant::now();
    let symbols =
        dm_health::symbols::Symbols::collect(BufReader::new(fs::File::open(&ast)?), &contracts)?;
    symbols.verify_sources()?;
    phase_times.insert("symbols", phase_started.elapsed().as_millis());
    phase_started = Instant::now();
    let mut findings = dm_health::ast::analyze_reader_with_symbols_in_files(
        BufReader::new(fs::File::open(&ast)?),
        &contracts,
        &symbols,
        type_selection.files.as_ref(),
    )?;
    phase_times.insert("legacy_diagnostics", phase_started.elapsed().as_millis());
    let mut type_coverage = dm_health::typing::TypeCoverage::default();
    let mut strict_failed = false;
    if type_selection.all || !type_selection.modules.is_empty() {
        phase_started = Instant::now();
        let (strict_findings, coverage) = dm_health::typing::analyze_with_cache(
            BufReader::new(fs::File::open(&ast)?),
            BufReader::new(fs::File::open(&ast)?),
            BufReader::new(fs::File::open(&ast)?),
            &symbols,
            &contracts,
            &type_selection,
            cache_dir.as_deref(),
        )?;
        strict_failed = strict_findings
            .iter()
            .any(|finding| finding.severity == "error");
        findings.extend(strict_findings);
        type_coverage = coverage;
        phase_times.insert("strict_types", phase_started.elapsed().as_millis());
    }
    phase_started = Instant::now();
    let mut metrics = dm_health::metrics::collect_in_files(
        BufReader::new(fs::File::open(&ast)?),
        &root,
        type_selection.files.as_ref(),
    )?;
    for file in &mut metrics.files {
        let source = root.join(&file.path);
        if source.exists() {
            let bytes = fs::read(source)?;
            (
                file.lines,
                file.code_lines,
                file.comment_lines,
                file.blank_lines,
            ) = dm_health::metrics::source_lines(&bytes);
        }
    }
    findings.extend(dm_health::metrics::diagnostics(&metrics));
    findings.extend(dm_health::metrics::documentation_diagnostics(
        &metrics, &root,
    ));
    phase_times.insert("metrics", phase_started.elapsed().as_millis());
    findings.extend(source_findings);
    dm_health::symbols::Symbols::verify_export_file(&ast)?;
    symbols.verify_sources()?;
    if let Some(path) = write_baseline {
        let fingerprints: Vec<_> = findings.iter().map(Finding::fingerprint).collect();
        fs::write(path, serde_json::to_string_pretty(&fingerprints)?)?;
    }
    phase_started = Instant::now();
    let mut known = HashMap::<String, usize>::new();
    if let Some(path) = baseline.as_deref() {
        for fingerprint in serde_json::from_str::<Vec<String>>(&fs::read_to_string(path)?)? {
            *known.entry(fingerprint).or_default() += 1;
        }
    }
    let mut new = Vec::new();
    for finding in &findings {
        let count = known.entry(finding.fingerprint()).or_default();
        if *count == 0 {
            new.push(finding);
        } else {
            *count -= 1;
        }
    }
    let mut file_finding_counts = HashMap::<&str, usize>::new();
    for finding in &findings {
        *file_finding_counts.entry(&finding.path).or_default() += 1;
    }
    for file in &mut metrics.files {
        file.findings = file_finding_counts
            .get(file.path.as_str())
            .copied()
            .unwrap_or(0);
    }
    dm_health::metrics::finalize_sources(&mut metrics, &root);
    dm_health::metrics::finalize_coupling(&mut metrics, &root)?;
    let module_index: HashMap<&str, usize> = metrics
        .modules
        .iter()
        .enumerate()
        .map(|(index, module)| (module.name.as_str(), index))
        .collect();
    let mut module_finding_counts = vec![0usize; metrics.modules.len()];
    for finding in &findings {
        let mut parent = finding.path.as_str();
        while let Some((directory, _)) = parent.rsplit_once('/') {
            if let Some(&index) = module_index.get(directory) {
                module_finding_counts[index] += 1;
            }
            parent = directory;
        }
    }
    for (module, count) in metrics.modules.iter_mut().zip(module_finding_counts) {
        module.findings = count;
    }
    phase_times.insert("finalize", phase_started.elapsed().as_millis());
    if let Some(expected) = &cache_key {
        let actual = dm_health::cache::key(
            &root,
            &ast,
            baseline.as_deref(),
            strict_types,
            &type_selection.modules,
            &included_paths,
        )?;
        if &actual != expected {
            return Err("analysis inputs changed during the scan; rerun it".into());
        }
    }
    if report.is_some() || history_dir.is_some() || cache_key.is_some() {
        let phase_started = Instant::now();
        let root_causes =
            dm_health::provenance::categorize_with_coverage(&findings, &type_coverage);
        phase_times.insert("root_causes", phase_started.elapsed().as_millis());
        let now = chrono::Utc::now();
        let snapshot = serde_json::json!({
            "schema_version": 2,
            "generated_at": now.to_rfc3339(),
            "analysis_reused": false,
            "analysis_cache_key": cache_key,
            "rust_analysis_ms": run_started.elapsed().as_millis(),
            "analysis_phases_ms": phase_times,
            "project": "CHOMPStation2",
            "counts": {
                "errors": findings.iter().filter(|f| f.severity == "error").count(),
                "warnings": findings.iter().filter(|f| f.severity == "warning").count(),
                "info": findings.iter().filter(|f| f.severity == "info").count(),
                "new": new.len()
            },
            "metrics": metrics,
            "type_coverage": type_coverage,
            "root_causes": root_causes,
            "findings": findings,
            "new_fingerprints": new.iter().map(|finding| finding.fingerprint()).collect::<Vec<_>>()
        });
        if let (Some(directory), Some(key)) = (cache_dir.as_deref(), cache_key.as_deref()) {
            dm_health::cache::store_snapshot(directory, key, strict_failed, &snapshot)?;
        }
        let payload = serde_json::to_vec_pretty(&snapshot)?;
        if let Some(path) = report {
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::write(path, &payload)?;
        }
        if let Some(dir) = history_dir {
            fs::create_dir_all(&dir)?;
            fs::write(
                dir.join(format!(
                    "dm-health-{}.json",
                    now.format("%Y%m%dT%H%M%S%.3fZ")
                )),
                &payload,
            )?;
        }
    }
    if json {
        println!("{}", serde_json::to_string_pretty(&findings)?);
    } else if summary {
        let errors = findings.iter().filter(|f| f.severity == "error").count();
        let warnings = findings.iter().filter(|f| f.severity == "warning").count();
        let information = findings.len() - errors - warnings;
        println!(
            "dm-health: {errors} errors, {warnings} warnings, {information} informational findings; {} new", new.len()
        );
    } else {
        for finding in &new {
            println!(
                "{}:{}: {} [{}] {}",
                finding.path, finding.line, finding.severity, finding.rule, finding.message
            );
        }
        eprintln!("dm-health: {} findings, {} new", findings.len(), new.len());
    }
    if strict_failed || (fail_on_new && !new.is_empty()) {
        std::process::exit(1);
    }
    Ok(())
}

fn emit_cached(
    cached: dm_health::cache::CachedReport,
    report: Option<PathBuf>,
    history_dir: Option<PathBuf>,
    json: bool,
    summary: bool,
    fail_on_new: bool,
    duration_ms: u128,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut snapshot = cached.snapshot;
    let now = chrono::Utc::now();
    snapshot["generated_at"] = serde_json::json!(now.to_rfc3339());
    snapshot["analysis_reused"] = serde_json::json!(true);
    snapshot["rust_analysis_ms"] = serde_json::json!(duration_ms);
    let payload = serde_json::to_vec_pretty(&snapshot)?;
    if let Some(path) = report {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, &payload)?;
    }
    if let Some(directory) = history_dir {
        fs::create_dir_all(&directory)?;
        fs::write(
            directory.join(format!(
                "dm-health-{}.json",
                now.format("%Y%m%dT%H%M%S%.3fZ")
            )),
            &payload,
        )?;
    }
    let findings = snapshot["findings"]
        .as_array()
        .ok_or("cached report has no findings")?;
    let new_count = snapshot["counts"]["new"].as_u64().unwrap_or(0) as usize;
    if json {
        println!("{}", serde_json::to_string_pretty(findings)?);
    } else if summary {
        let counts = &snapshot["counts"];
        println!(
            "dm-health: {} errors, {} warnings, {} informational findings; {} new (Rust cache hit)",
            counts["errors"].as_u64().unwrap_or(0),
            counts["warnings"].as_u64().unwrap_or(0),
            counts["info"].as_u64().unwrap_or(0),
            new_count
        );
    } else {
        let mut remaining = HashMap::<String, usize>::new();
        for fingerprint in snapshot["new_fingerprints"]
            .as_array()
            .into_iter()
            .flatten()
        {
            if let Some(fingerprint) = fingerprint.as_str() {
                *remaining.entry(fingerprint.into()).or_default() += 1;
            }
        }
        for finding in findings {
            let fingerprint = format!(
                "{}:{}:{}",
                finding["rule"].as_str().unwrap_or(""),
                finding["path"].as_str().unwrap_or(""),
                finding["message"].as_str().unwrap_or("")
            );
            let count = remaining.entry(fingerprint).or_default();
            if *count == 0 {
                continue;
            }
            *count -= 1;
            println!(
                "{}:{}: {} [{}] {}",
                finding["path"].as_str().unwrap_or(""),
                finding["line"].as_u64().unwrap_or(1),
                finding["severity"].as_str().unwrap_or(""),
                finding["rule"].as_str().unwrap_or(""),
                finding["message"].as_str().unwrap_or("")
            );
        }
        eprintln!(
            "dm-health: {} findings, {} new (Rust cache hit)",
            findings.len(),
            new_count
        );
    }
    if cached.strict_failed || (fail_on_new && new_count > 0) {
        std::process::exit(1);
    }
    Ok(())
}
