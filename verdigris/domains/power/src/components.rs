//! Power's component declarations (`rust_architecture.md` §6): plain data,
//! no behaviour. The laws in [`crate::laws`] are the only code that reads
//! or writes them.

use vg_core::rate::RateStore;
use vg_core::units::Watts;

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

/// `POWERCHAN_*`: a channel's setting.
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
}

/// A channel-shedding policy: as the cell's stored fraction falls, lower
/// priority channels turn off before higher priority ones. Config, not
/// hard-coded logic (`rust_bindings.md` R10: "APC = consumer + storage +
/// channel-priority policy config").
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SheddingPolicy {
    pub full_above_pct: f64,
    pub partial_below_pct: f64,
    pub full_allow: [u8; 3],
    pub partial_allow: [u8; 3],
    pub min_allow: [u8; 3],
    pub neutral_allow: [u8; 3],
}

impl Default for SheddingPolicy {
    fn default() -> Self {
        Self {
            full_above_pct: 30.0,
            partial_below_pct: 15.0,
            full_allow: [1, 1, 1],
            partial_allow: [2, 1, 1],
            min_allow: [2, 2, 1],
            neutral_allow: [0, 0, 0],
        }
    }
}

/// A cable piece: direction geometry only (`rust_bindings.md`'s "config/
/// input/state" taxonomy doesn't apply -- a cable's shape is set once at
/// bind and never live-edited; see [`crate::laws::connects`]).
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

/// A registered generator or one-step pulse source.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Producer {
    pub supply: Watts,
}

/// A static or terminal-fed draw (an APC's area, a machine's own load).
/// `priority`: lower drawn first by [`crate::laws::consumer_draw`]'s
/// caller when a region can't cover every consumer -- life support before
/// a fabricator.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Consumer {
    pub demand: [Watts; 3],
    pub priority: u8,
}

/// An APC: consumer + storage + channel-priority policy config
/// (`rust_bindings.md` R10).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Apc {
    pub active: bool,
    pub has_cell: bool,
    pub failed: bool,
    pub shorted_or_grid_check: bool,
    pub operating: bool,
    pub chargemode: bool,
    pub chargelevel: f64,
    pub policy: SheddingPolicy,
    /// Cell charge (`rate` = `CELLRATE`, watts per tick to charge units).
    pub cell: RateStore,
    pub channels: [ChannelSetting; 3],
    pub charging: u8,
    pub chargecount: u32,
    pub longtermpower: i32,
    pub autoflag: u8,
    pub alarm: bool,
    pub static_load: [Watts; 3],
    pub oneoff: [Watts; 3],
}

impl Default for Apc {
    fn default() -> Self {
        Self {
            active: true,
            has_cell: true,
            failed: false,
            shorted_or_grid_check: false,
            operating: true,
            chargemode: true,
            chargelevel: 0.0005,
            policy: SheddingPolicy::default(),
            cell: RateStore::new(CELLRATE),
            channels: [ChannelSetting::OnAuto; 3],
            charging: 0,
            chargecount: 0,
            longtermpower: 10,
            autoflag: 0,
            alarm: false,
            static_load: [Watts::ZERO; 3],
            oneoff: [Watts::ZERO; 3],
        }
    }
}

/// `CELLRATE`: charge units per watt-tick, an APC cell.
pub const CELLRATE: f64 = 0.002;
/// `SMESRATE`: charge units per watt-tick, a SMES.
pub const SMESRATE: f64 = 0.033_33;

/// A SMES: storage with input/output rate config, no channels.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Smes {
    pub input_enabled: bool,
    pub output_enabled: bool,
    pub input_level: Watts,
    pub output_level: Watts,
    pub charge: RateStore,
}

impl Default for Smes {
    fn default() -> Self {
        Self {
            input_enabled: false,
            output_enabled: true,
            input_level: Watts(50_000.0),
            output_level: Watts(50_000.0),
            charge: RateStore::new(SMESRATE),
        }
    }
}
