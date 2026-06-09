//! Panic isolation for FFI entry points.
//!
//! A Rust panic that unwinds across the BYOND FFI boundary is undefined
//! behavior and will SIGSEGV DreamDaemon with no DM-side stack trace. Every
//! `#[byond_fn]` body must therefore be wrapped in `panic_safe!` so that
//! panics surface as a runtime error on the DM side instead of taking the
//! whole server down.

use std::panic;
use std::sync::OnceLock;

static HOOK_INSTALLED: OnceLock<()> = OnceLock::new();

pub fn ensure_panic_hook() {
    HOOK_INSTALLED.get_or_init(|| {
        panic::set_hook(Box::new(|info| {
            eprintln!("[verdigris panic] {info}");
        }));
    });
}

#[derive(Debug)]
pub struct VerdigrisPanic(pub String);

impl std::fmt::Display for VerdigrisPanic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "verdigris panic: {}", self.0)
    }
}

impl std::error::Error for VerdigrisPanic {}

pub fn payload_to_message(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(s) = payload.downcast_ref::<&'static str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "verdigris panic with unknown payload".to_string()
    }
}

/// Wrap a fallible body that returns `ByondResult<T>` so panics convert into
/// `Err(ByondError)` instead of unwinding through BYOND's FFI shim.
#[macro_export]
macro_rules! panic_safe {
    ($body:expr) => {{
        $crate::panic::ensure_panic_hook();
        match ::std::panic::catch_unwind(::std::panic::AssertUnwindSafe(move || $body)) {
            Ok(value) => value,
            Err(payload) => {
                let msg = $crate::panic::payload_to_message(payload.as_ref());
                Err(::meowtonin::ByondError::boxed(
                    $crate::panic::VerdigrisPanic(msg),
                ))
            }
        }
    }};
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::panic::catch_unwind;

    #[test]
    fn payload_str_extracted() {
        let payload = catch_unwind(|| panic!("boom")).expect_err("should panic");
        let msg = payload_to_message(payload.as_ref());
        assert!(msg.contains("boom"), "got: {msg}");
    }

    #[test]
    fn payload_string_extracted() {
        let payload = catch_unwind(|| panic!("dynamic {}", 42)).expect_err("should panic");
        let msg = payload_to_message(payload.as_ref());
        assert!(msg.contains("dynamic 42"), "got: {msg}");
    }

    #[test]
    fn payload_unknown_kind_falls_back() {
        let payload = catch_unwind(|| {
            std::panic::panic_any(0u32);
        })
        .expect_err("should panic");
        let msg = payload_to_message(payload.as_ref());
        assert!(msg.contains("unknown payload"), "got: {msg}");
    }

    #[test]
    fn ensure_panic_hook_is_idempotent() {
        ensure_panic_hook();
        ensure_panic_hook();
        ensure_panic_hook();
    }
}
