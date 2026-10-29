//! Bounded original read, distinct from compiler's unchanged ordinary read API.
use super::*;
pub(super) fn filesystem_bounded_read(path: &Path, limit: usize) -> io::Result<CapturedInputRead> {
    use std::io::Read;
    let mut file = source_open::read_file(path)?;
    let before = stamp_handle(&file)?;
    let size = usize::try_from(before.size)
        .map_err(|_| invalid("policy file size exceeds address space"))?;
    if size > limit {
        return Err(invalid("policy original exceeds remaining capture budget"));
    }
    let mut bytes = Vec::new();
    bytes
        .try_reserve_exact(size)
        .map_err(|_| invalid("policy original allocation refused"))?;
    if bytes.capacity() > limit {
        return Err(invalid("policy original capacity exceeds remaining budget"));
    }
    let mut chunk = [0u8; 16384];
    loop {
        crate::daemon::control::checkpoint()?;
        let n = file.read(&mut chunk)?;
        if n == 0 {
            break;
        }
        if bytes.len().checked_add(n).is_none_or(|next| next > size) {
            return Err(io::Error::new(
                io::ErrorKind::Interrupted,
                "policy original grew beyond observed size",
            ));
        }
        bytes.extend_from_slice(&chunk[..n]);
    }
    if bytes.len() != size
        || stamp_handle(&file)? != before
        || FileSystemInputs.stamp(path)? != before
    {
        return Err(io::Error::new(
            io::ErrorKind::Interrupted,
            "policy original changed during bounded read",
        ));
    }
    Ok(CapturedInputRead::new(before, bytes))
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub(crate) fn read_policy_candidate(
        &self,
        path: &Path,
        limit: usize,
    ) -> io::Result<Option<dm_resources::SharedBytes>> {
        if !path.is_absolute() {
            return Err(invalid("workspace policy paths must be caller absolute"));
        }
        let path = canonical_path(path);
        let parent = path
            .parent()
            .ok_or_else(|| invalid("policy path has no parent"))?;
        self.record_search_folder(parent)?;
        let result = self.provider.read_policy_bounded(&path, limit);
        match result {
            Ok(Some(read)) => {
                let (stamp, bytes, hash) = read.into_parts();
                if stamp.size != bytes.len() as u64 || bytes.capacity() > limit {
                    return Err(invalid("bounded provider exceeded admitted size/capacity"));
                }
                self.snapshot
                    .lock()
                    .map_err(|_| invalid("input mutex poisoned"))?
                    .record_verified_digest(&path, stamp, hash)?;
                Ok(Some(bytes.into()))
            }
            Ok(None) => Err(invalid("provider cannot prove bounded original read")),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                self.snapshot
                    .lock()
                    .map_err(|_| invalid("input mutex poisoned"))?
                    .record_negative(&path)?;
                Ok(None)
            }
            Err(error) => Err(error),
        }
    }
}

#[cfg(test)]
#[path = "input_policy_read_tests.rs"]
mod tests;
