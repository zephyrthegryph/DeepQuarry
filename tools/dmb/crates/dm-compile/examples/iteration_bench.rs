//! Production Coordinator iteration benchmark. Never starts DreamDaemon.
//! One bounded compiler process runs at a time; owned source overlays are removed.
use dm_compiled::{Coordinator, Request, Response, SessionKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs::{self, OpenOptions},
    io::{self, Read, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

fn error(message: impl ToString) -> io::Error {
    io::Error::other(message.to_string())
}
fn write_json(path: &Path, value: &impl Serialize) -> io::Result<()> {
    serde_json::to_writer_pretty(fs::File::create(path)?, value).map_err(error)
}
fn file_digest(path: &Path) -> io::Result<String> {
    let mut file = fs::File::open(path)?;
    let mut hash = Sha256::new();
    let mut buffer = [0; 64 * 1024];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hash.update(&buffer[..count]);
    }
    Ok(format!("{:x}", hash.finalize()))
}

struct OwnedProject {
    manifest: PathBuf,
    overlay: PathBuf,
    prefix: String,
    created: Vec<PathBuf>,
}
impl OwnedProject {
    fn new(original: &Path) -> io::Result<Self> {
        let directory = original
            .parent()
            .ok_or_else(|| error("project has no parent"))?;
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(error)?
            .as_nanos();
        let prefix = format!("__dm_iteration_{}_{}", std::process::id(), nonce);
        let mut owned = Self {
            manifest: directory.join(format!("{prefix}.dme")),
            overlay: directory.join(format!("{prefix}.dm")),
            prefix,
            created: Vec::new(),
        };
        // Preserve the original manifest's byte encoding and relative include paths.
        let mut bytes = fs::read(original)?;
        bytes.extend_from_slice(format!("\n#include \"{}.dm\"\n", owned.prefix).as_bytes());
        let mut manifest = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&owned.manifest)?;
        owned.created.push(owned.manifest.clone());
        manifest.write_all(&bytes)?;
        let mut overlay = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&owned.overlay)?;
        owned.created.push(owned.overlay.clone());
        overlay.write_all(overlay_source(&owned.prefix, "baseline").as_bytes())?;
        // Fixtures share the unique owned prefix and are never game assets.
        // Create both eagerly so the add case measures discovery/reference work,
        // while the baseline archive contains only the first referenced file.
        for (suffix, bytes) in [("asset.txt", BASE_ASSET), ("added.txt", ADDED_ASSET)] {
            let path = directory.join(format!("{}_{suffix}", owned.prefix));
            let mut file = OpenOptions::new().write(true).create_new(true).open(&path)?;
            owned.created.push(path);
            file.write_all(bytes)?;
        }
        Ok(owned)
    }
}
impl Drop for OwnedProject {
    fn drop(&mut self) {
        for path in &self.created {
            let _ = fs::remove_file(path);
        }
    }
}
const BASE_ASSET: &[u8] = b"iteration resource baseline\n";
const EDITED_ASSET: &[u8] = b"iteration resource edited!!\n";
const ADDED_ASSET: &[u8] = b"iteration additional resource\n";
fn overlay_source(prefix: &str, case: &str) -> String {
    let default = if case == "change-default" { 2 } else { 1 };
    let body = match case {
        "body-edit" => 2,
        "cold-body-edit" => 303,
        _ => 1,
    };
    let mut source = format!("/datum/{prefix}\n    var/value = {default}\n    var/fixture_asset = '{prefix}_asset.txt'\n");
    if case == "add-resource" {
        source.push_str(&format!("    var/additional_asset = '{prefix}_added.txt'\n"));
    }
    if case == "add-var" {
        source.push_str("    var/additional = 7\n");
    }
    source.push_str(&format!("/proc/{prefix}_value()\n    return {body}\n"));
    if case == "add-proc" {
        source.push_str(&format!("/proc/{prefix}_added()\n    return 9\n"));
    }
    source
}

fn write_overlay(path: &Path, prefix: &str, case: &str) -> io::Result<()> {
    let source = overlay_source(prefix, case);
    // A cold unchanged probe must preserve filesystem proof clocks too, rather
    // than measuring an identical-text rewrite as an input edit.
    if fs::read(path).is_ok_and(|existing| existing == source.as_bytes()) {
        return Ok(());
    }
    fs::write(path, source)
}
fn write_fixture(config: &Configuration, case: &str) -> io::Result<()> {
    let directory = config.manifest.parent().ok_or_else(|| error("fixture has no parent"))?;
    let path = directory.join(format!("{}_asset.txt", config.prefix));
    let expected = if case == "asset-edit" { EDITED_ASSET } else { BASE_ASSET };
    if !fs::read(&path).is_ok_and(|existing| existing == expected) {
        fs::write(path, expected)?;
    }
    write_overlay(&config.overlay, &config.prefix, case)
}

#[derive(Clone, Serialize, Deserialize)]
struct Configuration {
    original: PathBuf,
    manifest: PathBuf,
    overlay: PathBuf,
    prefix: String,
    builtins: PathBuf,
    cache: PathBuf,
    output: PathBuf,
    defines: Vec<(String, String)>,
    cases: Vec<String>,
    workers: usize,
    memory_mib: usize,
}
#[derive(Serialize, Deserialize)]
struct Measurement {
    case: String,
    coordinator_seconds: f64,
    receipt_hash_seconds: f64,
    response: Response,
    dmb_sha256: Option<String>,
    rsc_sha256: Option<String>,
    #[serde(default)]
    rsc_matches_baseline: Option<bool>,
    #[serde(default)]
    trace: Vec<String>,
    #[serde(default)]
    stages: Vec<Stage>,
}
#[derive(Serialize, Deserialize)]
struct Stage {
    name: String,
    elapsed_seconds: f64,
}
#[derive(Serialize)]
struct Phase {
    name: String,
    process_seconds: f64,
    success: bool,
    measurements: Vec<Measurement>,
    stderr: PathBuf,
    error: Option<String>,
}
#[derive(Serialize)]
struct Report {
    format_version: u32,
    mode: &'static str,
    compiler: &'static str,
    fallback_count: usize,
    compiler_sha256: String,
    builtins_sha256: String,
    configuration: Configuration,
    phases: Vec<Phase>,
    success: bool,
    timing_contract: &'static str,
}

fn measure(
    coordinator: &mut Coordinator,
    config: &Configuration,
    key: &SessionKey,
    case: &str,
) -> io::Result<Measurement> {
    println!("iteration: begin {case}");
    eprintln!("ITERATION_BEGIN|{case}");
    let started = Instant::now();
    let response = coordinator.handle(Request::BuildProject {
        key: key.clone(),
        builtins: config.builtins.clone(),
        output_root: config.output.clone(),
    });
    let coordinator_seconds = started.elapsed().as_secs_f64();
    eprintln!("ITERATION_END|{case}");
    // Hash receipt files after the timer, using bounded streaming buffers.
    let hash_started = Instant::now();
    let (dmb_sha256, rsc_sha256) = if let Some(build) = &response.build {
        (
            Some(file_digest(&build.dmb)?),
            Some(file_digest(&build.rsc)?),
        )
    } else {
        (None, None)
    };
    println!(
        "iteration: {case}: {coordinator_seconds:.6}s, ok {}, cache {}, lowered {}, reused {}",
        response.ok,
        response.build.as_ref().is_some_and(|build| build.cache_hit),
        response
            .build
            .as_ref()
            .map_or(0, |build| build.lowered_procs),
        response
            .build
            .as_ref()
            .map_or(0, |build| build.reused_procs)
    );
    Ok(Measurement {
        case: case.into(),
        coordinator_seconds,
        receipt_hash_seconds: hash_started.elapsed().as_secs_f64(),
        response,
        dmb_sha256,
        rsc_sha256,
        rsc_matches_baseline: None,
        trace: Vec::new(),
        stages: Vec::new(),
    })
}
fn child(config_file: &Path, phase: &str, results_file: &Path) -> io::Result<()> {
    let config: Configuration = serde_json::from_slice(&fs::read(config_file)?).map_err(error)?;
    std::env::set_var("DM_COMPILER_CACHE_ROOT", &config.cache);
    std::env::set_var("DM_COMPILER_WORKERS", config.workers.to_string());
    std::env::set_var("DM_MEMORY_LIMIT_MB", config.memory_mib.to_string());
    std::env::set_var("DM_BUILD_TRACE", "1");
    let _budget = dm_host::install_process_budget()?;
    let key = SessionKey::new(
        config.manifest.parent().unwrap(),
        &config.manifest,
        "516.1687",
        config.defines.clone(),
        "canonical",
    )?;
    let mut coordinator = Coordinator::new(config.cache.clone())?;
    let mut measurements = Vec::new();
    let mut baseline_rsc = None;
    let cases = match phase {
        "retained" => config.cases.clone(),
        "cold-cached" => vec!["cold-process-cached".into()],
        "cold-body-edit" => vec!["cold-body-edit".into()],
        _ => return Err(error("unknown child phase")),
    };
    for case in &cases {
        if case != "unchanged" && case != "cold-process-cached" {
            write_fixture(&config, case)?;
        }
        let mut result = measure(&mut coordinator, &config, &key, case)?;
        if case == "baseline" { baseline_rsc = result.rsc_sha256.clone(); }
        result.rsc_matches_baseline = baseline_rsc.as_ref().zip(result.rsc_sha256.as_ref()).map(|(a, b)| a == b);
        let expects_changed_archive = matches!(case.as_str(), "asset-edit" | "add-resource");
        let archive_valid = result.rsc_matches_baseline.is_none_or(|same| same == !expects_changed_archive);
        let success = result.response.ok;
        measurements.push(result);
        write_json(results_file, &measurements)?;
        if !success {
            return Err(error(format!(
                "native build failed: {case}; see typed response"
            )));
        }
        if !archive_valid { return Err(error(format!("resource archive identity mismatch for {case}; see recorded SHA-256 receipts"))); }
        if phase == "retained" && case != "baseline" && case != "unchanged" {
            // Each edit starts from the same baseline. Record the real revert
            // request rather than hiding extra compilation between measurements.
            write_fixture(&config, "baseline")?;
            let mut result = measure(&mut coordinator, &config, &key, &format!("revert-{case}"))?;
            result.rsc_matches_baseline = baseline_rsc.as_ref().zip(result.rsc_sha256.as_ref()).map(|(a, b)| a == b);
            let archive_valid = result.rsc_matches_baseline != Some(false);
            let success = result.response.ok;
            measurements.push(result);
            write_json(results_file, &measurements)?;
            if !success {
                return Err(error(format!("baseline revert failed after {case}")));
            }
            if !archive_valid { return Err(error(format!("baseline archive identity changed after reverting {case}"))); }
        }
    }
    Ok(())
}

fn attach_trace(measurements: &mut [Measurement], path: &Path) -> io::Result<()> {
    let mut bytes = Vec::new();
    fs::File::open(path)?
        .take(32 * 1024 * 1024 + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() > 32 * 1024 * 1024 {
        return Err(error("trace exceeds 32MiB report bound"));
    }
    let text = String::from_utf8_lossy(&bytes);
    let mut active = None;
    for line in text.lines() {
        if let Some(case) = line.strip_prefix("ITERATION_BEGIN|") {
            active = measurements.iter().position(|value| value.case == case);
            continue;
        }
        if line.starts_with("ITERATION_END|") {
            active = None;
            continue;
        }
        let Some(index) = active else {
            continue;
        };
        measurements[index].trace.push(line.to_owned());
        if let Some(line) = line.strip_prefix("dm-compiled ") {
            if let Some((name, elapsed)) = line.rsplit_once(": ") {
                if let Some(seconds) = elapsed
                    .strip_suffix('s')
                    .and_then(|value| value.parse().ok())
                {
                    measurements[index].stages.push(Stage {
                        name: name.into(),
                        elapsed_seconds: seconds,
                    });
                }
            }
        }
    }
    Ok(())
}
fn run_phase(
    executable: &Path,
    config_file: &Path,
    out: &Path,
    name: &str,
    timeout: Duration,
) -> io::Result<Phase> {
    let stderr = out.join(format!("{name}.stderr.log"));
    let results = out.join(format!("{name}.measurements.json"));
    let mut command = Command::new(executable);
    command
        .arg("--child")
        .arg(config_file)
        .arg(name)
        .arg(&results)
        .stdout(Stdio::inherit())
        .stderr(Stdio::from(fs::File::create(&stderr)?));
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }
    let started = Instant::now();
    let mut process = command.spawn()?;
    let mut phase_error = None;
    let status = loop {
        match process.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {}
            Err(error) => {
                let _ = process.kill();
                let _ = process.wait();
                return Err(error);
            }
        }
        if started.elapsed() >= timeout {
            let _ = process.kill();
            phase_error = Some(format!("{name} exceeded {}s timeout", timeout.as_secs()));
            break process.wait()?;
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    let process_seconds = started.elapsed().as_secs_f64();
    let mut measurements: Vec<Measurement> = if results.exists() {
        serde_json::from_slice(&fs::read(&results)?).map_err(error)?
    } else {
        Vec::new()
    };
    if let Err(error) = attach_trace(&mut measurements, &stderr) {
        phase_error = Some(error.to_string());
    }
    let success = status.success()
        && phase_error.is_none()
        && !measurements.is_empty()
        && measurements.iter().all(|value| value.response.ok);
    if !success && phase_error.is_none() {
        phase_error = Some(format!("{name} exited with {status}"));
    }
    Ok(Phase {
        name: name.into(),
        process_seconds,
        success,
        measurements,
        stderr,
        error: phase_error,
    })
}

fn run() -> io::Result<()> {
    let mut args = std::env::args().skip(1).peekable();
    if args.next_if(|value| value == "--child").is_some() {
        let config = args.next().ok_or_else(|| error("missing child config"))?;
        let phase = args.next().ok_or_else(|| error("missing child phase"))?;
        let results = args.next().ok_or_else(|| error("missing child results"))?;
        return child(Path::new(&config), &phase, Path::new(&results));
    }
    let mut project = None;
    let mut output = None;
    let mut builtins = None;
    let mut cache = None;
    let mut defines = BTreeMap::new();
    let mut workers = 2usize;
    let mut memory_mib = 2048usize;
    let mut timeout = 1800u64;
    let mut cold = true;
    let mut cold_body = false;
    let mut cases: Vec<String> = [
        "baseline",
        "unchanged",
        "body-edit",
        "add-proc",
        "add-var",
        "change-default",
        "asset-edit",
        "add-resource",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect();
    while let Some(arg) = args.next() {
        let value = |args: &mut std::iter::Peekable<std::iter::Skip<std::env::Args>>| {
            args.next()
                .ok_or_else(|| error(format!("missing {arg} value")))
        };
        match arg.as_str() {
            "--project" => project = Some(PathBuf::from(value(&mut args)?)),
            "--output" => output = Some(PathBuf::from(value(&mut args)?)),
            "--builtins" => builtins = Some(PathBuf::from(value(&mut args)?)),
            "--cache-root" => cache = Some(PathBuf::from(value(&mut args)?)),
            "--workers" => workers = value(&mut args)?.parse().map_err(error)?,
            "--memory-mib" => memory_mib = value(&mut args)?.parse().map_err(error)?,
            "--timeout-seconds" => timeout = value(&mut args)?.parse().map_err(error)?,
            "--cases" => cases = value(&mut args)?.split(',').map(str::to_owned).collect(),
            "--skip-cold" => cold = false,
            "--cold-body-edit" => cold_body = true,
            _ if arg.starts_with("-D") => {
                let definition = if arg == "-D" { value(&mut args)? } else { arg[2..].to_owned() };
                let (name, replacement) = definition.split_once('=').unwrap_or((&definition, "1"));
                if name.is_empty() || !name.chars().enumerate().all(|(index, character)| {
                    character == '_' || character.is_ascii_alphabetic() || index != 0 && character.is_ascii_digit()
                }) || replacement.contains(['\r','\n']) || defines.insert(name.to_owned(), replacement.to_owned()).is_some() {
                    return Err(error("invalid or duplicate build define"));
                }
            }
            _ => return Err(error("usage: iteration_bench --project REAL.dme --output NEW_DIR [--builtins SCHEMA.bin] [--cache-root DIR] [-DNAME] [--cases baseline,unchanged,body-edit,add-proc,add-var,change-default,asset-edit,add-resource] [--skip-cold] [--cold-body-edit]")),
        }
    }
    if !(1..=4).contains(&workers)
        || !(1..=3072).contains(&memory_mib)
        || !(1..=86400).contains(&timeout)
    {
        return Err(error(
            "workers must be 1..4, memory-mib 1..3072, timeout-seconds 1..86400",
        ));
    }
    if cases.first().map(String::as_str) != Some("baseline")
        || cases.iter().any(|case| {
            ![
                "baseline",
                "unchanged",
                "body-edit",
                "add-proc",
                "add-var",
                "change-default",
                "asset-edit",
                "add-resource",
            ]
            .contains(&case.as_str())
        })
        || cases
            .iter()
            .collect::<std::collections::BTreeSet<_>>()
            .len()
            != cases.len()
    {
        return Err(error(
            "cases must be unique supported cases beginning with baseline",
        ));
    }
    let original = project
        .ok_or_else(|| error("--project REAL.dme required"))?
        .canonicalize()?;
    let out = output.ok_or_else(|| error("--output NEW_DIR required"))?;
    if out.exists() {
        return Err(error("benchmark output must be a new directory"));
    }
    fs::create_dir_all(&out)?;
    let out = out.canonicalize()?;
    let builtins = match builtins {
        Some(path) => path.canonicalize()?,
        None => {
            let path = out.join("builtins.bin");
            fs::write(
                &path,
                include_bytes!("../../../fixtures/native_template.bin"),
            )?;
            path
        }
    };
    // Sharing root is independent of measurement output directories.
    let cache = cache.unwrap_or_else(|| dm_compiled::default_cache_root(&original));
    fs::create_dir_all(&cache)?;
    let cache = cache.canonicalize()?;
    let owned = OwnedProject::new(&original)?;
    let config = Configuration {
        original,
        manifest: owned.manifest.clone(),
        overlay: owned.overlay.clone(),
        prefix: owned.prefix.clone(),
        builtins,
        cache,
        output: out.join("generation"),
        defines: defines.into_iter().collect(),
        cases,
        workers,
        memory_mib,
    };
    let config_file = out.join("configuration.json");
    write_json(&config_file, &config)?;
    let executable = std::env::current_exe()?;
    let mut report = Report { format_version: 1, mode: "production-coordinator-real-project", compiler: "native",
        fallback_count: 0, compiler_sha256: file_digest(&executable)?, builtins_sha256: file_digest(&config.builtins)?,
        configuration: config, phases: Vec::new(), success: false,
        timing_contract: "Coordinator.handle elapsed includes input proof/preparation, compilation or receipt reuse, and publication; receipt hashing is timed separately. Stage times are nested/overlapping elapsed totals, not a partition. Initial process build may use existing disk caches. Cold phase uses a new process after the retained process exits; no runtime starts." };
    write_json(&out.join("iteration.json"), &report)?;
    let mut phases = vec!["retained"];
    if cold {
        phases.push("cold-cached");
    }
    if cold_body {
        phases.push("cold-body-edit");
    }
    for phase in phases {
        // Ensure cold probes start from the baseline and run without a resident
        // compiler beside them. The body probe uses a previously unseen body.
        write_fixture(&report.configuration, "baseline")?;
        let result = run_phase(
            &executable,
            &config_file,
            &out,
            phase,
            Duration::from_secs(timeout),
        );
        report.phases.push(match result {
            Ok(value) => value,
            Err(error) => Phase {
                name: phase.into(),
                process_seconds: 0.0,
                success: false,
                measurements: Vec::new(),
                stderr: out.join(format!("{phase}.stderr.log")),
                error: Some(error.to_string()),
            },
        });
        report.success = report.phases.iter().all(|phase| phase.success);
        write_json(&out.join("iteration.json"), &report)?;
        if !report.success {
            return Err(error(format!(
                "{phase} failed; receipts: {}",
                out.join("iteration.json").display()
            )));
        }
    }
    println!("iteration report: {}", out.join("iteration.json").display());
    Ok(())
}
fn main() {
    if let Err(error) = dm_host::run_on_compiler_thread(|| run().map_err(|error| error.to_string()))
    {
        eprintln!("iteration_bench: {error}");
        std::process::exit(1);
    }
}
