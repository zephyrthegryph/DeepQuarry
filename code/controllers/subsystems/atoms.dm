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
	/// Late loaders from a mapload Initialize() that ran outside any batch frame; the next
	/// frame to close runs them. Frames keep their own (atoms_batch.dm).
	var/list/late_loaders = list()

	var/list/BadInitializeCalls = list()

	///InitAtom() adds the movables it creates from a template here while the running
	///InitializeAtoms() call was given a list to populate. Saved and restored per call.
	var/list/created_atoms

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

	// One frame per call (atoms_batch.dm): it owns the deferred work unless it joined a
	// running frame, and yields only between chunks.
	var/datum/materialize_batch/batch = batch_open(source)
	var/list/outer_created = created_atoms
	created_atoms = atoms_to_return ? list() : null
	batch.created_atoms = created_atoms
	// This may look a bit odd, but if the actual atom creation runtimes for some reason, we absolutely need to set initialized BACK
	CreateAtoms(batch, atoms)
	clear_tracked_initalize(source)
	var/list/created = batch.created_atoms
	created_atoms = outer_created
	batch_close(batch)

	var/list/loaders = batch.late_loaders
	if(length(late_loaders))
		loaders += late_loaders
		late_loaders.Cut()
	if(length(loaders))
		for(var/I in 1 to length(loaders))
			var/atom/A = loaders[I]
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
		testing("Late initialized [length(loaders)] atoms")

	if(created)
		atoms_to_return += created

	for (var/queued_deletion in queued_deletions)
		var/atom/resolved = om_resolve(queued_deletion)
		if(resolved)
			qdel(resolved)

	testing("[length(queued_deletions)] atoms were queued for deletion.")
	queued_deletions.Cut()
	if(!batch_trace)
		qdel(batch)

	#ifdef PROFILE_MAPLOAD_INIT_ATOM
	rustg_file_write(json_encode(mapload_init_times), "[GLOB.log_directory]/init_times.json")
	#endif

/// Initializes the frame's atoms (or every uninitialized atom in the world) chunk by chunk.
/// Exists solely so a runtime in the creation logic doesn't cause initialized to totally break.
/datum/controller/subsystem/atoms/proc/CreateAtoms(datum/materialize_batch/batch, list/atoms)
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
