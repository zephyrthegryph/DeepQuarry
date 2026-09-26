//! Gas FFI that needs live DM state, not just the pure gas registry
//! (`rust_architecture.md` §2, §8.5's "first gas slice"): reactions stay in
//! DM (`AGENTS.md`), so the live `/datum/gas_reaction` reference for each
//! reaction id is inherently FFI state and belongs here, not as a
//! domain-local `thread_local!` (the domain crate holds no global state --
//! `tools/ci/check_rust_core_consolidation.py`'s `thread_local` category).
//! The rest of vg-gas's ~60-bind mixture API still lives in
//! `verdigris/domains/gas/src/lib.rs` pending its own move here
//! (`rust_architecture.md` §8.5 step 6); this module is the first slice.

mod binds;
pub(crate) mod mix;
mod parser;

use std::cell::Cell;

use byondapi::prelude::*;
use eyre::{bail, eyre, Context, Result};
use vg_core::field::{FieldConfig, FieldKey, FieldKind, Geom, Side};
use vg_core::grid::{BlockKind, Dir, Face};
use vg_core::network::RegionId;
use vg_core::outbox::{Lane, Subscriber, Wake, WatchId};
use vg_core::registry::DomainRegistry;
use vg_core::slot::RawHandle;
use vg_core::watch::Cond;
use vg_core::world::{World, WorldBuilder};
use vg_gas::cell::{GasCell, GasCmd, TurfGas, Q};
use vg_gas::gas::constants::CELL_VOLUME;
use vg_gas::gas;
use vg_gas::laws::{CellReactionReadyLaw, CellVisualChangeLaw, SpacewindLaw};
use vg_gas::pipes::{PipeGas, Pipes};
use vg_gas::gate::{Fire, GasType, Requirement};

use self::mix::{with_mix, MixRef};
use crate::world::with_world;

// --- Pipe region slot compaction ----------------------------------------
//
// A pipe region's DM-facing handle is a compacted slot, not its raw arena
// bits (which can exceed `mix::MixRef::Pipe`'s 21-bit address
// budget) -- the one piece of bookkeeping the old hand-rolled `PipeNet`
// also needed for the same reason, not for revision or idle-skip
// tracking, which `NetworkHost`/`World` already provide generically. This
// lives here (FFI state, alongside the reaction table above and
// `crate::world`'s `WORLD`), not in `crate::pipes`, which only reads
// through [`region_of_slot`] -- `verdigris/ffi/src/pipes.rs`'s own docs.

#[derive(Default)]
pub(crate) struct SlotTable {
    slot_of: std::collections::HashMap<u32, u32>,
    raw_of: Vec<Option<u32>>,
    free: Vec<u32>,
}

impl SlotTable {
    pub(crate) fn slot_for(&mut self, raw: u32) -> u32 {
        if let Some(&s) = self.slot_of.get(&raw) {
            return s;
        }
        let s = self.free.pop().unwrap_or_else(|| {
            self.raw_of.push(None);
            u32::try_from(self.raw_of.len() - 1).unwrap_or(u32::MAX)
        });
        self.raw_of[s as usize] = Some(raw);
        self.slot_of.insert(raw, s);
        s
    }

    pub(crate) fn retire(&mut self, raw: u32) -> Option<u32> {
        let s = self.slot_of.remove(&raw)?;
        self.raw_of[s as usize] = None;
        self.free.push(s);
        Some(s)
    }

    pub(crate) fn raw_slot_of(&self, raw: u32) -> Option<u32> {
        self.slot_of.get(&raw).copied()
    }

    pub(crate) fn raw_of(&self, slot: u32) -> Option<u32> {
        self.raw_of.get(slot as usize).copied().flatten()
    }
}

std::thread_local! {
    /// Region raw handle <-> DM-facing compact slot. See the module docs
    /// above.
    pub(crate) static REGION_SLOTS: std::cell::RefCell<SlotTable> = std::cell::RefCell::default();
}

/// The pipe region a compacted DM-facing `slot` names, or `None` once it
/// has been retired.
pub(crate) fn region_of_slot(slot: u32) -> Option<RegionId<Pipes>> {
    let raw = REGION_SLOTS.with(|s| s.borrow().raw_of(slot))?;
    RawHandle::from_bits(raw).map(RegionId::from_raw)
}

std::thread_local! {
    /// The DM `/datum/gas_reaction` for each reaction id (the registry,
    /// `vg_gas::gate`, holds only its requirements). Reactions run in DM
    /// (`react_by_id`'s callback), so the live references are FFI state.
    static REACTION_VALUES: std::cell::RefCell<std::collections::HashMap<u64, ByondValue>> =
        std::cell::RefCell::default();
}

/// Reaction callback return bits (`/datum/gas_reaction/proc/react`).
const STOP_REACTIONS: u32 = 0b10;

/// Runs a reaction by id, calling back into the live `/datum/gas_reaction`
/// cached by [`load_reactions`].
///
/// # Errors
/// If the reaction itself has a runtime, or `id` names no cached reaction.
fn react_by_id(id: u64, src: ByondValue, holder: ByondValue) -> Result<ByondValue> {
    REACTION_VALUES.with_borrow(|r| {
        let reaction = r.get(&id).ok_or_else(|| eyre!("Reaction with invalid id"))?;
        reaction.call_id(byond_string!("react"), &[src, holder]).wrap_err("calling byond side react in react_by_id")
    })
}

/// Reads DM's `SSair.gas_reactions` into the registry, highest priority
/// first, caching each live reaction reference for [`react_by_id`].
fn load_reactions() -> Result<()> {
    let gas_reactions = ByondValue::new_global_ref()
        .read_var_id(byond_string!("SSair"))
        .wrap_err("load_reactions: couldn't read global SSair")?
        .read_var_id(byond_string!("gas_reactions"))
        .wrap_err("load_reactions: SSair has no gas_reactions var")?;
    let mut table: Vec<(f32, Requirement)> = Vec::new();
    for (reaction, _) in gas_reactions.iter().wrap_err("load_reactions: SSair.gas_reactions is not a list")? {
        let priority = reaction.read_number_id(byond_string!("priority")).map_err(|_| eyre!("Reaction priority must be a number!"))?;
        let string_id = reaction.read_string_id(byond_string!("id")).map_err(|_| eyre!("Reaction id must be a string!"))?;
        let id = {
            use std::hash::{Hash, Hasher};
            let mut state = rustc_hash::FxHasher::default();
            string_id.as_bytes().hash(&mut state);
            state.finish()
        };
        let Some(reqs) = reaction.read_var_id(byond_string!("min_requirements")).ok().filter(ByondValue::is_list) else {
            return Err(eyre!("Reaction {string_id} doesn't have a gas requirements list!"));
        };
        let read = |key: &str| reqs.read_list_index(key).ok().and_then(|v| v.get_number().ok());
        let gases = (0..gas::GAS_COUNT)
            .filter_map(|i| Some((i, reqs.read_list_index(gas::gas_path(i)?).and_then(|v| v.get_number()).ok()?)))
            .collect();
        if table.iter().any(|(p, _)| *p == priority) {
            let sender = auxcallback::byond_callback_sender();
            drop(sender.try_send(Box::new(move || Err(eyre!("Duplicate reaction priority {priority}, this reaction will be ignored!")))));
            continue;
        }
        REACTION_VALUES.with_borrow_mut(|r| r.insert(id, reaction));
        table.push((priority, Requirement { id, min_temp: read("TEMP"), max_temp: read("MAX_TEMP"), min_energy: read("ENER"), min_fire: read("FIRE_REAGENTS"), gases }));
    }
    table.sort_by(|a, b| b.0.total_cmp(&a.0));
    vg_gas::gate::install_reactions(table.into_iter().map(|(_, r)| r).collect());
    Ok(())
}

/// Registers gases, and get reaction infos for auxmos, only call when ssair is initing.
#[auxmacros::bind("/proc/auxtools_atmos_init")]
fn hook_init(gas_data: ByondValue) -> Result<ByondValue> {
    let data = gas_data.read_var_id(byond_string!("datums"))?;
    let mut gases: Vec<(usize, GasType)> = Vec::new();
    for (_, gas_datum) in data.iter()? {
        let path = gas_datum.read_string_id(byond_string!("id"))?;
        let idx = gas::gas_id_for_path(&path).ok_or_else(|| eyre!("{path} has no ID in verdigris gas/ids.rs"))?;
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        if let Ok(dm_idx) = gas_datum.read_number_id(byond_string!("idx"))
            && dm_idx as usize != idx
        {
            bail!("{path}: DM idx {dm_idx} disagrees with GAS_PATHS ID {idx}");
        }
        let specific_heat = gas_datum.read_number_id(byond_string!("specific_heat"))?;
        if specific_heat != vg_gas::cell::SPECIFIC_HEATS[idx] {
            bail!("{path} has specific_heat {specific_heat} in DM but {} in verdigris cell.rs SPECIFIC_HEATS", vg_gas::cell::SPECIFIC_HEATS[idx]);
        }
        let number = |var| gas_datum.read_number_id(var);
        let fire = if let Ok(temperature) = number(byond_string!("oxidation_temperature")) {
            Fire::Oxidizer { temperature, power: number(byond_string!("oxidation_rate"))? }
        } else if let Ok(temperature) = number(byond_string!("fire_temperature")) {
            Fire::Fuel { temperature, burn_rate: number(byond_string!("fire_burn_rate"))? }
        } else {
            Fire::None
        };
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let flags = number(byond_string!("flags")).unwrap_or_default() as u32;
        let entry = GasType {
            id: path.into_boxed_str(),
            flags,
            molar_mass: number(byond_string!("molar_mass")).unwrap_or_default(),
            visible: number(byond_string!("moles_visible")).ok(),
            fire,
        };
        gases.push((idx, entry));
    }
    gases.sort_by_key(|g| g.0);
    if gases.iter().map(|g| g.0).ne(0..gas::GAS_COUNT) {
        bail!("gas registry must hold every GAS_PATHS entry exactly once ({} of {})", gases.len(), gas::GAS_COUNT);
    }
    vg_gas::gate::install_gases(gases.into_iter().map(|g| g.1).collect());
    load_reactions()?;
    Ok(true.into())
}

/// For updating reaction informations for auxmos, only call this when it is changed.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxtools_update_reactions")]
fn update_reactions() -> Result<ByondValue> {
    load_reactions()?;
    Ok(true.into())
}

/// Args: (holder). Runs all reactions on this gas mixture. Holder is used by the reactions, and can be any arbitrary datum or null.
#[auxmacros::bind("/datum/gas_mixture/proc/react")]
fn react_hook(src: ByondValue, holder: ByondValue) -> Result<ByondValue> {
    let mut ret = 0;
    for reaction in with_mix(&src, |mix| Ok(mix.all_reactable()))? {
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        {
            ret |= react_by_id(reaction, src, holder)?.get_number().unwrap_or_default() as u32;
        }
        if ret & STOP_REACTIONS != 0 {
            break;
        }
    }
    #[allow(clippy::cast_precision_loss)]
    Ok((ret as f32).into())
}

/// The turf a gas field cell index names. `GasEvent`s carry a bare cell
/// index (the typed-event wire is plain numbers only); `on_gas_cell_*`
/// handlers call this once to resolve it.
#[auxmacros::bind("/proc/vg_turf_of")]
fn turf_of(cell: ByondValue) -> Result<ByondValue> {
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let c = cell.get_number()? as u32;
    Ok(ByondValue::new_ref(ValueType::Turf, c))
}

// --- Turf gas: the `TurfGas` field on the shared World ----------------------
//
// Every turf's gas is one cell of the `TurfGas` field (`rust_architecture.md`
// §8.5 step 6), on the world's one grid; its air-block masks are the grid's
// `BlockKind::Air` layer and its z links the grid's. The gas laws turn
// the field's state into typed events (`GasEvent`), which reach DM through
// `vg_drain_events()` like every other domain's.

/// Seconds of gas simulated per frame (`SSvg`'s `wait`, the world's `dt`).
const FRAME_DT: f32 = 0.5;
/// Sub-step cap per frame.
const MAX_SUBSTEPS: u32 = 16;

/// Every face a mask can block (`NORTH|SOUTH|EAST|WEST|UP|DOWN`).
/// @dm-define AIR_BLOCK_ALL
pub const AIR_BLOCK_ALL: u8 = 63;

/// Mask argument meaning "keep the mask Rust already has for this turf"
/// (any negative mask does).
/// @dm-define AIR_BLOCK_KEEP
#[allow(dead_code)] // read by DM only, through the generated define
pub const AIR_BLOCK_KEEP: i32 = -1;

/// Registration flag DM passes for a simulated turf.
/// @dm-define SIMULATION_ANY
#[allow(dead_code)] // read by DM only, through the generated define
pub const DM_SIMULATION_ANY: u8 = 3;

thread_local! {
    static TURF: Cell<Option<FieldKey<TurfGas>>> = const { Cell::new(None) };
}

/// Registers turf gas: the field, its watches and its laws
/// (`crate::world::register`).
pub(crate) fn register(b: &mut WorldBuilder) -> FieldKey<TurfGas> {
    let key = b.add_field::<TurfGas>(FieldConfig { dt: FRAME_DT, max_substeps: MAX_SUBSTEPS });
    b.watch_field(key);
    let _ = b.add_law::<CellReactionReadyLaw>();
    let _ = b.add_law::<CellVisualChangeLaw>();
    let _ = b.add_law::<SpacewindLaw>();
    key
}

/// Keeps the field key and installs the gas bridges once the world is built
/// (`crate::world::build`): a rebuilt world starts with no mixtures.
pub(crate) fn install(key: FieldKey<TurfGas>) {
    TURF.with(|t| t.set(Some(key)));
    mix::reset();
}

pub(crate) fn turf_key() -> Result<FieldKey<TurfGas>> {
    TURF.with(Cell::get).ok_or_else(|| eyre!("turf gas field not installed"))
}

fn geom_of(w: &World, key: FieldKey<TurfGas>, cell: u32) -> Geom {
    w.sim().port_ref(key.geometry).read(cell).unwrap_or_default()
}

/// A turf cell's gas and geometry as DM sees them now.
pub(crate) fn turf_read(w: &World, key: FieldKey<TurfGas>, cell: u32) -> Option<(GasCell, Geom)> {
    let g = w.sim().port_ref(key.geometry).read(cell)?;
    Some((w.read_cell(key, cell)?, g))
}

/// Whether `cell` is inside the grid.
fn contains(w: &World, cell: u32) -> bool {
    w.grid().is_ok_and(|g| cell < g.dims().layer_len() * g.dims().max_z())
}

/// The neighbour across `face` if air crosses it: both cells in the field,
/// neither blocking the shared face, and the levels linked for a vertical
/// face.
fn open(w: &World, key: FieldKey<TurfGas>, cell: u32, face: Face) -> Option<u32> {
    if !geom_of(w, key, cell).is_node() {
        return None;
    }
    let nb = w.grid().ok()?.open_neighbor(BlockKind::Air, cell, face)?;
    geom_of(w, key, nb).is_node().then_some(nb)
}

fn open_neighbors(w: &World, key: FieldKey<TurfGas>, cell: u32) -> Vec<u32> {
    Face::ALL.into_iter().filter_map(|f| open(w, key, cell, f)).collect()
}

fn set_mask(w: &mut World, cell: u32, mask: Option<u8>) {
    if let Some(m) = mask {
        let _ = w.edit_grid(|g| g.set_blocked(BlockKind::Air, cell, Dir(m & AIR_BLOCK_ALL)));
    }
}

/// Puts `value` into `cell` with its geometry (`reservoir`: space and
/// planets) and air-block mask (`None`: keep the current one).
fn register_cell(w: &mut World, key: FieldKey<TurfGas>, cell: u32, mut value: GasCell, volume: f32, reservoir: bool, mask: Option<u8>) {
    let volume = if volume > 0.0 { volume } else { CELL_VOLUME };
    value.refresh_in(volume);
    let _ = w.sim_mut().port(key.cells).put(cell, value);
    let geom = Geom { capacity: volume, blocked: Dir::NONE, reservoir };
    if geom_of(w, key, cell) != geom {
        let _ = w.sim_mut().port(key.geometry).put(cell, geom);
    }
    set_mask(w, cell, mask);
}

/// Drops a cell from the field (it became a wall, or its turf went away).
fn unregister_cell(w: &mut World, key: FieldKey<TurfGas>, cell: u32) {
    if geom_of(w, key, cell) != Geom::default() {
        let _ = w.sim_mut().port(key.geometry).put(cell, Geom::default());
    }
    if w.read_cell(key, cell) != Some(GasCell::default()) {
        let _ = w.sim_mut().port(key.cells).put(cell, GasCell::default());
    }
}

/// A turf cell's gas as a pipe device's side (`crate::pipes`' vents and
/// scrubbers): its gas and volume.
pub(crate) fn turf_device_probe(w: &World, cell: u32) -> Option<(PipeGas, f64)> {
    let (c, g) = turf_read(w, turf_key().ok()?, cell)?;
    let volume = if g.capacity > 0.0 { g.capacity } else { CELL_VOLUME };
    let mix = mix::mixture_of_cell(&c, volume);
    Some((PipeGas::from_amounts(&mix::amounts_of(&mix), mix.get_temperature()), f64::from(volume)))
}

/// Applies a device step's result to turf `cell`: the difference from what
/// [`turf_device_probe`] read, as one command.
pub(crate) fn turf_device_apply(w: &mut World, cell: u32, before: &PipeGas, after: &PipeGas) {
    let Ok(key) = turf_key() else { return };
    let (b, a) = (before.amounts(), after.amounts());
    let mut d = [0.0f32; Q];
    for (o, (x, y)) in d.iter_mut().zip(a.iter().zip(b)) {
        *o = x - y;
    }
    if d.iter().any(|v| *v != 0.0) {
        let _ = w.submit_cell(key, cell, GasCmd::Delta(d));
    }
}

/// Args: (links). One entry per z-level: the `UP`/`DOWN` bits of the levels
/// air may cross into. Vertical faces open only between linked levels.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_set_z_links")]
fn set_z_links(links: ByondValue) -> Result<ByondValue> {
    // get_list_values, not iter(): iter() indexes the list by each item.
    let links = links.get_list_values()?.iter().map(|v| v.get_number().unwrap_or(0.0) as u8).collect::<Vec<_>>();
    with_world(|w| {
        w.edit_grid(|g| {
            for (z, bits) in (0u32..).zip(links) {
                let up = (bits & Dir::UP.0 != 0).then_some(z + 1);
                let down = if bits & Dir::DOWN.0 != 0 { z.checked_sub(1) } else { None };
                g.set_z_link(z, up, down);
            }
        })
        .map_err(|e| eyre!("{e}"))
    })?;
    Ok(ByondValue::null())
}

fn is_set(value: std::result::Result<f32, byondapi::Error>) -> bool {
    value.is_ok_and(|n| n != 0.0)
}

fn mask_from_value(mask: &ByondValue) -> Option<u8> {
    mask.get_number().ok().filter(|&m| m >= 0.0).map(|m| (m as u8) & AIR_BLOCK_ALL)
}

/// Registers (flag >= 0) or removes (flag < 0) a turf's gas.
///
/// A turf's own `air` datum moves into its field cell (the datum's handle
/// becomes the cell's). Space's shared immutable vacuum stays a main-owned
/// mixture; its cells are reservoirs. Planet turfs are reservoirs that
/// relax back to their atmosphere when DM disturbs them.
fn register_turf(src: ByondValue, flag: i32, mask: Option<u8>) -> Result<()> {
    let cell = src.get_ref()?;
    let key = turf_key()?;
    if !with_world(|w| Ok(contains(w, cell)))? {
        return Ok(());
    }
    let unregister = || with_world(|w| {
        unregister_cell(w, key, cell);
        Ok(())
    });
    if flag < 0 || is_set(src.read_number_id(byond_string!("blocks_air"))) {
        return unregister();
    }
    let Ok(mut air) = src.read_var_id(byond_string!("air")) else {
        return Ok(());
    };
    if air.is_null() {
        return unregister();
    }
    let planet = is_set(src.read_number_id(byond_string!("planetary_atmos")));
    let planet_key = || src.read_string_id(byond_string!("initial_gas_mix")).unwrap_or_default();
    let r = MixRef::of(&air)?;
    if r == MixRef::Turf(cell) {
        // Already this turf's cell: the mask and the planet flag can change.
        return with_world(|w| {
            let (value, geom) = turf_read(w, key, cell).unwrap_or_default();
            if planet != (value.planet > 0) {
                let mut value = value;
                value.planet = if planet { vg_gas::planet::planet_id(&planet_key(), value) } else { 0 };
                register_cell(w, key, cell, value, CELL_VOLUME, planet, mask);
            } else if geom.is_node() {
                set_mask(w, cell, mask);
            } else {
                register_cell(w, key, cell, value, CELL_VOLUME, geom.reservoir, mask);
            }
            Ok(())
        });
    }
    let Some(mix) = mix::load(r) else {
        bail!("turf air has no gas mixture ({r:?})");
    };
    let mut value = mix::cell_of_mixture(&mix);
    if mix.is_immutable() || is_set(src.read_number_id(byond_string!("immutable_atmos"))) {
        value.flags |= vg_gas::cell::flags::IMMUTABLE;
        // Shared vacuum: the datum stays main-owned.
        return with_world(|w| {
            register_cell(w, key, cell, value, mix.volume, true, mask);
            Ok(())
        });
    }
    if planet {
        value.planet = vg_gas::planet::planet_id(&planet_key(), value);
    }
    with_world(|w| {
        register_cell(w, key, cell, value, mix.volume, planet, mask);
        Ok(())
    })?;
    if let MixRef::Main(slot) = r {
        mix::free(slot);
    }
    MixRef::Turf(cell).store(&mut air)?;
    Ok(())
}

/// Args: (flag, mask). Registers (flag >= 0) or removes (flag < 0) this
/// turf's gas and publishes its air-block mask (`AIR_BLOCK_KEEP` keeps the
/// current one). Reads blocks_air, air, immutable_atmos, planetary_atmos and
/// initial_gas_mix.
#[auxmacros::bind("/turf/proc/update_air_ref")]
fn hook_register_turf(src: ByondValue, flag: ByondValue, mask: ByondValue) -> Result<ByondValue> {
    register_turf(src, flag.get_number()? as i32, mask_from_value(&mask))?;
    Ok(ByondValue::null())
}

/// Bulk registration for round start and map loads. Args: (turfs, flag),
/// where `turfs` is an assoc list of turf -> air-block mask.
#[auxmacros::bind("/proc/_auxmos_register_turfs_bulk")]
fn hook_register_turfs_bulk(list: ByondValue, flag: ByondValue) -> Result<ByondValue> {
    let flag = flag.get_number()? as i32;
    for (turf, mask) in list.iter()?.collect::<Vec<_>>() {
        register_turf(turf, flag, mask_from_value(&mask))?;
    }
    Ok(ByondValue::null())
}

/// This turf's gas revision (bumped whenever its gas changes).
#[auxmacros::bind("/turf/proc/air_revision")]
fn hook_air_revision(src: ByondValue) -> Result<ByondValue> {
    let cell = src.get_ref()?;
    let rev = with_world(|w| Ok(turf_read(w, turf_key()?, cell).map_or(0, |(c, _)| c.revision())))?;
    #[allow(clippy::cast_precision_loss)]
    Ok(((rev & 0x00FF_FFFF) as f32).into())
}

fn turf_list(cells: Vec<u32>) -> Result<ByondValue> {
    let items = cells.into_iter().map(|c| ByondValue::new_ref(ValueType::Turf, c)).collect::<Vec<_>>();
    let list = ByondValue::new_list()?;
    list.write_list(&items)?;
    Ok(list)
}

/// Returns: the turfs this turf shares air with (face neighbours only).
#[auxmacros::bind("/proc/atmos_adjacent_turfs")]
fn atmos_adjacent_turfs(turf: ByondValue) -> Result<ByondValue> {
    let cell = turf.get_ref()?;
    turf_list(with_world(|w| Ok(open_neighbors(w, turf_key()?, cell)))?)
}

/// Batched form of `atmos_adjacent_turfs`: a list of lists, one per turf.
#[auxmacros::bind("/proc/atmos_adjacent_turfs_bulk")]
fn atmos_adjacent_turfs_bulk(turfs: ByondValue) -> Result<ByondValue> {
    let cells = turfs.get_list_values()?.iter().map(ByondValue::get_ref).collect::<Result<Vec<_>, _>>()?;
    let lists = with_world(|w| {
        let key = turf_key()?;
        Ok(cells.iter().map(|&c| open_neighbors(w, key, c)).collect::<Vec<_>>())
    })?;
    let out = lists.into_iter().map(turf_list).collect::<Result<Vec<_>>>()?;
    let list = ByondValue::new_list()?;
    list.write_list(&out)?;
    Ok(list)
}

/// Returns: the direction bits (NORTH..DOWN) across which this turf shares air.
#[auxmacros::bind("/proc/atmos_open_dirs")]
fn atmos_open_dirs(turf: ByondValue) -> Result<ByondValue> {
    let cell = turf.get_ref()?;
    let bits = with_world(|w| {
        let key = turf_key()?;
        Ok(Face::ALL.into_iter().filter(|&f| open(w, key, cell, f).is_some()).fold(0u8, |acc, f| acc | f.bit()))
    })?;
    Ok(f32::from(bits).into())
}

/// Diagnostic: list(registered, mask, z-level links, zero-based z).
#[auxmacros::bind("/proc/atmos_cell_info")]
fn atmos_cell_info(turf: ByondValue) -> Result<ByondValue> {
    let cell = turf.get_ref()?;
    let info = with_world(|w| {
        let key = turf_key()?;
        let grid = w.grid().map_err(|e| eyre!("{e}"))?;
        let links = [Face::Up, Face::Down].into_iter().filter(|&f| grid.neighbor(cell, f).is_some()).fold(0u8, |acc, f| acc | f.bit());
        #[allow(clippy::cast_precision_loss)]
        Ok([
            f32::from(u8::from(geom_of(w, key, cell).is_node())),
            f32::from(grid.blocked(BlockKind::Air, cell).0),
            f32::from(links),
            (cell / grid.dims().layer_len()) as f32,
        ])
    })?;
    crate::world::list(info)
}

/// Returns: whether two turfs are face neighbours that share air.
#[auxmacros::bind("/proc/atmos_turfs_share")]
fn atmos_turfs_share(first: ByondValue, second: ByondValue) -> Result<ByondValue> {
    let (a, b) = (first.get_ref()?, second.get_ref()?);
    let shares = with_world(|w| {
        let key = turf_key()?;
        Ok(Face::ALL.into_iter().any(|f| open(w, key, a, f) == Some(b)))
    })?;
    Ok(shares.into())
}

/// Diagnostic invariant for shuttle and atmos tests: the turf's air datum
/// names its field cell (or the shared vacuum), and the cell is in the field.
#[auxmacros::bind("/proc/_auxmos_topology_matches")]
fn topology_matches(src: ByondValue) -> Result<ByondValue> {
    let cell = src.get_ref()?;
    let r = MixRef::of(&src.read_var_id(byond_string!("air"))?).ok();
    let matches = with_world(|w| {
        let Some((value, geom)) = turf_read(w, turf_key()?, cell) else {
            return Ok(false);
        };
        Ok((r == Some(MixRef::Turf(cell)) || value.is_immutable()) && geom.is_node())
    })?;
    Ok(matches.into())
}

fn side(cell: &GasCell, g: Geom) -> Side<'_, GasCell> {
    Side {
        cell,
        capacity: g.capacity,
        inv_capacity: g.inv_capacity(),
        reservoir: g.reservoir,
        share: 1.0 / 6.0,
    }
}

/// Diagnostic: whether the turf's gas is still moving (some open edge is
/// not settled).
#[auxmacros::bind("/turf/proc/auxmos_is_atmos_active")]
fn turf_active_hook(src: ByondValue) -> Result<ByondValue> {
    let cell = src.get_ref()?;
    let active = with_world(|w| {
        let key = turf_key()?;
        let Some((a, ga)) = turf_read(w, key, cell) else {
            return Ok(false);
        };
        if !ga.is_node() || ga.reservoir {
            return Ok(false);
        }
        // Holding air next to vacuum is not settled until it is gone.
        Ok(open_neighbors(w, key, cell)
            .into_iter()
            .any(|nb| turf_read(w, key, nb).is_some_and(|(b, gb)| !TurfGas::settled(side(&a, ga), side(&b, gb)))))
    })?;
    Ok(active.into())
}

/// `list(frames, 0, 0, 0, 0, 0, 0, 0, last frame µs, command backlog,
/// overlay entries, view age, frames skipped, removal shortfall (mol), 0, 0,
/// 0, 0, 0)`: the world's frame metrics in the layout SSair's stat panel,
/// the profiler and the benchmarks read (the zeros were the old gas-only
/// driver's own counters).
#[auxmacros::bind("/proc/gas_stats")]
fn gas_stats() -> Result<ByondValue> {
    let v = with_world(|w| {
        let key = turf_key()?;
        let m = w.sim().metrics();
        let shortfall = w.sim().port_ref(key.cells).pinned().shortfall_total();
        #[allow(clippy::cast_precision_loss, clippy::cast_possible_truncation)]
        Ok([
            w.frame() as f32,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            m.last_frame.as_secs_f32() * 1e6,
            m.command_backlog as f32,
            m.overlay_entries as f32,
            m.view_age_ticks as f32,
            m.dispatches_skipped as f32,
            shortfall as f32,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        ])
    })?;
    crate::world::list(v)
}

/// `list(main mixtures live, main slots, 0, 0, 0, world frames, pending
/// callbacks, 0, 0, 0)` for SSair's stat panel and the benchmarks.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_diagnostics")]
fn auxmos_diagnostics() -> Result<ByondValue> {
    let (live, slots) = mix::counts();
    let frames = with_world(|w| Ok(w.frame()))?;
    #[allow(clippy::cast_precision_loss)]
    crate::world::list([
        live as f32,
        slots as f32,
        0.0,
        0.0,
        0.0,
        frames as f32,
        auxcallback::pending_callbacks() as f32,
        0.0,
        0.0,
        0.0,
    ])
}

/// Test hook: runs `frames` world steps to completion, one after another,
/// deterministically (no wall clock). Their events reach DM through
/// `vg_drain_events()`.
#[auxmacros::bind("/proc/gas_run_frames")]
fn gas_run_frames(frames: ByondValue) -> Result<ByondValue> {
    let n = frames.get_number()?.clamp(0.0, 100_000.0) as u32;
    with_world(|w| {
        for _ in 0..n {
            w.step_blocking();
        }
        Ok(())
    })?;
    Ok(ByondValue::null())
}

// --- Gas handles as a reactor watch domain -----------------------------------

/// Gas as a reactor domain: `REACT_ON` / `REACT_WHEN` on gas handles
/// ([`mix::watch`]).
pub(crate) struct GasDomain;

impl DomainRegistry for GasDomain {
    fn channels(&self) -> Vec<vg_core::channel::ChannelInfo> {
        vg_core::channel::channel_infos::<TurfGas>()
    }

    fn watch(&mut self, sub: Subscriber, lane: Lane, cond: &Cond) -> std::result::Result<(u8, WatchId), String> {
        mix::watch(sub, lane, cond).map_err(|e| e.to_string())
    }

    fn unwatch(&mut self, port: u8, id: WatchId) {
        mix::unwatch(port, id);
    }

    fn take_wakes(&mut self, out: &mut Vec<Wake>) {
        mix::reactor_wakes(out);
    }
}
