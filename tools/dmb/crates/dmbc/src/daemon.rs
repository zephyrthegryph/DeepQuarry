//! Local daemon over the same request runner; transport owns no compiler pipeline.
use std::{
    io,
    sync::{Arc, Mutex},
    time::Duration,
};
mod build_admission;
pub mod control;
pub mod endpoint_descriptor;
mod generation_listeners;
mod lifecycle_deadline;
mod protocol;
pub mod query;
mod service;
mod transport;

type OutputSink = Box<dyn Fn(bool, &[u8]) -> io::Result<()>>;
thread_local! {static OUTPUT:std::cell::RefCell<Option<OutputSink>>=const{std::cell::RefCell::new(None)};}
#[macro_export]
macro_rules! daemon_println {
    () => { $crate::daemon::emit_stdout(format_args!("")) };
    ($($argument:tt)*) => { $crate::daemon::emit_stdout(format_args!($($argument)*)) };
}
#[macro_export]
macro_rules! daemon_eprintln {
    () => { $crate::daemon::emit_stderr(format_args!("")) };
    ($($argument:tt)*) => { $crate::daemon::emit_stderr(format_args!($($argument)*)) };
}
pub fn emit_stderr(args: std::fmt::Arguments<'_>) {
    emit(false, args)
}
pub fn emit_stdout(args: std::fmt::Arguments<'_>) {
    emit(true, args)
}
fn emit(stdout: bool, args: std::fmt::Arguments<'_>) {
    use std::io::Write;
    let mut writer = OutputWriter { stdout };
    writer
        .write_fmt(args)
        .and_then(|()| writer.write_all(b"\n"))
        .expect("compiler diagnostic stream write failed");
}
/// Streaming adapters preserve arbitrary bytes and partial JSON-lines writes.
pub struct OutputWriter {
    stdout: bool,
}
pub fn stdout_writer() -> OutputWriter {
    OutputWriter { stdout: true }
}
pub fn stderr_writer() -> OutputWriter {
    OutputWriter { stdout: false }
}
impl io::Write for OutputWriter {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        OUTPUT.with(|sink| {
            if let Some(sink) = sink.borrow().as_ref() {
                for chunk in bytes.chunks(65536) {
                    sink(self.stdout, chunk)?;
                }
                Ok(bytes.len())
            } else if self.stdout {
                io::Write::write(&mut io::stdout().lock(), bytes)
            } else {
                io::Write::write(&mut io::stderr().lock(), bytes)
            }
        })
    }
    fn flush(&mut self) -> io::Result<()> {
        OUTPUT.with(|sink| {
            if sink.borrow().is_some() {
                Ok(())
            } else if self.stdout {
                io::Write::flush(&mut io::stdout().lock())
            } else {
                io::Write::flush(&mut io::stderr().lock())
            }
        })
    }
}
struct OutputBinding;
impl Drop for OutputBinding {
    fn drop(&mut self) {
        OUTPUT.with(|sink| *sink.borrow_mut() = None);
    }
}
fn output_binding(stream: Arc<Mutex<transport::Stream>>) -> OutputBinding {
    OUTPUT.with(|sink| {
        *sink.borrow_mut() = Some(Box::new(move |stdout, bytes| {
            protocol::send(
                &mut *stream.lock().unwrap_or_else(|e| e.into_inner()),
                &protocol::Reply::Diagnostic {
                    stdout,
                    bytes: bytes.to_vec(),
                },
            )
        }))
    });
    OutputBinding
}
pub fn serve() -> io::Result<()> {
    service::serve()
}
pub fn compiler_identity() -> io::Result<u128> {
    // Identity belongs to this running compiler generation. A replacement on disk
    // must produce a different client identity, not relabel an already-loaded daemon.
    static LOADED_IDENTITY: std::sync::OnceLock<u128> = std::sync::OnceLock::new();
    if let Some(identity) = LOADED_IDENTITY.get() {
        return Ok(*identity);
    }
    let identity = hash_compiler_image()?;
    Ok(*LOADED_IDENTITY.get_or_init(|| identity))
}
fn hash_compiler_image() -> io::Result<u128> {
    let _profile = dm_profile::stage("filesystem.compiler_identity");
    use std::io::Read;
    let mut input = std::fs::File::open(std::env::current_exe()?)?;
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    let mut bytes = [0; 65536];
    loop {
        let count = dm_profile::io_call(|| input.read(&mut bytes), |count| (*count as u64, 0))?;
        if count == 0 {
            break;
        }
        hash.update(&bytes[..count]);
    }
    Ok(hash.digest128())
}
/// Profile requests remain local: concurrent daemon process counters cannot certify them.
pub fn route(
    request: crate::request::BuildRequest,
) -> Result<crate::request::BuildOutcome, Box<dyn std::error::Error>> {
    let mut request = request;
    if request.cache_root.is_none() {
        request.cache_root = Some(crate::request::client_cache_root()?);
    }
    if let Some(root) = &mut request.cache_root {
        if !root.is_absolute() {
            *root = std::env::current_dir()?.join(&*root);
        }
    }
    if request.no_daemon || request.trace_path.is_some() {
        return crate::request_runner::run_build(request);
    }
    // Supervisors may require an already-owned server and prohibit lifecycle changes.
    let allow_lifecycle = std::env::var_os("DMB_DAEMON_AUTOSTART").is_none_or(|value| value != "0");
    let cwd = std::env::current_dir()?;
    if !request.project.is_absolute() {
        request.project = cwd.join(&request.project);
    }
    for path in [
        &mut request.engine_template,
        &mut request.output_store,
        &mut request.record_inputs,
        &mut request.replay_inputs,
        &mut request.artifact_directory,
    ] {
        if let Some(value) = path.as_mut() {
            if !value.is_absolute() {
                *value = cwd.join(&*value);
            }
        }
    }
    let identity = compiler_identity()?;
    let endpoint = transport::Endpoint::generation(identity)?;
    let mut started = false;
    let mut lifecycle = lifecycle_deadline::LifecycleDeadline::new(std::time::Instant::now());
    loop {
        let remaining = lifecycle.remaining(std::time::Instant::now())?;
        let connection = transport::connect(&endpoint);
        if let Ok(mut stream) = connection {
            transport::set_timeout(&mut stream, remaining)?;
            protocol::send(
                &mut stream,
                &protocol::Request::Hello {
                    version: protocol::VERSION,
                    compiler: identity,
                },
            )?;
            match protocol::receive::<protocol::Reply>(&mut stream)? {
                protocol::Reply::Hello {
                    version,
                    compiler,
                    retiring,
                } if version == protocol::VERSION && compiler == identity && !retiring => {
                    transport::set_timeout(&mut stream, Duration::from_secs(600))?;
                    protocol::send(&mut stream, &protocol::Request::Build(request))?;
                    loop {
                        match protocol::receive::<protocol::Reply>(&mut stream)? {
                            protocol::Reply::Accepted => {}
                            protocol::Reply::Diagnostic { stdout, bytes } => {
                                use std::io::Write;
                                if stdout {
                                    io::stdout().lock().write_all(&bytes)?;
                                } else {
                                    io::stderr().lock().write_all(&bytes)?;
                                }
                            }
                            protocol::Reply::Completed(outcome) => return Ok(outcome),
                            protocol::Reply::Rejected(error) => return Err(error.into()),
                            _ => return Err("unexpected daemon reply".into()),
                        }
                    }
                }
                protocol::Reply::Hello { .. } if !allow_lifecycle => {
                    return Err(
                        "existing daemon is incompatible or retiring; lifecycle changes disabled"
                            .into(),
                    );
                }
                protocol::Reply::Hello {
                    version,
                    compiler,
                    retiring: true,
                } if version == protocol::VERSION && compiler == identity => {
                    // Explicit retirement of THIS identical compiler must drain
                    // before restarting its same endpoint. Different generations
                    // never enter this wait; each has a separate listener.
                    lifecycle.retiring(std::time::Instant::now())?;
                    started = false;
                    protocol::send(&mut stream, &protocol::Request::Retire)?;
                    let _ = protocol::receive::<protocol::Reply>(&mut stream);
                }
                _ => return Err("invalid compiler-generation daemon handshake".into()),
            }
        } else if !allow_lifecycle {
            return Err("required existing daemon is unavailable; autostart disabled".into());
        } else if let Err(error) = connection {
            // Busy pipes and transient failures are not evidence that the old
            // generation has drained. Only an absent listener permits replacement.
            if listener_absent(&error) {
                lifecycle.unavailable(std::time::Instant::now())?;
                if !started {
                    // Discovery is advisory lifecycle control, never the build
                    // destination. An old busy listener cannot block the new
                    // generation from starting or change its request semantics.
                    if let Err(error) = retire_discovered(identity, remaining) {
                        eprintln!("native daemon: previous generation retirement unavailable: {error}; starting requested generation");
                    }
                    lifecycle.remaining(std::time::Instant::now())?;
                    start()?;
                    started = true;
                }
            }
        }
        let remaining = lifecycle.remaining(std::time::Instant::now())?;
        std::thread::sleep(Duration::from_millis(100).min(remaining));
    }
}
fn retire_discovered(identity: u128, remaining: Duration) -> io::Result<()> {
    let discovery = transport::Endpoint::discovery()?;
    let connection = transport::connect(&discovery);
    let connection = match connection {
        Err(error) if listener_absent(&error) => {
            transport::connect(&transport::Endpoint::current()?)
        }
        result => result,
    };
    let mut stream = match connection {
        Ok(stream) => stream,
        Err(error) if listener_absent(&error) => return Ok(()),
        Err(error) => return Err(error),
    };
    transport::set_timeout(&mut stream, remaining.min(Duration::from_secs(3)))?;
    protocol::send(
        &mut stream,
        &protocol::Request::Hello {
            version: protocol::VERSION,
            compiler: identity,
        },
    )?;
    match protocol::receive::<protocol::Reply>(&mut stream)? {
        protocol::Reply::Hello { compiler, .. } if compiler != identity => {
            protocol::send(&mut stream, &protocol::Request::Retire)?;
            match protocol::receive::<protocol::Reply>(&mut stream)? {
                protocol::Reply::Retiring => Ok(()),
                _ => Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "old daemon did not acknowledge retirement",
                )),
            }
        }
        protocol::Reply::Hello { .. } => Ok(()),
        _ => Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid discovery daemon handshake",
        )),
    }
}
fn listener_absent(error: &io::Error) -> bool {
    if error.kind() == io::ErrorKind::NotFound {
        return true;
    }
    #[cfg(unix)]
    if error.kind() == io::ErrorKind::ConnectionRefused {
        return true;
    }
    false
}

fn start() -> io::Result<()> {
    let mut command = std::process::Command::new(std::env::current_exe()?);
    command
        .arg("--serve-daemon")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr({
            let directory = std::path::PathBuf::from("E:/dq-cache/dmb-daemon");
            std::fs::create_dir_all(&directory)?;
            std::process::Stdio::from(
                std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(directory.join("lifecycle.log"))?,
            )
        });
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }
    command.spawn()?;
    Ok(())
}

#[cfg(test)]
mod output_tests {
    use super::*;
    use std::io::Write;
    #[test]
    fn fragments_and_print_macros_preserve_exact_bytes() {
        let records = Arc::new(Mutex::new(Vec::new()));
        let captured = Arc::clone(&records);
        OUTPUT.with(|sink| {
            *sink.borrow_mut() = Some(Box::new(move |stdout, bytes| {
                captured.lock().unwrap().push((stdout, bytes.to_vec()));
                Ok(())
            }))
        });
        let _binding = OutputBinding;
        stdout_writer().write_all(b"{\"x\":").unwrap();
        stdout_writer().write_all(&[0xce]).unwrap();
        stdout_writer().write_all(&[0xbb, 0xff]).unwrap();
        crate::daemon_println!("{}", 7);
        crate::daemon_eprintln!();
        let big = vec![b'a'; 131073];
        stderr_writer().write_all(&big).unwrap();
        stdout_writer().flush().unwrap();
        let records = records.lock().unwrap();
        assert!(records.iter().all(|(_, bytes)| bytes.len() <= 65536));
        let stdout: Vec<u8> = records
            .iter()
            .filter(|(out, _)| *out)
            .flat_map(|(_, bytes)| bytes.iter().copied())
            .collect();
        assert_eq!(stdout, b"{\"x\":\xce\xbb\xff7\n");
        let stderr: Vec<u8> = records
            .iter()
            .filter(|(out, _)| !*out)
            .flat_map(|(_, bytes)| bytes.iter().copied())
            .collect();
        assert_eq!(stderr[0], b'\n');
        assert_eq!(&stderr[1..], big);
    }
    #[test]
    fn disconnected_stream_errors_are_not_silently_dropped() {
        OUTPUT.with(|sink| {
            *sink.borrow_mut() = Some(Box::new(|_, _| {
                Err(io::Error::new(io::ErrorKind::BrokenPipe, "fixture"))
            }))
        });
        let _binding = OutputBinding;
        assert_eq!(
            stdout_writer().write_all(b"fragment").unwrap_err().kind(),
            io::ErrorKind::BrokenPipe
        );
        assert!(std::panic::catch_unwind(|| crate::daemon_eprintln!("diagnostic")).is_err());
    }
}
