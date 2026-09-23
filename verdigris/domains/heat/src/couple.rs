//! Couplings between stores: the gas interface, the exact pair exchange,
//! the energy ledger, and the solid ↔ turf gas frame task.
//!
//! R6 left couplings unbuilt. Here each coupling is one frame task that
//! writes both of its stores with one number: the energy it computes is
//! removed from one side and added to the other (or to the [`ledger`] when
//! the other side is a reservoir), so energy is conserved exactly apart
//! from `f32` rounding of the stored values.
//!
//! Gas lives outside the sim (vg-gas's arena, being restructured by M1a and
//! moved onto the field framework by M1b), so the heat domain only sees it
//! through the small [`GasExchange`] trait. The DLL implements it over the
//! arena; tests implement it over a vector.

use std::collections::BTreeSet;
use std::sync::Arc;

use vg_core::cow::ChunkLayout;
use vg_core::field::FieldKey;
use vg_core::frame::Task;
use vg_core::owner::{Applied, Domain, DomainKey};
use vg_core::sim::SimBuilder;

use crate::consts::{GAS_COUPLING, GAS_COUPLING_MIN_K};
use crate::solid::{SolidCell, SolidHeat, flags};

/// Which gas a coupling reaches.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum GasRef {
    /// The air of the turf at this cell index.
    Turf(u32),
    /// A gas mixture by arena id (a pipe network, a tank, a canister).
    Mixture(u32),
}

/// A gas as a coupling sees it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GasProbe {
    pub temperature: f32,
    /// J/K.
    pub capacity: f32,
    /// Immutable (space, a planet's atmosphere): energy added to it is not
    /// kept, and goes to the ledger.
    pub reservoir: bool,
}

/// The heat domain's view of gas. Implementations must be callable from
/// frame-pool threads and must never block on a busy gas: they return
/// `None` and the coupling retries next frame.
pub trait GasExchange: Send + Sync + 'static {
    /// The gas's state, or `None` if there is none or it is busy.
    fn probe(&self, gas: GasRef) -> Option<GasProbe>;

    /// Locks the gas, calls `f` with its state, and adds the energy `f`
    /// returns (J; negative removes). Returns the energy actually added
    /// (an implementation may clamp so the gas stays at or above TCMB; a
    /// reservoir reports the full amount without changing), or `None`
    /// with nothing changed if the gas is missing or busy.
    fn exchange(&self, gas: GasRef, f: &mut dyn FnMut(GasProbe) -> f32) -> Option<f32>;

    /// Appends the turf cells whose gas temperature changed since the last
    /// call (the coupling revisits them). The default reports nothing.
    fn take_changed(&self, _out: &mut Vec<u32>) {}
}

/// A gas-less world (tests, and the DLL before the gas arena is up).
#[derive(Clone, Copy, Debug, Default)]
pub struct NoGas;

impl GasExchange for NoGas {
    fn probe(&self, _gas: GasRef) -> Option<GasProbe> {
        None
    }
    fn exchange(&self, _gas: GasRef, _f: &mut dyn FnMut(GasProbe) -> f32) -> Option<f32> {
        None
    }
}

/// Exact energy moved from `a` to `b` over `dt` by conductance `g` (W/K):
/// `ΔT · h · (1 − e^(−g (1/Ca + 1/Cb) dt))` with `h = 1 / (1/Ca + 1/Cb)`.
/// A reservoir side passes `f32::INFINITY`. Never overshoots, for any `dt`.
///
/// A thin wrapper over `vg_core::thermo::pair_exchange` (the one
/// pair-exchange law every domain shares, `rust_core.md` §15): kept as a
/// raw-`f32` function here so existing callers in this crate don't need to
/// wrap their temperatures/capacities in `ThermalBody`.
#[must_use]
pub fn pair_exchange(ta: f32, ca: f32, tb: f32, cb: f32, g: f32, dt: f32) -> f32 {
    use vg_core::thermo::{self, ThermalBody};
    use vg_core::units::{HeatCapacity, Kelvin, Seconds};
    let a = ThermalBody::new(HeatCapacity::from(ca), Kelvin::from(ta));
    let b = ThermalBody::new(HeatCapacity::from(cb), Kelvin::from(tb));
    thermo::pair_exchange(a, b, f64::from(g), Seconds::from(dt)).into()
}

/// As [`pair_exchange`], with the pair's relaxation rate (1/s) given
/// directly: `ΔT · h · (1 − e^(−rate dt))`. See [`pair_exchange`]'s note:
/// wraps `vg_core::thermo::pair_exchange_at_rate`.
#[must_use]
pub fn pair_exchange_at_rate(ta: f32, ca: f32, tb: f32, cb: f32, rate: f32, dt: f32) -> f32 {
    use vg_core::thermo::{self, ThermalBody};
    use vg_core::units::{HeatCapacity, Kelvin, Seconds};
    let a = ThermalBody::new(HeatCapacity::from(ca), Kelvin::from(ta));
    let b = ThermalBody::new(HeatCapacity::from(cb), Kelvin::from(tb));
    thermo::pair_exchange_at_rate(a, b, f64::from(rate), Seconds::from(dt)).into()
}

/// Where energy went that no store kept. Cells of the [`HeatLedger`]
/// domain, in J, cumulative.
pub mod ledger {
    /// Net inflow into solid reservoir cells (space, planets): the field's
    /// own ledger, mirrored each frame.
    pub const FIELD_RESERVOIRS: u32 = 0;
    /// Net inflow into reservoir gases (immutable space and planet air).
    pub const GAS_RESERVOIRS: u32 = 1;
    /// Net energy put into mutable gases by couplings (J the gas domain now
    /// holds; the gas side of the books).
    pub const GAS: u32 = 2;
    /// Energy bodies' power sources added (negative: sinks removed).
    pub const POWER: u32 = 3;
    /// Energy released bodies returned to no environment.
    pub const RELEASED: u32 = 4;
    /// Energy an analytic body exchanged under a coupling DM removed before
    /// it settled, and (negative) energy a body's TCMB floor supplied when a
    /// sink would have taken it lower.
    pub const LOST: u32 = 5;
    /// Net inflow from bodies into solid reservoir cells.
    pub const BODY_RESERVOIRS: u32 = 6;
    pub const LEN: u32 = 8;
}

/// The energy ledger: one cumulative `f64` per [`ledger`] entry, written by
/// frame tasks and readable from the pinned view.
pub struct HeatLedger;

impl Domain for HeatLedger {
    type Value = f64;
    /// Adds to the entry.
    type Command = f64;
    const NAME: &'static str = "heat_ledger";

    fn apply(value: &mut f64, cmd: &f64) -> Applied {
        *value += cmd;
        Applied::default()
    }
}

/// Registers the ledger domain.
pub fn add_ledger(builder: &mut SimBuilder) -> DomainKey<HeatLedger> {
    builder.add_domain::<HeatLedger>(ChunkLayout::linear(ledger::LEN))
}

/// Worker state of the solid ↔ gas coupling: cells still diverged after
/// their last exchange (or whose gas was busy).
#[derive(Debug, Default)]
pub struct GasCouplingState {
    pending: BTreeSet<u32>,
    scratch: Vec<u32>,
    /// Exchanges in the last frame.
    pub last_exchanges: u32,
}

/// Registers the solid ↔ turf gas coupling task (after the field task).
///
/// Candidates each frame: cells the gas reported changed, cells still
/// pending, and air cells of chunks the field left active. Each pair relaxes
/// exactly at `rate = GAS_COUPLING · conductivity` (today's
/// `temperature_share_non_gas` coefficient, integrated exactly instead of
/// explicitly), for pairs more than `GAS_COUPLING_MIN_K` apart. Unlike
/// superconduct.rs, this is no longer gated on either side being above
/// 303 K: cold air cools floors too.
pub fn add_gas_coupling(
    builder: &mut SimBuilder,
    field: FieldKey<SolidHeat>,
    ledger_key: DomainKey<HeatLedger>,
    gas: Arc<dyn GasExchange>,
    dt: f32,
) {
    let state = builder.add_resource("heat:gas_coupling", GasCouplingState::default());
    let (geom_res, cells_res, field_res, ledger_res) = (
        field.geometry.state(),
        field.cells.state(),
        field.state,
        ledger_key.state(),
    );
    builder.add_task(
        Task::new("heat:gas_coupling", move |ctx| {
            let geom = ctx.read(geom_res);
            let field_state = ctx.read(field_res);
            let mut cells = ctx.write(cells_res);
            let mut st = ctx.write(state);
            let st = &mut *st;
            let mut candidates = std::mem::take(&mut st.pending);
            st.scratch.clear();
            gas.take_changed(&mut st.scratch);
            candidates.extend(st.scratch.iter().copied());
            let layout = cells.store.layout();
            for chunk in field_state.active_chunks() {
                let Some(values) = cells.store.chunk(chunk) else {
                    continue;
                };
                for (i, v) in values.iter().enumerate() {
                    if v.has(flags::AIR) {
                        if let Some(index) = layout.index_of(chunk, i) {
                            candidates.insert(index);
                        }
                    }
                }
            }
            let (mut to_gas, mut to_reservoir) = (0.0f64, 0.0f64);
            let mut exchanges = 0u32;
            for cell in candidates {
                let Some(g) = geom.store.get(cell) else {
                    continue;
                };
                if !g.is_node() || g.reservoir {
                    continue;
                }
                let Some(solid) = cells.store.get(cell) else {
                    continue;
                };
                if !solid.has(flags::AIR) || solid.conductivity <= 0.0 {
                    continue;
                }
                let ts = solid.energy / g.capacity;
                let rate = GAS_COUPLING * solid.conductivity;
                let mut reservoir = false;
                let mut gas_after = 0.0f32;
                let result = gas.exchange(GasRef::Turf(cell), &mut |p: GasProbe| {
                    reservoir = p.reservoir;
                    gas_after = p.temperature;
                    if p.capacity <= 0.0 || (ts - p.temperature).abs() < GAS_COUPLING_MIN_K {
                        return 0.0;
                    }
                    let cg = if p.reservoir {
                        f32::INFINITY
                    } else {
                        p.capacity
                    };
                    let moved = pair_exchange_at_rate(ts, g.capacity, p.temperature, cg, rate, dt);
                    if !p.reservoir {
                        gas_after = p.temperature + moved / p.capacity;
                    }
                    moved
                });
                match result {
                    None => {
                        st.pending.insert(cell);
                    }
                    Some(applied) if applied != 0.0 => {
                        exchanges += 1;
                        let c: &mut SolidCell = cells.store.get_mut(cell).expect("cell in layout");
                        c.energy -= applied;
                        c.temperature = c.energy / g.capacity;
                        if reservoir {
                            to_reservoir += f64::from(applied);
                        } else {
                            to_gas += f64::from(applied);
                        }
                        if (c.temperature - gas_after).abs() >= GAS_COUPLING_MIN_K {
                            st.pending.insert(cell);
                        }
                    }
                    Some(_) => {}
                }
            }
            st.last_exchanges = exchanges;
            drop(cells);
            if to_gas != 0.0 || to_reservoir != 0.0 {
                let mut l = ctx.write(ledger_res);
                if let Some(v) = l.store.get_mut(ledger::GAS) {
                    *v += to_gas;
                }
                if let Some(v) = l.store.get_mut(ledger::GAS_RESERVOIRS) {
                    *v += to_reservoir;
                }
            }
        })
        .reads(geom_res.id())
        .reads(field_res.id())
        .writes(cells_res.id())
        .writes(state.id())
        .writes(ledger_res.id()),
    );
}

/// Registers the task that mirrors the field's reservoir ledger into the
/// ledger domain (so it is readable from the main thread).
pub fn add_field_ledger_mirror(
    builder: &mut SimBuilder,
    field: FieldKey<SolidHeat>,
    ledger_key: DomainKey<HeatLedger>,
) {
    let (field_res, ledger_res) = (field.state, ledger_key.state());
    builder.add_task(
        Task::new("heat:ledger", move |ctx| {
            let total = ctx.read(field_res).ledger()[0];
            let mut l = ctx.write(ledger_res);
            if l.store.get(ledger::FIELD_RESERVOIRS) != Some(total) {
                l.store.set(ledger::FIELD_RESERVOIRS, total);
            }
        })
        .reads(field_res.id())
        .writes(ledger_res.id()),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    // The exhaustive closed-form and never-overshoots properties now live
    // with the law itself in `vg_core::thermo` (`rust_core.md` §15); this is
    // just a smoke test that the wrapper actually delegates (right sign,
    // right ballpark) rather than re-deriving its own copy.
    #[test]
    fn wraps_core_thermo_pair_exchange() {
        let moved = pair_exchange(400.0, 100.0, 200.0, 100.0, 10.0, 3.0);
        let expect = 200.0 * 50.0 * (1.0 - (-0.6f64).exp());
        assert!(
            (f64::from(moved) - expect).abs() < 1e-3,
            "{moved} vs {expect}"
        );
        // A reservoir: harmonic -> the body's capacity.
        let moved = pair_exchange(400.0, 100.0, 300.0, f32::INFINITY, 10.0, 1e6);
        assert!((moved - 10_000.0).abs() < 1e-2);
    }

    #[test]
    fn wraps_core_thermo_pair_exchange_at_rate() {
        let moved = pair_exchange_at_rate(400.0, 100.0, 200.0, 100.0, 0.2, 3.0);
        let expect = 200.0 * 50.0 * (1.0 - (-0.6f64).exp());
        assert!(
            (f64::from(moved) - expect).abs() < 1e-3,
            "{moved} vs {expect}"
        );
    }
}
