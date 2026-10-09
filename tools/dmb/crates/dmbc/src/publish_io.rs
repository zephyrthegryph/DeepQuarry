//! Owned staging and authenticated streaming copies. No staged output reread.
use super::*;
use std::io::Write;

/// Removes only the exact staged entry and fixed children this operation owns.
/// Immutable links are unlinked without changing their shared file attributes.
pub(super) struct StagedPath {
    path: PathBuf,
    cleanup: bool,
}
impl StagedPath {
    pub(super) fn new(path: PathBuf) -> Self {
        Self {
            path,
            cleanup: true,
        }
    }
    pub(super) fn path(&self) -> &Path {
        &self.path
    }
    pub(super) fn preserve(mut self) {
        self.cleanup = false;
    }
}
impl Drop for StagedPath {
    fn drop(&mut self) {
        if !self.cleanup {
            return;
        }
        if fs::symlink_metadata(&self.path).is_ok_and(|metadata| metadata.file_type().is_dir()) {
            for name in [
                "deepquarry.dmb",
                "deepquarry.rsc",
                "pair.json",
                "archive.rsc",
                "record.json",
                "receipt.json",
                "slot-complete",
            ] {
                let _ = eviction::unlink_immutable(&self.path.join(name));
            }
            let _ = fs::remove_dir(&self.path);
        } else {
            let _ = eviction::unlink_immutable(&self.path);
        }
    }
}

/// `bytes` is the immutable buffer whose memory hash supplied the pair identity.
/// A successful write and flush establish the owned file without a disk reread.
pub(super) fn write_owned(path: &Path, bytes: &[u8]) -> io::Result<crate::input_snapshot::Stamp> {
    let mut file = OpenOptions::new().write(true).create_new(true).open(path)?;
    dm_profile::io_call(|| file.write_all(bytes), |_| (0, bytes.len() as u64))?;
    file.flush()?;
    if file.metadata()?.len() != bytes.len() as u64 {
        return Err(invalid("owned output write has unexpected length"));
    }
    finish_owned(file, path)
}

/// Hash only bytes accepted by the output writer. A short write is retried;
/// failure never exposes a partial output or authorizes its inode.
pub(super) fn copy_hashed(
    source: &Path,
    destination: &Path,
    expected: (u64, u128),
) -> io::Result<crate::input_snapshot::Stamp> {
    use crate::input_snapshot::SnapshotProvider;
    let before = crate::input_snapshot::FileSystemInputs.stamp(source)?;
    let mut input = File::open(source)?;
    if crate::input_snapshot::stamp_handle(&input)? != before {
        return Err(invalid("copy source inode changed before open"));
    }
    let mut output = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(destination)?;
    let actual = copy_stream(&mut input, &mut output)?;
    output.flush()?;
    if actual != expected || output.metadata()?.len() != expected.0 {
        return Err(invalid("output copy failed authentication"));
    }
    if crate::input_snapshot::stamp_handle(&input)? != before
        || crate::input_snapshot::FileSystemInputs.stamp(source)? != before
    {
        return Err(invalid("immutable copy source changed during read"));
    }
    finish_owned(output, destination)
}

/// Windows may finalize last-write time when the last writer handle closes.
/// Compare the actual writer inode and length before accepting that final stamp.
pub(super) fn finish_owned(
    mut file: File,
    path: &Path,
) -> io::Result<crate::input_snapshot::Stamp> {
    use crate::input_snapshot::SnapshotProvider;
    file.flush()?;
    let handle = crate::input_snapshot::stamp_handle(&file)?;
    drop(file);
    let closed = crate::input_snapshot::FileSystemInputs.stamp(path)?;
    let same_inode = match (handle.file_id, closed.file_id) {
        (Some(before), Some(after)) => before == after && handle.size == closed.size,
        _ => handle == closed,
    };
    if !same_inode {
        return Err(invalid("owned writer inode replaced before admission"));
    }
    Ok(closed)
}

fn copy_stream(input: &mut impl Read, output: &mut impl Write) -> io::Result<(u64, u128)> {
    let mut hash = Xxh3::new();
    let mut bytes = 0u64;
    let mut buffer = [0u8; 65536];
    loop {
        let count = dm_profile::io_call(|| input.read(&mut buffer), |count| (*count as u64, 0))?;
        if count == 0 {
            break;
        }
        let mut accepted = 0;
        while accepted < count {
            let written = match dm_profile::io_call(
                || output.write(&buffer[accepted..count]),
                |count| (0, *count as u64),
            ) {
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                result => result?,
            };
            if written == 0 {
                return Err(io::ErrorKind::WriteZero.into());
            }
            hash.update(&buffer[accepted..accepted + written]);
            bytes = bytes
                .checked_add(written as u64)
                .ok_or_else(|| invalid("output byte count overflow"))?;
            accepted += written;
        }
    }
    Ok((bytes, hash.digest128()))
}

#[cfg(test)]
mod tests {
    use super::*;
    struct ShortWriter {
        bytes: Vec<u8>,
        fail_after: Option<usize>,
    }
    impl Write for ShortWriter {
        fn write(&mut self, input: &[u8]) -> io::Result<usize> {
            if self
                .fail_after
                .is_some_and(|limit| self.bytes.len() >= limit)
            {
                return Err(io::ErrorKind::Other.into());
            }
            let count = input.len().min(3);
            self.bytes.extend_from_slice(&input[..count]);
            Ok(count)
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }
    #[test]
    fn short_writes_hash_only_accepted_bytes_and_failures_do_not_admit() {
        let bytes = b"a deliberately longer payload";
        let mut writer = ShortWriter {
            bytes: Vec::new(),
            fail_after: None,
        };
        assert_eq!(
            copy_stream(&mut bytes.as_slice(), &mut writer).unwrap(),
            (bytes.len() as u64, xxh3_128(bytes))
        );
        assert_eq!(writer.bytes, bytes);
        let mut writer = ShortWriter {
            bytes: Vec::new(),
            fail_after: Some(6),
        };
        assert!(copy_stream(&mut bytes.as_slice(), &mut writer).is_err());
        assert_eq!(writer.bytes.len(), 6);
    }
}

#[cfg(all(test, windows))]
mod windows_tests {
    use super::*;
    use crate::input_snapshot::SnapshotProvider;
    #[test]
    fn owned_writer_admits_final_closed_inode_stamp() {
        let store = super::super::tests::store();
        let path = store.root.join("writer.dmb");
        let stamp = write_owned(&path, b"owned write with close-time metadata").unwrap();
        assert!(stamp.file_id.is_some());
        assert_eq!(
            stamp,
            crate::input_snapshot::FileSystemInputs
                .stamp(&path)
                .unwrap()
        );
        assert_eq!(stamp.size, 36);
    }
}
