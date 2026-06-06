//! Metadata + lifecycle functions.
use const_format::formatcp as const_format;

// bosion can fail to resolve git state in some environments (shallow clone, git
// worktrees, missing git binary). Fall back to literal placeholders so the build
// stays green — `verdigris_version()` and `verdigris_features()` are diagnostic
// helpers, not load-bearing.
const GIT_HASH: &str = match option_env!("BOSION_GIT_COMMIT_SHORTHASH") {
    Some(h) => h,
    None => "unknown",
};
const CRATE_FEATURES: &str = match option_env!("BOSION_CRATE_FEATURES") {
    Some(f) => f,
    None => "",
};

#[byond_fn]
pub fn verdigris_version() -> &'static str {
    const_format!(
        "{name} v{version} ({git_hash})",
        name = env!("CARGO_PKG_NAME"),
        version = env!("CARGO_PKG_VERSION"),
        git_hash = GIT_HASH,
    )
}

#[byond_fn]
pub fn verdigris_features() -> &'static str {
    CRATE_FEATURES
}

/// Install the FFI panic hook and any other one-time global state.
/// DM should call this in `/world/New()` before any other verdigris call.
#[byond_fn]
pub fn verdigris_init() {
    crate::panic::ensure_panic_hook();
}

/// Drop transient Rust-side state. Currently a no-op; once the gas-mixture
/// arena exists this becomes the drain hook for a clean `/world/New()`.
#[byond_fn]
pub fn cleanup() {
    let _ = std::panic::catch_unwind(|| {
        // future: arena.drain(); reaction_registry.clear(); etc.
    });
}
