//! `vg-ffi`: BYOND binds. byondapi-sys is 32-bit only, so this crate builds for
//! the i686 targets only; everything it calls lives in host-buildable crates.
//!
//! Every bind wears `#[auxmacros::panic_safe]`, which turns a panic into a DM
//! runtime instead of unwinding across the FFI boundary.

pub mod allocator;
mod layout;
mod lifecycle;
