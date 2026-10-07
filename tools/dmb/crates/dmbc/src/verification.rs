//! A sequential, snapshot-fed cold oracle, with separate output directories.
use std::{
    fs,
    io::{self, Read},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub fn run_cli(arguments: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    if arguments.first().map(String::as_str) != Some("compile") {
        return Err("--verify is supported for compile".into());
    }
    if arguments.iter().any(|arg| {
        matches!(
            arg.as_str(),
            "--record-inputs" | "--replay-inputs" | "--artifact-directory"
        )
    }) {
        return Err("--verify cannot be combined with internal capture/replay options".into());
    }
    let mut path = None;
    let mut skip = false;
    for arg in arguments.iter().skip(1) {
        if skip {
            skip = false;
            continue;
        }
        if matches!(
            arg.as_str(),
            "--workers" | "--output-store" | "--engine-template" | "-D"
        ) {
            skip = true;
            continue;
        }
        if !arg.starts_with('-') {
            path = Some(PathBuf::from(arg));
        }
    }
    let project = fs::canonicalize(path.ok_or("verification manifest missing")?)?;
    let nonce = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let directory = project
        .parent()
        .ok_or("manifest parent missing")?
        .join(".dmbc/verification")
        .join(format!("{}-{nonce}", std::process::id()));
    fs::create_dir_all(&directory)?;
    let journal = directory.join("inputs");
    let incremental = directory.join("incremental");
    let cold = directory.join("cold");
    let deadline = Instant::now() + Duration::from_secs(285);
    let mut base: Vec<String> = arguments
        .iter()
        .filter(|arg| !matches!(arg.as_str(), "--verify" | "--progress" | "--no-cache"))
        .cloned()
        .collect();
    base.extend([
        "--record-inputs".into(),
        journal.to_string_lossy().into_owned(),
        "--artifact-directory".into(),
        incremental.to_string_lossy().into_owned(),
    ]);
    let first = run_child(&base, &directory.join("incremental.log"), deadline)?;
    let mut fresh: Vec<String> = arguments
        .iter()
        .filter(|arg| !matches!(arg.as_str(), "--verify" | "--progress" | "--no-cache"))
        .cloned()
        .collect();
    fresh.extend([
        "--no-cache".into(),
        "--replay-inputs".into(),
        journal.to_string_lossy().into_owned(),
        "--artifact-directory".into(),
        cold.to_string_lossy().into_owned(),
    ]);
    let second = run_child(&fresh, &directory.join("cold.log"), deadline)?;
    if first.is_none() || second.is_none() {
        return Err(format!(
            "verification child terminated without an exit code; evidence {}",
            directory.display()
        )
        .into());
    }
    if first != second {
        return Err(format!(
            "verification exit-status mismatch; evidence {}",
            directory.display()
        )
        .into());
    }
    let diagnostics = |path: PathBuf| -> io::Result<Vec<String>> {
        Ok(fs::read_to_string(path)?
            .lines()
            .filter(|line| !is_measurement(line))
            .map(str::to_owned)
            .collect())
    };
    if diagnostics(directory.join("incremental.log"))? != diagnostics(directory.join("cold.log"))? {
        return Err(format!(
            "verification diagnostic mismatch; evidence {}",
            directory.display()
        )
        .into());
    }
    if first == Some(0) {
        let filename = project.file_name().ok_or("manifest filename missing")?;
        for extension in ["dmb", "rsc"] {
            if !same_bytes(
                &incremental.join(filename).with_extension(extension),
                &cold.join(filename).with_extension(extension),
            )? {
                return Err(format!(
                    "verification {extension} mismatch; evidence {}",
                    directory.display()
                )
                .into());
            }
        }
        let pair: crate::publish::OutputPair = serde_json::from_slice(&fs::read(
            incremental.join(filename).with_extension("dmb-pair.json"),
        )?)?;
        let explicit_store = arguments
            .windows(2)
            .find(|args| args[0] == "--output-store")
            .map(|args| PathBuf::from(&args[1]));
        let store = crate::publish::PairStore::open(match explicit_store {
            Some(path) => path,
            None => crate::publish::default_store_path(&project)?,
        })?;
        // Acquire the ordinary build lock only after the two isolated children
        // finish. Publication installs the already-authenticated matching pair.
        let _lock = crate::compile_driver::acquire_build_lock(&project)?;
        store.install(
            pair.id,
            &project.with_extension("dmb"),
            &project.with_extension("rsc"),
            &project.with_extension("dmb-pair.json"),
        )?;
    }
    if first != Some(0) {
        return Err(format!("both incremental and cold compilation rejected the captured input with matching diagnostics; evidence {}", directory.display()).into());
    }
    eprintln!(
        "native verification passed: output and diagnostics match; evidence {}",
        directory.display()
    );
    Ok(())
}
fn is_measurement(line: &str) -> bool {
    [
        "native stages:",
        "native compile:",
        "native resolver memo:",
        "native lowering memo:",
        "native failed stages:",
        "native cache unavailable:",
        "native cache snapshot rejected:",
        "native cache publication skipped:",
        "native cache lease skipped:",
        "native telemetry skipped:",
    ]
    .iter()
    .any(|prefix| line.starts_with(prefix))
}
fn run_child(arguments: &[String], log: &Path, deadline: Instant) -> io::Result<Option<i32>> {
    if Instant::now() >= deadline {
        return Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "verification deadline expired before child launch",
        ));
    }
    let mut command = Command::new(std::env::current_exe()?);
    command
        .args(arguments)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::from(fs::File::create(log)?));
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000); // CREATE_NO_WINDOW
    }
    let mut child = command.spawn()?;
    loop {
        let status = match child.try_wait() {
            Ok(status) => status,
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(error);
            }
        };
        if let Some(status) = status {
            return Ok(status.code());
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "verification exceeded 285 seconds",
            ));
        }
        thread::sleep(Duration::from_millis(20));
    }
}
fn same_bytes(left: &Path, right: &Path) -> io::Result<bool> {
    let mut left = fs::File::open(left)?;
    let mut right = fs::File::open(right)?;
    let before_left = left.metadata()?;
    let before_right = right.metadata()?;
    if !before_left.is_file() || !before_right.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "verification artifact is not a regular file",
        ));
    }
    if before_left.len() != before_right.len() {
        return Ok(false);
    }
    let equal = same_streams(&mut left, &mut right, before_left.len())?;
    let after_left = left.metadata()?;
    let after_right = right.metadata()?;
    if before_left.len() != after_left.len()
        || before_right.len() != after_right.len()
        || before_left.modified()? != after_left.modified()?
        || before_right.modified()? != after_right.modified()?
    {
        return Err(io::Error::new(
            io::ErrorKind::Interrupted,
            "verification artifact changed during comparison",
        ));
    }
    Ok(equal)
}
fn same_streams(left: &mut impl Read, right: &mut impl Read, mut length: u64) -> io::Result<bool> {
    let mut a = [0u8; 65536];
    let mut b = [0u8; 65536];
    while length != 0 {
        let count = length.min(a.len() as u64) as usize;
        left.read_exact(&mut a[..count])?;
        right.read_exact(&mut b[..count])?;
        if a[..count] != b[..count] {
            return Ok(false);
        }
        length -= count as u64;
    }
    let mut extra_a = [0u8; 1];
    let mut extra_b = [0u8; 1];
    if left.read(&mut extra_a)? != 0 || right.read(&mut extra_b)? != 0 {
        return Err(io::Error::new(
            io::ErrorKind::Interrupted,
            "verification artifact grew during comparison",
        ));
    }
    Ok(true)
}
#[cfg(test)]
mod tests {
    use super::*;
    struct Short<'a> {
        bytes: &'a [u8],
        chunk: usize,
    }
    impl Read for Short<'_> {
        fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
            let count = out.len().min(self.chunk).min(self.bytes.len());
            out[..count].copy_from_slice(&self.bytes[..count]);
            self.bytes = &self.bytes[count..];
            Ok(count)
        }
    }
    #[test]
    fn verification_comparison_accepts_different_short_read_boundaries() {
        let bytes = vec![42u8; 70000];
        assert!(same_streams(
            &mut Short {
                bytes: &bytes,
                chunk: 3
            },
            &mut Short {
                bytes: &bytes,
                chunk: 109
            },
            bytes.len() as u64
        )
        .unwrap());
        assert!(same_streams(&mut &b"short"[..], &mut &b"short"[..], 6).is_err());
        assert!(same_streams(&mut &b"longer"[..], &mut &b"longer"[..], 4).is_err());
        assert!(!same_streams(&mut &b"abcd"[..], &mut &b"abce"[..], 4).unwrap());
    }
    #[test]
    fn verification_filters_only_known_observational_warning_prefixes() {
        assert!(is_measurement(
            "native cache lease skipped: sharing violation"
        ));
        assert!(is_measurement("native telemetry skipped: access denied"));
        assert!(!is_measurement("native unsupported: unknown initializer"));
        assert!(!is_measurement("native internal: poisoned semantic state"));
        assert!(!is_measurement(
            "native session not saved: inputs changed during compilation"
        ));
    }
}
