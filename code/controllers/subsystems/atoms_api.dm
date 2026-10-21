// The atoms system's API (code/controllers/subsystems/atoms.dm declares the system).
//
//   SSatoms.suppress_materialize() / resume_materialize()    new_unmaterialized() nests these around a creation
//   SSatoms.set_atom_initialized(state)                       INITIALIZATION_* state new atoms read in New()
//   SSatoms.defer_resolver(row) / take_deferred_resolvers()   map resolvers that wait for the load's atoms
//   atoms_*()                                                 reads (code/contracts/accessors/accessors.dm)

/datum/system/atoms/proc/suppress_materialize()
	materialize_suppressed++

/datum/system/atoms/proc/resume_materialize()
	materialize_suppressed--

/// Sets the state atoms are created in; returns the previous one.
/datum/system/atoms/proc/set_atom_initialized(state)
	. = atom_initialized
	atom_initialized = state

/// Queues one map-resolver row (proc path, location token, path, varedits).
/datum/system/atoms/proc/defer_resolver(list/row)
	LAZYADD(deferred_resolvers, list(row))

/// Hands over the queued map-resolver rows and clears the queue.
/datum/system/atoms/proc/take_deferred_resolvers()
	. = deferred_resolvers
	deferred_resolvers = null

/// Whether any deferred resolver rows are waiting.
/datum/system/atoms/proc/has_deferred_resolvers()
	return length(deferred_resolvers) > 0

/// Sets the system's initialization state (INITIALIZATION_*; INITIALIZE_IMMEDIATE types borrow INNEW_MAPLOAD while they initialize).
/datum/system/atoms/proc/change_initialized(state)
	initialized = state

/// The system's initialization state (INITIALIZATION_*; TRUE/FALSE-like until it has run).
/datum/system/atoms/proc/is_initialized()
	return initialized
