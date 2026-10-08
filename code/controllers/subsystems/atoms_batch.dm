// Chunked materialize (Phase 4 track 4d, doc/rewrite/init_and_turfs.md sec 3.3a).
//
// Every SSatoms.InitializeAtoms() call is one /datum/materialize_batch frame. The frame
// initializes (and so materializes) its atoms in chunks of MATERIALIZE_CHUNK_SIZE and may
// yield to the MC only between two chunks. Ordering rules the frames keep:
//
// 1. Atoms initialize in the order the caller listed them (areas, turfs, then movables for
//    a template); a yield never reorders or skips one.
// 2. A frame's after_init() entries (code/engine/actions/after_init.dm) run after every atom of that frame has initialized.
// 3. Deferred work (BATCH_WORK_*: adjacency recomputes, cable binds) belongs to the frame that
//    owns it and flushes once when that frame closes, before its after_init() entries,
//    in BATCH_WORK_* order.
// 4. A frame opened while another frame is running (a nested InitializeAtoms() from inside
//    an Initialize()) joins it: its deferred work goes to the running frame's owner, as the
//    shared lists did before. Its own after_init() entries still run when it closes.
// 5. While a frame is suspended at a yield, no frame is active: atoms other code creates
//    meanwhile initialize and bind normally instead of queueing into the sleeping frame,
//    and a frame opened meanwhile owns its own work.
//
// Callers defer work with SSatoms.batch_defer(kind, thing), which returns TRUE when a frame
// took it, and drop it with SSatoms.batch_undefer(kind, thing).

/datum/materialize_batch
	/// The SSatoms tracked-initialization source this frame holds.
	var/source
	/// The frame that owns this frame's deferred work: itself, or the frame it joined.
	/// Transient: set while the frame is open (an owner's self-reference is cleared at close).
	var/tmp/datum/materialize_batch/owner
	/// What SSatoms.active_batch was when this frame opened; restored and cleared at close.
	var/tmp/datum/materialize_batch/previous
	/// BATCH_WORK_* -> (thing -> TRUE). Only an owner frame has one.
	var/list/work
	/// Map-loaded instances of this frame with after_init() entries: armed when the frame closes, after every atom of the load exists.
	var/list/after_inits
	/// Movables this frame created from templates, when the caller asked for them.
	var/list/created_atoms
	/// Chunks initialized and yields taken (tests and the boot log read them).
	var/chunks = 0
	var/yields = 0
	var/closed = FALSE

// Links between open frames; nothing here owns what it names.

/datum/materialize_batch/New(source, datum/materialize_batch/running)
	src.source = source
	previous = running
	if(running)
		owner = running.owner
	else
		owner = src
		work = new /list(BATCH_WORK_KINDS)

/datum/system/atoms
	/// The frame currently initializing atoms, or null (no batch, or its frame is yielding).
	var/tmp/datum/materialize_batch/active_batch
	/// Test hook: when set to list(owner, PROC_REF), every chunk boundary suspends the frame and calls owner.proc(batch).
	var/tmp/list/batch_yield_probe
	/// Every frame that opened, in order, when a test is recording (else null).
	var/list/batch_trace


/// Opens a frame for one InitializeAtoms() call and makes it the active one.
/datum/system/atoms/proc/batch_open(source)
	var/datum/materialize_batch/batch = new(source, active_batch)
	active_batch = batch
	batch_trace?.Add(batch)
	return batch

/// Flushes an owner frame's deferred work, then deactivates the frame.
/datum/system/atoms/proc/batch_close(datum/materialize_batch/batch)
	if(batch.closed)
		return
	batch.closed = TRUE
	if(batch.owner == batch)
		var/list/work = batch.work
		for(var/kind in 1 to BATCH_WORK_KINDS)
			var/list/queued = work[kind]
			if(!length(queued))
				continue
			work[kind] = null
			flush_batch_work(kind, queued)
	// Clear the frame's links so a closed frame holds nothing (and no self-reference).
	active_batch = batch.previous
	batch.previous = null
	if(batch.owner == batch)
		batch.owner = null

/// A chunk boundary of a sync InitializeAtoms(): it never yields (a sync run is boot, a nested frame or a
/// test, where nothing needs the tick back); a chunked run is an atom_init_job below. Only the test probe
/// sees the boundary, as a suspended frame.
/datum/system/atoms/proc/batch_yield_point(datum/materialize_batch/batch)
	if(!batch_yield_probe)
		return
	batch_suspend(batch)
	batch_resume(batch)

/// Suspends a frame at a chunk boundary: while it is suspended no frame is active (rule 5 above).
/datum/system/atoms/proc/batch_suspend(datum/materialize_batch/batch)
	var/list/probe = batch_yield_probe
	batch.yields++
	active_batch = null
	clear_tracked_initalize(batch.source)
	if(probe)
		holder_call(probe[1], probe[2], list(batch))

/// Resumes a suspended frame.
/datum/system/atoms/proc/batch_resume(datum/materialize_batch/batch)
	set_tracked_initalized(INITIALIZATION_INNEW_MAPLOAD, batch.source)
	active_batch = batch

// A chunked InitializeAtoms() over a list of atoms, as a job(): one chunk of MATERIALIZE_CHUNK_SIZE atoms per
// step, the frame suspended between steps, then the frame closes exactly as the sync run closes it.

/datum/atom_init_job
	/// The frame's context (ATOM_RUN_*) once begun.
	var/list/run
	var/list/atoms
	/// InitializeAtoms()' second argument: filled with the movables the run created.
	var/list/atoms_to_return
	var/index = 1
	var/begun = FALSE

/// One step of the run: opens the frame the first time, resumes it otherwise, then initializes a chunk (with
/// `sync`, every chunk) and suspends the frame (JOB_MORE) or closes it (JOB_DONE).
/datum/atom_init_job/proc/run_step(datum/act/timer/A, sync = FALSE)
	var/datum/system/atoms/S = SSatoms
	if(!begun)
		begun = TRUE
		run = S.initialize_atoms_begin(atoms_to_return)
		if(!run)
			return JOB_DONE // atoms are not being initialized yet: let proper initialisation handle them later
	else
		S.batch_resume(run[ATOM_RUN_BATCH])
	return S.initialize_atoms_chunk(src, sync)

/// Initializes the next atoms of an atom_init_job (every remaining chunk with `sync`), then suspends the
/// frame (JOB_MORE) or closes it (JOB_DONE).
/datum/system/atoms/proc/initialize_atoms_chunk(datum/atom_init_job/I, sync)
	var/datum/materialize_batch/batch = I.run[ATOM_RUN_BATCH]
	var/list/atoms = I.atoms
	var/total = length(atoms)
	var/list/mapload_arg = list(TRUE)
	while(I.index <= total)
		// A runtime in the creation logic must not leave the frame open, or initialized would stay broken.
		try
			var/chunk_end = min(total, I.index + MATERIALIZE_CHUNK_SIZE - 1)
			for(var/J in I.index to chunk_end)
				var/atom/A = atoms[J]
				if(!(A.flags & ATOM_INITIALIZED))
					PROFILE_INIT_ATOM_BEGIN()
					InitAtom(A, TRUE, mapload_arg)
					PROFILE_INIT_ATOM_END(A)
			batch.chunks++
			I.index = chunk_end + 1
		catch(var/exception/e)
			dq_report_caught(e, "atom init job")
			I.index = total + 1
		if(I.index <= total && !sync)
			batch_suspend(batch)
			return JOB_MORE
	initialize_atoms_finish(I.run, I.atoms_to_return)
	return JOB_DONE

/// Queues `thing` as `kind` work on the running frame's owner. FALSE when no frame runs.
/datum/system/atoms/proc/batch_defer(kind, datum/thing)
	var/datum/materialize_batch/batch = active_batch
	if(!batch)
		return FALSE
	var/list/work = batch.owner.work
	var/list/queued = work[kind]
	if(!queued)
		queued = list()
		work[kind] = queued
	queued[thing] = TRUE
	return TRUE

/// Drops `thing` from every open frame's `kind` work (a cable unplaced before its bind).
/datum/system/atoms/proc/batch_undefer(kind, datum/thing)
	for(var/datum/materialize_batch/batch = active_batch, batch, batch = batch.previous)
		var/list/queued = batch.owner.work[kind]
		queued?.Remove(thing)
	// A frame suspended at a yield is not on the active chain; its work is filtered at flush.

/// Runs one kind of deferred work. Every flusher skips deleted things.
/datum/system/atoms/proc/flush_batch_work(kind, list/queued)
	switch(kind)
		if(BATCH_WORK_ADJACENCY)
			adjacency_flush_batch(queued)
		if(BATCH_WORK_CABLE_BINDS)
			power_bind_cables(queued)
		else
			stack_trace("flush_batch_work: unknown kind [kind]")
