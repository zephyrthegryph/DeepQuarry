/turf
	// thermal_conductivity and heat_capacity are already declared on
	// CHOMP's /turf (code/game/turfs/turf.dm:30-31) with values 0.05 and 1.
	// LINDA wanted heat_capacity = INFINITY (opt-in heating); CHOMP defaults
	// matter (most turfs are heat-able). Don't redeclare — runtime will use
	// CHOMP's value (1) for all turfs, which means turfs CAN be heated by gas.
	// This is closer to /tg/'s opt-OUT behavior anyway.
	///Archived version of the temperature on a turf
	var/temperature_archived
	///All currently stored conductivities changes
	var/list/thermal_conductivities

	///list of turfs adjacent to us that air can flow onto
	var/list/atmos_adjacent_turfs
	///bitfield of dirs in which we are superconducitng
	var/atmos_supeconductivity = NONE

	///used to determine whether we should archive
	var/archived_cycle = 0
	var/current_cycle = 0

	/**
	 * used for mapping and for breathing while in walls (because that's a thing that needs to be accounted for...)
	 * string parsed by /datum/gas/proc/copy_from_turf
	 * approximation of MOLES_O2STANDARD and MOLES_N2STANDARD pending byond allowing constant expressions to be embedded in constant strings
	 * If someone will place 0 of some gas there, SHIT WILL BREAK. Do not do that.
	**/
	var/initial_gas_mix = OPENTURF_DEFAULT_ATMOS

/turf/open
	//used for spacewind
	///Pressure difference between two turfs
	var/pressure_difference = 0
	///Where the difference come from (from higher pressure to lower pressure)
	var/pressure_direction = 0
	/// katmos target turf ref, written/read by the Rust equalize pass
	/// (turf.pressure_specific_target). Declared so the auxmos read/write_var_id
	/// calls don't panic (NonExistentString); DM never sets it directly.
	var/pressure_specific_target

	/// Excited-group tracking moved to the Rust arena. This var is retained
	/// (untyped) only so lingering external readers (e.g. LINDA_fire hotspot
	/// processing) still resolve; the DM engine no longer maintains it.
	var/excited_group
	///Are we active? Retained for legacy readers; auxmos owns activity now.
	var/excited = FALSE
	///Our gas mix
	var/datum/gas_mixture/air

	///If there is an active hotspot on us store a reference to it here
	var/obj/effect/hotspot/active_hotspot
	/// air will slowly revert to initial_gas_mix
	var/planetary_atmos = FALSE
	/// once our paired turfs are finished with all other shares, do one 100% share
	/// exists so things like space can ask to take 100% of a tile's gas
	var/run_later = FALSE

	///gas IDs of current active gas overlays
	var/list/atmos_overlay_types
	var/significant_share_ticker = 0
	///the cooldown on playing a fire starting sound each time a tile is ignited
	COOLDOWN_DECLARE(fire_puff_cooldown)
	#ifdef TRACK_MAX_SHARE
	var/max_share = 0
	#endif

/turf/open/Initialize(mapload)
	if(!blocks_air)
		air = create_gas_mixture()
		if(planetary_atmos)
			if(!SSair.planetary[initial_gas_mix])
				var/datum/gas_mixture/immutable/planetary/mix = new
				mix.parse_string_immutable(initial_gas_mix)
				SSair.planetary[initial_gas_mix] = mix
	. = ..()
	// Register this turf's air ref in the Rust arena. During roundstart mapload
	// SSair isn't initialised yet — setup_allturfs/Initalize_Atmos registers every
	// turf then. For turfs created AFTER SSair init (ChangeTurf, runtime spawns)
	// we register here so auxmos picks them up. air_update_turf (called by the
	// ChangeTurf path) then rebuilds + pushes adjacency.
	if(SSair.initialized)
		update_air_ref(0)

/turf/open/Destroy()
	if(active_hotspot)
		QDEL_NULL(active_hotspot)
	// Unregister src's air ref from the Rust arena BEFORE clearing adjacency so the
	// next SSair tick doesn't process this dying turf. ChangeTurf-style replacement
	// swaps a new turf into the same world coords; unregistering here drops the old
	// slot cleanly (remove_from_active -> update_air_ref(-1)).
	if(SSair)
		SSair.remove_from_active(src)
	// Clear src out of each neighbour's atmos_adjacent_turfs, push the corrected
	// adjacency to the arena, and re-register the neighbour so auxmos reconsiders
	// it now that a bordering turf is gone.
	for(var/turf/near_turf as anything in atmos_adjacent_turfs)
		if(near_turf.atmos_adjacent_turfs)
			near_turf.atmos_adjacent_turfs -= src
			UNSETEMPTY(near_turf.atmos_adjacent_turfs)
		if(SSair?.initialized)
			near_turf.__update_auxtools_turf_adjacency_info()
		SSair.add_to_active(near_turf)
	atmos_adjacent_turfs = null
	return ..()

/////////////////GAS MIXTURE PROCS///////////////////

///Copies all gas info from the turf into a new gas_mixture, along with our temperature
///Returns the created gas_mixture
/turf/proc/create_gas_mixture()
	var/datum/gas_mixture/mix = SSair.parse_gas_string(initial_gas_mix, /datum/gas_mixture/turf)

	//acounts for changes in temperature
	var/turf/parent = parent_type
	if(temperature != initial(temperature) || temperature != initial(parent.temperature))
		mix.set_temperature(temperature) // arena-backed write; refreshes the DM mirror

	return mix

/turf/open/assume_air(datum/gas_mixture/giver) //use this for machines to adjust air
	if(!giver)
		return FALSE
	air.merge(giver)
	update_visuals()
	// air_update_turf now (re)pushes arena adjacency both directions even with
	// update=FALSE, so a turf that just received gas has live neighbour edges and
	// auxmos will spread the gas out (critical on runtime-built turfs whose edges
	// were never pushed). No need for the expensive update=TRUE geometry rescan.
	air_update_turf(FALSE, FALSE)
	return TRUE

/turf/open/remove_air(amount)
	var/datum/gas_mixture/ours = return_air()
	var/datum/gas_mixture/removed = ours.remove(amount)
	update_visuals()
	air_update_turf(FALSE, FALSE)
	return removed

/turf/open/proc/copy_air_with_tile(turf/open/target_turf)
	if(istype(target_turf))
		air.copy_from(target_turf.air)

/turf/open/proc/copy_air(datum/gas_mixture/copy)
	if(copy)
		air.copy_from(copy)

/turf/return_air()
	RETURN_TYPE(/datum/gas_mixture)
	var/datum/gas_mixture/copied_mixture = create_gas_mixture()
	return copied_mixture

/turf/open/return_air()
	RETURN_TYPE(/datum/gas_mixture)
	// After the /turf/simulated → /turf/open reparent, walls / dense / vacuum tiles
	// are /turf/open subtypes with air = null. Stock /tg/ never hits this (walls are
	// a separate /turf/closed type with no return_air), so its ~260 return_air()
	// callers assume a non-null mixture and deref it directly — every one of them is
	// a latent null-crash on an airless tile (the external dock airlock sensors hit
	// it every tick). Fall back to the base turf's non-null empty (vacuum) mixture
	// for airless tiles instead of returning null: consumers read 0-pressure vacuum,
	// which is the correct answer for a wall/space tile, rather than runtiming. The
	// atmos hot path (share/process_cell) uses .air directly and is unaffected.
	return air || ..()

/turf/open/return_analyzable_air()
	return return_air()

// moved to /turf/simulated because to_be_destroyed/max_fire_temperature_sustained
// are declared on CHOMP's /turf/simulated (simulated.dm:13-14), not the base /turf.
// Non-simulated turfs (space, unsimulated walls) inherit the no-op base.
/turf/should_atmos_process(datum/gas_mixture/air, exposed_temperature)
	return FALSE

/turf/simulated/should_atmos_process(datum/gas_mixture/air, exposed_temperature)
	return (exposed_temperature >= heat_capacity || to_be_destroyed)

/turf/atmos_expose(datum/gas_mixture/air, exposed_temperature)
	return

/turf/simulated/atmos_expose(datum/gas_mixture/air, exposed_temperature)
	if(exposed_temperature >= heat_capacity)
		to_be_destroyed = TRUE
	if(to_be_destroyed && exposed_temperature >= max_fire_temperature_sustained)
		max_fire_temperature_sustained = min(exposed_temperature, max_fire_temperature_sustained + heat_capacity / 4)
	if(to_be_destroyed && !changing_turf)
		burn_turf()

/turf/proc/burn_turf()
	return

/turf/simulated/burn_turf()
	burn_tile()
	var/chance_of_deletion
	if (heat_capacity) //beware of division by zero
		chance_of_deletion = max_fire_temperature_sustained / heat_capacity * 8
	else
		chance_of_deletion = 100
	if(prob(chance_of_deletion))
		Melt()
		max_fire_temperature_sustained = 0
	else
		to_be_destroyed = FALSE

/turf/temperature_expose(datum/gas_mixture/air, exposed_temperature)
	atmos_expose(air, exposed_temperature)

/turf/open/temperature_expose(datum/gas_mixture/air, exposed_temperature)
	SEND_SIGNAL(src, COMSIG_TURF_EXPOSE, air, exposed_temperature)
	// was calling a no-op check_atmos_process() shim that swallowed
	// the work; replaced with the direct should-then-expose check. (/tg/'s
	// original used a /datum/element to dispatch; we skip the element layer.)
	if(should_atmos_process(air, exposed_temperature))
		atmos_expose(air, exposed_temperature)

// /turf/proc/archive + /turf/open/archive removed — turf FDM archiving is Rust-side
// now (auxmos snapshots inside process_turfs). temperature_archived is still
// declared on /turf for legacy readers but is no longer maintained by an archive
// pass; nothing in the (deleted) DM turf engine reads it anymore.

/////////////////////////GAS OVERLAYS//////////////////////////////


/**
 * Recompute this turf's gas overlays from its (arena-backed) air contents and
 * apply the diff to vis_contents. Called directly by ~56 DM atmos callers
 * (pumps, scrubbers, canisters, vents) after they mutate a turf's air. The Rust
 * turf-processing path does NOT call this — it calls set_visuals() with a
 * precomputed overlay list (see below).
 */
/turf/open/proc/update_visuals()
	if(!air) // airless / wall tile — clear any lingering overlays
		set_visuals(null)
		return

	// Moles now live in the arena; get_gases() returns id -> bare mole count (NOT
	// the old list(MOLES,ARCHIVE,GAS_META)). Per-gas meta lives in the global
	// meta table, keyed by the same gas-type path. Build the overlay list here,
	// mirroring the GAS_OVERLAYS macro but off arena getters, then hand it to
	// set_visuals for the vis_contents diff.
	var/list/gases = air.get_gases()
	var/offset = GET_TURF_PLANE_OFFSET(src) + 1
	var/list/new_overlay_types
	for(var/id in gases)
		if(GLOB.nonoverlaying_gases[id])
			continue
		var/list/gas_meta = GLOB.meta_gas_info[id]
		if(!gas_meta)
			continue
		var/moles = gases[id]
		if(moles <= gas_meta[META_GAS_MOLES_VISIBLE])
			continue
		var/list/gas_overlay = gas_meta[META_GAS_OVERLAY][offset]
		LAZYADD(new_overlay_types, gas_overlay[min(TOTAL_VISIBLE_STATES, CEILING(moles / MOLES_GAS_VISIBLE_STEP, 1))])
	set_visuals(new_overlay_types)

/**
 * Apply a precomputed gas-overlay list to vis_contents, diffing against the
 * currently applied set. This is the DM callback the auxmos turf-processing loop
 * invokes (verdigris turfs.rs::update_visuals -> turf.set_visuals(overlay_types)),
 * and the tail of the DM update_visuals() path above. Passing null/empty clears.
 */
/turf/open/proc/set_visuals(list/new_overlay_types)
	// Best-effort DM temperature-mirror sync. The Rust FDM keeps temperature in the
	// arena and this baked verdigris .so exposes no "changed turfs" drain, so we
	// can't cheaply refresh every turf's .temperature mirror each tick. set_visuals
	// fires (from the Rust callback) for the turfs auxmos flagged as interesting, so
	// piggy-back the mirror refresh here for those. Turfs whose temperature changed
	// WITHOUT a visual change keep a stale .temperature mirror — read authoritative
	// values via air.return_temperature() where correctness matters.
	if(air)
		air.temperature = air.return_temperature()

	var/list/atmos_overlay_types = src.atmos_overlay_types // Cache for free performance

	if (atmos_overlay_types)
		for(var/overlay in atmos_overlay_types-new_overlay_types) //doesn't remove overlays that would only be added
			vis_contents -= overlay

	if (length(new_overlay_types))
		if (atmos_overlay_types)
			vis_contents += new_overlay_types - atmos_overlay_types //don't add overlays that already exist
		else
			vis_contents += new_overlay_types

	UNSETEMPTY(new_overlay_types)
	src.atmos_overlay_types = new_overlay_types

/proc/typecache_of_gases_with_no_overlays()
	. = list()
	for (var/gastype in subtypesof(/datum/gas))
		var/datum/gas/gasvar = gastype
		if (!initial(gasvar.gas_overlay))
			.[gastype] = TRUE

/////////////////////////////SIMULATION///////////////////////////////////
// The DM turf-sharing engine (process_cell, LAST_SHARE_CHECK/PLANET_SHARE_CHECK
// macros, archive-based compare/share, the planetary-mix share pass) is DELETED.
// Turf FDM gas sharing, excited groups and equalize all run in the Rust arena now,
// driven by SSair.fire() via process_turfs_auxtools / process_excited_groups_auxtools
// / process_turf_equalize_auxtools. The Rust side dispatches back into DM through
// three callbacks that live in this file: consider_pressure_difference (below),
// air.react(turf) (gas_mixture.dm react bind -> DM /datum/gas_reaction), and
// turf.set_visuals(overlay_list) (above).

//////////////////////////SPACEWIND/////////////////////////////
// consider_pressure_difference is a Rust->DM callback: the arena's FDM/katmos loop
// calls it (turf.consider_pressure_difference(enemy, diff)) for turfs with a
// pressure delta big enough to blow things around. It appends src to
// SSair.high_pressure_delta, which the SSAIR_HIGHPRESSURE fire() step drains into
// high_pressure_movements().

/turf/open/proc/consider_pressure_difference(turf/target_turf, difference)
	SSair.high_pressure_delta |= src
	if(difference > pressure_difference)
		pressure_direction = get_dir(src, target_turf)
		pressure_difference = difference

// consider_firelocks / handle_decompression_floor_rip are Rust->DM callbacks the baked
// auxmos katmos (equalize/decompression) loop invokes by name via call_id. They exist in
// /tg/ and the auxmos katmos.rs still calls them:
//   turf.consider_firelocks(other)              (katmos equalize + explosively_depressurize)
//   turf.handle_decompression_floor_rip(sum)    (explosively_depressurize)
// Neither had a DM definition here, so the very first equalize/decompression event would
// hit a NonExistentString / missing-proc and panic the FFI call. These are defined on the
// base /turf (not just /turf/open) so the string resolves for any turf the arena hands us.
//
// STUB: safe no-ops. DeepQuarry's firedoors (Baystation/Polaris lineage) don't use /tg's
// automatic pressure-triggered firelock closing, and this fork doesn't rip up floor tiles
// on decompression, so doing nothing preserves current behavior. Give either real behavior
// later if desired — the contract is just "must not runtime/panic when called".

/// Rust katmos hook: called on a turf when an adjacent turf has a large enough pressure
/// delta that /tg would auto-close firelocks between them. No-op stub (see note above).
/turf/proc/consider_firelocks(turf/other)
	return

/// Rust katmos hook: called during explosive depressurization; /tg rips up floor tiles
/// under strong decompression. No-op stub (see note above). `sum` is the summed transfer.
/turf/proc/handle_decompression_floor_rip(sum)
	return

/turf/open/proc/high_pressure_movements()
	var/atom/movable/moving_atom
	for(var/thing in src)
		moving_atom = thing
		if (moving_atom.last_high_pressure_movement_air_cycle < SSair.times_fired)
			if (!moving_atom.anchored && !moving_atom.pulledby)
				moving_atom.experience_pressure_difference(pressure_difference, pressure_direction)
			else
				SEND_SIGNAL(moving_atom, COMSIG_MOVABLE_RESISTED_SPACEWIND, pressure_difference, pressure_direction)

/atom/movable
	///How much delta pressure is needed for us to move
	var/pressure_resistance = 10
	var/last_high_pressure_movement_air_cycle = 0

/atom/movable/proc/experience_pressure_difference(pressure_difference, direction, pressure_resistance_prob_delta = 0)
	set waitfor = FALSE
	if(SEND_SIGNAL(src, COMSIG_ATOM_PRE_PRESSURE_PUSH) & COMSIG_ATOM_BLOCKS_PRESSURE)
		return
	var/const/PROBABILITY_OFFSET = 25
	var/const/PROBABILITY_BASE_PRECENT = 75
	var/max_force = sqrt(pressure_difference) * (MOVE_FORCE_DEFAULT / 5)
	var/move_prob = 100
	if (pressure_resistance > 0)
		move_prob = (pressure_difference / pressure_resistance * PROBABILITY_BASE_PRECENT) - PROBABILITY_OFFSET
	move_prob += pressure_resistance_prob_delta
	if (move_prob > PROBABILITY_OFFSET && prob(move_prob) && (move_resist != INFINITY) && (!anchored && (max_force >= (move_resist * MOVE_FORCE_PUSH_RATIO))) || (anchored && (max_force >= (move_resist * MOVE_FORCE_FORCEPUSH_RATIO))))
		step(src, direction)
		last_high_pressure_movement_air_cycle = SSair.times_fired

///////////////////////////EXCITED GROUPS/////////////////////////////
// The /datum/excited_group type and its self_breakdown/dismantle/merge_groups/
// garbage_collect/display machinery are DELETED — excited groups are tracked in
// the Rust arena (process_excited_groups_auxtools). Nothing in DM references a
// /datum/excited_group anymore.

////////////////////////SUPERCONDUCTIVITY/////////////////////////////
// LINDA's DM superconduction engine (super_conduct, conductivity_directions,
// neighbor_conduct_with_src, temperature_share_open_to_solid,
// share_temperature_mutual_solid, radiate_to_spess, finish_superconduction,
// consider_superconductivity) is DELETED. auxmos ships a Rust heat subsystem
// (process_turf_heat / return_temperature bind, superconductivity feature) but it
// is NOT wired into SSair.fire() by this cutover — heat conduction between turfs
// is currently inert. Reviving it means adding a process_turf_heat fire() step and
// declaring the turf vars it reads (conductivity_blocked_directions,
// initial_temperature, should_conduct_to_space, thermal_conductivity, heat_capacity).
//
// should_conduct_to_space() is a Rust->DM callback: auxmos superconduct.rs's
// supercond_update_ref() invokes turf.should_conduct_to_space() by name via call_id to
// decide whether a turf radiates heat to space. Even though the heat subsystem isn't wired
// into fire() yet, the proc name must exist so that if/when it is, the call_id resolves
// instead of hitting a NonExistentString / missing-proc panic. STUB: reports whether this
// turf is space-exposed. /turf/space (and the base /turf, treated as unsimulated) return
// TRUE; simulated open turfs return FALSE. Adjust when the heat subsystem is revived.

/// Rust superconductivity hook: TRUE if this turf should radiate heat directly to space.
/turf/proc/should_conduct_to_space()
	return TRUE

/turf/open/should_conduct_to_space()
	return FALSE

/turf/space/should_conduct_to_space()
	return TRUE

