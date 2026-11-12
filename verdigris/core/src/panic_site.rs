//! Where the last panic on this thread happened. A caught panic's payload is only its message; the panic hook
//! installed here records `file:line:col` first, so a catcher (the frame runner in [`crate::sim`], the bind guard in
//! `auxcallback`) can report where it came from. The slot is process-wide, not per thread: a panic in a rayon task is
//! re-raised on the thread that opened the scope, not the one that panicked. Two panics racing can swap locations; it
//! is a diagnostic.

use std::sync::{Mutex, Once, PoisonError};

static LAST: Mutex<Option<String>> = Mutex::new(None);

thread_local! {
    /// This thread's own last panic, preferred over the shared slot when the catcher is the thread that panicked.
    static LOCAL: std::cell::RefCell<Option<String>> = const { std::cell::RefCell::new(None) };
}

static INSTALL: Once = Once::new();

/// Installs the recording hook once per process, chained in front of whatever hook was there (the default one
/// still prints the panic to stderr).
pub fn install() {
    INSTALL.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            if let Some(loc) = info.location() {
                let site = format!("{}:{}:{}", loc.file(), loc.line(), loc.column());
                let _ = LOCAL.try_with(|l| l.replace(Some(site.clone())));
                *LAST.lock().unwrap_or_else(PoisonError::into_inner) = Some(site);
            }
            previous(info);
        }));
    });
}

/// The location of the last panic since the previous call, if the hook saw one.
#[must_use]
pub fn take() -> Option<String> {
    let mut shared = LAST.lock().unwrap_or_else(PoisonError::into_inner);
    match LOCAL.try_with(|l| l.borrow_mut().take()).ok().flatten() {
        Some(own) => {
            if shared.as_deref() == Some(own.as_str()) {
                *shared = None;
            }
            Some(own)
        }
        None => shared.take(),
    }
}

/// `msg` with the location of the panic that produced it, when known.
#[must_use]
pub fn describe(msg: &str) -> String {
    match take() {
        Some(site) => format!("{msg} (at {site})"),
        None => msg.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_caught_panic_reports_its_location() {
        install();
        let _ = take();
        let r = std::panic::catch_unwind(|| panic!("boom"));
        assert!(r.is_err());
        let d = describe("boom");
        assert!(d.contains("panic_site.rs:") && d.contains("(at "), "{d}");
    }
}
