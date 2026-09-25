//! Metadata + lifecycle binds: version, features, allocator diagnostics,
//! init and cleanup.
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
    name = "verdigris",
    version = env!("CARGO_PKG_VERSION"),
    git_hash = GIT_HASH,
);

// `#[auxmacros::bind]` wraps each body in catch_unwind so a panic surfaces to
// DM as a runtime instead of unwinding across the FFI boundary and aborting
// DreamDaemon.
#[auxmacros::bind("/proc/verdigris_version")]
fn verdigris_version() -> Result<ByondValue> {
    Ok(ByondValue::new_str(VERSION_STRING)?)
}

#[auxmacros::bind("/proc/verdigris_features")]
fn verdigris_features() -> Result<ByondValue> {
    Ok(ByondValue::new_str(CRATE_FEATURES)?)
}

#[auxmacros::bind("/proc/verdigris_allocator_diagnostics")]
fn verdigris_allocator_diagnostics() -> Result<ByondValue> {
    let (current, peak) = crate::allocator::diagnostics();
    let values = [current, peak]
        .into_iter()
        .map(|value| ByondValue::from(value as f32))
        .collect::<Vec<_>>();
    let list = ByondValue::new_list()?;
    list.write_list(&values)?;
    Ok(list)
}

/// One-time global state init and the version handshake. DM calls this in
/// `/world/New()` before any other verdigris call, passing its generated
/// `VERDIGRIS_ABI`. Returns the library's ABI string; DM stops the boot when it
/// differs (a DLL and a DM build from different bind sets).
#[auxmacros::bind("/proc/verdigris_init")]
fn verdigris_init(dm_abi: ByondValue) -> Result<ByondValue> {
    let dm_abi = dm_abi.get_string().unwrap_or_default();
    if dm_abi != crate::abi::ABI {
        eyre::bail!(
            "verdigris ABI mismatch: library {} vs DM {:?}; rebuild the DLL and the DM from the same tree",
            crate::abi::ABI,
            dm_abi
        );
    }
    crate::entity::reset_all()?;
    Ok(ByondValue::new_str(crate::abi::ABI)?)
}

/// Drop transient Rust-side state for a clean `/world/New()`
/// (`rust_bindings.md` §4: "world start ... resets every Rust store"). Every
/// registered entity domain (§1) drops its components and the entity table
/// itself is rebuilt, so no `vg_entity` handle survives into a new round.
#[auxmacros::bind("/proc/verdigris_cleanup")]
fn verdigris_cleanup() -> Result<ByondValue> {
    crate::entity::reset_all()?;
    Ok(ByondValue::null())
}
