SUBSYSTEM_DEF(explosions)
	name = "Explosions"
	priority = FIRE_PRIORITY_EXPLOSIONS
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	wait = 0.5 SECONDS
	dependencies = list(
		/datum/controller/subsystem/machines
	)
	flags = SS_NO_INIT

	VAR_PRIVATE/resolve_explosions = FALSE
	VAR_PRIVATE/list/currentrun = null
	VAR_PRIVATE/list/currentrun_keys = null
	VAR_PRIVATE/currentrun_index = 1
	VAR_PRIVATE/list/currentsignals = null
	VAR_PRIVATE/list/current_signal_keys = null
	VAR_PRIVATE/current_signal_index = 1
	VAR_PRIVATE/list/pending_explosions = list()
	VAR_PRIVATE/list/resolving_explosions = list()
	VAR_PRIVATE/list/explosion_signals = list()
	VAR_PRIVATE/list/pending_sound_events = list()
	VAR_PRIVATE/atmos_topology_batch_open = FALSE
	VAR_PRIVATE/epoch_started_at = 0
	VAR_PRIVATE/epoch_prepare_ms = 0
	VAR_PRIVATE/epoch_resolve_ms = 0
	VAR_PRIVATE/epoch_turfs_prepared = 0
	VAR_PRIVATE/epoch_turfs_resolved = 0
	VAR_PRIVATE/epoch_submissions = 0
	VAR_PRIVATE/epoch_visuals = 0
	VAR_PRIVATE/last_epoch_ms = 0
	/// Epoch-wide blast batches (damage.md §7): type -> list of atoms. Turfs
	/// collect strongest severity first; atoms receive their packets only after
	/// all turf transformations complete, one type batch at a time.
	VAR_PRIVATE/list/blast_batches = list()
	/// Every batch (a list of atoms) in the order it was opened. A type whose
	/// batch is already delivered opens a new one (contents spilled late).
	VAR_PRIVATE/list/blast_batch_order = list()
	VAR_PRIVATE/blast_batch_type_index = 1
	VAR_PRIVATE/blast_batch_atom_index = 2
	/// Most atoms that receive a blast packet in one fire(); the rest resume next fire.
	var/blast_batch_budget = 1024
	VAR_PRIVATE/epoch_blast_batches = 0
	/// Atoms may move between affected turfs or be reached by several nested cell
	/// blasts. Strongest-first resolution plus this epoch set guarantees one
	/// ex_act per atom instead of repeatedly destroying the same ownership graph.
	VAR_PRIVATE/list/resolved_atoms = list()
	VAR_PRIVATE/epoch_atoms_resolved = 0
	VAR_PRIVATE/epoch_atoms_deduplicated = 0
	/// Changed turfs (turf -> TRUE, in insertion order). Turfs are changed in
	/// place, so the ref itself is the key; no coordinate strings.
	VAR_PRIVATE/list/deferred_turf_updates = list()
	VAR_PRIVATE/deferred_turf_update_index = 1
	/// Changed turfs and their neighbours, for one appearance update each.
	VAR_PRIVATE/list/deferred_appearance_updates = list()
	VAR_PRIVATE/deferred_appearance_update_index = 1
	VAR_PRIVATE/bulk_resolution_active = FALSE
	VAR_PRIVATE/list/explosion_resistance_cache = list()
	VAR_PRIVATE/epoch_atom_collect_ms = 0
	VAR_PRIVATE/epoch_atom_resolve_ms = 0
	/// Optional low-rate concrete-type timing, enabled by destructive benchmarks.
	var/profile_atom_types = FALSE
	VAR_PRIVATE/atom_profile_index = 0
	VAR_PRIVATE/atom_profile_stride = 16
	VAR_PRIVATE/list/atom_profile_cost = list()
	VAR_PRIVATE/list/atom_profile_calls = list()

/datum/controller/subsystem/explosions/stat_entry(msg)
	var/meme = ""
	switch(length(resolving_explosions))
		if(0 to 10000) meme = ""
		if(10000 to 15000) meme = "- HEAVY LOAD"
		if(15000 to 20000) meme = "- EXTREME LOAD"
		if(20000 to 25000) meme = "- I STILL FUNCTION"
		if(25000 to 30000) meme = "- WANNA BET?"
		if(30000 to INFINITY) meme = "- CALL /abort() TO FORCE END"
	var/remaining = max(0, LAZYLEN(currentrun_keys) - currentrun_index + 1)
	msg = "E:[epoch_submissions] P:[length(pending_explosions)] R:[length(resolving_explosions)] CR:[remaining] [resolve_explosions ? "RESOLVE" : remaining ? "PREP" : "IDLE"] last:[round(last_epoch_ms, 0.1)]ms prep:[round(epoch_prepare_ms, 0.1)]ms resolve:[round(epoch_resolve_ms, 0.1)]ms [meme]"
	return ..()

/datum/controller/subsystem/explosions/proc/performance_diagnostics()
	return list(
		"phase" = resolve_explosions ? "resolve" : currentrun_index <= LAZYLEN(currentrun_keys) ? "prepare" : "idle",
		"pending" = length(pending_explosions),
		"prepared" = length(resolving_explosions),
		"current" = max(0, LAZYLEN(currentrun_keys) - currentrun_index + 1),
		"signals" = length(explosion_signals),
		"epoch_submissions" = epoch_submissions,
		"epoch_prepare_ms" = epoch_prepare_ms,
		"epoch_resolve_ms" = epoch_resolve_ms,
		"epoch_turfs_prepared" = epoch_turfs_prepared,
		"epoch_turfs_resolved" = epoch_turfs_resolved,
		"epoch_visuals" = epoch_visuals,
		"epoch_atoms_resolved" = epoch_atoms_resolved,
		"epoch_atoms_deduplicated" = epoch_atoms_deduplicated,
		"epoch_blast_batches" = epoch_blast_batches,
		"epoch_atom_collect_ms" = epoch_atom_collect_ms,
		"epoch_atom_resolve_ms" = epoch_atom_resolve_ms,
		"deferred_turf_updates" = max(0, length(deferred_turf_updates) - deferred_turf_update_index + 1),
		"deferred_appearance_updates" = max(0, length(deferred_appearance_updates) - deferred_appearance_update_index + 1),
		"last_epoch_wall_ms" = last_epoch_ms,
		"topology_batch_open" = atmos_topology_batch_open,
	)

/datum/controller/subsystem/explosions/proc/gotosleep()
	can_fire = FALSE

/datum/controller/subsystem/explosions/proc/wakeup()
	can_fire = TRUE
	next_fire = world.time

/datum/controller/subsystem/explosions/fire(resumed)
	// Build both queues. The first one gets the explosion power in each turf
	// The second queue applies that explosion power to all turfs and objects in them
	if(!resumed)
		dispatch_sound_events()
		if(resolve_explosions && currentrun_index > LAZYLEN(currentrun_keys))
			end_resolve()
		if(!resolve_explosions)
			// Setup the explosion buffer!
			load_currentrun(pending_explosions)
			currentsignals = explosion_signals.Copy()
			pending_explosions.Cut()
			explosion_signals.Cut()
	if(currentrun_index > LAZYLEN(currentrun_keys) && !resolve_explosions) // Wait till we're useful if we have nothing to do!
		gotosleep()
		return

	// The heavy lifting part...
	var/profile_resolve_phase = resolve_explosions
	var/phase_profile_start = TICK_USAGE
	while(currentrun_index <= length(currentrun_keys))
		// Lets handle list management here instead of in each proc
		// get the first key of the current run, use the key to get the
		// data, use the data, than discard it from the list using the key!
		var/key = currentrun_keys[currentrun_index]
		var/entry_complete = TRUE
		if(resolve_explosions)
			entry_complete = fire_resolve_explosions(currentrun[key])
			if(entry_complete)
				epoch_turfs_resolved++
		else
			fire_prepare_explosions(currentrun[key])
			epoch_turfs_prepared++
		if(entry_complete)
			currentrun_index++
		else
			record_turf_phase_cost(profile_resolve_phase, phase_profile_start)
			return

		// Check if we move on to final resolution
		if(currentrun_index > length(currentrun_keys))
			if(!resolve_explosions)
				start_resolve()
				load_currentrun(resolving_explosions, TRUE)
				resolving_explosions.Cut()
				record_turf_phase_cost(profile_resolve_phase, phase_profile_start)
				return
			break // In resolution mode, break into final res ahead

		if(MC_TICK_CHECK)
			record_turf_phase_cost(profile_resolve_phase, phase_profile_start)
			return
	record_turf_phase_cost(profile_resolve_phase, phase_profile_start)

	if(resolve_explosions && !deliver_blast_batches())
		return
	if(resolve_explosions && !flush_deferred_turf_updates())
		return

	// Finalization is resumable too. A cascade can contain thousands of nested
	// submissions; emitting every global signal in one call used to defeat the
	// carefully bounded turf/atom phases above.
	if(!current_signal_keys)
		current_signal_keys = list()
		for(var/signal_key in currentsignals)
			current_signal_keys += signal_key
		current_signal_index = 1
	while(current_signal_index <= length(current_signal_keys))
		var/signal_key = current_signal_keys[current_signal_index++]
		var/list/time_dat = currentsignals[signal_key]
		var/turf/epicenter = locate(time_dat[1],time_dat[2],time_dat[3])
		if(!epicenter)
			continue
		var/z_transfer			= time_dat[8]
		if(z_transfer != (UP|DOWN)) // Only the initial explosion in a multiz explosion transfers both up and down!
			continue
		var/devastation_range 	= time_dat[4]
		var/heavy_impact_range 	= time_dat[5]
		var/light_impact_range 	= time_dat[6]
		var/took 				= (world.time - time_dat[7]) / (1 SECOND) // Horrifyingly, this has always been server performance dependant. Should really only be used for cosmetic stuff.
		SEND_GLOBAL_SIGNAL(COMSIG_GLOB_EXPLOSION, epicenter, devastation_range, heavy_impact_range, light_impact_range, took)
		if(MC_TICK_CHECK)
			return
	currentsignals.Cut()
	current_signal_keys = null
	current_signal_index = 1

	// return to setup mode... Unless...
	end_resolve()
	if(!length(pending_explosions))
		last_epoch_ms = (REALTIMEOFDAY - epoch_started_at) * 100
		dump_atom_profile()
		log_runtime("EXPLOSION_PROFILE [json_encode(performance_diagnostics())]")
		suspend_and_invoke_deferred_subsystems()

/datum/controller/subsystem/explosions/proc/record_turf_phase_cost(resolve_phase, profile_start)
	if(resolve_phase)
		epoch_resolve_ms += TICK_DELTA_TO_MS(TICK_USAGE - profile_start)
	else
		epoch_prepare_ms += TICK_DELTA_TO_MS(TICK_USAGE - profile_start)

/datum/controller/subsystem/explosions/proc/load_currentrun(list/source, strongest_first = FALSE)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	currentrun = source.Copy()
	currentrun_keys = list()
	if(strongest_first)
		var/list/high = list()
		var/list/medium = list()
		var/list/low = list()
		for(var/key in source)
			var/list/data = source[key]
			var/ratio = data[4] / max(3, data[5] / 3)
			if(ratio >= 2.5)
				high += key
			else if(ratio >= 1.5)
				medium += key
			else
				low += key
		currentrun_keys = high + medium + low
	else
		for(var/key in source)
			currentrun_keys += key
	currentrun_index = 1

/datum/controller/subsystem/explosions/proc/queue_sound_event(turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range)
	// Every per-turf table is keyed by the turf itself: turfs change in place,
	// so the ref is stable, and it costs no key string per visit.
	var/key = epicenter
	var/list/prior = pending_sound_events[key]
	if(!prior || max(devastation_range, heavy_impact_range, light_impact_range) > max(prior[2], prior[3], prior[4]))
		pending_sound_events[key] = list(epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range)

/datum/controller/subsystem/explosions/proc/dispatch_sound_events()
	if(!length(pending_sound_events))
		return
	// One perceptual event per listener and subsystem slice. Cascading cells no
	// longer perform two complete player-list scans apiece or layer hundreds of
	// identical sounds; each player hears the strongest/closest queued blast.
	for(var/mob/M in GLOB.player_list)
		var/list/best
		var/best_score = -INFINITY
		var/best_distance = INFINITY
		for(var/key in pending_sound_events)
			var/list/event = pending_sound_events[key]
			var/turf/epicenter = event[1]
			if(!epicenter || epicenter.z != M.z)
				continue
			var/distance = get_dist(get_turf(M), epicenter)
			var/score = event[2] * 20 + event[3] * 5 + event[4] - distance
			if(score > best_score)
				best = event
				best_score = score
				best_distance = distance
		if(!best)
			continue
		var/turf/epicenter = best[1]
		var/max_range = max(best[2], best[3], best[4], best[5])
		var/far_dist = best[3] * 5 + best[2] * 20
		if(best_distance <= round(max_range + world.view - 2, 1))
			M.playsound_local(epicenter, get_sfx("explosion"), 100, TRUE, get_rand_frequency(), falloff = 5)
			if(isliving(M))
				var/mob/living/living_listener = M
				living_listener.deaf_loop.start()
		else if(best_distance <= far_dist || !istype(M.loc, /turf/space))
			var/far_volume = CLAMP(far_dist, 30, 50) + (best_distance <= far_dist * 0.5 ? 50 : 0)
			M.playsound_local(epicenter, 'sound/effects/explosionfar.ogg', far_volume, TRUE, get_rand_frequency(), falloff = 5)
	pending_sound_events.Cut()

/datum/controller/subsystem/explosions/proc/fire_prepare_explosions(list/data)
	var/pwr = data[4]
	var/direction = data[5]
	var/starting_power = data[6]
	if(pwr <= 0)
		return
	//This step handles the gathering of turfs which will be ex_act() -ed in the next step. It also ensures each turf gets the maximum possible amount of power dealt to it.
	var/turf/epicenter = locate(data[1],data[2],data[3])
	if(!epicenter)
		return
	var/list/res_explo = resolving_explosions[epicenter] // check if this has already resolved
	if(res_explo && res_explo[4] >= pwr)
		return
	if(direction)
		//This is the amount of power that will be spread to the tile in the direction of the blast, subtracted from everything blocking it in the turf!
		var/spread_power = pwr - cached_explosion_resistance(epicenter)
		if(spread_power > 0)
			// Fan outward from the original explosion
			var/turf/T = get_step(epicenter, direction)
			if(T)
				append_currentrun(T,spread_power,direction,starting_power)
				T = get_step(epicenter, turn(direction,90))
				if(T)
					append_currentrun(T,spread_power,direction,starting_power)
				T = get_step(epicenter, turn(direction,-90))
				if(T)
					append_currentrun(T,spread_power,direction,starting_power)
			// Make these feel a little more flashy
			if(epoch_visuals < 64 && spread_power > 3 && spread_power < GLOB.max_explosion_range && prob(6)) // bombs above maxcap are probably badmins, lets not make 10000 effects
				epoch_visuals++
				if(prob(30))
					var/datum/effect/effect/system/smoke_spread/S = new/datum/effect/effect/system/smoke_spread()
					S.set_up(2,0,epicenter,direction)
					S.start()
				else
					var/datum/effect/system/expl_particles/P = new/datum/effect/system/expl_particles()
					P.set_up(2,epicenter,direction)
					P.start()
	// Build the final explosion list, will be processed when we get to final resolution
	finalize_explosion(epicenter,pwr,starting_power)

/datum/controller/subsystem/explosions/proc/fire_resolve_explosions(list/data)
	var/pwr = data[4]
	var/starting_power = data[5]
	if(pwr <= 0)
		return
	var/turf/T = locate(data[1],data[2],data[3])
	if(!T)
		return TRUE
	//Wow severity looks confusing to calculate... Fret not, I didn't leave you with any additional instructions or help. (just kidding, see the line under the calculation)
	var/severity = 4 - round(max(min( 3, ((pwr - T.explosion_resistance) / (max(3,(starting_power/3)))) ) ,1), 1)								//sanity			effective power on tile				divided by either 3 or one third the total explosion power
							//															One third because there are three power levels and I
							//															want each one to take up a third of the crater
	var/collect_start = TICK_USAGE
	for(var/atom/movable/AM as anything in T)
		queue_blast(AM, severity)
	epoch_atom_collect_ms += TICK_DELTA_TO_MS(TICK_USAGE - collect_start)
	T.ex_act(severity)
	return TRUE

/// Queue `AM` for a blast packet this epoch. Each atom is hit once, at the
/// strongest severity that reached it. Bomb-proof atoms are never queued.
/datum/controller/subsystem/explosions/proc/queue_blast(atom/movable/AM, severity)
	if(!AM || QDELETED(AM) || !AM.simulated)
		return
	if(isobj(AM))
		var/obj/O = AM
		if(O.resistance_flags & BOMB_PROOF)
			return
	var/prior_severity = resolved_atoms[AM]
	if(prior_severity)
		epoch_atoms_deduplicated++
		if(severity < prior_severity)
			resolved_atoms[AM] = severity
		return
	resolved_atoms[AM] = severity
	var/list/batch = blast_batches[AM.type]
	if(!batch)
		batch = list(AM.type) // [1] is the batch's type; atoms follow
		blast_batches[AM.type] = batch
		blast_batch_order[++blast_batch_order.len] = batch
	batch += AM

/// Deliver queued blast packets, one type batch at a time, to at most
/// `budget` atoms. Containers queue their contents into the same epoch, in
/// bulk, before their own packet lands (a destroyed container spills them).
/// Returns TRUE once every batch is delivered.
/datum/controller/subsystem/explosions/proc/deliver_blast_batches(budget = blast_batch_budget, tick_checked = TRUE)
	var/profile_start = TICK_USAGE
	var/delivered = 0
	while(blast_batch_type_index <= length(blast_batch_order))
		var/list/batch = blast_batch_order[blast_batch_type_index]
		if(blast_batch_atom_index == 2)
			epoch_blast_batches++
		while(blast_batch_atom_index <= length(batch))
			if(delivered >= budget || (tick_checked && MC_TICK_CHECK))
				epoch_atom_resolve_ms += TICK_DELTA_TO_MS(TICK_USAGE - profile_start)
				return FALSE
			var/atom/movable/AM = batch[blast_batch_atom_index++]
			delivered++
			if(!AM || QDELETED(AM))
				continue
			var/severity = resolved_atoms[AM]
			if(!severity)
				continue
			var/has_latent = AM.has_latent()
			var/contents_severity = (length(AM.contents) || has_latent) ? AM.explosion_contents_severity(severity) : 0
			if(contents_severity && has_latent)
				AM.latent_blast(contents_severity) // entries resolve as data (C5)
			if(contents_severity)
				for(var/atom/movable/inner as anything in AM.contents)
					queue_blast(inner, contents_severity)
			epoch_atoms_resolved++
			atom_profile_index++
			if(profile_atom_types && !(atom_profile_index % atom_profile_stride))
				var/atom_type = "[AM.type]"
				var/atom_started = TICK_USAGE
				AM.ex_act(severity)
				atom_profile_cost[atom_type] += TICK_DELTA_TO_MS(TICK_USAGE - atom_started) * atom_profile_stride
				atom_profile_calls[atom_type] += atom_profile_stride
			else
				AM.ex_act(severity)
		// Later atoms of this type (spilled contents) open a fresh batch.
		var/batch_type = batch[1]
		if(blast_batches[batch_type] == batch)
			blast_batches -= batch_type
		blast_batch_type_index++
		blast_batch_atom_index = 2
	epoch_atom_resolve_ms += TICK_DELTA_TO_MS(TICK_USAGE - profile_start)
	clear_blast_batches()
	return TRUE

/datum/controller/subsystem/explosions/proc/clear_blast_batches()
	blast_batches.Cut()
	blast_batch_order.Cut()
	blast_batch_type_index = 1
	blast_batch_atom_index = 2
	resolved_atoms.Cut()

/// Pending atoms, for tests and diagnostics.
/datum/controller/subsystem/explosions/proc/pending_blast_count()
	. = 0
	for(var/i in blast_batch_type_index to length(blast_batch_order))
		var/list/batch = blast_batch_order[i]
		. += length(batch) - 1
	if(blast_batch_type_index <= length(blast_batch_order))
		. -= blast_batch_atom_index - 2

/datum/controller/subsystem/explosions/proc/dump_atom_profile()
	if(!profile_atom_types || !length(atom_profile_cost))
		return
	var/list/sorted_cost = atom_profile_cost.Copy()
	sortTim(sorted_cost, /proc/cmp_numeric_desc, TRUE)
	var/rank = 0
	for(var/atom_type in sorted_cost)
		log_runtime("EXPLOSION_ATOM_PROFILE type=[atom_type] estimated_cost_ms=[round(atom_profile_cost[atom_type], 0.01)] estimated_calls=[atom_profile_calls[atom_type]]")
		if(++rank >= 25)
			break

/datum/controller/subsystem/explosions/proc/cached_explosion_resistance(turf/T)
	. = explosion_resistance_cache[T]
	if(!isnull(.))
		return
	. = T.explosion_resistance
	for(var/obj/O in T)
		. += O.explosion_resistance
	explosion_resistance_cache[T] = .

/datum/controller/subsystem/explosions/proc/start_resolve()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	resolve_explosions = TRUE
	bulk_resolution_active = TRUE

/datum/controller/subsystem/explosions/proc/end_resolve()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	resolve_explosions = FALSE
	bulk_resolution_active = FALSE

/datum/controller/subsystem/explosions/proc/is_bulk_resolving()
	return bulk_resolution_active

/datum/controller/subsystem/explosions/proc/defer_turf_update(turf/T)
	if(!T)
		return
	if(deferred_turf_updates[T])
		return // its neighbourhood is already queued too
	deferred_turf_updates[T] = TRUE
	for(var/turf/neighbor as anything in RANGE_TURFS(1, T))
		deferred_appearance_updates[neighbor] = TRUE

/datum/controller/subsystem/explosions/proc/flush_deferred_turf_updates()
	while(deferred_turf_update_index <= length(deferred_turf_updates))
		var/turf/T = deferred_turf_updates[deferred_turf_update_index++]
		T?.finalize_explosion_deferred_change(FALSE)
		if(MC_TICK_CHECK)
			return FALSE
	deferred_turf_updates.Cut()
	deferred_turf_update_index = 1
	while(deferred_appearance_update_index <= length(deferred_appearance_updates))
		var/turf/T = deferred_appearance_updates[deferred_appearance_update_index++]
		T?.finalize_explosion_deferred_appearance()
		if(MC_TICK_CHECK)
			return FALSE
	deferred_appearance_updates.Cut()
	deferred_appearance_update_index = 1
	return TRUE

/datum/controller/subsystem/explosions/proc/wake_and_defer_subsystem_updates()
	// Even a small blast can destroy a cell, cable, or pipe.  Keep one
	// transaction open for the complete nested explosion epoch: every cable
	// the blast removes reaches Rust as one power commit. Gas geometry needs
	// no matching begin/commit here (unlike master's old turf-adjacency-graph
	// atmos, M1b's field applies the whole epoch's turf commands in order at
	// its next frame) -- only the power side batches.
	if(!atmos_topology_batch_open)
		atmos_topology_batch_open = TRUE
		SSmachines.power_batch_begin()
	// waking from sleep, we are absolutely not resuming, and INSTANT feedback to players is required here.
	if(can_fire) // already awake
		return
	epoch_started_at = REALTIMEOFDAY
	epoch_prepare_ms = 0
	epoch_resolve_ms = 0
	epoch_turfs_prepared = 0
	epoch_turfs_resolved = 0
	epoch_submissions = 0
	epoch_visuals = 0
	epoch_atoms_resolved = 0
	epoch_atoms_deduplicated = 0
	epoch_blast_batches = 0
	epoch_atom_collect_ms = 0
	epoch_atom_resolve_ms = 0
	atom_profile_index = 0
	atom_profile_cost.Cut()
	atom_profile_calls.Cut()
	clear_blast_batches()
	explosion_resistance_cache.Cut()
	deferred_turf_updates.Cut()
	deferred_turf_update_index = 1
	deferred_appearance_updates.Cut()
	deferred_appearance_update_index = 1
	current_signal_keys = null
	current_signal_index = 1
	wakeup()

/datum/controller/subsystem/explosions/proc/suspend_and_invoke_deferred_subsystems()
	// Resolve all the stuff we put off for after the explosion resolved
	if(atmos_topology_batch_open)
		atmos_topology_batch_open = FALSE
		SSair.rust_commit_pending_pipenets()
		SSmachines.power_batch_end()
	SSmachines.flush_gas_watch_updates()
	// we've finished. Pause because was have no more work to do.
	if(!can_fire) // already asleep
		return
	gotosleep()

/datum/controller/subsystem/explosions/proc/abort()
	if(currentrun_index > LAZYLEN(currentrun_keys))
		return
	// Removes all entries except the top most, so we enter resolution phase properly, need at least one entry to do so...
	var/key = currentrun_keys[currentrun_index]
	var/data = currentrun[key]
	currentrun = list()
	currentrun[key] = data
	currentrun_keys = list(key)
	currentrun_index = 1

// INTERNAL explosion proc, meant for GROWING a currently processing blast.
/datum/controller/subsystem/explosions/proc/append_currentrun(turf/key,pwr,direction,starting_power)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	if(pwr <= 0)
		return
	// check if there is already an explosion calculated by our current run...
	var/final_data = resolving_explosions[key]
	var/final_power = 0
	if(final_data)
		final_power = final_data[4]
	// If there is already a stronger explosion calculated there, then we don't need to bother
	if(pwr <= final_power)
		return
	// Update data at position for next run. Floodfill until the current_run is empty of new explosions!
	var/max_starting = starting_power
	var/list/dat = currentrun[key]
	if(!isnull(dat) && dat[6] > max_starting)
		max_starting = dat[6]
	if(isnull(dat) || pwr >= dat[4])
		if(isnull(dat))
			currentrun_keys += key
		currentrun[key] = list(key.x,key.y,key.z,pwr,direction,max_starting)

// Queue explosion event, call this from explosion() ONLY
/datum/controller/subsystem/explosions/proc/append_explosion(turf/epicenter, pwr, devastation_range, heavy_impact_range, light_impact_range, flash_range, z_transfer)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(pwr <= 0)
		return
	var/x0 = epicenter.x
	var/y0 = epicenter.y
	var/z0 = epicenter.z
	// actual explosion. Do not allow multiple, just take the highest power explosion hitting that turf
	var/max_starting = pwr
	var/key = epicenter
	var/list/dat = pending_explosions[key]
	if(!isnull(dat) && dat[6] > max_starting)
		max_starting = dat[6]
	if(isnull(dat) || pwr >= dat[4])
		// primary explosion
		pending_explosions[key] = list(x0,y0,z0,pwr,0,max_starting)
		// outward radiating explosions
		var/rad_power = pwr - epicenter.explosion_resistance
		for(var/direction in GLOB.cardinal)
			var/turf/T = get_step(epicenter, direction)
			if(T)
				dat = pending_explosions[T]
				max_starting = pwr
				if(!isnull(dat) && dat[6] > max_starting)
					max_starting = dat[6]
				if(isnull(dat) || rad_power >= dat[4])
					pending_explosions[T] = list(T.x,T.y,T.z,rad_power,direction,max_starting)

	// send signals to dopplers
	var/list/prior_signal = explosion_signals[key]
	if(!prior_signal || max(devastation_range, heavy_impact_range, light_impact_range) > max(prior_signal[4], prior_signal[5], prior_signal[6]))
		explosion_signals[key] = list(x0, y0, z0, devastation_range, heavy_impact_range, light_impact_range, world.time, z_transfer)
	// BOINK! Time to wake up sleeping beauty!
	wake_and_defer_subsystem_updates()
	epoch_submissions++

// Collect prepared explosions for BLAST PROCESSING
/datum/controller/subsystem/explosions/proc/finalize_explosion(turf/key,pwr,max_starting)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	if(pwr <= 0)
		return
	var/list/dat = resolving_explosions[key]
	if(isnull(dat) || pwr >= dat[4])
		resolving_explosions[key] = list(key.x,key.y,key.z,pwr,max_starting)

/proc/explosion(turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range, adminlog = 1, z_transfer = UP|DOWN, shaped)
	// Rarely objects might explode during init... Don't.
	if(!SSticker.HasRoundStarted())
		return

	// Lets assume recursive prey has happened...
	var/limit_escape = 10
	while(isbelly(epicenter))
		if(limit_escape-- <= 0)
			break
		var/obj/belly/B = epicenter
		epicenter = B.owner.loc
	epicenter = get_turf(epicenter)
	if(!epicenter)
		return

	// Handles recursive propagation of explosions.
	var/multi_z_scalar = CONFIG_GET(number/multi_z_explosion_scalar)
	if(z_transfer && multi_z_scalar)
		var/adj_dev   = max(0, (multi_z_scalar * devastation_range) - (shaped ? 2 : 0) )
		var/adj_heavy = max(0, (multi_z_scalar * heavy_impact_range) - (shaped ? 2 : 0) )
		var/adj_light = max(0, (multi_z_scalar * light_impact_range) - (shaped ? 2 : 0) )
		var/adj_flash = max(0, (multi_z_scalar * flash_range) - (shaped ? 2 : 0) )
		if(adj_dev > 0 || adj_heavy > 0)
			if(HasAbove(epicenter.z) && z_transfer & UP)
				explosion(GetAbove(epicenter), round(adj_dev), round(adj_heavy), round(adj_light), round(adj_flash), 0, UP, shaped)
			if(HasBelow(epicenter.z) && z_transfer & DOWN)
				explosion(GetBelow(epicenter), round(adj_dev), round(adj_heavy), round(adj_light), round(adj_flash), 0, DOWN, shaped)
	SSexplosions.queue_sound_event(epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range)

	if(adminlog)
		message_admins("Explosion with [shaped ? "shaped" : "non-shaped"] size ([devastation_range], [heavy_impact_range], [light_impact_range]) in area [epicenter.loc.name] ([epicenter.x],[epicenter.y],[epicenter.z]) (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[epicenter.x];Y=[epicenter.y];Z=[epicenter.z]'>JMP</a>)")
		log_game("Explosion with [shaped ? "shaped" : "non-shaped"] size ([devastation_range], [heavy_impact_range], [light_impact_range]) in area [epicenter.loc.name] ")

	if(heavy_impact_range > 1)
		var/datum/effect/system/explosion/E = new/datum/effect/system/explosion()
		E.set_up(epicenter)
		E.start()

	// Queue explosion event
	var/power = devastation_range * 2 + heavy_impact_range + light_impact_range //The ranges add up, ie light 14 includes both heavy 7 and devestation 3. So this calculation means devestation counts for 4, heavy for 2 and light for 1 power, giving us a cap of 27 power.
	SSexplosions.append_explosion(epicenter,power,devastation_range,heavy_impact_range,light_impact_range,flash_range,z_transfer)
