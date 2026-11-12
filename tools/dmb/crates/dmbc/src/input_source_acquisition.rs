//! Primary-read acquisition leases, separately owned from interned lexical text.
use super::*;
use dm_preprocess::{AcquiredSource, SourcePreparationDemand, SourceText};
use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
struct RecordedSourceReceipt {
    exact_open:bool,
    // Only this private exact-open receipt can remember successful validation.
    // This is never serialized or transferred to a reissued receipt.
    checked_epoch:AtomicUsize,
    original_bytes: Option<dm_resources::SharedBytes>,
    issuer: Arc<()>,
    legacy_path: Option<PathBuf>,
    fact: FileInput,
}
impl RecordedSourceReceipt {
    // Exact-open facts already own the canonical spelling. Ordinary receipts
    // preserve the separate path they received from their legacy route.
    fn path(&self) -> &PathBuf {
        self.legacy_path.as_ref().unwrap_or(&self.fact.path)
    }
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub(super) fn acquire_recorded_source(
        &self,
        path: &Path,
        bytes: Vec<u8>,
    ) -> io::Result<AcquiredSource> {
        self.acquire_recorded_source_with_demand(path, bytes, SourcePreparationDemand::Lexical)
    }

    pub(super) fn acquire_recorded_source_with_demand(
        &self,
        path: &Path,
        bytes: Vec<u8>,
        demand: SourcePreparationDemand,
    ) -> io::Result<AcquiredSource> {
        let path = canonical_path(path);
        // This private entrypoint is called only by the SAME read_recorded
        // transaction/primary prepared read, never supplied external text.
        let fact = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?
            .files
            .get(&path)
            .cloned()
            .ok_or_else(|| invalid("source acquisition lacks recorded read"))?;
        if fact.content != xxhash_rust::xxh3::xxh3_128(&bytes) {
            return Err(invalid("source acquisition contradicts actual read"));
        }
        let mut receipt = RecordedSourceReceipt {
            exact_open:false,
            checked_epoch:AtomicUsize::new(0),
            original_bytes: None,
            issuer: Arc::clone(&self.source_issuer),
            legacy_path: Some(path.clone()),
            fact,
        };
        let acquired = if bytes.starts_with(b"\xef\xbb\xbf") || std::str::from_utf8(&bytes).is_err()
        {
            let bytes = dm_resources::SharedBytes::from(bytes);
            self.remember_exceptional_source(&path, bytes.clone())?;
            receipt.original_bytes = Some(bytes.clone());
            AcquiredSource::from_original_slice_using(bytes.as_slice(), receipt, demand)
        } else {
            let candidate = self.prior_original_text.get().and_then(|index| index.get(&path));
            let acquired = AcquiredSource::from_original_bytes_with_candidate_using(bytes, candidate, receipt, demand);
            if candidate.is_some_and(|text| text.same_view(acquired.lease().source_text()))
                && std::env::var_os("DMB_UNIFIED_TEST_OWNER_TRACE").as_deref() == Some(std::ffi::OsStr::new("1"))
            {
                crate::daemon_eprintln!("native source backing observation: {}", serde_json::json!({
                    "path": &path, "edge": "original_decoded_text_to_native",
                }));
            }
            acquired
        };
        self.source_acquisitions
            .lock()
            .map_err(|_| invalid("source acquisition mutex poisoned"))?
            .insert(path, acquired.clone());
        Ok(acquired)
    }
    pub(super) fn acquire_raw_recorded_source(
        &self,
        path: &Path,
        bytes: Vec<u8>,
    ) -> io::Result<dm_preprocess::SourceAcquisitionLease> {
        let path = canonical_path(path);
        // This private entrypoint is called only by the SAME read_recorded
        // transaction/primary prepared read, never supplied external text.
        let fact = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?
            .files
            .get(&path)
            .cloned()
            .ok_or_else(|| invalid("source acquisition lacks recorded read"))?;
        if fact.content != xxhash_rust::xxh3::xxh3_128(&bytes) {
            return Err(invalid("source acquisition contradicts actual read"));
        }
        let mut receipt = RecordedSourceReceipt {
            exact_open:false,
            checked_epoch:AtomicUsize::new(0),
            original_bytes: None,
            issuer: Arc::clone(&self.source_issuer),
            legacy_path: Some(path.clone()),
            fact,
        };
        let acquired = if bytes.starts_with(b"\xef\xbb\xbf") || std::str::from_utf8(&bytes).is_err()
        {
            let bytes = dm_resources::SharedBytes::from(bytes);
            self.remember_exceptional_source(&path, bytes.clone())?;
            receipt.original_bytes = Some(bytes.clone());
            dm_preprocess::SourceAcquisitionLease::from_raw_original_bytes(bytes.as_slice().to_vec(), receipt)
        } else {
            dm_preprocess::SourceAcquisitionLease::from_raw_original_bytes(bytes, receipt)
        };
        Ok(acquired)
    }
    pub(crate) fn read_raw_source(&self,path:&Path,limit:usize,prior:Option<&dm_preprocess::SourceAcquisitionLease>,before_decode:impl FnOnce(usize,bool,bool)->io::Result<()>)->io::Result<Option<dm_preprocess::SourceAcquisitionLease>>{
        let Some(bytes)=self.read_policy_vec(path,limit)?else{return Ok(None)};
        self.finish_raw_source_read(path,bytes,prior,before_decode).map(Some)
    }
    pub(super) fn finish_raw_source_read(&self,path:&Path,bytes:Vec<u8>,prior:Option<&dm_preprocess::SourceAcquisitionLease>,before_decode:impl FnOnce(usize,bool,bool)->io::Result<()>)->io::Result<dm_preprocess::SourceAcquisitionLease>{
        let old=if let Some(prior)=prior{let receipt=prior.receipt::<RecordedSourceReceipt>().ok_or_else(||invalid("raw prior has no genuine recorded acquisition"))?;if receipt.path()!=&canonical_path(path){return Err(invalid("raw prior belongs to a different actual path"))}let raw=recorded_source_original(prior)?;let same=match raw{RecordedSourceOriginal::Utf8(text)=>text.as_bytes()==bytes.as_slice(),RecordedSourceOriginal::Bytes(raw)=>raw.as_slice()==bytes.as_slice()};same.then_some((prior,receipt))}else{None};
        before_decode(bytes.capacity(),bytes.starts_with(b"\xef\xbb\xbf")||std::str::from_utf8(&bytes).is_err(),old.is_none())?;
        let acquired=if let Some((prior,receipt))=old{let path=canonical_path(path);let fact=self.snapshot.lock().map_err(|_|invalid("input mutex poisoned"))?.files.get(&path).cloned().ok_or_else(||invalid("raw reissue lacks actual bounded read"))?;prior.reissued(RecordedSourceReceipt{exact_open:false,checked_epoch:AtomicUsize::new(0),original_bytes:receipt.original_bytes.clone(),issuer:Arc::clone(&self.source_issuer),legacy_path:Some(path),fact})}else{self.acquire_raw_recorded_source(path,bytes)?};
        if !self.validate_recorded_source_lease(path,&acquired){return Err(invalid("actual raw read acquisition issuer/path/facts differ"))}Ok(acquired)}
    /// Admitted physical raw route only. The old checked/capture path above
    /// stays unchanged. No prepared source/parser/model is manufactured here.
    pub(super) fn finish_raw_source_read_admitted(&self,path:&Path,bytes:Vec<u8>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<dm_preprocess::SourceAcquisitionLease>{
        let path=canonical_path(path);
        let fact=self.snapshot.lock().map_err(|_|invalid("input mutex poisoned"))?.files.get(&path).cloned().ok_or_else(||invalid("source acquisition lacks recorded read"))?;
        if fact.content!=xxhash_rust::xxh3::xxh3_128(&bytes){return Err(invalid("source acquisition contradicts actual read"))}
        let encoding=if std::str::from_utf8(&bytes).is_err(){dm_preprocess::SourceEncoding::IncompatibleOriginal}else if bytes.starts_with(b"\xef\xbb\xbf"){dm_preprocess::SourceEncoding::Utf8Bom}else{dm_preprocess::SourceEncoding::Utf8};
        let exceptional=encoding!=dm_preprocess::SourceEncoding::Utf8;
        // These path/fact copies belong to the existing input-operation metadata
        // admission BEFORE beforeRead. Their actual capacities become part of
        // the immutable receipt, explicitly paid again before escaping it.
        let constructor=dm_preprocess::SourceAcquisitionLease::raw_constructor_storage_bytes::<RecordedSourceReceipt>()?.checked_add(path.capacity()).and_then(|n|n.checked_add(fact.path.capacity())).and_then(|n|if exceptional{n.checked_add(std::mem::size_of::<dm_resources::SharedBytesOwner>()+2*std::mem::size_of::<usize>())}else{Some(n)}).ok_or(io::ErrorKind::OutOfMemory)?;
        let capacity=bytes.capacity();
        let mut bytes=Some(bytes);
        let decoded=if exceptional{
            // Eliminate SharedBytes->to_vec. SAME decoder pays/allocates exact
            // decoded String while the one original raw allocation remains.
            dm_preprocess::decode_source_bytes_admitted(bytes.as_ref().unwrap(),&mut |decoded_bytes|before_decode(dm_preprocess::OriginalRawAllocationPlan::new(bytes.as_ref().unwrap(),capacity,constructor,decoded_bytes,exceptional,true)),&mut ||crate::daemon::control::checkpoint())?
        }else{
            before_decode(dm_preprocess::OriginalRawAllocationPlan::new(bytes.as_ref().unwrap(),capacity,constructor,0,exceptional,true))?;
            // Genuine UTF8 classification above; consuming Vec does not allocate.
            String::from_utf8(bytes.take().unwrap()).map_err(|_|invalid("validated UTF8 changed"))?
        };
        let mut receipt=RecordedSourceReceipt{exact_open:false,checked_epoch:AtomicUsize::new(0),original_bytes:None,issuer:Arc::clone(&self.source_issuer),legacy_path:Some(path),fact};
        let source=if exceptional{
            let original=dm_resources::SharedBytes::from(bytes.take().unwrap());receipt.original_bytes=Some(original.clone());
            let source=dm_preprocess::SourceAcquisitionLease::from_raw_original_decoded(decoded,encoding,receipt);
            let actual_path=source.receipt::<RecordedSourceReceipt>().expect("same private receipt").path();
            // All fallible decoding happened BEFORE publishing exceptional bytes.
            // After successful publication acquired() is the first fallible step.
            self.remember_exceptional_source(actual_path,original)?;
            source
        }else{
            // The ordinary path must move its raw allocation (see wrapper below).
            dm_preprocess::SourceAcquisitionLease::from_raw_original_decoded(decoded,encoding,receipt)
        };
        acquired(&source)?;
        let actual_path=source.receipt::<RecordedSourceReceipt>().expect("same private receipt").path();
        if !self.validate_recorded_source_lease(actual_path,&source){return Err(invalid("actual raw read acquisition issuer/path/facts differ"))}
        Ok(source)
    }
    /// Borrow the actual recorded original, never a decoded-text reencoding.
    /// This authenticates current byte input only, not logical/token EOF.
    pub(super) fn finish_exact_original_read_admitted(&self,path:&Path,bytes:Vec<u8>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,fund_text:Option<&dm_preprocess::source_arena_credit::OriginalReadTextFunding<'_>>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->io::Result<()>)->io::Result<dm_preprocess::SourceAcquisitionLease>{
        let actual_path=path;
        let digest=self.snapshot.lock().map_err(|_|invalid("input mutex poisoned"))?
            .original_payloads.get(actual_path).ok_or_else(||invalid("source acquisition lacks exact actual Original payload"))?;
        if digest.content!=xxhash_rust::xxh3::xxh3_128(&bytes){return Err(invalid("source acquisition contradicts actual read"))}
        let encoding=if std::str::from_utf8(&bytes).is_err(){dm_preprocess::SourceEncoding::IncompatibleOriginal}else if bytes.starts_with(b"\xef\xbb\xbf"){dm_preprocess::SourceEncoding::Utf8Bom}else{dm_preprocess::SourceEncoding::Utf8};
        let exceptional=encoding!=dm_preprocess::SourceEncoding::Utf8;
        // The single exact path copy belongs to the existing input-operation
        // metadata admission. Its actual capacity is funded before it escapes.
        let path_bound=actual_path.as_os_str().len().checked_mul(8).ok_or(io::ErrorKind::OutOfMemory)?;
        let constructor=dm_preprocess::SourceAcquisitionLease::raw_constructor_storage_bytes::<RecordedSourceReceipt>()?.checked_add(path_bound).and_then(|n|if exceptional{n.checked_add(std::mem::size_of::<dm_resources::SharedBytesOwner>()+2*std::mem::size_of::<usize>())}else{Some(n)}).ok_or(io::ErrorKind::OutOfMemory)?;
        let capacity=bytes.capacity();
        let mut bytes=Some(bytes);
        let decoded=if exceptional{
            // Eliminate SharedBytes->to_vec. SAME decoder pays/allocates exact
            // decoded String while the one original raw allocation remains.
            dm_preprocess::decode_source_bytes_admitted(bytes.as_ref().unwrap(),&mut |decoded_bytes|before_decode(dm_preprocess::OriginalRawAllocationPlan::new(bytes.as_ref().unwrap(),capacity,constructor,decoded_bytes,exceptional,true)),&mut ||crate::daemon::control::checkpoint())?
        }else{
            before_decode(dm_preprocess::OriginalRawAllocationPlan::new(bytes.as_ref().unwrap(),capacity,constructor,0,exceptional,true))?;
            // Genuine UTF8 classification above; consuming Vec does not allocate.
            String::from_utf8(bytes.take().unwrap()).map_err(|_|invalid("validated UTF8 changed"))?
        };
        let path=actual_path.to_path_buf();if path.capacity()>path_bound{return Err(io::ErrorKind::OutOfMemory.into())}let fact=FileInput{path,stamp:digest.stamp,content:digest.content};
        let mut receipt=RecordedSourceReceipt{exact_open:true,checked_epoch:AtomicUsize::new(0),original_bytes:None,issuer:Arc::clone(&self.source_issuer),legacy_path:None,fact};
        let source=if exceptional{
            let funding = fund_text.map(|fund| fund.split_exceptional_bytes(
                capacity, dm_resources::SharedBytes::owner_allocation_bytes(),
            )).transpose()?.flatten();
            let bytes = bytes.take().expect("fresh exceptional read still owns raw bytes");
            let original = match funding {
                Some((payload, control)) => dm_resources::SharedBytes::from_source_arena(bytes, payload, control)?,
                None => dm_resources::SharedBytes::from(bytes),
            };
            receipt.original_bytes = Some(original);
            // The actual raw owner remains on this receipt, with no legacy cache alias.
            dm_preprocess::SourceAcquisitionLease::from_raw_original_decoded(decoded,encoding,receipt)
        }else{
            // The actual opened read and its full raw allocation have already
            // been admitted. Borrow prepared bytes only as a candidate, after
            // all actual digest, encoding and before_decode checks.
            let candidate=self.prepared_text_for_exact_open(actual_path);
            match fund_text {
                Some(fund_text) => dm_preprocess::SourceAcquisitionLease::from_raw_original_decoded_with_funding(
                    decoded, encoding, receipt, candidate.as_ref(), &fund_text.for_recorder(&self.original_read_group),
                )?,
                None => dm_preprocess::SourceAcquisitionLease::from_raw_original_decoded_with_candidate(
                    decoded, encoding, receipt, candidate.as_ref(),
                ),
            }
        };
        acquired(&source)?;
        let actual_path=source.receipt::<RecordedSourceReceipt>().expect("same private receipt").path();
        if !self.validate_recorded_source_lease(actual_path,&source){return Err(invalid("actual raw read acquisition issuer/path/facts differ"))}
        Ok(source)
    }
    fn prepared_text_for_exact_open(&self,path:&Path)->Option<SourceText>{
        let ordinary=self.source_acquisitions.lock().ok()?;
        let candidate=ordinary.get(path)?;
        let receipt=candidate.receipt::<RecordedSourceReceipt>()?;
        // No canonicalization, filesystem metadata, old content digest,
        // prepared artifact validation, or previous proof enters this loan.
        (!receipt.exact_open
            && receipt.path().as_os_str().as_encoded_bytes()==path.as_os_str().as_encoded_bytes()
            && Arc::ptr_eq(&receipt.issuer,&self.source_issuer)
            && candidate.encoding()==dm_preprocess::SourceEncoding::Utf8)
            .then(||candidate.lease().source_text().clone())
    }
    /// Borrow the actual recorded original, never a decoded-text reencoding.
    /// This authenticates current byte input only, not logical/token EOF.
    pub(super) fn original_bytes_checked<'a>(&'a self,lease:&'a dm_preprocess::SourceAcquisitionLease)->io::Result<&'a[u8]>{
        if self.initial_environment!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(invalid("Original bytes require its actual Original pipeline context"))}
        let Some(receipt)=lease.receipt::<RecordedSourceReceipt>() else {
            // A lease has one concrete receipt. Only a non-recorded receipt
            // can be the subject's private synthetic header.
            if self.analysis_subject.as_ref().is_some_and(|subject|
                subject.authenticates_header(subject.project(),lease))
            {
                return Ok(lease.source_text().as_bytes());
            }
            return Err(invalid("Original bytes lack a genuine recorded read receipt"));
        };
        let current=if receipt.exact_open{
            self.exact_byte_loan_epoch(receipt).is_some()
        }else{
            self.validate_recorded_source_receipt(receipt.path(),receipt)
        };
        if !current{return Err(invalid("Original byte lease differs from current issuer/path/input facts"))}
        match recorded_source_original_with_receipt(lease,receipt)?{RecordedSourceOriginal::Utf8(text)=>Ok(text.as_bytes()),RecordedSourceOriginal::Bytes(bytes)=>Ok(bytes.as_slice())}
    }
    pub(super) fn original_geometry_recorder(&self) -> (&Arc<()>, &AtomicUsize) {
        (&self.source_issuer, self.snapshot.published_epoch_flag())
    }

    pub(super) fn original_geometry_byte_loan<'a>(
        &'a self, lease: &'a dm_preprocess::SourceAcquisitionLease,
    ) -> io::Result<dm_preprocess::OriginalGeometryByteLoan<'a>> {
        use dm_preprocess::OriginalGeometryByteLoan as Loan;
        let Some(receipt) = lease.receipt::<RecordedSourceReceipt>().filter(|r| r.exact_open) else {
            return self.original_bytes_checked(lease).map(Loan::ordinary);
        };
        if self.initial_environment != dm_preprocess::InitialEnvironment::OriginalChecker0290 {
            return Err(invalid("Original bytes require its actual Original pipeline context"));
        }
        let epoch = self.exact_byte_loan_epoch(receipt)
            .ok_or_else(|| invalid("Original byte lease differs from current issuer/path/input facts"))?;
        let bytes = match recorded_source_original_with_receipt(lease, receipt)? {
            RecordedSourceOriginal::Utf8(text) => text.as_bytes(),
            RecordedSourceOriginal::Bytes(bytes) => bytes.as_slice(),
        };
        Ok(match std::num::NonZeroUsize::new(epoch) {
            Some(epoch) => Loan::for_recorder_epoch(bytes, self.snapshot.published_epoch_flag(), epoch),
            None => Loan::ordinary(bytes),
        })
    }
    pub(super) fn refresh_source_acquisition(
        &self,
        path: &Path,
        source: &Arc<dm_preprocess::regions::prepared_source::PreparedSource>,
        old: Option<&AcquiredSource>,
    ) -> io::Result<Option<AcquiredSource>> {
        let path = canonical_path(path);
        // Caller has just authenticated the retained PreparedInputPayload's
        // complete InputSnapshot. No certificate is minted for old payloads.
        let Some(old) = old else {
            self.source_acquisitions
                .lock()
                .map_err(|_| invalid("source acquisition mutex poisoned"))?
                .remove(&path);
            return Ok(None);
        };
        let previous = old
            .receipt::<RecordedSourceReceipt>()
            .ok_or_else(|| invalid("foreign prepared acquisition receipt"))?;
        if previous.path() != &path || !Arc::ptr_eq(old.prepared(), source) {
            return Err(invalid("prepared acquisition source owner differs"));
        }
        let fact = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input mutex poisoned"))?
            .files
            .get(&path)
            .cloned()
            .ok_or_else(|| invalid("refreshed source fact missing"))?;
        if previous.fact.content != fact.content {
            return Err(invalid("prepared proof changed original acquisition"));
        }
        let current = old.reissued(RecordedSourceReceipt {
            exact_open:false,
            checked_epoch:AtomicUsize::new(0),
            original_bytes: previous.original_bytes.clone(),
            issuer: Arc::clone(&self.source_issuer),
            legacy_path: Some(path.clone()),
            fact,
        });
        self.source_acquisitions
            .lock()
            .map_err(|_| invalid("source acquisition mutex poisoned"))?
            .insert(path, current.clone());
        Ok(Some(current))
    }
    pub(crate) fn validate_source_acquisition(
        &self,
        path: &Path,
        acquired: &AcquiredSource,
    ) -> bool {
        self.validate_source_lease(path, acquired.lease())
    }
    pub(super) fn validate_recorded_source_lease(
        &self,
        path: &Path,
        acquired: &dm_preprocess::SourceAcquisitionLease,
    ) -> bool {
        acquired.receipt::<RecordedSourceReceipt>()
            .is_some_and(|receipt|self.validate_recorded_source_receipt(path,receipt))
    }
    /// This is the self-path byte route. Explicit paths and reissues validate fully.
    fn exact_byte_loan_epoch(&self, receipt: &RecordedSourceReceipt) -> Option<usize> {
        if !receipt.exact_open || !Arc::ptr_eq(&receipt.issuer, &self.source_issuer) { return None; }
        let checked = receipt.checked_epoch.load(Ordering::SeqCst);
        if self.snapshot.accepts_epoch(checked) { return Some(checked); }
        let current = self.snapshot.lock().ok()?;
        if !Self::exact_receipt_matches(&current, receipt.path(), receipt) { return None; }
        let checked = current.epoch();
        receipt.checked_epoch.store(checked, Ordering::SeqCst);
        Some(checked)
    }

    #[cfg(test)]
    pub(super) fn exact_loan_is_warm(&self,lease:&dm_preprocess::SourceAcquisitionLease)->bool{
        lease.receipt::<RecordedSourceReceipt>().is_some_and(|receipt|
            receipt.exact_open&&Arc::ptr_eq(&receipt.issuer,&self.source_issuer)
                &&self.snapshot.accepts_epoch(receipt.checked_epoch.load(Ordering::SeqCst)))
    }
    fn validate_recorded_source_receipt(&self,path:&Path,receipt:&RecordedSourceReceipt)->bool{
        if receipt.exact_open{return self.validate_recorded_source_receipt_canonical(path,receipt)}
        let path=canonical_path(path);
        self.validate_recorded_source_receipt_canonical(&path,receipt)
    }
    fn validate_recorded_source_lease_canonical(&self,path:&Path,acquired:&dm_preprocess::SourceAcquisitionLease)->bool{
        acquired.receipt::<RecordedSourceReceipt>()
            .is_some_and(|receipt|self.validate_recorded_source_receipt_canonical(path,receipt))
    }
    fn validate_recorded_source_receipt_canonical(&self,path:&Path,receipt:&RecordedSourceReceipt)->bool{
        let recorded=receipt.path().as_path();
        if !Arc::ptr_eq(&receipt.issuer, &self.source_issuer)
            || (!std::ptr::eq(recorded,path)&&recorded!=path) {
            return false;
        }
        let Ok(snapshot) = self.snapshot.lock() else {
            return false;
        };
        if receipt.exact_open{return Self::exact_receipt_matches(&snapshot,path,receipt)}
        if snapshot.files.get(path) != Some(&receipt.fact) {
            return false;
        }
        true
    }
    fn exact_receipt_matches(snapshot:&InputSnapshot,path:&Path,receipt:&RecordedSourceReceipt)->bool{
        snapshot.opened_reads.get_ref(path).is_some_and(|status|status.is_readable())
            &&snapshot.original_payloads.get_ref(path).is_some_and(|fact|fact.stamp==receipt.fact.stamp&&fact.content==receipt.fact.content)
    }
    /// A raw read receipt proves acquired bytes, never a prepared compiler input.
    pub(crate) fn validate_source_lease(
        &self,
        path: &Path,
        acquired: &dm_preprocess::SourceAcquisitionLease,
    ) -> bool {
        let path=canonical_path(path);
        if !self.validate_recorded_source_lease_canonical(&path,acquired){return false}
        self.source_acquisitions
            .lock()
            .ok()
            .and_then(|m| {
                m.get(&path)
                    .map(|current| current.lease().same_binding(acquired))
            })
            .unwrap_or(false)
    }
    pub(super) fn current_source_acquisition(
        &self,
        path: &Path,
        text: &SourceText,
    ) -> Option<AcquiredSource> {
        let path = canonical_path(path);
        let acquired = self.source_acquisitions.lock().ok()?.get(&path)?.clone();
        (acquired.prepared().original().same_view(text)
            && self.validate_source_acquisition(&path, &acquired))
        .then_some(acquired)
    }
}
#[cfg(test)]
#[path = "input_source_acquisition_tests.rs"]
mod tests;

#[path = "input_source_semantic.rs"]
mod semantic;
pub(crate) use semantic::SemanticSourceEvidence;

/// Exact opened-read receipt ownership, separate from resource-only weak
/// observations and from the source issuance represented by this object.
pub(crate) fn exact_open_receipt_charge(value: &(dyn std::any::Any + Send + Sync)) -> io::Result<usize> {
    let receipt = value.downcast_ref::<RecordedSourceReceipt>()
        .filter(|receipt| receipt.exact_open && receipt.legacy_path.is_none() && receipt.original_bytes.is_none())
        .ok_or_else(|| invalid("receipt credit requires the actual exact opened UTF-8 receipt"))?;
    use std::alloc::Layout;
    let allocation = Layout::new::<[usize; 2]>().extend(Layout::new::<RecordedSourceReceipt>())
        .map_err(|_| io::ErrorKind::OutOfMemory)?.0.pad_to_align().size();
    allocation.checked_add(receipt.fact.path.capacity())
        .ok_or_else(|| io::ErrorKind::OutOfMemory.into())
}

pub(crate) fn recorded_source_receipt_storage(
    value: &(dyn std::any::Any + Send + Sync),
) -> Option<(&PathBuf, &PathBuf, &Arc<()>)> {
    if let Some(storage)=super::analysis_subject::subject_receipt_storage(value){return Some(storage)}
    let value = value.downcast_ref::<RecordedSourceReceipt>()?;
    Some((value.path(), &value.fact.path, &value.issuer))
}

/// Borrow a private original-byte representation issued by the SAME primary read.
/// Normal UTF8 has no additional raw buffer. Exceptional bytes share the existing
/// SharedBytes acquisition; no decoded hash/pointer reconstructs raw authority.
pub(crate) enum RecordedSourceOriginal<'a> {
    Utf8(&'a dm_preprocess::SourceText),
    Bytes(&'a dm_resources::SharedBytes),
}
pub(crate) fn recorded_source_original(
    lease: &dm_preprocess::SourceAcquisitionLease,
) -> io::Result<RecordedSourceOriginal<'_>> {
    let receipt = lease
        .receipt::<RecordedSourceReceipt>()
        .ok_or_else(|| invalid("original source bytes have no recorded acquisition receipt"))?;
    recorded_source_original_with_receipt(lease,receipt)
}
fn recorded_source_original_with_receipt<'a>(
    lease: &'a dm_preprocess::SourceAcquisitionLease,
    receipt: &'a RecordedSourceReceipt,
) -> io::Result<RecordedSourceOriginal<'a>> {
    if let Some(bytes) = &receipt.original_bytes {
        return Ok(RecordedSourceOriginal::Bytes(bytes));
    }
    if lease.encoding() != dm_preprocess::SourceEncoding::Utf8 {
        return Err(invalid("exceptional source original bytes unavailable"));
    }
    Ok(RecordedSourceOriginal::Utf8(lease.source_text()))
}
pub(crate) fn recorded_source_receipt_original(
    value: &(dyn std::any::Any + Send + Sync),
) -> Option<&dm_resources::SharedBytes> {
    value
        .downcast_ref::<RecordedSourceReceipt>()?
        .original_bytes
        .as_ref()
}

/// SAME raw normalization for actual recorded originals. Caller preadmits the
/// exposed transform peak; this source-neutral projection grants no source role.
pub(crate) fn normalize_recorded_policy_original(original:&RecordedSourceOriginal<'_>)->dm_preprocess::SourceText{
 match original{
  RecordedSourceOriginal::Utf8(text)if !text.as_bytes().contains(&b'\r')=>(*text).clone(),
  _=>{let raw=match original{RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()};String::from_utf8_lossy(raw).replace("\r\n","\n").replace('\r',"\n").into()}
 }
}

/// Resource DATA only: actual source backing addresses never grant a read role.
pub(crate) fn visit_raw_source_backing(lease:&dm_preprocess::SourceAcquisitionLease,mut visit:impl FnMut((u8,usize),usize)){
 lease.source_text().visit_storage(|address,bytes,storage|{visit((0,address),bytes.saturating_add(2*std::mem::size_of::<usize>()));match storage{dm_preprocess::SourceTextStorage::Original(text)=>visit((1,Arc::as_ptr(text)as *const u8 as usize),text.len().saturating_add(2*std::mem::size_of::<usize>())),dm_preprocess::SourceTextStorage::Transformed(text)=>visit((1,text.as_ptr()as usize),text.capacity()),dm_preprocess::SourceTextStorage::Reserved{text,committed}=>visit((1,text.as_ptr()as usize),committed)}});
 lease.source_text().visit_fingerprint_storage(|address,_,bytes|{if bytes!=0{visit((4,address),bytes);}});
 if let Some(bytes)=lease.receipt::<RecordedSourceReceipt>().and_then(|r|r.original_bytes.as_ref()){visit((2,bytes.owner_address()),std::mem::size_of_val(bytes.shared_owner())+2*std::mem::size_of::<usize>());visit((3,bytes.as_ptr()as usize),bytes.capacity());}
}

#[cfg(test)]mod raw_recorded_validation_tests{
 use super::*;
 #[test]fn genuine_raw_read_validates_without_minting_a_native_prepared_source(){
  let root=crate::test_scratch::dir("raw-recorded-validation");std::fs::create_dir_all(&root).unwrap();let path=root.join("source.dm");std::fs::write(&path,"/proc/probe()\n    return 1\n").unwrap();
  let inputs=RecordingInputs::new(FileSystemInputs,0);
  let lease=inputs.read_raw_source(&path,65536,None,|_,_,_|Ok(())).unwrap().unwrap();
  assert!(inputs.validate_recorded_source_lease(&path,&lease));assert!(!inputs.validate_source_lease(&path,&lease));
  assert!(inputs.source_acquisitions.lock().unwrap().is_empty(),"raw read never constructs or registers PreparedSource");
  assert!(!inputs.validate_recorded_source_lease(&root.join("different.dm"),&lease));
  let other=RecordingInputs::new(FileSystemInputs,0);assert!(!other.validate_recorded_source_lease(&path,&lease));
 }
 #[test]fn raw_reissue_reuses_actual_original_bytes_but_binds_only_the_new_actual_read(){
  let root=crate::test_scratch::dir("raw-recorded-reissue-validation");std::fs::create_dir_all(&root).unwrap();let path=root.join("source.dm");std::fs::write(&path,b"\xef\xbb\xbf/proc/probe()\r\n    return 1\r\n").unwrap();
  let first=RecordingInputs::new(FileSystemInputs,0);let old=first.read_raw_source(&path,65536,None,|_,_,_|Ok(())).unwrap().unwrap();
  let second=RecordingInputs::new(FileSystemInputs,0);let current=second.read_raw_source(&path,65536,Some(&old),|_,_,needs_decode|{assert!(!needs_decode,"same actual bytes reuse original decoding");Ok(())}).unwrap().unwrap();
  assert!(old.source_text().same_view(current.source_text()));assert!(!old.same_binding(&current));
  assert!(first.validate_recorded_source_lease(&path,&old));assert!(!first.validate_recorded_source_lease(&path,&current));
  assert!(second.validate_recorded_source_lease(&path,&current));assert!(!second.validate_recorded_source_lease(&path,&old));
  assert!(!second.validate_source_lease(&path,&current));assert!(second.source_acquisitions.lock().unwrap().is_empty());
 }
}

#[cfg(test)]mod original_raw_provider_tests{
 use super::*;use dm_preprocess::SourceProvider;
 #[test]fn actual_original_provider_lends_same_bytes_without_native_preparation_or_reopen(){
  for(raw,label)in[(&b"/proc/probe()\n    return 1\n"[..],"utf8"),(&b"\xef\xbb\xbf/proc/probe()\r\n"[..],"bom"),(&b"/proc/probe()\n    // \x80\xff\n"[..],"legacy")]{
   let root=crate::test_scratch::dir(&format!("original-raw-provider-{label}"));std::fs::create_dir_all(&root).unwrap();let path=root.join("source.dm");std::fs::write(&path,raw).unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);let observed=std::cell::Cell::new(0);
   let lease=inputs.original_raw_source_checked(&path,4096,&mut |capacity,_,decode|{assert!(capacity>=raw.len());assert!(decode);observed.set(observed.get()+1);Ok(())}).unwrap().unwrap();assert_eq!(observed.get(),1);assert!(inputs.source_acquisitions.lock().unwrap().is_empty());assert!(!inputs.validate_source_lease(&path,&lease));
   let borrowed=inputs.original_source_bytes(&lease).unwrap().unwrap();assert_eq!(borrowed,raw);let pointer=borrowed.as_ptr();std::fs::remove_file(&path).unwrap();assert_eq!(inputs.original_source_bytes(&lease).unwrap().unwrap().as_ptr(),pointer,"lending uses recorded bytes, never reopens source");assert_eq!(lease.source_text().as_str(),dm_preprocess::decode_source_bytes(raw));
   let foreign=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);assert!(foreign.original_source_bytes(&lease).is_err());
  }
 }
 #[test]fn native_context_and_unissued_provider_never_fallback_to_an_original_raw_grant(){
  let root=crate::test_scratch::dir("original-raw-context");std::fs::create_dir_all(&root).unwrap();let path=root.join("missing.dm");let native=RecordingInputs::new(FileSystemInputs,0);assert!(native.original_raw_source_checked(&path,4096,&mut |_,_,_|panic!("wrong context must reject before read/admission")).is_err());assert!(native.snapshot.lock().unwrap().files.is_empty());assert_eq!(dm_preprocess::FileSystem.original_raw_source_checked(&path,4096,&mut |_,_,_|panic!("default provider grants no read")).unwrap_err().kind(),io::ErrorKind::NotConnected);
 }
 #[test]fn original_raw_missing_is_an_actual_recorded_negative_not_an_unissued_provider(){
  let root=crate::test_scratch::dir("original-raw-negative");std::fs::create_dir_all(&root).unwrap();let path=root.join("missing.dm");let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);assert!(inputs.original_raw_source_checked(&path,4096,&mut |_,_,_|panic!("absent source has no decode")).unwrap().is_none());assert!(inputs.snapshot.lock().unwrap().negative_files.contains(&canonical_path(&path)));assert!(inputs.source_acquisitions.lock().unwrap().is_empty());
 }
 #[test]fn original_raw_predecode_preserves_actual_first_io_and_same_input_can_retry(){
  let root=crate::test_scratch::dir("original-raw-provider-io");std::fs::create_dir_all(&root).unwrap();let path=root.join("source.dm");std::fs::write(&path,b"\xef\xbb\xbf/proc/probe()\n").unwrap();let inputs=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
  let error=inputs.original_raw_source_checked(&path,4096,&mut |_,_,_|Err(io::Error::from_raw_os_error(1450))).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert!(inputs.source_acquisitions.lock().unwrap().is_empty());let lease=inputs.original_raw_source_checked(&path,4096,&mut |_,_,_|Ok(())).unwrap().unwrap();assert!(inputs.original_source_bytes(&lease).unwrap().is_some());
 }
}

/// Receipt comparison only; no public source constructor or new source grant.
pub(super) fn recorded_root_lease_matches(lease:&dm_preprocess::SourceAcquisitionLease,issuer:&Arc<()>,path:&Path,exact:bool)->bool{lease.receipt::<RecordedSourceReceipt>().is_some_and(|receipt|Arc::ptr_eq(&receipt.issuer,issuer)&&receipt.path().as_path()==path&&(!exact||receipt.exact_open))}

/// Borrow the actual private exact-open acquisition receipt against an
/// already admitted/current snapshot. No source bytes, path or FileInput are
/// synthesized. In particular an ordinary positive row must remain present;
/// readable Original open/payload observations alone do not substitute for it.
pub(crate) fn recorded_original_source_fact_in<'a>(
    mapping: &'a dm_tree::frontend::SourceExportMapping, occurrence: usize, current: &InputSnapshot,
) -> io::Result<&'a FileInput> {
    if mapping.initial_environment() != dm_preprocess::InitialEnvironment::OriginalChecker0290 {
        return Err(invalid("native primary fact requires actual Original mapping"));
    }
    let lease = mapping.source_acquisition(occurrence)
        .ok_or_else(|| invalid("native primary fact acquisition is absent"))?;
    let receipt = lease.receipt::<RecordedSourceReceipt>()
        .filter(|receipt| receipt.exact_open && receipt.legacy_path.is_none())
        .ok_or_else(|| invalid("native primary fact has no actual exact-open receipt"))?;
    let fact = &receipt.fact;
    if !RecordingInputs::<FileSystemInputs>::exact_receipt_matches(current, fact.path.as_path(), receipt)
        || current.files.get(&fact.path).is_none_or(|recorded|
            recorded.path.as_os_str() != fact.path.as_os_str() || recorded != fact)
    {
        return Err(invalid("native primary ordinary fact differs from its actual receipt"));
    }
    Ok(fact)
}

impl<P:SnapshotProvider> RecordingInputs<P>{
 /// A mapping loan authenticates the exact Original acquisition independently
 /// of the unrelated native PreparedSource cache. This returns observation DATA,
 /// never a prepared/compiler input or a current-source/semantic grant.
 /// The joined closure holds this recorder's snapshot lock already. Use
 /// that loan directly, preserving exact issuer/receipt/path and ordinary-row
 /// checks without attempting a recursive snapshot lock.
 pub(crate) fn mapped_original_source_fact_in<'a>(
    &self, mapping: &'a dm_tree::frontend::SourceExportMapping, occurrence: usize,
    path: &Path, current: &InputSnapshot,
 ) -> io::Result<&'a FileInput> {
    let fact = recorded_original_source_fact_in(mapping, occurrence, current)?;
    let receipt = mapping.source_acquisition(occurrence)
        .and_then(|lease| lease.receipt::<RecordedSourceReceipt>())
        .ok_or_else(|| invalid("native primary fact receipt is absent"))?;
    if !Arc::ptr_eq(&receipt.issuer, &self.source_issuer)
        || fact.path.as_os_str() != path.as_os_str()
    {
        return Err(invalid("native primary fact belongs to another recorder or path"));
    }
    Ok(fact)
 }
 pub(crate) fn mapped_recorded_source_fact<'a>(&self,mapping:&'a dm_tree::frontend::SourceExportMapping,occurrence:usize,path:&Path)->io::Result<&'a FileInput>{
  let lease=mapping.source_acquisition(occurrence).ok_or_else(||{
    let indexed=mapping.source_acquisitions().nth(occurrence).map(|(path,_)|path);
    invalid(&format!("mapped original acquisition absent: occurrence={occurrence} requested={} indexed={indexed:?} slots={}",path.display(),mapping.source_acquisitions().count()))
  })?;
  let receipt=lease.receipt::<RecordedSourceReceipt>().ok_or_else(||invalid("mapped original has no actual recorder receipt"))?;
  let valid=if receipt.exact_open{mapping.initial_environment()==dm_preprocess::InitialEnvironment::OriginalChecker0290&&self.validate_recorded_source_lease(path,lease)}else{self.validate_source_lease(path,lease)};
  if !valid{return Err(invalid("mapped original belongs to another recorder/open/payload observation"))}Ok(&receipt.fact)
 }
}

impl<P:SnapshotProvider> RecordingInputs<P>{
 /// Readonly provenance inspection for an embedding diagnostic borrower that
 /// already owns this RecordingInputs and a genuinely issued native mapping.
 /// Actual Original raw reads deliberately are not in the PreparedSource cache;
 /// this check lets that borrower reject a foreign recorder or wrong occurrence
 /// before displaying provenance without creating a second preparation.
 /// No IO, lease, receipt, prepared source, EOF, completeness or current-source
 /// role is issued. Success is not a reusable source-admission witness and no
 /// compiler/query API accepts it in place of its existing typed admissions.
 pub fn check_recorded_mapping_observation(&self,mapping:&dm_tree::frontend::SourceExportMapping,occurrence:usize,path:&Path)->io::Result<()>{self.mapped_recorded_source_fact(mapping,occurrence,path).map(|_|())}
}
