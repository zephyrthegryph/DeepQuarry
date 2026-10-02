// Chunked materialize (Phase 4 track 4d, doc/rewrite/init_and_turfs.md sec 3.3a).
//
// Every SSatoms.InitializeAtoms() call is one /datum/materialize_batch frame. The frame
// initializes (and so materializes) its atoms in chunks of MATERIALIZE_CHUNK_SIZE and may
// yield to the MC only between two chunks. Ordering rules the frames keep:
//
// 1. Atoms initialize in the order the caller listed them (areas, turfs, then movables for
//    a template); a yield never reorders or skips one.
// 2. A frame's LateInitialize() calls run after every atom of that frame has initialized.
// 3. Deferred work (BATCH_WORK_*: wall smoothing, cable binds) belongs to the frame that
//    owns it and flushes once when that frame closes, before its LateInitialize() calls,
//    in BATCH_WORK_* order.
// 4. A frame opened while another frame is running (a nested InitializeAtoms() from inside
//    an Initialize()) joins it: its deferred work goes to the running frame's owner, as the
//    shared lists did before. Its own late loaders still run when it closes.
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
	/// Atoms whose Initialize() returned INITIALIZE_HINT_LATELOAD during a mapload.
	var/list/late_loaders
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
	late_loaders = list()

/datum/system/atoms
	/// The frame currently initializing atoms, or null (no batch, or its frame is yielding).
	var/tmp/datum/materialize_batch/active_batch
	/// Test hook: when set, every chunk boundary yields and calls this instead of stoplag().
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

/// A chunk boundary: yields to the MC if the tick is spent (never under unit tests, which
/// have no clients to keep smooth) and keeps the frame isolated while it sleeps.
/datum/system/atoms/proc/batch_yield_point(datum/materialize_batch/batch)
	var/list/probe = batch_yield_probe
	if(!probe)
		#ifdef UNIT_TESTS
		return
		#else
		if(!length(GLOB.clients) || !TICK_CHECK)
			return
		#endif
	batch.yields++
	active_batch = null
	clear_tracked_initalize(batch.source)
	if(probe)
		om_run(probe, batch)
	else
		stoplag() // ALLOW(scheduler): map-load batches yield between chunks so a big load does not stall the tick
	set_tracked_initalized(INITIALIZATION_INNEW_MAPLOAD, batch.source)
	active_batch = batch

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
		if(BATCH_WORK_WALL_SMOOTHING)
			flush_wall_smoothing(queued)
		if(BATCH_WORK_CABLE_BINDS)
			power_bind_cables(queued)
		else
			stack_trace("flush_batch_work: unknown kind [kind]")

/// Smooths every wall the batch queued, plus the walls next to them (a template's edge
/// touches walls that were already there), once each, now that every material is set.
/// A neighbour another frame has not initialized yet queues itself when it does.
/datum/system/atoms/proc/flush_wall_smoothing(list/queued)
	var/list/walls = queued.Copy()
	for(var/turf/simulated/wall/W as anything in queued)
		for(var/turf/simulated/wall/neighbour in orange(W, 1))
			walls[neighbour] = TRUE
	for(var/turf/simulated/wall/W as anything in walls)
		if(QDELETED(W) || !istype(W) || !(W.flags & ATOM_INITIALIZED))
			continue
		W.update_connections()
		W.update_icon()
