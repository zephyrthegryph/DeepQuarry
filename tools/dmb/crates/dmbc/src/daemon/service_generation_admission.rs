//! The Accepted reply commits this generation to draining a queued request.
use super::*;

/// Issued only while this exact daemon's retirement barrier remains open.
/// Connections already account for queued work and terminal reply delivery;
/// this certificate adds no separate queue, counter or capacity reservation.
pub(super) struct AcceptedRequest(Arc<Shared>);

impl Shared {
    pub(super) fn accept_request(self: &Arc<Self>) -> io::Result<AcceptedRequest> {
        // This mutex also serializes retirement and numeric permit admission.
        // A racing Retire either precedes issuance or observes a drainable
        // request; it can never invalidate a ticket after Accepted was sent.
        let _active = self
            .running
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if self.retiring.load(Ordering::Acquire) {
            return Err(io::Error::other("daemon retiring"));
        }
        Ok(AcceptedRequest(Arc::clone(self)))
    }

    pub(super) fn retire(&self) {
        {
            let _active = self
                .running
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            self.retiring.store(true, Ordering::Release);
        }
        self.capacity.notify_all();
    }

    pub(super) fn acquire_accepted_until(
        self: &Arc<Self>,
        accepted: &AcceptedRequest,
        workers: usize,
        deadline: &admission_deadline::AdmissionDeadline,
    ) -> io::Result<Permit> {
        self.acquire_accepted_until_observing(accepted, workers, deadline, transport::private_bytes)
    }

    fn acquire_accepted_until_observing(
        self: &Arc<Self>,
        accepted: &AcceptedRequest,
        workers: usize,
        deadline: &admission_deadline::AdmissionDeadline,
        private_bytes: impl Fn() -> Option<u64>,
    ) -> io::Result<Permit> {
        if !Arc::ptr_eq(&accepted.0, self) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "accepted request belongs to a different daemon generation",
            ));
        }
        // Retirement closes new ticket issuance. Existing tickets still use
        // the ordinary worker/private-memory throttle and current deadline /
        // cancellation checkpoints; draining cannot oversubscribe the pool.
        self.acquire_with_admission_until_observing(workers, deadline, true, private_bytes)
    }

    pub(super) fn exit_ready(&self, incoming: bool, idle_for: Duration) -> bool {
        // An accepted listener result has not acquired its Connection guard yet.
        // It must reach dispatch before idle exit can inspect zero counters.
        !incoming
            && (self.retiring.load(Ordering::Acquire) || idle_for >= Duration::from_secs(7200))
            && *self
                .running
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                == 0
            && self.connections.load(Ordering::Acquire) == 0
    }
}

#[cfg(test)]
#[path = "service_generation_admission_tests.rs"]
mod tests;
