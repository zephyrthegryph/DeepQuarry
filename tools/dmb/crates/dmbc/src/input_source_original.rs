//! Exceptional original source bytes retained at their existing acquisition.
//! Normal UTF8 consumes its allocation into text and stores no byte alias.
//! This receipt is request/prepared-source ownership, not another filesystem cache.
use super::*;
use dm_resources::SharedBytes;
#[derive(Clone)]
pub(super) struct ExceptionalOriginal {
    content: u128,
    bytes: SharedBytes,
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub(super) fn decode_recorded_source(&self, path: &Path, bytes: Vec<u8>) -> io::Result<String> {
        let exceptional =
            bytes.starts_with(&[0xef, 0xbb, 0xbf]) || std::str::from_utf8(&bytes).is_err();
        if !exceptional {
            return Ok(decode_owned_source(bytes));
        }
        // Transfer the authenticated allocation; do not clone its Vec. Only
        // exceptional encodings need their distinct compiler/raw text views.
        let original = SharedBytes::from(bytes);
        self.remember_exceptional_source(path, original.clone())?;
        Ok(dm_preprocess::decode_source_bytes(original.as_slice()))
    }
    pub(super) fn remember_exceptional_source(
        &self,
        path: &Path,
        bytes: SharedBytes,
    ) -> io::Result<()> {
        let path = canonical_path(path);
        let content = xxhash_rust::xxh3::xxh3_128(bytes.as_slice());
        let fact = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .files
            .get(&path)
            .cloned()
            .ok_or_else(|| invalid("exceptional source has no recorded file fact"))?;
        if fact.content != content {
            return Err(invalid(
                "exceptional source bytes contradict recorded digest",
            ));
        }
        if !bytes.starts_with(&[0xef, 0xbb, 0xbf]) && std::str::from_utf8(bytes.as_slice()).is_ok()
        {
            return Err(invalid(
                "ordinary UTF8 must not retain an exceptional byte buffer",
            ));
        }
        let mut originals = self
            .exceptional_originals
            .lock()
            .map_err(|_| invalid("source original mutex poisoned"))?;
        if let Some(previous) = originals.get(&path) {
            if previous.content != content || previous.bytes.as_slice() != bytes.as_slice() {
                return Err(invalid("contradictory source original receipt"));
            }
        } else {
            originals.insert(path, ExceptionalOriginal { content, bytes });
        }
        Ok(())
    }
    /// Historical raw bytes from this request's primary read, never a reread.
    pub(crate) fn exceptional_source_bytes(&self, path: &Path) -> io::Result<Option<SharedBytes>> {
        let path = canonical_path(path);
        let content = self
            .snapshot
            .lock()
            .map_err(|_| invalid("input capture mutex poisoned"))?
            .files
            .get(&path)
            .map(|fact| fact.content);
        let originals = self
            .exceptional_originals
            .lock()
            .map_err(|_| invalid("source original mutex poisoned"))?;
        let Some(original) = originals.get(&path) else {
            return Ok(None);
        };
        if Some(original.content) != content
            || xxhash_rust::xxh3::xxh3_128(original.bytes.as_slice()) != original.content
        {
            return Err(invalid(
                "exceptional source receipt does not match recorded original bytes",
            ));
        }
        Ok(Some(original.bytes.clone()))
    }
    pub(crate) fn visit_exceptional_source_originals(
        &self,
        mut visit: impl FnMut(&PathBuf, &SharedBytes),
    ) -> io::Result<()> {
        let originals = self
            .exceptional_originals
            .lock()
            .map_err(|_| invalid("source original mutex poisoned"))?;
        for (path, original) in originals.iter() {
            visit(path, &original.bytes);
        }
        Ok(())
    }
}
#[cfg(test)]
#[path = "input_source_original_tests.rs"]
mod tests;
