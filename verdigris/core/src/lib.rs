//! `vg-core`: the domain-agnostic base every verdigris simulation builds on
//! (see `doc/rewrite/rust_core.md`).
//!
//! Rules for this crate:
//! - no `byondapi` (it builds and tests on the host, not only on i686);
//! - no global statics (tests run in parallel, and a `World` owns all state).

pub mod activity;
pub mod alloc;
pub mod arena;
pub mod bitset;
pub mod channel;
pub mod command;
pub mod component;
pub mod conservation;
pub mod cow;
pub mod entity;
pub mod field;
pub mod frame;
pub mod grid;
pub mod handle;
pub mod intern;
pub mod jobs;
pub mod law;
pub mod mailbox;
pub mod metrics;
pub mod network;
pub mod outbox;
pub mod overlay;
pub mod owner;
pub mod propagate;
pub mod rate;
pub mod reactor;
pub mod recorder;
pub mod replay;
pub mod revision;
pub mod rng;
pub mod sim;
pub mod thermo;
pub mod timer;
pub mod units;
pub mod watch;

pub use arena::Arena;
pub use entity::{CellAllocator, ComponentRef, EntityError, EntitySlots, EntityTable};
pub use handle::{Handle, RawHandle};

/// The `#[vg::component]`, `#[vg::query]` and `#[vg::events]` attributes
/// (`rust_bindings.md` §2), re-exported under this short name so a domain
/// crate can `use vg_core::vg;` and write `#[vg::component(...)]`.
pub mod vg {
    pub use auxmacros::{component, events, query};
}
