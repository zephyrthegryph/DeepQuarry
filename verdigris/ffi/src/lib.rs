//! `vg-ffi`: BYOND binds. byondapi-sys is 32-bit only, so this crate builds for
//! the i686 targets only; everything it calls lives in host-buildable crates.
//!
//! Every bind is declared with `#[auxmacros::bind]`, which turns a panic into a
//! DM runtime instead of unwinding across the FFI boundary. The DM side is
//! generated: see `tools/build/lib/verdigris_bindings.ts`.

mod abi;
mod adjacency;
pub mod allocator;
mod bulk;
mod chem;
pub mod entity;
pub mod frame;
mod gas;
mod heat;
mod heat_net;
mod heat_regulator;
mod jobs;
mod layout;
mod lifecycle;
mod metrics;
mod pipes;
mod power;
pub mod propagate;
pub mod registry;
mod sched;
pub mod world;

#[cfg(test)]
mod boot_memory_tests;

// The boot-memory tests read the Rust heap peak, so the unit-test binary counts
// allocations the way the DLL does (verdigris/src/lib.rs).
#[cfg(test)]
#[global_allocator]
static TEST_ALLOCATOR: allocator::TrackingAllocator = allocator::TrackingAllocator;
