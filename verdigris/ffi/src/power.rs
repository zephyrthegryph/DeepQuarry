//! Binds for `vg-power` (M3): the cable network, the power ledger and the
//! APC and SMES models. DM (`code/modules/power/power_bridge.dm`) queues
//! edits and commands in one flat list and sends it with
//! [`vg_power_edit`](power_edit) (an explosion's edits are one call and one
//! commit), draws synchronously, and makes one [`power_step`] call per
//! machinery tick, which returns the events it must act on.
//!
//! Everything runs on BYOND's main thread.
use std::cell::RefCell;

use byondapi::prelude::*;
use eyre::{Result, bail};
use vg_power::PowerWorld;
use vg_power::apc::ApcConfig;
use vg_power::geom::{CableShape, pos};
use vg_power::smes::SmesConfig;

// --- DM constants: edit ops. Each op is `op, n, n values`. -----------------

/// `key, x, y, z, d1, d2, z_above, z_below, link_id`
/// @dm-define POWER_OP_CABLE
pub const OP_CABLE: u32 = 1;
/// `key, x, y, z`
/// @dm-define POWER_OP_MACHINE
pub const OP_MACHINE: u32 = 2;
/// `key`
/// @dm-define POWER_OP_REMOVE
pub const OP_REMOVE: u32 = 3;
/// `key, watts`: persistent supply.
/// @dm-define POWER_OP_SUPPLY
pub const OP_SUPPLY: u32 = 4;
/// `key, watts`: supply for the next step only.
/// @dm-define POWER_OP_PULSE
pub const OP_PULSE: u32 = 5;
/// `key, terminal (-1 none), flags, max_charge, chargelevel, charge (-1
/// keep), eqp, lgt, env (-1 keep), autoflag (-1 keep)`
/// @dm-define POWER_OP_APC
pub const OP_APC: u32 = 6;
/// `key, eqp, lgt, env`: the area's static load (W).
/// @dm-define POWER_OP_AREA_LOAD
pub const OP_AREA_LOAD: u32 = 7;
/// `key, eqp, lgt, env`: one-off area use (W) for the next step.
/// @dm-define POWER_OP_ONEOFF
pub const OP_ONEOFF: u32 = 8;
/// `key, flags, capacity, input_level, output_level, charge (-1 keep),
/// terminal keys...`
/// @dm-define POWER_OP_SMES
pub const OP_SMES: u32 = 9;
/// `key, charge`
/// @dm-define POWER_OP_CHARGE
pub const OP_CHARGE: u32 = 10;
/// `key`: forget an APC or SMES.
/// @dm-define POWER_OP_REMOVE_STORAGE
pub const OP_REMOVE_STORAGE: u32 = 11;

/// APC flags.
/// @dm-define POWER_APC_ACTIVE
pub const APC_ACTIVE: u32 = 1;
/// @dm-define POWER_APC_HAS_CELL
pub const APC_HAS_CELL: u32 = 2;
/// @dm-define POWER_APC_FAILED
pub const APC_FAILED: u32 = 4;
/// @dm-define POWER_APC_SHORTED
pub const APC_SHORTED: u32 = 8;
/// @dm-define POWER_APC_OPERATING
pub const APC_OPERATING: u32 = 16;
/// @dm-define POWER_APC_CHARGEMODE
pub const APC_CHARGEMODE: u32 = 32;

/// SMES flags.
/// @dm-define POWER_SMES_INPUT
pub const SMES_INPUT: u32 = 1;
/// @dm-define POWER_SMES_OUTPUT
pub const SMES_OUTPUT: u32 = 2;

// --- DM constants: events from `vg_power_step`. -----------------------------

/// @dm-define POWER_EV_BIND
pub const EV_BIND: u32 = 1;
/// @dm-define POWER_EV_REGION
pub const EV_REGION: u32 = 2;
/// @dm-define POWER_EV_RETIRED
pub const EV_RETIRED: u32 = 3;
/// @dm-define POWER_EV_APC
pub const EV_APC: u32 = 4;
/// @dm-define POWER_EV_SMES
pub const EV_SMES: u32 = 5;
/// @dm-define POWER_EV_BROWNOUT
pub const EV_BROWNOUT: u32 = 6;

/// Numbers in a `vg_power_region` reply: region, avail, load, netexcess,
/// supply, eqp, lgt, env, capacity, members.
/// @dm-define POWER_REGION_STRIDE
pub const REGION_STRIDE: u32 = 10;

const _: () = {
    assert!(EV_BIND == vg_power::ev::BIND);
    assert!(EV_REGION == vg_power::ev::REGION);
    assert!(EV_RETIRED == vg_power::ev::RETIRED);
    assert!(EV_APC == vg_power::ev::APC);
    assert!(EV_SMES == vg_power::ev::SMES);
    assert!(EV_BROWNOUT == vg_power::ev::BROWNOUT);
    assert!(REGION_STRIDE == 10);
};

thread_local! {
    static WORLD: RefCell<PowerWorld> = RefCell::new(PowerWorld::new());
}

fn with<T>(f: impl FnOnce(&mut PowerWorld) -> Result<T>) -> Result<T> {
    WORLD.with(|w| f(&mut w.borrow_mut()))
}

fn list(values: &[f32]) -> Result<ByondValue> {
    let items: Vec<ByondValue> = values.iter().map(|&v| ByondValue::from(v)).collect();
    let list = ByondValue::new_list()?;
    list.write_list(&items)?;
    Ok(list)
}

fn key_of(v: f32) -> Result<u32> {
    if !(v >= 0.0 && v.fract() == 0.0 && v < 16_777_216.0) {
        bail!("bad power key {v}");
    }
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    Ok(v as u32)
}

#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn small(v: f32) -> u32 {
    v.max(0.0) as u32
}

fn keep(v: f32) -> Option<f32> {
    (v >= 0.0).then_some(v)
}

fn apply(w: &mut PowerWorld, op: u32, a: &[f32]) -> Result<()> {
    let need = |n: usize| -> Result<()> {
        if a.len() < n {
            bail!("power op {op} needs {n} values, got {}", a.len());
        }
        Ok(())
    };
    match op {
        OP_CABLE => {
            need(9)?;
            let shape = CableShape {
                d1: u8::try_from(small(a[4]))?,
                d2: u8::try_from(small(a[5]))?,
                up: small(a[6]),
                down: small(a[7]),
                link: small(a[8]),
            };
            let p = pos(small(a[1]), small(a[2]), small(a[3]));
            w.add_cable(key_of(a[0])?, p, shape).map_err(|e| eyre::eyre!(e))?;
        }
        OP_MACHINE => {
            need(4)?;
            let p = pos(small(a[1]), small(a[2]), small(a[3]));
            w.add_machine(key_of(a[0])?, p).map_err(|e| eyre::eyre!(e))?;
        }
        OP_REMOVE => {
            need(1)?;
            w.remove(key_of(a[0])?);
        }
        OP_SUPPLY => {
            need(2)?;
            w.set_supply(key_of(a[0])?, f64::from(a[1]));
        }
        OP_PULSE => {
            need(2)?;
            w.pulse(key_of(a[0])?, f64::from(a[1]));
        }
        OP_APC => {
            need(10)?;
            let key = key_of(a[0])?;
            let terminal = (a[1] >= 0.0).then(|| key_of(a[1])).transpose()?;
            let flags = small(a[2]);
            let config = ApcConfig {
                active: flags & APC_ACTIVE != 0,
                has_cell: flags & APC_HAS_CELL != 0,
                failed: flags & APC_FAILED != 0,
                shorted_or_grid_check: flags & APC_SHORTED != 0,
                operating: flags & APC_OPERATING != 0,
                chargemode: flags & APC_CHARGEMODE != 0,
                max_charge: f64::from(a[3].max(0.0)),
                chargelevel: f64::from(a[4].max(0.0)),
                ..ApcConfig::default()
            };
            let old = w.apc(key).map(|x| x.state);
            let mut state = old.unwrap_or_default();
            if let Some(c) = keep(a[5]) {
                state.charge = f64::from(c);
            }
            for (i, v) in a[6..9].iter().enumerate() {
                if let Some(c) = keep(*v) {
                    state.channels[i] = u8::try_from(small(c).min(3))?;
                }
            }
            if let Some(f) = keep(a[9]) {
                state.autoflag = u8::try_from(small(f).min(255))?;
            }
            w.set_apc(key, config, terminal, Some(state));
        }
        OP_AREA_LOAD => {
            need(4)?;
            w.set_area_load(key_of(a[0])?, [a[1], a[2], a[3]].map(f64::from));
        }
        OP_ONEOFF => {
            need(4)?;
            w.add_area_oneoff(key_of(a[0])?, [a[1], a[2], a[3]].map(f64::from));
        }
        OP_SMES => {
            need(6)?;
            let flags = small(a[1]);
            let config = SmesConfig {
                capacity: f64::from(a[2].max(0.0)),
                input_level: f64::from(a[3].max(0.0)),
                output_level: f64::from(a[4].max(0.0)),
                input_enabled: flags & SMES_INPUT != 0,
                output_enabled: flags & SMES_OUTPUT != 0,
            };
            let terminals = a[6..].iter().map(|&t| key_of(t)).collect::<Result<Vec<u32>>>()?;
            w.set_smes(key_of(a[0])?, config, terminals, keep(a[5]).map(f64::from));
        }
        OP_CHARGE => {
            need(2)?;
            w.set_charge(key_of(a[0])?, f64::from(a[1]));
        }
        OP_REMOVE_STORAGE => {
            need(1)?;
            w.remove_storage(key_of(a[0])?);
        }
        _ => bail!("unknown power op {op}"),
    }
    Ok(())
}

/// Applies a flat list of edits and commands (`op, n, n values` each; the
/// `POWER_OP_*` defines). Topology waits for the next read or step, so a
/// batch commits once.
#[auxmacros::bind("/proc/power_edit")]
fn power_edit(ops: ByondValue) -> Result<ByondValue> {
    let values: Vec<f32> = ops
        .get_list_values()?
        .iter()
        .map(|v| Ok(v.get_number()?))
        .collect::<Result<Vec<f32>>>()?;
    with(|w| {
        let mut i = 0;
        while i + 1 < values.len() {
            let op = small(values[i]);
            let n = small(values[i + 1]) as usize;
            let end = (i + 2 + n).min(values.len());
            apply(w, op, &values[i + 2..end])?;
            i = end;
        }
        Ok(())
    })?;
    Ok(ByondValue::null())
}

/// One machinery tick. Returns the events as `type, n, n values` records
/// (the `POWER_EV_*` defines).
#[auxmacros::bind("/proc/power_step")]
fn power_step() -> Result<ByondValue> {
    let events = with(|w| Ok(w.step()))?;
    list(&events)
}

/// Draws up to `watts` for `key` from its region now; returns what was
/// delivered.
#[auxmacros::bind("/proc/power_draw")]
fn power_draw(key: ByondValue, watts: ByondValue) -> Result<ByondValue> {
    let key = key_of(key.get_number()?)?;
    let watts = f64::from(watts.get_number()?);
    #[allow(clippy::cast_possible_truncation)]
    let got = with(|w| Ok(w.draw(key, watts)))? as f32;
    Ok(ByondValue::from(got))
}

/// The region `key` is on, `POWER_REGION_STRIDE` numbers, or null.
#[auxmacros::bind("/proc/power_region")]
fn power_region(key: ByondValue) -> Result<ByondValue> {
    let key = key_of(key.get_number()?)?;
    let Some(info) = with(|w| Ok(w.region_info(key)))? else {
        return Ok(ByondValue::null());
    };
    #[allow(clippy::cast_possible_truncation, clippy::cast_precision_loss)]
    let values = [
        info.region as f32,
        info.avail as f32,
        info.load as f32,
        info.netexcess as f32,
        info.summary[0] as f32,
        info.summary[1] as f32,
        info.summary[2] as f32,
        info.summary[3] as f32,
        info.summary[4] as f32,
        info.members as f32,
    ];
    list(&values)
}

/// Keys of every cable and machine on `key`'s region.
#[auxmacros::bind("/proc/power_members")]
fn power_members(key: ByondValue) -> Result<ByondValue> {
    let key = key_of(key.get_number()?)?;
    #[allow(clippy::cast_precision_loss)]
    let keys: Vec<f32> = with(|w| Ok(w.members(key)))?
        .into_iter()
        .map(|k| k as f32)
        .collect();
    list(&keys)
}

/// Forgets everything (world start and tests).
#[auxmacros::bind("/proc/power_reset")]
fn power_reset() -> Result<ByondValue> {
    with(|w| {
        *w = PowerWorld::new();
        Ok(())
    })?;
    Ok(ByondValue::null())
}
