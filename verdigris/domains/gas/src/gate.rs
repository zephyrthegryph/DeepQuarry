//! The gas registry: every gas's data and every reaction's requirements, as
//! DM registered them at boot (and on the rare `update_reactions`). One
//! immutable table published as an `Arc` behind an uncontended read lock:
//! the turf field reads it on frame threads (the "can react" check and the
//! visual signature), mixtures on the main thread.

use std::sync::{Arc, RwLock};

use crate::cell::{heat_capacity, temperature_of, GasCell, N};
use crate::gas::constants::{FACTOR_GAS_VISIBLE_MAX, GAS_MIN_MOLES, MOLES_GAS_VISIBLE_STEP};

/// One reaction's requirements (a `/datum/gas_reaction`'s
/// `min_requirements`), with the id DM's reaction datum is cached under.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Requirement {
    pub id: u64,
    pub min_temp: Option<f32>,
    pub max_temp: Option<f32>,
    pub min_energy: Option<f32>,
    pub min_fire: Option<f32>,
    pub gases: Vec<(usize, f32)>,
}

/// A gas's fire behaviour.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub enum Fire {
    #[default]
    None,
    Oxidizer {
        temperature: f32,
        power: f32,
    },
    Fuel {
        temperature: f32,
        burn_rate: f32,
    },
}

/// One gas's registry entry (a `/datum/gas`).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct GasType {
    /// The gas-string id (`"o2"`).
    pub id: Box<str>,
    /// `flags` (bitflags DM filters by).
    pub flags: u32,
    /// kg/mol (`0.0`: none on file).
    pub molar_mass: f32,
    /// Moles above which the gas is visible.
    pub visible: Option<f32>,
    pub fire: Fire,
}

/// The registry.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Gate {
    /// By gas index (empty until DM registers the roster).
    pub gases: Vec<GasType>,
    /// Highest priority first.
    pub reactions: Vec<Requirement>,
}

impl Gate {
    fn fire(&self, i: usize) -> Fire {
        self.gases.get(i).map_or(Fire::None, |g| g.fire)
    }

    /// Oxidation power and fuel amount at `temperature`.
    #[must_use]
    pub fn burnability(&self, moles: &[f32; N], temperature: f32) -> (f32, f32) {
        let mut acc = (0.0, 0.0);
        for (i, &amt) in moles.iter().enumerate().filter(|(_, &a)| a > GAS_MIN_MOLES) {
            match self.fire(i) {
                Fire::Oxidizer { temperature: t, power } if temperature > t => {
                    acc.0 += amt * (1.0 - t / temperature).max(0.0) * power;
                }
                Fire::Fuel { temperature: t, burn_rate } if temperature > t => {
                    acc.1 += amt * (1.0 - t / temperature).max(0.0) / burn_rate;
                }
                _ => {}
            }
        }
        acc
    }

    fn holds(&self, r: &Requirement, moles: &[f32; N], energy: f32, temperature: f32) -> bool {
        r.min_temp.is_none_or(|t| temperature >= t)
            && r.max_temp.is_none_or(|t| temperature <= t)
            && r.gases.iter().all(|&(g, v)| moles.get(g).is_some_and(|&m| m >= v))
            && r.min_energy.is_none_or(|e| energy >= e)
            && r.min_fire.is_none_or(|f| {
                let (oxi, fuel) = self.burnability(moles, temperature);
                oxi.min(fuel) >= f
            })
    }

    /// The index (in [`Gate::reactions`]) of the highest-priority reaction
    /// whose requirements hold, if any: the field's `GasEvent::
    /// CellReactionReady` carries it, and DM resolves it against the same
    /// order it registered its reactions in.
    #[must_use]
    pub fn ready(&self, moles: &[f32; N], energy: f32, temperature: f32) -> Option<usize> {
        self.reactions.iter().position(|r| self.holds(r, moles, energy, temperature))
    }

    /// The ids of every reaction whose requirements hold, highest priority
    /// first.
    #[must_use]
    pub fn all_ready(&self, moles: &[f32; N], energy: f32, temperature: f32) -> Vec<u64> {
        self.reactions.iter().filter(|r| self.holds(r, moles, energy, temperature)).map(|r| r.id).collect()
    }

    /// Visible-gas signature of a mole vector (0: nothing visible).
    #[must_use]
    pub fn vis_signature(&self, moles: &[f32; N]) -> u16 {
        let mut h: u32 = 0;
        for (i, &amt) in moles.iter().enumerate() {
            if let Some(threshold) = self.gases.get(i).and_then(|g| g.visible) {
                if amt > threshold {
                    let step = (amt / MOLES_GAS_VISIBLE_STEP).ceil().clamp(1.0, FACTOR_GAS_VISIBLE_MAX) as u32;
                    h = h.wrapping_mul(31).wrapping_add((i as u32 + 1) * 64 + step);
                }
            }
        }
        // Keep 0 for "nothing visible".
        if h == 0 {
            0
        } else {
            ((h ^ (h >> 16)) as u16).max(1)
        }
    }
}

static GATE: RwLock<Option<Arc<Gate>>> = RwLock::new(None);

/// Publishes the registry.
pub fn install(gate: Gate) {
    *GATE.write().unwrap_or_else(std::sync::PoisonError::into_inner) = Some(Arc::new(gate));
}

/// The registry, if one is installed.
#[must_use]
pub fn current() -> Option<Arc<Gate>> {
    GATE.read().unwrap_or_else(std::sync::PoisonError::into_inner).clone()
}

/// Runs `f` on the registry (an empty one before DM registers it).
pub fn with<T>(f: impl FnOnce(&Gate) -> T) -> T {
    match current() {
        Some(g) => f(&g),
        None => f(&Gate::default()),
    }
}

/// Replaces the reaction table, keeping the gases.
pub fn install_reactions(reactions: Vec<Requirement>) {
    let mut g = current().map(|g| (*g).clone()).unwrap_or_default();
    g.reactions = reactions;
    install(g);
}

/// Replaces the gas roster, keeping the reactions.
pub fn install_gases(gases: Vec<GasType>) {
    let mut g = current().map(|g| (*g).clone()).unwrap_or_default();
    g.gases = gases;
    install(g);
}

/// The index of the highest-priority reaction ready on this cell.
#[must_use]
pub fn ready(cell: &GasCell) -> Option<usize> {
    if cell.total_moles() <= GAS_MIN_MOLES {
        return None;
    }
    let t = temperature_of(&cell.moles, cell.energy, cell.temperature);
    with(|g| g.ready(&cell.moles, cell.energy, t))
}

/// Visible-gas signature of a mole vector (0: nothing visible).
#[must_use]
pub fn vis_signature(moles: &[f32; N]) -> u16 {
    if heat_capacity(moles) <= 0.0 {
        return 0;
    }
    with(|g| g.vis_signature(moles))
}

/// The index of a gas string: its DM type path (`"/datum/gas/oxygen"`) or
/// its short id (`"o2"`).
///
/// # Errors
/// If the string names no gas.
pub fn gas_idx_from_string(id: &str) -> eyre::Result<usize> {
    crate::gas::ids::gas_id_for_path(id)
        .or_else(|| with(|g| g.gases.iter().position(|gas| &*gas.id == id)))
        .ok_or_else(|| eyre::eyre!("Invalid gas ID: {id}"))
}

/// The gas index for a numeric `GAS_ID_*` value from DM.
///
/// # Errors
/// If the value is not a gas index.
#[allow(clippy::cast_sign_loss, clippy::cast_possible_truncation)]
pub fn gas_idx_from_value(raw: f32) -> eyre::Result<usize> {
    if raw < 0.0 || raw.fract() != 0.0 || raw as usize >= N {
        return Err(eyre::eyre!("Invalid gas ID: {raw}"));
    }
    Ok(raw as usize)
}
