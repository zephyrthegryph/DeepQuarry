//! `vg-core`: the domain-agnostic base every verdigris simulation builds on
//! (see `doc/rewrite/rust_core.md`).
//!
//! Architecture: `doc/rewrite/rust_architecture.md`. The driver is
//! [`world::World`]; domains declare components (`#[vg::component]`),
//! network and field kinds, laws ([`law::Law`] over [`query::Query`]s) and
//! events (`#[vg::events]`), and register them with a
//! [`world::WorldBuilder`].
//!
//! Rules for this crate:
//! - no `byondapi` (it builds and tests on the host, not only on i686);
//! - no global statics (tests run in parallel, and a `World` owns all state).

// Lets core's own tests and modules use the `#[vg::*]` macros, which expand
// to `::vg_core::` paths.
extern crate self as vg_core;

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
pub mod event;
pub mod field;
pub mod frame;
pub mod grid;
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
pub mod query;
pub mod rate;
pub mod reactor;
pub mod recorder;
pub mod registry;
pub mod replay;
pub mod rng;
pub mod sim;
pub mod slot;
pub mod store;
pub mod thermo;
pub mod timer;
pub mod units;
pub mod watch;
pub mod world;

pub use arena::Arena;
pub use entity::{ComponentRef, EntityError, EntityId, EntitySlots, EntityTable};
pub use slot::{Handle, RawHandle};

/// The `#[vg::component]`, `#[vg::query]` and `#[vg::events]` attributes
/// (`rust_bindings.md` §2), re-exported under this short name so a domain
/// crate can `use vg_core::vg;` and write `#[vg::component(...)]`.
pub mod vg {
    pub use auxmacros::{component, events, query};
}
