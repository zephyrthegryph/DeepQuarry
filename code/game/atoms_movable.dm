/atom/movable
	layer = OBJ_LAYER
	glide_size = 8
	appearance_flags = TILE_BOUND|PIXEL_SCALE|KEEP_TOGETHER|LONG_GLIDE

	var/tmp/last_move = null //The direction the atom last moved
	var/anchored = FALSE
	var/tmp/moving_diagonally
	var/tmp/move_speed = 10
	EXPIRY_TMP_DECLARE(l_move_time)
	l_move_time = 1
	var/datum/thrownthing/throwing // running: set only mid-throw
	var/tmp/datum/throw_source
	var/throw_speed = 2
	var/throw_range = 7
	// moved_recently lives in code/datums/sparse_vars/movable_misc.dm
	var/item_state = null // Used to specify the item state for the on-mob overlays.
	var/icon_scale_x = DEFAULT_ICON_SCALE_X // Used to scale icons up or down horizonally in update_transform().
	var/icon_scale_y = DEFAULT_ICON_SCALE_Y // Used to scale icons up or down vertically in update_transform().
	var/icon_rotation = DEFAULT_ICON_ROTATION // Used to rotate icons in update_transform()
	var/icon_expected_height = 32
	var/icon_expected_width = 32
	var/old_x = 0
	var/old_y = 0
	var/datum/riding/riding_datum = null
	var/does_spin = TRUE // Does the atom spin when thrown (of course it does :P)
	var/movement_type = NONE

	// dq_get_cloaked(src) lives in code/datums/sparse_vars/movable_misc.dm
	// cloaked_selfimage lives in code/datums/sparse_vars/movable_misc.dm
	// belly_cycles lives in code/datums/sparse_vars/movable_misc.dm
	var/autotransferable = TRUE // Toggle for autotransfer mechanics.
	// recursive_listeners lives in code/datums/sparse_vars/movable_misc.dm
	var/listening_recursive = NON_LISTENING_ATOM
	var/unacidable = TRUE

// ALLOW(init/FRAMEWORK): the movable base of the init chain runs its per-instance setup
/atom/movable/Initialize(mapload)
	. = ..()
	movable_instance_setup()

/// The table path (atom_type_table.dm) runs the same per-instance setup as Initialize().
/atom/movable/table_initialize()
	..()
	movable_instance_setup()

/// The per-instance part of /atom/movable/Initialize(), shared with table_initialize().
/atom/movable/proc/movable_instance_setup()
	PRIVATE_PROC(TRUE)
	// L3 (doc/rewrite/lifecycle.md Â§5): a declared `lifetime` self-arms here
	// instead of every timed-delete type calling expire()/QDEL_IN by hand.
	lifecycle_arm_lifetime()
	if(proximity_tracked)
		SSproximity.member_update(src)

#if EMISSIVE_BLOCK_GENERIC != 0
	#error EMISSIVE_BLOCK_GENERIC is expected to be 0 to facilitate a weird optimization hack where we rely on it being the most common.
	#error Read the comment in code/game/atoms_movable.dm for details.
#endif

	if (blocks_emissive)
		if (blocks_emissive == EMISSIVE_BLOCK_UNIQUE)
			render_target = ref(src)
			rel_set(src, nameof(/atom/movable::em_block), new /atom/movable/emissive_blocker(null, src))
			// Note, this should be refactored to drop priority overlays
			add_overlay(list(em_block), TRUE)
			observe(em_block, /datum/notice/qdeleting, src, then(PROC_REF(emblocker_gc)))
	else
		var/mutable_appearance/gen_emissive_blocker = mutable_appearance(icon, icon_state, plane = PLANE_EMISSIVE, alpha = src.alpha)
		gen_emissive_blocker.color = GLOB.em_block_color
		gen_emissive_blocker.dir = dir
		gen_emissive_blocker.appearance_flags |= appearance_flags
		// Note, this should be refactored to drop priority overlays
		add_overlay(list(gen_emissive_blocker), TRUE)

	if(opacity)
		start_blocking_light()
	if(icon_scale_x != DEFAULT_ICON_SCALE_X || icon_scale_y != DEFAULT_ICON_SCALE_Y || icon_rotation != DEFAULT_ICON_ROTATION)
		update_transform()
	switch(light_system)
		if(MOVABLE_LIGHT)
			add_overlay_lighting(src, starts_on = light_on)
		if(MOVABLE_LIGHT_DIRECTIONAL)
			add_overlay_lighting(src, is_directional = TRUE, starts_on = light_on)

/// World registration moved out of Initialize() (L2): radiation shielding,
/// static lighting and recursive listening reach outside the object.
/atom/movable/on_materialize()
	. = ..()
	if(rad_insulation != RAD_NO_INSULATION)
		RAD_SHIELDING_CHANGED(loc)
	if(light_system == STATIC_LIGHT)
		update_light()
	// Unchanged from Initialize(): set_listening() is a no-op when the var is
	// already set, so this never registered anything. Destroy() clears it.
	if (listening_recursive)
		set_listening(listening_recursive)
	// R10 bind (doc/rewrite/rust_bindings.md Â§4): one call creates the Rust
	// entity and every component this type declares (vg_gas, and future
	// vg_power/vg_heat/...), from the init_* values and the current inputs.
	// Last, so registries and signals this atom's inputs might read (e.g.
	// REGISTRY_MACHINES via join_registries() in the base on_materialize())
	// are already in place.
	vg_bind()
	if(vg_entity)
		SSvg.register(src)

/atom/movable/on_dematerialize()
	// R10 unbind. J1's pre_destroy() is the design's intended call site
	// (rust_bindings.md Â§4); it has not landed yet (rewrite/ledger-joint).
	// Until it does, this is the earliest guaranteed point every Destroy()
	// path reaches (mirrors how L3's leave_registries() piggybacks on the
	// same hook, __defines/misc.dm). Move this single call into pre_destroy()
	// when J1 lands; do not add a second unbind mechanism.
	if(vg_entity)
		var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
		if(batch?.doomed[src])
			// Batched destroy: one pass over SSvg.bound and one unbind call at the end.
			var/slot = ((vg_entity - 1) & VG_ENTITY_INDEX_MASK) + 1
			if(slot <= length(SSvg.entities_by_index) && SSvg.entities_by_index[slot] == src)
				SSvg.entities_by_index[slot] = null
			rel_add(batch, nameof(batch.unbind_movers), src)
			batch.unbind_entities += vg_entity
		else
			SSvg.unregister(src)
			vg_entity_unbind(vg_entity)
		vg_entity = 0
	if(rad_insulation != RAD_NO_INSULATION)
		RAD_SHIELDING_CHANGED(loc)
	if(light_system == STATIC_LIGHT && light)
		rel_clear(src, nameof(light))
	return ..()

/atom/movable/Destroy()
	// L1 (doc/rewrite/lifecycle.md Â§2): contents already went where each
	// slot's declared policy said, in the destroy transaction's phase 3
	// (destroy_transaction() -> dq_lifecycle_resolve_contents()), before
	// Destroy() ever runs. Nothing decides that here any more; phase 3 itself
	// checks that it released them (dq_lifecycle_check_released()).
	if(em_block)
		cut_overlay(em_block)
		unobserve(em_block, /datum/notice/qdeleting, src)
		rel_clear(src, nameof(em_block))
	// Leave the turf's opacity_sources while loc is still valid.
	stop_blocking_light()
	. = ..()

	// Any mobs buckled to us were already unbuckled in the destroy
	// transaction's phase 5 teardown, before Destroy() ran: the buckled_to
	// relation (code/datums/om/library.dm) unlinks its edges -- and runs its
	// on_unlink() cleanup -- for both ends of a deleted entity automatically.

	// Snapshot: each member's Destroy() pulls it out of contents mid-iteration
	// (moveToNullspace), which makes DM's for-in skip members â€” skipped ones
	// never run Destroy() and keep a loc ref to this deleted container.
	for(var/atom/movable/AM in contents.Copy())
		ended_with(AM, src)
	clear_containment_ledger()

	moveToNullspace()

	vis_contents.Cut()
	for(var/atom/movable/A as anything in vis_locs)
		A.vis_contents -= src

	var/mob/pulledby = src?.pulled_by_mob()
	if(pulledby)
		pulledby.stop_pulling()

	stop_orbit()
	rel_clear(src, nameof(throw_source))
	rel_clear(src, nameof(riding_datum))
	set_listening(NON_LISTENING_ATOM)

////////////////////////////////////////
/atom/movable/Move(atom/newloc, direct = 0, movetime)
	// Didn't pass enough info
	if(!loc || !newloc)
		return FALSE

	var/datum/act/pre_move/step = ACT_TRY(src, pre_move, direct, newloc)
	if(!step)
		return FALSE
	act_cancel(step)

	// Store this early before we might move, it's used several places
	var/atom/oldloc = loc

	// If we're not moving to the same spot (why? does that even happen?)
	if(loc != newloc)
		if(!direct)
			direct = get_dir(oldloc, newloc)
		if (IS_CARDINAL(direct)) //GLOB.cardinal move
			// Track our failure if any in this value
			. = TRUE

			// Face the direction of movement
			set_dir(direct)

			// Check to make sure we can leave
			if(!loc.Exit(src, newloc))
				. = FALSE

			// Check to make sure we can enter, if we haven't already failed
			if(. && !newloc.Enter(src, src.loc))
				. = FALSE

			// Check to make sure if we're multi-tile we can move, if we haven't already failed
			if(. && !check_multi_tile_move_density_dir(direct, locs))
				. = FALSE

			// Definitely moving if you enter this, no failures so far
			if(. && locs.len <= 1)	// We're not a multi-tile object.
				var/area/oldarea = get_area(oldloc)
				var/area/newarea = get_area(newloc)
				var/old_z = get_z(oldloc)
				var/dest_z = get_z(newloc)

				// Do The Move
				if(movetime)
					glide_for(movetime) // First attempt, lets let the diag do it.
				loc = newloc // ALLOW(containment): Move()'s own commit point (the ledger is only on holders, a turf-to-turf step)
				. = TRUE

				// So objects can be informed of z-level changes
				if (old_z != dest_z)
					onTransitZ(old_z, dest_z)

				// We don't call parent so we are calling this for byond
				oldloc.Exited(src, newloc)
				if(oldarea != newarea)
					oldarea.Exited(src, newloc)

				// Multi-tile objects can't reach here, otherwise you'd need to avoid uncrossing yourself
				for(var/atom/movable/thing as anything in oldloc)
					// We don't call parent so we are calling this for byond
					thing.Uncrossed(src)

				// We don't call parent so we are calling this for byond
				newloc.Entered(src, oldloc)
				if(oldarea != newarea)
					newarea.Entered(src, oldloc)

				// Multi-tile objects can't reach here, otherwise you'd need to avoid uncrossing yourself
				// ALLOW(spatial): Move() hot path, raw Crossed loop avoids a list copy per step
				for(var/atom/movable/thing as anything in loc)
					// We don't call parent so we are calling this for byond
					thing.Crossed(src, oldloc)

			// We're a multi-tile object (multiple locs)
			else if(. && newloc)
				. = doMove(newloc)

		//Diagonal move, split it into GLOB.cardinal moves
		else
			moving_diagonally = FIRST_DIAG_STEP
			var/first_step_dir
			// The `&& moving_diagonally` checks are so that a forceMove taking
			// place due to a Crossed, Bumped, etc. call will interrupt
			// the second half of the diagonal movement, or the second attempt
			// at a first half if step() fails because we hit something.
			glide_for(movetime * SQRT_2)
			if (direct & NORTH)
				if (direct & EAST)
					if (step(src, NORTH) && moving_diagonally)
						first_step_dir = NORTH
						moving_diagonally = SECOND_DIAG_STEP
						. = step(src, EAST)
					else if (moving_diagonally && step(src, EAST))
						first_step_dir = EAST
						moving_diagonally = SECOND_DIAG_STEP
						. = step(src, NORTH)
				else if (direct & WEST)
					if (step(src, NORTH) && moving_diagonally)
						first_step_dir = NORTH
						moving_diagonally = SECOND_DIAG_STEP
						. = step(src, WEST)
					else if (moving_diagonally && step(src, WEST))
						first_step_dir = WEST
						moving_diagonally = SECOND_DIAG_STEP
						. = step(src, NORTH)
			else if (direct & SOUTH)
				if (direct & EAST)
					if (step(src, SOUTH) && moving_diagonally)
						first_step_dir = SOUTH
						moving_diagonally = SECOND_DIAG_STEP
						. = step(src, EAST)
					else if (moving_diagonally && step(src, EAST))
						first_step_dir = EAST
						moving_diagonally = SECOND_DIAG_STEP
						. = step(src, SOUTH)
				else if (direct & WEST)
					if (step(src, SOUTH) && moving_diagonally)
						first_step_dir = SOUTH
						moving_diagonally = SECOND_DIAG_STEP
						. = step(src, WEST)
					else if (moving_diagonally && step(src, WEST))
						first_step_dir = WEST
						moving_diagonally = SECOND_DIAG_STEP
						. = step(src, SOUTH)
			// If we failed, turn to face the direction of the first step at least
			if(!. && moving_diagonally == SECOND_DIAG_STEP)
				set_dir(first_step_dir)
			// Done, regardless!
			moving_diagonally = 0
			// We return because step above will call Move() and we don't want to do shenanigans back in here again
			return

	else if(!loc || (loc == oldloc))
		last_move = 0
		return

	// If we moved, call Moved() on ourselves
	if(.)
		Moved(oldloc, direct, FALSE, movetime ? movetime : MOVE_GLIDE_CALC(glide_size, moving_diagonally) )

	// Update timers/cooldown stuff
	move_speed = world.time - l_move_time
	EXPIRY_STAMP(src, l_move_time, CLOCK_WORLD)
	last_move = direct // The direction you last moved
	// set_dir(direct) //Don't think this is necessary

///Called after a successful Move(). By this point, we've already moved
/atom/movable/proc/Moved(atom/old_loc, direction, forced = FALSE, movetime)
	// BYOND turns a mover natively on Move(), bypassing set_dir(): publish the dir a drawn atom now shows, only when it changed.
	if((rx?.look_key || rel_watchers) && dir != rx?.look_seen_dir)
		rx_of(src).look_seen_dir = dir
		tracked_changed(src, nameof(dir))
	if(blocks_light)
		light_blocking_moved(old_loc)
	PUBLISH_LEGACY(src, /datum/notice/moved, old_loc, direction, forced)
	// Mobs publish MOB_KEY_LOC themselves (living_movement.dm).
	if(om_listen && !ismob(src) && !isitem(src))
		changed(src, CHANGE_EXPLICIT)
	// A window watching this thing as its host re-checks its status (code/modules/tgui/ui_status.dm); nobody else reads this key.
	if(rx?.observed)
		PUBLISH_CHANGE(src, ATOM_KEY_LOC)
	// Covers Destroy() too, which moves to nullspace.
	if(rad_insulation != RAD_NO_INSULATION)
		RAD_SHIELDING_CHANGED(old_loc)
		RAD_SHIELDING_CHANGED(loc)
	// Handle any buckled mobs on this movable
	if(has_buckled_mobs())
		handle_buckled_mob_movement(old_loc, direction, movetime)
	if(riding_datum)
		riding_datum.handle_vehicle_layer()
		riding_datum.handle_vehicle_offsets()
	for (var/datum/light_source/light as anything in light_sources) // Cycle through the light sources on this atom and tell them to update.
		light.source_atom.update_light()
	if(!isnull(heat_body))
		heat_recouple()
	if(GLOB.heat_followers_of[src])
		heat_followers_moved(src)
	if(proximity_tracked)
		SSproximity.member_update(src)
	if(lifeform_moves)
		lifeform_moved(src, old_loc) // registry(by = REG_Z | REG_AREA) and adjacency() (code/engine/lifeforms/)
	return TRUE

/mob/Moved(atom/old_loc, direction, forced, movetime)
	. = ..()
	// One publish; it returns before any turf lookup while nothing is subscribed (Q12).
	if(GLOB.mob_chunk_watches || (client && GLOB.player_chunk_watches) || length(GLOB.mob_chunks))
		publish_mob_move(old_loc, src, !!client)
	//If we return focus to our own mob, but we are still inside something with an inherent remote view. Restart it.
	if(client)
		restore_remote_views()
		SSproximity.eye_update(client)

/atom/movable/set_dir(newdir)
	. = ..(newdir)
	if(rx?.look_key || rel_watchers)
		rx_of(src).look_seen_dir = dir
	if(riding_datum)
		riding_datum.handle_vehicle_offsets()

/atom/movable/relaymove(mob/user, direction)
	. = ..()
	if(riding_datum)
		riding_datum.handle_ride(user, direction)

// Make sure you know what you're doing if you call this, this is intended to only be called by byond directly.
// You probably want CanPass()
/atom/movable/Cross(atom/movable/AM)
	if(guard(src, GUARD_CROSS, AM))
		return FALSE
	return CanPass(AM, loc)

/atom/movable/CanPass(atom/movable/mover, turf/target)
	. = ..()
	if(locs && locs.len >= 2)	// If something is standing on top of us, let them pass.
		if(mover.loc in locs)
			. = TRUE
	return .

/atom/movable/Bump(atom/A)
	if(!A)
		CRASH("Bump was called with no argument.")
	. = ..()
	if(!QDELETED(throwing))
		throwing.finalize(hit = TRUE, t_target = A)
		if(QDELETED(A))
			return

	PUBLISH_LEGACY(src, /datum/notice/movable_bump, A)

	bump_into(A)

/// The bump action (doc/rewrite/final_api.html, section 8 "World actions"): `src` walked into `A`. The one emitter of /datum/act/bump: the
/// action runs on the bumped atom, whose hooks (extend(/datum/act/bump, ...), on_notice(/datum/notice/bumped, ...)) answer it; a refused or
/// taken-over bump stops there. A type not converted yet still answers through its legacy Bumped(), which runs after the notice.
/atom/movable/proc/bump_into(atom/A)
	var/datum/act/bump/B = ACT_TRY(A, bump, src, A, get_dir(src, A))
	if(!B)
		return
	act_done(B)
	if(QDELETED(A))
		return
	A.Bumped(src)
	EXPIRY_STAMP(A, last_bumped, CLOCK_WORLD)

/atom/movable/proc/forceMove(atom/destination, direction, movetime)
	. = FALSE
	if(destination)
		. = doMove(destination, direction, movetime)
	else
		CRASH("No valid destination passed into forceMove")

/atom/movable/proc/moveToNullspace()
	return doMove(null)

/atom/movable/proc/doMove(atom/destination, direction, movetime)
	var/atom/oldloc = loc
	var/area/old_area = get_area(oldloc)
	var/same_loc = oldloc == destination

	if(destination)
		var/area/destarea = get_area(destination)

		// J5: the before-hook, right before the loc write. Gated on one var
		// test, so an unhooked mover (almost everything) pays nothing.
		if(containment_move_flags())
			move_hooks_dispatch(TRUE)

		// Do The Move
		glide_for(movetime)
		last_move = isnull(direction) ? 0 : direction
		loc = destination // ALLOW(containment): doMove()'s commit point; note_exit/note_enter follow
		// The containment ledger's commit point: account for the move before
		// anything else can react to it.
		if(!same_loc)
			if(oldloc?.containment_ledger())
				oldloc.containment_ledger().note_exit(src)
			// A move into a holder registers in its default slot through the same note_enter() path move_into() lands in, also
			// when the holder has not built its ledger yet (a net or a jar that was never asked what it holds): the ledger is
			// made here (its sync adopts the arrival), so the slot's occupancy is published and a draw that reads it hears of it.
			var/datum/ledger/entered = destination.containment_ledger() || dq_ledger_for_arrival(destination)
			entered?.note_enter(src)

		// J5: the after-hook, right after note_enter(), before Exited()/
		// Uncrossed(). Not run for a same-loc "move" (nothing left or entered).
		if(containment_move_flags() && !same_loc)
			move_hooks_dispatch(FALSE)

		// Unset this in case it was set in some other proc. We're no longer moving diagonally for sure.
		moving_diagonally = 0

		// We are moving to a different loc
		if(!same_loc)
			// Not moving out of nullspace
			if(oldloc)
				oldloc.Exited(src, destination)
				// If it's not the same area, Exited() it
				if(old_area && old_area != destarea)
					old_area.Exited(src, destination)

			// Uncross everything where we left
			for(var/atom/movable/AM as anything in oldloc)
				if(AM == src)
					continue
				AM.Uncrossed(src)
				if(loc != destination) // Uncrossed() triggered a separate movement
					return

			// Information about turf and z-levels for source and dest collected
			var/turf/oldturf = get_turf(oldloc)
			var/turf/destturf = get_turf(destination)
			var/old_z = (oldturf ? oldturf.z : null)
			var/dest_z = (destturf ? destturf.z : null)

			// So objects can be informed of z-level changes
			if (old_z != dest_z)
				onTransitZ(old_z, dest_z)

			// Destination atom Entered
			destination.Entered(src, oldloc)

			// Entered() the new area if it's not the same area
			if(destarea && old_area != destarea)
				destarea.Entered(src, oldloc)

			// We ignore ourselves because if we're multi-tile we might be in both old and new locs
			for(var/atom/movable/AM as anything in destination)
				if(AM == src)
					continue
				AM.Crossed(src, oldloc)
				if(loc != destination) // Crossed triggered a separate movement
					return

			// Call our thingy to inform everyone we moved
			Moved(oldloc, NONE, TRUE)

		// The pulling relation's holds_while = in_range(1) (code/datums/om/library.dm)
		// unlinks pulling/pulledby on its own once the live scheduler re-checks
		// it, replacing the hand-rolled distance/z check that used to live here.

		// We moved
		return TRUE

	//If no destination, move the atom into nullspace (don't do this unless you know what you're doing)
	else if(oldloc)
		// J5: the before-hook still runs on a deletion move (there is no
		// "after" -- nothing to settle into), so clocks settle and cancel
		// instead of being silently dropped by moveToNullspace().
		if(containment_move_flags())
			move_hooks_dispatch(TRUE)
		loc = null // ALLOW(containment): doMove()'s nullspace commit point; note_exit follows
		oldloc.containment_ledger()?.note_exit(src)

		// Uncross everything where we left (no multitile safety like above because we are definitely not still there)
		for(var/atom/movable/AM as anything in oldloc)
			AM.Uncrossed(src)

		// Exited() our loc and area
		oldloc.Exited(src, null)
		if(old_area)
			old_area.Exited(src, null)

		// Leaving the map is a z-level change like any other.
		var/turf/oldturf = get_turf(oldloc)
		if(oldturf)
			onTransitZ(oldturf.z, null)

		// We moved
		return TRUE

/atom/movable/proc/onTransitZ(old_z,new_z)
	PUBLISH_LEGACY(src, /datum/notice/movable_z_changed, old_z, new_z)
	for(var/atom/movable/AM as anything in contents_of(src)) // Notify contents of Z-transition. This can be overridden IF we know the items contents do not care.
		AM.onTransitZ(old_z,new_z)

/atom/movable/proc/reset_glide_size()
	glide_size = initial(glide_size)

/// Anchors or frees it. Anchored is a tracked base var (G8): this is its only writer. A change publishes
/// nameof(anchored) and, as a bridge, raises the channel of the type's declared field (a machine
/// CHANGE_MACHINE_ANCHORED; machinery_fields.dm).
/atom/movable/proc/set_anchored(state)
	if(anchored == state)
		return FALSE
	anchored = state
	tracked_bridged_changed(src, nameof(anchored))
	return TRUE
SETTER(/atom/movable, anchored)

/atom/movable/proc/glide_for(movetime)
	if(movetime)
		glide_size = WORLD_ICON_SIZE/max(DS2TICKS(movetime), 1)
		after(src, movetime, PROC_REF(reset_glide_size))
	else
		glide_size = initial(glide_size)

/////////////////////////////////////////////////////////////////

//called when src is thrown into hit_atom
/atom/movable/proc/throw_impact(atom/hit_atom, datum/thrownthing/throwingdatum)
	PUBLISH_LEGACY(src, /datum/notice/movable_impact, hit_atom, throwingdatum)
	if(isliving(hit_atom))
		var/mob/living/M = hit_atom
		if(M?.buckled_to() == src)
			return // Don't hit the thing we're buckled to.
		M.hitby(src, throwingdatum)

	else if(isobj(hit_atom))
		var/obj/O = hit_atom
		if(!O.anchored)
			step(O, src.last_move)
		O.hitby(src, throwingdatum)

	else if(isturf(hit_atom))
		var/turf/T = hit_atom
		T.hitby(src, throwingdatum)

/atom/movable/proc/throw_at(atom/target, range, speed, mob/thrower, spin = TRUE, then = null, datum/then_owner = null, list/then_with = null) //If this returns FALSE then then_owner.then() will not be called.
	. = TRUE
	if (!target || speed <= 0 || QDELETED(src) || (target.z != src.z))
		return FALSE

	var/mob/pulledby = src?.pulled_by_mob()
	if (pulledby)
		pulledby.stop_pulling()

	var/real_force = 0
	if(isitem(src))
		var/obj/item/thrown_item = src
		real_force = thrown_item.throwforce

	var/datum/thrownthing/TT = new(src, target, dir, range, speed, thrower, FALSE, real_force, FALSE, then, then_owner, then_with)
	rel_set(src, nameof(throwing), TT)

	pixel_z = 0
	if(spin && does_spin)
		SpinAnimation(4,1)

	SSthrow_steps.kernel_join(TT) // code/datums/thrownthing.dm

//Overlays
/atom/movable/overlay
	var/atom/master = null
	anchored = TRUE

// An overlay passes touches and items on to what it overlays.
CAPABILITIES(/atom/movable/overlay)
	op("pass_touch", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(overlay_pass_touch)))
	op("pass_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 2), then(PROC_REF(overlay_pass_item)))

/atom/movable/overlay/proc/overlay_pass_touch(datum/act/op/A)
	var/mob/user = A.actor
	if(master)
		master.attack_hand(user)
	return OP_OK

/atom/movable/overlay/proc/overlay_pass_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(master)
		return master.attackby(W, user) ? OP_OK : OP_PASS
	return OP_OK

/atom/movable/proc/touch_map_edge()
	if(z in using_map.sealed_levels)
		return

	if(using_map.use_overmap)
		overmap_spacetravel(get_turf(src), src)
		return

	var/move_to_z = src.get_transit_zlevel()
	if(move_to_z)
		var/new_z = move_to_z
		var/new_x
		var/new_y

		if(x <= TRANSITIONEDGE)
			new_x = world.maxx - TRANSITIONEDGE - 2
			new_y = rand(TRANSITIONEDGE + 2, world.maxy - TRANSITIONEDGE - 2)

		else if (x >= (world.maxx - TRANSITIONEDGE + 1))
			new_x = TRANSITIONEDGE + 1
			new_y = rand(TRANSITIONEDGE + 2, world.maxy - TRANSITIONEDGE - 2)

		else if (y <= TRANSITIONEDGE)
			new_y = world.maxy - TRANSITIONEDGE -2
			new_x = rand(TRANSITIONEDGE + 2, world.maxx - TRANSITIONEDGE - 2)

		else if (y >= (world.maxy - TRANSITIONEDGE + 1))
			new_y = TRANSITIONEDGE + 1
			new_x = rand(TRANSITIONEDGE + 2, world.maxx - TRANSITIONEDGE - 2)

		if(SSticker && istype(SSticker.mode, /datum/game_mode/nuclear)) //only really care if the game mode is nuclear
			var/datum/game_mode/nuclear/G = SSticker.mode
			G.check_nuke_disks()

		var/turf/T = locate(new_x, new_y, new_z)
		if(istype(T))
			forceMove(T)

//by default, transition randomly to another zlevel
/atom/movable/proc/get_transit_zlevel()
	var/list/candidates = using_map.accessible_z_levels.Copy()
	candidates.Remove("[src.z]")

	if(!candidates.len)
		return null
	return text2num(pickweight(candidates))

// Returns the current scaling of the sprite.
// Note this DOES NOT measure the height or width of the icon, but returns what number is being multiplied with to scale the icons, if any.
/atom/movable/proc/get_icon_scale_x()
	return icon_scale_x

/atom/movable/proc/get_icon_scale_y()
	return icon_scale_y

/atom/movable/proc/update_transform()
	var/matrix/M = matrix()
	M.Scale(icon_scale_x, icon_scale_y)
	M.Turn(icon_rotation)
	src.transform = M

// Use this to set the object's scale.
/atom/movable/proc/adjust_scale(new_scale_x, new_scale_y)
	if(isnull(new_scale_y))
		new_scale_y = new_scale_x
	if(new_scale_x != 0)
		icon_scale_x = new_scale_x
	if(new_scale_y != 0)
		icon_scale_y = new_scale_y
	update_transform()

/atom/movable/proc/adjust_rotation(new_rotation)
	icon_rotation = new_rotation
	update_transform()

// Called when touching a lava tile.
/atom/movable/proc/lava_act()
	fire_act(10000, 1000)

// Procs to cloak/uncloak
/atom/movable/proc/cloak()
	if(!cloak_begin())
		return FALSE
	cloak_animation(1 SECOND) // cloak_finish() when it has played
	return TRUE

/// Cloaking without waiting: marks the atom cloaked and starts the fade. TRUE when it did work.
/// cloak_finish() completes it after the animation (cloak() sleeps for it; a task doesn't).
/atom/movable/proc/cloak_begin()
	if(dq_get_cloaked(src))
		return FALSE
	dq_set_cloaked(src, TRUE)
	dq_set_cloaked_selfimage(src, get_cloaked_selfimage())
	return TRUE

/atom/movable/proc/cloak_finish()
	//Needs to be last so people can actually see the effect before we become invisible
	if(dq_get_cloaked(src)) // Ensure we are still dq_get_cloaked(src) after the animation delay
		plane = CLOAKED_PLANE

/atom/movable/proc/uncloak()
	if(!dq_get_cloaked(src))
		return FALSE
	dq_set_cloaked(src, FALSE)
	. = TRUE // We did work

	var/static/animation_time = 1 SECOND
	// cloaked_selfimage in component
	var/image/csi = dq_get_cloaked_selfimage(src)
	if(csi)
		spent(csi)
		dq_set_cloaked_selfimage(src, null)

	//Needs to be first so people can actually see the effect, so become uninvisible first
	plane = initial(plane)

	//Oooooo
	uncloak_animation(animation_time)

// Animations for cloaking/uncloaking
/atom/movable/proc/cloak_animation(length = 1 SECOND)
	//Save these
	var/initial_alpha = alpha

	//Animate alpha fade
	animate(src, alpha = 0, time = length)

	//Animate a cloaking effect
	var/our_filter = filters.len+1 //Filters don't appear to have a type that can be stored in a var and accessed. This is how the DM reference does it.
	filters += filter(type="wave", x = 0, y = 16, size = 0, offset = 0, flags = WAVE_SIDEWAYS)
	animate(filters[our_filter], offset = 1, size = 8, time = length, flags = ANIMATION_PARALLEL)

	//When the animations finish
	after(src, length + 0.5 SECONDS, PROC_REF(cloak_animation_done), with = list(initial_alpha))

/atom/movable/proc/cloak_animation_done(initial_alpha)
	//Remove those
	filters -= filter(type="wave", x = 0, y = 16, size = 8, offset = 1, flags = WAVE_SIDEWAYS)

	//Back to original alpha
	alpha = initial_alpha
	cloak_finish()

/atom/movable/proc/uncloak_animation(length = 1 SECOND)
	//Save these
	var/initial_alpha = alpha

	//Put us back to normal, but no alpha
	alpha = 0

	//Animate alpha fade up
	animate(src, alpha = initial_alpha, time = length)

	//Animate a cloaking effect
	var/our_filter = filters.len+1 //Filters don't appear to have a type that can be stored in a var and accessed. This is how the DM reference does it.
	filters += filter(type="wave", x=0, y = 16, size = 8, offset = 1, flags = WAVE_SIDEWAYS)
	animate(filters[our_filter], offset = 0, size = 0, time = length, flags = ANIMATION_PARALLEL)

	//When the animations finish
	after(src, length + 0.5 SECONDS, PROC_REF(uncloak_animation_done))

/atom/movable/proc/uncloak_animation_done()
	//Remove those
	filters -= filter(type="wave", x=0, y = 16, size = 0, offset = 0, flags = WAVE_SIDEWAYS)

// So dq_get_cloaked(src) things can see themselves, if necessary
/atom/movable/proc/get_cloaked_selfimage()
	var/icon/selficon = icon(icon, icon_state)
	selficon.MapColors(0,0,0, 0,0,0, 0,0,0, 1,1,1) //White
	var/image/selfimage = image(selficon)
	selfimage.color = "#0000FF"
	selfimage.alpha = 100
	selfimage.layer = initial(layer)
	selfimage.plane = initial(plane)
	image_anchor(selfimage, src)

	return selfimage

/atom/movable/proc/get_cell()
	return

/atom/movable/proc/emblocker_gc(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = N.target
	unobserve(source, /datum/notice/qdeleting, src)
	cut_overlay(source)
	// A blocker deleted from outside leaves em_block in its destroy's phase 2.

/atom/movable/proc/abstract_move(atom/new_loc)
	var/atom/old_loc = loc
	var/direction = get_dir(old_loc, new_loc)
	loc = new_loc // ALLOW(containment): abstract_move(): the deliberate no-Enter/Exit move primitive
	Moved(old_loc, direction, TRUE)

// Helper procs called on entering/exiting a belly. Does nothing by default, override on children for special behavior.
/atom/movable/proc/enter_belly(obj/belly/B)
	return

/atom/movable/proc/exit_belly(obj/belly/B)
	return

/atom/movable/proc/set_listening(set_to)
	if (listening_recursive && !set_to)
		dq_recursive_listeners_remove(src, src)
		if (!dq_recursive_listeners_len(src))
			for (var/atom/movable/location as anything in get_nested_locs(src))
				dq_recursive_listeners_remove(location, src)
	if (!listening_recursive && set_to)
		dq_recursive_listeners_or(src, src)
		for (var/atom/movable/location as anything in get_nested_locs(src))
			dq_recursive_listeners_or(location, src)
	listening_recursive = set_to

///Returns a list of all locations (except the area) the movable is within.
/proc/get_nested_locs(atom/movable/atom_on_location, include_turf = FALSE)
	. = list()
	var/atom/location = atom_on_location.loc
	var/turf/our_turf = get_turf(atom_on_location)
	while(location && location != our_turf)
		. += location
		location = location.loc
	if(our_turf && include_turf) //At this point, only the turf is left, provided it exists.
		. += our_turf

/atom/movable/Exited(atom/movable/gone, atom/new_loc)
	. = ..()

	var/list/gone_listeners = dq_get_recursive_listeners(gone)
	if (!length(gone_listeners))
		return
	for (var/atom/movable/location as anything in get_nested_locs(src)|src)
		for(var/listener in gone_listeners)
			dq_recursive_listeners_remove(location, listener)

/atom/movable/Entered(atom/movable/arrived, atom/old_loc)
	. = ..()

	var/list/arrived_listeners = dq_get_recursive_listeners(arrived)
	if (!length(arrived_listeners))
		return
	for (var/atom/movable/location as anything in get_nested_locs(src)|src)
		for(var/listener in arrived_listeners)
			dq_recursive_listeners_or(location, listener)

/atom/movable/proc/show_message(msg, type, alt, alt_type)//Message, type of message (1 or 2), alternative message, alt message type (1 or 2)
	return

/atom/movable/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION("", "---------")
	VV_DROPDOWN_OPTION(VV_HK_GET_MOVABLE, "Get Movable")
	VV_DROPDOWN_OPTION(VV_HK_EDIT_PARTICLES, "Edit Particles")


/atom/movable/proc/vv_topic_get_movable(datum/act/op/A)
	var/mob/user = A.actor
	if(ismob(src)) // incase there was a client inside an object being yoinked
		var/mob/M = src
		M.reset_perspective(src) // Force reset to self before teleport
	forceMove(get_turf(user))
	return TRUE

/atom/movable/proc/vv_topic_edit_particles(datum/act/op/A)
	var/mob/user = A.actor
	user.client?.open_particle_editor(src)
	return TRUE


// The throw_of relation's view field: its on_unlink() clears it.
