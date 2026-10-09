//! Local daemon over the same request runner; transport owns no compiler pipeline.
use std::{
    io,
    sync::{Arc, Mutex},
    time::Duration,
};
pub mod control;
mod protocol;
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
    use std::io::Read;
    let mut input = std::fs::File::open(std::env::current_exe()?)?;
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    let mut bytes = [0; 65536];
    loop {
        let count = input.read(&mut bytes)?;
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
    if request.no_daemon || request.trace_path.is_some() {
        return crate::request_runner::run_build(request);
    }
    let mut request = request;
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
    let endpoint = transport::Endpoint::current()?;
    let identity = compiler_identity()?;
    let mut started = false;
    let startup_deadline = std::time::Instant::now() + Duration::from_secs(20);
    for attempt in 0..200 {
        let remaining = startup_deadline
            .checked_duration_since(std::time::Instant::now())
            .filter(|duration| !duration.is_zero())
            .ok_or("daemon failed to start or drain within 20 seconds")?;
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
                protocol::Reply::Hello { .. } => {
                    protocol::send(&mut stream, &protocol::Request::Retire)?;
                    let _ = protocol::receive::<protocol::Reply>(&mut stream);
                }
                _ => return Err("invalid daemon handshake".into()),
            }
        } else if !started {
            start()?;
            started = true;
        }
        if attempt == 199 {
            return Err("daemon failed to start or drain within 20 seconds".into());
        }
        let remaining = startup_deadline.saturating_duration_since(std::time::Instant::now());
        std::thread::sleep(Duration::from_millis(100).min(remaining));
    }
    unreachable!()
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
