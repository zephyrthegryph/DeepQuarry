//! `vg-ffi`: BYOND binds. byondapi-sys is 32-bit only, so this crate builds for
//! the i686 targets only; everything it calls lives in host-buildable crates.
//!
//! Every bind is declared with `#[auxmacros::bind]`, which turns a panic into a
//! DM runtime instead of unwinding across the FFI boundary. The DM side is
//! generated: see `tools/build/lib/verdigris_bindings.ts`.

mod abi;
pub mod allocator;
mod jobs;
mod layout;
mod lifecycle;
mod metrics;
mod propagate;
mod reactor;
