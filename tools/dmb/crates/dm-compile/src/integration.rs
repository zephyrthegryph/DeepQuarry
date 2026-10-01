//! Build-pipeline compatibility and shadow checks. Source failures never fall
//! back. Proven infrastructure failures may visibly use BYOND unless strict.
use super::parse_defines;
use dm_compiled::{default_cache_root, BuildResult, Coordinator, Request, Response, SessionKey};
use dm_output::generation::{publish_generation_from_files, Generation};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::env;
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

static NEXT: AtomicU64 = AtomicU64::new(0);
const TARGET: &str = "516.1687";
const BUILTIN_DIGEST: &str = "9221528efb715be5b8df23020989e0c2a53ea32bff9894747166dbe04d785540";

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Mode {
    Byond,
    Native,
    Shadow,
}
impl Mode {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "byond" => Ok(Self::Byond),
            "native" => Ok(Self::Native),
            "shadow" => Ok(Self::Shadow),
            _ => Err(format!(
                "DQ_COMPILER must be byond, native, or shadow; got {value:?}"
            )),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FailureKind {
    Source,
    Internal,
    Configuration,
    Comparison,
}

#[derive(Debug)]
pub struct Failure {
    kind: FailureKind,
    project: PathBuf,
    message: String,
    diagnostics: Vec<String>,
}
impl std::fmt::Display for Failure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{}", diagnostic(&self.project, &self.message))?;
        for message in &self.diagnostics {
            write!(formatter, "\n{}", diagnostic(&self.project, message))?;
        }
        Ok(())
    }
}
impl std::error::Error for Failure {}

struct Options {
    project: PathBuf,
    builtins: PathBuf,
    byond: PathBuf,
    mode: Mode,
    output: PathBuf,
    report: PathBuf,
    daemon: Option<String>,
    strict: bool,
    defines: BTreeMap<String, String>,
    target: String,
}
impl Options {
    fn failure(&self, kind: FailureKind, message: impl Into<String>) -> Failure {
        Failure {
            kind,
            project: self.project.clone(),
            message: message.into(),
            diagnostics: vec![],
        }
    }
}

#[derive(Serialize)]
struct IntegrationReport {
    version: u32,
    mode: Mode,
    selected_backend: Mode,
    ok: bool,
    fallback: Option<Fallback>,
    failure: Option<Fallback>,
    build: Option<BuildResult>,
    conventional: Option<dm_output::conventional::ConventionalPair>,
    shadow: Option<ShadowReport>,
    elapsed_seconds: f64,
    producing_compiler: Option<Mode>,
    native_gate_passed: bool,
    target: String,
    builtin_digest: Option<String>,
    source_digest: Option<String>,
}
#[derive(Deserialize)]
struct BuiltinManifest {
    target: String,
    sha256: String,
}
#[derive(Serialize)]
struct Fallback {
    kind: FailureKind,
    reason: String,
}
#[derive(Serialize)]
struct ShadowReport {
    native_matches_fresh_native: bool,
    same_source_revision: bool,
    native_dmb_digest: String,
    fresh_dmb_digest: String,
    native_rsc_digest: String,
    fresh_rsc_digest: String,
    byond_structure_differences: Vec<Difference>,
    byond_resources_match: bool,
    comparison_limit: usize,
    bytecode_compared: bool,
}
#[derive(Serialize)]
struct Difference {
    path: String,
    field: String,
    expected: String,
    actual: String,
}

fn options(args: Vec<String>) -> Result<Options, String> {
    let mut args = args.into_iter();
    let project = PathBuf::from(args.next().ok_or("usage: dm-compile integrated-build PROJECT.dme [--mode byond|native|shadow] [--builtins FILE] [--byond FILE] [--daemon ADDRESS] [-DNAME]")?);
    let mut mode = Mode::parse(&env::var("DQ_COMPILER").unwrap_or_else(|_| "byond".into()))?;
    let mut builtins = env::var_os("DQ_NATIVE_BUILTINS")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("tools/dmb/fixtures/native_template.bin"));
    let mut byond = env::var_os("DM_EXE").map(PathBuf::from).unwrap_or_else(|| {
        PathBuf::from(if cfg!(windows) {
            "dm.exe"
        } else {
            "DreamMaker"
        })
    });
    let mut daemon = env::var("DQ_NATIVE_DAEMON").ok();
    let mut output = None;
    let mut report = None;
    let mut strict = env::var("DQ_COMPILER_STRICT").ok().as_deref() == Some("1");
    let mut target = env::var("DQ_NATIVE_TARGET").unwrap_or_else(|_| TARGET.into());
    let mut define_args = Vec::new();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--mode" => mode = Mode::parse(&args.next().ok_or("missing --mode value")?)?,
            "--builtins" => {
                builtins = PathBuf::from(args.next().ok_or("missing --builtins value")?)
            }
            "--byond" => byond = PathBuf::from(args.next().ok_or("missing --byond value")?),
            "--daemon" => daemon = Some(args.next().ok_or("missing --daemon value")?),
            "--output-root" => {
                output = Some(PathBuf::from(
                    args.next().ok_or("missing --output-root value")?,
                ))
            }
            "--report" => {
                report = Some(PathBuf::from(args.next().ok_or("missing --report value")?))
            }
            "--strict" => strict = true,
            "--target" => target = args.next().ok_or("missing --target value")?,
            "--define" | "-D" => {
                define_args.push(arg);
                define_args.push(args.next().ok_or("missing define")?);
            }
            _ if arg.starts_with("-D") || arg.starts_with("--define=") => define_args.push(arg),
            _ => return Err(format!("unknown integration argument {arg}")),
        }
    }
    let project = project
        .canonicalize()
        .map_err(|error| format!("{}: {error}", project.display()))?;
    let parent = project.parent().ok_or("project has no directory")?;
    let name = project.file_name().ok_or("project has no filename")?;
    let state = parent.join(".dm-native").join(name);
    Ok(Options {
        project,
        builtins,
        byond,
        mode,
        output: output.unwrap_or_else(|| state.join("native")),
        report: report.unwrap_or_else(|| state.join("integration.json")),
        daemon,
        strict,
        defines: parse_defines(define_args)?,
        target,
    })
}

/// New patch targets require a deliberate compiler/catalog update and fixture
/// gates. A v516 header alone cannot prove compatibility with a patch release.
fn preflight(options: &Options) -> Result<String, Failure> {
    if options.target != TARGET {
        return Err(options.failure(
            FailureKind::Configuration,
            format!(
                "native target {} is not fixture-gated; supported target is {TARGET}",
                options.target
            ),
        ));
    }
    let bytes = fs::read(&options.builtins).map_err(|error| {
        options.failure(
            FailureKind::Configuration,
            format!("builtin schema: {error}"),
        )
    })?;
    let digest = format!("{:x}", Sha256::digest(&bytes));
    let schema = byond_dmb::dmb::Dmb::from_bytes(&bytes).map_err(|error| {
        options.failure(
            FailureKind::Configuration,
            format!("builtin schema format: {error}"),
        )
    })?;
    if schema.header.version_line != b"world bin v516\n" {
        return Err(options.failure(
            FailureKind::Configuration,
            "builtin schema must use the v516 format",
        ));
    }
    if digest != BUILTIN_DIGEST {
        let manifest_path = options.builtins.with_extension("target.json");
        let manifest: BuiltinManifest =
            serde_json::from_slice(&fs::read(&manifest_path).map_err(|error| {
                options.failure(
                    FailureKind::Configuration,
                    format!(
                        "custom builtin schema requires {}: {error}",
                        manifest_path.display()
                    ),
                )
            })?)
            .map_err(|error| {
                options.failure(
                    FailureKind::Configuration,
                    format!("builtin target manifest: {error}"),
                )
            })?;
        if manifest.target != TARGET || manifest.sha256 != digest {
            return Err(options.failure(
                FailureKind::Configuration,
                "builtin target manifest does not match the native target and schema bytes",
            ));
        }
    }
    Ok(digest)
}

fn diagnostic(project: &Path, message: &str) -> String {
    if message.contains(":error:") || message.contains(":warning:") {
        return message.to_owned();
    }
    // Preserve Windows drive prefixes and messages containing colons. Existing
    // source-path:line diagnostics become directly consumable by BYOND tooling.
    for (index, _) in message.match_indices(':') {
        let tail = &message[index + 1..];
        if let Some((line, text)) = tail.split_once(':') {
            if !line.is_empty() && line.bytes().all(|byte| byte.is_ascii_digit()) {
                let text = text.trim();
                for severity in ["error", "warning"] {
                    if let Some(text) = text
                        .strip_prefix(severity)
                        .and_then(|text| text.strip_prefix(':'))
                    {
                        return format!(
                            "{}:{}:{severity}: {}",
                            &message[..index],
                            line,
                            text.trim_start()
                        );
                    }
                }
                return format!("{}:{}:error: {}", &message[..index], line, text);
            }
        }
    }
    format!("{}:1:error: {message}", project.display())
}

fn permit_fallback(kind: FailureKind, strict: bool) -> bool {
    kind == FailureKind::Internal && !strict
}

fn native_build(options: &Options) -> Result<Response, Failure> {
    let key = SessionKey::new(
        env::current_dir()
            .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?,
        &options.project,
        &options.target,
        options.defines.clone().into_iter().collect(),
        "canonical",
    )
    .map_err(|error| options.failure(FailureKind::Configuration, error.to_string()))?;
    let request = Request::BuildProject {
        key,
        builtins: options.builtins.clone(),
        output_root: options.output.clone(),
    };
    let response = if let Some(address) = &options.daemon {
        let exchange = || -> io::Result<Response> {
            let mut stream = TcpStream::connect(address)?;
            stream.set_read_timeout(Some(std::time::Duration::from_secs(1800)))?;
            serde_json::to_writer(&mut stream, &request).map_err(io::Error::other)?;
            stream.write_all(b"\n")?;
            let mut line = String::new();
            BufReader::new(stream)
                .take(32 * 1024 * 1024)
                .read_line(&mut line)?;
            serde_json::from_str(&line).map_err(io::Error::other)
        };
        exchange().map_err(|error| {
            options.failure(
                FailureKind::Internal,
                format!("native daemon transport: {error}"),
            )
        })?
    } else {
        let mut coordinator =
            Coordinator::new(default_cache_root(&options.project)).map_err(|error| {
                options.failure(
                    FailureKind::Internal,
                    format!("native cache setup: {error}"),
                )
            })?;
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| coordinator.handle(request)))
            .map_err(|_| options.failure(FailureKind::Internal, "native compiler panicked"))?
    };
    if !response.ok {
        // Only explicitly classified infrastructure failures permit fallback.
        // Old daemons and unclassified semantic strings remain source failures.
        let (message, diagnostics) =
            failure_messages(response.error.as_deref(), &response.diagnostics);
        let mut failure = options.failure(compiler_failure_kind(response.failure_kind), message);
        failure.diagnostics = diagnostics;
        return Err(failure);
    }
    for message in &response.diagnostics {
        eprintln!("{}", diagnostic(&options.project, message));
    }
    if response.build.is_none() {
        return Err(options.failure(
            FailureKind::Internal,
            "native compiler returned no generation",
        ));
    }
    Ok(response)
}

fn failure_messages(error: Option<&str>, diagnostics: &[String]) -> (String, Vec<String>) {
    let primary = error
        .or_else(|| diagnostics.first().map(String::as_str))
        .unwrap_or("native build failed without a diagnostic");
    // The caller renders the primary once. Keep each remaining provider record,
    // including genuinely repeated records from distinct include occurrences.
    let selected = diagnostics.iter().position(|message| message == primary);
    (
        primary.to_owned(),
        diagnostics
            .iter()
            .enumerate()
            .filter(|(index, _)| Some(*index) != selected)
            .map(|(_, message)| message.clone())
            .collect(),
    )
}

fn compiler_failure_kind(kind: Option<dm_compiled::FailureKind>) -> FailureKind {
    match kind {
        Some(dm_compiled::FailureKind::Internal) => FailureKind::Internal,
        Some(dm_compiled::FailureKind::Configuration) => FailureKind::Configuration,
        // Old daemons and unclassified semantic strings remain source failures.
        _ => FailureKind::Source,
    }
}

fn byond_build(options: &Options) -> Result<(), Failure> {
    if options.mode == Mode::Shadow {
        let version = Command::new(&options.byond).output().map_err(|error| {
            options.failure(
                FailureKind::Internal,
                format!("BYOND version preflight: {error}"),
            )
        })?;
        let text = format!(
            "{}{}",
            String::from_utf8_lossy(&version.stdout),
            String::from_utf8_lossy(&version.stderr)
        );
        let actual = text
            .split("DM compiler version ")
            .nth(1)
            .and_then(|value| value.split_whitespace().next());
        if actual != Some(options.target.as_str()) {
            return Err(options.failure(
                FailureKind::Configuration,
                format!(
                    "shadow reference must be BYOND {}; found {:?}",
                    options.target, actual
                ),
            ));
        }
    }
    let mut command = Command::new(&options.byond);
    for (name, value) in &options.defines {
        command.arg(format!("-D{name}={value}"));
    }
    let output = command.arg(&options.project).output().map_err(|error| {
        options.failure(
            FailureKind::Internal,
            format!("starting BYOND compiler: {error}"),
        )
    })?;
    io::stdout()
        .write_all(&output.stdout)
        .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?;
    io::stderr()
        .write_all(&output.stderr)
        .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?;
    if !output.status.success() {
        return Err(options.failure(
            FailureKind::Source,
            format!("BYOND compiler exited {}", output.status),
        ));
    }
    if !options.project.with_extension("dmb").is_file() {
        return Err(options.failure(
            FailureKind::Internal,
            "BYOND reported success without a DMB",
        ));
    }
    if !options.project.with_extension("rsc").exists() {
        fs::write(options.project.with_extension("rsc"), [])
            .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?;
    }
    publish_generation_from_files(
        &options
            .output
            .parent()
            .unwrap_or(&options.output)
            .join("byond"),
        &options.project.with_extension("dmb"),
        &options.project.with_extension("rsc"),
    )
    .map_err(|error| {
        options.failure(
            FailureKind::Internal,
            format!("BYOND generation import: {error}"),
        )
    })?;
    Ok(())
}

fn hash_file(path: &Path) -> io::Result<String> {
    let mut reader = File::open(path)?;
    let mut buffer = [0u8; 64 * 1024];
    let mut hash = Sha256::new();
    loop {
        let count = reader.read(&mut buffer)?;
        if count == 0 {
            return Ok(format!("{:x}", hash.finalize()));
        }
        hash.update(&buffer[..count]);
    }
}

fn resource_inventory(path: &Path) -> io::Result<BTreeMap<(Vec<u8>, u8), Vec<String>>> {
    let mut input = BufReader::new(File::open(path)?);
    let mut inventory: BTreeMap<_, Vec<_>> = BTreeMap::new();
    while let Some(entry) = byond_dmb::rsc::read_entry(&mut input)? {
        if let byond_dmb::rsc::Entry::Named(resource) = entry {
            inventory
                .entry((resource.name.clone(), resource.kind))
                .or_default()
                .push(format!("{:x}", Sha256::digest(resource.asset_bytes()?)));
        }
    }
    for hashes in inventory.values_mut() {
        hashes.sort();
    }
    Ok(inventory)
}

fn fresh_native(options: &Options) -> Result<Response, Failure> {
    let fresh = options
        .output
        .parent()
        .unwrap_or(&options.output)
        .join(format!(
            "fresh-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
    fs::create_dir_all(&fresh)
        .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?;
    let mut command = Command::new(
        env::current_exe()
            .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?,
    );
    command
        .arg("build-project-json")
        .arg(&options.project)
        .arg(&options.builtins)
        .arg(fresh.join("output"))
        .env("DM_COMPILER_CACHE_ROOT", fresh.join("cache"))
        .env("DQ_NATIVE_TARGET", &options.target);
    for (name, value) in &options.defines {
        command.arg(format!("-D{name}={value}"));
    }
    let output = command.output().map_err(|error| {
        options.failure(
            FailureKind::Internal,
            format!("fresh native process: {error}"),
        )
    })?;
    let response: Response = serde_json::from_slice(&output.stdout).map_err(|error| {
        options.failure(
            FailureKind::Internal,
            format!(
                "fresh native response: {error}; {}",
                String::from_utf8_lossy(&output.stderr)
            ),
        )
    })?;
    if !output.status.success() || !response.ok {
        let (message, diagnostics) =
            failure_messages(response.error.as_deref(), &response.diagnostics);
        let mut failure = options.failure(
            if response.ok {
                // A successful build response followed by an unsuccessful exit
                // violates the child protocol rather than rejecting source.
                FailureKind::Internal
            } else {
                compiler_failure_kind(response.failure_kind)
            },
            message,
        );
        failure.diagnostics = diagnostics;
        return Err(failure);
    }
    Ok(response)
}

fn shadow(options: &Options, native: &Response) -> Result<ShadowReport, Failure> {
    let fresh = fresh_native(options)?;
    let cached = native.build.as_ref().unwrap();
    let fresh_build = fresh
        .build
        .as_ref()
        .ok_or_else(|| options.failure(FailureKind::Internal, "fresh native generation missing"))?;
    let check = || -> Result<ShadowReport, Box<dyn std::error::Error>> {
        let native_dmb_digest = hash_file(&cached.dmb)?;
        let fresh_dmb_digest = hash_file(&fresh_build.dmb)?;
        let native_rsc_digest = hash_file(&cached.rsc)?;
        let fresh_rsc_digest = hash_file(&fresh_build.rsc)?;
        let reference =
            byond_dmb::dmb::Dmb::from_bytes(&fs::read(options.project.with_extension("dmb"))?)?;
        let actual = byond_dmb::dmb::Dmb::from_bytes(&fs::read(&cached.dmb)?)?;
        let mut differences = byond_dmb::compare::compare_dmbs(
            &reference,
            &actual,
            &byond_dmb::compare::CompareOptions {
                compare_bytecode: false,
                max_discrepancies: 200,
                ..Default::default()
            },
        );
        if differences.len() < 200 {
            differences.extend(byond_dmb::compare::compare_maps_semantic(
                &reference,
                &actual,
                200 - differences.len(),
            ));
        }
        Ok(ShadowReport {
            native_matches_fresh_native: native_dmb_digest == fresh_dmb_digest
                && native_rsc_digest == fresh_rsc_digest,
            same_source_revision: native.source_digest == fresh.source_digest,
            native_dmb_digest,
            fresh_dmb_digest,
            native_rsc_digest,
            fresh_rsc_digest,
            byond_structure_differences: differences
                .into_iter()
                .map(|difference| Difference {
                    path: difference.path,
                    field: difference.field,
                    expected: difference.expected,
                    actual: difference.actual,
                })
                .collect(),
            byond_resources_match: resource_inventory(&options.project.with_extension("rsc"))?
                == resource_inventory(&cached.rsc)?,
            comparison_limit: 200,
            bytecode_compared: false,
        })
    };
    check().map_err(|error| options.failure(FailureKind::Comparison, error.to_string()))
}

fn persist_report(options: &Options, report: &IntegrationReport) -> Result<(), Failure> {
    if let Some(parent) = options.report.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?;
    }
    let temporary = options.report.with_extension(format!(
        "pending-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let mut file = File::create(&temporary)
        .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?;
    serde_json::to_writer_pretty(&mut file, report)
        .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?;
    file.write_all(b"\n")
        .and_then(|_| file.sync_all())
        .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?;
    drop(file);
    replace_report(&temporary, &options.report)
        .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))
}

#[cfg(windows)]
fn replace_report(source: &Path, destination: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn MoveFileExW(source: *const u16, destination: *const u16, flags: u32) -> i32;
    }
    let source: Vec<u16> = source.as_os_str().encode_wide().chain(Some(0)).collect();
    let destination: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect();
    if unsafe { MoveFileExW(source.as_ptr(), destination.as_ptr(), 1 | 8) } == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}
#[cfg(not(windows))]
fn replace_report(source: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(source, destination)
}

pub fn run(args: Vec<String>) -> Result<(), Failure> {
    let project_hint = args
        .first()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("project.dme"));
    let options = options(args).map_err(|message| Failure {
        kind: FailureKind::Configuration,
        project: project_hint,
        message,
        diagnostics: vec![],
    })?;
    let started = Instant::now();
    let gate_path = options
        .project
        .parent()
        .unwrap()
        .join(".dm-native")
        .join(options.project.file_name().unwrap());
    fs::create_dir_all(&gate_path)
        .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?;
    let gate = fs::OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .open(gate_path.join("build.lock"))
        .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?;
    gate.lock()
        .map_err(|error| options.failure(FailureKind::Internal, error.to_string()))?;
    let mut report = IntegrationReport {
        version: 1,
        mode: options.mode,
        selected_backend: options.mode,
        ok: false,
        fallback: None,
        failure: None,
        build: None,
        conventional: None,
        shadow: None,
        elapsed_seconds: 0.0,
        producing_compiler: None,
        native_gate_passed: false,
        target: options.target.clone(),
        builtin_digest: None,
        source_digest: None,
    };
    let mut result = (|| -> Result<(), Failure> {
        if options.mode == Mode::Byond {
            byond_build(&options)?;
            report.producing_compiler = Some(Mode::Byond);
            return Ok(());
        }
        report.builtin_digest = Some(preflight(&options)?);
        if options.mode == Mode::Shadow {
            byond_build(&options)?;
            report.selected_backend = Mode::Byond;
        }
        let native = match native_build(&options) {
            Ok(native) => native,
            Err(error)
                if options.mode == Mode::Native && permit_fallback(error.kind, options.strict) =>
            {
                eprintln!(
                    "{}:1:warning: native compiler infrastructure failure; using BYOND: {}",
                    options.project.display(),
                    error.message
                );
                report.fallback = Some(Fallback {
                    kind: error.kind,
                    reason: error.message,
                });
                report.selected_backend = Mode::Byond;
                byond_build(&options)?;
                report.producing_compiler = Some(Mode::Byond);
                return Ok(());
            }
            Err(error) => return Err(error),
        };
        report.build = native.build.clone();
        report.source_digest = native.source_digest.clone();
        if options.mode == Mode::Shadow {
            let comparison = shadow(&options, &native)?;
            let matches = comparison.native_matches_fresh_native && comparison.same_source_revision;
            eprintln!("shadow: cached/fresh native parity {}; {} structural BYOND differences; resource parity {}", matches,
                comparison.byond_structure_differences.len(), comparison.byond_resources_match);
            report.shadow = Some(comparison);
            if !matches {
                return Err(options.failure(FailureKind::Comparison, "cached native output does not match fresh native output for the same source revision"));
            }
            report.producing_compiler = Some(Mode::Byond);
            report.native_gate_passed = true;
        } else {
            let build = native.build.as_ref().unwrap();
            let generation = Generation {
                id: build.generation.clone(),
                dmb: build.dmb.clone(),
                rsc: build.rsc.clone(),
            };
            report.conventional = Some(
                dm_output::conventional::materialize_generation(
                    &options.project,
                    &options.output,
                    &generation,
                )
                .map_err(|error| {
                    options.failure(
                        FailureKind::Internal,
                        format!("conventional output publication: {error}"),
                    )
                })?,
            );
            println!(
                "{} - 0 errors, 0 warnings; {} procedures ({} lowered, {} reused)",
                options.project.with_extension("dmb").display(),
                build.emitted_procs,
                build.lowered_procs,
                build.reused_procs
            );
            report.producing_compiler = Some(Mode::Native);
            report.native_gate_passed = true;
        }
        Ok(())
    })();
    if let Err(error) = &result {
        if options.mode == Mode::Native
            && report.fallback.is_none()
            && permit_fallback(error.kind, options.strict)
        {
            eprintln!(
                "{}:1:warning: native compiler infrastructure failure; using BYOND: {}",
                options.project.display(),
                error.message
            );
            report.fallback = Some(Fallback {
                kind: error.kind,
                reason: error.message.clone(),
            });
            report.selected_backend = Mode::Byond;
            report.conventional = None;
            result = byond_build(&options);
            if result.is_ok() {
                report.producing_compiler = Some(Mode::Byond);
            }
        }
    }
    if let Err(error) = &result {
        report.failure = Some(Fallback {
            kind: error.kind,
            reason: error.message.clone(),
        });
    }
    report.ok = result.is_ok();
    report.elapsed_seconds = started.elapsed().as_secs_f64();
    persist_report(&options, &report)?;
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_proven_internal_failures_allow_automatic_fallback() {
        assert!(permit_fallback(FailureKind::Internal, false));
        for kind in [
            FailureKind::Source,
            FailureKind::Configuration,
            FailureKind::Comparison,
        ] {
            assert!(!permit_fallback(kind, false));
        }
        assert!(!permit_fallback(FailureKind::Internal, true));
    }
    #[test]
    fn error_format_preserves_windows_paths_and_existing_locations() {
        assert_eq!(
            diagnostic(
                Path::new("probe.dme"),
                r"C:\game\code.dm:42: invalid declaration"
            ),
            r"C:\game\code.dm:42:error: invalid declaration"
        );
        assert_eq!(
            diagnostic(Path::new("probe.dme"), "bad.dm:9:error: invalid"),
            "bad.dm:9:error: invalid"
        );
        assert_eq!(
            diagnostic(Path::new("probe.dme"), "bad.dm:9: error: invalid"),
            "bad.dm:9:error: invalid"
        );
        assert_eq!(
            diagnostic(Path::new("probe.dme"), "bad.dm:9: warning: unused"),
            "bad.dm:9:warning: unused"
        );
        assert_eq!(
            diagnostic(Path::new("probe.dme"), "unsupported expression"),
            "probe.dme:1:error: unsupported expression"
        );
    }
    #[test]
    fn selector_rejects_unknown_modes() {
        assert_eq!(Mode::parse("native").unwrap(), Mode::Native);
        assert!(Mode::parse("opendream").is_err());
    }
    #[test]
    fn source_diagnostics_are_rendered_once_without_a_generic_extra_error() {
        let diagnostics = vec![
            "a.dm:2:error: first".to_owned(),
            "b.dm:4:error: second".to_owned(),
        ];
        let (message, remaining) = failure_messages(None, &diagnostics);
        let failure = Failure {
            kind: FailureKind::Source,
            project: PathBuf::from("project.dme"),
            message,
            diagnostics: remaining,
        };
        assert_eq!(failure.to_string(), diagnostics.join("\n"));
        let (message, remaining) = failure_messages(Some(&diagnostics[0]), &diagnostics);
        assert_eq!(message, diagnostics[0]);
        assert_eq!(remaining, diagnostics[1..]);
    }
    #[test]
    fn native_and_fresh_shadow_failures_keep_typed_classification() {
        assert_eq!(compiler_failure_kind(None), FailureKind::Source);
        assert_eq!(
            compiler_failure_kind(Some(dm_compiled::FailureKind::Source)),
            FailureKind::Source
        );
        assert_eq!(
            compiler_failure_kind(Some(dm_compiled::FailureKind::Internal)),
            FailureKind::Internal
        );
        assert_eq!(
            compiler_failure_kind(Some(dm_compiled::FailureKind::Configuration)),
            FailureKind::Configuration
        );
    }
}
