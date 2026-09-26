//! `vg-power`: the power domain (`rust_architecture.md` §6, §8.5).
//! Declarations and laws only -- no `PowerHost`, no side ledger, no
//! `byondapi` (`rust_architecture.md` §2, §4.5).
//!
//! - [`components`]: `Cable` (plain network node data), `Apc`, `Producer`,
//!   `Smes` (binds its own node for output), `SmesInputTerminal` (a SMES's
//!   possibly-several input terminals, each its own entity) --
//!   `#[vg::component]` declarations.
//! - [`kind`]: [`kind::Cables`], the R7 network kind. All region state is
//!   in [`kind::PowerLedger`], the payload.
//! - [`geom`]: turf position packing and BYOND direction math, what the
//!   connection rule ([`kind::Cables`]'s `connects`/`reach`) builds on.
//! - [`laws`]: the pure physics (`apc_tick`, `smes_plan`,
//!   `smes_charge_in`/`smes_discharge_out`, `storage_input_share`/
//!   `storage_output_share`, `brownout`), each proven by its own tests, and
//!   the `Law` types (`PowerReset`, `ProducerCredit`, `SmesOutputPlan`/
//!   `SmesInputPlan`, `ApcTick`, `PowerSettle`, `SmesOutputApply`/
//!   `SmesInputApply`) that run them over `vg_core`'s driver.
//! - [`events`][mod@events]: [`events::PowerEvent`].

pub mod components;
pub mod events;
pub mod geom;
pub mod kind;
pub mod laws;

pub use components::{Apc, Cable, Channel, Producer, Smes, SmesInputTerminal};
pub use events::PowerEvent;
pub use kind::{Cables, PowerLedger, PowerNode};
