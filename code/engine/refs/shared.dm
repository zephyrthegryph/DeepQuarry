// Shared (doc/rewrite/ownership.md §2): immortal registry singletons and DEFs.
//
// REGISTRY_TYPE(path, getter) replaces the fiat OM_STATIC_TYPE list: membership is proven at
// runtime by the getter, which returns the registered instance D stands for. The registry
// declarations themselves live next to each registry (grep REGISTRY_TYPE); the ones for types
// with no better home are in registry_types.dm.

/// REGISTRY_TYPE(PATH, GETTER): the getter proc path for this type's registry, or null.
/datum/proc/registry_getter()
	return null

/// TRUE when `D`'s type is a registry type (its instances may be registered singletons).
/proc/registry_type(datum/D)
	return isdatum(D) && !isnull(D.registry_getter())

/// TRUE when `D` is the registered instance of its registry: shared, immortal, never tracked.
/proc/is_registered(datum/D)
	if(!isdatum(D))
		return FALSE
	var/getter = D.registry_getter()
	if(isnull(getter))
		return FALSE
	return call(getter)(D) == D

/// Points holder.var_name at a registered instance (or null). Asserts registration.
/proc/shared_set(datum/holder, var_name, datum/value)
	if(!isnull(value) && !own_guard(holder, value, "shared_set([var_name])")) // the one teardown guard (guard.dm)
		return null
	if(!isnull(value) && !is_registered(value))
		OWN_REPORT("[holder.type].[var_name] is SHARED but [value.type] is not a registered instance (own it, or make the var PROTO)")
	holder.vars[var_name] = value // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
	own_field_changed(holder, var_name)
	return value

// ---------------------------------------------------------------- DEF freeze (test builds)

#ifdef UNIT_TESTS
/// "type ref" -> hash of the instance's vars at boot.
GLOBAL_LIST_EMPTY(def_freeze_snapshot)
#endif

/// D's vars as name -> stable text digest (lists by content, datums by type and ref).
/proc/def_freeze_digest(datum/D)
	. = list()
	for(var/name in D.vars)
		if(name in list("vars", "gc_destroyed", "om_rec", "om_listen", "om_hid", "om_refs_in", "datum_flags", "tag", "own_holder_ref", "own_slot", "own_key_text", "cached_ref"))
			continue
		var/value = D.vars[name]
		if(!issaved(value) && !islist(value))
			continue
		.[name] = md5(def_freeze_value(value, 2))

/proc/def_freeze_value(value, depth)
	if(islist(value))
		if(depth <= 0)
			return "list([length(value)])"
		var/list/L = value
		var/list/out = list()
		for(var/key in L)
			out += isnum(key) ? def_freeze_value(key, depth - 1) : "[def_freeze_value(key, depth - 1)]:[def_freeze_value(L[key], depth - 1)]"
		return "([jointext(out, ",")])"
	if(isdatum(value))
		var/datum/V = value
		return "[V.type]@[ref(V)]"
	return "[value]"

/// Every registered instance of every enumerable registry (GLOB.registry_enum_procs,
/// registry_types.dm).
/proc/def_freeze_instances()
	. = list()
	for(var/enum_proc in GLOB.registry_enum_procs)
		var/list/instances = call(enum_proc)()
		for(var/key in instances)
			var/datum/D = isdatum(key) ? key : instances[key]
			if(isdatum(D))
				. |= D

/// Boot (test builds): digest every registered instance.
/proc/def_freeze_snapshot()
	#ifdef UNIT_TESTS
	GLOB.def_freeze_snapshot = list()
	for(var/datum/D as anything in def_freeze_instances())
		GLOB.def_freeze_snapshot["[D.type] [ref(D)]"] = def_freeze_digest(D)
	#endif

/// Test end: every registered instance whose vars changed since boot, as report lines.
/proc/def_freeze_verify()
	. = list()
	#ifdef UNIT_TESTS
	for(var/datum/D as anything in def_freeze_instances())
		var/key = "[D.type] [ref(D)]"
		var/list/old = GLOB.def_freeze_snapshot[key]
		if(!islist(old))
			continue
		var/list/now = def_freeze_digest(D)
		var/list/changed = list()
		for(var/name in now)
			if(old[name] != now[name])
				changed += name
		if(length(changed))
			. += "DEF FROZEN: [D.type] ([ref(D)]) was written after boot: [jointext(changed, ", ")]"
	#endif
