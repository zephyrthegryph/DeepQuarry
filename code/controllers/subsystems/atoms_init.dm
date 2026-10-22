/// Init this specific atom
/datum/system/atoms/proc/InitAtom(atom/A, from_template = FALSE, list/arguments)

	var/the_type = A.type

	if(QDELING(A))
		// Check init_start_time to not worry about atoms created before the atoms SS that are cleaned up before this
		if (A.gc_destroyed > init_start_time)
			BadInitializeCalls[the_type] |= BAD_INIT_QDEL_BEFORE
		return TRUE

	// Map-time resolver (map_resolvers.dm): the atom's work happens here and it is detached,
	// never initialized nor qdel'd.
	if(GLOB.map_resolvers[the_type] && map_resolve_instance(A))
		return TRUE

	// This is handled and battle tested by dreamchecker. Limit to UNIT_TESTS just in case that ever fails.
	#ifdef UNIT_TESTS
	var/start_tick = world.time
	#endif

	#ifdef BENCHMARK_DEEP_PROFILE
	var/bench_depth = benchmark_init_frame_begin()
	#endif

	// Phase 0 of the init contract: the starting occupants a type's code before `..()` reads (owns_*(early = TRUE)), before the chain runs.
	var/datum/own_table/early_table = own_table_of(A)
	if(early_table.early_vars)
		own_init_starts(A, early_table, length(arguments) ? arguments[1] : FALSE, TRUE)
		if(QDELETED(A))
			return TRUE

	// Type-table fast path (atom_type_table.dm): an Initialize-free type skips the proc chain.
	// A mapper-set colour needs /atom/Initialize()'s colour handling, and extra New() args an override.
	var/result
	if(A.init_from_table && length(arguments) == 1 && !A.color)
		A.table_initialize()
		result = INITIALIZE_HINT_NORMAL
	else
		result = A.Initialize(arglist(arguments))
	// Opt-in constructor completion needs the settled parent state and transient params.
	// Never run it for an Initialize/keeps_if rejection; the ordinary setup phase stays below.
	if(setup_pending?[A] == SETUP_PENDING_WITH_PARAMS && result == INITIALIZE_HINT_NORMAL && !init_discard_pending?[A])
		try
			setup_run(A, with_params = TRUE)
			if(param_drop_pending?[A])
				params_drop(A)
		catch(var/exception/e)
			if(param_drop_pending?[A])
				params_drop(A)
			setup_pending -= A
			throw e
	// keeps_if() (code/engine/lifeforms/keeps_if.dm): a failed condition is the atom's INITIALIZE_HINT_QDEL.
	if(init_discard_pending?[A] && keeps_if_discarded(A) && result == INITIALIZE_HINT_NORMAL)
		result = INITIALIZE_HINT_QDEL
	// setup() and name_prefix() (code/engine/lifeforms/setup.dm): the type's own setup, once its Initialize() chain has returned.
	if(setup_pending?[A])
		if(result == INITIALIZE_HINT_NORMAL)
			// A setup(PROC_REF(x), mapload = TRUE) hook may return INITIALIZE_HINT_QDEL: handled below as an Initialize() return.
			if(setup_run(A, FALSE, length(arguments) ? arguments[1] : FALSE) == INITIALIZE_HINT_QDEL)
				result = INITIALIZE_HINT_QDEL
		else
			setup_pending -= A

	// param(keep = FALSE) values are for Initialize() and the type's setup() (a statue's setup reads the mob it copies); they go once both ran
	// (code/engine/lifeforms/params.dm).
	if(param_drop_pending?[A])
		params_drop(A)

	#ifdef BENCHMARK_DEEP_PROFILE
	var/list/bench_init_mark = benchmark_init_frame_mark(bench_depth)
	#endif

	#ifdef UNIT_TESTS
	if(start_tick != world.time)
		BadInitializeCalls[the_type] |= BAD_INIT_SLEPT
	#endif

	var/qdeleted = FALSE

	switch(result)
		if (INITIALIZE_HINT_NORMAL)
			EMPTY_BLOCK_GUARD // Pass
		if(INITIALIZE_HINT_QDEL)
			spent(A)
			qdeleted = TRUE
		else
			BadInitializeCalls[the_type] |= BAD_INIT_NO_HINT

	// after_init() entries (code/engine/actions/after_init.dm): Initialize() has returned, so they run now (made at runtime) or when the
	// map-load frame closes (atoms_batch.dm rule 2). A deleted atom is only dropped from the waiting list.
	if(after_init_pending?[A])
		after_init_initialized(A, arguments[1])

	if(!A) //possible harddel
		qdeleted = TRUE
	else if(!(A.flags & ATOM_INITIALIZED))
		BadInitializeCalls[the_type] |= BAD_INIT_DIDNT_INIT
	else
		// L2 lifecycle: enter the live world. A mapload after_init() is
		// deferred to the end of the batch; materializing does not wait for it,
		// so the registrations moved out of Initialize() keep their old timing.
		if(!materialize_suppressed && !qdeleted && !QDELING(A))
			// Type-table fast path (atom_type_table.dm): turfs have no on_materialize() of their
			// own (tools/ci/init_lint.py keeps it so), so a turf whose type needs no registries,
			// rules or OM is live once flagged. Most of the ~390 k map turfs take this path.
			if(isturf(A) && !A.containment_ledger() && !(atom_type_table(A) & TYPE_TABLE_MATERIALIZE_WORK))
				A.flags |= ATOM_MATERIALIZED
			else
				A.materialize()
		var/atom/location = A.loc
		if(location)
			/// Emits that the new atom `src`, has been created at `loc`
			PUBLISH_LEGACY(location, /datum/notice/atom_after_successful_initialized_on, A, arguments[1])
			RANGE_WATCH(location, RANGE_INITIALIZED, A, arguments[1])
			// Created straight into a holder with a ledger: record it now (containment C1).
			location.containment_ledger()?.note_enter(A)
		if(created_atoms && from_template && ispath(the_type, /atom/movable))//we only want to populate the list with movables
			created_atoms += A.get_all_contents()

	#ifdef BENCHMARK_DEEP_PROFILE
	benchmark_init_frame_end(bench_depth, the_type, bench_init_mark)
	#endif

	return qdeleted || QDELING(A)

/// Binds everything a batch queued, one bind_list() per binder.
/datum/system/atoms/proc/flush_decl_binds()
	var/list/queued = deferred_decl_binds
	deferred_decl_binds = null
	for(var/path in queued)
		var/list/atoms = queued[path]
		if(length(atoms))
			decl_binder(path).bind_list(atoms)
