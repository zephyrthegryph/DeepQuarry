//! The APC: a port of DM's `/datum/apc_power_distributor` (channel state
//! machine, cell charging, load shedding). Rust runs it every power step,
//! so the DM APC never polls; DM hears only the state it shows (channels,
//! charging, status, alarm) and the cell charge. Cell discharge runs on
//! the shared [`vg_core::rate::RateStore`] (`rust_core.md` §15), the same
//! rate model SMES uses (see [`crate::smes`]) at a different rate.

use vg_core::rate::RateStore;

use crate::kind::Channel;

/// `POWERCHAN_*`.
pub mod chan {
    pub const OFF: u8 = 0;
    pub const OFF_AUTO: u8 = 1;
    pub const ON: u8 = 2;
    pub const ON_AUTO: u8 = 3;
}

/// `APC_EXTERNAL_POWER_*`.
pub mod status {
    pub const NOT_CONNECTED: u8 = 0;
    pub const NO_ENERGY: u8 = 1;
    pub const GOOD: u8 = 2;
}

/// `CELLRATE`: watts per tick to cell units.
pub const CELLRATE: f64 = 0.002;

/// A channel-shedding policy: as the cell's stored fraction falls, lower
/// priority channels turn off before higher priority ones. Config, not
/// hard-coded logic: `update_channels` only evaluates these thresholds
/// and per-tier channel requests (`chan::*`'s `on` argument to
/// [`autoset`]), so a different consumer+storage pairing can carry a
/// different policy without new code.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SheddingPolicy {
    /// Above this stored percent (or while charge trends up), every
    /// channel in `full_allow` is requested.
    pub full_above_pct: f64,
    /// Below `full_above_pct` but above this, while charge trends down,
    /// `partial_allow` is requested; at or below it, `min_allow` is.
    /// Between the two thresholds with charge flat, `neutral_allow` is
    /// requested.
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

/// What DM sets (settings and conditions); changes come as commands.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ApcConfig {
    /// Processes at all: the area requires power, the APC is not broken or
    /// in maintenance, and no failure countdown runs.
    pub active: bool,
    pub has_cell: bool,
    /// A power failure countdown (`energy_fail`) runs: the area is dark.
    pub failed: bool,
    /// `shorted || grid_check`: the no-cell path, and the area is dark.
    pub shorted_or_grid_check: bool,
    /// The main breaker.
    pub operating: bool,
    pub chargemode: bool,
    pub max_charge: f64,
    pub chargelevel: f64,
    pub policy: SheddingPolicy,
}

impl Default for ApcConfig {
    fn default() -> Self {
        Self {
            active: true,
            has_cell: true,
            failed: false,
            shorted_or_grid_check: false,
            operating: true,
            chargemode: true,
            max_charge: 0.0,
            chargelevel: 0.0005,
            policy: SheddingPolicy::default(),
        }
    }
}

/// Runtime state (what `apc_power_distributor` held), plus the cell charge.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ApcState {
    pub charge: f64,
    /// Channel settings, `chan::*`, indexed by [`Channel::idx`].
    pub channels: [u8; 3],
    /// 0 not charging, 1 charging, 2 full.
    pub charging: u8,
    pub chargecount: u32,
    pub longtermpower: i32,
    pub autoflag: u8,
    pub main_status: u8,
    /// The power alarm is raised.
    pub alarm: bool,
    /// Last step's usage (W): equipment, lighting, environment, charging, total.
    pub lastused: [f64; 5],
}

impl Default for ApcState {
    fn default() -> Self {
        Self {
            charge: 0.0,
            channels: [chan::ON_AUTO; 3],
            charging: 0,
            chargecount: 0,
            longtermpower: 10,
            autoflag: 0,
            main_status: status::NOT_CONNECTED,
            alarm: false,
            lastused: [0.0; 5],
        }
    }
}

/// An APC: its config, state, the area's loads and its terminal.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Apc {
    pub config: ApcConfig,
    pub state: ApcState,
    /// Static area demand per channel (W), counted while the channel is on.
    pub static_load: [f64; 3],
    /// One-off draws since the last step, per channel (always counted).
    pub oneoff: [f64; 3],
    /// Terminal node key, if connected.
    pub terminal: Option<u32>,
}

/// `autoset()`: `on` is 0 force off, 1 allow on, 2 auto-off.
#[must_use]
pub const fn autoset(cur: u8, on: u8) -> u8 {
    match cur {
        chan::OFF_AUTO if on == 1 => chan::ON_AUTO,
        chan::ON if on == 0 => chan::OFF,
        chan::ON_AUTO if on == 0 || on == 2 => chan::OFF_AUTO,
        _ => cur,
    }
}

/// The grid as one APC sees it during a step.
pub trait Grid {
    /// The region's supply this step (0: not connected).
    fn avail(&self) -> f64;
    /// `avail - load` so far.
    fn surplus(&self) -> f64;
    /// Draws up to `watts`; returns what was delivered.
    fn draw(&mut self, watts: f64) -> f64;
}

impl Apc {
    /// Whether channel `c` powers its area now (DM `apc.update()`).
    #[must_use]
    pub fn powered(&self, c: Channel) -> bool {
        self.config.operating
            && !self.config.shorted_or_grid_check
            && !self.config.failed
            && self.state.channels[c.idx()] >= chan::ON
    }

    /// Area channel bits (1 equipment, 2 lighting, 4 environment).
    #[must_use]
    pub fn channel_bits(&self) -> u8 {
        Channel::ALL
            .into_iter()
            .fold(0, |b, c| b | (u8::from(self.powered(c)) << c.idx()))
    }

    /// Area demand this step: one-offs always, static load while the
    /// channel is on.
    #[must_use]
    pub fn demand(&self) -> [f64; 3] {
        let s = &self.state;
        Channel::ALL.map(|c| {
            let i = c.idx();
            self.oneoff[i]
                + if s.channels[i] >= chan::ON {
                    self.static_load[i]
                } else {
                    0.0
                }
        })
    }

    /// One machinery tick (`apc_power_distributor.tick()`). Returns the
    /// cell's own contribution this tick, `(discharged, charged)` watts,
    /// for the caller's conservation books: `discharged` was drawn from
    /// the cell to cover the area (never touches `grid`, so it never
    /// reaches [`Grid::draw`]'s own delivered accounting) and `charged`
    /// went from the grid into the cell (it *does* reach `grid.draw`, so
    /// a caller that books `grid.draw`'s return as delivered must not
    /// double-count `charged` there -- only as storage input).
    pub fn tick(&mut self, grid: &mut dyn Grid) -> (f64, f64) {
        let used = self.demand();
        self.oneoff = [0.0; 3];
        if !self.config.active {
            return (0.0, 0.0);
        }
        let s = &mut self.state;
        s.lastused[..3].copy_from_slice(&used);
        s.lastused[3] = 0.0;
        s.lastused[4] = used.iter().sum();

        let excess = grid.surplus();
        s.main_status = if grid.avail() == 0.0 {
            status::NOT_CONNECTED
        } else if excess < 0.0 {
            status::NO_ENERGY
        } else {
            status::GOOD
        };
        if self.config.has_cell && !self.config.shorted_or_grid_check {
            self.with_cell(excess, grid)
        } else {
            s.charging = 0;
            s.chargecount = 0;
            for c in &mut s.channels {
                *c = autoset(*c, 0);
            }
            s.alarm = true;
            s.autoflag = 0;
            (0.0, 0.0)
        }
    }

    fn with_cell(&mut self, excess: f64, grid: &mut dyn Grid) -> (f64, f64) {
        let cfg = self.config;
        let s = &mut self.state;
        let total = s.lastused[4];
        let mut discharged = 0.0;
        if excess >= total {
            grid.draw(total);
        } else {
            let mut store = RateStore {
                charge: s.charge,
                capacity: cfg.max_charge,
                rate: CELLRATE,
            };
            let available = store.watts_available();
            discharged = store.discharge_out(total);
            s.charge = store.charge;
            if available + excess >= total {
                let drawn = grid.draw(excess);
                s.charge = cfg.max_charge.min(s.charge + CELLRATE * drawn);
                s.charging = 0;
            } else {
                s.charging = 0;
                s.chargecount = 0;
                for c in &mut s.channels {
                    *c = autoset(*c, 0);
                }
                s.autoflag = 0;
            }
        }

        self.update_channels();

        let s = &mut self.state;
        s.lastused[3] = 0.0;
        let mut charged = 0.0;
        if cfg.chargemode && s.charging == 1 && cfg.operating {
            if excess > 0.0 {
                let ch = (excess * CELLRATE).min(cfg.max_charge * cfg.chargelevel);
                let drawn = grid.draw(ch / CELLRATE);
                s.charge = (s.charge + drawn * CELLRATE).min(cfg.max_charge.max(s.charge));
                s.lastused[3] = drawn;
                s.lastused[4] += drawn;
                charged = drawn;
            } else {
                s.charging = 0;
                s.chargecount = 0;
            }
        }
        if s.charge >= cfg.max_charge {
            s.charge = cfg.max_charge;
            s.charging = 2;
        }
        if cfg.chargemode {
            if s.charging == 0 {
                if excess > cfg.max_charge * cfg.chargelevel {
                    s.chargecount += 1;
                } else {
                    s.chargecount = 0;
                }
                if s.chargecount >= 10 {
                    s.chargecount = 0;
                    s.charging = 1;
                }
            }
        } else {
            s.charging = 0;
            s.chargecount = 0;
        }
        (discharged, charged)
    }

    /// `_update_channels()`: shedding tiers from the cell level and trend.
    fn update_channels(&mut self) {
        let policy = self.config.policy;
        let store = RateStore {
            charge: self.state.charge,
            capacity: self.config.max_charge,
            rate: CELLRATE,
        };
        let s = &mut self.state;
        if s.charging != 0 && s.longtermpower < 10 {
            s.longtermpower += 1;
        } else if s.longtermpower > -10 {
            s.longtermpower -= 2;
        }
        let pct = 100.0 * store.fraction();
        let set = |s: &mut ApcState, allow: [u8; 3]| {
            for c in Channel::ALL {
                s.channels[c.idx()] = autoset(s.channels[c.idx()], allow[c.idx()]);
            }
        };
        if pct > policy.full_above_pct || s.longtermpower > 0 {
            if s.autoflag != 3 {
                set(s, policy.full_allow);
                s.autoflag = 3;
                s.alarm = false;
            }
        } else if pct <= policy.full_above_pct && pct > policy.partial_below_pct && s.longtermpower < 0 {
            if s.autoflag != 2 {
                set(s, policy.partial_allow);
                s.alarm = true;
                s.autoflag = 2;
            }
        } else if pct <= policy.partial_below_pct {
            if s.autoflag > 1 {
                set(s, policy.min_allow);
                s.alarm = true;
                s.autoflag = 1;
            }
        } else if s.autoflag != 0 {
            set(s, policy.neutral_allow);
            s.alarm = true;
            s.autoflag = 0;
        }
    }
}
