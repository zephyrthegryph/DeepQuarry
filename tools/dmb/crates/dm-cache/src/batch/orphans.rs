//! Bounded advisory cleanup. Only v2 names promise a lifetime file lock.
//! Legacy spools, lock files and published segments never authorize deletion.
use fs2::FileExt;
use std::{
    fs::{self, Metadata, OpenOptions},
    io,
    path::Path,
    time::{Duration, Instant},
};

pub(super) struct Bounds {
    pub entries: usize,
    pub reaped: usize,
    pub time: Duration,
}
impl Default for Bounds {
    fn default() -> Self {
        Self {
            entries: 64,
            reaped: 8,
            time: Duration::from_millis(10),
        }
    }
}
#[derive(Default, Debug)]
pub(super) struct Report {
    pub inspected: usize,
    pub reaped: usize,
}
fn name_supported(name: &str) -> bool {
    let Some(body) = name
        .strip_prefix(".batch-v2-")
        .and_then(|s| s.strip_suffix(".tmp"))
    else {
        return false;
    };
    let mut parts = body.split('-');
    let valid = |part: Option<&str>, max: u128| {
        part.is_some_and(|s| {
            !s.is_empty()
                && s.len() <= 39
                && s.bytes().all(|b| b.is_ascii_digit())
                && s.parse::<u128>()
                    .is_ok_and(|n| n <= max && n.to_string() == s)
        })
    };
    valid(parts.next(), u32::MAX as u128)
        && valid(parts.next(), u128::MAX)
        && valid(parts.next(), u64::MAX as u128)
        && parts.next().is_none()
}
fn reparse(metadata: &Metadata) -> bool {
    if metadata.file_type().is_symlink() {
        return true;
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        if metadata.file_attributes() & 0x400 != 0 {
            return true;
        }
    }
    false
}
fn safe_root(root: &Path) -> bool {
    root.is_absolute()
        && root.parent().is_some()
        && root.ancestors().all(|ancestor| {
            fs::symlink_metadata(ancestor).is_ok_and(|m| m.is_dir() && !reparse(&m))
        })
}
pub(super) fn validate_root(root: &Path) -> io::Result<()> {
    let absolute = if root.is_absolute() {
        root.to_path_buf()
    } else {
        std::env::current_dir()?.join(root)
    };
    if safe_root(&absolute) {
        Ok(())
    } else {
        Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "batch spool refuses reparse or invalid cache ancestors",
        ))
    }
}
fn same_leaf(path: &Path, held: &Metadata) -> bool {
    fs::symlink_metadata(path).is_ok_and(|current| {
        if !current.is_file()
            || reparse(&current)
            || current.len() != held.len()
            || current.modified().ok() != held.modified().ok()
        {
            return false;
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            current.dev() == held.dev() && current.ino() == held.ino()
        }
        #[cfg(windows)]
        {
            use std::os::windows::fs::MetadataExt;
            current.creation_time() == held.creation_time()
        }
        #[cfg(not(any(unix, windows)))]
        {
            false
        }
    })
}
pub(super) fn reap(root: &Path, bounds: Bounds) -> io::Result<Report> {
    let started = Instant::now();
    let mut report = Report::default();
    let absolute;
    let root = if root.is_absolute() {
        root
    } else {
        absolute = std::env::current_dir()?.join(root);
        absolute.as_path()
    };
    if !safe_root(root) {
        return Ok(report);
    }
    // No collection/sort/global walk. Large roots may need later passes; the
    // entry/time limits bound attempted work, not filesystem syscall latency.
    for entry in fs::read_dir(root)?.take(bounds.entries) {
        if report.reaped >= bounds.reaped || started.elapsed() >= bounds.time {
            break;
        }
        report.inspected += 1;
        let Ok(entry) = entry else {
            continue;
        };
        let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        if !name_supported(&name) {
            continue;
        }
        let path = entry.path();
        if path.parent() != Some(root) {
            continue;
        }
        let Ok(before) = fs::symlink_metadata(&path) else {
            continue;
        };
        if !before.is_file() || reparse(&before) {
            continue;
        }
        let mut options = OpenOptions::new();
        options.read(true).write(true);
        #[cfg(windows)]
        {
            use std::os::windows::fs::OpenOptionsExt;
            options.custom_flags(0x0020_0000); // FILE_FLAG_OPEN_REPARSE_POINT
        }
        let Ok(file) = options.open(&path) else {
            continue;
        };
        if FileExt::try_lock_exclusive(&file).is_err() {
            continue;
        }
        let Ok(held) = file.metadata() else {
            continue;
        };
        if !same_leaf(&path, &held) || !safe_root(root) {
            continue;
        }
        // A v2 producer never recreates this unique name. Its segment staging
        // file is owned by this same locked spool through the whole finish.
        let staged = path.with_extension("segment.tmp");
        match fs::symlink_metadata(&staged) {
            Ok(m) if m.is_file() && !reparse(&m) => {
                if fs::remove_file(&staged).is_err() {
                    continue;
                }
            }
            Ok(_) => continue,
            Err(e) if e.kind() == io::ErrorKind::NotFound => (),
            Err(_) => continue,
        }
        // Keep the lock held through unlink; releasing it first allows another
        // cleanup attempt to race this one. No PID liveness decision is used.
        if same_leaf(&path, &held) && fs::remove_file(&path).is_ok() {
            report.reaped += 1;
        }
    }
    Ok(report)
}
