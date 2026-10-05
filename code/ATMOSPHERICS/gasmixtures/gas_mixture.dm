/*
 * gas_mixture.dm — arena-backed (auxmos) implementation.
 *
 * Gas data no longer lives in a DM assoc list. Each /datum/gas_mixture is a
 * HANDLE into the Rust auxmos arena (index stored in _extools_pointer_gasmixture).
 * All moles/temperature/volume math runs in Rust; the DM procs below are thin
 * routes over the auxmos FFI binds (the generated vg_<hook>(...) procs in code/__defines/verdigris/_bindings.dm),
 * or DM logic layered on top of the arena-backed getters.
 *
 * OPAQUE HANDLE (/tg/ auxmos model): there is NO public temperature/volume var. The
 * Rust arena is the single source of truth. READ via return_temperature()/return_volume()
 * (each crosses the FFI boundary — cache in a local in hot loops); WRITE via
 * heat_set() (code/domains/heat/) / set_volume(). A stale-mirror read is impossible and a raw
 * `GM.temperature = x` is a compile error.
 *
 * Gas identity: gas binds take numeric GAS_ID_* IDs (generated from verdigris
 * gas/ids.rs). Callers may pass a GAS_ID_* number or a /datum/gas type path;
 * every route converts with GAS_IDX(), so no string crosses the FFI.
 *
 * The DM turf-sharing engine (share/archive/temperature_share DM math) is DELETED
 * — auxmos' Rust turf processing replaces it.
 */

GLOBAL_LIST_INIT(meta_gas_info, meta_gas_list()) //see ATMOSPHERICS/gas_types.dm
// Constant per-gas template table. The mixture 'gases' assoc list is gone (moles
// live in the Rust arena), but this cache is still a shared constant table read by
// GAS_TYPE_COUNT / the GAS_2_LIST helpers, so it is kept.
GLOBAL_LIST_INIT(gaslist_cache, init_gaslist_cache()) // ALLOW(cache): constant table computed at init

/proc/init_gaslist_cache()
	var/list/gases = list()
	for(var/id in GLOB.meta_gas_info)
		var/list/cached_gas = new(3)

		gases[id] = cached_gas

		cached_gas[MOLES] = 0
		cached_gas[ARCHIVE] = 0
		cached_gas[GAS_META] = GLOB.meta_gas_info[id]
	return gases

/datum/gas_mixture
	// OPAQUE HANDLE (/tg/ auxmos model). There is deliberately NO public `temperature`
	// or `volume` var — the Rust arena is the single source of truth. Read via
	// return_temperature() / return_volume(); write via set_temperature() / set_volume().
	// This makes a stale-mirror read impossible and a mis-write a COMPILE error. In hot
	// loops, cache the accessor result in a local (e.g. `var/temp = air.return_temperature()`)
	// rather than calling it repeatedly, since each call crosses the FFI boundary.
	/// The last tick this gas mixture shared on. A counter that turfs use to manage activity
	var/last_share = 0
	/// Tells us what reactions have happened in our gasmix. Assoc list of reaction - moles reacted pair.
	var/list/reaction_results
	/// Whether to call garbage_collect() on the sharer during shares, used for immutable mixtures
	var/gc_share = FALSE
	/// When this gas mixture was last touched by pipeline processing
	/// I am sorry
	var/pipeline_cycle = -1
	/// auxmos arena handle: index into the Rust gas-mixture arena, written by
	/// register_gasmixture_hook_ffi (verdigris GasArena::register_mix). Null until
	/// registered. See code/ATMOSPHERICS/README.md.
	var/_extools_pointer_gasmixture
	/// Volume the mixture was created with; read by register_mix to size the
	/// Rust-side mixture at New(). The live volume lives in the arena (return_volume()).
	var/initial_volume = CELL_VOLUME

/datum/gas_mixture/New(volume)
	// Ensure auxmos knows the gas roster before ANY set_moles can run on this
	// mixture. Turf air is parsed during mapload, before SSair.Initialize, so
	// this (idempotent) call is what actually registers gases in practice.
	ensure_auxmos_gas_registry()
	if(!isnull(volume))
		initial_volume = volume
	if(initial_volume <= 0)
		stack_trace("Created a gas mixture with zero volume!")
	// Register the mixture in the Rust arena. Reads initial_volume, writes
	// _extools_pointer_gasmixture.
	vg_register_gasmixture_hook(src)

/// Phase 1 (unbind): frees the Rust arena slot for reuse.
/datum/gas_mixture/lifecycle_unbind()
	. = ..()
	vg_unregister_gasmixture_hook(src)

// Gas mixtures are opaque handles with no post-Destroy cleanup dependency.
// Let BYOND collect them naturally instead of retaining tens of thousands of
// dead turf handles in SSgarbage's five-minute reference-check queue.
/datum/gas_mixture
	destroy_hint = QDEL_HINT_IWILLGC

//gas presence procs — the arena auto-manages gas presence, so the old
//assert/add/garbage_collect family are no-ops kept for caller compatibility.

///assert_gas(gas_id) - NO-OP. The arena auto-creates gases on first write.
/datum/gas_mixture/proc/assert_gas(gas_id)
	return

///assert_gases(args) - NO-OP. The arena auto-manages presence.
/datum/gas_mixture/proc/assert_gases(...)
	return

///add_gas(gas_id) - NO-OP. The arena auto-creates gases on first write.
/datum/gas_mixture/proc/add_gas(gas_id)
	return

///add_gases(args) - NO-OP. The arena auto-manages presence.
/datum/gas_mixture/proc/add_gases(...)
	return

///garbage_collect() - NO-OP. The arena drops empty gases automatically.
/datum/gas_mixture/proc/garbage_collect(list/tocheck)
	return


///joules per kelvin
/datum/gas_mixture/proc/heat_capacity(data = MOLES)
	return vg_heat_cap_hook(src)

/// Same as above except vacuums return HEAT_CAPACITY_VACUUM
/datum/gas_mixture/turf/heat_capacity(data = MOLES)
	. = vg_heat_cap_hook(src)
	if(!.)
		. += HEAT_CAPACITY_VACUUM //we want vacuums in turfs to have the same heat capacity as space

/// Returns the heat capacity of a single gas in the mixture, in J/K.
/datum/gas_mixture/proc/partial_heat_capacity(gas_id)
	return vg_partial_heat_capacity(src, GAS_IDX(gas_id))

/// Calculate moles
/datum/gas_mixture/proc/revision()
	return vg_hook_mix_revision(src)

/// Stable Rust arena ID used for dependency subscriptions.
/datum/gas_mixture/proc/arena_id()
	return _extools_pointer_gasmixture

/// Batched read: one FFI call returns pressure, temperature, volume, total moles,
/// heat capacity and every gas's moles for each mixture in `mixtures` (nulls read
/// as zero). See GAS_READ_* for the layout. Use this instead of calling several
/// getters per mixture in a loop.
/proc/read_gas_mixtures(list/mixtures)
	return vg_read_mixtures(mixtures)

/**
 * A gas dependency watch (code/datums/om/native.dm): `mixture_id` changing
 * in any GAS_DEPENDENCY_* bit of `mask` calls `callback` on the owner as
 * (watch, mixture_id, change_mask, list/observation, observation_index); the
 * observation record (from the mixture id on) is `drain_observations()` in
 * verdigris/ffi/src/gas/mix.rs; it reaches DM as a CHANGED record of the frame
 * (native system).
 */
/datum/native_watch/gas
	var/mixture_id
	var/mask = GAS_DEPENDENCY_ALL
	delivery_source = NATIVE_SRC_GAS_WATCH

/datum/native_watch/gas/register()
	vg_watch_dirty_gas_mixture(mixture_id, handle, mask)
	return TRUE

/datum/native_watch/gas/unregister()
	vg_unwatch_dirty_gas_mixture(handle)

/proc/gas_dependency_watch(datum/owner, mixture_id, mask, callback)
	if(isnull(mixture_id) || !mask)
		return null
	var/datum/native_watch/gas/W = new(owner, callback)
	W.mixture_id = mixture_id
	W.mask = mask
	W.register()
	return W

/datum/gas_mixture/proc/total_moles()
	return vg_total_moles_hook(src)

/// Returns the moles of a single gas in the mixture.
/datum/gas_mixture/proc/get_moles(gas_id)
	return vg_get_moles_hook(src, GAS_IDX(gas_id))

/// Sets the moles of a single gas in the mixture.
/datum/gas_mixture/proc/set_moles(gas_id, amount)
	return vg_set_moles_hook(src, GAS_IDX(gas_id), amount)

/// Adjusts the moles of a single gas by the given (signed) amount.
/datum/gas_mixture/proc/adjust_moles(gas_id, amount)
	return vg_adjust_moles_hook(src, GAS_IDX(gas_id), amount)

/// Returns an assoc list of /datum/gas type path -> moles for every gas present,
/// read in one FFI call (Rust returns a flat id, moles, id, moles, ... list).
/// Iterating it yields the type paths, the same contract the old DM gases[]
/// keys had (meta_gas_info / get_moles all accept type paths).
/datum/gas_mixture/proc/get_gases()
	var/list/flat = vg_get_gases_hook(src)
	. = list()
	var/list/paths = GLOB.gas_path_by_idx
	for(var/i in 1 to length(flat) step 2)
		.[paths[flat[i] + 1]] = flat[i + 1]

/// Checks to see if gas amount exists in mixture.
/datum/gas_mixture/proc/has_gas(gas_id, amount=0)
	return amount < (vg_get_moles_hook(src, GAS_IDX(gas_id)) || 0)

/// Calculate pressure in kilopascals
/datum/gas_mixture/proc/return_pressure()
	return vg_return_pressure_hook(src)

/// Calculate temperature in kelvins
/datum/gas_mixture/proc/return_temperature()
	return vg_return_temperature_hook(src)

/// Calculate volume in liters
/datum/gas_mixture/proc/return_volume()
	return max(0, vg_return_volume_hook(src))

/// Gets the gas visuals for everything in this mixture
/datum/gas_mixture/proc/return_visuals(turf/z_context)
	var/list/output
	var/offset = GET_TURF_PLANE_OFFSET(z_context) + 1
	var/list/cached_gases = get_gases()
	for(var/id in cached_gases)
		if(GLOB.nonoverlaying_gases[id])
			continue
		var/list/gas_meta = GLOB.meta_gas_info[id]
		if(!gas_meta)
			continue
		var/moles = cached_gases[id]
		if(moles <= gas_meta[META_GAS_MOLES_VISIBLE])
			continue
		var/list/gas_overlay = gas_meta[META_GAS_OVERLAY][offset]
		LAZYADD(output, gas_overlay[min(TOTAL_VISIBLE_STATES, CEILING(moles / MOLES_GAS_VISIBLE_STEP, 1))])
	return output

/// Calculate thermal energy in joules
/datum/gas_mixture/proc/thermal_energy()
	return vg_thermal_energy_hook(src)

///Merges all air from giver into self. Does NOT modify giver. Returns: TRUE if we are mutable.
/datum/gas_mixture/proc/merge(datum/gas_mixture/giver)
	if(!giver)
		return FALSE
	. = vg_merge_hook(src, giver)

/// Atomically transfers a mole quantity between two authoritative arena
/// mixtures. This avoids the temporary DM gas datum and the second FFI crossing
/// required by remove()+merge().
/datum/gas_mixture/proc/transfer_to(datum/gas_mixture/other, moles)
	if(!other || other == src || moles <= 0)
		return FALSE
	vg_transfer_hook(src, other, moles)
	return TRUE

// Set the gas specie within the gas mix to a set amount, if there is none it will be created at the target temp
/datum/gas_mixture/proc/set_gas(gas_specie, amount)
	return vg_set_moles_hook(src, GAS_IDX(gas_specie), amount)

/datum/gas_mixture/proc/set_volume(vol)
	return vg_set_volume_hook(src, vol)

/// Add a specific amount of moles to specified gas or add a new gas to the mix
/// amount is added so make it negative to remove
/datum/gas_mixture/proc/adjust_gas(gas, amount)
	return vg_adjust_moles_hook(src, GAS_IDX(gas), QUANTIZE(amount))

/// Add a specific amount of moles to all the gasses present or add a new gas to the mix
///gases_moles is an associative list of gas species to their amount to be added
/datum/gas_mixture/proc/adjust_multiple_gases(list/gases_moles)
	var/list/adjustments = list()
	for(var/gas_specie in gases_moles)
		adjustments += GAS_IDX(gas_specie)
		adjustments += gases_moles[gas_specie]
	if(length(adjustments))
		vg_adjust_multi_hook(arglist(list(src) + adjustments))

/// Modify the gas list as to convert moles of gas species A to gas species B
/// reactant and product are the gas species to convert and conversion_amount is the amount to be converted
/datum/gas_mixture/proc/convert_gas(datum/gas/reactant, datum/gas/product, conversion_amount)
	var/amount = QUANTIZE(conversion_amount)
	vg_adjust_moles_hook(src, GAS_IDX(reactant), -amount)
	vg_adjust_moles_hook(src, GAS_IDX(product), amount)

///Proportionally removes amount of gas from the gas_mixture.
///Returns: gas_mixture with the gases removed
/datum/gas_mixture/proc/remove(amount)
	var/sum = vg_total_moles_hook(src)
	amount = min(amount, sum) //Can not take more air than tile has!
	if(amount <= 0)
		return null
	var/datum/gas_mixture/removed = new type(return_volume())
	vg_remove_hook(src, removed, amount)
	return removed

///Proportionally removes ratio of gas from the gas_mixture.
///Returns: gas_mixture with the gases removed
/datum/gas_mixture/proc/remove_ratio(ratio)
	var/datum/gas_mixture/removed = new type(return_volume())
	if(ratio <= 0)
		return removed
	ratio = min(ratio, 1)
	vg_remove_ratio_hook(src, removed, ratio)
	return removed

///Removes an amount of a specific gas from the gas_mixture.
///Returns: gas_mixture with the gas removed
/datum/gas_mixture/proc/remove_specific(gas_id, amount)
	amount = min(amount, vg_get_moles_hook(src, GAS_IDX(gas_id)))
	if(amount <= 0)
		return null
	var/datum/gas_mixture/removed = new type
	heat_set(removed, return_temperature())
	vg_set_moles_hook(removed, GAS_IDX(gas_id), amount)
	vg_adjust_moles_hook(src, GAS_IDX(gas_id), -amount)
	return removed

/datum/gas_mixture/proc/remove_specific_ratio(gas_id, ratio)
	if(ratio <= 0)
		return null
	ratio = min(ratio, 1)
	var/datum/gas_mixture/removed = new type
	heat_set(removed, return_temperature())
	var/amount = QUANTIZE(vg_get_moles_hook(src, GAS_IDX(gas_id)) * ratio)
	vg_set_moles_hook(removed, GAS_IDX(gas_id), amount)
	vg_adjust_moles_hook(src, GAS_IDX(gas_id), -amount)
	return removed

///Distributes the contents of two mixes equally between themselves
//Returns: bool indicating whether gases moved between the two mixes
/datum/gas_mixture/proc/equalize(datum/gas_mixture/other)
	return vg_equalize_with_hook(src, other)

///Creates new, identical gas mixture
///Returns: duplicate gas mixture
/datum/gas_mixture/proc/copy()
	var/datum/gas_mixture/copy = new type
	vg_copy_from_hook(copy, src)
	return copy

///Copies variables from sample
///Returns: TRUE if we are mutable, FALSE otherwise
/datum/gas_mixture/proc/copy_from(datum/gas_mixture/sample)
	vg_copy_from_hook(src, sample)
	return TRUE

///Copies variables from sample, moles multiplicated by partial
///Returns: TRUE if we are mutable, FALSE otherwise
/datum/gas_mixture/proc/copy_from_ratio(datum/gas_mixture/sample, partial = 1)
	vg_copy_from_hook(src, sample)
	if(partial != 1)
		vg_multiply_hook(src, partial)
	return TRUE

///Compares sample to self to see if within acceptable ranges that group processing may be enabled
///Returns: TRUE if the mixtures differ enough to warrant processing, FALSE otherwise
/datum/gas_mixture/proc/compare(datum/gas_mixture/sample)
	return vg_compare_hook(src, sample)

///Performs various reactions such as combustion and fabrication
/// Runs DM gas reactions against this mixture. Reactions stay in DM (user
/// decision); this dispatcher checks each /datum/gas_reaction's requirements via
/// arena getters and calls its react() (whose body was ported onto arena
/// accessors). auxmos' own reaction engine is NOT used (SSair.gas_reactions is
/// emptied during auxtools_atmos_init so hook_init doesn't parse it).
/datum/gas_mixture/proc/react(datum/holder)
	. = NO_REACTION
	var/list/reactions = SSair.gas_reactions
	if(!length(reactions))
		return
	// One batched read for the temperature and every gas the requirements name.
	var/list/readings = vg_read_mixtures(list(src))
	var/temp = readings[GAS_READ_TEMPERATURE]
	// Hypernoblium suppresses all reactions (parity with the old react()).
	if(readings[GAS_READ_MOLES(GAS_ID_HYPERNOBLIUM)] >= REACTION_OPPRESSION_THRESHOLD && temp > REACTION_OPPRESSION_MIN_TEMP)
		return STOP_REACTIONS
	var/results_reset = FALSE
	for(var/datum/gas_reaction/reaction as anything in reactions)
		var/list/reqs = reaction.requirements
		if(!reqs)
			continue
		if((reqs["MIN_TEMP"] && temp < reqs["MIN_TEMP"]) || (reqs["MAX_TEMP"] && temp > reqs["MAX_TEMP"]))
			continue
		var/satisfied = TRUE
		for(var/id in reqs)
			if(id == "MIN_TEMP" || id == "MAX_TEMP")
				continue
			if(readings[GAS_READ_MOLES(GAS_IDX(id))] < reqs[id])
				satisfied = FALSE
				break
		if(!satisfied)
			continue
		// Reset reaction_results once, only when a reaction actually fires, so it
		// can't accumulate across ticks on a persistent (turf) mixture without
		// allocating a list on every no-op tick. A fresh list (not LAZYCLEARLIST,
		// which nulls it here) — the reactions below index it via SET_REACTION_RESULTS.
		if(!results_reset)
			reaction_results = list()
			results_reset = TRUE
		. |= reaction.react(src, holder)
		if(. & STOP_REACTIONS)
			return
		// The reaction changed the mixture: later requirement checks see the new
		// moles (the temperature stays the one sampled at the start, as before).
		readings = vg_read_mixtures(list(src))

/**
 * Returns the partial pressure of the gas in the breath based on BREATH_VOLUME
 * eg:
 * Plas_PP = get_breath_partial_pressure(gas_mixture.get_moles(/datum/gas/plasma))
 * O2_PP = get_breath_partial_pressure(gas_mixture.get_moles(/datum/gas/oxygen))
 * get_breath_partial_pressure(gas_mole_count) --> PV = nRT, P = nRT/V
 *
 * 10/20*5 = 2.5
 * 10 = 2.5/5*20
 */
/datum/gas_mixture/proc/get_breath_partial_pressure(gas_mole_count)
	return (gas_mole_count * R_IDEAL_GAS_EQUATION * return_temperature()) / BREATH_VOLUME

/// Moves gas from src into `sink` until the sink reaches `target_kpa`, capped at `max_moles`
/// (null: no cap), only the gases in `gases_mask` (a 1 << gas id bitset, 0: all). One Rust
/// solve of the ideal-gas mixing equation; returns the moles moved.
/datum/gas_mixture/proc/transfer_to_pressure(datum/gas_mixture/sink, target_kpa, max_moles = null, gases_mask = 0)
	return vg_transfer_to_pressure(src, sink, target_kpa, max_moles, gases_mask)

// /datum/gas_mixture/proc/electrolyze removed. /tg/'s electrolyzer
// machinery (which is the only caller) isn't ported to DQ; the proc had no
// live callers, and keeping it required /datum/electrolyzer_reaction +
// GLOB.electrolyzer_reactions stubs in tg_infra_compat. Re-add this proc
// when porting /tg/ electrolyzer machinery.

/// Convert a gas mixture to a string (ie. "o2=22;n2=82;TEMP=180")
/// Rounds all temperature and gases to 0.01 and skips any gases less than that amount
/datum/gas_mixture/proc/to_string()
	var/rounded_temp = round(return_temperature(), 0.01)

	var/list/atmos_contents = list()
	var/temperature_str = "TEMP=[num2text(rounded_temp)]"

	var/list/cached_gases = get_gases()
	if(!length(cached_gases) || total_moles() < 0.01)
		return temperature_str

	for(var/gas_path in cached_gases)
		var/gas_moles = round(cached_gases[gas_path], 0.01)
		if(gas_moles < 0.01)
			continue
		var/list/gas_meta = GLOB.meta_gas_info[gas_path]
		var/gas_id = gas_meta ? gas_meta[META_GAS_ID] : "[gas_path]"
		atmos_contents += "[gas_id]=[num2text(gas_moles)]"

	atmos_contents += temperature_str
	return atmos_contents.Join(";")
