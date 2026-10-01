//! Supported end-to-end canonical materialization benchmark; never starts DreamDaemon.
use dm_compiler::{
    bootstrap::{
        compile_preprocessed_project_with_resource_catalog,
        compile_preprocessed_project_with_resources_prepared_mode,
        resolved_resource_requests_with_literals,
    },
    frontend::OutlineSession,
    load_map_set_from_paths, ProjectSession,
};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs, io,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::atomic::{AtomicU64, Ordering},
    time::{Duration, Instant},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
fn err(e: impl std::fmt::Display) -> io::Error {
    io::Error::other(e.to_string())
}
fn sha(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
#[derive(Serialize)]
struct Measurement {
    project: PathBuf,
    case: String,
    preparation_s: f64,
    materialization_s: f64,
    reference_validation_s: f64,
    encoding_s: f64,
    pair_validation_s: f64,
    durable_publication_s: f64,
    total_s: f64,
    catalog_materialization_s: f64,
    catalog_encoding_validation_s: f64,
    catalog_publication_s: f64,
    catalog_total_s: f64,
    symbolic_hits: usize,
    symbolic_misses: usize,
    dmb_digest: String,
    rsc_digest: String,
    native_s: Option<f64>,
}
#[derive(Serialize)]
struct Report {
    format_version: u32,
    compiler_fingerprint: String,
    mode: String,
    workers: usize,
    measurements: Vec<Measurement>,
}
struct OwnedProject {
    manifest: PathBuf,
    overlay: PathBuf,
}
impl OwnedProject {
    fn new(original: &Path) -> io::Result<Self> {
        let root = original
            .parent()
            .ok_or_else(|| err("manifest needs parent"))?;
        let stem = format!(
            "__dm_materialization_{}_{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        );
        let manifest = root.join(format!("{stem}.dme"));
        let overlay = root.join(format!("{stem}.dm"));
        if [
            manifest.clone(),
            overlay.clone(),
            manifest.with_extension("dmb"),
            manifest.with_extension("rsc"),
        ]
        .iter()
        .any(|p| p.exists())
        {
            return Err(err("owned benchmark filename already exists"));
        }
        let source = fs::read_to_string(original)?;
        fs::write(&overlay, overlay_source("baseline"))?;
        fs::write(&manifest, format!("{source}\n#include \"{stem}.dm\"\n"))?;
        Ok(Self { manifest, overlay })
    }
}
impl Drop for OwnedProject {
    fn drop(&mut self) {
        for p in [
            &self.manifest,
            &self.overlay,
            &self.manifest.with_extension("dmb"),
            &self.manifest.with_extension("rsc"),
        ] {
            let _ = fs::remove_file(p);
        }
    }
}
fn overlay_source(case: &str) -> String {
    let default = if case == "change-default" { 2 } else { 1 };
    let mut source = format!("/datum/__dm_benchmark_holder\n    var/value = {default}\n");
    if case == "add-var" {
        source.push_str("    var/additional = 9\n");
    }
    for i in 0..64 {
        source.push_str(&format!(
            "/proc/__dm_benchmark_{i}(value = 1)\n    return value + {i}\n"
        ));
    }
    if case == "add-proc" {
        source.push_str("/proc/__dm_benchmark_added()\n    return 42\n");
    }
    source
}
fn native(
    byond: &Path,
    project: &Path,
    defines: &BTreeMap<String, String>,
    logs: &Path,
) -> io::Result<f64> {
    fs::create_dir_all(logs)?;
    let mut command = Command::new(byond);
    command.arg(project).current_dir(project.parent().unwrap());
    for (name, value) in defines {
        command.arg(format!("-D{name}={value}"));
    }
    command.stdout(Stdio::from(fs::File::create(
        logs.join("native.stdout.log"),
    )?));
    command.stderr(Stdio::from(fs::File::create(
        logs.join("native.stderr.log"),
    )?));
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }
    let start = Instant::now();
    let mut child = command.spawn()?;
    loop {
        if let Some(status) = child.try_wait()? {
            if !status.success() {
                return Err(err(format!(
                    "native compiler failed: {status}; see {}",
                    logs.display()
                )));
            }
            break;
        }
        if start.elapsed() > Duration::from_secs(600) {
            let _ = child.kill();
            let _ = child.wait();
            return Err(err("native compiler timeout"));
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    // Some DreamMaker releases return success with compile errors; require artifacts.
    if !project.with_extension("dmb").is_file() {
        return Err(err("native compiler produced no output pair"));
    }
    Ok(start.elapsed().as_secs_f64())
}
fn materialize(
    project: &Path,
    case: &str,
    builtins: &[u8],
    defines: &BTreeMap<String, String>,
    out: &Path,
    frontend: &mut OutlineSession,
) -> io::Result<Measurement> {
    let total = Instant::now();
    let start = Instant::now();
    let session = ProjectSession::from_disk(project.to_owned(), defines.clone());
    let expanded = session.preprocess_incremental();
    if !expanded.diagnostics.is_empty() {
        return Err(err(format!(
            "preprocess diagnostics: {:?}",
            expanded.diagnostics
        )));
    }
    let maps = load_map_set_from_paths(project, &expanded.map_includes).map_err(err)?;
    let literals = frontend.resource_literals(&expanded.text).map_err(err)?;
    let requests = resolved_resource_requests_with_literals(
        project,
        &literals,
        &maps,
        &expanded.skin_includes,
        &expanded.file_dirs,
        &[],
    )
    .map_err(err)?;
    let preparation_s = start.elapsed().as_secs_f64();
    let start = Instant::now();
    // No project-pair receipt, previous DMB, ledger checkpoint or patch shortcut.
    let compiled = compile_preprocessed_project_with_resources_prepared_mode(
        project, &expanded, builtins, "world", frontend, &maps, &requests, false,
    )
    .map_err(err)?;
    let materialization_s = start.elapsed().as_secs_f64();
    let start = Instant::now();
    compiled.dmb.validate_references()?;
    let reference_validation_s = start.elapsed().as_secs_f64();
    let start = Instant::now();
    let dmb = compiled.dmb.to_bytes()?;
    let encoding_s = start.elapsed().as_secs_f64();
    let start = Instant::now();
    dm_output::validate_byond_pair(&dmb, &compiled.rsc_bytes)?;
    let pair_validation_s = start.elapsed().as_secs_f64();
    let start = Instant::now();
    let generation = dm_output::generation::publish_generation(out, &dmb, &compiled.rsc_bytes)?;
    dm_output::generation::verify_generation_digest(out, &generation)?;
    let durable_publication_s = start.elapsed().as_secs_f64();
    let total_s = total.elapsed().as_secs_f64();
    // A second canonical assembly reuses only a verified resource catalog/archive,
    // never the previously linked world or a wire patch.
    let catalog_total = Instant::now();
    let archive = dm_output::generation::verified_archive(out, &generation)?;
    let start = Instant::now();
    let catalog_compiled = compile_preprocessed_project_with_resource_catalog(
        project,
        &expanded,
        builtins,
        "world",
        frontend,
        &maps,
        &compiled.resource_catalog,
    )
    .map_err(err)?;
    let catalog_materialization_s = start.elapsed().as_secs_f64();
    let start = Instant::now();
    catalog_compiled.dmb.validate_references()?;
    let catalog_dmb = catalog_compiled.dmb.to_bytes()?;
    if catalog_dmb != dmb || !catalog_compiled.rsc_bytes.is_empty() {
        return Err(err(
            "resource-catalog assembly differs from full archive assembly",
        ));
    }
    let catalog_encoding_validation_s = start.elapsed().as_secs_f64();
    let start = Instant::now();
    let catalog_generation =
        dm_output::generation::publish_generation_with_archive(out, &catalog_dmb, &archive)?;
    dm_output::generation::verify_generation_digest(out, &catalog_generation)?;
    let catalog_publication_s = start.elapsed().as_secs_f64();
    let catalog_total_s = catalog_total.elapsed().as_secs_f64();
    Ok(Measurement {
        project: project.to_owned(),
        case: case.into(),
        preparation_s,
        materialization_s,
        reference_validation_s,
        encoding_s,
        pair_validation_s,
        durable_publication_s,
        total_s,
        catalog_materialization_s,
        catalog_encoding_validation_s,
        catalog_publication_s,
        catalog_total_s,
        symbolic_hits: compiled.lowering_cache_stats.hits,
        symbolic_misses: compiled.lowering_cache_stats.misses,
        dmb_digest: sha(&dmb),
        rsc_digest: sha(&compiled.rsc_bytes),
        native_s: None,
    })
}
fn run_project(
    original: &Path,
    builtins: &[u8],
    defines: &BTreeMap<String, String>,
    out: &Path,
    byond: Option<&Path>,
    cases: &[String],
    repeat: bool,
) -> io::Result<Vec<Measurement>> {
    let owned = OwnedProject::new(original)?;
    let mut frontend = OutlineSession::new(Some(out.join("frontend")));
    let mut results = vec![];
    for case in cases {
        let case = case.as_str();
        let source_case = if case == "cached-baseline" {
            "baseline"
        } else {
            case
        };
        fs::write(&owned.overlay, overlay_source(source_case))?;
        // Require the same manifest/source/context to reconstruct byte-identical DMB/RSC.
        let mut result = materialize(
            &owned.manifest,
            case,
            builtins,
            defines,
            &out.join(case),
            &mut frontend,
        )?;
        if repeat {
            let repeated = materialize(
                &owned.manifest,
                "determinism-check",
                builtins,
                defines,
                &out.join(format!("{case}-repeat")),
                &mut frontend,
            )?;
            if result.dmb_digest != repeated.dmb_digest || result.rsc_digest != repeated.rsc_digest
            {
                return Err(err(format!("non-deterministic materialization: {case}")));
            }
        }
        if case == "cached-baseline" && result.symbolic_misses != 0 {
            eprintln!("cached-baseline retained {} misses; report reflects budget/history eviction or invalidated facts, not a zero-miss guarantee", result.symbolic_misses);
        }
        if let Some(byond) = byond {
            // Remove only our previous native outputs so failure cannot reuse stale files.
            for p in [
                owned.manifest.with_extension("dmb"),
                owned.manifest.with_extension("rsc"),
            ] {
                if p.exists() {
                    fs::remove_file(p)?;
                }
            }
            result.native_s = Some(native(byond, &owned.manifest, defines, &out.join(case))?);
        }
        println!(
            "{}: total {:.6}s, materialization {:.6}s, symbolic {}/{} hits/misses, native {:?}",
            case,
            result.total_s,
            result.materialization_s,
            result.symbolic_hits,
            result.symbolic_misses,
            result.native_s
        );
        results.push(result);
    }
    Ok(results)
}
fn run() -> io::Result<()> {
    let _budget = dm_host::install_process_budget()?;
    let mut args = std::env::args().skip(1);
    let mut projects = vec![];
    let mut out = None;
    let mut byond = None;
    let mut builtins = None;
    let mut defines = BTreeMap::new();
    let mut six = false;
    let mut repeat = true;
    let mut cases: Vec<String> = [
        "baseline",
        "cached-baseline",
        "add-proc",
        "add-var",
        "change-default",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect();
    while let Some(arg) = args.next() {
        match arg.as_str(){
        "--output"=>out=Some(PathBuf::from(args.next().ok_or_else(||err("missing output"))?)),
        "--project"=>projects.push(PathBuf::from(args.next().ok_or_else(||err("missing project"))?)),
        "--byond"=>byond=Some(PathBuf::from(args.next().ok_or_else(||err("missing native compiler"))?)),
        "--builtins"=>builtins=Some(PathBuf::from(args.next().ok_or_else(||err("missing schema"))?)),
        "--six-worktrees"=>six=true,
        "--skip-repeat"=>repeat=false,
        "--cases"=>{cases=args.next().ok_or_else(||err("missing cases"))?.split(',').map(str::to_owned).collect(); if cases.is_empty() || cases.iter().any(|case| !["baseline","cached-baseline","add-proc","add-var","change-default"].contains(&case.as_str())) {return Err(err("unknown benchmark case"));}},
        _ if arg.starts_with("-D")=>{let d=arg.trim_start_matches("-D");let(n,v)=d.split_once('=').unwrap_or((d,"1"));defines.insert(n.to_owned(),v.to_owned());},
        _=>return Err(err("usage: materialization_bench --output NEW_DIR [--byond DreamMaker.exe] [--project ISOLATED.dme ...] [--six-worktrees] [-DNAME]")),
    }
    }
    let out = out.ok_or_else(|| err("--output NEW_DIR required"))?;
    if out.exists() {
        return Err(err("benchmark output directory must be new"));
    }
    fs::create_dir_all(&out)?;
    let out = out.canonicalize()?;
    std::env::set_var("DM_COMPILER_CACHE_ROOT", out.join("shared-cache"));
    let bytes = if let Some(path) = builtins {
        fs::read(path)?
    } else {
        include_bytes!("../../../fixtures/native_template.bin").to_vec()
    };
    let fixture = projects.is_empty();
    if fixture {
        let count = if six { 6 } else { 1 };
        for i in 0..count {
            let root = out.join(format!("fixture-{i}"));
            fs::create_dir_all(&root)?;
            let project = root.join("world.dme");
            fs::write(
                &project,
                "world\n    maxx = 1\n    maxy = 1\n    maxz = 1\n",
            )?;
            projects.push(project);
        }
    }
    if six && projects.len() != 6 {
        return Err(err(
            "six-worktree mode requires exactly six --project arguments or default fixtures",
        ));
    }
    let mut measurements = vec![];
    // Two concurrent compiler jobs bound memory; six independent source roots share CAS.
    for (chunk_index, chunk) in projects.chunks(if six { 2 } else { 1 }).enumerate() {
        let results = std::thread::scope(|scope| {
            chunk
                .iter()
                .enumerate()
                .map(|(i, project)| {
                    let target = out.join(format!("project-{}", chunk_index * 2 + i));
                    let bytes = &bytes;
                    let defines = &defines;
                    let byond = byond.as_deref();
                    let cases = &cases;
                    std::thread::Builder::new()
                        .stack_size(16 * 1024 * 1024)
                        .spawn_scoped(scope, move || {
                            run_project(project, bytes, defines, &target, byond, cases, repeat)
                        })
                        .expect("benchmark thread")
                })
                .collect::<Vec<_>>()
                .into_iter()
                .map(|handle| handle.join().map_err(|_| err("benchmark worker panic"))?)
                .collect::<io::Result<Vec<_>>>()
        });
        for result in results? {
            measurements.extend(result);
        }
    }
    let report = Report {
        format_version: 1,
        compiler_fingerprint: sha(&fs::read(std::env::current_exe()?)?),
        mode: if fixture {
            "fixture"
        } else {
            "explicit-project"
        }
        .into(),
        workers: if six { 2 } else { 1 },
        measurements,
    };
    let file = fs::File::create(out.join("materialization.json"))?;
    serde_json::to_writer_pretty(file, &report).map_err(err)?;
    println!("report: {}", out.join("materialization.json").display());
    Ok(())
}
fn main() {
    if let Err(error) = run() {
        eprintln!("materialization_bench: {error}");
        std::process::exit(1);
    }
}
