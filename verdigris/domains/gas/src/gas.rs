//! The gas registry and mixture maths. Where each gas lives (main-owned
//! slots, turf field cells, pipe regions) is `world.rs`; the helpers below
//! give DM binds a mixture by its datum, whoever owns it.

// Physical/tuning constants mirrored from DM (`SPECIFIC_HEATS`, fire/reaction
// thresholds, ...); many are read from DM or by other gas submodules rather
// than from within `constants` itself, so per-constant dead_code is noise.
#[allow(dead_code)]
pub mod constants;
pub mod ids;
pub mod mixture;
pub mod types;

use byondapi::prelude::*;
use eyre::{eyre, Result};
pub use ids::*;
pub use mixture::Mixture;
pub use types::*;

use crate::world::{with_world, MixRef};

pub type GasIDX = usize;

// Dirty-mixture change bits. `@dm-define` exports each one to the generated
// DM bindings, where machinery interest masks use them.
/// @dm-define GAS_DEPENDENCY_PRESSURE
pub const GAS_CHANGE_PRESSURE: u8 = 1;
/// @dm-define GAS_DEPENDENCY_TEMPERATURE
pub const GAS_CHANGE_TEMPERATURE: u8 = 2;
/// @dm-define GAS_DEPENDENCY_COMPOSITION
pub const GAS_CHANGE_COMPOSITION: u8 = 4;

pub(crate) fn missing(r: MixRef) -> eyre::Report {
	eyre!("no gas mixture behind handle {} ({r:?})", r.id())
}

/// Calls `f` with the mixture behind a `/datum/gas_mixture`.
///
/// # Errors
/// If the datum has no live handle, or `f` fails.
pub fn with_mix<T, F>(mix: &ByondValue, f: F) -> Result<T>
where
	F: FnOnce(&Mixture) -> Result<T>,
{
	let r = MixRef::of(mix)?;
	with_world(|w| match r {
		MixRef::Main(i) => f(w.mains.get(i).ok_or_else(|| missing(r))?),
		_ => f(&w.load(r).ok_or_else(|| missing(r))?),
	})
}

/// As [`with_mix`], but mutable. A turf's gas changes by one command.
///
/// # Errors
/// If the datum has no live handle, or `f` fails.
pub fn with_mix_mut<T, F>(mix: &ByondValue, f: F) -> Result<T>
where
	F: FnOnce(&mut Mixture) -> Result<T>,
{
	let r = MixRef::of(mix)?;
	with_world(|w| {
		let before = w.load(r).ok_or_else(|| missing(r))?;
		let mut after = before.clone();
		let out = f(&mut after)?;
		w.store(r, &before, &after);
		Ok(out)
	})
}

/// As [`with_mix`], with two mixtures.
///
/// # Errors
/// If a datum has no live handle, or `f` fails.
pub fn with_mixes<T, F>(src: &ByondValue, arg: &ByondValue, f: F) -> Result<T>
where
	F: FnOnce(&Mixture, &Mixture) -> Result<T>,
{
	let (a, b) = (MixRef::of(src)?, MixRef::of(arg)?);
	with_world(|w| {
		let ma = w.load(a).ok_or_else(|| missing(a))?;
		let mb = w.load(b).ok_or_else(|| missing(b))?;
		f(&ma, &mb)
	})
}

/// As [`with_mix_mut`], with two mixtures. When both datums name the same
/// mixture, only the first argument's changes are kept.
///
/// # Errors
/// If a datum has no live handle, or `f` fails.
pub fn with_mixes_mut<T, F>(src: &ByondValue, arg: &ByondValue, f: F) -> Result<T>
where
	F: FnOnce(&mut Mixture, &mut Mixture) -> Result<T>,
{
	let (a, b) = (MixRef::of(src)?, MixRef::of(arg)?);
	with_world(|w| {
		let before_a = w.load(a).ok_or_else(|| missing(a))?;
		let before_b = w.load(b).ok_or_else(|| missing(b))?;
		let (mut ma, mut mb) = (before_a.clone(), before_b.clone());
		let out = f(&mut ma, &mut mb)?;
		w.store(a, &before_a, &ma);
		if a != b {
			w.store(b, &before_b, &mb);
		}
		Ok(out)
	})
}

/// Live main-owned mixtures (turf and pipe gas have no slot).
#[must_use]
pub fn amt_gases() -> usize {
	with_world(|w| w.mains.live())
}

/// Main-owned mixture slots allocated.
#[must_use]
pub fn tot_gases() -> usize {
	with_world(|w| w.mains.capacity())
}
