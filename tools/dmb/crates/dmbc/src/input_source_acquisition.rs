//! Primary-read acquisition leases, separately owned from interned lexical text.
use super::*;
use dm_preprocess::{AcquiredSource, SourceText};
use std::sync::Arc;
struct RecordedSourceReceipt {
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
        let receipt = RecordedSourceReceipt {
            issuer: Arc::clone(&self.source_issuer),
            path: path.clone(),
            fact,
        };
        let acquired = if bytes.starts_with(b"\xef\xbb\xbf") || std::str::from_utf8(&bytes).is_err()
        {
            let bytes = dm_resources::SharedBytes::from(bytes);
            self.remember_exceptional_source(&path, bytes.clone())?;
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
            .and_then(|m| m.get(&path).map(|current| current.same_binding(acquired)))
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
