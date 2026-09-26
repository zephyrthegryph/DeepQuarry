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

use vg_core::query::LinksTo;
use vg_core::vg;

/// A power channel: equipment, lighting, environment. Per-channel values
/// are fields keyed by this enum, never a magic index
/// (`rust_bindings.md` §2).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Channel {
    Equip,
    Light,
    Environ,
}

impl Channel {
    pub const ALL: [Channel; 3] = [Channel::Equip, Channel::Light, Channel::Environ];

    #[must_use]
    pub const fn idx(self) -> usize {
        match self {
            Channel::Equip => 0,
            Channel::Light => 1,
            Channel::Environ => 2,
        }
    }
}

/// `POWERCHAN_*`: a channel's setting, packed as `u8` in a component field.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum ChannelSetting {
    Off,
    OffAuto,
    On,
    OnAuto,
}

impl ChannelSetting {
    /// `autoset()`: `on` is 0 force off, 1 allow on, 2 auto-off.
    #[must_use]
    pub const fn autoset(self, on: u8) -> Self {
        match self {
            Self::OffAuto if on == 1 => Self::OnAuto,
            Self::On if on == 0 => Self::Off,
            Self::OnAuto if on == 0 || on == 2 => Self::OffAuto,
            other => other,
        }
    }

    #[must_use]
    pub const fn powered(self) -> bool {
        matches!(self, Self::On | Self::OnAuto)
    }

    /// The packed `u8` a component field stores.
    #[must_use]
    pub const fn as_u8(self) -> u8 {
        match self {
            Self::Off => 0,
            Self::OffAuto => 1,
            Self::On => 2,
            Self::OnAuto => 3,
        }
    }

    /// Unpacks a component field's `u8` (an out-of-range byte is `Off`, not
    /// a panic: a corrupt save must not crash the tick).
    #[must_use]
    pub const fn from_u8(v: u8) -> Self {
        match v {
            1 => Self::OffAuto,
            2 => Self::On,
            3 => Self::OnAuto,
            _ => Self::Off,
        }
    }
}

/// A channel-shedding policy: as the cell's stored fraction falls, lower
/// priority channels turn off before higher priority ones. Config, not
/// hard-coded logic (`rust_bindings.md` R10); [`Apc`]'s `policy_*` fields
/// are this, flattened to the numeric fields the component macro accepts.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SheddingPolicy {
    pub full_above_pct: f64,
    pub partial_below_pct: f64,
    pub full_allow: [u8; 3],
    pub partial_allow: [u8; 3],
    pub min_allow: [u8; 3],
    pub neutral_allow: [u8; 3],
}

/// A cable piece: direction geometry only, bound once at construction and
/// never live-edited (`crate::kind::Cables::connects`) --
/// [`vg_core::network::NetworkKind::Node`] data, not a component.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Cable {
    pub d1: u8,
    pub d2: u8,
    /// z above/below this cable's z (0 = none); read only for UP/DOWN.
    pub up: u32,
    pub down: u32,
    /// Ender cables with the same non-zero id are joined wherever they are.
    pub link: u32,
}

/// `CELLRATE`: charge units per watt-tick, an APC cell.
pub const CELLRATE: f64 = 0.002;
/// `SMESRATE`: charge units per watt-tick, a SMES.
pub const SMESRATE: f64 = 0.033_33;

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

impl Apc {
    #[must_use]
    pub fn cell(&self) -> vg_core::rate::RateStore {
        vg_core::rate::RateStore {
            charge: self.charge,
            capacity: self.capacity,
            rate: self.rate,
        }
    }

    pub fn set_cell(&mut self, cell: vg_core::rate::RateStore) {
        self.charge = cell.charge;
        self.capacity = cell.capacity;
        self.rate = cell.rate;
    }

    #[must_use]
    pub fn channel(&self, c: Channel) -> ChannelSetting {
        ChannelSetting::from_u8(self.channels[c.idx()])
    }

    pub fn set_channel(&mut self, c: Channel, v: ChannelSetting) {
        self.channels[c.idx()] = v.as_u8();
    }

    #[must_use]
    pub fn policy(&self) -> SheddingPolicy {
        SheddingPolicy {
            full_above_pct: self.policy_full_above_pct,
            partial_below_pct: self.policy_partial_below_pct,
            full_allow: self.policy_full_allow,
            partial_allow: self.policy_partial_allow,
            min_allow: self.policy_min_allow,
            neutral_allow: self.policy_neutral_allow,
        }
    }
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
}

impl Smes {
    #[must_use]
    pub fn cell(&self) -> vg_core::rate::RateStore {
        vg_core::rate::RateStore {
            charge: self.charge,
            capacity: self.capacity,
            rate: self.rate,
        }
    }

    pub fn set_cell(&mut self, cell: vg_core::rate::RateStore) {
        self.charge = cell.charge;
        self.capacity = cell.capacity;
        self.rate = cell.rate;
    }
}

/// A SMES's input terminal: its own [`crate::kind::Cables`] node, on its
/// own region, naming the unit entity that holds the [`Smes`] row. A SMES
/// may have several (DM's `terminals` list), each sharing pro-rata in
/// whatever region it is on; the output side has no such fan-out (one SMES,
/// one output node, at the unit's own tile) and so needs no terminal
/// component of its own -- `Smes` binds its own [`crate::kind::Cables`]
/// node directly, exactly as `Apc` does.
#[vg::component(domain = power, kind = 5, dm = "/obj/machinery/power/terminal/smes_input", owner = main)]
pub struct SmesInputTerminal {
    #[vg(config, default = 0)]
    pub unit: u32,
}

impl LinksTo for SmesInputTerminal {
    fn linked_index(&self) -> Option<u32> {
        Some(self.unit)
    }
}
