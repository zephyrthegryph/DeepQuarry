//! Metadata + lifecycle FFI binds.
//!
//! Everything here is a byondapi bind, so the whole module is i686-only
//! (byondapi-sys is 32-bit). These are diagnostic/lifecycle helpers called at
//! runtime from the loaded `libverdigris.so`; there is nothing host-buildable to
//! keep outside the `cfg`.
#[cfg(target_arch = "x86")]
mod ffi {
    use byondapi::prelude::*;
    use const_format::formatcp as const_format;
    use eyre::Result;

    // bosion can fail to resolve git state in some environments (shallow clone, git
    // worktrees, missing git binary). Fall back to literal placeholders so the build
    // stays green — verdigris_version()/verdigris_features() are diagnostics, not
    // load-bearing.
    const GIT_HASH: &str = match option_env!("BOSION_GIT_COMMIT_SHORTHASH") {
        Some(h) => h,
        None => "unknown",
    };
    const CRATE_FEATURES: &str = match option_env!("BOSION_CRATE_FEATURES") {
        Some(f) => f,
        None => "",
    };
    const VERSION_STRING: &str = const_format!(
        "{name} v{version} ({git_hash})",
        name = env!("CARGO_PKG_NAME"),
        version = env!("CARGO_PKG_VERSION"),
        git_hash = GIT_HASH,
    );

    // `#[auxmacros::panic_safe]` (below each bind) wraps the body in catch_unwind
    // so a panic surfaces to DM as a runtime instead of unwinding across the FFI
    // boundary and aborting DreamDaemon. This is the same panic guard auxmos uses
    // on its own binds — one unified mechanism across the whole library.
    #[byondapi::bind("/proc/verdigris_version")]
    #[auxmacros::panic_safe]
    fn verdigris_version() -> Result<ByondValue> {
        Ok(ByondValue::new_str(VERSION_STRING)?)
    }

    #[byondapi::bind("/proc/verdigris_features")]
    #[auxmacros::panic_safe]
    fn verdigris_features() -> Result<ByondValue> {
        Ok(ByondValue::new_str(CRATE_FEATURES)?)
    }

    /// One-time global state init. DM should call this in `/world/New()` before
    /// any other verdigris call.
    #[byondapi::bind("/proc/verdigris_init")]
    #[auxmacros::panic_safe]
    fn verdigris_init() -> Result<ByondValue> {
        Ok(ByondValue::null())
    }

    /// Drop transient Rust-side state. Currently a no-op; once the gas-mixture
    /// arena needs an explicit drain for a clean `/world/New()`, it lands here.
    #[byondapi::bind("/proc/verdigris_cleanup")]
    #[auxmacros::panic_safe]
    fn verdigris_cleanup() -> Result<ByondValue> {
        // future: arena.drain(); reaction_registry.clear(); etc.
        Ok(ByondValue::null())
    }
}
