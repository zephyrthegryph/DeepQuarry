//! Power's component declarations (`rust_architecture.md` §6, §8.5):
//! `#[vg::component]` structs -- plain numeric fields only, so the macro
//! generates the whole FFI/watch surface. [`crate::laws`] is the only code
//! that reads or writes them.
//!
//! A cable piece stays plain [`vg_core::network::NetworkKind::Node`] data
//! (`crate::kind::PowerNode::Cable`), not a component: DM never watches or
//! generically reads/writes a cable's shape, it is bound once and only the
//! connection rule ([`crate::kind::Cables`]) reads it.
//!
//! A SMES's storage state and its output node share one entity (as `Apc`
//! binds its own node): DM has exactly one output connection per SMES, at
//! the unit's own tile. Its input side can fan out to several physical
//! terminal objects (`rust_architecture.md` step 3: sharing is per
//! terminal, not per unit) -- each [`SmesInputTerminal`] is its own entity,
//! on its own region, naming the unit entity with [`vg_core::query::LinksTo`];
//! [`crate::laws`] reaches the shared `Smes` row through
//! [`vg_core::query::Foreign`].

use vg_core::vg;

/// `POWERCHAN_*`: a channel's setting, as an APC's `channels` field holds
/// it (channel 0 equipment, 1 lighting, 2 environment). An out-of-range
/// byte reads as off: a corrupt save must not crash the tick.
pub mod setting {
    pub const OFF: u8 = 0;
    pub const OFF_AUTO: u8 = 1;
    pub const ON: u8 = 2;
    pub const ON_AUTO: u8 = 3;

    /// `autoset()`: `on` is 0 force off, 1 allow on, 2 auto-off.
    pub const fn autoset(v: u8, on: u8) -> u8 {
        match v {
            OFF_AUTO if on == 1 => ON_AUTO,
            ON if on == 0 => OFF,
            ON_AUTO if on == 0 || on == 2 => OFF_AUTO,
            other => other,
        }
    }

    pub const fn powered(v: u8) -> bool {
        matches!(v, ON | ON_AUTO)
    }
}

/// A cable piece: direction geometry only, bound once at construction and
/// never live-edited ([`crate::kind::Cables::connects`]) --
/// [`vg_core::network::NetworkKind::Node`] data, not a component.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Cable {
    pub d1: u8,
    pub d2: u8,
    /// Ender cables with the same non-zero id are joined wherever they are.
    pub link: u32,
    /// The cells this cable reaches, each with the direction a cable there
    /// must have to connect back (computed where the cell is placed on the
    /// map: `vg-ffi`).
    pub reach: Vec<(vg_core::grid::CellId, u8)>,
}

/// A registered generator or one-step pulse source, bound to a
/// [`crate::kind::Cables`] node. `pulse` is a one-shot addition to its
/// region's supply, consumed and reset to zero by
/// [`crate::laws::ProducerCredit`] the tick after DM sets it.
#[vg::component(domain = power, kind = 2, dm = "/obj/machinery/power", owner = main)]
pub struct Producer {
    #[vg(config, unit = "W", range = 0.0..=1000000.0, default = 0.0, on_invalid = clamp)]
    pub supply: f64,
    #[vg(config, unit = "W", range = 0.0..=10000000.0, default = 0.0, on_invalid = clamp)]
    pub pulse: f64,
}

/// An APC: consumer + storage + channel-priority policy config
/// (`rust_bindings.md` R10). `charge`/`capacity`/`rate` are
/// `vg_core::rate::RateStore`'s fields, flattened; `channels` and the
/// `policy_*_allow` arrays are [`ChannelSetting`], packed. Bound to its own
/// [`crate::kind::Cables`] node (an APC's area terminal is itself).
#[vg::component(domain = power, kind = 3, dm = "/obj/machinery/power/apc", owner = main)]
pub struct Apc {
    #[vg(config, default = true)]
    pub active: bool,
    #[vg(config, default = true)]
    pub has_cell: bool,
    #[vg(config, default = false)]
    pub failed: bool,
    #[vg(config, default = false)]
    pub shorted_or_grid_check: bool,
    #[vg(config, default = true)]
    pub operating: bool,
    #[vg(config, default = true)]
    pub chargemode: bool,
    #[vg(config, range = 0.0..=1.0, default = 0.0005, on_invalid = clamp)]
    pub chargelevel: f64,
    #[vg(config, unit = "J", range = 0.0..=1000000000.0, default = 0.0, on_invalid = clamp)]
    pub capacity: f64,
    #[vg(config, default = 0.002)]
    pub rate: f64,
    #[vg(state, unit = "J", conserve = "power_apc_charge")]
    pub charge: f64,
    // DM-writable (a manual channel override from the APC UI); the law
    // still writes it (the autoset ladder), same as it may write any
    // `config` field it owns -- `config`/`state` only gate DM's own
    // generic setter.
    #[vg(config, default = [3, 3, 3])]
    pub channels: [u8; 3],
    #[vg(state, default = 0)]
    pub charging: u8,
    #[vg(state, default = 0)]
    pub chargecount: u32,
    #[vg(state, default = 10)]
    pub longtermpower: i32,
    #[vg(state, default = 0)]
    pub autoflag: u8,
    #[vg(state, default = false)]
    pub alarm: bool,
    #[vg(config, unit = "W", range = 0.0..=1000000.0, default = [0.0, 0.0, 0.0], on_invalid = clamp)]
    pub static_load: [f64; 3],
    #[vg(config, unit = "W", range = 0.0..=1000000.0, default = [0.0, 0.0, 0.0], on_invalid = clamp)]
    pub oneoff: [f64; 3],
    #[vg(config, range = 0.0..=100.0, default = 30.0, on_invalid = clamp)]
    pub policy_full_above_pct: f64,
    #[vg(config, range = 0.0..=100.0, default = 15.0, on_invalid = clamp)]
    pub policy_partial_below_pct: f64,
    #[vg(config, default = [1, 1, 1])]
    pub policy_full_allow: [u8; 3],
    #[vg(config, default = [2, 1, 1])]
    pub policy_partial_allow: [u8; 3],
    #[vg(config, default = [2, 2, 1])]
    pub policy_min_allow: [u8; 3],
    #[vg(config, default = [0, 0, 0])]
    pub policy_neutral_allow: [u8; 3],
}

/// A SMES's storage, bound to the unit entity (not itself a network node --
/// its terminals are). `charge`/`capacity`/`rate` are
/// `vg_core::rate::RateStore`'s fields, flattened.
#[vg::component(domain = power, kind = 4, dm = "/obj/machinery/power/smes", owner = main)]
pub struct Smes {
    #[vg(config, default = false)]
    pub input_enabled: bool,
    #[vg(config, default = true)]
    pub output_enabled: bool,
    #[vg(config, unit = "W", range = 0.0..=10000000.0, default = 50000.0, on_invalid = clamp)]
    pub input_level: f64,
    #[vg(config, unit = "W", range = 0.0..=10000000.0, default = 50000.0, on_invalid = clamp)]
    pub output_level: f64,
    #[vg(config, unit = "J", range = 0.0..=10000000000.0, default = 0.0, on_invalid = clamp)]
    pub capacity: f64,
    #[vg(config, default = 0.03333)]
    pub rate: f64,
    #[vg(state, unit = "J", conserve = "power_smes_charge")]
    pub charge: f64,
    // What flowed this step (watts), for the unit's display and window: zeroed
    // by `SmesFlowReset` before the apply laws, written by `SmesOutputApply`
    // (delivered to load) and summed by `SmesInputApply` over its terminals
    // (absorbed, and the leftover supply each terminal's region offered).
    #[vg(state, unit = "W", default = 0.0)]
    pub output_used: f64,
    #[vg(state, unit = "W", default = 0.0)]
    pub input_used: f64,
    #[vg(state, unit = "W", default = 0.0)]
    pub input_available: f64,
}

/// A SMES's input terminal: its own [`crate::kind::Cables`] node, on its
/// own region, naming the unit entity that holds the [`Smes`] row. A SMES
/// may have several (DM's `terminals` list), each sharing pro-rata in
/// whatever region it is on; the output side has no such fan-out (one SMES,
/// one output node, at the unit's own tile) and so needs no terminal
/// component of its own -- `Smes` binds its own [`crate::kind::Cables`]
/// node directly, exactly as `Apc` does.
#[vg::component(domain = power, kind = 5, dm = "/obj/machinery/power/terminal/smes_input", owner = main, links = [unit])]
pub struct SmesInputTerminal {
    #[vg(config, default = 0)]
    pub unit: u32,
}

vg_core::rate_store!(Apc, Smes);
