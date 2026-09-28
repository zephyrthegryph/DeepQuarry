SUBSYSTEM_DEF(atoms)
	name = "Atoms"
	dependencies = list(
		/datum/controller/subsystem/garbage,
		/datum/controller/subsystem/mapping,
		/datum/controller/subsystem/job
	)
	flags = SS_NO_FIRE

	/// A stack of list(source, desired initialized state)
	/// We read the source of init changes from the last entry, and assert that all changes will come with a reset
	var/list/initialized_state = list()
	var/base_initialized

	var/atom_initialized = INITIALIZATION_INSSATOMS
	var/list/late_loaders = list()

	var/list/BadInitializeCalls = list()

	///initAtom() adds the atom its creating to this list iff InitializeAtoms() has been given a list to populate as an argument
	var/list/created_atoms

	/// While a map-load batch initializes (InitializeAtoms()), walls queue here instead of
	/// smoothing themselves and their neighbours one by one; the batch smooths each once at the
	/// end (doc/rewrite/init_and_turfs.md sec 4.2). Null outside a batch.
	var/list/deferred_wall_smoothing

	/// While a map-load batch initializes, cables queue their power node here (cable -> TRUE)
	/// and the batch binds them in one Rust call (doc/rewrite/init_and_turfs.md sec 3.3 step 4).
	/// Null outside a batch. Machines poll their region every power step, so nothing needs the
	/// nodes before the batch ends.
	var/list/deferred_cable_binds

	/// While a map-load batch initializes, anchored power machines queue their node here
	/// (machine -> TRUE) instead of one vg_power_bind_machine() each; the batch binds them in one
	/// vg_power_bind_machine_list() call (doc/rewrite/init_and_turfs.md sec 4.6). Null outside a
	/// batch. The handle is the machine's own vg_entity, already live, so nothing waits on it.
	var/list/deferred_machine_binds

	/// Atoms that will be deleted once the subsystem is initialized
	var/list/queued_deletions = list()

	var/init_start_time

	#ifdef PROFILE_MAPLOAD_INIT_ATOM
	var/list/mapload_init_times = list()
	#endif

	atom_initialized = INITIALIZATION_INSSATOMS

/datum/controller/subsystem/atoms/Initialize()
	init_start_time = world.time
	// Mapload resleeving machines register with the transcore databases (was a SStranscore dependency).
	boot_world_service(GLOB.transcore_service)
	// Planets register their floors and walls as turfs initialize (fold wave F4; was SSplanets).
	boot_world_service(GLOB.planet_service)

	atom_initialized = INITIALIZATION_INNEW_MAPLOAD
	InitializeAtoms()
	atom_initialized = INITIALIZATION_INNEW_REGULAR

	// Services that set up on the initialized map declare boot_after = SSatoms (pai, xenoarch,
	// events, night shift, antagonists, radio, crew transfer); the MC boots them next.
	validate_property_registry()

	return SS_INIT_SUCCESS

/datum/controller/subsystem/atoms/proc/InitializeAtoms(list/atoms, list/atoms_to_return)
	if(atom_initialized == INITIALIZATION_INSSATOMS)
		return

	// Generate a unique mapload source for this run of InitializeAtoms
	var/static/uid = 0
	uid = (uid + 1) % (SHORT_REAL_LIMIT - 1)
	var/source = "subsystem init [uid]"
	set_tracked_initalized(INITIALIZATION_INNEW_MAPLOAD, source)

	var/smoothing_owner = isnull(deferred_wall_smoothing)
	if(smoothing_owner)
		deferred_wall_smoothing = list()
	var/cable_owner = isnull(deferred_cable_binds)
	if(cable_owner)
		deferred_cable_binds = list()
	var/machine_owner = isnull(deferred_machine_binds)
	if(machine_owner)
		deferred_machine_binds = list()
	var/decl_bind_owner = isnull(deferred_decl_binds)
	if(decl_bind_owner)
		deferred_decl_binds = list()
	// Heat bodies created by the batch take pre-reserved handles and configure in one call (heat_bind_batch.dm).
	dq_heat_bind_begin()
	// This may look a bit odd, but if the actual atom creation runtimes for some reason, we absolutely need to set initialized BACK
	CreateAtoms(atoms, atoms_to_return, source)
	clear_tracked_initalize(source)
	if(smoothing_owner)
		flush_wall_smoothing()
	if(cable_owner)
		flush_cable_binds()
	if(machine_owner)
		flush_machine_binds()
	// Decl binds run inside the heat bind scope, so bodies they create batch too.
	if(decl_bind_owner)
		flush_decl_binds()
	dq_heat_bind_end()

	if(length(late_loaders))
		for(var/I in 1 to length(late_loaders))
			var/atom/A = late_loaders[I]
			//I hate that we need this
			if(QDELETED(A))
				continue
			#ifdef BENCHMARK_DEEP_PROFILE
			var/bench_depth = benchmark_init_frame_begin()
			#endif
			A.LateInitialize()
			#ifdef BENCHMARK_DEEP_PROFILE
			benchmark_late_frame_end(bench_depth, A.type)
			#endif
		testing("Late initialized [length(late_loaders)] atoms")
		late_loaders.Cut()

	if (created_atoms)
		atoms_to_return += created_atoms
		created_atoms = null

	for (var/queued_deletion in queued_deletions)
		var/atom/resolved = om_resolve(queued_deletion)
		if(resolved)
			qdel(resolved)

	testing("[length(queued_deletions)] atoms were queued for deletion.")
	queued_deletions.Cut()

	#ifdef PROFILE_MAPLOAD_INIT_ATOM
	rustg_file_write(json_encode(mapload_init_times), "[GLOB.log_directory]/init_times.json")
	#endif

/// Smooths every wall the batch queued, plus the walls next to them (a template's edge
/// touches walls that were already there), once each, now that every material is set.
/datum/controller/subsystem/atoms/proc/flush_wall_smoothing()
	var/list/queued = deferred_wall_smoothing
	deferred_wall_smoothing = null
	if(!length(queued))
		return
	var/list/walls = queued.Copy()
	for(var/turf/simulated/wall/W as anything in queued)
		for(var/turf/simulated/wall/neighbour in orange(W, 1))
			walls[neighbour] = TRUE
	for(var/turf/simulated/wall/W as anything in walls)
		if(QDELETED(W) || !istype(W))
			continue
		W.update_connections()
		W.update_icon()

/// Binds every cable the batch queued in one Rust call.
/datum/controller/subsystem/atoms/proc/flush_cable_binds()
	var/list/queued = deferred_cable_binds
	deferred_cable_binds = null
	if(length(queued))
		power_bind_cables(queued)

/// Binds every power machine node the batch queued in one Rust call (after the cables, so the
/// machines join the batch's knots).
/datum/controller/subsystem/atoms/proc/flush_machine_binds()
	var/list/queued = deferred_machine_binds
	deferred_machine_binds = null
	if(length(queued))
		power_bind_machines(queued)

/// Actually creates the list of atoms. Exists solely so a runtime in the creation logic doesn't cause initialized to totally break
/datum/controller/subsystem/atoms/proc/CreateAtoms(list/atoms, list/atoms_to_return = null, mapload_source = null)
	if (atoms_to_return)
		LAZYINITLIST(created_atoms)

	#ifdef TESTING
	var/count
	#endif

	var/list/mapload_arg = list(TRUE)

	if(atoms)
		#ifdef TESTING
		count = length(atoms)
		#endif

		for(var/I in 1 to length(atoms))
			var/atom/A = atoms[I]
			if(!(A.flags & ATOM_INITIALIZED))
				#ifndef UNIT_TESTS
				// Unrolled CHECK_TICK setup to let us enable/disable mapload based off source.
				// Skipped in unit-test builds: there are no clients to keep the tick
				// smooth for, and under a loaded MC this per-atom stoplag() turns a
				// 65k-turf template load (expedition z-alloc) into ~35 minutes of
				// sleeps — the InitAtom work itself is seconds.
				if(length(GLOB.clients) && TICK_CHECK)
					clear_tracked_initalize(mapload_source)
					stoplag() // ALLOW(scheduler): runtime template loads yield between atoms (lane-work conversion pending)
					if(mapload_source)
						set_tracked_initalized(INITIALIZATION_INNEW_MAPLOAD, mapload_source)
				#endif
				PROFILE_INIT_ATOM_BEGIN()
				InitAtom(A, TRUE, mapload_arg)
				PROFILE_INIT_ATOM_END(A)
	else
		#ifdef TESTING
		count = 0
		#endif

		for(var/atom/A as anything in world)
			if(!(A.flags & ATOM_INITIALIZED))
				PROFILE_INIT_ATOM_BEGIN()
				InitAtom(A, FALSE, mapload_arg)
				PROFILE_INIT_ATOM_END(A)
				#ifdef TESTING
				++count
				#endif
				if(length(GLOB.clients) && TICK_CHECK)
					clear_tracked_initalize(mapload_source)
					stoplag() // ALLOW(scheduler): runtime template loads yield between atoms (lane-work conversion pending)
					if(mapload_source)
						set_tracked_initalized(INITIALIZATION_INNEW_MAPLOAD, mapload_source)

	#ifdef TESTING
	testing("Initialized [count] atoms")
	#endif

/datum/controller/subsystem/atoms/proc/map_loader_begin(source)
	set_tracked_initalized(INITIALIZATION_INSSATOMS, source)

/datum/controller/subsystem/atoms/proc/map_loader_stop(source)
	clear_tracked_initalize(source)

/// Returns the source currently modifying SSatom's init behavior
/datum/controller/subsystem/atoms/proc/get_initialized_source()
	var/state_length = length(initialized_state)
	if(!state_length)
		return null
	return initialized_state[state_length][1]

/// Use this to set initialized to prevent error states where the old initialized is overridden, and we end up losing all context
/// Accepts a state and a source, the most recent state is used, sources exist to prevent overriding old values accidentally
/datum/controller/subsystem/atoms/proc/set_tracked_initalized(state, source)
	if(!length(initialized_state))
		base_initialized = atom_initialized
	initialized_state += list(list(source, state))
	atom_initialized = state

/datum/controller/subsystem/atoms/proc/clear_tracked_initalize(source)
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
/datum/controller/subsystem/atoms/proc/initializing_something()
	return length(initialized_state) > 1

/datum/controller/subsystem/atoms/Recover()
	atom_initialized = SSatoms.atom_initialized
	if(atom_initialized == INITIALIZATION_INNEW_MAPLOAD)
		InitializeAtoms()
	initialized_state = SSatoms.initialized_state
	BadInitializeCalls = SSatoms.BadInitializeCalls

/datum/controller/subsystem/atoms/proc/InitLog()
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
/datum/controller/subsystem/atoms/proc/prepare_deletion(atom/target)
	if (atom_initialized == INITIALIZATION_INNEW_REGULAR)
		// Atoms SS has already completed, just kill it now.
		qdel(target)
	else
		queued_deletions += om_handle(target)

/datum/controller/subsystem/atoms/Shutdown()
	var/initlog = InitLog()
	if(initlog)
		text2file(initlog, "[GLOB.log_directory]-initialize.log")
