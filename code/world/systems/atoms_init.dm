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
	// The type's construction plan (code/engine/declare/ctor_plan.dm): one lookup for the per-type facts every step below asks. Null while it cannot be
	// built yet, and then each step asks its own table as before.
	var/plan = ctor_plan_of(A)
	A.datum_flags |= DF_CONSTRUCTING // under construction until its birth below, after its setup() rows (silent construction, E3)
	if((plan ? (plan & CTOR_RESOLVER) : GLOB.map_resolvers[the_type]) && map_resolve_instance(A))
		return TRUE

	// An atom initializes with the air under it already made: whatever it reads of it in Initialize() or in a condition (a sensor, a generator's
	// cooling) is the turf's own mixture, not vacuum, whichever of the two the map load initializes first. Outside any condition, so it may write.
	if(isturf(A.loc))
		var/turf/home = A.loc
		home.settle_air()

	// This is handled and battle tested by dreamchecker. Limit to UNIT_TESTS just in case that ever fails.
	#ifdef UNIT_TESTS
	var/start_tick = world.time
	#endif

	#ifdef BENCHMARK_DEEP_PROFILE
	var/bench_depth = benchmark_init_frame_begin()
	#endif

	BOOT_PHASE_BEGIN(bp_early)
	// Phase 0 of the init contract: the starting occupants a type's code before `..()` reads (owns_*(early = TRUE)), before the chain runs.
	if(plan)
		if(plan & CTOR_EARLY_STARTS)
			own_init_starts(A, null, length(arguments) ? arguments[1] : FALSE, TRUE)
			if(QDELETED(A))
				return TRUE
		if(plan & CTOR_PARAM_EARLY)
			params_early(A, length(arguments) ? arguments[1] : FALSE)
			if(QDELETED(A))
				return TRUE
		if(plan & CTOR_SETUP_EARLY)
			// setup_early()'s rows, read here: the head of the type's Initialize() (code/engine/lifeforms/setup.dm).
			var/datum/lifeform_plan/early_plan = lifeform_plans[A.type]
			for(var/handler in early_plan.setup_rows_early)
				try
					call(A, handler)()
				catch(var/exception/early_error)
					dq_report_caught(early_error, "setup([handler], early = TRUE) on [A.type]")
				if(QDELETED(A))
					break
			if(QDELETED(A))
				return TRUE
	else
		ctor_early_unplanned(A, arguments)
		if(QDELETED(A))
			return TRUE

	BOOT_PHASE_END(bp_early, "InitAtom: early starts, params, setup_early" + BOOT_KIND(A), A)
	// Type-table fast path (atom_type_table.dm): an Initialize-free type skips the proc chain.
	// A mapper-set colour needs /atom/Initialize()'s colour handling, and extra New() args an override.
	BOOT_PHASE_BEGIN(bp_init)
	var/result
	// Its own writes inside Initialize() publish nothing: nothing has seen it yet, and caps_init() queues its first full refresh (state_changed()).
	var/atom/outer_initializing = GLOB.atom_initializing
	var/outer_plan = ctor_plan_current
	GLOB.atom_initializing = A
	ctor_plan_current = plan | 0 // a number: the plan bits
	if(outer_initializing)
		GLOB.atoms_init_outer += outer_initializing // still partway through its own Initialize() while this one's runs
	if((plan ? (plan & CTOR_FROM_TABLE) : GLOB.init_from_table_types[A.type]) && length(arguments) == 1 && !A.color)
		A.table_initialize()
		result = INITIALIZE_HINT_NORMAL
	else
		result = A.Initialize(arglist(arguments))
	GLOB.atom_initializing = outer_initializing
	ctor_plan_current = outer_plan
	if(outer_initializing)
		GLOB.atoms_init_outer.len--
	BOOT_PHASE_END(bp_init, "InitAtom: Initialize (includes decls, caps_init, nested inits)" + BOOT_KIND(A), A)
	// Opt-in constructor completion needs the settled parent state and transient params.
	// Never run it for an Initialize/keeps_if rejection; the ordinary setup phase stays below.
	if(length(setup_pending) && setup_pending[A] == SETUP_PENDING_WITH_PARAMS && result == INITIALIZE_HINT_NORMAL && !(length(init_discard_pending) && init_discard_pending[A]))
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
	if(length(init_discard_pending) && init_discard_pending[A] && keeps_if_discarded(A) && result == INITIALIZE_HINT_NORMAL)
		result = INITIALIZE_HINT_QDEL
	// setup() and name_prefix() (code/engine/lifeforms/setup.dm): the type's own setup, once its Initialize() chain has returned.
	BOOT_PHASE_BEGIN(bp_setup)
	if((plan & CTOR_SETUP_ONLY) && result == INITIALIZE_HINT_NORMAL && !QDELETED(A))
		// The plan says the type's only engine init is its setup rows (ctor_plan.dm): no setup_pending note was made, they run here, as setup_run_hooks()
		// runs them. No init frame is opened: the atom is under construction (DF_CONSTRUCTING), which holds its draws the same way until its birth.
		if(ctor_setup_rows(A, length(arguments) ? arguments[1] : FALSE) == INITIALIZE_HINT_QDEL)
			result = INITIALIZE_HINT_QDEL
	else if(length(setup_pending) && setup_pending[A])
		if(result == INITIALIZE_HINT_NORMAL)
			// A setup(PROC_REF(x), mapload = TRUE) hook may return INITIALIZE_HINT_QDEL: handled below as an Initialize() return.
			if(setup_run(A, FALSE, length(arguments) ? arguments[1] : FALSE) == INITIALIZE_HINT_QDEL)
				result = INITIALIZE_HINT_QDEL
		else
			setup_pending -= A
	BOOT_PHASE_END(bp_setup, "InitAtom: setup_run" + BOOT_KIND(A), A)
	construction_birth(A) // silent construction ends: what it wrote is published once, its on_change baselines taken (code/engine/change/refresh.dm)

	// param(keep = FALSE) values are for Initialize() and the type's setup() (a statue's setup reads the mob it copies); they go once both ran
	// (code/engine/lifeforms/params.dm).
	if(length(param_drop_pending) && param_drop_pending[A])
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
	BOOT_PHASE_BEGIN(bp_after)
	if(after_init_pending?[A])
		after_init_initialized(A, arguments[1])
	BOOT_PHASE_END(bp_after, "InitAtom: after_init_initialized" + BOOT_KIND(A), A)

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
			// rules or the scheduler is live once flagged. Most of the ~390 k map turfs take this path.
			if(isturf(A) && !A.rx?.containment_ledger && !((plan & CTOR_MATERIALIZE_KNOWN) ? (plan & CTOR_MATERIALIZE_WORK) : ctor_materialize_work(A, plan)))
				A.flags |= ATOM_MATERIALIZED
			else
				BOOT_PHASE_BEGIN(bp_mat)
				A.materialize()
				BOOT_PHASE_END(bp_mat, "InitAtom: materialize" + BOOT_KIND(A), A)
		var/atom/location = A.loc
		if(location)
			/// Emits that the new atom `src`, has been created at `loc`
			// Nothing of the location's type hears it and the location has no listener of its own (notice_wanted()'s fast path, read here): not published.
			var/datum/rx_state/location_rx = location.rx
			var/list/location_unheard = GLOB.notice_unheard[location.type]
			if(!(location_unheard?[/datum/notice/atom_after_successful_initialized_on] && (!location_rx || (!location_rx.notice_types && (!location_rx.hooks || !notice_hooks_live_hear(location_rx, /datum/notice/atom_after_successful_initialized_on))))))
				PUBLISH(location, atom_after_successful_initialized_on, created = A, mapload = arguments[1])
			RANGE_WATCH(location, RANGE_INITIALIZED, A, arguments[1])
			// Created straight into a holder with a ledger: nothing is noted here. The ledger is made on first use and its sync() adopts whatever
			// arrived without a move (code/engine/refs/containment/ledger.dm), so a holder whose ledger is never asked for costs nothing at init.
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

/// InitAtom()'s phase 0 for a type with no construction plan yet (the globals are still being made): each fact from its own table, as before plans.
/proc/ctor_early_unplanned(atom/A, list/arguments)
	var/datum/own_table/early_table = _CACHED_KEY_FAST(own_table, A.type, A)
	if(early_table.early_vars)
		own_init_starts(A, early_table, length(arguments) ? arguments[1] : FALSE, TRUE)
		if(QDELETED(A))
			return
	var/datum/type_table/lifeform_table = type_table_store?[A.type]
	if(!lifeform_table)
		lifeform_table = table_of(A)
	if(lifeform_table.hook_flags & ENGINE_HOOK_LIFEFORMS)
		params_early(A, length(arguments) ? arguments[1] : FALSE)
		if(QDELETED(A))
			return
		setup_early(A)

/// Whether A's type has materialize work, from its construction plan: worked out once per type (atom_type_table()) and kept in the plan's bits,
/// so the ~390 k map turfs read one bit. `plan`: A's plan bits as InitAtom() fetched them (0 without a plan: the table is asked).
/proc/ctor_materialize_work(atom/A, plan)
	if(!plan)
		return atom_type_table(A) & TYPE_TABLE_MATERIALIZE_WORK
	if(plan & CTOR_MATERIALIZE_KNOWN)
		return plan & CTOR_MATERIALIZE_WORK
	var/bits = plan | CTOR_MATERIALIZE_KNOWN
	if(atom_type_table(A) & TYPE_TABLE_MATERIALIZE_WORK)
		bits |= CTOR_MATERIALIZE_WORK
	ctor_plans[A.type] = bits
	return bits & CTOR_MATERIALIZE_WORK

/// The setup() rows of a CTOR_SETUP_ONLY type, as setup_run_hooks() runs them (in order; a mapload = TRUE row's INITIALIZE_HINT_QDEL stops them and is
/// returned; a name_prefix row prefixes the name), without the setup_pending note and the init frame (the atom is under construction).
/proc/ctor_setup_rows(atom/A, mapload)
	var/datum/lifeform_plan/P = lifeform_plans[A.type]
	for(var/list/row as anything in P.setup_rows_plain)
		var/handler = row[1]
		if(handler)
			if(row[3])
				var/hint = call(A, handler)(mapload)
				if(hint == INITIALIZE_HINT_QDEL)
					log_world("setup([handler]) on [A.type] returned INITIALIZE_HINT_QDEL (mapload=[mapload ? 1 : 0]): the instance is discarded")
					return INITIALIZE_HINT_QDEL
				if(!isnull(hint) && hint != INITIALIZE_HINT_NORMAL)
					stack_trace("setup([handler]) on [A.type] returned init hint [hint]; only INITIALIZE_HINT_NORMAL and INITIALIZE_HINT_QDEL are supported there")
			else
				call(A, handler)()
		else if(!isnull(row[2]))
			var/prefix = row[2]
			if(istext(prefix) && hascall(A, prefix))
				prefix = call(A, prefix)()
			A.name = "[prefix] [A.name]"
		if(QDELETED(A))
			return INITIALIZE_HINT_NORMAL
	return INITIALIZE_HINT_NORMAL
