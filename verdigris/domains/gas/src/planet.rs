//! Planet atmospheres a turf cell relaxes back to (`rust_architecture.md`
//! §8.5 step 6): a small, process-wide table, the same shape `gate.rs`
//! already uses for reaction/visibility data, chosen for the same reason --
//! `PlanetRelaxLaw` (`laws.rs`) runs on a worker frame-pool thread and reads
//! it there, while `planet_id` is only ever called from DM's main-thread
//! turf-registration path (`ffi/src/gas.rs`), so the table needs to be
//! `Send + Sync` but not a [`vg_core::query::Global`] (that would require a
//! worker-phase write, which DM's own main-thread call can never make).

use std::sync::RwLock;

use crate::cell::GasCell;

/// `(atmosphere key, baseline)` by id (`1`-based: index `0` is planet id 1).
/// A plain `Vec`, not a map: at most 255 entries, registered a handful of
/// times per round (once per unique `initial_gas_mix` string), so a linear
/// scan on registration costs nothing next to the FFI call around it.
static PLANETS: RwLock<Vec<(String, GasCell)>> = RwLock::new(Vec::new());

/// The planet id for an atmosphere string (interned on first use),
/// registering `baseline` as what cells with that id relax back to. `0`
/// once every id is taken (255 planets is generous headroom).
///
/// # Panics
/// If the lock is poisoned (a prior panic while holding it).
pub fn planet_id(key: &str, baseline: GasCell) -> u8 {
	let mut p = PLANETS.write().unwrap_or_else(std::sync::PoisonError::into_inner);
	if let Some(id) = p.iter().position(|(k, _)| k == key) {
		return u8::try_from(id + 1).unwrap_or(0);
	}
	if p.len() >= 255 {
		return 0;
	}
	let id = u8::try_from(p.len() + 1).unwrap_or(0);
	if id == 0 {
		return 0;
	}
	p.push((key.to_owned(), baseline));
	id
}

/// The baseline atmosphere for `id` (`1`-based; `0`/out of range: none),
/// for a worker-thread law to relax a reservoir cell toward. Never blocks:
/// a busy writer (registering a brand new planet) just means the reader
/// tries again next step, the same "retry" contract the old field's own
/// planet relaxation had.
#[must_use]
pub fn baseline(id: u8) -> Option<GasCell> {
	if id == 0 {
		return None;
	}
	let p = PLANETS.try_read().ok()?;
	p.get(usize::from(id) - 1).map(|(_, cell)| *cell)
}

#[cfg(test)]
pub(crate) fn reset_for_test() {
	PLANETS.write().unwrap_or_else(std::sync::PoisonError::into_inner).clear();
}
