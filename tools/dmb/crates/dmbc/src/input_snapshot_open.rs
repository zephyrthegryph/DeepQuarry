//! Open source reads once on Windows; the caller authenticates the live handle.
use std::{fs::File, io, path::Path};

pub(super) fn read_file(path: &Path) -> io::Result<File> {
    // Unix special files may block in open(), so preserve the regular-file
    // precheck there. Windows ordinary files need no separate attributes query:
    // stamp_handle checks the opened object before any bytes are consumed.
    #[cfg(not(windows))]
    {
        if !std::fs::metadata(path)?.is_file() {
            return Err(not_regular());
        }
        File::open(path)
    }
    #[cfg(windows)]
    {
        match File::open(path) {
            Ok(file) => Ok(file),
            Err(open_error) => {
                // File::open rejects directories on Windows. Preserve the old
                // directory/missing/attributes error precedence on this path.
                match std::fs::metadata(path) {
                    Ok(metadata) if !metadata.is_file() => Err(not_regular()),
                    Ok(_) => Err(open_error),
                    Err(metadata_error) => Err(metadata_error),
                }
            }
        }
    }
}

fn not_regular() -> io::Error {
    io::Error::new(io::ErrorKind::NotFound, "candidate is not a regular file")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::input_snapshot::{FileSystemInputs, SnapshotProvider};
    use std::sync::atomic::{AtomicUsize, Ordering};
    static NEXT: AtomicUsize = AtomicUsize::new(0);

    #[test]
    fn handle_read_keeps_regular_directory_and_missing_contracts() {
        let directory = std::env::temp_dir().join(format!(
            "dmbc-read-open-{}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&directory).unwrap();
        let file = directory.join("source.dm");
        std::fs::write(&file, b"/datum/probe\n").unwrap();
        let (stamp, bytes) = FileSystemInputs.read(&file).unwrap();
        assert_eq!(bytes, b"/datum/probe\n");
        assert_eq!(stamp, FileSystemInputs.stamp(&file).unwrap());
        assert_eq!(
            FileSystemInputs.read(&directory).unwrap_err().kind(),
            io::ErrorKind::NotFound
        );
        let missing = directory.join("missing.dm");
        assert_eq!(
            FileSystemInputs.read(&missing).unwrap_err().kind(),
            std::fs::metadata(&missing).unwrap_err().kind()
        );
        std::fs::remove_file(file).unwrap();
        std::fs::remove_dir(directory).unwrap();
    }
}
