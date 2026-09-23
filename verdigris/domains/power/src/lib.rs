//! `vg-power`: the power domain (`rust_architecture.md` §6). Declarations
//! and laws only, host-buildable (`vg-core` only) -- no `Sim`, no key
//! tables, no display state (`rust_architecture.md` §2, §4.5).
//!
//! - [`components`]: `Cable`, `Apc`, `Smes`, `Consumer`, `Producer` --
//!   plain data.
//! - [`kind`]: [`kind::Cables`], the R7 network kind. All region state is
//!   in [`kind::PowerLedger`], the payload.
//! - [`geom`]: turf position packing and BYOND direction math, what the
//!   connection rule ([`kind::Cables`]'s `connects`/`reach`) builds on.
//! - [`laws`]: `apc_tick`, `smes_plan`/`smes_charge_in`/`smes_discharge_out`,
//!   `consumer_draw`, `brownout` -- pure functions, tested directly; the
//!   per-`Law`-trait scheduler wiring lands once Core B's component stores
//!   do (`rust_architecture.md` §4.3, §7).
//! - [`events`][mod@events]: [`events::PowerEvent`].

pub mod components;
pub mod events;
pub mod geom;
pub mod kind;
pub mod laws;

pub use components::{Apc, Cable, Channel, Consumer, Producer, Smes};
pub use events::PowerEvent;
pub use kind::{Cables, PowerLedger, PowerNode};
