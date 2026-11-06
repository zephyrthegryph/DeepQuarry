//! Bounded opt-in subprocess client for resident named and selected reports.
//! The child owns request parsing, source capture and the actual policy run.
use super::{capture_command, OUTER_WATCHDOG};
use crate::selected_exclusions_wire::{Hex128, NamedImageDirTerminal, Roster, Seal, Terminal, MAX_HEADER, MAX_STREAM};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, BufReader, Read, Seek, Write},
    path::{Path, PathBuf},
    process::Command,
    sync::atomic::{AtomicU64, Ordering},
};
use xxhash_rust::xxh3::Xxh3;

const BLOCK: usize = 8192;
static NEXT: AtomicU64 = AtomicU64::new(1);

fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

#[derive(Clone, Copy)]
enum Role { Exclusions, ImageDir }
impl Role {
    fn command(self) -> &'static str {
        match self { Self::Exclusions => "analyze-exclusions", Self::ImageDir => "analyze-image-dir" }
    }
    fn label(self) -> &'static str {
        match self { Self::Exclusions => "native-exclusions", Self::ImageDir => "native-image-dir" }
    }
}
enum Selection { Exclusions(Roster), ImageDir }
struct Options {
    program: PathBuf,
    request: PathBuf,
    scratch: PathBuf,
    selection: Selection,
}

fn options(args: &[String], role: Role) -> io::Result<Options> {
    let usage = || io::Error::new(io::ErrorKind::InvalidInput, match role {
        Role::Exclusions => "usage: analyze native-exclusions --dmbc ABSOLUTE_EXE --scratch ABSOLUTE_DIR --roster base|with-cooldown|with-engine-internal|with-silicon|with-library-layering|with-handlers|with-semantic-reads|with-setter-publishes|with-reactive-policies REQUEST.json",
        Role::ImageDir => "usage: analyze-native native-image-dir --dmbc ABSOLUTE_EXE --scratch ABSOLUTE_DIR REQUEST.json",
    });
    let mut program = None;
    let mut request = None;
    let mut scratch = None;
    let mut roster = None;
    let mut rest = args.iter();
    while let Some(arg) = rest.next() {
        match arg.as_str() {
            "--dmbc" if program.is_none() => program = Some(PathBuf::from(rest.next().ok_or_else(usage)?)),
            "--scratch" if scratch.is_none() => scratch = Some(PathBuf::from(rest.next().ok_or_else(usage)?)),
            "--roster" if matches!(role, Role::Exclusions) && roster.is_none() => roster = Some(match rest.next().map(String::as_str) {
                Some("base") => Roster::Base,
                Some("with-cooldown") => Roster::WithCooldown,
                Some("with-engine-internal") => Roster::WithEngineInternal,
                Some("with-silicon") => Roster::WithSilicon,
                Some("with-library-layering") => Roster::WithLibraryLayering,
                Some("with-handlers") => Roster::WithHandlers,
                Some("with-semantic-reads") => Roster::WithSemanticReads,
                Some("with-setter-publishes") => Roster::WithSetterPublishes,
                Some("with-reactive-policies") => Roster::WithReactivePolicies,
                _ => return Err(usage()),
            }),
            name if !name.starts_with('-') && request.is_none() => request = Some(PathBuf::from(name)),
            _ => return Err(usage()),
        }
    }
    let program = program.filter(|path| path.is_absolute()).ok_or_else(usage)?;
    let scratch = scratch.filter(|path| path.is_absolute()).ok_or_else(usage)?;
    let scratch = fs::canonicalize(scratch)?;
    if !scratch.is_dir() {
        return Err(usage());
    }
    let selection = match role {
        Role::Exclusions => Selection::Exclusions(roster.ok_or_else(usage)?),
        Role::ImageDir => Selection::ImageDir,
    };
    Ok(Options { program, scratch, request: request.ok_or_else(usage)?, selection })
}

// Both readers keep one private handle. Unix unlinks this invocation's newly
// created file immediately. Windows uses a private delete-on-close handle.
fn scratch_file(root: &Path) -> io::Result<File> {
    for _ in 0..16 {
        let nonce = NEXT.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| value.checked_add(1))
            .map_err(|_| io::Error::other("exclusions scratch identities exhausted"))?;
        let path = root.join(format!(".analyze-exclusions-{}-{nonce}", std::process::id()));
        let mut open = OpenOptions::new();
        open.read(true).write(true).create_new(true);
        #[cfg(windows)]
        {
            use std::os::windows::fs::OpenOptionsExt;
            const GENERIC_READ: u32 = 0x8000_0000;
            const GENERIC_WRITE: u32 = 0x4000_0000;
            const DELETE_ACCESS: u32 = 0x0001_0000;
            const FILE_ATTRIBUTE_TEMPORARY: u32 = 0x0000_0100;
            const FILE_FLAG_DELETE_ON_CLOSE: u32 = 0x0400_0000;
            open.access_mode(GENERIC_READ | GENERIC_WRITE | DELETE_ACCESS)
                .share_mode(0).custom_flags(FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE);
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            open.mode(0o600);
        }
        match open.open(&path) {
            Ok(file) => {
                #[cfg(unix)]
                fs::remove_file(&path)?;
                return Ok(file);
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
    Err(io::Error::new(io::ErrorKind::AlreadyExists, "exclusions scratch namespace collision limit reached"))
}

struct Captured {
    file: File,
    seal: Seal,
}
impl Captured {
    fn read(input: &mut impl Read, root: &Path, limit: u64) -> io::Result<Self> {
        let mut file = scratch_file(root)?;
        let mut hash = Xxh3::new();
        let mut length = 0u64;
        let mut buffer = [0; BLOCK];
        loop {
            // Probe only one byte beyond the actual limit. Never write it.
            let capacity = (limit - length + 1).min(BLOCK as u64) as usize;
            let count = input.read(&mut buffer[..capacity])?;
            if count == 0 { break; }
            length = length.checked_add(count as u64).filter(|&n| n <= limit)
                .ok_or_else(|| invalid("exclusions stream exceeds its declared or physical bound"))?;
            file.write_all(&buffer[..count])?;
            hash.update(&buffer[..count]);
        }
        file.flush()?;
        file.rewind()?;
        Ok(Self { file, seal: Seal { length, hash: Hex128(hash.digest128()) } })
    }

    fn publish(self, output: &mut impl Write) -> io::Result<()> {
        if self.seal.length == 0 { return Ok(()); }
        let mut file = self.file.take(self.seal.length);
        let count = io::copy(&mut file, output)?;
        if count != self.seal.length {
            return Err(invalid("verified exclusions scratch became incomplete"));
        }
        output.flush()
    }
}

struct Stdout<T> {
    bytes: [u8; MAX_HEADER],
    length: usize,
    header: T,
    report: Captured,
}

fn capture_batch<T: serde::de::DeserializeOwned>(
    input: impl Read, root: &Path, report_seal: impl FnOnce(&T) -> io::Result<Seal>,
) -> io::Result<Option<Stdout<T>>> {
    let mut input = BufReader::new(input);
    let mut bytes = [0u8; MAX_HEADER];
    let mut length = 0;
    loop {
        if length == MAX_HEADER {
            return Err(invalid("native report header exceeds its fixed bound"));
        }
        if input.read(&mut bytes[length..length + 1])? == 0 {
            return if length == 0 { Ok(None) } else { Err(invalid("incomplete native report header")) };
        }
        length += 1;
        if bytes[length - 1] == b'\n' { break; }
    }
    let header = serde_json::from_slice(&bytes[..length - 1])
        .map_err(|_| invalid("invalid native report batch header"))?;
    let seal = report_seal(&header)?;
    let report = Captured::read(&mut input, root, seal.length)?;
    if report.seal != seal {
        return Err(invalid("native report length or digest differs"));
    }
    Ok(Some(Stdout { bytes, length, header, report }))
}

fn capture_stdout(input: impl Read, root: &Path, expected: Roster) -> io::Result<Option<Stdout<Terminal>>> {
    capture_batch(input, root, |header: &Terminal| { header.require(expected)?; Ok(header.report) })
}

fn capture_image_dir_stdout(input: impl Read, root: &Path) -> io::Result<Option<Stdout<NamedImageDirTerminal>>> {
    capture_batch(input, root, |header: &NamedImageDirTerminal| { header.require()?; Ok(header.report) })
}

fn deliver(
    status: Option<i32>, stdout: Option<Stdout<Terminal>>, stderr: Captured,
    output: &mut impl Write, diagnostics: &mut impl Write,
) -> io::Result<u8> {
    match (status, stdout) {
        (Some(code @ (0 | 1)), Some(batch)) => {
            let observed = (stderr.seal.length != 0).then_some(stderr.seal);
            if batch.header.clean != (code == 0) || batch.header.diagnostics != observed {
                return Err(invalid("exclusions batch status or diagnostic seal differs"));
            }
            // The child and both readers have finished. No real result or
            // diagnostics can escape on a malformed/truncated batch.
            stderr.publish(diagnostics)?;
            output.write_all(&batch.bytes[..batch.length])?;
            batch.report.publish(output)?;
            Ok(code as u8)
        }
        (Some(0 | 1), None) | (_, Some(_)) => Err(invalid("exclusions process status lacks its matching batch")),
        (status, None) => {
            // A genuine operational refusal has no stdout envelope. Keep
            // its separate error diagnostic and the cancellation status.
            stderr.publish(diagnostics)?;
            Ok(if status == Some(75) { 75 } else { 2 })
        }
    }
}

fn deliver_image_dir(
    status: Option<i32>, stdout: Option<Stdout<NamedImageDirTerminal>>, stderr: Captured,
    output: &mut impl Write, diagnostics: &mut impl Write,
) -> io::Result<u8> {
    match (status, stdout) {
        (Some(code @ (0 | 1)), Some(batch)) => {
            if batch.header.clean != (code == 0) || stderr.seal.length != 0 {
                return Err(invalid("ImageDir status differs or notice-free batch has stderr"));
            }
            // The metadata is transport evidence. Analyze stdout is only the
            // exact legacy-compatible report, including a finding result.
            batch.report.publish(output)?;
            Ok(code as u8)
        }
        (Some(code @ (2 | 75)), None) => {
            stderr.publish(diagnostics)?;
            Ok(code as u8)
        }
        _ => Err(invalid("ImageDir process status lacks its matching batch or refusal")),
    }
}

fn run_cli(args: &[String], role: Role, output: &mut impl Write, diagnostics: &mut impl Write) -> io::Result<u8> {
    let Options { program, request, scratch, selection } = options(args, role)?;
    let mut command = Command::new(program);
    // Only dmbc opens and interprets the request. The parent supplies no
    // workspace fields, source authority, or fallback execution path.
    command.arg(role.command()).arg(request).arg("--report-batch");
    let stderr_root = scratch.clone();
    let read_stderr = move |mut stderr| Captured::read(&mut stderr, &stderr_root, MAX_STREAM);
    match selection {
        Selection::Exclusions(roster) => {
            let (status, stdout, stderr) = capture_command(command, OUTER_WATCHDOG,
                move |stdout| capture_stdout(stdout, &scratch, roster), read_stderr)?;
            deliver(status.code(), stdout, stderr, output, diagnostics)
        }
        Selection::ImageDir => {
            let (status, stdout, stderr) = capture_command(command, OUTER_WATCHDOG,
                move |stdout| capture_image_dir_stdout(stdout, &scratch), read_stderr)?;
            deliver_image_dir(status.code(), stdout, stderr, output, diagnostics)
        }
    }
}

fn cli_for(args: &[String], role: Role) -> std::process::ExitCode {
    let result = run_cli(args, role, &mut io::stdout().lock(), &mut io::stderr().lock());
    match result {
        Ok(code) => std::process::ExitCode::from(code),
        Err(error) => {
            eprintln!("analyze {}: {error}", role.label());
            std::process::ExitCode::from(2)
        }
    }
}

pub(super) fn cli(args: &[String]) -> std::process::ExitCode { cli_for(args, Role::Exclusions) }
pub(super) fn image_dir_cli(args: &[String]) -> std::process::ExitCode { cli_for(args, Role::ImageDir) }

#[cfg(test)]
#[path = "native_exclusions_tests.rs"]
mod tests;
