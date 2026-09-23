/atom
	///Check if atmos can pass in this atom (ATMOS_PASS_YES, ATMOS_PASS_NO, ATMOS_PASS_DENSITY, ATMOS_PASS_PROC)
	var/can_atmos_pass = ATMOS_PASS_YES

/atom/proc/can_atmos_pass(turf/target_turf, vertical = FALSE)
	switch (can_atmos_pass)
		if (ATMOS_PASS_PROC)
			// route to CanZASPass so CHOMP overrides on doors,
			// windows, airlocks, blast doors, multi-tile doors, etc. take
			// effect under LINDA without each needing its own can_atmos_pass
			// proc override.
			return CanZASPass(target_turf, FALSE)
		if (ATMOS_PASS_DENSITY)
			return !density
		else
			return can_atmos_pass

/turf
	can_atmos_pass = ATMOS_PASS_NO

/turf/open
	can_atmos_pass = ATMOS_PASS_PROC

// === Turf adjacency ===
//
// Rust owns turf adjacency (verdigris/domains/gas/src/turfs.rs, AirCells). DM
// publishes one air-block mask per turf: the faces (NORTH|SOUTH|EAST|WEST|UP|DOWN)
// that the turf and the atoms on it block. Two registered face neighbours share
// air when neither blocks the shared face. A turf republishes its mask through
// air_update_turf(TRUE) whenever something that blocks air changes on it: a door
// opening, a window being built or moved, the turf itself changing. DM keeps no
// copy of the adjacency; readers ask Rust (get_atmos_adjacent_turfs,
// atmos_adjacent_turfs_bulk, SSair.air_blocked). tools/ci/check_grep.sh rejects
// DM copies of this state.

/// The faces of this turf that air cannot cross, as direction bits. The turf's
/// own block ORed with every atom on it. Only open turfs carry air.
/turf/proc/air_block_mask()
	return AIR_BLOCK_ALL

/turf/open/air_block_mask()
	if(blocks_air)
		return AIR_BLOCK_ALL
	. = NONE
	// Vertical faces: air crosses a z-boundary only through an opening
	// (zAirIn/zAirOut, tg_infra_compat.dm). Leaving through a face and entering
	// through it are both checked, so the pair is symmetric.
	if(!zAirOut(UP, null) || !zAirIn(DOWN, null))
		. |= UP
	if(!zAirOut(DOWN, null) || !zAirIn(UP, null))
		. |= DOWN
	for(var/obj/checked_object in contents)
		// qdel runs Destroy() synchronously but BYOND keeps the object in
		// contents until it is collected. A destroyed door must not keep a face
		// sealed in the meantime, especially inside an explosion batch.
		if(QDELETED(checked_object))
			continue
		switch(checked_object.can_atmos_pass)
			if(ATMOS_PASS_YES)
				continue
			if(ATMOS_PASS_NO)
				return AIR_BLOCK_ALL
			if(ATMOS_PASS_DENSITY)
				if(checked_object.density)
					return AIR_BLOCK_ALL
				continue
		// ATMOS_PASS_PROC: directional blockers (windows, firedoors, doors) are
		// asked per face, with the neighbouring turf as the target.
		for(var/direction in GLOB.cardinals_multiz)
			if(. & direction)
				continue
			var/turf/neighbor = get_step_multiz(src, direction)
			if(neighbor && !checked_object.can_atmos_pass(neighbor, (direction & (UP|DOWN))))
				. |= direction

///Do NOT use this to see if 2 turfs are connected; ask Rust with SSair.air_blocked().
///This recomputes both turfs' masks from their current contents.
/turf/open/can_atmos_pass(turf/target_turf, vertical = FALSE)
	if(target_turf == src)
		return !blocks_air
	if(!istype(target_turf, /turf/open))
		return FALSE
	var/direction = vertical ? get_dir_multiz(src, target_turf) : get_dir(src, target_turf)
	return !(air_block_mask() & direction) && !(target_turf.air_block_mask() & REVERSE_DIR(direction))

/**
 * The turfs that share air with this one, as an assoc list (turf -> TRUE), read
 * from Rust. Face neighbours only.
 */
/turf/proc/get_atmos_adjacent_turfs()
	var/list/adjacent = list()
	for(var/turf/neighbor as anything in vg_atmos_adjacent_turfs(src))
		adjacent[neighbor] = TRUE
	return adjacent

/**
 * Batched adjacency read: one FFI call for a whole list of turfs. Returns a
 * list of lists, parallel to `turfs`.
 */
/proc/atmos_adjacent_turfs_bulk(list/turfs)
	return vg_atmos_adjacent_turfs_bulk(turfs)

/atom/proc/air_update_turf(update = FALSE, remove = FALSE)
	if(!SSair.initialized) // I'm sorry for polutting user code, I'll do 10 hail giacom's
		return
	var/turf/local_turf = get_turf(loc)
	if(!local_turf)
		return
	local_turf.air_update_turf(update, remove)

/**
 * Tells the Rust arena that this turf's air or what blocks it changed.
 *
 * Arguments:
 * * update - Has something that blocks air changed here (a door, a window, the
 *   turf itself)? Then the air-block mask is recomputed and republished, and Rust
 *   rebuilds this turf's adjacency. Otherwise the turf is only re-registered.
 * * remove - Legacy; Rust drops a turf that stops sharing on its own.
*/
/turf/air_update_turf(update = FALSE, remove = FALSE)
	if(!SSair.initialized) // I'm sorry for polutting user code, I'll do 10 hail giacom's
		return
	update_air_ref(0, update ? air_block_mask() : AIR_BLOCK_KEEP)

/atom/movable/proc/move_update_air(turf/target_turf)
	if(isturf(target_turf))
		target_turf.air_update_turf(TRUE, FALSE) //You're empty now
	air_update_turf(TRUE, TRUE) //You aren't

/atom/proc/atmos_spawn_air(text) //because a lot of people loves to copy paste awful code lets just make an easy proc to spawn your plasma fires
	var/turf/open/local_turf = get_turf(src)
	if(!istype(local_turf))
		return
	local_turf.atmos_spawn_air(text)

/turf/open/atmos_spawn_air(text)
	if(!text || !air)
		return

	var/datum/gas_mixture/turf_mixture = SSair.parse_gas_string(text, /datum/gas_mixture/turf)

	air.merge(turf_mixture)
	// archive() removed — turf FDM archiving is Rust-side now.
	SSair.add_to_active(src)
