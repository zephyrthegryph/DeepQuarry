// The explosion system's API (code/game/objects/explosion_service.dm declares the system).
//
//   SSexplosions.append_explosion(...)                  queue one explosion cell (explosion() calls it)
//   SSexplosions.queue_sound_event(...)                 queue an explosion's sound for the epoch
//   SSexplosions.queue_blast(atom, severity)            queue a blast packet for an atom
//   SSexplosions.deliver_blast_batches(budget, tick_checked)  deliver the queued blast batches
//   SSexplosions.pending_blast_count()                  atoms still waiting for a blast packet
//   SSexplosions.is_bulk_resolving()                    TRUE while an epoch resolves (callers defer their own updates)
//   SSexplosions.defer_turf_update(turf)                a changed turf is updated once at the end of the epoch
//   SSexplosions.wake_and_defer_subsystem_updates()     open the epoch's deferred batches
//   SSexplosions.wakeup() / abort()                     start an epoch / end it now
//   SSexplosions.performance_diagnostics()              the epoch's counters

// Queue explosion event, call this from explosion() ONLY
/datum/system/explosions/proc/append_explosion(turf/epicenter, pwr, devastation_range, heavy_impact_range, light_impact_range, flash_range, z_transfer)
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

/datum/system/explosions/proc/queue_sound_event(turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range)
	// Every per-turf table is keyed by the turf itself: turfs change in place,
	// so the ref is stable, and it costs no key string per visit.
	var/key = epicenter
	var/list/prior = pending_sound_events[key]
	if(!prior || max(devastation_range, heavy_impact_range, light_impact_range) > max(prior[2], prior[3], prior[4]))
		pending_sound_events[key] = list(epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range)

/// Queue `AM` for a blast packet this epoch. Each atom is hit once, at the
/// strongest severity that reached it. Bomb-proof atoms are never queued.
/datum/system/explosions/proc/queue_blast(atom/movable/AM, severity)
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
			resolved_atoms[AM] = severity // ALLOW(ownership): per-epoch scratch map atom -> severity number, Cut() at the end of the same epoch
		return
	resolved_atoms[AM] = severity // ALLOW(ownership): per-epoch scratch map atom -> severity number, Cut() at the end of the same epoch
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
/datum/system/explosions/proc/deliver_blast_batches(budget = blast_batch_budget, tick_checked = TRUE)
	// Everything this slice of blast packets destroys goes as one batched
	// destroy (code/datums/lifecycle/batch.dm), run before returning.
	dq_destroy_collect_begin()
	. = deliver_blast_batches_collected(budget, tick_checked)
	epoch_batched_destroys += dq_destroy_collect_end()

/// Pending atoms, for tests and diagnostics.
/datum/system/explosions/proc/pending_blast_count()
	. = 0
	for(var/i in blast_batch_type_index to length(blast_batch_order))
		var/list/batch = blast_batch_order[i]
		. += length(batch) - 1
	if(blast_batch_type_index <= length(blast_batch_order))
		. -= blast_batch_atom_index - 2

/datum/system/explosions/proc/is_bulk_resolving()
	return bulk_resolution_active

/datum/system/explosions/proc/defer_turf_update(turf/T)
	if(!T)
		return
	if(deferred_turf_updates[T])
		return // its neighbourhood is already queued too
	deferred_turf_updates[T] = TRUE
	for(var/turf/neighbor as anything in RANGE_TURFS(1, T))
		deferred_appearance_updates[neighbor] = TRUE

/datum/system/explosions/proc/wake_and_defer_subsystem_updates()
	// Even a small blast can destroy a cell, cable, or pipe.  Keep one
	// transaction open for the complete nested explosion epoch: every cable
	// the blast removes reaches Rust as one power commit. Gas geometry needs
	// no matching begin/commit here (unlike master's old turf-adjacency-graph
	// atmos, M1b's field applies the whole epoch's turf commands in order at
	// its next frame) -- only the power side batches.
	if(!atmos_topology_batch_open)
		atmos_topology_batch_open = TRUE
		SScontracts?.begin_contract_batch()
	// waking from sleep, we are absolutely not resuming, and INSTANT feedback to players is required here.
	if(awake) // already awake
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
	epoch_batched_destroys = 0
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

/// Starts an epoch: the work item steps at the kernel's next pass.
/datum/system/explosions/proc/wakeup()
	awake = TRUE
	wake_work_item(PROC_REF(explosion_step))

/datum/system/explosions/proc/abort()
	if(currentrun_index > LAZYLEN(currentrun_keys))
		return
	// Removes all entries except the top most, so we enter resolution phase properly, need at least one entry to do so...
	var/key = currentrun_keys[currentrun_index]
	var/data = currentrun[key]
	currentrun = list()
	currentrun[key] = data
	currentrun_keys = list(key)
	currentrun_index = 1

/datum/system/explosions/proc/performance_diagnostics()
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
		"epoch_batched_destroys" = epoch_batched_destroys,
		"epoch_atom_collect_ms" = epoch_atom_collect_ms,
		"epoch_atom_resolve_ms" = epoch_atom_resolve_ms,
		"deferred_turf_updates" = max(0, length(deferred_turf_updates) - deferred_turf_update_index + 1),
		"deferred_appearance_updates" = max(0, length(deferred_appearance_updates) - deferred_appearance_update_index + 1),
		"last_epoch_wall_ms" = last_epoch_ms,
		"topology_batch_open" = atmos_topology_batch_open,
	)
