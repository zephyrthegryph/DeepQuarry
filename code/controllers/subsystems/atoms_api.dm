/datum/system/atoms/proc/initialization_mode()
	return atom_initialized

/datum/system/atoms/proc/system_initialization_state()
	return initialized

/// INITIALIZE_IMMEDIATE restores the exact inherited initialized value afterwards.
/datum/system/atoms/proc/begin_immediate_initialization()
	. = initialized
	initialized = INITIALIZATION_INNEW_MAPLOAD

/datum/system/atoms/proc/end_immediate_initialization(previous)
	initialized = previous

/datum/system/atoms/proc/begin_materialize_suppression()
	materialize_suppressed++

/datum/system/atoms/proc/end_materialize_suppression()
	materialize_suppressed--

/datum/system/atoms/proc/map_load_is_active()
	return initialize_depth || atom_initialized != INITIALIZATION_INNEW_REGULAR

/datum/system/atoms/proc/defer_map_resolver(proc_path, atom/loc, path, list/varedits)
	if(atom_initialized == INITIALIZATION_INNEW_REGULAR && !initialize_depth)
		call(proc_path)(loc, path, varedits)
		return
	LAZYADD(deferred_resolvers, list(list(proc_path, entity_handle(loc), path, varedits)))

/// Hand over the complete pending batch before running callbacks; nested work is a new batch.
/datum/system/atoms/proc/take_resolver_batch()
	. = deferred_resolvers
	deferred_resolvers = null

/datum/system/atoms/proc/bind_declarations(atom/A, datum/lifecycle_decls/decls)
	var/list/deferred = deferred_decl_binds
	for(var/path in decls.binders)
		if(deferred)
			var/list/queue = deferred[path]
			if(!queue)
				queue = deferred[path] = list()
			queue[A] = TRUE
		else
			decl_binder(path).bind_list(list(A))

/datum/system/atoms/proc/unbind_declarations(datum/D, datum/lifecycle_decls/decls)
	var/list/deferred = deferred_decl_binds
	for(var/path in decls.binders)
		if(deferred)
			var/list/queue = deferred[path]
			queue?.Remove(D)
		decl_binder(path).unbind(D)
