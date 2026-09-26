//! Gas FFI that needs live DM state, not just the pure gas registry
//! (`rust_architecture.md` §2, §8.5's "first gas slice"): reactions stay in
//! DM (`AGENTS.md`), so the live `/datum/gas_reaction` reference for each
//! reaction id is inherently FFI state and belongs here, not as a
//! domain-local `thread_local!` (the domain crate holds no global state --
//! `tools/ci/check_rust_core_consolidation.py`'s `thread_local` category).
//! The rest of vg-gas's ~60-bind mixture API still lives in
//! `verdigris/domains/gas/src/lib.rs` pending its own move here
//! (`rust_architecture.md` §8.5 step 6); this module is the first slice.

use byondapi::prelude::*;
use eyre::{eyre, Context, Result};
use vg_core::network::RegionId;
use vg_core::slot::RawHandle;
use vg_gas::gas::constants::ReactionReturn;
use vg_gas::gas::{self, with_mix};
use vg_gas::pipes::Pipes;
use vg_gas::reaction::{Reaction, ReactionIdentifier, ReactionPriority};

// --- Pipe region slot compaction ----------------------------------------
//
// A pipe region's DM-facing handle is a compacted slot, not its raw arena
// bits (which can exceed `vg_gas::world::MixRef::Pipe`'s 21-bit address
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
    /// The DM `/datum/gas_reaction` for each reaction id, keyed by the same
    /// id `vg_gas::gas::types::install_reactions` uses for its pure
    /// registry. Reactions run in DM (`react_by_id`'s callback), so this
    /// table of live references can only live where `byondapi` state
    /// belongs -- the FFI's own per-DLL state, alongside [`crate::world`]'s
    /// `WORLD`.
    static REACTION_VALUES: std::cell::RefCell<std::collections::HashMap<ReactionIdentifier, ByondValue>> =
        std::cell::RefCell::default();
}

/// Runs a reaction given a `ReactionIdentifier`, calling back into the live
/// `/datum/gas_reaction` cached by [`load_reactions`].
///
/// # Errors
/// If the reaction itself has a runtime, or `id` names no cached reaction.
fn react_by_id(id: ReactionIdentifier, src: ByondValue, holder: ByondValue) -> Result<ByondValue> {
    REACTION_VALUES.with_borrow(|r| {
        r.get(&id).map_or_else(
            || Err(eyre!("Reaction with invalid id")),
            |reaction| {
                reaction
                    .call_id(byond_string!("react"), &[src, holder])
                    .wrap_err("calling byond side react in react_by_id")
            },
        )
    })
}

/// Reads DM's `SSair.gas_reactions` into the pure registry
/// (`vg_gas::gas::types::install_reactions`), caching each live reaction
/// reference for [`react_by_id`].
fn load_reactions() -> Result<()> {
    use float_ord::FloatOrd;
    use std::collections::BTreeMap;

    let gas_reactions = ByondValue::new_global_ref()
        .read_var_id(byond_string!("SSair"))
        .wrap_err("load_reactions: couldn't read global SSair")?
        .read_var_id(byond_string!("gas_reactions"))
        .wrap_err("load_reactions: SSair has no gas_reactions var")?;
    let mut cache: BTreeMap<ReactionPriority, Reaction> = BTreeMap::new();
    for (reaction, _) in gas_reactions
        .iter()
        .wrap_err("load_reactions: SSair.gas_reactions is not a list")?
    {
        let priority: ReactionPriority = FloatOrd(
            reaction
                .read_number_id(byond_string!("priority"))
                .map_err(|_| eyre!("Reaction priority must be a number!"))?,
        );
        let string_id = reaction
            .read_string_id(byond_string!("id"))
            .map_err(|_| eyre!("Reaction id must be a string!"))?;
        let id: ReactionIdentifier = {
            use std::hash::{Hash, Hasher};
            let mut state = rustc_hash::FxHasher::default();
            string_id.as_bytes().hash(&mut state);
            state.finish()
        };
        let Some(min_reqs) = reaction
            .read_var_id(byond_string!("min_requirements"))
            .ok()
            .filter(ByondValue::is_list)
        else {
            return Err(eyre!("Reaction {string_id} doesn't have a gas requirements list!"));
        };
        let mut min_gas_reqs: Vec<(gas::GasIDX, f32)> = Vec::new();
        for i in 0..gas::total_num_gases() {
            let Some(path) = gas::gas_path(i) else { continue };
            if let Ok(req_amount) = min_reqs.read_list_index(path).and_then(|v| v.get_number()) {
                min_gas_reqs.push((i, req_amount));
            }
        }
        let read_req = |key: &str| min_reqs.read_list_index(key).ok().and_then(|v| v.get_number().ok());
        let parsed = Reaction::new(
            id,
            priority,
            read_req("TEMP"),
            read_req("MAX_TEMP"),
            read_req("ENER"),
            read_req("FIRE_REAGENTS"),
            min_gas_reqs,
        );
        if cache.contains_key(&parsed.get_priority()) {
            let priority = parsed.get_priority().0;
            let sender = auxcallback::byond_callback_sender();
            drop(sender.try_send(Box::new(move || {
                Err(eyre!("Duplicate reaction priority {priority}, this reaction will be ignored!"))
            })));
            continue;
        }
        REACTION_VALUES.with_borrow_mut(|r| r.insert(id, reaction));
        cache.insert(parsed.get_priority(), parsed);
    }
    gas::install_reactions(cache);
    Ok(())
}

/// Registers gases, and get reaction infos for auxmos, only call when ssair is initing.
#[auxmacros::bind("/proc/auxtools_atmos_init")]
fn hook_init(gas_data: ByondValue) -> Result<ByondValue> {
    use gas::GasType;

    let data = gas_data.read_var_id(byond_string!("datums"))?;
    let gases = data
        .iter()?
        .map(|(_, gas_datum)| {
            let path = gas_datum.read_string_id(byond_string!("id"))?;
            let idx = gas::gas_id_for_path(&path).ok_or_else(|| eyre!("{path} has no ID in verdigris gas/ids.rs"))?;
            if let Ok(dm_idx) = gas_datum.read_number_id(byond_string!("idx")) {
                #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
                if dm_idx as gas::GasIDX != idx {
                    return Err(eyre!("{path}: DM idx {dm_idx} disagrees with GAS_PATHS ID {idx}"));
                }
            }
            let fire_info = if let Ok(temperature) = gas_datum.read_number_id(byond_string!("oxidation_temperature")) {
                gas::FireInfo::Oxidation(gas::OxidationInfo::new(temperature, gas_datum.read_number_id(byond_string!("oxidation_rate"))?))
            } else if let Ok(temperature) = gas_datum.read_number_id(byond_string!("fire_temperature")) {
                gas::FireInfo::Fuel(gas::FuelInfo::new(temperature, gas_datum.read_number_id(byond_string!("fire_burn_rate"))?))
            } else {
                gas::FireInfo::None
            };
            let fire_products = gas_datum.read_var_id(byond_string!("fire_products")).ok().and_then(|product_info| {
                if product_info.is_list() {
                    Some(gas::FireProductInfo::Generic(
                        product_info
                            .iter()
                            .ok()?
                            .filter_map(|(k, v)| k.get_string().ok().and_then(|s| v.get_number().ok().map(|amt| (gas::GasRef::Deferred(s), amt))))
                            .collect(),
                    ))
                } else if product_info.is_num() {
                    Some(gas::FireProductInfo::Plasma)
                } else {
                    None
                }
            });
            Ok(GasType::new(
                idx,
                path.clone().into_boxed_str(),
                gas_datum.read_string_id(byond_string!("name"))?.into_boxed_str(),
                gas_datum.read_number_id(byond_string!("flags")).unwrap_or_default() as u32,
                gas_datum.read_number_id(byond_string!("specific_heat"))?,
                gas_datum.read_number_id(byond_string!("molar_mass")).unwrap_or_default(),
                gas_datum.read_number_id(byond_string!("fusion_power")).unwrap_or_default(),
                gas_datum.read_number_id(byond_string!("moles_visible")).ok(),
                gas_datum.read_number_id(byond_string!("enthalpy")).unwrap_or_default(),
                gas_datum.read_number_id(byond_string!("fire_radiation_released")).unwrap_or_default(),
                fire_info,
                fire_products,
            ))
        })
        .collect::<Result<Vec<_>>>()
        .wrap_err("auxtools_atmos_init failed to register gas")?;
    gas::install_gases(gases)?;
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
    let mut ret = ReactionReturn::NO_REACTION;
    let reactions = with_mix(&src, |mix| Ok(mix.all_reactable()))?;
    for reaction in reactions {
        ret |= ReactionReturn::from_bits_truncate(
            react_by_id(reaction, src, holder)?.get_number().unwrap_or_default() as u32,
        );
        if ret.contains(ReactionReturn::STOP_REACTIONS) {
            return Ok((ret.bits() as f32).into());
        }
    }
    Ok((ret.bits() as f32).into())
}
