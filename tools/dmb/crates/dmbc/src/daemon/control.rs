//! Cancellation is cooperative before publication; publication is indivisible.
use std::{
    cell::RefCell,
    sync::{
        atomic::{AtomicU8, Ordering},
        Arc,
    },
    time::Instant,
};
#[derive(Clone, Default)]
pub struct Cancellation(Arc<AtomicU8>);
impl Cancellation {
    pub(super) fn same_request(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }
    pub fn cancel(&self) {
        let _ = self
            .0
            .compare_exchange(0, 1, Ordering::AcqRel, Ordering::Acquire);
    }
    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::Acquire) == 1
    }
}
thread_local! {static ACTIVE:RefCell<Option<(Cancellation,bool,Option<Instant>)>>=const{RefCell::new(None)};}
pub(super) struct Binding;
pub(super) fn bind(token: Cancellation) -> Binding {
    bind_inner(token, None)
}
pub(super) fn bind_with_deadline(token: Cancellation, deadline: Instant) -> Binding {
    bind_inner(token, Some(deadline))
}
fn bind_inner(token: Cancellation, deadline: Option<Instant>) -> Binding {
    ACTIVE.with(|active| {
        assert!(active.borrow().is_none(), "one request per coordinator");
        *active.borrow_mut() = Some((token, false, deadline));
    });
    Binding
}
impl Drop for Binding {
    fn drop(&mut self) {
        ACTIVE.with(|active| *active.borrow_mut() = None);
    }
}
pub fn checkpoint() -> std::io::Result<()> {
    checkpoint_at(Instant::now())
}
fn checkpoint_at(now: Instant) -> std::io::Result<()> {
    ACTIVE.with(|active| {
        if let Some((token, publishing, deadline)) = active.borrow().as_ref() {
            if !publishing {
                if deadline.is_some_and(|deadline| now >= deadline) {
                    token.cancel();
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::Interrupted,
                        "daemon request deadline expired",
                    ));
                }
                if token.is_cancelled() {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::Interrupted,
                        "build superseded before publication",
                    ));
                }
            }
        }
        Ok(())
    })
}
/// Check cancellation once, then permanently make this request non-cancellable.
pub fn begin_publication() -> std::io::Result<()> {
    checkpoint()?;
    ACTIVE.with(|active| {
        if let Some((token, publishing, _)) = active.borrow_mut().as_mut() {
            if token
                .0
                .compare_exchange(0, 2, Ordering::AcqRel, Ordering::Acquire)
                .is_err()
                && token.is_cancelled()
            {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::Interrupted,
                    "build superseded before publication",
                ));
            }
            *publishing = true;
        }
        Ok(())
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn query_deadline_is_cooperative_and_binding_is_request_local() {
        let now = Instant::now();
        let token = Cancellation::default();
        let binding = bind_with_deadline(token.clone(), now + std::time::Duration::from_secs(20));
        checkpoint_at(now).unwrap();
        let error = checkpoint_at(now + std::time::Duration::from_secs(20)).unwrap_err();
        assert_eq!(crate::request_failure::exit_code(&error), 75);
        assert!(token.is_cancelled());
        assert!(begin_publication().is_err());
        drop(binding);
        checkpoint_at(now + std::time::Duration::from_secs(300)).unwrap();
    }
    #[test]
    fn admitted_publication_remains_indivisible_after_deadline() {
        let now = Instant::now();
        let _binding = bind_with_deadline(
            Cancellation::default(),
            now + std::time::Duration::from_secs(300),
        );
        begin_publication().unwrap();
        checkpoint_at(now + std::time::Duration::from_secs(301)).unwrap();
    }
    #[test]
    fn cancellation_stops_before_publication_but_never_during() {
        let token = Cancellation::default();
        let binding = bind(token.clone());
        begin_publication().unwrap();
        token.cancel();
        checkpoint().unwrap();
        drop(binding);
        let cancelled = Cancellation::default();
        cancelled.cancel();
        let binding = bind(cancelled);
        assert_eq!(
            checkpoint().unwrap_err().kind(),
            std::io::ErrorKind::Interrupted
        );
        assert!(begin_publication().is_err());
        drop(binding);
        checkpoint().unwrap();
    }
}
