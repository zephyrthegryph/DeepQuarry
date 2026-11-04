//! Bounded original read, distinct from compiler's unchanged ordinary read API.
use super::*;
pub(super) fn filesystem_bounded_read(path: &Path, limit: usize) -> io::Result<CapturedInputRead> {
    filesystem_bounded_read_admitted(path, limit, &mut |_| Ok(()))
}
/// The same single-handle read, with resource admission BEFORE the payload
/// allocation. The callback lends resources only, never input/source authority.
pub(super) fn filesystem_bounded_read_admitted(path: &Path, limit: usize, before_allocate: &mut dyn FnMut(usize) -> io::Result<()>) -> io::Result<CapturedInputRead> {
    let file = source_open::read_policy_file(path)?;
    read_opened_handle_admitted(file,path,limit,before_allocate)
}
/// Original's real OS open is before duplicate suppression. This exact opened
/// handle then moves into the EXISTING bounded payload kernel, never reopens.
pub(super) fn filesystem_original_open_read_admitted(path:&Path,limit:usize,after_open:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before_allocate:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<OriginalOpenedRead>{
    crate::daemon::control::checkpoint()?;
    let file=match std::fs::File::open(path){Ok(file)=>file,Err(actual)if original_source_open_failure(&actual)=>return Ok(OriginalOpenedRead::SourceOpenFailed(actual)),Err(actual)=>return Err(actual)};
    if after_open()?==dm_preprocess::OriginalRawOpenDecision::Suppress{return Ok(OriginalOpenedRead::Suppressed)}
    read_opened_handle_admitted(file,path,limit,before_allocate).map(OriginalOpenedRead::Read)
}
fn read_opened_handle_admitted(mut file:std::fs::File,path:&Path,limit:usize,before_allocate:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<CapturedInputRead>{
    use std::io::Read;
    let before = stamp_handle(&file)?;
    let size = usize::try_from(before.size)
        .map_err(|_| invalid("policy file size exceeds address space"))?;
    if size > limit {
        return Err(invalid("policy original exceeds remaining capture budget"));
    }
    before_allocate(size)?;
    // Allocate the exact admitted layout; try_reserve_exact permits a larger
    // reported capacity, which would allocate bytes the callback never funded.
    let mut bytes = if size == 0 { Vec::new() } else {
        let layout = std::alloc::Layout::array::<u8>(size)
            .map_err(|_| invalid("policy original allocation refused"))?;
        let pointer = std::ptr::NonNull::new(unsafe { std::alloc::alloc(layout) })
            .ok_or_else(|| invalid("policy original allocation refused"))?;
        // SAFETY: global allocator, exact u8 layout/capacity, no initialized
        // elements. Vec owns and frees it; extend below never exceeds size.
        unsafe { Vec::from_raw_parts(pointer.as_ptr(), 0, size) }
    };
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
    pub(crate) fn read_policy_candidate(&self,path:&Path,limit:usize)->io::Result<Option<dm_resources::SharedBytes>>{self.read_policy_vec(path,limit).map(|bytes|bytes.map(Into::into))}
    pub(super) fn read_policy_vec(&self,path:&Path,limit:usize)->io::Result<Option<Vec<u8>>>{
        if !path.is_absolute() {
            return Err(invalid("workspace policy paths must be caller absolute"));
        }
        let path = canonical_path(path);
        let parent = path
            .parent()
            .ok_or_else(|| invalid("policy path has no parent"))?;
        self.record_search_folder(parent)?;
        let result = self.provider.read_policy_bounded(&path, limit);
        self.record_policy_read_result(&path, limit, result)
    }
    pub(super) fn read_policy_vec_admitted(&self, path: &Path, limit: usize, before_allocate: &mut dyn FnMut(usize) -> io::Result<()>) -> io::Result<Option<Vec<u8>>> {
        if !path.is_absolute() { return Err(invalid("workspace policy paths must be caller absolute")); }
        let path = canonical_path(path);
        let parent = path.parent().ok_or_else(|| invalid("policy path has no parent"))?;
        self.record_search_folder(parent)?;
        let mut admission_error = None;
        let result = self.provider.read_policy_bounded_admitted(&path, limit, &mut |size| {
            if admission_error.is_some() { return Err(io::ErrorKind::Other.into()); }
            match before_allocate(size) {
                Ok(()) => Ok(()),
                Err(error) => {
                    admission_error = Some(error);
                    // Keep the actual error here: a provider cannot replace it,
                    // swallow it, or turn resource NotFound into source absence.
                    Err(io::ErrorKind::Other.into())
                }
            }
        });
        if let Some(error) = admission_error { return Err(error); }
        self.record_policy_read_result(&path, limit, result)
    }
    fn record_policy_read_result(&self, path: &Path, limit: usize, result: io::Result<Option<CapturedInputRead>>) -> io::Result<Option<Vec<u8>>> {
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
                Ok(Some(bytes))
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
