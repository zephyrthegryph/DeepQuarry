//! `dmbc analyze`: the lint and analysis engine (tools/analyze) served by this daemon, so one resident program compiles and
//! analyzes (doc/rewrite/proposals/lean_unified.md).
//!
//! The client sends its command line, environment and working directory; the daemon runs the request through
//! `dq_analyze::cli::run_hosted` (one at a time, on threads of its own, output and environment scoped to the request) and returns
//! its stdout, stderr and exit code. The client prints them only once the request has finished, so a request that fails on the
//! way (the daemon died, a protocol error, admission refused) falls back to running in the client with nothing printed twice.
//! `DQ_ANALYZE_DAEMON=0` (and `CI`) run in the client.
//!
//! A command `dq_analyze::cli::rememberable` names is answered through the root's query database (`analysis_db`): from memory
//! while nothing it read changed. Its answer goes to the client as data, an `Answered` (`Reply::AnalysisData` frames): the
//! report with every diagnostic, the revision it was made at and, for `--since N`, the report of revision N. The client renders it
//! (`dq_analyze::report::View`): the same bytes the command prints standalone.

use super::{lifecycle_deadline, protocol, transport};
use serde::{Deserialize, Serialize};
use std::io;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

#[derive(Serialize, Deserialize)]
pub(super) struct AnalyzeRequest {
    pub argv: Vec<String>,
    pub env: Vec<(String, String)>,
    pub cwd: PathBuf,
}

/// A remembered command's answer as the client receives it.
#[derive(Serialize, Deserialize)]
struct Answered {
    revision: u64,
    report: dq_analyze::report::Report,
    /// The report of revision `--since N`, when the daemon still holds it.
    base: Option<dq_analyze::report::Report>,
}

/// A request is refused (and runs in the client) while less than this much RAM is free: a run peaks at about 3.5 GB.
const MIN_FREE_BYTES: u64 = 6 << 30;
/// Frames carry output in chunks of at most this many bytes (JSON spells each byte as up to four characters).
const CHUNK: usize = 512 << 10;

fn trace() -> bool {
    std::env::var_os("DQ_ANALYZE_DAEMON_TRACE").is_some()
}

/// Whether `argv` goes to the daemon.
fn wanted(argv: &[String]) -> bool {
    if matches!(std::env::var("DQ_ANALYZE_DAEMON").as_deref(), Ok("0") | Ok("off")) || std::env::var_os("CI").is_some() {
        return false;
    }
    // A cold child of a hosted run re-enters through the command line; it must run where it was started.
    if std::env::var_os("DQ_ANALYZE_UNUSED_RECHECK").is_some() {
        return false;
    }
    dq_analyze::cli::hostable(argv)
}

/// Runs `argv` in the daemon: `Some(exit code)` when it answered (its output already printed), `None` to run here.
pub fn client(argv: &[String]) -> Option<u8> {
    if !wanted(argv) {
        return None;
    }
    let started = Instant::now();
    match exchange(argv) {
        Ok((code, out, err)) => {
            use std::io::Write;
            let _ = io::stdout().lock().write_all(&out);
            let _ = io::stdout().flush();
            let _ = io::stderr().lock().write_all(&err);
            let _ = io::stderr().flush();
            if trace() {
                eprintln!("dmbc analyze: served by the daemon in {:.1?}", started.elapsed());
            }
            Some(code)
        }
        Err(error) => {
            if trace() {
                eprintln!("dmbc analyze: the daemon did not serve this request ({error}); running here");
            }
            None
        }
    }
}

fn exchange(argv: &[String]) -> io::Result<(u8, Vec<u8>, Vec<u8>)> {
    let request = AnalyzeRequest {
        argv: argv.to_vec(),
        env: std::env::vars().collect(),
        cwd: std::env::current_dir()?,
    };
    let step = |what: &'static str| move |e: io::Error| io::Error::new(e.kind(), format!("{what}: {e}"));
    let identity = super::compiler_identity().map_err(step("compiler identity"))?;
    let endpoint = transport::Endpoint::generation(identity).map_err(step("endpoint"))?;
    let allow_lifecycle = std::env::var_os("DMB_DAEMON_AUTOSTART").is_none_or(|value| value != "0");
    let mut lifecycle = lifecycle_deadline::LifecycleDeadline::new(Instant::now());
    let mut started = false;
    let mut request = Some(request);
    loop {
        let remaining = lifecycle.remaining(Instant::now())?;
        match transport::connect(&endpoint) {
            Ok(mut stream) => {
                transport::set_timeout(&mut stream, remaining)?;
                protocol::send(&mut stream, &protocol::Request::Hello { version: protocol::VERSION, compiler: identity })?;
                match protocol::receive::<protocol::Reply>(&mut stream)? {
                    protocol::Reply::Hello { version, compiler, retiring: false } if version == protocol::VERSION && compiler == identity => {
                        transport::set_timeout(&mut stream, transport::BUILD_DEADLINE)?;
                        let Some(request) = request.take() else { return Err(io::Error::other("request already sent")) };
                        protocol::send(&mut stream, &protocol::Request::Analyze(request))?;
                        let (mut out, mut err, mut data) = (Vec::new(), Vec::new(), String::new());
                        loop {
                            match protocol::receive::<protocol::Reply>(&mut stream)? {
                                protocol::Reply::Accepted => {}
                                protocol::Reply::Diagnostic { stdout: true, bytes } => out.extend_from_slice(&bytes),
                                protocol::Reply::Diagnostic { stdout: false, bytes } => err.extend_from_slice(&bytes),
                                protocol::Reply::AnalysisData(part) => data.push_str(&part),
                                protocol::Reply::Analyzed(code) => {
                                    if !data.is_empty() {
                                        let answered: Answered = serde_json::from_str(&data).map_err(io::Error::other)?;
                                        let (_, view) = dq_analyze::report::View::split(argv);
                                        out = view.render(&answered.report, answered.revision, answered.base.as_ref()).into_bytes();
                                    }
                                    return Ok((code, out, err));
                                }
                                protocol::Reply::Rejected(failure) => return Err(io::Error::other(format!("{failure:?}"))),
                                _ => return Err(io::Error::other("unexpected daemon reply")),
                            }
                        }
                    }
                    _ => return Err(io::Error::other("daemon of another generation, or retiring")),
                }
            }
            Err(error) => {
                if !allow_lifecycle || !super::listener_absent(&error) {
                    return Err(step("connecting")(error));
                }
                lifecycle.unavailable(Instant::now())?;
                if !started && !super::resident::same_binary_draining() {
                    super::start().map_err(step("starting the daemon"))?;
                    started = true;
                }
            }
        }
        let remaining = lifecycle.remaining(Instant::now())?;
        std::thread::sleep(Duration::from_millis(100).min(remaining));
    }
}

/// Serves one admitted request on `stream`: streams its output in frames and ends with its exit code.
pub(super) fn serve(stream: &mut transport::Stream, request: AnalyzeRequest) -> io::Result<()> {
    if let Some(available) = super::service::available_memory() {
        if available < MIN_FREE_BYTES {
            return protocol::send(
                stream,
                &protocol::Reply::Rejected(crate::request_failure::RequestFailure::infrastructure(format!(
                    "{:.1} GB of RAM free; an analysis request needs {:.0} GB",
                    available as f64 / (1u64 << 30) as f64,
                    (MIN_FREE_BYTES >> 30) as f64
                ))),
            );
        }
    }
    protocol::send(stream, &protocol::Reply::Accepted)?;
    // A run that starts analyze again (the cold unused-ALLOW recheck) starts this executable as `dmbc analyze`.
    dq_analyze::cli::set_launch_prefix(vec!["analyze".to_string()]);
    let (plain, view) = dq_analyze::report::View::split(&request.argv);
    let env: std::collections::HashMap<String, String> = request.env.iter().cloned().collect();
    if dq_analyze::cli::rememberable(&plain, &env) {
        return serve_remembered(stream, plain, view, env, request.cwd);
    }
    let (tx, rx) = std::sync::mpsc::channel::<(bool, Vec<u8>)>();
    let tx = std::sync::Mutex::new(tx);
    let sink: std::sync::Arc<dq_hostio::Sink> = std::sync::Arc::new(move |stdout: bool, bytes: &[u8]| {
        let _ = tx.lock().unwrap_or_else(|e| e.into_inner()).send((stdout, bytes.to_vec()));
    });
    let (argv, cwd) = (request.argv, request.cwd);
    let next = (argv.clone(), env.clone(), cwd.clone());
    let started = Instant::now();
    *LAST_REQUEST.lock().unwrap_or_else(|e| e.into_inner()) = Some(Instant::now());
    let runner = std::thread::Builder::new()
        .name("analyze-host".into())
        .spawn(move || {
            host_stores();
            let shown = std::path::Path::new(&cwd).display().to_string();
            let code = dq_analyze::cli::run_hosted(argv, env, cwd, sink).code;
            eprintln!("dmbc pid={} root={}: {}", std::process::id(), shown, dq_analyze::incr::stats());
            code
        })
        .map_err(io::Error::other)?;
    // Output in order, coalesced per stream; the channel closes when the request has finished and dropped its sink.
    let mut pending: Option<(bool, Vec<u8>)> = None;
    let mut send_error: Option<io::Error> = None;
    let mut flush = |stream: &mut transport::Stream, part: (bool, Vec<u8>), failed: &mut Option<io::Error>| {
        if failed.is_some() {
            return;
        }
        for chunk in part.1.chunks(CHUNK) {
            if let Err(e) = protocol::send(stream, &protocol::Reply::Diagnostic { stdout: part.0, bytes: chunk.to_vec() }) {
                *failed = Some(e);
                return;
            }
        }
    };
    for (stdout, bytes) in rx {
        match &mut pending {
            Some((s, b)) if *s == stdout && b.len() + bytes.len() <= CHUNK => b.extend_from_slice(&bytes),
            _ => {
                if let Some(part) = pending.take() {
                    flush(stream, part, &mut send_error);
                }
                pending = Some((stdout, bytes));
            }
        }
    }
    if let Some(part) = pending.take() {
        flush(stream, part, &mut send_error);
    }
    let code = runner.join().unwrap_or(70);
    super::emit_stderr(format_args!("dmbd analyze: request finished in {:.1?} (exit {code})", started.elapsed()));
    *LAST_REQUEST.lock().unwrap_or_else(|e| e.into_inner()) = Some(Instant::now());
    if let Some(e) = send_error {
        dq_analyze::cli::finish_hosted();
        return Err(e);
    }
    let answered = protocol::send(stream, &protocol::Reply::Analyzed(code));
    // Read ahead for this root's next request, unless the machine is short of memory (then it would only be shed again).
    if super::service::available_memory().is_none_or(|a| a >= KEEP_FREE_BYTES) {
        let t = Instant::now();
        dq_analyze::cli::prewarm_hosted(&next.0, next.1, next.2);
        super::emit_stderr(format_args!("dmbd analyze: freed the request and read ahead for the next in {:.1?}", t.elapsed()));
    } else {
        dq_analyze::cli::finish_hosted();
    }
    start_shedder();
    answered
}

/// Runs one request to completion with its output collected (an `analysis_db` answer is computed here): (what it did, stdout,
/// stderr). The analysis store backs `incr` meanwhile.
pub(super) fn run_request(
    argv: Vec<String>,
    env: std::collections::HashMap<String, String>,
    cwd: PathBuf,
) -> (dq_analyze::cli::Hosted, Vec<u8>, Vec<u8>) {
    let collected: std::sync::Arc<std::sync::Mutex<(Vec<u8>, Vec<u8>)>> = Default::default();
    let into = std::sync::Arc::clone(&collected);
    let sink: std::sync::Arc<dq_hostio::Sink> = std::sync::Arc::new(move |stdout: bool, bytes: &[u8]| {
        let mut c = into.lock().unwrap_or_else(|e| e.into_inner());
        if stdout {
            c.0.extend_from_slice(bytes)
        } else {
            c.1.extend_from_slice(bytes)
        }
    });
    host_stores();
    let shown = cwd.display().to_string();
    let done = dq_analyze::cli::run_hosted(argv, env, cwd, sink);
    eprintln!("dmbc pid={} root={}: {}", std::process::id(), shown, dq_analyze::incr::stats());
    let (out, err) = std::mem::take(&mut *collected.lock().unwrap_or_else(|e| e.into_inner()));
    (done, out, err)
}

/// A request answered through the root's query database: from memory while nothing it read changed, else run now.
fn serve_remembered(
    stream: &mut transport::Stream,
    argv: Vec<String>,
    view: dq_analyze::report::View,
    env: std::collections::HashMap<String, String>,
    cwd: PathBuf,
) -> io::Result<()> {
    let started = Instant::now();
    *LAST_REQUEST.lock().unwrap_or_else(|e| e.into_inner()) = Some(Instant::now());
    let root = dq_analyze::cli::root_in(&argv, &cwd);
    let next = (argv.clone(), env.clone(), cwd.clone());
    let since = view.since;
    let worker = std::thread::Builder::new()
        .name("analyze-answer".into())
        .stack_size(64 << 20)
        .spawn(move || super::analysis_db::answer(&root, argv, env, cwd, since));
    let (answer, base, computed) = match worker.map_err(io::Error::other)?.join() {
        Ok(a) => a,
        Err(_) => return protocol::send(stream, &protocol::Reply::Analyzed(70)),
    };
    let mut send_error: Option<io::Error> = None;
    let mut send = |reply: protocol::Reply, failed: &mut Option<io::Error>| {
        if failed.is_none() {
            if let Err(e) = protocol::send(stream, &reply) {
                *failed = Some(e);
            }
        }
    };
    match &answer.report {
        Some(report) => {
            let data = serde_json::to_string(&Answered { revision: answer.revision, report: report.clone(), base: base.as_deref().cloned() })
                .map_err(io::Error::other)?;
            let mut rest = data.as_str();
            while !rest.is_empty() {
                let mut cut = rest.len().min(CHUNK);
                while !rest.is_char_boundary(cut) {
                    cut -= 1;
                }
                send(protocol::Reply::AnalysisData(rest[..cut].to_string()), &mut send_error);
                rest = &rest[cut..];
            }
        }
        None => {
            for chunk in answer.stdout.chunks(CHUNK) {
                send(protocol::Reply::Diagnostic { stdout: true, bytes: chunk.to_vec() }, &mut send_error);
            }
        }
    }
    for chunk in answer.stderr.chunks(CHUNK) {
        send(protocol::Reply::Diagnostic { stdout: false, bytes: chunk.to_vec() }, &mut send_error);
    }
    super::emit_stderr(format_args!(
        "dmbd analyze: {} in {:.1?} (revision {}, exit {})",
        if computed { "answered (computed)" } else { "answered from memory" },
        started.elapsed(),
        answer.revision,
        answer.code
    ));
    *LAST_REQUEST.lock().unwrap_or_else(|e| e.into_inner()) = Some(Instant::now());
    if let Some(e) = send_error {
        if computed {
            dq_analyze::cli::finish_hosted();
        }
        return Err(e);
    }
    let answered = protocol::send(stream, &protocol::Reply::Analyzed(answer.code));
    if computed {
        if super::service::available_memory().is_none_or(|a| a >= KEEP_FREE_BYTES) {
            let t = Instant::now();
            dq_analyze::cli::prewarm_hosted(&next.0, next.1, next.2);
            super::emit_stderr(format_args!("dmbd analyze: freed the request and read ahead for the next in {:.1?}", t.elapsed()));
        } else {
            dq_analyze::cli::finish_hosted();
        }
    }
    start_shedder();
    answered
}

/// Where the analysis stores persist inside the daemon (`dq_analyze::incr`): one directory per binary image under
/// `E:/dq-cache/analysis` (`DMB_ANALYSIS_DIR` moves it; `off`: the worktree's own cache directory, as standalone), bounded by
/// `[cache.analysis]` in tools/ci/disk_budget.toml. Each image keeps its own: a persisted entry is valid only for the binary that
/// wrote it (its stamp names the analyzer's sources, not the front end that builds the model). Answers persist there too
/// (`analysis_db`).
pub(super) fn stores_dir() -> Option<&'static Path> {
    static DIR: std::sync::OnceLock<Option<PathBuf>> = std::sync::OnceLock::new();
    DIR.get_or_init(|| {
        let dir = match std::env::var("DMB_ANALYSIS_DIR") {
            Ok(v) if v == "off" => None,
            Ok(v) => Some(PathBuf::from(v)),
            Err(_) => Some(PathBuf::from("E:/dq-cache/analysis")).filter(|p| p.parent().is_some_and(|d| d.is_dir())),
        };
        dir.map(|d| d.join(image_id()))
    })
    .as_deref()
}

/// A content hash of this executable (read once per process).
fn image_id() -> String {
    let bytes = std::env::current_exe().and_then(std::fs::read).unwrap_or_default();
    format!("{:032x}", xxhash_rust::xxh3::xxh3_128(&bytes))
}

static STORES_HOSTED: std::sync::OnceLock<()> = std::sync::OnceLock::new();

/// The first hosted request makes the daemon the stores' host (they then persist in [`stores_dir`]).
fn host_stores() {
    STORES_HOSTED.get_or_init(|| dq_analyze::incr::set_persist_dir(stores_dir().map(Path::to_path_buf)));
}

/// The stores' usage for `SharedStore::report` (none before the first hosted request).
pub(super) fn report_line() -> Option<String> {
    STORES_HOSTED.get()?;
    let (entries, bytes) = dq_analyze::incr::usage();
    Some(format!("; analysis_results: entries={entries} ({bytes} B)"))
}

/// When the last analysis request started or finished.
static LAST_REQUEST: std::sync::Mutex<Option<Instant>> = std::sync::Mutex::new(None);

/// What is read ahead is dropped after this long without a request.
const IDLE_SHED: Duration = Duration::from_secs(10 * 60);
/// ...or as soon as free RAM falls under this (a compile beside it needs the room).
const KEEP_FREE_BYTES: u64 = 8 << 30;

/// Starts (once) the thread that sheds the read-ahead model when idle or short of memory.
fn start_shedder() {
    static STARTED: std::sync::Once = std::sync::Once::new();
    STARTED.call_once(|| {
        let _ = std::thread::Builder::new().name("analyze-shed".into()).spawn(|| loop {
            std::thread::sleep(Duration::from_secs(15));
            let idle = LAST_REQUEST.lock().unwrap_or_else(|e| e.into_inner()).map_or(IDLE_SHED, |t| t.elapsed());
            let short = super::service::available_memory().is_some_and(|a| a < KEEP_FREE_BYTES);
            if idle >= IDLE_SHED || short {
                if dq_analyze::cli::shed_stores() {
                    super::emit_stderr(format_args!("dmbd analyze: dropped the analysis stores from memory (their slots stay on disk)"));
                }
            }
            if !dq_analyze::cli::hosted_resident() {
                continue;
            }
            if (idle >= IDLE_SHED || short) && dq_analyze::cli::shed_hosted() {
                super::emit_stderr(format_args!(
                    "dmbd analyze: dropped the read-ahead model ({})",
                    if short { "short of memory" } else { "idle" }
                ));
            }
        });
    });
}
