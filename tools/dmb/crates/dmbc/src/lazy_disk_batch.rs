//! One request spool shared by every semantic producer. Append never publishes.
use super::*;
pub(super) enum State {
    Dormant,
    Open(dm_cache::BatchSpool),
    Failed(String),
    Finished,
}
pub struct Attempt<'a>(&'a LazyDisk);
impl Drop for Attempt<'_> {
    fn drop(&mut self) {
        let mut state = self
            .0
            .batch
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if !matches!(*state, State::Finished) {
            // Failure/panic/cancellation invalidates escaped producer handles too.
            *state = State::Failed("cache request ended without completion".into());
        }
    }
}
impl LazyDisk {
    pub fn batch_attempt(&self) -> Attempt<'_> {
        Attempt(self)
    }

    pub fn append_records(&self, records: Vec<dm_cache::Record>) -> Result<(), String> {
        if records.is_empty() {
            return Ok(());
        }
        let mut state = self
            .batch
            .lock()
            .map_err(|_| "cache batch lock poisoned".to_owned())?;
        if matches!(*state, State::Dormant) {
            let opened = if self.root.is_none() {
                self.loaded_snapshot()
                    .ok_or("captured cache snapshot missing")
                    .map_err(str::to_owned)
                    .and_then(|snapshot| snapshot.batch_spool().map_err(|error| error.to_string()))
            } else {
                self.writer()
                    .map_err(str::to_owned)
                    .and_then(|cache| cache.batch_spool().map_err(|error| error.to_string()))
            };
            *state = match opened {
                Ok(spool) => State::Open(spool),
                Err(error) => State::Failed(error),
            };
        }
        match &mut *state {
            State::Open(spool) => {
                for record in records {
                    if let Err(error) = spool.append(record) {
                        let error = error.to_string();
                        // Drop failed private files immediately; future calls fail closed.
                        *state = State::Failed(error.clone());
                        return Err(error);
                    }
                }
                Ok(())
            }
            State::Failed(error) => Err(error.clone()),
            State::Finished => Err("cache batch already finished".into()),
            State::Dormant => unreachable!(),
        }
    }
    pub fn visit_batch_storage(&self, visitor: impl FnMut(dm_cache::BatchStorageView)) {
        let state = self.batch.lock().unwrap_or_else(|error| error.into_inner());
        if let State::Open(spool) = &*state {
            spool.visit_storage(visitor);
        }
    }
    /// The request coordinator alone calls this after successful output publication.
    /// All producers must have joined; completion is terminal, including failure.
    pub fn finish_batch(&self) -> Result<dm_cache::BatchReport, String> {
        let mut state = self
            .batch
            .lock()
            .map_err(|_| "cache batch lock poisoned".to_owned())?;
        match std::mem::replace(&mut *state, State::Finished) {
            State::Dormant => Ok(dm_cache::BatchReport::default()),
            State::Open(spool) => spool.finish().map_err(|error| error.to_string()),
            State::Failed(error) => Err(error),
            State::Finished => Err("cache batch already finished".into()),
        }
    }
}
#[cfg(test)]
#[path = "lazy_disk_batch_tests.rs"]
mod tests;
