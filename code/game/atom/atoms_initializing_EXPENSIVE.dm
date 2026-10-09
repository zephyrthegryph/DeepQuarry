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

	// Type-table fast path (atom_type_table.dm): an Initialize-free type skips the proc chain.
	// A mapper-set colour needs /atom/Initialize()'s colour handling, and extra New() args an override.
	var/result
	if(A.init_from_table && length(arguments) == 1 && !A.color)
		A.table_initialize()
		result = INITIALIZE_HINT_NORMAL
	else
		result = A.Initialize(arglist(arguments))
	// param(keep = FALSE) values were for Initialize() alone (code/engine/lifeforms/params.dm)
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

/**
 * Called when an atom is created in byond (built in engine proc)
 *
 * Not a lot happens here in SS13 code, as we offload most of the work to the
 * [Initialization][/atom/proc/Initialize] proc, mostly we run the preloader
 * if the preloader is being used and then call [InitAtom][/datum/system/atoms/proc/InitAtom] of which the ultimate
 * result is that the Initialize proc is called.
 *
 */
/atom/New(loc, ...)
	//atom creation method that preloads variables at creation
	if(GLOB.use_preloader && src.type == GLOB._preloader_path)//in case the instantiated atom is creating other atoms in New()
		world.preloader_load(src)

	// make() records and param(pos =) arguments write the instance's params before anything of the type runs (code/engine/lifeforms/params.dm).
	var/list/init_args = args
	if(length(args) > 1 && lifeform_new_args(src, args))
		init_args = args.Copy()
		init_args.Cut(2, 3) // the make() record is not an Initialize() argument
	var/do_initialize = SSatoms.atom_initialized
	if(do_initialize != INITIALIZATION_INSSATOMS)
		init_args[1] = do_initialize == INITIALIZATION_INNEW_MAPLOAD
		if(SSatoms.InitAtom(src, FALSE, init_args))
			//we were deleted
			return

/**
 * The primary method that objects are setup in SS13 with
 *
 * we don't use New as we have better control over when this is called and we can choose
 * to delay calls or hook other logic in and so forth
 *
 * During roundstart map parsing, atoms are queued for initialization in the base atom/New(),
 * After the map has loaded, then Initialize is called on all atoms one by one. NB: this
 * is also true for loading map templates as well, so they don't Initialize until all objects
 * in the map file are parsed and present in the world
 *
 * If you're creating an object at any point after SSInit has run then this proc will be
 * immediately be called from New.
 *
 * mapload: This parameter is true if the atom being loaded is either being initialized during
 * the Atom subsystem initialization, or if the atom is being loaded from the map template.
 * If the item is being created at runtime any time after the Atom subsystem is initialized then
 * it's false.
 *
 * The mapload argument occupies the same position as loc when Initialize() is called by New().
 * loc will no longer be needed after it passed New(), and thus it is being overwritten
 * with mapload at the end of atom/New() before this proc (atom/Initialize()) is called.
 *
 * You must always call the parent of this proc, otherwise failures will occur as the item
 * will not be seen as initialized (this can lead to all sorts of strange behaviour, like
 * the item being completely unclickable)
 *
 * You must not sleep in this proc, or any subprocs
 *
 * Any parameters from new are passed through (excluding loc), naturally if you're loading from a map
 * there are no other arguments
 *
 * Must return an [initialization hint][INITIALIZE_HINT_NORMAL] or a runtime will occur.
 *
 * Note: the following functions don't call the base for optimization and must copypasta handling:
 * * [/turf/proc/Initialize]
 * * [/turf/open/space/proc/Initialize]
 */
/atom/proc/Initialize(mapload, ...)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_CALL_PARENT(TRUE)

	if(flags & ATOM_INITIALIZED)
		stack_trace("Warning: [src]([type]) initialized multiple times!")
	flags |= ATOM_INITIALIZED
	// set /tg/'s INITIALIZED_1 in parallel with CHOMP's ATOM_INITIALIZED so
	// LINDA's `flags_1 & INITIALIZED_1` checks (SSair.add_to_active, signal-handler
	// gates, /tg/ component lifecycle) work without us having to rewrite each
	// callsite to use the CHOMP flag.
	flags_1 |= INITIALIZED_1

	//atom color stuff
	if(color)
		add_atom_colour(color, FIXED_COLOUR_PRIORITY)

	if(uses_integrity)
		atom_integrity = max_integrity

	// Declared instance state (code/datums/lifecycle/declarations.dm): children, gas, reagents,
	// appearance. Here, at the root of the chain, so a subtype's code after `. = ..()` sees it.
	lifecycle_decls_init(src, mapload)
	// Capabilities' per-instance state, then the first look (code/datums/capabilities/).
	caps_init(src, mapload)

	/*
	if (light_system == COMPLEX_LIGHT && light_power && light_range)
		update_light()
	*/
	return INITIALIZE_HINT_NORMAL
