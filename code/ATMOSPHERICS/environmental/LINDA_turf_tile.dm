/turf
	// thermal_conductivity and heat_capacity are already declared on
	// CHOMP's /turf (code/game/turfs/turf.dm:30-31) with values 0.05 and 1.
	// LINDA wanted heat_capacity = INFINITY (opt-in heating); CHOMP defaults
	// matter (most turfs are heat-able). Don't redeclare — runtime will use
	// CHOMP's value (1) for all turfs, which means turfs CAN be heated by gas.
	// This is closer to /tg/'s opt-OUT behavior anyway.
	///All currently stored conductivities changes
	var/list/thermal_conductivities


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
	///Our gas mix
	var/datum/gas_mixture/air

	///If there is an active hotspot on us store a reference to it here
	var/obj/effect/hotspot/active_hotspot
	/// air will slowly revert to initial_gas_mix
	var/planetary_atmos = FALSE
	/// The gas mixture is a constant source or sink and cannot be changed by diffusion.
	var/immutable_atmos = FALSE
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
		if(immutable_atmos)
			// Space and transit hold nothing but vacuum, so they all share one
			// cached immutable mixture instead of a mixture (and Rust arena slot)
			// each. The arena drops writes to it; Destroy() must never qdel it.
			air = SSair.parse_gas_string(initial_gas_mix, /datum/gas_mixture/immutable/space)
		else
			air = create_gas_mixture()
		if(planetary_atmos)
			if(!SSair.planetary[initial_gas_mix])
				var/datum/gas_mixture/immutable/planetary/mix = new
				mix.parse_string_immutable(initial_gas_mix)
				SSair.planetary[initial_gas_mix] = mix
	. = ..()
	// Register this turf's air ref in the Rust arena. During roundstart mapload
	// SSair isn't initialised yet — SSair.setup_allturfs registers every
	// turf then. For turfs created AFTER SSair init (ChangeTurf, runtime spawns)
	// we register here, with the air-block mask of whatever is already on the
	// turf, so Rust builds its adjacency.
	if(SSair.initialized)
		update_air_ref(0, air_block_mask())

/turf/open/Destroy()
	if(active_hotspot)
		QDEL_NULL(active_hotspot)
	// Unregister src from the Rust arena so the next SSair tick doesn't process
	// this dying turf. Rust drops its adjacency and wakes the turfs that shared
	// air with it. ChangeTurf-style replacement swaps a new turf into the same
	// coordinates, which registers itself in Initialize.
	if(SSair)
		SSair.remove_from_active(src)
	if(immutable_atmos)
		// Shared vacuum (see Initialize); other turfs still use it.
		air = null
	else
		QDEL_NULL(air)
	return ..()

/////////////////GAS MIXTURE PROCS///////////////////

///Copies all gas info from the turf into a new gas_mixture, along with our temperature
///Returns the created gas_mixture
/turf/proc/create_gas_mixture()
	var/datum/gas_mixture/mix = SSair.parse_gas_string(initial_gas_mix, /datum/gas_mixture/turf)

	//acounts for changes in temperature
	var/turf/parent = parent_type
	if(temperature != initial(temperature) || temperature != initial(parent.temperature))
		mix.set_temperature(temperature) // arena-backed write (no DM mirror under the opaque-handle model)

	return mix

/turf/open/assume_air(datum/gas_mixture/giver) //use this for machines to adjust air
	if(!giver || !air)
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
	var/static/datum/gas_mixture/immutable/space/vacuum
	if(!vacuum)
		vacuum = new
	return vacuum

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
	set_visuals()

/**
 * Recompute this turf's gas overlays from its (arena-backed) air and diff the
 * result into vis_contents. This is the single source of truth for gas visuals.
 *
 * It's called two ways: (a) directly by ~56 DM atmos callers (pumps, canisters,
 * vents) via update_visuals() after they mutate air; (b) by the auxmos turf-
 * processing loop (verdigris turfs.rs::update_visuals -> turf.set_visuals(list))
 * for every turf whose gas changed during the FDM share — this is how a turf that
 * RECEIVED gas from a neighbour (not the injector) gets its overlay updated.
 *
 * Rust publication passes a precomputed overlay list so the main thread does not
 * re-enumerate every changed mixture. Direct DM callers omit the argument and
 * recompute from the authoritative arena mixture. Empty air clears.
 */
/turf/open/proc/set_visuals(list/rust_overlay_types)
	// (Formerly refreshed a DM temperature mirror here. Under the /tg/ opaque-handle
	// model there is no mirror — the arena is authoritative and read via
	// return_temperature() — so this per-turf sync is gone. Do NOT re-add a
	// set_temperature() here: writing the arena its own value re-marks the turf active
	// and causes endless re-processing/re-visualising.)
	var/list/new_overlay_types = rust_overlay_types
	if(isnull(rust_overlay_types) && air)
		// get_gases() returns an assoc id -> moles (id = gas-type path). Per-gas meta
		// lives in the global meta table keyed by the same path.
		var/list/gases = air.get_gases()
		var/offset = GET_TURF_PLANE_OFFSET(src) + 1
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
// Turf FDM gas sharing and pressure equalization run in the Rust arena now,
// driven by SSair.fire() via the detached process_turfs_auxtools transaction.
// The Rust side dispatches back into DM through
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
// Pressure boundaries close adjacent firelocks. Floor ripping remains disabled because
// this fork does not model decompression damage to floor tiles.

/// Rust katmos hook: called on a turf when an adjacent turf has a large enough pressure
/// delta that should close firelocks between them.
/turf/proc/consider_firelocks(turf/other)
	if(!other || get_dist(src, other) != 1)
		return
	for(var/turf/boundary in list(src, other))
		for(var/obj/machinery/door/firedoor/firelock in boundary)
			if(!firelock.density && !firelock.blocked)
				INVOKE_ASYNC(firelock, TYPE_PROC_REF(/obj/machinery/door/firedoor, close))

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

/atom/movable
	///How much delta pressure is needed for us to move
	var/pressure_resistance = 10
	var/tmp/last_high_pressure_movement_air_cycle = 0

/atom/movable/proc/experience_pressure_difference(pressure_difference, direction, pressure_resistance_prob_delta = 0)
	set waitfor = FALSE
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
// garbage_collect/display machinery are DELETED. The transactional Rust turf
// solver owns convergence; nothing references a /datum/excited_group anymore.

////////////////////////SUPERCONDUCTIVITY/////////////////////////////
// LINDA's DM superconduction engine (super_conduct, conductivity_directions,
// neighbor_conduct_with_src, temperature_share_open_to_solid,
// share_temperature_mutual_solid, radiate_to_spess, finish_superconduction,
// consider_superconductivity) is DELETED. Heat conduction now runs in RUST and
// IS live: the auxmos superconductivity feature is compiled in and SSair.fire()
// drives it via the SSAIR_SUPERCONDUCTIVITY step (process_turf_heat() — see
// SSair.dm). Turf heat lives in the Rust superconductivity arena; read/write it
// via /turf/proc/return_temperature() / set_temperature(), never a raw var.
//
// should_conduct_to_space() is a Rust->DM callback: auxmos superconduct.rs's
// supercond_update_ref() invokes turf.should_conduct_to_space() by name via
// call_id to decide whether a turf radiates heat to space. Reports whether this
// turf is space-exposed: /turf/space (and the base /turf, treated as
// unsimulated) return TRUE; simulated open turfs return FALSE.

/// Rust superconductivity hook: TRUE if this turf should radiate heat directly to space.
/turf/proc/should_conduct_to_space()
	return TRUE

/turf/open/should_conduct_to_space()
	for(var/direction in GLOB.cardinals)
		var/turf/neighbor = get_step(src, direction)
		if(istype(neighbor, /turf/space))
			return TRUE
	return FALSE

/turf/space/should_conduct_to_space()
	return TRUE
