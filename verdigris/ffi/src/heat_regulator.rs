//! One bind for `vg_heat::regulator::Regulator` (H4: the generic thermal
//! regulator DM's air conditioners, space heaters and thermoregulators wire
//! onto instead of each computing their own COP, `rust_core.md` §15's "the
//! heat regulator" row).
//!
//! A [`Regulator`] step is pure and stateless (settings plus the two
//! bodies' current capacity/temperature in, a flow out; nothing is kept
//! between calls), so unlike the mob heat-body component this needs no
//! entity, no domain and no thread-local world -- one bind computes a step,
//! and the machine's own DM code applies `work`/`moved`/`other` to its
//! power draw and the two thermal sides exactly as it already tracks them
//! (a wired-through-Rust step replaces the COP formula, not the machine's
//! surrounding bookkeeping).

// heat_regulator_step's argument count is inherent to the DM call
// convention (one parameter per Regulator setting plus both bodies'
// state); an item-level #[allow] doesn't reach the warning, which is
// emitted inside ::byondapi::bind's own macro expansion (see
// ffi/src/reactor.rs's file-level allow and its comment for the same
// reason).
#![allow(clippy::too_many_arguments)]

use byondapi::prelude::*;
use eyre::Result;
use vg_core::thermo::ThermalBody;
use vg_core::units::{HeatCapacity, Kelvin};
use vg_core::thermo::{Regulator, RegulatorMode};

/// `RegulatorMode` as DM sends it.
/// @dm-define REGULATOR_MODE_HEAT
pub const MODE_HEAT: i32 = 0;
/// @dm-define REGULATOR_MODE_COOL
pub const MODE_COOL: i32 = 1;
/// @dm-define REGULATOR_MODE_BOTH
pub const MODE_BOTH: i32 = 2;

fn num(v: &ByondValue) -> Result<f32> {
    Ok(v.get_number()?)
}

fn mode_of(v: f32) -> RegulatorMode {
    match v as i32 {
        MODE_HEAT => RegulatorMode::Heat,
        MODE_COOL => RegulatorMode::Cool,
        MODE_BOTH => RegulatorMode::Both,
        // An out-of-range value degrades to the least restrictive mode.
        _ => RegulatorMode::Both,
    }
}

/// One regulator step. `other_capacity < 0` means an infinite (reservoir)
/// other side (space, a planet's atmosphere, an unlimited external loop).
/// Returns `list(work, moved, other)` (`RegulatorStep`'s three flows, W or
/// J per `dt`, matching whichever unit the caller passed capacities in).
///
/// # Errors
/// A non-numeric argument.
#[auxmacros::bind("/proc/heat_regulator_step")]
fn heat_regulator_step(
    target: ByondValue,
    max_power: ByondValue,
    mode: ByondValue,
    carnot_fraction: ByondValue,
    max_cop: ByondValue,
    resistive_heating: ByondValue,
    deadband: ByondValue,
    controlled_capacity: ByondValue,
    controlled_temp: ByondValue,
    other_capacity: ByondValue,
    other_temp: ByondValue,
    dt: ByondValue,
) -> Result<ByondValue> {
    let regulator = Regulator {
        target: num(&target)?,
        max_power: num(&max_power)?,
        mode: mode_of(num(&mode)?),
        carnot_fraction: num(&carnot_fraction)?,
        max_cop: num(&max_cop)?,
        resistive_heating: num(&resistive_heating)? != 0.0,
        deadband: num(&deadband)?,
    };
    let controlled = ThermalBody::new(
        HeatCapacity::from(num(&controlled_capacity)?),
        Kelvin::from(num(&controlled_temp)?),
    );
    let oc = num(&other_capacity)?;
    let other = ThermalBody::new(
        if oc < 0.0 {
            HeatCapacity::from(f32::INFINITY)
        } else {
            HeatCapacity::from(oc)
        },
        Kelvin::from(num(&other_temp)?),
    );
    let step = regulator.step(controlled, other, num(&dt)?);
    let list = ByondValue::new_list()?;
    list.write_list(&[
        ByondValue::from(step.work),
        ByondValue::from(step.moved),
        ByondValue::from(step.other),
    ])?;
    Ok(list)
}

/// Just the cooling-side Carnot-bounded COP (`cold`/`hot` in K), for a
/// caller that owns its own power-budget accounting (grid `draw_power()`)
/// and only wants the COP formula itself off DM -- a smaller surface than
/// [`heat_regulator_step`] for a machine that can't hand its whole budget
/// to the generic step without also rewriting how it draws from the power
/// grid.
///
/// # Errors
/// A non-numeric argument.
#[auxmacros::bind("/proc/heat_regulator_cooling_cop")]
fn heat_regulator_cooling_cop(
    cold: ByondValue,
    hot: ByondValue,
    carnot_fraction: ByondValue,
    max_cop: ByondValue,
) -> Result<ByondValue> {
    let cop = vg_core::thermo::cooling_cop(
        num(&cold)?,
        num(&hot)?,
        num(&carnot_fraction)?,
        num(&max_cop)?,
    );
    Ok(ByondValue::from(cop))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mode_decode_matches_the_dm_defines() {
        assert_eq!(mode_of(MODE_HEAT as f32), RegulatorMode::Heat);
        assert_eq!(mode_of(MODE_COOL as f32), RegulatorMode::Cool);
        assert_eq!(mode_of(MODE_BOTH as f32), RegulatorMode::Both);
        // An out-of-range value degrades to the least restrictive mode
        // (Both) rather than silently picking Heat or Cool.
        assert_eq!(mode_of(99.0), RegulatorMode::Both);
    }
}
