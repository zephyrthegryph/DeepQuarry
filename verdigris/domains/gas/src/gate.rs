//! Registry data the field reads on frame threads: reaction requirements
//! (for `TurfGas::local`, the "can react" check) and gas visibility
//! thresholds (for the visual signature).
//!
//! DM registers reactions and gases once at boot (and on the rare
//! `update_reactions`). The table is immutable once built and published as
//! an `Arc`; frame threads keep a thread-local copy and only touch the lock
//! when the version moves, so the per-cell check is lock-free.

use std::cell::RefCell;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, RwLock};

use crate::cell::{heat_capacity, temperature_of, GasCell, N};
use crate::gas::constants::{FACTOR_GAS_VISIBLE_MAX, GAS_MIN_MOLES, MOLES_GAS_VISIBLE_STEP};

/// One reaction's requirements (a `/datum/gas_reaction`'s
/// `min_requirements`).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Requirement {
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

/// The registry data frame threads need.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Gate {
	pub reactions: Vec<Requirement>,
	pub fire: [Fire; N],
	/// Moles above which each gas is visible.
	pub visible: [Option<f32>; N],
}

impl Gate {
	/// Oxidation power and fuel amount at the cell's temperature.
	#[must_use]
	pub fn burnability(&self, moles: &[f32; N], temperature: f32) -> (f32, f32) {
		let mut acc = (0.0, 0.0);
		for (i, &amt) in moles.iter().enumerate() {
			if amt <= GAS_MIN_MOLES {
				continue;
			}
			match self.fire[i] {
				Fire::Oxidizer {
					temperature: t,
					power,
				} if temperature > t => {
					acc.0 += amt * (1.0 - t / temperature).max(0.0) * power;
				}
				Fire::Fuel {
					temperature: t,
					burn_rate,
				} if temperature > t => {
					acc.1 += amt * (1.0 - t / temperature).max(0.0) / burn_rate;
				}
				_ => {}
			}
		}
		acc
	}

	/// Whether any reaction's requirements hold.
	#[must_use]
	pub fn can_react(&self, moles: &[f32; N], energy: f32, temperature: f32) -> bool {
		self.reactions.iter().any(|r| {
			r.min_temp.is_none_or(|t| temperature >= t)
				&& r.max_temp.is_none_or(|t| temperature <= t)
				&& r.gases
					.iter()
					.all(|&(g, v)| moles.get(g).is_some_and(|&m| m >= v))
				&& r.min_energy.is_none_or(|e| energy >= e)
				&& r.min_fire.is_none_or(|f| {
					let (oxi, fuel) = self.burnability(moles, temperature);
					oxi.min(fuel) >= f
				})
		})
	}

	/// See [`vis_signature`].
	#[must_use]
	pub fn vis_signature(&self, moles: &[f32; N]) -> u16 {
		let mut h: u32 = 0;
		for (i, &amt) in moles.iter().enumerate() {
			if let Some(threshold) = self.visible[i] {
				if amt > threshold {
					let step = (amt / MOLES_GAS_VISIBLE_STEP)
						.ceil()
						.clamp(1.0, FACTOR_GAS_VISIBLE_MAX) as u32;
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
static VERSION: AtomicU64 = AtomicU64::new(0);

thread_local! {
	static CACHE: RefCell<(u64, Option<Arc<Gate>>)> = const { RefCell::new((u64::MAX, None)) };
}

/// Publishes a new gate (boot, reaction updates).
pub fn install(gate: Gate) {
	*GATE
		.write()
		.unwrap_or_else(std::sync::PoisonError::into_inner) = Some(Arc::new(gate));
	VERSION.fetch_add(1, Ordering::Release);
}

/// The current gate, if one is installed.
#[must_use]
pub fn current() -> Option<Arc<Gate>> {
	GATE.read()
		.unwrap_or_else(std::sync::PoisonError::into_inner)
		.clone()
}

fn with<T>(f: impl FnOnce(&Gate) -> T) -> Option<T> {
	CACHE.with(|c| {
		let mut c = c.borrow_mut();
		let v = VERSION.load(Ordering::Acquire);
		if c.0 != v {
			*c = (v, current());
		}
		c.1.as_deref().map(f)
	})
}

/// Whether any registered reaction's requirements hold for the cell.
#[must_use]
pub fn can_react(cell: &GasCell) -> bool {
	if cell.total_moles() <= GAS_MIN_MOLES {
		return false;
	}
	let t = temperature_of(&cell.moles, cell.energy, cell.temperature);
	with(|g| g.can_react(&cell.moles, cell.energy, t)).unwrap_or(false)
}

/// Visible-gas signature of a mole vector (0: nothing visible).
#[must_use]
pub fn vis_signature(moles: &[f32; N]) -> u16 {
	if heat_capacity(moles) <= 0.0 {
		return 0;
	}
	with(|g| g.vis_signature(moles)).unwrap_or(0)
}
