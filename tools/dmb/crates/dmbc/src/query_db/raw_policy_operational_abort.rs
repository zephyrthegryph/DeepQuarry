//! Operational failures are NOT semantic query values. The first original IO
//! error is returned by the guarded API; the independent latch stays set until
//! a new guarded family operation starts, including after that error is taken.
use super::*;
#[derive(Default)]
pub(super) struct OperationalAbort {
    aborted: std::sync::atomic::AtomicBool,
    first: Mutex<Option<io::Error>>,
    #[cfg(test)]
    polls: AtomicUsize,
    #[cfg(test)]
    cancel_at: Mutex<Option<(usize, crate::daemon::control::Cancellation)>>,
}
impl OperationalAbort {
    pub(super) fn begin(&self) {
        self.first.lock().unwrap_or_else(|e| e.into_inner()).take();
        self.aborted.store(false, Ordering::Release);
        #[cfg(test)]
        self.polls.store(0, Ordering::Relaxed);
    }
    pub(super) fn is_aborted(&self) -> bool {
        self.aborted.load(Ordering::Acquire)
    }
    pub(super) fn scan_checkpoint(&self) -> Result<(), String> {
        if self.is_aborted() {
            return Err("native policy operation aborted".into());
        }
        #[cfg(test)]
        {
            let n = self.polls.fetch_add(1, Ordering::Relaxed) + 1;
            if let Some((at, token)) = self
                .cancel_at
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .as_ref()
            {
                if n == *at {
                    token.cancel();
                }
            }
        }
        if let Err(error) = crate::daemon::control::checkpoint() {
            let message = error.to_string();
            let mut first = self.first.lock().unwrap_or_else(|e| e.into_inner());
            if first.is_none() {
                *first = Some(error);
            }
            self.aborted.store(true, Ordering::Release);
            return Err(message);
        }
        Ok(())
    }
    pub(super) fn before_outcome(&self, key: Key) -> Result<(), QueryError> {
        self.scan_checkpoint().map_err(|_| QueryError::Missing(key))
    }
    pub(super) fn take_error(&self) -> Option<io::Error> {
        self.first.lock().unwrap_or_else(|e| e.into_inner()).take()
    }
    #[cfg(test)]
    pub(super) fn cancel_on_poll(&self, at: usize, token: crate::daemon::control::Cancellation) {
        assert!(at > 1, "regression must cancel DURING computation");
        *self.cancel_at.lock().unwrap() = Some((at, token));
    }
    #[cfg(test)]
    pub(super) fn poll_count(&self) -> usize {
        self.polls.load(Ordering::Relaxed)
    }
    #[cfg(test)]
    pub(super) fn disarm(&self) {
        self.cancel_at.lock().unwrap().take();
    }
}
