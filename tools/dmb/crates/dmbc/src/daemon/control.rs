//! Cancellation is cooperative before publication; publication is indivisible.
use std::{
    cell::RefCell,
    sync::{
        atomic::{AtomicU8, Ordering},
        Arc,
    },
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
thread_local! {static ACTIVE:RefCell<Option<(Cancellation,bool)>>=const{RefCell::new(None)};}
pub(super) struct Binding;
pub(super) fn bind(token: Cancellation) -> Binding {
    ACTIVE.with(|active| {
        assert!(active.borrow().is_none(), "one request per coordinator");
        *active.borrow_mut() = Some((token, false));
    });
    Binding
}
impl Drop for Binding {
    fn drop(&mut self) {
        ACTIVE.with(|active| *active.borrow_mut() = None);
    }
}
pub fn checkpoint() -> std::io::Result<()> {
    ACTIVE.with(|active| {
        if active
            .borrow()
            .as_ref()
            .is_some_and(|(token, publishing)| !publishing && token.is_cancelled())
        {
            Err(std::io::Error::new(
                std::io::ErrorKind::Interrupted,
                "build superseded before publication",
            ))
        } else {
            Ok(())
        }
    })
}
/// Check cancellation once, then permanently make this request non-cancellable.
pub fn begin_publication() -> std::io::Result<()> {
    ACTIVE.with(|active| {
        if let Some((token, publishing)) = active.borrow_mut().as_mut() {
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
