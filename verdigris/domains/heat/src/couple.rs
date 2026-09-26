//! The gas interface (`rust_architecture.md` step 4, decision (b)): gas is
//! not yet a [`vg_core::field::FieldKind`] (step 6 ports it), so every edge
//! that touches gas -- solid↔gas in a turf, and a body's [`crate::components::GasCoupling`]
//! -- still reaches it through this small trait instead of a `Foreign`
//! join. Both are deleted in step 6 once `TurfGas` lands and the edges
//! become field↔field/component↔field laws.

use std::collections::BTreeSet;
use std::sync::Arc;

use vg_core::field::FieldKey;
use vg_core::frame::Task;
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
    /// kept.
    pub reservoir: bool,
}

/// The heat domain's view of gas. Implementations must be callable from
/// frame-pool threads and must never block on a busy gas: they return
/// `None` and the coupling retries next frame.
pub trait GasExchange: Send + Sync + 'static {
    /// The gas's state, or `None` if there is none or it is busy.
    fn probe(&self, gas: GasRef) -> Option<GasProbe>;

    /// Locks the gas, calls `f` with its state, and adds the energy `f`
    /// returns (J; negative removes). Returns the energy actually added, or
    /// `None` with nothing changed if the gas is missing or busy.
    fn exchange(&self, gas: GasRef, f: &mut dyn FnMut(GasProbe) -> f32) -> Option<f32>;

    /// Appends the turf cells whose gas temperature changed since the last
    /// call (the coupling revisits them even when the solid side is
    /// quiescent). The default reports nothing.
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

/// A pointer to the world's gas side, for [`vg_core::query::Global`]
/// (`Clone + PartialEq + Send + Sync + 'static`; `PartialEq` is pointer
/// identity, since the trait object itself never compares).
#[derive(Clone)]
pub struct GasHandle(pub Arc<dyn GasExchange>);

impl PartialEq for GasHandle {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }
}

impl Default for GasHandle {
    fn default() -> Self {
        Self(Arc::new(NoGas))
    }
}

/// Worker state of the solid ↔ gas coupling: cells still diverged after
/// their last exchange (or whose gas was busy).
#[derive(Debug, Default)]
pub struct GasCouplingState {
    pending: BTreeSet<u32>,
    scratch: Vec<u32>,
}

/// Registers the solid ↔ turf gas coupling task (after the field task), as
/// a plain [`SimBuilder`] task -- not a [`vg_core::law::Law`] -- because
/// `Cell<SolidHeat>`'s anchor only visits cells the field's own step left
/// active, and a gas-only change (the solid side quiescent) needs
/// [`GasExchange::take_changed`]'s extra candidates too
/// (`dq_h3_hotspot_heats_items`: a coupling that only reads active chunks
/// misses exactly this case).
///
/// Candidates each frame: cells the gas reported changed, cells still
/// pending, and air cells of chunks the field left active. Each pair
/// relaxes exactly at `rate = GAS_COUPLING * conductivity`, for pairs more
/// than [`GAS_COUPLING_MIN_K`] apart.
pub fn add_gas_coupling(builder: &mut SimBuilder, field: FieldKey<SolidHeat>, gas: Arc<dyn GasExchange>, dt: f32) {
    let state = builder.add_resource("heat:gas_coupling", GasCouplingState::default());
    let (geom_res, cells_res, field_res) = (field.geometry.state(), field.cells.state(), field.state);
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
                let mut gas_after = 0.0f32;
                let result = gas.exchange(GasRef::Turf(cell), &mut |p: GasProbe| {
                    gas_after = p.temperature;
                    if p.capacity <= 0.0 || (ts - p.temperature).abs() < GAS_COUPLING_MIN_K {
                        return 0.0;
                    }
                    let cg = if p.reservoir { f32::INFINITY } else { p.capacity };
                    let moved = vg_core::thermo::pair_exchange_at_rate_f32(ts, g.capacity, p.temperature, cg, rate, dt);
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
                        let c: &mut SolidCell = cells.store.get_mut(cell).expect("cell in layout");
                        c.energy -= applied;
                        c.temperature = c.energy / g.capacity;
                        if (c.temperature - gas_after).abs() >= GAS_COUPLING_MIN_K {
                            st.pending.insert(cell);
                        }
                    }
                    Some(_) => {}
                }
            }
        })
        .reads(geom_res.id())
        .reads(field_res.id())
        .writes(cells_res.id())
        .writes(state.id()),
    );
}
