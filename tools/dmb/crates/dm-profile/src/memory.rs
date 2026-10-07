//! Low-frequency process memory observations, never per-span OS queries.
use crate::State;
use std::sync::Arc;

const INTERVAL_MS: u64 = 20;

pub(crate) fn interval_ms() -> Option<u64> {
    cfg!(windows).then_some(INTERVAL_MS)
}

pub(crate) fn enter(state: &State, name: &'static str) {
    #[cfg(windows)]
    {
        let mut entries = state
            .entries
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let entry = entries.entry(name).or_default();
        entry.active = entry.active.saturating_add(1);
    }
    #[cfg(not(windows))]
    let _ = (state, name);
}

#[cfg(any(windows, test))]
fn observe(entry: &mut crate::Entry, private_bytes: Option<u64>) {
    if entry.active == 0 {
        return;
    }
    if let Some(bytes) = private_bytes {
        entry.report.private_memory_samples = entry.report.private_memory_samples.saturating_add(1);
        entry.report.sampled_peak_private_bytes = Some(
            entry
                .report
                .sampled_peak_private_bytes
                .unwrap_or(0)
                .max(bytes),
        );
    } else {
        entry.report.private_memory_failed_samples =
            entry.report.private_memory_failed_samples.saturating_add(1);
    }
}

pub(crate) struct Sampler {
    #[cfg(windows)]
    stop: std::sync::mpsc::Sender<()>,
    #[cfg(windows)]
    worker: std::thread::JoinHandle<()>,
}

impl Sampler {
    pub(crate) fn start(state: Arc<State>) -> Result<Option<Self>, String> {
        #[cfg(windows)]
        {
            let (stop, receiver) = std::sync::mpsc::channel();
            let worker = std::thread::Builder::new()
                .name("dm-profile-memory".into())
                .spawn(move || loop {
                    // Holding the registry lock across this one OS query keeps
                    // stage entry/exit from changing ownership mid-sample. No
                    // payload allocation, file access or per-stage OS query.
                    {
                        let mut entries = state
                            .entries
                            .lock()
                            .unwrap_or_else(|error| error.into_inner());
                        if entries.values().any(|entry| entry.active > 0) {
                            let bytes = crate::clock::current_private_bytes();
                            for entry in entries.values_mut() {
                                observe(entry, bytes);
                            }
                        }
                    }
                    match receiver.recv_timeout(std::time::Duration::from_millis(INTERVAL_MS)) {
                        Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
                        _ => break,
                    }
                })
                .map_err(|error| format!("start private-memory sampler: {error}"))?;
            Ok(Some(Self { stop, worker }))
        }
        #[cfg(not(windows))]
        {
            let _ = state;
            Ok(None)
        }
    }

    pub(crate) fn stop(self) -> Result<(), String> {
        #[cfg(windows)]
        {
            let _ = self.stop.send(());
            self.worker
                .join()
                .map_err(|_| "private-memory sampler panicked".to_string())?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn observations_only_cover_active_stages_and_keep_missing_distinct() {
        let mut entry = crate::Entry::default();
        observe(&mut entry, Some(900));
        assert_eq!(entry.report.sampled_peak_private_bytes, None);
        entry.active = 2;
        observe(&mut entry, None);
        assert_eq!(entry.report.sampled_peak_private_bytes, None);
        assert_eq!(entry.report.private_memory_failed_samples, 1);
        observe(&mut entry, Some(100));
        observe(&mut entry, Some(80));
        observe(&mut entry, Some(120));
        assert_eq!(entry.report.sampled_peak_private_bytes, Some(120));
        assert_eq!(entry.report.private_memory_samples, 3);
        entry.active = 0;
        observe(&mut entry, Some(900));
        assert_eq!(entry.report.sampled_peak_private_bytes, Some(120));
    }
}
