//! `dmbc analyze`: the lint and analysis engine (tools/analyze) served by this daemon, so one resident program compiles and
//! analyzes (doc/rewrite/proposals/lean_unified.md).
//!
//! The client sends its command line, environment and working directory; the daemon runs the request through
//! `dq_analyze::cli::run_hosted` (one at a time, on threads of its own, output and environment scoped to the request) and returns
//! its stdout, stderr and exit code. The client prints them only once the request has finished, so a request that fails on the
//! way (the daemon died, a protocol error, admission refused) falls back to running in the client with nothing printed twice.
//! `DQ_ANALYZE_DAEMON=0` (and `CI`) run in the client.

use super::{lifecycle_deadline, protocol, transport};
use serde::{Deserialize, Serialize};
use std::io;
use std::path::PathBuf;
use std::time::{Duration, Instant};

#[derive(Serialize, Deserialize)]
pub(super) struct AnalyzeRequest {
    pub argv: Vec<String>,
    pub env: Vec<(String, String)>,
    pub cwd: PathBuf,
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
                        let (mut out, mut err) = (Vec::new(), Vec::new());
                        loop {
                            match protocol::receive::<protocol::Reply>(&mut stream)? {
                                protocol::Reply::Accepted => {}
                                protocol::Reply::Diagnostic { stdout: true, bytes } => out.extend_from_slice(&bytes),
                                protocol::Reply::Diagnostic { stdout: false, bytes } => err.extend_from_slice(&bytes),
                                protocol::Reply::Analyzed(code) => return Ok((code, out, err)),
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
    let (tx, rx) = std::sync::mpsc::channel::<(bool, Vec<u8>)>();
    let tx = std::sync::Mutex::new(tx);
    let sink: std::sync::Arc<dq_hostio::Sink> = std::sync::Arc::new(move |stdout: bool, bytes: &[u8]| {
        let _ = tx.lock().unwrap_or_else(|e| e.into_inner()).send((stdout, bytes.to_vec()));
    });
    let env: std::collections::HashMap<String, String> = request.env.into_iter().collect();
    let (argv, cwd) = (request.argv, request.cwd);
    let next = (argv.clone(), env.clone(), cwd.clone());
    let started = Instant::now();
    *LAST_REQUEST.lock().unwrap_or_else(|e| e.into_inner()) = Some(Instant::now());
    let runner = std::thread::Builder::new()
        .name("analyze-host".into())
        .spawn(move || {
            // The daemon-wide analysis store backs `incr` on this hosted path (analysis_store.rs).
            let store = super::analysis_store::started();
            store.begin(std::path::Path::new(&cwd));
            let shown = std::path::Path::new(&cwd).display().to_string();
            let code = dq_analyze::cli::run_hosted(argv, env, cwd, sink);
            eprintln!("dmbc pid={} root={}: {}", std::process::id(), shown, store.end());
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
                let freed = super::analysis_model::shed();
                if freed > 0 {
                    super::emit_stderr(format_args!("dmbd analyze: dropped the remembered models ({} MB)", freed >> 20));
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
