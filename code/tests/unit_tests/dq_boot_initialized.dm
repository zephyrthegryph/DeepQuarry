// The map pass of boot initializes every atom the map made. A movable left without ATOM_INITIALIZED means the pass stopped early (a landmark that
// rolled itself without end once threw "Maximum recursion level reached" out of it, silently, and the engine room and every later z-level stayed raw).
// Meaningful with --full-map: it is the map and its template loads that are checked.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_boot_leaves_no_movable_uninitialized
	boot_needs = list()

/datum/unit_test/dq_boot_leaves_no_movable_uninitialized/Run()
	var/list/by_type = list()
	var/left = 0
	for(var/atom/movable/M in world)
		if(!M.loc)
			continue // a resolved map atom is detached on purpose (map_resolve_instance()): never live, never initialized
		if(!(M.flags & ATOM_INITIALIZED))
			left++
			by_type["[M.type] in [M.loc?.type] at [M.loc?.x],[M.loc?.y],[M.loc?.z]"]++
	if(left)
		var/list/sample = list()
		for(var/type in by_type)
			sample += "[type] x[by_type[type]]"
			if(length(sample) >= 12)
				break
		TEST_FAIL("[left] movable(s) were never initialized, by type: [jointext(sample, ", ")]")

#endif
