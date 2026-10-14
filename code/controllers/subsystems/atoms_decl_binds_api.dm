// atoms system operations moved from code/datums/lifecycle/declarations.dm.

/// Binds everything a batch queued, one bind_list() per binder.
/datum/system/atoms/proc/flush_decl_binds()
	var/list/queued = deferred_decl_binds
	deferred_decl_binds = null
	for(var/path in queued)
		var/list/atoms = queued[path]
		if(length(atoms))
			decl_binder(path).bind_list(atoms)
