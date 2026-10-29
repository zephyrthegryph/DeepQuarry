//! Fixture-only actual-byte provider. Classification is minted from the real
//! read, never recreated from decoded text or a guessed UTF8 marker.
use dm_preprocess::{AcquiredSource, SourceProvider, SourceText};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::Mutex,
};
#[derive(Default)]
pub struct AcquiredFiles {
    issued: Mutex<BTreeMap<PathBuf, AcquiredSource>>,
}
impl SourceProvider for AcquiredFiles {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("fixture requires original acquired bytes".into())
    }
    fn acquired_source(&self, path: &Path) -> Result<Option<AcquiredSource>, String> {
        let mut issued = self
            .issued
            .lock()
            .map_err(|_| "fixture input lock poisoned")?;
        if let Some(source) = issued.get(path) {
            return Ok(Some(source.clone()));
        }
        let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
        let source = AcquiredSource::from_original_bytes(bytes, ());
        issued.insert(path.to_owned(), source.clone());
        Ok(Some(source))
    }
    fn source_acquisition(&self, path: &Path, text: &SourceText) -> Option<AcquiredSource> {
        let issued = self.issued.lock().ok()?;
        let source = issued.get(path)?;
        source
            .lease()
            .source_text()
            .same_view(text)
            .then(|| source.clone())
    }
}
