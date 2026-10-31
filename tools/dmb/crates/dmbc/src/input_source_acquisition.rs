//! Primary-read acquisition leases, separately owned from interned lexical text.
use super::*;
use dm_preprocess::{AcquiredSource, SourceText};
use std::sync::Arc;
struct RecordedSourceReceipt {
    original_bytes: Option<dm_resources::SharedBytes>,
    issuer: Arc<()>,
    path: PathBuf,
    fact: FileInput,
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub(super) fn acquire_recorded_source(
        &self,
        path: &Path,
        bytes: Vec<u8>,
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
            original_bytes: None,
            issuer: Arc::clone(&self.source_issuer),
            path: path.clone(),
            fact,
        };
        let acquired = if bytes.starts_with(b"\xef\xbb\xbf") || std::str::from_utf8(&bytes).is_err()
        {
            let bytes = dm_resources::SharedBytes::from(bytes);
            self.remember_exceptional_source(&path, bytes.clone())?;
            receipt.original_bytes = Some(bytes.clone());
            AcquiredSource::from_original_slice(bytes.as_slice(), receipt)
        } else {
            AcquiredSource::from_original_bytes(bytes, receipt)
        };
        self.source_acquisitions
            .lock()
            .map_err(|_| invalid("source acquisition mutex poisoned"))?
            .insert(path, acquired.clone());
        Ok(acquired)
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
        if previous.path != path || !Arc::ptr_eq(old.prepared(), source) {
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
            original_bytes: previous.original_bytes.clone(),
            issuer: Arc::clone(&self.source_issuer),
            path: path.clone(),
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
    pub(crate) fn validate_source_lease(
        &self,
        path: &Path,
        acquired: &dm_preprocess::SourceAcquisitionLease,
    ) -> bool {
        let path = canonical_path(path);
        let Some(receipt) = acquired.receipt::<RecordedSourceReceipt>() else {
            return false;
        };
        if !Arc::ptr_eq(&receipt.issuer, &self.source_issuer) || receipt.path != path {
            return false;
        }
        let Ok(snapshot) = self.snapshot.lock() else {
            return false;
        };
        if snapshot.files.get(&path) != Some(&receipt.fact) {
            return false;
        }
        drop(snapshot);
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

pub(crate) fn recorded_source_receipt_storage(
    value: &(dyn std::any::Any + Send + Sync),
) -> Option<(&PathBuf, &PathBuf, &Arc<()>)> {
    let value = value.downcast_ref::<RecordedSourceReceipt>()?;
    Some((&value.path, &value.fact.path, &value.issuer))
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
