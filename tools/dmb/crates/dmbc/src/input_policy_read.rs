//! Bounded original read, distinct from compiler's unchanged ordinary read API.
use super::*;

pub(crate) enum FixedLibraryBaseline {
    Readable(dm_resources::SharedBytes),
    Missing,
    #[cfg(windows)]
    OpenUnreadable,
}

impl FixedLibraryBaseline {
    pub(crate) fn bytes(&self) -> Option<&dm_resources::SharedBytes> {
        match self {
            Self::Readable(bytes) => Some(bytes),
            Self::Missing => None,
            #[cfg(windows)]
            Self::OpenUnreadable => None,
        }
    }

    pub(crate) fn selects_file_fact(&self) -> bool {
        match self {
            Self::Readable(_) | Self::Missing => true,
            #[cfg(windows)]
            Self::OpenUnreadable => false, // selected by the typed open ledger
        }
    }
}

impl<P: SnapshotProvider> RecordingInputs<P> {
    /// Selected authored Library Sites only. The existing Original opened
    /// reader distinguishes an actual pre-payload OS denial from allocation,
    /// cancellation, post-open I/O and admission errors.
    pub(crate) fn read_fixed_library_baseline(
        &self, root: &Path, path: &Path, limit: usize,
        work: &dyn dm_preprocess::source_arena_credit::SourceArenaWork,
    ) -> io::Result<FixedLibraryBaseline> {
        if !root.is_absolute()
            || path.strip_prefix(root).ok() != Some(Path::new(crate::runner_host::workspace_capture::LIBRARY_SITES_BASELINE))
        {
            return Err(invalid("fixed library baseline path differs from its selected root"));
        }
        self.read_registered_baseline(path, limit, work)
    }

    /// Called only by the fixed or registered baseline issuance paths. The
    /// caller must fund retained bytes and validate membership before reading.
    pub(crate) fn read_registered_baseline(
        &self, path: &Path, limit: usize,
        work: &dyn dm_preprocess::source_arena_credit::SourceArenaWork,
    ) -> io::Result<FixedLibraryBaseline> {
        self.read_registered_baseline_using(path, limit, work, None)
    }

    pub(crate) fn read_registered_baseline_using(
        &self, path: &Path, limit: usize,
        work: &dyn dm_preprocess::source_arena_credit::SourceArenaWork,
        mut fund_payload: Option<&mut dyn FnMut(usize) -> io::Result<()>>,
    ) -> io::Result<FixedLibraryBaseline> {
        use FixedLibraryBaseline as Seen;
        if !path.is_absolute() {
            return Err(invalid("baseline observation requires an absolute path"));
        }
        work.checkpoint()?;
        if fund_payload.is_some() {
            let path = canonical_path(path);
            let parent = path.parent().ok_or_else(|| invalid("fixed baseline parent absent"))?;
            // Joined Derived configuration already observed tools/ci. Do
            // not enter an unbounded new folder-list allocation in this lane.
            let current = self.snapshot.lock().map_err(|_| invalid("input capture mutex poisoned"))?;
            if !current.folders.contains_key(parent) {
                return Err(invalid("variable baseline grant requires its recorded parent listing"));
            }
        }
        #[cfg(not(windows))]
        {
            if let Some(fund_payload) = fund_payload {
                return Ok(match self.read_policy_vec_admitted(path, limit, fund_payload)? {
                    Some(bytes) => Seen::Readable(bytes.into()),
                    None => Seen::Missing,
                });
            }
            // Unix can successfully open a directory and fail its first read.
            // No fixed payload-failure currentness is issued on that host.
            Ok(match self.read_policy_candidate(path, limit)? {
                Some(bytes) => Seen::Readable(bytes),
                None => Seen::Missing,
            })
        }
        #[cfg(windows)]
        {
            let path = canonical_path(path);
            self.record_search_folder(path.parent().ok_or_else(|| invalid("fixed baseline parent absent"))?)?;
            let opened = std::cell::Cell::new(false);
            let admitted = std::cell::Cell::new(None);
            let first = std::cell::RefCell::new(None);
            let result = self.provider.read_original_open_admitted(
                &path, limit, work,
                &mut || {
                    if opened.replace(true) {
                        let error = invalid("provider repeated the fixed baseline open");
                        if first.borrow().is_none() { *first.borrow_mut() = Some(error); }
                        return Err(io::ErrorKind::Other.into());
                    }
                    Ok(dm_preprocess::OriginalRawOpenDecision::Read)
                },
                &mut |size| {
                    let status = if !opened.get() || admitted.get().is_some() || size > limit {
                        Err(invalid("provider requested invalid fixed baseline payload admission"))
                    } else {
                        admitted.set(Some(size));
                        work.checkpoint().and_then(|()| match fund_payload.as_mut() {
                            Some(fund) => fund(size),
                            None => Ok(()),
                        })
                    };
                    match status {
                        Ok(()) => Ok(()),
                        Err(error) => {
                            if first.borrow().is_none() { *first.borrow_mut() = Some(error); }
                            Err(io::ErrorKind::Other.into())
                        }
                    }
                },
            );
            if let Some(actual) = first.into_inner() { return Err(actual); }
            match result? {
                OriginalOpenedRead::Read(read) if opened.get() && admitted.get().is_some() => {
                    let bytes = self.record_policy_read_result(&path, admitted.get().unwrap(), Ok(Some(read)))?
                        .ok_or_else(|| invalid("actual readable fixed baseline was not recorded"))?;
                    Ok(Seen::Readable(bytes.into()))
                }
                OriginalOpenedRead::SourceOpenFailed(error) if !opened.get() => {
                    if error.kind() == io::ErrorKind::NotFound && matches!(error.raw_os_error(), Some(2 | 3)) {
                        self.record_policy_read_result(&path, limit, Err(error))?;
                        return Ok(Seen::Missing);
                    }
                    // Windows File::open also issues ACCESS_DENIED on a
                    // directory. Keep the exact code, not synthetic absence.
                    if !matches!(error.raw_os_error(), Some(5 | 32 | 33)) { return Err(error); }
                    let before = self.snapshot.lock().map_err(|_| invalid("input capture mutex poisoned"))?
                        .opened_reads.clone();
                    let prepaid = work.reserve(before.probe_pregrant(&path)?)?;
                    let status = OriginalReadOpenStatus::capture_using(&error, work)?;
                    let next = before.recorded_using(&path, status, prepaid, work)?;
                    let mut snapshot = self.snapshot.lock().map_err(|_| invalid("input capture mutex poisoned"))?;
                    if !snapshot.opened_reads.same_owner(&before) {
                        return Err(io::Error::new(io::ErrorKind::Interrupted, "fixed baseline open capture changed before commit"));
                    }
                    snapshot.opened_reads = next;
                    Ok(Seen::OpenUnreadable)
                }
                _ => Err(invalid("provider did not issue the fixed baseline's exact open/read result")),
            }
        }
    }
}
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
enum OptionalKernelProduct{Read(CapturedInputRead),Readable,NoText(OptionalReadStatus)}
/// Keep the existing regular-file topology refusal before opening arbitrary
/// special inputs. Environmental lookup failure still asks the actual legacy
/// OS open for its real NoText cause; unrelated operational IO is preserved.
fn optional_file(path:&Path)->io::Result<Result<std::fs::File,OptionalReadStatus>>{
 match std::fs::metadata(path){Ok(metadata)if !metadata.is_file()&&!metadata.is_dir()=>return Err(invalid("optional special input has no finite regular-file grant")),Ok(_)=>{},Err(error)if original_source_open_failure(&error)=>{},Err(actual)=>return Err(actual)}
 match std::fs::File::open(path){Ok(file)=>Ok(Ok(file)),Err(error)=>Ok(Err(OptionalReadStatus::os_failure(OptionalReadPhase::Open,error)?))}
}
fn read_opened_handle_admitted(file:std::fs::File,path:&Path,limit:usize,before_allocate:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<CapturedInputRead>{match read_opened_handle_mode(file,path,limit,before_allocate,false,true)?{OptionalKernelProduct::Read(actual)=>Ok(actual),_=>Err(invalid("required policy reader returned optional product"))}}
/// ONLY actual OS open/read errors become NoText. Every funding, allocation,
/// deadline, cancellation, stamp and stability error keeps its real Err path.
pub(super) fn filesystem_optional_read_admitted(path:&Path,limit:usize,fund:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<OptionalInputRead>{
 crate::daemon::control::checkpoint()?;let file=match optional_file(path)?{Ok(file)=>file,Err(actual)=>return Ok(OptionalInputRead::NoText(actual))};
 match read_opened_handle_mode(file,path,limit,fund,true,true)?{OptionalKernelProduct::Read(actual)=>Ok(OptionalInputRead::Read(actual)),OptionalKernelProduct::NoText(actual)=>Ok(OptionalInputRead::NoText(actual)),OptionalKernelProduct::Readable=>Err(invalid("optional payload reader omitted its actual bytes"))}
}
pub(super) fn filesystem_optional_probe(path:&Path)->io::Result<OptionalReadStatus>{
 crate::daemon::control::checkpoint()?;let file=match optional_file(path)?{Ok(file)=>file,Err(actual)=>return Ok(actual)};
 match read_opened_handle_mode(file,path,dq_analyze::captured_raw_policy::MAX_FIXTURE_FILE_BYTES,&mut |_|Err(invalid("optional probe must not allocate payload")),true,false)?{OptionalKernelProduct::Readable=>Ok(OptionalReadStatus::Readable),OptionalKernelProduct::NoText(actual)=>Ok(actual),OptionalKernelProduct::Read(_)=>Err(invalid("optional probe retained unexpected payload"))}
}
fn read_opened_handle_mode(mut file:std::fs::File,path:&Path,limit:usize,before_allocate:&mut dyn FnMut(usize)->io::Result<()>,optional:bool,keep:bool)->io::Result<OptionalKernelProduct>{
    use std::io::Read;
    // Unix permits opening a directory, then issues its actual read errno.
    // Observe that errno rather than fabricating source absence from stamp's
    // non-regular-file refusal. Other successful special readers stay closed.
    if optional && file.metadata()?.is_dir(){let mut byte=[0u8;1];loop{match file.read(&mut byte){Err(error)if error.kind()==io::ErrorKind::Interrupted=>{crate::daemon::control::checkpoint()?;continue},Err(error)=>return Ok(OptionalKernelProduct::NoText(OptionalReadStatus::os_failure(OptionalReadPhase::Read,error)?)),Ok(_)=>return Err(invalid("optional non-regular readable input has no finite captured file grant"))}}}
    let before = stamp_handle(&file)?;
    let size = usize::try_from(before.size)
        .map_err(|_| invalid("policy file size exceeds address space"))?;
    if size > limit {
        return Err(invalid(&format!("policy original exceeds remaining capture budget: {} (size={size}, limit={limit})",path.display())));
    }
    if keep{before_allocate(size)?;}
    // Allocate the exact admitted layout; try_reserve_exact permits a larger
    // reported capacity, which would allocate bytes the callback never funded.
    let mut bytes = if !keep||size == 0 { Vec::new() } else {
        let layout = std::alloc::Layout::array::<u8>(size)
            .map_err(|_| invalid("policy original allocation refused"))?;
        let pointer = std::ptr::NonNull::new(unsafe { std::alloc::alloc(layout) })
            .ok_or_else(|| invalid("policy original allocation refused"))?;
        // SAFETY: global allocator, exact u8 layout/capacity, no initialized
        // elements. Vec owns and frees it; extend below never exceeds size.
        unsafe { Vec::from_raw_parts(pointer.as_ptr(), 0, size) }
    };
    let mut count=0usize;
    let mut chunk = [0u8; 16384];
    loop {
        crate::daemon::control::checkpoint()?;
        let n=match file.read(&mut chunk){Ok(n)=>n,Err(error)if optional&&error.kind()==io::ErrorKind::Interrupted=>continue,Err(error)if optional=>return Ok(OptionalKernelProduct::NoText(OptionalReadStatus::os_failure(OptionalReadPhase::Read,error)?)),Err(error)=>return Err(error)};
        if n == 0 {
            break;
        }
        if count.checked_add(n).is_none_or(|next| next > size) {
            return Err(io::Error::new(
                io::ErrorKind::Interrupted,
                "policy original grew beyond observed size",
            ));
        }
        count+=n;if keep{bytes.extend_from_slice(&chunk[..n]);}
    }
    if count != size
        || stamp_handle(&file)? != before
        || FileSystemInputs.stamp(path)? != before
    {
        return Err(io::Error::new(
            io::ErrorKind::Interrupted,
            "policy original changed during bounded read",
        ));
    }
    Ok(if keep{OptionalKernelProduct::Read(CapturedInputRead::new(before,bytes))}else{OptionalKernelProduct::Readable})
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
        self.read_policy_payload_admitted(&path, limit, before_allocate)
    }
    /// Sibling input producers with a captured exact typed parent listing
    /// can use the same payload kernel without acquiring a second listing.
    pub(super) fn read_policy_payload_admitted(&self, path: &Path, limit: usize, before_allocate: &mut dyn FnMut(usize) -> io::Result<()>) -> io::Result<Option<Vec<u8>>> {
        self.read_policy_payload_mode(path, limit, before_allocate, false)
    }

    /// A preflight reread may use the recorded ordinary parent and file
    /// metadata already paid by this recorder. The actual provider read and
    /// digest validation still run. This entry point cannot create new rows.
    pub(super) fn reread_policy_payload_admitted(&self, path: &Path, limit: usize, before_allocate: &mut dyn FnMut(usize) -> io::Result<()>) -> io::Result<Option<Vec<u8>>> {
        self.read_policy_payload_mode(path, limit, before_allocate, true)
    }

    fn read_policy_payload_mode(&self, path: &Path, limit: usize, before_allocate: &mut dyn FnMut(usize) -> io::Result<()>, known: bool) -> io::Result<Option<Vec<u8>>> {
        let mut admission_error = None;
        let result = self.provider.read_policy_bounded_admitted(path, limit, &mut |size| {
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
        if known {
            let check = |stamp: Option<(&Stamp,u128)>| -> io::Result<()> {
                let current=self.snapshot.lock().map_err(|_|invalid("input mutex poisoned"))?;
                let parent=path.parent().ok_or_else(||invalid("policy path has no parent"))?;
                let fact=current.files.get(path).filter(|_|current.folders.contains_key(parent))
                    .ok_or_else(||invalid("previously recorded policy file or folder disappeared"))?;
                let Some((stamp,hash))=stamp else{return Err(invalid("present input became negative during capture"))};
                if current.path_presence.get(path)==Some(false){return Err(invalid("missing metadata path became a captured file"))}
                if current.negative_files.contains(path){return Err(invalid("negative input became present during capture"))}
                if &fact.stamp!=stamp||fact.content!=hash{return Err(invalid("input changed during repeated capture"))}
                Ok(())
            };
            return match result {
                Ok(Some(read))=>{
                    let(stamp,bytes,hash)=read.into_parts();
                    if stamp.size!=bytes.len() as u64||bytes.capacity()>limit{return Err(invalid("bounded provider exceeded admitted size/capacity"))}
                    check(Some((&stamp,hash)))?;Ok(Some(bytes))
                }
                Ok(None)=>Err(invalid("provider cannot prove bounded original read")),
                Err(error) if error.kind()==io::ErrorKind::NotFound=>{check(None)?;Ok(None)}
                Err(actual)=>Err(actual),
            }
        }
        self.record_policy_read_result(path, limit, result)
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

impl<P:SnapshotProvider> RecordingInputs<P>{
 pub(super) fn read_optional_callback_payload(&self,path:&Path,limit:usize,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,fund:&mut dyn FnMut(usize)->io::Result<()>)->io::Result<Option<Vec<u8>>>{
  let before=self.snapshot.lock().map_err(|_|invalid("callback recorder poisoned"))?.optional_reads.clone();let prepaid=work.reserve(before.probe_pregrant(path)?)?;
  let first=std::cell::RefCell::new(None);let admitted=std::cell::Cell::new(None);
  let read=self.provider.read_optional_admitted(path,limit,work,&mut|size|{let next=(||{if admitted.replace(Some(size)).is_some()||size>limit{return Err(invalid("optional provider repeated or exceeded payload admission"))}work.checkpoint()?;fund(size)})();match next{Ok(())=>Ok(()),Err(error)=>{if first.borrow().is_none(){*first.borrow_mut()=Some(error)}Err(io::ErrorKind::Other.into())}}});
  if let Some(actual)=first.into_inner(){return Err(actual)}
  let(status,bytes)=match read?{
   OptionalInputRead::Read(actual)=>{let size=admitted.get().ok_or_else(||invalid("optional payload omitted actual admission"))?;(OptionalReadStatus::Readable,self.record_policy_read_result(path,size,Ok(Some(actual)))?)},
   OptionalInputRead::NoText(actual@OptionalReadStatus::NoText{phase, ..})=>{if phase==OptionalReadPhase::Open&&admitted.get().is_some(){return Err(invalid("optional open failure followed an impossible payload admission"))}(actual,None)},
   OptionalInputRead::NoText(OptionalReadStatus::Readable)=>return Err(invalid("optional NoText cannot claim readable payload")),
  };
  let next=before.recorded_using(path,status,prepaid,work)?;
  let mut snapshot=self.snapshot.lock().map_err(|_|invalid("callback recorder poisoned"))?;if !snapshot.optional_reads.same_owner(&before){return Err(io::Error::new(io::ErrorKind::Interrupted,"optional callback observations changed before commit"))}snapshot.optional_reads=next;Ok(bytes)
 }
}
