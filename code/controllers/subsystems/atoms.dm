SYSTEM_DEF(atoms)
	name = "Atoms"
	needs = list(
		/datum/system/garbage,
		// The map-time resolver table and the loot declarations (static entries) are read as the atoms initialize.
		/datum/system/static_entries,
		// The early assets load before the atoms (they set the tracked init state the atoms then read).
		/datum/system/early_assets,
		/datum/system/mapping,
		/datum/system/job,
		// Mapload resleeving machines register with the transcore databases (was a SStranscore dependency).
		/datum/system/transcore,
		// Planets register their floors and walls as turfs initialize (fold wave F4; was SSplanets).
		/datum/system/planets,
		// Mapload R&D servers connect to the science techweb in Initialize() (the boot order no longer happens to put it first).
		/datum/system/research,
	)

	/// A stack of list(source, desired initialized state)
	/// We read the source of init changes from the last entry, and assert that all changes will come with a reset
	var/list/initialized_state = list()
	var/base_initialized

	var/atom_initialized = INITIALIZATION_INSSATOMS

	var/list/BadInitializeCalls = list()

	///InitAtom() adds the movables it creates from a template here while the running
	///InitializeAtoms() call was given a list to populate. Saved and restored per call.
	var/list/created_atoms

	/// While a map-load batch initializes, anchored power machines queue their node here
	/// (machine -> TRUE) instead of one vg_power_bind_machine() each; the outermost
	/// InitializeAtoms() binds them in one vg_power_bind_machine_list() call after its frame's
	/// cable binds (doc/rewrite/init_and_turfs.md sec 4.6). Null outside a batch.
	var/list/deferred_machine_binds

	/// Map resolvers that need the whole load in place (map_resolve_later()): list(proc, loc, path,
	/// varedits) rows, run after the outermost InitializeAtoms() of the load created its atoms.
	var/list/deferred_resolvers
	/// InitializeAtoms() nesting depth; deferred resolvers flush when it returns to 0.
	var/initialize_depth = 0
	/// TRUE while the boot map loads (initialize()): its settling drain is the first kernel tick's.
	var/booting = FALSE

	EXPIRY_DECLARE(init_start_time)

	#ifdef PROFILE_MAPLOAD_INIT_ATOM
	var/list/mapload_init_times = list()
	#endif

	atom_initialized = INITIALIZATION_INSSATOMS

/datum/system/atoms/initialize()
	EXPIRY_STAMP(src, init_start_time, CLOCK_WORLD)

	atom_initialized = INITIALIZATION_INNEW_MAPLOAD
	booting = TRUE
	InitializeAtoms()
	booting = FALSE
	atom_initialized = INITIALIZATION_INNEW_REGULAR

	// Services that set up on the initialized map declare needs = list(/datum/system/atoms) (pai, xenoarch,
	// events, night shift, antagonists, radio, crew transfer); the boot DAG boots them next.
	validate_property_registry()
	// Map load and the initial materialize batch are done: validate the ownership table of every
	// mapped and registered type now, not on first use (doc/rewrite/ownership.md sec 8).
	own_validate_boot()

/datum/system/atoms/proc/InitializeAtoms(list/atoms, list/atoms_to_return)
	var/list/run = initialize_atoms_begin(atoms_to_return)
	if(!run)
		return
	// This may look a bit odd, but if the actual atom creation runtimes for some reason, we absolutely need to set initialized BACK
	CreateAtoms(run[ATOM_RUN_BATCH], atoms)
	initialize_atoms_finish(run, atoms_to_return)

/// Opens the frame for one InitializeAtoms() run and returns its context list (ATOM_RUN_*), or null when
/// atoms are not being initialized yet. The sync InitializeAtoms() and the chunked atom_init_job (below) share
/// this, so a chunked run does exactly what the sync one does.
/datum/system/atoms/proc/initialize_atoms_begin(list/atoms_to_return)
	if(atom_initialized == INITIALIZATION_INSSATOMS)
		return null

	// Generate a unique mapload source for this run of InitializeAtoms
	var/static/uid = 0
	uid = (uid + 1) % (SHORT_REAL_LIMIT - 1)
	var/source = "subsystem init [uid]"
	set_tracked_initalized(INITIALIZATION_INNEW_MAPLOAD, source)

	// One frame per call (atoms_batch.dm): it owns the deferred work unless it joined a
	// running frame, and yields only between chunks.
	var/datum/materialize_batch/batch = batch_open(source)
	initialize_depth++
	var/list/outer_created = created_atoms
	created_atoms = atoms_to_return ? list() : null
	batch.created_atoms = created_atoms
	var/machine_owner = isnull(deferred_machine_binds)
	if(machine_owner)
		deferred_machine_binds = list()
	var/decl_bind_owner = isnull(deferred_decl_binds)
	if(decl_bind_owner)
		deferred_decl_binds = list()
	// Heat bodies created by the batch take pre-reserved handles and configure in one call (heat_bind_batch.dm).
	dq_heat_bind_begin()
	var/list/run = new /list(ATOM_RUN_FIELDS)
	run[ATOM_RUN_SOURCE] = source
	run[ATOM_RUN_BATCH] = batch
	run[ATOM_RUN_OUTER_CREATED] = outer_created
	run[ATOM_RUN_MACHINE_OWNER] = machine_owner
	run[ATOM_RUN_DECL_OWNER] = decl_bind_owner
	return run

/// Closes the frame `initialize_atoms_begin()` opened: deferred resolvers, the frame's deferred work, binds,
/// late loaders and the queued deletions.
/datum/system/atoms/proc/initialize_atoms_finish(list/run, list/atoms_to_return)
	var/source = run[ATOM_RUN_SOURCE]
	var/datum/materialize_batch/batch = run[ATOM_RUN_BATCH]
	var/list/outer_created = run[ATOM_RUN_OUTER_CREATED]
	var/machine_owner = run[ATOM_RUN_MACHINE_OWNER]
	var/decl_bind_owner = run[ATOM_RUN_DECL_OWNER]
	// Deferred map resolvers run once the outermost load's atoms exist, still inside its frame
	// (what they create initializes as mapload and joins the batch).
	if(initialize_depth == 1 && (deferred_resolvers || length(GLOB.map_resolve_scratch)))
		map_resolve_flush_deferred()
	clear_tracked_initalize(source)
	var/list/created = batch.created_atoms
	created_atoms = outer_created
	batch_close(batch)
	// The frame flushed walls and cables; machines bind after the cables so they join the knots.
	if(machine_owner)
		flush_machine_binds()
	// Decl binds run inside the heat bind scope, so bodies they create batch too.
	if(decl_bind_owner)
		flush_decl_binds()
	dq_heat_bind_end()

	after_init_flush(batch) // the frame's map-loaded instances run their after_init() entries, after its last atom

	if(created)
		atoms_to_return += created

	initialize_depth--
	// The load is complete: one settling drain runs the hooks and marked stats its atoms' init owes (doc section 7, "Initial evaluation is
	// silent"). At boot the first kernel tick's drain is that drain: the systems that boot after the atoms must exist before a hook runs.
	if(!initialize_depth && !booting)
		stat_drain_point()

	testing("[length(queued_deletions)] atoms were queued for deletion.")
	for (var/atom/queued as anything in queued_deletions?.Copy())
		spent(queued)
	rel_clear(src, nameof(queued_deletions))

	#ifdef PROFILE_MAPLOAD_INIT_ATOM
	rustg_file_write(json_encode(mapload_init_times), "[GLOB.log_directory]/init_times.json")
	#endif

/// Binds every power machine node the batch queued in one Rust call (after the cables, so the
/// machines join the batch's knots).
/datum/system/atoms/proc/flush_machine_binds()
	var/list/queued = deferred_machine_binds
	deferred_machine_binds = null
	if(length(queued))
		power_bind_machines(queued)

/// Initializes the frame's atoms (or every uninitialized atom in the world) chunk by chunk.
/// Exists solely so a runtime in the creation logic doesn't cause initialized to totally break.
/datum/system/atoms/proc/CreateAtoms(datum/materialize_batch/batch, list/atoms)
	var/list/mapload_arg = list(TRUE)
	#ifdef TESTING
	var/count = 0
	#endif

	if(atoms)
		var/total = length(atoms)
		var/index = 1
		while(index <= total)
			var/chunk_end = min(total, index + MATERIALIZE_CHUNK_SIZE - 1)
			for(var/I in index to chunk_end)
				var/atom/A = atoms[I]
				if(!(A.flags & ATOM_INITIALIZED))
					PROFILE_INIT_ATOM_BEGIN()
					InitAtom(A, TRUE, mapload_arg)
					PROFILE_INIT_ATOM_END(A)
					#ifdef TESTING
					count++
					#endif
			batch.chunks++
			index = chunk_end + 1
			if(index <= total)
				batch_yield_point(batch)
	else
		var/in_chunk = 0
		for(var/atom/A as anything in world)
			if(!(A.flags & ATOM_INITIALIZED))
				PROFILE_INIT_ATOM_BEGIN()
				InitAtom(A, FALSE, mapload_arg)
				PROFILE_INIT_ATOM_END(A)
				#ifdef TESTING
				count++
				#endif
				if(++in_chunk >= MATERIALIZE_CHUNK_SIZE)
					in_chunk = 0
					batch.chunks++
					batch_yield_point(batch)
		if(in_chunk)
			batch.chunks++

	#ifdef TESTING
	testing("Initialized [count] atoms in [batch.chunks] chunks, [batch.yields] yields")
	#endif

/datum/system/atoms/proc/map_loader_begin(source)
	set_tracked_initalized(INITIALIZATION_INSSATOMS, source)

/datum/system/atoms/proc/map_loader_stop(source)
	clear_tracked_initalize(source)

/// Returns the source currently modifying SSatom's init behavior
/datum/system/atoms/proc/get_initialized_source()
	var/state_length = length(initialized_state)
	if(!state_length)
		return null
	return initialized_state[state_length][1]

/// Use this to set initialized to prevent error states where the old initialized is overridden, and we end up losing all context
/// Accepts a state and a source, the most recent state is used, sources exist to prevent overriding old values accidentally
/datum/system/atoms/proc/set_tracked_initalized(state, source)
	if(!length(initialized_state))
		base_initialized = atom_initialized
	initialized_state += list(list(source, state))
	atom_initialized = state

/datum/system/atoms/proc/clear_tracked_initalize(source)
	if(!length(initialized_state))
		return
	for(var/i in length(initialized_state) to 1 step -1)
		if(initialized_state[i][1] == source)
			initialized_state.Cut(i, i+1)
			break

	if(!length(initialized_state))
		atom_initialized = base_initialized
		base_initialized = INITIALIZATION_INNEW_REGULAR
		return
	atom_initialized = initialized_state[length(initialized_state)][2]

/// Returns TRUE if anything is currently being initialized
/datum/system/atoms/proc/initializing_something()
	return length(initialized_state) > 1


/datum/system/atoms/proc/InitLog()
	. = ""
	for(var/path in BadInitializeCalls)
		. += "Path : [path] \n"
		var/fails = BadInitializeCalls[path]
		if(fails & BAD_INIT_DIDNT_INIT)
			. += "- Didn't call atom/Initialize(mapload)\n"
		if(fails & BAD_INIT_NO_HINT)
			. += "- Didn't return an Initialize hint\n"
		if(fails & BAD_INIT_QDEL_BEFORE)
			. += "- Qdel'd before Initialize proc ran\n"
		if(fails & BAD_INIT_SLEPT)
			. += "- Slept during Initialize()\n"

/// Prepares an atom to be deleted once the atoms SS is initialized.
/datum/system/atoms/proc/prepare_deletion(atom/target)
	if (atom_initialized == INITIALIZATION_INNEW_REGULAR)
		// Atoms SS has already completed, just kill it now.
		spent(target)
	else
		rel_add(src, nameof(queued_deletions), target)

/datum/system/atoms/on_shutdown()
	var/initlog = InitLog()
	if(initlog)
		text2file(initlog, "[GLOB.log_directory]-initialize.log")

/datum/system/atoms/relations()
	. = ..()
	. += rel_many(nameof(queued_deletions))

/// Atoms to delete once init finishes: a relation list view (a member deleted early leaves it).
/datum/system/atoms/var/list/atom/queued_deletions

// ---- after_init() (code/engine/actions/after_init.dm): armed when an instance's init is complete ----

/datum/system/atoms
	/// Instances whose init has run their engine init but not yet finished Initialize(): instance -> TRUE. InitAtom() takes each out when its
	/// Initialize() returns and arms its after_init() entries (now, or at the close of the map-load frame).
	var/list/after_init_pending
	/// Map-loaded instances with after_init() entries, made outside any frame: the next frame to close arms them.
	var/list/after_init_loose

/// after_init_note(): `A` has after_init() entries and its Initialize() is running.
/datum/system/atoms/proc/after_init_wait(atom/A)
	if(!after_init_pending)
		after_init_pending = list()
	after_init_pending[A] = TRUE

/// InitAtom(): `A`'s Initialize() returned. A map-loaded instance waits for its frame to close; any other is armed now.
/datum/system/atoms/proc/after_init_initialized(atom/A, mapload)
	after_init_pending -= A
	if(!length(after_init_pending))
		after_init_pending = null
	if(QDELETED(A))
		return
	if(mapload)
		var/datum/materialize_batch/batch = active_batch
		if(batch)
			LAZYADD(batch.after_inits, A)
		else
			LAZYADD(after_init_loose, A)
		return
	after_init_arm(A, FALSE)

/// A frame closed (initialize_atoms_finish(), after its deferred work and binds): every map-loaded instance it holds is armed.
/datum/system/atoms/proc/after_init_flush(datum/materialize_batch/batch)
	var/list/armed = batch.after_inits
	batch.after_inits = null
	if(length(after_init_loose))
		armed = (armed || list()) + after_init_loose
		after_init_loose = null
	for(var/atom/A as anything in armed)
		if(QDELETED(A))
			continue
		#ifdef BENCHMARK_DEEP_PROFILE
		var/bench_depth = benchmark_init_frame_begin()
		#endif
		after_init_arm(A, TRUE)
		#ifdef BENCHMARK_DEEP_PROFILE
		benchmark_late_frame_end(bench_depth, A.type)
		#endif

/// TRUE while a map load is in progress: a load frame is open (InitializeAtoms(), or a chunked load suspended between its steps). The engine's
/// drains wait for the load to complete (stat_drain_point()).
/datum/system/atoms/proc/map_loading()
	return initialize_depth > 0
