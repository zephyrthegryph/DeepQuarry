//! Power's events (`rust_architecture.md` §4.8, §6): typed, through
//! `#[vg::events]`. They are about a region, not a component, so they are
//! domain events: the DM generator dispatches them to global handlers
//! (`vg_on_power_brownout(...)`).

use vg_core::vg;

/// A region's power events.
#[vg::events(domain = power)]
pub enum PowerEvent {
    /// A region lost supply or was overdrawn.
    Brownout,
    /// A previously browned-out region recovered.
    Restored,
    /// An APC's channel settings changed (the shedding ladder, or a manual
    /// override).
    ApcChannelChanged,
}
